//
//  AppLaunchCoordinator.swift
//  NovelSpeaker
//
//  Created by Codex on 2026/03/21.
//

import UIKit
import FTLinearActivityIndicator

@objcMembers
final class AppLaunchCoordinator: NSObject {
    @objc(runPreflight)
    static func runPreflight() -> Bool {
        guard NovelSpeakerUtility.CheckRealmReadable() else {
            fatalError("Realm is not readable at launch")
        }

        if !NiftyUtility.isTesting() {
            NovelSpeakerUtility.StartAllLongLivedOperationIDWatcher()
        }
        NovelSpeakerUtility.PreloadPrivacyTrackingBlockRuleListIfNeeded()
        return true
    }

    @objc(createInitialRootViewController)
    static func createInitialRootViewController() -> UIViewController {
        let context = AppLaunchContextBuilder.build()
        return AppRootViewControllerFactory.create(context: context)
    }

    @objc(runPostLaunchWithRootViewController:)
    static func runPostLaunch(rootViewController: UIViewController) {
        NiftyUtility.RegisterToplevelViewController(viewController: rootViewController)
        NovelSpeakerUtility.RemoveInvalidKeyDataFromCookieStorage(storage: HTTPCookieStorage.shared)
        UIApplication.configureLinearNetworkActivityIndicatorIfNeeded()
        configurePreferredFontsForTextStyle()
        NovelDownloadQueue.shared.RegisterBackgroundProcess()
        NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
        NovelDownloadQueue.shared.ClearDownloadCountBadge()
        NiftyUtility.StartiCloudDataVersionChecker()
        NovelSpeakerUtility.CleanBackupFolder()
        ImportFromWebPageViewController.ClearDownloadTemporaryDirectory()
        NovelSpeakerUtility.SetInitialAvailableMemory()
        NovelSpeakerUtility.StartPrivacyTrackingBlockRuleListRefreshTimerIfNeeded()
    }

    #if targetEnvironment(macCatalyst)
    // 着手順4(改): Catalyst をコマンドラインから「検査だけして終了」させるワンショットモード。
    // 常駐(Timer/スケジューラ)させず、launchd 等が定期起動 → 検査 → stdout にレポート → exit、という運用を想定。
    // 起動引数 `--scrape-inspect`、または環境変数 NOVELSPEAKER_SCRAPE_INSPECT=1 で有効。
    // stdout には他のログも混ざるため、レポートは BEGIN/END マーカーで囲んで FileHandle で直接書き出す。
    // 終了コード: NG または ERROR が1件でもあれば 1、それ以外(OK/WARN/SKIP/ROBOTSのみ)は 0。
    private static var cliInspector: ScrapeInspector?
    // URL検査モードで完了まで StoryFetcher を保持する(headless httpClient ごと生かす)。
    private static var cliFetcher: StoryFetcher?
    // DOMダンプモードで完了まで headless クライアントを保持する。
    private static var cliHeadlessClient: HeadlessHttpClient?

