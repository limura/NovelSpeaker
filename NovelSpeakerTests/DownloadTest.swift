//
//  File.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2021/01/16.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker
@testable import Kanna

// NOTE: かつてここに pixiv の実URLへアクセスしてスクレイプ結果を照合する統合テスト
// (testPixiv_FirstPageLink / testPixiv_nextLink_for_LastSeries) があったが、
// 第三者サイトの生挙動(ログイン壁・HTML変更・ネットワーク有無)に依存し単体テストとして成立しないため削除した。
// 「現在の SiteInfo で各サイトを正しくスクレイプできるか」は別の(日次の)監視の仕組みで担保する想定。

class DownloadTest: XCTestCase {

    func testNovelDownloadThrottlePolicyNominalKeepsConfiguredSpeed() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: true, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .nominal, isLowPowerModeEnabled: false, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 5)
        XCTAssertEqual(parameters.queueDelayTime, 1.05, accuracy: 0.001)
    }

    func testNovelDownloadThrottlePolicySeriousThrottlesAggressively() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: true, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .serious, isLowPowerModeEnabled: false, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 1)
        XCTAssertEqual(parameters.queueDelayTime, 2.10, accuracy: 0.001)
    }

    func testNovelDownloadThrottlePolicyLowPowerModeReducesParallelism() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: true, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .nominal, isLowPowerModeEnabled: true, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 4)
        XCTAssertEqual(parameters.queueDelayTime, 1.40, accuracy: 0.001)
    }

    func testNovelDownloadThrottlePolicyCanBeDisabled() throws {
        let settings = NovelDownloadThrottleSettings(isDynamicThrottleEnabled: false, baseMaxSimultaneousDownloadCount: 5, minimumQueueDelayTime: 1.05)
        let parameters = NovelDownloadThrottlePolicy.parameters(thermalState: .critical, isLowPowerModeEnabled: true, settings: settings)

        XCTAssertEqual(parameters.maxSimultaneousDownloadCount, 5)
        XCTAssertEqual(parameters.queueDelayTime, 1.05, accuracy: 0.001)
    }

    // MARK: - スクレイプ検査(checkTargets)の手動確認(一時/Catalyst専用)
    // InspectFetchSinglePage(単ページモード)の挙動を実URLで目視確認するための一時テスト。
    // 実ネットワーク+headless WebView を使う統合テストなので Catalyst(住宅IP)でのみ動かす。
    // 確認が済んだら削除する想定。設計メモ: DESIGN_スクレイプ検査.md
    #if targetEnvironment(macCatalyst)
    func testManual_InspectFetchSinglePage_RealSites() throws {
        // SiteInfo を強制的に再取得する(24h キャッシュに古いシートが残っていると新しい forceError が反映されないため)。
        StoryHtmlDecoder.shared.cacheFileExpireTimeinterval = 0
        let urls = [
            "https://www.pixiv.net/novel/show.php?id=28239994",
        ]
        let fetcher = StoryFetcher()
        let finished = expectation(description: "inspect all urls")

        func summarize(_ state: StoryState) -> String {
            let contentHead = (state.content?.prefix(120)).map { String($0).replacingOccurrences(of: "\n", with: "⏎") } ?? "nil"
            return """
              content(\(state.content?.count ?? -1)): \(contentHead)
              title: \(state.title ?? "nil")
              author: \(state.author ?? "nil")
              subtitle: \(state.subtitle ?? "nil")
              tagArray: \(state.tagArray.joined(separator: ", "))
              firstPageLink: \(state.firstPageLink?.absoluteString ?? "nil")
              nextUrl(nextLink): \(state.nextUrl?.absoluteString ?? "nil")
              nextButton: \(state.nextButton == nil ? "nil" : "有")
              firstPageButton: \(state.firstPageButton == nil ? "nil" : "有")
              isNeedHeadless: \(state.isNeedHeadless)
            """
        }

        func inspect(_ index: Int) {
            if index >= urls.count { finished.fulfill(); return }
            let urlString = urls[index]
            guard let url = URL(string: urlString) else { inspect(index + 1); return }
            print("\n===== InspectFetchSinglePage [\(index)] \(urlString) =====")
            fetcher.InspectFetchSinglePage(url: url, cookieString: "", successAction: { state in
                print("[OK] 抽出結果:\n\(summarize(state))")
                inspect(index + 1)
            }, failedAction: { failedUrl, reason in
                print("[NG/失敗] \(failedUrl.absoluteString)\n  reason: \(reason)")
                inspect(index + 1)
            })
        }

        inspect(0)
        waitForExpectations(timeout: 180)
    }

    // pixiv が「ログイン済みCookie由来」で取れているのか「未ログインでもHTML埋め込みで取れる」のかを切り分ける診断。
    // 返ってきたHTMLの目印と、pixiv.net ドメインのCookie『名前』(値は出さない)をダンプする。
    func testManual_Diagnose_PixivLoginState() throws {
        StoryHtmlDecoder.shared.cacheFileExpireTimeinterval = 0
        let urlString = "https://www.pixiv.net/novel/show.php?id=28239994"
        let url = try XCTUnwrap(URL(string: urlString))
        let fetcher = StoryFetcher()
        let finished = expectation(description: "diagnose pixiv")

        // まず最新 SiteInfo をロードして pixiv 用 SiteInfo の forceError 設定を確認する。
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady { _ in
        let siteInfos = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: urlString)
        print("\n===== pixiv SiteInfo 確認 (\(siteInfos.count)件) =====")
        for (i, si) in siteInfos.enumerated() {
            print("[\(i)] resourceUrl: \(si.resourceUrl ?? "nil")")
            print("    forceErrorMessageAndElement: \(si.forceErrorMessageAndElement ?? "nil")")
            print("    forceErrorElement(xpath): \(si.forceErrorElement ?? "nil")")
        }

        // inject(本番)経路と条件を揃える: UAをnil明示設定 + 待ち4秒。
        fetcher.httpClient.overrideUserAgent(userAgentString: nil)
        NiftyUtility.httpHeadlessRequest(url: url, timeoutInterval: 60, cookieString: "", mainDocumentURL: url, httpClient: fetcher.httpClient, withWaitSecond: 4.0, successAction: { doc in
            let html = doc.innerHTML ?? ""
            // 取得HTMLに対して forceError の xpath が実際にマッチするか確認する。
            if let kanna = try? Kanna.HTML(html: html, encoding: .utf8) {
                // ユーザーが SiteInfo に入れた PC版/スマホ版の2変種(union)。
                let pcXpath = "//main/section/div/div/div/div/span[contains(text(),'表示にはpixivアカウントが必要です')]"
                let spXpath = "//div[@id='contents']/div[@id='spa-contents']/div/div/div/div/div/div/div/div[contains(text(),'表示にはpixivアカウントが必要です')]"
                let unionXpath = pcXpath + "|" + spXpath
                let pc = NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: kanna, xpath: pcXpath, isNeedWhitespaceSplitForTag: false)
                let sp = NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: kanna, xpath: spXpath, isNeedWhitespaceSplitForTag: false)
                let uni = NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: kanna, xpath: unionXpath, isNeedWhitespaceSplitForTag: false)
                print("xpath(PC版 //main/.../span) マッチ数: \(pc.count)")
                print("xpath(スマホ版 //div[@id='contents']/...) マッチ数: \(sp.count)")
                print("xpath(union PC|スマホ) マッチ数: \(uni.count)  → forceError発火: \(uni.count > 0)")
            } else {
                print("Kanna HTML パース失敗")
            }
            // gate文言周辺の生マークアップをダンプして実際の構造を見る。
            for needle in ["表示できません", "が必要"] {
                if let r = html.range(of: needle) {
                    let lo = html.index(r.lowerBound, offsetBy: -250, limitedBy: html.startIndex) ?? html.startIndex
                    let hi = html.index(r.upperBound, offsetBy: 250, limitedBy: html.endIndex) ?? html.endIndex
                    print("----- 周辺マークアップ(\(needle)) -----\n\(html[lo..<hi])\n-----")
                } else {
                    print("『\(needle)』は生HTMLに見つからず")
                }
            }
            func has(_ s: String) -> Bool { html.contains(s) }
            let hasGate1 = has("R-18作品は表示できません")
            let hasGate2 = has("表示にはpixivアカウントが必要")
            let hasBody = has("登場人物")
            let hasPreload = has("meta-preload-data")
            let hasLogout = has("ログアウト") || has("logout")
            print("\n===== pixiv 診断 =====")
            print("html.count: \(html.count)")
            print("gate文言『R-18作品は表示できません』: \(hasGate1)")
            print("gate文言『表示にはpixivアカウントが必要』: \(hasGate2)")
            print("本文目印『登場人物』: \(hasBody)")
            print("preload-data(本文埋め込みJSON)存在: \(hasPreload)")
            print("『ログアウト』links(=ログイン済みの目印): \(hasLogout)")
            fetcher.httpClient.getAllCookies { cookies in
                let pixiv = (cookies ?? []).filter { $0.domain.contains("pixiv.net") }
                print("pixiv.net Cookie 件数: \(pixiv.count)")
                print("pixiv.net Cookie 名前一覧(値は出さない): \(pixiv.map { $0.name }.sorted().joined(separator: ", "))")
                // PHPSESSID は『数字_ランダム』形式だとログイン済み。先頭の数字(ユーザID)有無だけ見る。
                if let session = pixiv.first(where: { $0.name == "PHPSESSID" }) {
                    let looksLoggedIn = session.value.contains("_") && (session.value.first?.isNumber ?? false)
                    print("PHPSESSID 形式: ログイン済みっぽい=\(looksLoggedIn)")
                } else {
                    print("PHPSESSID: 無し")
                }
                finished.fulfill()
            }
        }, failedAction: { error in
            print("pixiv 診断 失敗: \(error?.localizedDescription ?? "nil")")
            finished.fulfill()
        })
        } // WaitLoadSiteInfoReady

        waitForExpectations(timeout: 120)
    }

    // forceError を SiteInfo に直接注入し、未ログイン pixiv が「failedAction(gateメッセージ)」になる事を
    // end-to-end で証明する(シートの反映遅延と切り離して仕組みだけを検証する)。
    // これが通れば、検査ランナー(着手順3)は [auth] ターゲットでこの failedAction を SKIP に振り分ければよい。
    func testManual_PixivForceErrorEscapesViaInjectedSiteInfo() throws {
        let urlString = "https://www.pixiv.net/novel/show.php?id=28239994"
        let url = try XCTUnwrap(URL(string: urlString))
        // 実teaser DOM(/tmp/pixiv_fetchnext.html)に対して lxml で検証した堅いxpath。
        // 3原則: (1)深い固定パスを避け //* (2)text()でなく . で子孫連結に当てる (3)ダッシュ等を避け短いかな漢字句。
        // 自動生成class名は使わない。'R-18' の '-' は生DOMで不一致になるため 'R-18' を含めず '作品は表示できません' を使う。
        let gateXpath = "//*[contains(.,'作品は表示できません')]|//*[contains(.,'アカウントが必要')]"
        let forceError = "pixiv にログインしていない事によるログインを促す画面が出ているようです。「Web取込タブ」側でログインしてからお試し下さい。:" + gateXpath
        let siteInfo = StorySiteInfo(
            id: UUID().uuidString,
            name: "pixiv-test",
            newPageElement: "//main",      // 何かしら本文っぽく拾える(=この SiteInfo が match 対象になる)
            url: "^https://(www|touch)\\.pixiv\\.net/novel/(show\\.php|series/\\d+)",
            title: nil, subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil,
            isNeedHeadless: "true",        // gate は JS 描画なので headless 必須
            injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: 8.0,
            forceClickButton: nil, resourceUrl: "pixiv-test", overrideUserAgent: nil,
            forceErrorMessageAndElement: forceError, scrollTo: nil, isNeedWhitespaceSplitForTag: nil
        )
        let fetcher = StoryFetcher()
        let state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfoWith(siteInfoArray: [siteInfo], url: url, cookieString: "", previousContent: nil)
        let finished = expectation(description: "pixiv forceError")

        fetcher.FetchNext(currentState: state, inspectionTargetURL: url, successAction: { resultState in
            let c = resultState.content ?? ""
            print("\n[想定外] OK になってしまった(forceError が発火していない): content(\(c.count))")
            print("  content に『表示にはpixivアカウントが必要』含む: \(c.contains("表示にはpixivアカウントが必要"))")
            print("  content に『R-18作品は表示できません』含む: \(c.contains("R-18作品は表示できません"))")
            print("  content 先頭120字: \(String(c.prefix(120)).replacingOccurrences(of: "\n", with: "/"))")
            XCTFail("forceError が発火せず OK になった")
            finished.fulfill()
        }, failedAction: { failedUrl, reason in
            print("\n[想定どおり] failedAction = SKIP相当: \(reason)")
            XCTAssertTrue(reason.contains("ログインを促す画面"), "gate メッセージが返るはず")
            finished.fulfill()
        })

        waitForExpectations(timeout: 90)
    }

    // 同一プロセス・同一WebViewで「直接httpHeadlessRequest」と「FetchNext(本番)経路」を背中合わせに実行し、
    // gate検出の差が『コード経路差』なのか『プロセス間の描画揺れ』なのかを決着させる。
    func testManual_PixivCompareBothPaths() throws {
        let urlString = "https://www.pixiv.net/novel/show.php?id=28239994"
        let url = try XCTUnwrap(URL(string: urlString))
        let pcXpath = "//main/section/div/div/div/div/span[contains(text(),'表示にはpixivアカウントが必要です')]"
        let spXpath = "//div[@id='contents']/div[@id='spa-contents']/div/div/div/div/div/div/div/div[contains(text(),'表示にはpixivアカウントが必要です')]"
        let unionXpath = pcXpath + "|" + spXpath
        let forceError = "ログインを促す画面が出ています:" + unionXpath
        let fetcher = StoryFetcher()
        let finished = expectation(description: "compare both paths")

        // Step A: 直接 httpHeadlessRequest
        fetcher.httpClient.overrideUserAgent(userAgentString: nil)
        NiftyUtility.httpHeadlessRequest(url: url, postData: nil, timeoutInterval: 300, cookieString: "", mainDocumentURL: url, httpClient: fetcher.httpClient, withWaitSecond: 4.0, injectJavaScript: nil, successAction: { doc in
            let html = doc.innerHTML ?? ""
            let count: Int
            if let kanna = try? Kanna.HTML(html: html, encoding: .utf8) {
                count = NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: kanna, xpath: unionXpath, isNeedWhitespaceSplitForTag: false).count
            } else { count = -1 }
            print("\n[A: 直接httpHeadlessRequest] html.count=\(html.count) union一致=\(count) gate文言=\(html.contains("R-18作品は表示できません"))")

            // Step B: 同じ fetcher/WebView で FetchNext(本番)経路
            let siteInfo = StorySiteInfo(
                id: UUID().uuidString, name: "pixiv-test", newPageElement: "//main",
                url: "^https://(www|touch)\\.pixiv\\.net/novel/(show\\.php|series/\\d+)",
                title: nil, subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil,
                isNeedHeadless: "true", injectStyle: nil, nextButton: nil, firstPageButton: nil,
                waitSecondInHeadless: 4.0, forceClickButton: nil, resourceUrl: "pixiv-test",
                overrideUserAgent: nil, forceErrorMessageAndElement: forceError, scrollTo: nil, isNeedWhitespaceSplitForTag: nil
            )
            let state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfoWith(siteInfoArray: [siteInfo], url: url, cookieString: "", previousContent: nil)
            fetcher.FetchNext(currentState: state, inspectionTargetURL: url, successAction: { s in
                print("[B: FetchNext経路] OK(発火せず) content=\(s.content?.count ?? -1) gate文言含=\((s.content ?? "").contains("R-18作品は表示できません"))")
                finished.fulfill()
            }, failedAction: { _, reason in
                print("[B: FetchNext経路] failedAction(発火) reason=\(reason)")
                finished.fulfill()
            })
        }, failedAction: { error in
            print("[A] 失敗: \(error?.localizedDescription ?? "nil")")
            finished.fulfill()
        })

        waitForExpectations(timeout: 120)
    }
    // FetchNext経路で実際に取得されるHTMLを /tmp/pixiv_fetchnext.html に保存し、
    // gate検出 xpath 候補を実エンジン(Kanna)で評価する。
    // 待ちは FetchNext 側(waitSecondInHeadless 8.0)に揃える。React SPA のDOMは待ち時間で変わるため。
    func testManual_PixivDumpTeaserDOM() throws {
        let url = try XCTUnwrap(URL(string: "https://www.pixiv.net/novel/show.php?id=28239994"))
        let fetcher = StoryFetcher()
        let finished = expectation(description: "dump teaser")
        fetcher.httpClient.overrideUserAgent(userAgentString: nil)
        RobotsFileTool.shared.CheckRobotsTxt(url: url, userAgentString: "NovelSpeaker/2") { _ in
            NiftyUtility.httpHeadlessRequest(url: url, postData: nil, timeoutInterval: 300, cookieString: "", mainDocumentURL: url, httpClient: fetcher.httpClient, withWaitSecond: 8.0, injectJavaScript: nil, successAction: { doc in
                let html = doc.innerHTML ?? ""
                try? html.write(toFile: "/tmp/pixiv_fetchnext.html", atomically: true, encoding: .utf8)
                print("[DUMP] htmlCount=\(html.count) saved=/tmp/pixiv_fetchnext.html")

                // (1) 生html(=正規化前)に gate文言が contiguous で在るか / 空白入りで断片化しているか。
                func collapsed(_ s: String) -> String { s.components(separatedBy: .whitespacesAndNewlines).joined() }
                let collapsedHtml = collapsed(html)
                for needle in ["R-18作品は表示できません", "作品は表示できません", "アカウントが必要"] {
                    print("  生html contiguous『\(needle)』: \(html.contains(needle))  / 空白除去後: \(collapsedHtml.contains(collapsed(needle)))")
                }

                // (2) 実エンジン(Kanna)で候補xpathのヒット数。これが decodeForceErrorElement と同じ判定。
                guard let k = try? Kanna.HTML(html: html, encoding: .utf8) else { print("  Kanna parse 失敗"); finished.fulfill(); return }
                let cands: [(String, String)] = [
                    ("//*[contains(.,'作品は表示できません')]", "//*[contains(.,'作品は表示できません')]"),
                    ("//span[contains(.,'作品は表示できません')]", "//span[contains(.,'作品は表示できません')]"),
                    ("//*[contains(.,'アカウントが必要')]", "//*[contains(.,'アカウントが必要')]"),
                    ("//*[contains(.,'表示できません')]", "//*[contains(.,'表示できません')]"),
                    ("//*[contains(.,'必要です')]", "//*[contains(.,'必要です')]"),
                ]
                for (name, xp) in cands {
                    let n = NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: k, xpath: xp, isNeedWhitespaceSplitForTag: false).count
                    print("  Kanna xpath ヒット \(n) : \(name)")
                }
                finished.fulfill()
            }, failedAction: { e in print("fail:\(e?.localizedDescription ?? "nil")"); finished.fulfill() })
        }
        waitForExpectations(timeout: 120)
    }

    // pixiv は UA で DOM 構造を出し分ける（iOS版 / Mac Safari版）。指定UAで取得して savePath に保存する。
    private func capturePixivDOM(userAgent: String?, savePath: String, label: String) {
        guard let url = URL(string: "https://www.pixiv.net/novel/show.php?id=28239994") else { return }
        let fetcher = StoryFetcher()
        let finished = expectation(description: "capture-\(label)")
        fetcher.httpClient.overrideUserAgent(userAgentString: userAgent)
        RobotsFileTool.shared.CheckRobotsTxt(url: url, userAgentString: "NovelSpeaker/2") { _ in
            NiftyUtility.httpHeadlessRequest(url: url, postData: nil, timeoutInterval: 300, cookieString: "", mainDocumentURL: url, httpClient: fetcher.httpClient, withWaitSecond: 8.0, injectJavaScript: nil, successAction: { doc in
                let html = doc.innerHTML ?? ""
                try? html.write(toFile: savePath, atomically: true, encoding: .utf8)
                print("[DUMP \(label)] htmlCount=\(html.count) saved=\(savePath)  UA=\(userAgent ?? "(default)")")
                finished.fulfill()
            }, failedAction: { e in print("fail \(label):\(e?.localizedDescription ?? "nil")"); finished.fulfill() })
        }
        waitForExpectations(timeout: 120)
    }

    func testManual_PixivDumpDOM_iOSUA() throws {
        capturePixivDOM(userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", savePath: "/tmp/pixiv_ios.html", label: "iOS")
    }
    func testManual_PixivDumpDOM_MacUA() throws {
        capturePixivDOM(userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15", savePath: "/tmp/pixiv_mac.html", label: "Mac")
    }

    // ネットワーク無しの決定的再現。捕獲済みの「forceError非発火DOM」(/tmp/pixiv_decode_dump.html)を読み、
    // Kannaで「単独xpath」「|ユニオンxpath」「実 decodeForceErrorElement」のヒット数を突き合わせ、0の出所を特定する。
    func testManual_PixivDecodeDumpReproduce() throws {
        let path = "/tmp/pixiv_decode_dump.html"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("先に testManual_PixivForceErrorEscapesViaInjectedSiteInfo を実行して \(path) を生成してください")
        }
        let html = try String(contentsOfFile: path, encoding: .utf8)
        let k = try XCTUnwrap(try? Kanna.HTML(html: html, encoding: .utf8))

        let single1 = "//*[contains(.,'作品は表示できません')]"
        let single2 = "//*[contains(.,'アカウントが必要')]"
        let union = single1 + "|" + single2
        func cnt(_ xp: String) -> Int { NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: k, xpath: xp, isNeedWhitespaceSplitForTag: false).count }
        func raw(_ xp: String) -> Int { k.xpath(xp).count }   // Kannaの生xpathノード数
        print("\n===== decode_dump 再現 (html.count=\(html.count)) =====")
        print("  raw  単独1 = \(raw(single1))   FilterExtruct = \(cnt(single1))")
        print("  raw  単独2 = \(raw(single2))   FilterExtruct = \(cnt(single2))")
        print("  raw  union = \(raw(union))   FilterExtruct = \(cnt(union))")
        print("  raw  //span[…作品は表示できません] = \(raw("//span[contains(.,'作品は表示できません')]"))")

        // 実アプリと同一経路: 注入SiteInfo の decodeForceErrorElement。
        let forceError = "ログインを促す画面が出ています。:" + union
        let siteInfo = StorySiteInfo(
            id: UUID().uuidString, name: "pixiv-test", newPageElement: "//main",
            url: "^https://(www|touch)\\.pixiv\\.net/novel/(show\\.php|series/\\d+)",
            title: nil, subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil,
            isNeedHeadless: "true", injectStyle: nil, nextButton: nil, firstPageButton: nil,
            waitSecondInHeadless: 8.0, forceClickButton: nil, resourceUrl: "pixiv-test",
            overrideUserAgent: nil, forceErrorMessageAndElement: forceError, scrollTo: nil, isNeedWhitespaceSplitForTag: nil
        )
        print("  siteInfo.forceErrorElement = \(siteInfo.forceErrorElement ?? "nil")")
        print("  siteInfo.forceErrorMessage = \(siteInfo.forceErrorMessage ?? "nil")")
        print("  decodeForceErrorElement() = \(siteInfo.decodeForceErrorElement(xmlDocument: k))  ← これが実アプリの発火判定")
    }

    // ユーザ提案の「構造＋button揃い踏み」でガチガチに縛る forceError xpath を、
    // 取得済みの各DOM(iOS版/Mac版/デフォルト)に対して実機Kannaで検証する。ネットワーク不要・決定的。
    // 思想: forceErrorは「誤検知より検知漏れ」。広く当たる .ユニオンは不採用。
    func testManual_PixivGateXpathCandidates() throws {
        // ユーザ確定版の各ブランチ。
        let macBranch = "//main/section/div/div/div/div[child::span[contains(.,'表示にはpixivアカウントが必要です。')]]/div/div[child::button[@class='charcoal-button' and text()='アカウントを作成'] and child::button[@class='charcoal-button' and text()='ログイン']]"
        let iosBranch = "//div/div/div/div/div/div[child::a[contains(@href,'/signup.php')] and child::a[contains(@href,'/login.php')]]/div[contains(.,'表示にはpixivアカウントが必要です。')]"
        let union = macBranch + "|" + iosBranch

        let files: [(String, String)] = [
            ("Mac UA",     "/tmp/pixiv_mac.html"),
            ("iOS UA",     "/tmp/pixiv_ios.html"),
            ("default UA", "/tmp/pixiv_fetchnext.html"),
        ].filter { FileManager.default.fileExists(atPath: $0.1) }
        if files.isEmpty {
            throw XCTSkip("先に testManual_PixivDumpDOM_iOSUA / _MacUA (または testManual_PixivDumpTeaserDOM) を実行してダンプを生成してください")
        }

        for (label, path) in files {
            let html = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            guard let k = try? Kanna.HTML(html: html, encoding: .utf8) else { print("[\(label)] Kanna parse 失敗"); continue }
            func raw(_ xp: String) -> Int { k.xpath(xp).count }
            print("\n===== \(label)  (\(path), html.count=\(html.count)) =====")
            print("  has //main=\(raw("//main")) / //a[contains(@href,'/login.php')]=\(raw("//a[contains(@href,'/login.php')]")) / //a[contains(@href,'/signup.php')]=\(raw("//a[contains(@href,'/signup.php')]"))")
            print("  buttons: charcoal-button[アカウントを作成]=\(raw("//button[@class='charcoal-button' and text()='アカウントを作成']")) / [ログイン]=\(raw("//button[@class='charcoal-button' and text()='ログイン']"))")
            print("  Macブランチ raw = \(raw(macBranch))")
            print("  iOSブランチ raw = \(raw(iosBranch))")
            print("  union       raw = \(raw(union))")

            // 実アプリ経路: 注入SiteInfo の decodeForceErrorElement。
            let siteInfo = StorySiteInfo(
                id: UUID().uuidString, name: "pixiv-test", newPageElement: "//main",
                url: "^https://(www|touch)\\.pixiv\\.net/novel/(show\\.php|series/\\d+)",
                title: nil, subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil,
                isNeedHeadless: "true", injectStyle: nil, nextButton: nil, firstPageButton: nil,
                waitSecondInHeadless: 8.0, forceClickButton: nil, resourceUrl: "pixiv-test",
                overrideUserAgent: nil, forceErrorMessageAndElement: "ログインを促す画面が出ています。:" + union, scrollTo: nil, isNeedWhitespaceSplitForTag: nil
            )
            print("  decodeForceErrorElement(union) = \(siteInfo.decodeForceErrorElement(xmlDocument: k))  ← 実アプリの発火判定")
        }
    }

    // 最新SiteInfoを取り直して、各SiteInfoの checkTargets が『どうパースされたか』を表示する。
    // ユーザのシート記法のチェック用(URL/要認証/期待トークンが意図どおりか)。実検査はしない(ネットはCSV取得のみ)。
    func testManual_DumpCheckTargets() throws {
        StoryHtmlDecoder.shared.cacheFileExpireTimeinterval = 0  // ファイルキャッシュ無効化
        URLCache.shared.removeAllCachedResponses()               // HTTPキャッシュも消さないと古いCSVが返る
        let finished = expectation(description: "dump checkTargets")
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady { errorString in
            if let e = errorString { print("[SiteInfoロードエラー] \(e)") }
            var total = 0
            for siteInfoArray in StoryHtmlDecoder.shared.siteInfoArrayArray {
                for siteInfo in siteInfoArray where !siteInfo.checkTargets.isEmpty {
                    print("\n=== \(siteInfo.name ?? "(no name)")  (\(siteInfo.checkTargets.count)件) ===")
                    for t in siteInfo.checkTargets {
                        total += 1
                        let toks = t.expectations.map { "\($0.mustBeEmpty ? "!" : "")\($0.token.rawValue)" }.joined(separator: ",")
                        print("  \(t.requireAuth ? "[auth] " : "")\(t.url.absoluteString)\n      => [\(toks)]")
                        if !t.unknownTokens.isEmpty {
                            print("      ⚠️ 無効トークン(typo?): \(t.unknownTokens.joined(separator: ", "))")
                        }
                    }
                }
            }
            print("\n合計 \(total) ターゲット")
            finished.fulfill()
        }
        waitForExpectations(timeout: 120)
    }

    // 着手順3: 全SiteInfoの checkTargets を逐次検査してレポートを出す手動実行(実ネットワーク)。
    // SiteInfoシートに checkTargets 列を埋めると、ここに OK/NG/SKIP/ROBOTS が並ぶ。
    func testManual_RunScrapeInspectorAll() throws {
        StoryHtmlDecoder.shared.cacheFileExpireTimeinterval = 0  // ファイルキャッシュ無効化
        URLCache.shared.removeAllCachedResponses()               // HTTPキャッシュも消さないと古いCSVが返る
        let inspector = ScrapeInspector()
        let finished = expectation(description: "inspect all")
        inspector.InspectAll(progress: { done, total, result in
            print("  (\(done)/\(total)) \(result.description)")
        }, completion: { results in
            print("\n" + ScrapeInspector.report(results: results))
            finished.fulfill()
        })
        waitForExpectations(timeout: 1800)
    }

    // 「ホスト変化で未ログイン検出」方式の前提確認: novel18 を未ログインで検査したとき、
    // 検査の最終 state.url がリダイレクト先ホスト(nl.syosetu.com 等)を保持しているかを実機で見る。
    // 保持していれば requestedHost != finalHost で「別ホストの壁へ飛ばされた=未ログイン確定」を判定できる。
    func testManual_Novel18RedirectFinalURL() throws {
        let requested = try XCTUnwrap(URL(string: "https://novel18.syosetu.com/n8956gi/1/"))
        let fetcher = StoryFetcher()
        let finished = expectation(description: "novel18 redirect")
        fetcher.InspectFetchSinglePage(url: requested, cookieString: "", successAction: { state in
            // state.url(=要求URL由来かもしれない) と、headless WKWebView の実際の現在URLの両方を出す。
            let realCurrent = fetcher.httpClient.GetCurrentURL()
            print("[N18 success] requestedHost=\(requested.host ?? "nil")")
            print("  state.url        = \(state.url.absoluteString)  (host=\(state.url.host ?? "nil"))")
            print("  httpClient.GetCurrentURL = \(realCurrent?.absoluteString ?? "nil")  (host=\(realCurrent?.host ?? "nil"))  ← これが実遷移後URL")
            print("  content?=\(state.content?.isEmpty == false)(len=\(state.content?.count ?? -1)) firstPageLink?=\(state.firstPageLink != nil) author?=\(state.author?.isEmpty == false) subtitle?=\(state.subtitle?.isEmpty == false) nextUrl?=\(state.nextUrl != nil)")
            if let c = state.content { print("  content先頭80: \(String(c.prefix(80)))") }
            finished.fulfill()
        }, failedAction: { url, msg in
            print("[N18 failed] url=\(url.absoluteString) msg=\(msg)")
            finished.fulfill()
        })
        waitForExpectations(timeout: 120)
    }
 #endif
}
