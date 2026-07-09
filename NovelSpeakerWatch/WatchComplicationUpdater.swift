//
//  WatchComplicationUpdater.swift
//  NovelSpeakerWatch
//
//  「今読んでいる小説」の情報を App Group 共有ストアに書き、コンプリケーションを更新する。
//  リモコン(iPhone 再生)の playState と、Watch 単体再生(WatchSpeechPlayer)の両方から呼ばれる。
//  最後に書いた方が採用される(通常どちらも同じ小説・章を指すので実害は無い)。
//
//  コンプリケーションの再読込(WidgetCenter.reloadAllTimelines)は OS が間引くので、
//  小説・章が変わった時は即時、章内進捗だけの変化は間引いて呼ぶ(内容が実質同じなら保存もしない)。
//

import Foundation
import WidgetKit

enum WatchComplicationUpdater {
    private static let lock = NSObject()
    private static var lastReloadDate = Date(timeIntervalSince1970: 0)
    /// 章内進捗だけの変化での再読込は、この間隔より頻繁には呼ばない
    private static let minReloadInterval: TimeInterval = 60

    static func update(novelID: String, title: String, chapterSubtitle: String,
                       chapterNumber: Int, chapterCount: Int, progressInChapter: Double) {
        var data = WatchComplicationData()
        data.novelID = novelID
        data.title = title
        data.chapterSubtitle = chapterSubtitle
        data.chapterNumber = chapterNumber
        data.chapterCount = chapterCount
        data.progressInChapter = progressInChapter
        data.updatedAt = Date()

        objc_sync_enter(lock)
        defer { objc_sync_exit(lock) }

        let previous = WatchComplicationData.load()
        // 内容が実質同じ(進捗が僅差)なら何もしない
        guard data.saveIfChanged() else { return }

        // 小説・章が変わったら即時、章内進捗だけなら間引いて再読込する
        let structuralChange = previous?.novelID != novelID
            || previous?.chapterNumber != chapterNumber
            || previous?.chapterCount != chapterCount
        let now = Date()
        if structuralChange || now.timeIntervalSince(lastReloadDate) >= minReloadInterval {
            lastReloadDate = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