    @discardableResult
    static func runScrapeInspectionCLIIfRequested() -> Bool {
        let args = CommandLine.arguments
        let env = ProcessInfo.processInfo.environment

        // モードA(checkTargets 量産用): 任意URLを本番SiteInfoで1ページ取得し、取れた項目を JSON 行で出す。
        //   NovelSpeaker --scrape-inspect-url <URL> [<URL> ...]
        //   または 環境変数 NOVELSPEAKER_SCRAPE_INSPECT_URL に空白/改行区切りでURL列。
        // 1URLにつき1行 `NOVELSPEAKER_SCRAPE_INSPECT_URL_LINE {json}` を逐次出力(途中で落ちても結果が残る)。
        // 最後に `NOVELSPEAKER_SCRAPE_INSPECT_URL_DONE` を出して exit(0)。
        if let flagIndex = args.firstIndex(of: "--scrape-inspect-url") {
            let urlStrings = Array(args[(flagIndex + 1)...]).filter { !$0.hasPrefix("-") }
            runScrapeInspectURL(urlStrings: urlStrings)
            return true
        }
        if let urlEnv = env["NOVELSPEAKER_SCRAPE_INSPECT_URL"], urlEnv.contains(where: { !$0.isWhitespace }) {
            let urlStrings = urlEnv.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            runScrapeInspectURL(urlStrings: urlStrings)
            return true
        }

        // モードC(選択子オーサリング用): URLを強制headlessで描画し、描画後(ハイドレート済み)DOMを出力する。
        //   NovelSpeaker --dump-rendered-html <URL> [--wait <秒>] [--ua <UserAgent>]
        //   SiteInfo には依存しない(matchするしないに関わらず必ず headless で取得)。
        //   出力: `NOVELSPEAKER_DUMP_HTML_BEGIN <url>` の次行から outerHTML、末尾に `NOVELSPEAKER_DUMP_HTML_END`。
        if let flagIndex = args.firstIndex(of: "--dump-rendered-html") {
            let positional = Array(args[(flagIndex + 1)...]).first(where: { !$0.hasPrefix("-") })
            var waitSec: Double = 6
            if let wi = args.firstIndex(of: "--wait"), wi + 1 < args.count, let w = Double(args[wi + 1]) { waitSec = w }
            var userAgent: String? = env["NOVELSPEAKER_DUMP_UA"]
            if let ui = args.firstIndex(of: "--ua"), ui + 1 < args.count { userAgent = args[ui + 1] }
            runDumpRenderedHTML(urlString: positional, waitSec: waitSec, userAgent: userAgent)
            return true
        }

        // モードD(キャッシュ整理): SiteInfo のキャッシュ(ファイルキャッシュ + URLCacheのHTTP応答)を
        //   アプリ内の正規ルート(StoryHtmlDecoder.ClearSiteInfo)でクリアする。シェルから cache ファイルを直接
        //   rm すると URLCache が中途半端になりがちなので、こちらで安全に消す。
        //   NovelSpeaker --clear-siteinfo-cache
        if args.contains("--clear-siteinfo-cache") {
            runClearSiteInfoCache()
            return true
        }

        // モードB(既存): 登録済み checkTargets を全件検査。
        guard args.contains("--scrape-inspect") || env["NOVELSPEAKER_SCRAPE_INSPECT"] == "1" else {
            return false
        }

        // 検査は「いま本番(公開シート)に入っている checkTargets」を対象にしたい。
        // 通常の SiteInfo ロードは 24h のファイルキャッシュを使うため、CLI 起動時に古いキャッシュが
        // あると検査対象が陳腐化する(例: シート反映直後でもキャッシュ時代の数件しか見ない)。
        // ここでキャッシュ期限を 0 にして、検査前に必ず最新の SiteInfo を取り直させる。
        StoryHtmlDecoder.shared.cacheFileExpireTimeinterval = 0

        let inspector = ScrapeInspector()
        // InspectAll は内部で [weak self] を使うため、完了まで外側で保持する。
        cliInspector = inspector
        inspector.InspectAll { results in
            let report = ScrapeInspector.report(results: results)
            let hasProblem = results.contains { $0.status == .ng || $0.status == .error }
            let body = "<<<NOVELSPEAKER_SCRAPE_INSPECT_BEGIN>>>\n"
                + report
                + "\n<<<NOVELSPEAKER_SCRAPE_INSPECT_END exit=\(hasProblem ? 1 : 0)>>>\n"
            FileHandle.standardOutput.write(Data(body.utf8))
            exit(hasProblem ? 1 : 0)
        }
        return true
    }

