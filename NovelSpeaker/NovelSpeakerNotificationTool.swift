//
//  LocalNotifications.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/21.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import Foundation
import RealmSwift

extension Notification.Name {
    struct NovelSpeaker {
        // フォントサイズが変わった時
        //static let FontSizeChanged = Notification.Name("NovelSpeaker_Notification_FontSizeChanged")
        // 特定の Story (userInfo["storyID"]: String) の content が変更された時
        //static let StoryContentChanged = Notification.Name("NovelSpeaker_Notification_StoryContentChanged")
        // ダウンロード状態が変わった時
        static let DownloadStatusChanged = Notification.Name("NovelSpeaker_Notification_DownloadStatusChanged")
        // 設定がいろいろ変わって設定ページをリロードした方が良い時
        static let GlobalStateChanged = Notification.Name("NovelSpeaker_Notification_GlobalStateChanged")
        // 利用する Realm の設定等が変わった時(localRelam から cloud realm になった等)
        static let RealmSettingChanged = Notification.Name("NovelSpeaker_Notification_RealmSettingChanged")
        // SpeechViewController を popViewController してほしい時に呼ぶ
        static let ForcePopViewControllerForSpeechView = Notification.Name("NovelSpeaker_Notification_ForcePopViewControllerForSpeechView")
    }
}
extension Notification {
    struct NovelSpeakerUserInfoKey {
        static let StoryID = "storyID"
    }
}

class NovelSpeakerNotificationTool {
    static let lock = NSLock()
    static var notificationTokenHolder:[ObjectIdentifier:[NSObjectProtocol]] = [:]
    
    static func addObserver(selfObject:ObjectIdentifier, name: Notification.Name, queue: OperationQueue?, using: @escaping (Notification)->Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: queue, using: using)
        lock.lock()
        defer { lock.unlock() }
        if var holder = self.notificationTokenHolder[selfObject] {
            holder.append(token)
            self.notificationTokenHolder[selfObject] = holder
        }else{
            let holder = [token]
            self.notificationTokenHolder[selfObject] = holder
        }
    }
    static func removeObserver(selfObject:ObjectIdentifier) {
        guard let holder = self.notificationTokenHolder[selfObject] else { return }
        let notificationCenter = NotificationCenter.default
        lock.lock()
        defer { lock.unlock() }
        for token in holder {
            notificationCenter.removeObserver(token)
        }
        self.notificationTokenHolder.removeValue(forKey: selfObject)
    }
    
    /*
    static func AnnounceFontSizeChanged() {
        let notificationCenter = NotificationCenter.default
        let notification = Notification(name: Notification.Name.NovelSpeaker.FontSizeChanged)
        notificationCenter.post(notification)
    }
    static func AnnounceStoryContentChanged(storyID: String) {
        let notificationCenter = NotificationCenter.default
        let notification = Notification(name: Notification.Name.NovelSpeaker.StoryContentChanged, object: nil, userInfo: [Notification.NovelSpeakerUserInfoKey.StoryID: storyID])
        notificationCenter.post(notification)
    }
     */
    static func AnnounceDownloadStatusChanged() {
        let notificationCenter = NotificationCenter.default
        let notification = Notification(name: Notification.Name.NovelSpeaker.DownloadStatusChanged)
        notificationCenter.post(notification)
    }
    
    static func AnnounceGlobalStateChanged() {
        let notificationCenter = NotificationCenter.default
        let notification = Notification(name: Notification.Name.NovelSpeaker.GlobalStateChanged)
        notificationCenter.post(notification)
    }

    static func AnnounceRealmSettingChanged() {
        let notificationCenter = NotificationCenter.default
        let notification = Notification(name: Notification.Name.NovelSpeaker.RealmSettingChanged)
        notificationCenter.post(notification)
    }

    static func AnnounceForcePopViewControllerForSpeechView() {
        let notificationCenter = NotificationCenter.default
        let notification = Notification(name: Notification.Name.NovelSpeaker.ForcePopViewControllerForSpeechView)
        notificationCenter.post(notification)
    }
}
