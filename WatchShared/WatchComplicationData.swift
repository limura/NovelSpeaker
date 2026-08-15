//
//  WatchComplicationData.swift
//  NovelSpeaker
//
//  文字盤コンプリケーション(第二弾: 情報表示)が表示する「今読んでいる小説」の情報。
//  Watch アプリが App Group 共有 UserDefaults に書き、ウィジェット拡張が読む。
//  Foundation 以外に依存しないこと(WatchShared の他ファイルと同様)。
//

import Foundation

struct WatchComplicationData: Codable {
    var novelID: String = ""
    var title: String = ""
    /// 現在の章タイトル(subtitle)。無い章もある
    var chapterSubtitle: String = ""
    var chapterNumber: Int = 0
    var chapterCount: Int = 0
    /// 現在の章内の進捗(0.0-1.0)
    var progressInChapter: Double = 0
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// 全体の読了進捗(章ベース + 章内進捗)。本棚の読了ゲージと同じ考え方
    var overallProgress: Double {
        guard chapterCount > 0 else { return 0 }
        let base = Double(max(0, chapterNumber - 1))
        let inChapter = min(max(progressInChapter, 0), 1)
        return min(1.0, (base + inChapter) / Double(chapterCount))
    }

    /// 「章/総章」(総章が不明なら章番号のみ)
    var chapterFraction: String {
        if chapterCount > 0 { return "\(chapterNumber)/\(chapterCount)" }
        return chapterNumber > 0 ? "\(chapterNumber)" : ""
    }

    /// rectangular の詳細行: 「章/総章 章タイトル(あれば)」
    var rectangularDetail: String {
        let fraction = chapterFraction
        if !chapterSubtitle.isEmpty {
            return fraction.isEmpty ? chapterSubtitle : "\(fraction) \(chapterSubtitle)"
        }
        return fraction
    }

    var hasNovel: Bool { !novelID.isEmpty && !title.isEmpty }

    // MARK: - App Group 共有ストア

    static let appGroupID = "group.com.limuraproducts.novelspeaker.watch"
    private static let defaultsKey = "WatchComplicationData"

    static func load() -> WatchComplicationData? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(WatchComplicationData.self, from: data) else { return nil }
        return value
    }

    /// 共有ストアに保存する。内容が実質同じ(小説・章・進捗が僅差)なら false を返し、
    /// 呼び出し側はコンプリケーションの再読込をスキップできる(OS の更新回数節約)
    @discardableResult
    func saveIfChanged() -> Bool {
        guard let defaults = UserDefaults(suiteName: WatchComplicationData.appGroupID) else { return false }
        if let previous = WatchComplicationData.load(), !previous.isMeaningfullyDifferent(from: self) {
            return false
        }
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: WatchComplicationData.defaultsKey)
        return true
    }

    /// 小説・章が変わった、または全体進捗が 1% 以上動いたら「意味のある変化」とみなす
    private func isMeaningfullyDifferent(from other: WatchComplicationData) -> Bool {
        if novelID != other.novelID || chapterNumber != other.chapterNumber
            || chapterCount != other.chapterCount || title != other.title
            || chapterSubtitle != other.chapterSubtitle { return true }
        return abs(overallProgress - other.overallProgress) >= 0.01
    }
}