    // --clear-siteinfo-cache の本体。アプリ内の正規ルート(StoryHtmlDecoder.ClearSiteInfo)で
    // SiteInfo のファイルキャッシュと URLCache のHTTP応答キャッシュをまとめてクリアする。
    // 削除は内部で非同期(GetNovelSpeakerRemoteConfig コールバック)に行われるので、少し待ってから exit する。
    private static func runClearSiteInfoCache() {
        StoryHtmlDecoder.shared.ClearSiteInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            FileHandle.standardOutput.write(Data("NOVELSPEAKER_SITEINFO_CACHE_CLEARED\n".utf8))
            exit(0)
        }
    }

    // --scrape-inspect-url の本体。SiteInfo をロードしてから URL を逐次取得し、結果を JSON 行で出力する。
    private static func runScrapeInspectURL(urlStrings: [String]) {
        let fetcher = StoryFetcher()
        cliFetcher = fetcher
        let decoder = StoryHtmlDecoder.shared
        decoder.WaitLoadSiteInfoReady { _ in
            DispatchQueue.main.async {
                processInspectURL(urlStrings: urlStrings, index: 0, fetcher: fetcher, decoder: decoder)
            }
        }
    }

    private static func processInspectURL(urlStrings: [String], index: Int, fetcher: StoryFetcher, decoder: StoryHtmlDecoder) {
        if index >= urlStrings.count {
            FileHandle.standardOutput.write(Data("NOVELSPEAKER_SCRAPE_INSPECT_URL_DONE\n".utf8))
            exit(0)
        }
        let urlString = urlStrings[index]
        var finished = false
        func done(_ dict: [String: Any]) {
            DispatchQueue.main.async {
                if finished { return }
                finished = true
                emitInspectURLLine(dict)
                // 連続アクセスはサイトに優しく一定間隔を空ける。
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    processInspectURL(urlStrings: urlStrings, index: index + 1, fetcher: fetcher, decoder: decoder)
                }
            }
        }
        guard let url = URL(string: urlString) else {
            done(["url": urlString, "ok": false, "error": "invalid URL"])
            return
        }
        // success/failed のどちらも来ない場合に詰まらないようウォッチドッグ。
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            done(buildInspectURLDict(urlString: urlString, state: nil, fetcher: fetcher, decoder: decoder, error: "timeout"))
        }
        fetcher.InspectFetchSinglePage(url: url, cookieString: "", successAction: { state in
            done(buildInspectURLDict(urlString: urlString, state: state, fetcher: fetcher, decoder: decoder, error: nil))
        }, failedAction: { _, message in
            done(buildInspectURLDict(urlString: urlString, state: nil, fetcher: fetcher, decoder: decoder, error: message))
        })
    }

    // 1URL分の取得結果を JSON 化可能な辞書にまとめる。
    private static func buildInspectURLDict(urlString: String, state: StoryState?, fetcher: StoryFetcher, decoder: StoryHtmlDecoder, error: String?) -> [String: Any] {
        var dict: [String: Any] = ["url": urlString]
        if let finalURL = fetcher.httpClient.GetCurrentURL()?.absoluteString {
            dict["finalUrl"] = finalURL
        }
        // このURLにマッチする SiteInfo(fallback の //body 以外を優先)を1件、参考情報として添える。
        let matched = decoder.SearchSiteInfoArrayFrom(urlString: urlString)
        if let first = matched.first(where: { ($0.name?.isEmpty == false) }) ?? matched.first {
            var si: [String: Any] = ["isNeedHeadless": first.isNeedHeadless]
            if let n = first.name { si["name"] = n }
            if let p = first.url?.pattern { si["urlPattern"] = p }
            dict["matchedSiteInfo"] = si
        }
        guard let state = state else {
            dict["ok"] = false
            dict["error"] = error ?? "unknown error"
            return dict
        }
        dict["ok"] = true
        dict["present"] = [
            "content": (state.content?.isEmpty == false),
            "title": (state.title?.isEmpty == false),
            "author": (state.author?.isEmpty == false),
            "subtitle": (state.subtitle?.isEmpty == false),
            "tag": !state.tagArray.isEmpty,
            "firstPageLink": (state.firstPageLink != nil),
            "nextLink": (state.nextUrl != nil),
            "nextButton": (state.nextButton != nil),
            "firstPageButton": (state.firstPageButton != nil),
        ]
        var values: [String: Any] = [:]
        if let t = state.title, !t.isEmpty { values["title"] = t }
        if let a = state.author, !a.isEmpty { values["author"] = a }
        if let s = state.subtitle, !s.isEmpty { values["subtitle"] = s }
        if !state.tagArray.isEmpty { values["tag"] = state.tagArray }
        if let f = state.firstPageLink?.absoluteString { values["firstPageLink"] = f }
        if let n = state.nextUrl?.absoluteString { values["nextUrl"] = n }
        if let c = state.content {
            values["contentLength"] = c.count
            values["contentHead"] = String(c.prefix(120))
        }
        dict["values"] = values
        return dict
    }

    private static func emitInspectURLLine(_ dict: [String: Any]) {
        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            json = str
        } else {
            json = "{\"url\":\"?\",\"ok\":false,\"error\":\"json serialize failed\"}"
        }
        FileHandle.standardOutput.write(Data(("NOVELSPEAKER_SCRAPE_INSPECT_URL_LINE " + json + "\n").utf8))
    }

    // --dump-rendered-html の本体。SiteInfo に依存せず、URL を強制 headless で描画して outerHTML を出力する。
    // 選択子(pageElementV2)を作るために「ハイドレート済みDOM」を確認する用途。JS描画を待つため waitSec 秒待ってから取得する。
    private static func runDumpRenderedHTML(urlString: String?, waitSec: Double, userAgent: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            FileHandle.standardOutput.write(Data("NOVELSPEAKER_DUMP_HTML_ERROR invalid URL\n".utf8))
            exit(1)
        }
        let client = HeadlessHttpClient()
        cliHeadlessClient = client
        if let userAgent = userAgent, !userAgent.isEmpty {
            client.overrideUserAgent(userAgentString: userAgent)
        }
        var finished = false
        func emit(html: String?, error: String?) {
            DispatchQueue.main.async {
                if finished { return }
                finished = true
                if let html = html {
                    let body = "NOVELSPEAKER_DUMP_HTML_BEGIN \(urlString)\n" + html + "\nNOVELSPEAKER_DUMP_HTML_END\n"
                    FileHandle.standardOutput.write(Data(body.utf8))
                    exit(0)
                } else {
                    FileHandle.standardOutput.write(Data("NOVELSPEAKER_DUMP_HTML_ERROR \(error ?? "unknown")\n".utf8))
                    exit(1)
                }
            }
        }
        // success/error のどちらも来ない場合に詰まらないようウォッチドッグ(描画待ち + 余裕)。
        DispatchQueue.main.asyncAfter(deadline: .now() + waitSec + 90) {
            emit(html: nil, error: "timeout")
        }
        client.HttpRequest(url: url, cookieString: "", successResultHandler: { _ in
            // ページロード完了後、JSのハイドレーション/後読みを待ってから DOM を取り出す。
            // Erik の evaluate ラッパーは巨大文字列の取り出しに失敗するため WKWebView へ直接評価する。
            DispatchQueue.main.asyncAfter(deadline: .now() + waitSec) {
                client.webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                    if let html = result as? String {
                        emit(html: html, error: nil)
                    } else {
                        emit(html: nil, error: error?.localizedDescription ?? "outerHTML did not return a string")
                    }
                }
            }
        }, errorResultHandler: { error in
            emit(html: nil, error: error.localizedDescription)
        })
    }
    #endif

    private static func configurePreferredFontsForTextStyle() {
        UINavigationBar.appearance().titleTextAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .headline),
        ]
        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .body)],
            for: .normal
        )
        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .body)],
            for: .highlighted
        )
        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .body)],
            for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .body)],
            for: .normal
        )
    }
}

