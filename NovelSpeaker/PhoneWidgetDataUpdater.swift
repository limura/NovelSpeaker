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

    private static var observerTokens: [NotificationToken] = []
    private static var debounceWorkItem: DispatchWorkItem?
    /// SetStory の入口で先取りした「これから読む小説」。
    /// currentReadingNovelID の本書き込み(SetStory 完了後)が追いつくまでの間、
    /// ランチャー表示にはこちらを優先して使う(main thread からのみ触る)
    private static var upcomingReadingNovelID: String?

    /// Realm の変更を監視して共有ストアを追従させる(runPostLaunch から一度だけ呼ぶ)。
    /// 一発のトリガ(起動時・バックグラウンド移行時)だけだと、
    /// - 小説を開いた直後にホームへ戻る: currentReadingNovelID の更新は SetStory の
    ///   重い非同期処理の完了後なので、didEnterBackground 時点ではまだ前の小説のまま
    /// - ウィジェット操作だけで発話→停止: 栞の保存は StopSpeech の後から非同期に走る
    /// といった「書き込みがトリガより後に来る」ケースを取りこぼすため、
    /// 書き込みそのもの(RealmGlobalState / RealmNovel の変更)を監視する。
    /// 再計算は軽い(上位30件+skip-if-equal)のでデバウンスは短めでよい
    static func startObserving() {
        DispatchQueue.main.async {
            guard observerTokens.isEmpty else { return }
            // コントロールセンター/ロック画面下部角のコントロールは OS 側が登録を
            // キャッシュするため、アプリ更新でコントロールの見た目や分岐を変えても
            // 反映されないことがある。起動のたびに再読込を頼んでおく
            #if !targetEnvironment(macCatalyst)
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadAllControls()
            }
            #endif
            RealmUtil.RealmBlock { realm in
                // currentReadingNovelID の切り替わり(小説を開いた等)
                if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                    observerTokens.append(globalState.observe { _ in
                        updateSoon()
                    })
                }
                // 栞(読了位置・lastReadDate)や小説の追加・削除
                if let novels = RealmNovel.GetAllObjectsWith(realm: realm) {
                    observerTokens.append(novels.observe { changes in
                        guard case .update(_, let deletions, let insertions, let modifications) = changes,
                              !(deletions.isEmpty && insertions.isEmpty && modifications.isEmpty) else { return }
                        updateSoon()
                    })
                }
            }
        }
    }

    /// SetStory 直後(重い処理の完了前)の先取り通知(StorySpeaker.SetStory から呼ばれる)。
    /// アプリがまだ前面にいるうちに即時反映しておくことで、直後にホーム画面へ
    /// 戻られてもウィジェットが新しい小説になっているようにする
    static func noteReadingNovel(novelID: String) {
        DispatchQueue.main.async {
            guard upcomingReadingNovelID != novelID else { return }
            upcomingReadingNovelID = novelID
            update()
        }
    }

    /// 変更の連打(発話中の栞保存や iCloud 同期のバースト)をまとめるためのデバウンス
    static func updateSoon() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem {
            update()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    static func update() {
        DispatchQueue.main.async {
            var changed = false
            RealmUtil.RealmBlock { realm in
                changed = PhoneWidgetDataStore.saveReadingState(currentReadingState(realm: realm)) || changed
                changed = PhoneWidgetDataStore.saveSummaries(currentSummaries(realm: realm)) || changed
                changed = PhoneWidgetDataStore.saveBookshelfStats(currentBookshelfStats(realm: realm)) || changed
            }
            if changed {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// 今読んでいる小説(前回読んでいた小説)。読了進捗は栞の位置から計算する
    private static func currentReadingState(realm: Realm) -> PhoneWidgetReadingState? {
        // SetStory の先取り通知があればそちらを優先する。
        // 本書き込み(currentReadingNovelID)が追いついたら先取りは解除する
        if let upcoming = upcomingReadingNovelID {
            if RealmGlobalState.GetInstanceWith(realm: realm)?.currentReadingNovelID == upcoming {
                upcomingReadingNovelID = nil
            } else if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: upcoming) {
                return PhoneWidgetReadingState(
                    novelID: upcoming,
                    title: novel.title,
                    chapterNumber: novel.readingChapterNumber ?? 1,
                    chapterCount: novel.lastChapterNumber ?? 0,
                    overallProgress: roundedProgress(novel: novel))
            }
        }
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

    /// 本棚の統計(ランチャーの統計行用)。
    /// 「更新あり」は本棚の NEW バッジ(RealmNovel.isNewFlug)と同じ日付比較。
    /// 日付プロパティ同士の比較は Realm のクエリで完結するので件数が多くても軽い
    private static func currentBookshelfStats(realm: Realm) -> PhoneWidgetBookshelfStats {
        guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else {
            return PhoneWidgetBookshelfStats(novelCount: 0, newArrivalCount: 0)
        }
        return PhoneWidgetBookshelfStats(
            novelCount: novels.count,
            newArrivalCount: novels.filter("lastDownloadDate > lastReadDate").count)
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
