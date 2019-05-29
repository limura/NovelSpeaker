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
    }
}
extension Notification {
    struct NovelSpeakerUserInfoKey {
        static let StoryID = "storyID"
    }
}

class NovelSpeakerNotificationTool {
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
}