private struct AppLaunchContext {
    let shouldOpenSafeMode: Bool
    let requiresMigration: Bool
}

private enum LaunchStoryboard: String {
    case main = "Main"
    case coreDataMigration = "coreDataMigration"
    case safeMode = "safeMode"
}

private enum AppLaunchContextBuilder {
    static func build() -> AppLaunchContext {
        let isICloudValid = validateICloudStatus()
        normalizeRealmStorage()

        let globalData = GlobalDataSingleton.getInstance()
        let shouldOpenSafeMode = NovelSpeakerUtility.CheckRestartFrequency(tickTime: 30, count: 3)
        let requiresMigration = (globalData?.isRequiredCoreDataMigration() ?? false)
            || CoreDataToRealmTool.IsNeedMigration()
            || !isICloudValid

        return AppLaunchContext(
            shouldOpenSafeMode: shouldOpenSafeMode,
            requiresMigration: requiresMigration
        )
    }

    private static func validateICloudStatus() -> Bool {
        guard RealmUtil.IsUseCloudRealm() else { return true }

        var isICloudValid = true
        let semaphore = DispatchSemaphore(value: 0)
        RealmUtil.CheckCloudAccountStatus { result, _ in
            isICloudValid = result
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
        return isICloudValid
    }

    private static func normalizeRealmStorage() {
        if RealmUtil.IsUseCloudRealm() {
            if RealmUtil.CheckIsCloudRealmCreated() {
                RealmUtil.RemoveLocalRealmFile()
            }
            return
        }

        if RealmUtil.CheckIsLocalRealmCreated() {
            RealmUtil.RemoveCloudRealmFile()
        }
    }
}

private enum AppRootViewControllerFactory {
    static func create(context: AppLaunchContext) -> UIViewController {
        let storyboard: LaunchStoryboard
        if context.shouldOpenSafeMode {
            storyboard = .safeMode
        } else if context.requiresMigration {
            storyboard = .coreDataMigration
        } else {
            NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
            NovelSpeakerUtility.ForceOverrideHungSpeakStringToSpeechModSettings()
            NovelSpeakerUtility.NormalizeExistingNovelTitlesAndWritersToNFCIfNeeded()
            storyboard = .main
        }

        return UIStoryboard(name: storyboard.rawValue, bundle: nil).instantiateInitialViewController()!
    }
}
