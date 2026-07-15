//
//  WatchNovelSummaryStore.swift
//  NovelSpeaker
//
//  設定可能ウィジェット(「この小説を再生」)の小説選択肢と読了ゲージのための、
//  小説別の要約(novelID→タイトル・章数・読了進捗)を App Group 共有ストアに置く。
//  Watch アプリが「Watch に転送済みの小説 + 最近読んだ順の上位」を最近読んだ/再生した順で書き、
//  ウィジェット拡張(EntityQuery / タイムラインプロバイダ)が読む。
//
//  Foundation 以外に依存しないこと(WatchShared の他ファイルと同様。ウィジェット拡張と
//  アプリ本体の両ターゲットでコンパイルされる)。
//

import Foundation

/// ウィジェットが扱う小説1件分の要約
struct WatchWidgetNovelSummary: Codable, Equatable, Identifiable {
    var novelID: String
    var title: String
    var chapterCount: Int
    /// 全体の読了進捗(0.0-1.0)。本棚・コンプリケーションと同じ考え方(章ベース+章内進捗)
    var overallProgress: Double

    var id: String { novelID }
}

enum WatchNovelSummaryStore {
    static let appGroupID = WatchComplicationData.appGroupID
    private static let key = "WatchWidgetNovelSummaries"

    static func load() -> [WatchWidgetNovelSummary] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode([WatchWidgetNovelSummary].self, from: data) else { return [] }
        return value
    }

    static func summary(novelID: String) -> WatchWidgetNovelSummary? {
        return load().first { $0.novelID == novelID }
    }

    /// 共有ストアに保存する。内容が前回と同じなら false を返し、呼び出し側はウィジェットの
    /// 再読込をスキップできる(OS の更新回数節約)
    @discardableResult
    static func save(_ summaries: [WatchWidgetNovelSummary]) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        if load() == summaries { return false }
        guard let data = try? JSONEncoder().encode(summaries) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// 章ベース+章内進捗の読了進捗(WatchComplicationData.overallProgress と同じ式)。
    /// chapterNumber は栞の章(1始まり)、inChapter は章内進捗(0.0-1.0)
    static func overallProgress(chapterNumber: Int, chapterCount: Int, inChapter: Double) -> Double {
        guard chapterCount > 0 else { return 0 }
        let base = Double(max(0, chapterNumber - 1))
        let clamped = min(max(inChapter, 0), 1)
        return min(1.0, (base + clamped) / Double(chapterCount))
    }
}
