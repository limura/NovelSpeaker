//
//  VoicevoxSilenceReporter.swift
//  NovelSpeaker
//
//  「読み上げの途中で音が途切れた」事だけを記録する。
//
//  VOICEVOX は合成が再生に間に合わないと、そのまま無音になる。
//  利用者から「たまに止まる」と言われた時に手掛かりが何も無いと、
//  端末が遅いのか・作り置きが足りないのか・不具合なのかを切り分けられない。
//
//  以前は再生まわりの出来事を全部ためて無音時に吐き出していたが、
//  普段は誰も見ないものを常に集め続ける事になる。
//  **問い合わせで効くのは「いつ・何秒・何回・間に合わなかった理由」**だけなので、
//  そこに絞って「アプリ内エラーのお知らせ」に1件残す。
//  同じ内容は dedupeKey でまとめられるので、何度途切れても件数が増えるだけで済む。
//
//  意図的な間(「間の設定」やユーザー操作による停止)は無音として数えない。
//

import Foundation

final class VoicevoxSilenceReporter {
    static let shared = VoicevoxSilenceReporter()

    /// これ以上途切れたら記録する。短い途切れは端末の都合でも起きるので拾わない。
    static let reportThresholdSeconds: Double = 2.0

    /// 間に合わなかった時の理由。無音の原因の切り分けに使う。
    enum Cause: Equatable {
        /// 先行合成には出していたが、再生に間に合わなかった(端末が遅い/文章が長い)。
        case synthesisWasTooSlow
        /// そもそも先行合成に出していなかった(取りこぼし=不具合の可能性)。
        case notScheduled

        var text: String {
            switch self {
            case .synthesisWasTooSlow: return NSLocalizedString("VoicevoxSilence_CauseTooSlow", comment: "合成が再生に間に合わなかった")
            case .notScheduled: return NSLocalizedString("VoicevoxSilence_CauseNotScheduled", comment: "先行合成に出せていなかった")
            }
        }

        /// 集計の見出しに使う、翻訳されない短い名前。
        var key: String {
            switch self {
            case .synthesisWasTooSlow: return "tooSlow"
            case .notScheduled: return "notScheduled"
            }
        }
    }

    /// 途切れの長さをまとめる区切り(秒)。この境界で件数を数える。
    /// 「2秒が200回」なのか「14秒が200回」なのかで話が全く変わるため。
    static let bucketBoundaries: [Double] = [3, 5, 10, 20]

    /// まとめの記録を出す最短間隔(秒)。
    /// 途切れる度に1件ずつ出すと数百件になり、まとめて数えないと読めない。
    static let summaryIntervalSeconds: TimeInterval = 300

    /// 「今までで一番長い」を更新したとみなす差(秒)。
    static let worseningStepSeconds: Double = 1.0

    private let lock = NSLock()
    private var lastPlaybackEndedAt: Date?
    private var lastIntentionalDelay: TimeInterval = 0
    private var lastCause: Cause?
    private var totalCount = 0
    private var totalSeconds: Double = 0
    private var worstSeconds: Double = 0
    private var bucketCounts: [Int] = Array(repeating: 0, count: bucketBoundaries.count + 1)
    private var causeCounts: [String: Int] = [:]
    private var lastSummaryDate: Date?
    private var countAtLastSummary = 0
    private var reportedWorstSeconds: Double = 0

    /// あるブロックを鳴らし終えた(次に音が出るまでが無音になる)。
    /// - Parameter intentionalDelay: この後に入る「間の設定」由来の意図的なポーズ秒数。
    func notePlaybackEnded(intentionalDelay: TimeInterval, at now: Date = Date()) {
        lock.lock()
        lastPlaybackEndedAt = now
        lastIntentionalDelay = intentionalDelay
        lock.unlock()
    }

    /// ユーザー操作による停止/一時停止など、無音として数えるべきでない中断。
    func notePlaybackInterrupted() {
        lock.lock()
        lastPlaybackEndedAt = nil
        lastIntentionalDelay = 0
        lock.unlock()
    }

    /// 再生に必要な音声が用意できていなかった事と、その理由。
    func noteCacheMiss(wasQueuedForPrefetch: Bool) {
        lock.lock()
        lastCause = wasQueuedForPrefetch ? .synthesisWasTooSlow : .notScheduled
        lock.unlock()
    }

