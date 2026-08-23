//
//  VoicevoxCacheAutoGeneration.swift
//  NovelSpeaker
//
//  読み上げ中に、貯めてある音声が心細くなってきたら自動で作り足す役。
//
//  なぜ要るか:
//  事前に作った分を聴き終わった瞬間から、実時間合成に戻って無音だらけになる
//  (背面バッテリーでは必要CPU率が128〜226%に対し使えるのは80%)。
//  一方、キャッシュから再生している間は合成のCPUがゼロで、80%の予算が丸ごと空いている。
//  **生成に最も適した時間帯が、何もしていない時間になっている**のがもったいない。
//
//  ただし十分に貯まっているなら作らない。聴き終わらないかもしれない先の分を
//  作るのは電池の無駄なので、「この先の貯金が閾値(既定15分)を切ったら作る」とする。
//

import Foundation

#if !os(watchOS)
final class VoicevoxCacheAutoGeneration {

    static let shared = VoicevoxCacheAutoGeneration()

    /// 判定の間隔。毎回のwillSpeakRangeで測ると重いので間引く。
    private static let evaluationIntervalSeconds: Double = 15

    /// 走り続けている間、貯金がどうなっているかを残す間隔。
    ///
    /// 開始と停止しか記録していなかったため、実機ログから
    /// 「作り足しは動いているのに貯金が増えているのか減っているのか」が読めなかった。
    /// 74分回して無音が55%という結果は取れたのに、その間ずっと生成は走りっぱなしで、
    /// 貯まっていたのか追いつけていなかったのかが分からない。
    /// 前景か背面か・スレッド数も一緒に残す(画面が消えて背面に落ちていた場合、
    /// それは「前景で測った結果」ではないため)。
    private static let heartbeatIntervalSeconds: Double = 300

    private let lock = NSLock()
    private var lastEvaluationDate = Date.distantPast
    private var lastHeartbeatDate = Date.distantPast

    private init() {}

    /// 読み上げが進む度に呼ばれる(内部で間引く)。
    func evaluateIfNeeded() {
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(lastEvaluationDate) < Self.evaluationIntervalSeconds {
            lock.unlock()
            return
        }
        lastEvaluationDate = now
        lock.unlock()
        evaluate()
    }

    /// 読み上げが止まった時に呼ぶ。自動生成も止める
    /// (利用者が明示的に始めた生成は止めない)。
    func playbackDidStop() {
        VoicevoxCacheGenerator.shared.stopIfFollowingPlayback(reason: "読み上げが止まったため")
    }

    func evaluate() {
        // この機能を使わない設定(0分)なら何もしない。
        guard VoicevoxCacheLead.keepGeneratingBelowMinutes > 0 else {
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback(reason: "裏での作り足しが設定で無効になっているため")
            return
        }
        // 事前生成を有効にしていない小説でも作り足す。
        // 作った物は一時分に置かれ、聴き終わった所から消えるので、
        // 「断りなくストレージを使い続ける」事にはならない。
        guard let context = VoicevoxCore.shared.diskCacheContext else {
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback(reason: "今読んでいる小説が分からないため")
            return
        }
        guard StorySpeaker.shared.isPlayng else {
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback(reason: "読み上げ中ではないため")
            return
        }
        // 利用者が明示的に始めた生成が走っている時は、そちらに任せる。
        if let running = VoicevoxCacheGenerator.shared.runningNovelID,
           VoicevoxCacheGenerator.shared.runningMode == .manual {
            _ = running
            return
        }

        let lead = contiguousLeadSeconds(context: context)
        logHeartbeatIfNeeded(leadSeconds: lead)
        if VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: lead) {
            if VoicevoxCacheGenerator.shared.runningNovelID != context.novelID {
                AppInformationLogger.AddLog(message:
                    "[VOICEVOX音声生成] この先の貯金が \(VoicevoxCacheGenerationProgress.durationText(seconds: lead))"
                    + "(下限\(VoicevoxCacheLead.keepGeneratingBelowMinutes)分)なので、読み上げの裏で作り足します",
                    isForDebug: true)
                VoicevoxCacheGenerator.shared.start(novelID: context.novelID, mode: .followingPlayback)
            }
        } else {
            if VoicevoxCacheGenerator.shared.runningNovelID != nil,
               VoicevoxCacheGenerator.shared.runningMode == .followingPlayback {
                AppInformationLogger.AddLog(message:
                    "[VOICEVOX音声生成] この先の貯金が \(VoicevoxCacheGenerationProgress.durationText(seconds: lead)) 貯まったので、裏での作り足しを止めます",
                    isForDebug: true)
            }
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback(reason: "貯金が下限まで貯まったため")
        }
    }

    /// 走り続けている間の様子を、たまに記録する。
    ///
    /// 貯金が増えているのか減っているのかは、これが無いと後から分からない。
    private func logHeartbeatIfNeeded(leadSeconds: Double) {
        guard VoicevoxCacheGenerator.shared.runningNovelID != nil else { return }
        let now = Date()
        lock.lock()
        guard now.timeIntervalSince(lastHeartbeatDate) >= Self.heartbeatIntervalSeconds else {
            lock.unlock()
            return
        }
        lastHeartbeatDate = now
        lock.unlock()
        let monitor = VoicevoxPrefetchThrottleMonitor.shared
        AppInformationLogger.AddLog(message:
            "[VOICEVOX音声生成] 作り足し中: この先の貯金は "
            + VoicevoxCacheGenerationProgress.durationText(seconds: leadSeconds),
            appendix: [
                "leadSeconds": String(format: "%.0f", leadSeconds),
                "isBackground": monitor.isBackground ? "true" : "false",
                "isOnExternalPower": monitor.isOnExternalPower ? "true" : "false",
                "threadCount": "\(VoicevoxCore.activeCPUNumThreads)",
                "thermalState": "\(ProcessInfo.processInfo.thermalState.rawValue)",
            ], isForDebug: VoicevoxDiagnostics.isForDebug)
    }

    /// 今の再生位置から先に、途切れずに貯めてある音声の秒数。
    ///
    /// ブロック列の取り出しだけをここで行い、数える所は `VoicevoxCacheLead` に置いてある
    /// (StorySpeaker に依存しない形にして、テストから叩けるようにするため)。
    private func contiguousLeadSeconds(context: VoicevoxAudioProvider.DiskCacheContext) -> Double {
        let store = VoicevoxDiskCacheStore.shared
        let speaker = StorySpeaker.shared.speaker
        let blocks = speaker.speechBlockArray
        let startIndex = speaker.currentSpeechBlockIndex

        var durations: [Double?] = []
        if startIndex < blocks.count {
            for block in blocks[startIndex...] {
                guard block.type == "VOICEVOX" else {
                    // 他のエンジンで読むブロックは合成が要らないので、穴とは見なさない。
                    durations.append(0)
                    continue
                }
                let text = block.speechText
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || VoicevoxCacheBlockSource.hasNoSpeakableCharacter(text) {
                    durations.append(0)
                    continue
                }
                let styleId = VoicevoxCore.styleId(fromVoiceIdentifier: block.voiceIdentifier)
                let key = VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
                durations.append(store.durationSeconds(novelID: context.novelID, chapterNumber: context.chapterNumber, key: key))
            }
        }
        return VoicevoxCacheLead.contiguousLeadSeconds(
            store: store,
            novelID: context.novelID,
            chapterNumber: context.chapterNumber,
            upcomingDurations: durations)
    }
}
#endif
