//
//  AppDelegate.swift
//  NovelSpeaker
//
//  Created by Codex on 2026/03/21.
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if targetEnvironment(macCatalyst)
        // コマンドライン引数(--scrape-inspect)指定時は、UIも重いpreflight(CloudKit/Realm)も行わず、
        // SiteInfo検査だけして stdout にレポートを吐いて exit する。
        // runPreflight() より前に出すのは、検査エンジンが CloudKit を必要とせず、
        // かつ headless 起動(cron/launchd)では iCloud コンテナ初期化が落ちうるため。
        if AppLaunchCoordinator.runScrapeInspectionCLIIfRequested() {
            return true
        }
        #endif

        guard AppLaunchCoordinator.runPreflight() else {
            return false
        }

        let topLevelViewController = AppLaunchCoordinator.createInitialRootViewController()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = topLevelViewController
        window?.makeKeyAndVisible()
        AppLaunchCoordinator.runPostLaunch(rootViewController: topLevelViewController)

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        NSLog("application did enter background.")
        GlobalDataSingleton.getInstance()?.saveContext()
        RealmUtil.SetCheckCloudDataIsValidInterrupt(isInterrupt: true)
        NovelDownloadQueue.shared.scheduleBackgroundProcess()
        // ホーム画面に戻る=ウィジェットが見える直前なので、進捗表示などを更新しておく
        PhoneWidgetDataUpdater.update()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        NSLog("application did become active.")
        NovelDownloadQueue.shared.ClearDownloadCountBadge()
        StorySpeaker.becomeActiveHandle()
        NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
        if RealmUtil.IsUseCloudRealm() {
            RealmUtil.CloudPull()
        }
        WebSpeechViewController.instance?.RedisplayWebView()
        // バックグラウンド中に完了した栞・小説切替の書き込みを取りこぼしていても
        // ここで追いつく(デバウンス発火前にサスペンドした場合など)
        PhoneWidgetDataUpdater.update()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        NSLog("application will terminate")
        GlobalDataSingleton.getInstance()?.saveContext()
        let queuedCount = NovelDownloadQueue.DownloadFlush()
        NovelSpeakerUtility.ForceStopSpeech()
        if RealmUtil.IsUseCloudRealm() {
            RealmUtil.CloudPull()
        }
        RealmUtil.sync()
        if queuedCount > 0 {
            Thread.sleep(forTimeInterval: 3.0)
        }
        RealmUtil.sync()
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        NovelSpeakerUtility.ProcessURL(url: url)
    }

    /// 背面で走らせていた取得(VOICEVOXの音声モデル)が終わって、OS がアプリを起こしてきた。
    ///
    /// **completionHandler を呼ばないと、次から背面で走らせてもらえなくなる。**
    /// 実際の後始末が終わったところで呼びたいので、ダウンローダに預ける。
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == VoicevoxVoiceModelDownloader.sessionIdentifier else {
            completionHandler()
            return
        }
        VoicevoxVoiceModelDownloader.shared.backgroundEventsCompletionHandler = completionHandler
        VoicevoxVoiceModelDownloader.shared.resumePendingDownloadsIfNeeded()
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        if #available(iOS 13.0, *) {
            MenuButtonHandler.buildMenuHandler(builder: builder)
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        NovelSpeakerUtility.supportRotationMask
    }
}
