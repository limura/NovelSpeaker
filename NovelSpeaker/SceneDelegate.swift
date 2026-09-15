//
//  SceneDelegate.swift
//  NovelSpeaker
//
//  Created by Codex on 2026/09/15.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        #if targetEnvironment(macCatalyst)
        // コマンドライン検査モードではUIを作らず、検査完了時にプロセスが終了する。
        guard !AppDelegate.isHeadlessLaunch else { return }
        #endif

        guard let windowScene = scene as? UIWindowScene else { return }

        let topLevelViewController = AppLaunchCoordinator.createInitialRootViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = topLevelViewController
        self.window = window
        window.makeKeyAndVisible()
        AppLaunchCoordinator.runPostLaunch(rootViewController: topLevelViewController)

        // アプリが終了中にURLで起動された場合は、Scene接続時のURLを処理する。
        for context in connectionOptions.urlContexts {
            _ = NovelSpeakerUtility.ProcessURL(url: context.url)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NSLog("scene did enter background.")
        GlobalDataSingleton.getInstance()?.saveContext()
        RealmUtil.SetCheckCloudDataIsValidInterrupt(isInterrupt: true)
        NovelDownloadQueue.shared.scheduleBackgroundProcess()
        // ホーム画面に戻る=ウィジェットが見える直前なので、進捗表示などを更新しておく
        PhoneWidgetDataUpdater.update()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        NSLog("scene did become active.")
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

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            _ = NovelSpeakerUtility.ProcessURL(url: context.url)
        }
    }
}
