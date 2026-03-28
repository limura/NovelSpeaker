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
