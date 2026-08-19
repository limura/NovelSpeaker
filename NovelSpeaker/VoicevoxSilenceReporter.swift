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
    }

    private let lock = NSLock()
    private var lastPlaybackEndedAt: Date?
    private var lastIntentionalDelay: TimeInterval = 0
    private var lastCause: Cause?
    private var totalCount = 0

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
        let count = totalCount
        let cause = lastCause
        lastCause = nil
        lock.unlock()

        AppInformationLogger.AddLogWithStruct(
            message: Self.message(gapSeconds: seconds, totalCount: count, cause: cause),
            isForDebug: true,
            category: "voicevoxSilence",
            dedupeKey: "voicevoxSilence")
        return seconds
    }

    static func message(gapSeconds: Double, totalCount: Int, cause: Cause?) -> String {
        var text = String(format: NSLocalizedString(
            "VoicevoxSilence_MessageFormat",
            comment: "VOICEVOXの読み上げが %1$.1f秒 途切れました(この起動で %2$d回目)"), gapSeconds, totalCount)
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
        lock.unlock()
    }
}
