//
//  PhoneWidgetDataUpdater.swift
//  NovelSpeaker
//
//  iPhone側ウィジェットが使う App Group 共有ストア(PhoneWidgetDataStore)を
//  Realm から再計算して書き込む。書き込みは差分がある時だけで、その時だけ
//  WidgetCenter に再読込を頼む(OS の更新回数節約)。
//
//  呼び出しタイミング: アプリ起動後(runPostLaunch)、バックグラウンド移行時
//  (ホーム画面に戻る=ウィジェットが見える直前)、ウィジェット intent の実行後。
//  リアルタイム追従はしない(Watch のコンプリケーションと同じ鮮度感)。
//

import Foundation
import WidgetKit
import RealmSwift

class PhoneWidgetDataUpdater {
    /// 設定可能ウィジェットの小説候補数。多すぎても選択 UI が長くなるだけなので上位のみ
    static let novelSummaryLimit = 30

    static func update() {
        DispatchQueue.main.async {
            var changed = false
            RealmUtil.RealmBlock { realm in
                changed = PhoneWidgetDataStore.saveReadingState(currentReadingState(realm: realm)) || changed
                changed = PhoneWidgetDataStore.saveSummaries(currentSummaries(realm: realm)) || changed
            }
            if changed {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// 今読んでいる小説(前回読んでいた小説)。読了進捗は栞の位置から計算する
    private static func currentReadingState(realm: Realm) -> PhoneWidgetReadingState? {
        guard let story = RealmGlobalState.GetLastReadStory(realm: realm) else { return nil }
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: story.storyID)
        guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return nil }
        return PhoneWidgetReadingState(
            novelID: novelID,
            title: novel.title,
            chapterNumber: RealmStoryBulk.StoryIDToChapterNumber(storyID: story.storyID),
            chapterCount: novel.lastChapterNumber ?? 0,
            overallProgress: roundedProgress(novel: novel))
    }

    /// 「指定小説の再生を開始」の小説候補。最近読んだ順の上位のみ
    private static func currentSummaries(realm: Realm) -> [PhoneWidgetNovelSummary] {
        guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return [] }
        let sorted = novels.sorted(byKeyPath: "lastReadDate", ascending: false)
        var result: [PhoneWidgetNovelSummary] = []
        for novel in sorted {
            if result.count >= novelSummaryLimit { break }
            result.append(PhoneWidgetNovelSummary(
                novelID: novel.novelID,
                title: novel.title,
                chapterCount: novel.lastChapterNumber ?? 0,
                overallProgress: roundedProgress(novel: novel)))
        }
        return result
    }

    /// 全体の読了進捗。細かすぎる差分で毎回「変化あり」にならないよう 1% 単位に丸める
    private static func roundedProgress(novel: RealmNovel) -> Double {
        let contentCount = max(novel.m_readingChapterContentCount, 1)
        let inChapter = Double(novel.m_readingChapterReadingPoint) / Double(contentCount)
        let progress = PhoneWidgetDataStore.overallProgress(
            chapterNumber: novel.readingChapterNumber ?? 0,
            chapterCount: novel.lastChapterNumber ?? 0,
            inChapter: inChapter)
        return (progress * 100).rounded() / 100
    }
}
