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
        static let FontSizeChanged = Notification.Name("NovelSpeaker_Notification_FontSizeChanged")
        // 特定の Story (userInfo["storyID"]: String) の content が変更された時
        static let StoryContentChanged = Notification.Name("NovelSpeaker_Notification_StoryContentChanged")
    }
}
extension Notification {
    struct NovelSpeakerUserInfoKey {
        static let StoryID = "storyID"
    }
}

class NovelSpeakerNotificationTool {
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
}