    /// これから音を鳴らす。直前の再生終了からの間隔が意図しない無音になる。
    /// - Returns: 記録した無音の秒数(記録しなかった場合は nil)。
    @discardableResult
    func notePlaybackStarting(at now: Date = Date()) -> Double? {
        lock.lock()
        guard let endedAt = lastPlaybackEndedAt else {
            lock.unlock()
            return nil
        }
        let seconds = now.timeIntervalSince(endedAt) - lastIntentionalDelay
        lastPlaybackEndedAt = nil
        lastIntentionalDelay = 0
        guard seconds >= Self.reportThresholdSeconds else {
            lock.unlock()
            return nil
        }
        totalCount += 1
        totalSeconds += seconds
        worstSeconds = max(worstSeconds, seconds)
        bucketCounts[Self.bucketIndex(forSeconds: seconds)] += 1
        let cause = lastCause
        lastCause = nil
        if let cause = cause {
            causeCounts[cause.key, default: 0] += 1
        }

        // ★1件ずつ dedupeKey でまとめる、という方法は使えない。
        //  AppInformationLogger の dedupe は「最初のログの文面を残して回数だけ増やす」
        //  実装なので、それだと**全部が1件目の秒数として表示される**。
        //  実機ログで「14.0秒 が 217回」と並び、2秒の途切れが217回だったのか
        //  14秒が217回だったのかが全く分からなくなった。
        //  代わりに、こちらで数えたものをまとめて出す。
        let shouldReport: Bool
        if totalCount == 1 {
            // 1件目は必ず残す(この仕組みが動いている事と、その時の秒数が分かる)。
            shouldReport = true
        } else if seconds >= reportedWorstSeconds + Self.worseningStepSeconds {
            // 今までで一番長い途切れが出た。
            shouldReport = true
        } else if let last = lastSummaryDate, now.timeIntervalSince(last) >= Self.summaryIntervalSeconds {
            // 定期のまとめ。件数の推移が時系列で分かるようにする。
            shouldReport = true
        } else {
            shouldReport = false
        }
        guard shouldReport else {
            lock.unlock()
            return seconds
        }
        reportedWorstSeconds = max(reportedWorstSeconds, seconds)
        lastSummaryDate = now
        let snapshot = (count: totalCount,
                        total: totalSeconds,
                        worst: worstSeconds,
                        latest: seconds,
                        sinceLast: totalCount - countAtLastSummary,
                        buckets: bucketCounts,
                        causes: causeCounts)
        countAtLastSummary = totalCount
        lock.unlock()

        var appendix: [String: AnyCodable] = [
            "totalCount": AnyCodable("\(snapshot.count)"),
            "totalSeconds": AnyCodable(String(format: "%.1f", snapshot.total)),
            "worstSeconds": AnyCodable(String(format: "%.1f", snapshot.worst)),
            "latestSeconds": AnyCodable(String(format: "%.1f", snapshot.latest)),
            "countSinceLastReport": AnyCodable("\(snapshot.sinceLast)"),
            "lengths": AnyCodable(Self.bucketText(counts: snapshot.buckets)),
        ]
        for (key, value) in snapshot.causes {
            appendix["cause_" + key] = AnyCodable("\(value)")
        }
        AppInformationLogger.AddLogWithStruct(
            message: Self.summaryMessage(totalCount: snapshot.count,
                                         totalSeconds: snapshot.total,
                                         worstSeconds: snapshot.worst,
                                         latestSeconds: snapshot.latest,
                                         cause: cause),
            appendix: appendix,
            // 既定ではデバッグ用のログにだけ残る。
            // 「VOICEVOX の不調をお知らせに出す」を点けている間は普通のお知らせとして見せる。
            isForDebug: VoicevoxDiagnostics.isForDebug,
            category: "voicevoxSilence")
        return seconds
    }

    /// 途切れの長さがどの区切りに入るか。
    static func bucketIndex(forSeconds seconds: Double) -> Int {
        for (index, boundary) in bucketBoundaries.enumerated() where seconds < boundary {
            return index
        }
        return bucketBoundaries.count
    }

    /// 「2〜3秒:12 3〜5秒:4 …」のような、長さの分布を1行にしたもの。
    static func bucketText(counts: [Int]) -> String {
        var parts: [String] = []
        var lower = reportThresholdSeconds
        for (index, count) in counts.enumerated() {
            let label: String
            if index < bucketBoundaries.count {
                label = String(format: "%.0f-%.0fs", lower, bucketBoundaries[index])
                lower = bucketBoundaries[index]
            } else {
                label = String(format: "%.0fs-", lower)
            }
            if count > 0 { parts.append("\(label):\(count)") }
        }
        return parts.joined(separator: " ")
    }

    static func summaryMessage(totalCount: Int,
                               totalSeconds: Double,
                               worstSeconds: Double,
                               latestSeconds: Double,
                               cause: Cause?) -> String {
        var text = String(format: NSLocalizedString(
            "VoicevoxSilence_SummaryFormat",
            comment: "VOICEVOXの読み上げが途切れています: この起動で %1$d回 / 合計 %2$.0f秒 / 最長 %3$.1f秒 / 直近 %4$.1f秒"),
                          totalCount, totalSeconds, worstSeconds, latestSeconds)
        if let cause = cause {
            text += String(format: NSLocalizedString(
                "VoicevoxSilence_CauseFormat", comment: "。理由: %@"), cause.text)
        }
        return text
    }

    /// テスト用。
    func resetForTesting() {
        lock.lock()
        lastPlaybackEndedAt = nil
        lastIntentionalDelay = 0
        lastCause = nil
        totalCount = 0
        totalSeconds = 0
        worstSeconds = 0
        bucketCounts = Array(repeating: 0, count: Self.bucketBoundaries.count + 1)
        causeCounts.removeAll()
        lastSummaryDate = nil
        countAtLastSummary = 0
        reportedWorstSeconds = 0
        lock.unlock()
    }
}
