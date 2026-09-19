//
//  SceneDelegate.swift
//  NovelSpeaker
//
//  Created by Codex on 2026/09/15.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    #if DEBUG
    private var didPresentUITestDialog = false
    private var didRequestUITestStartLandscape = false
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        #if DEBUG
        NSLog("UI test launch arguments: \(ProcessInfo.processInfo.arguments)")
        #endif

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
        #if DEBUG
        NSLog("UI test active arguments: \(ProcessInfo.processInfo.arguments)")
        #endif
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

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestingStartLandscape"),
           !didRequestUITestStartLandscape,
           let windowScene = window?.windowScene,
           #available(iOS 16.0, *) {
            didRequestUITestStartLandscape = true
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
                NSLog("UI test landscape geometry request: \(String(describing: error))")
            }
        }
        presentUITestDialogIfRequested()
        #endif
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            _ = NovelSpeakerUtility.ProcessURL(url: context.url)
        }
    }

    #if DEBUG
    private func requestUITestGeometry(for interfaceOrientations: UIInterfaceOrientationMask) {
        guard #available(iOS 16.0, *),
              let windowScene = window?.windowScene else { return }

        NSLog("UI test requesting interface orientations: \(interfaceOrientations)")
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: interfaceOrientations)) { error in
            NSLog("UI test orientation geometry request: \(String(describing: error))")
        }
    }

    private func presentUITestDialogIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        let shouldPresentLongMessageDialog = arguments.contains("-UITestingLongMessageDialog")
        let shouldPresentLongMessageTwoButtonDialog = arguments.contains("-UITestingLongMessageTwoButtonDialog")
        guard (shouldPresentLongMessageDialog || shouldPresentLongMessageTwoButtonDialog), !didPresentUITestDialog else { return }
        guard let rootViewController = window?.rootViewController, rootViewController.viewIfLoaded?.window != nil else {
            DispatchQueue.main.async { [weak self] in self?.presentUITestDialogIfRequested() }
            return
        }

        didPresentUITestDialog = true
        NSLog("UI test: presenting EasyDialogLongMessageDialog")
        let message = "Webページに掲載されている小説をアプリに読み上げさせる事で小説を「聞く」ためのアプリです。\n\nこの文章を ことせかい アプリ内の本棚から選択して読んでいる場合、右上辺りにある「Speak」というボタンを押す事で、読み上げが開始されます。（読み上げが行われると音が出ますのでご注意下さい。読み上げが開始された後は「Speak」ボタンは「Stop」ボタンに変化します。「Stop」ボタンを押すことで読み上げが停止します）読み上げを開始する位置を指定したい場合には、読み上げが停止している状態で読み上げを開始したい位置を長押しして選択範囲を表示させた状態にした上で、右上の「Speak」ボタンを押します。"
        let dialog: EasyDialog
        if shouldPresentLongMessageTwoButtonDialog {
            dialog = NiftyUtility.EasyDialogLongMessageTwoButton(
                viewController: rootViewController,
                title: nil,
                message: message,
                button1Title: "キャンセル",
                button1Action: nil,
                button2Title: "OK",
                button2Action: nil
            )
        } else {
            dialog = NiftyUtility.EasyDialogLongMessageDialog(viewController: rootViewController, message: message)
        }
        dialog.view.accessibilityIdentifier = "UITestEasyDialog"
        var dialogButtonIndex = 1
        assignUITestDialogButtonIdentifiers(in: dialog.view, nextIndex: &dialogButtonIndex)

        if ProcessInfo.processInfo.arguments.contains("-UITestingAllowRotation") {
            let portraitTrigger = UIButton(type: .custom)
            portraitTrigger.accessibilityIdentifier = "UITestRotateToPortrait"
            portraitTrigger.frame = CGRect(x: 10, y: 10, width: 44, height: 44)
            portraitTrigger.alpha = 0.05
            portraitTrigger.addAction(UIAction { [weak self] _ in
                NSLog("UI test portrait trigger tapped")
                self?.requestUITestPortrait()
            }, for: .touchUpInside)
            dialog.view.addSubview(portraitTrigger)
            dialog.view.bringSubviewToFront(portraitTrigger)
        }
    }

    private func requestUITestPortrait() {
        requestUITestGeometry(for: .portrait)
    }

    private func assignUITestDialogButtonIdentifiers(in view: UIView, nextIndex: inout Int) {
        for subview in view.subviews {
            if let button = subview as? UIButton, button.accessibilityIdentifier == nil {
                button.accessibilityIdentifier = "UITestDialogButton\(nextIndex)"
                nextIndex += 1
            }
            assignUITestDialogButtonIdentifiers(in: subview, nextIndex: &nextIndex)
        }
    }
    #endif
}
