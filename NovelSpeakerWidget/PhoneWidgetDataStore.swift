//
//  PhoneWidgetDataStore.swift
//  NovelSpeaker
//
//  iPhone側ウィジェットのための App Group 共有ストア。
//  アプリ本体(PhoneWidgetDataUpdater)が Realm から再計算して書き、
//  ウィジェット拡張(タイムラインプロバイダ / EntityQuery)が読む。
//  Foundation 以外に依存しないこと(アプリと拡張の両ターゲットでコンパイルされる)。
//
//  Watch 版の WatchComplicationData / WatchNovelSummaryStore に相当するが、
//  App Group が別(こちらは iPhone アプリ⇔iPhone ウィジェット拡張)なので独立させている。
//

import Foundation

/// 今読んでいる小説(ランチャーの進捗表示用)
struct PhoneWidgetReadingState: Codable, Equatable {
    var novelID: String
    var title: String
    /// 栞の章(1始まり)
    var chapterNumber: Int
    var chapterCount: Int
    /// 全体の読了進捗(0.0-1.0)。章ベース+章内進捗
    var overallProgress: Double

    var chapterFraction: String { "\(chapterNumber)/\(chapterCount)" }
}

/// 設定可能ウィジェット(「指定小説の再生を開始」)の小説選択肢1件分
struct PhoneWidgetNovelSummary: Codable, Equatable, Identifiable {
    var novelID: String
    var title: String
    var chapterCount: Int
    /// 全体の読了進捗(0.0-1.0)
    var overallProgress: Double

    var id: String { novelID }
}

enum PhoneWidgetDataStore {
    static let appGroupID = "group.com.limuraproducts.novelspeaker"
    private static let readingStateKey = "PhoneWidgetReadingState"
    private static let summariesKey = "PhoneWidgetNovelSummaries"

    static func loadReadingState() -> PhoneWidgetReadingState? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: readingStateKey),
              let value = try? JSONDecoder().decode(PhoneWidgetReadingState.self, from: data) else { return nil }
        return value
    }

    /// 保存する。内容が前回と同じなら false を返し、呼び出し側はウィジェットの
    /// 再読込をスキップできる(OS の更新回数節約)
    @discardableResult
    static func saveReadingState(_ state: PhoneWidgetReadingState?) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        if loadReadingState() == state { return false }
        if let state = state, let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: readingStateKey)
        } else {
            defaults.removeObject(forKey: readingStateKey)
        }
        return true
    }

    static func loadSummaries() -> [PhoneWidgetNovelSummary] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: summariesKey),
              let value = try? JSONDecoder().decode([PhoneWidgetNovelSummary].self, from: data) else { return [] }
        return value
    }

    static func summary(novelID: String) -> PhoneWidgetNovelSummary? {
        return loadSummaries().first { $0.novelID == novelID }
    }

    @discardableResult
    static func saveSummaries(_ summaries: [PhoneWidgetNovelSummary]) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        if loadSummaries() == summaries { return false }
        guard let data = try? JSONEncoder().encode(summaries) else { return false }
        defaults.set(data, forKey: summariesKey)
        return true
    }

    /// 章ベース+章内進捗の読了進捗(Watch 版 WatchNovelSummaryStore.overallProgress と同じ式)。
    /// chapterNumber は栞の章(1始まり)、inChapter は章内進捗(0.0-1.0)
    static func overallProgress(chapterNumber: Int, chapterCount: Int, inChapter: Double) -> Double {
        guard chapterCount > 0 else { return 0 }
        let base = Double(max(0, chapterNumber - 1))
        let clamped = min(max(inChapter, 0), 1)
        return min(1.0, (base + clamped) / Double(chapterCount))
    }
}
