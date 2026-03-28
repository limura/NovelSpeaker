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

        NovelSpeakerUtility.StartAllLongLivedOperationIDWatcher()
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
    }

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
            storyboard = .main
        }

        return UIStoryboard(name: storyboard.rawValue, bundle: nil).instantiateInitialViewController()!
    }
}
