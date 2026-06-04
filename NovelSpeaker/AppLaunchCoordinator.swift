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

    @discardableResult
    static func runScrapeInspectionCLIIfRequested() -> Bool {
        let args = CommandLine.arguments
        let env = ProcessInfo.processInfo.environment
        guard args.contains("--scrape-inspect") || env["NOVELSPEAKER_SCRAPE_INSPECT"] == "1" else {
            return false
        }

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
