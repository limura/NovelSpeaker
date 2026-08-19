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

    private let lock = NSLock()
    private var lastEvaluationDate = Date.distantPast

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
        VoicevoxCacheGenerator.shared.stopIfFollowingPlayback()
    }

    func evaluate() {
        // この機能を使わない設定(0分)なら何もしない。
        guard VoicevoxCacheLead.keepGeneratingBelowMinutes > 0 else {
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback()
            return
        }
        guard let context = VoicevoxCore.shared.diskCacheContext, context.isWritable else {
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback()
            return
        }
        guard StorySpeaker.shared.isPlayng else {
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback()
            return
        }
        // 利用者が明示的に始めた生成が走っている時は、そちらに任せる。
        if let running = VoicevoxCacheGenerator.shared.runningNovelID,
           VoicevoxCacheGenerator.shared.runningMode == .manual {
            _ = running
            return
        }

        let lead = contiguousLeadSeconds(context: context)
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
            VoicevoxCacheGenerator.shared.stopIfFollowingPlayback()
        }
    }

    /// 今の再生位置から先に、**途切れずに**貯めてある音声の秒数。
    ///
    /// 今読んでいるページの残りを1ブロックずつ数え、ページを跨いだ後は
    /// 「そのページに貯めてある合計」を足していき、何も無いページで打ち切る。
    /// 後半は概算で、部分的にしか出来ていないページを丸ごと数えてしまうが、
    /// 生成は前から順に埋めていくので、そういうページは境目の1つだけになる
    /// (=多く見積もってもそのページ1つぶん)。
    private func contiguousLeadSeconds(context: VoicevoxCore.DiskCacheContext) -> Double {
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
        var lead = VoicevoxCacheLead.contiguousSeconds(upcomingDurations: durations)

        // このページの最後まで揃っている時だけ、次のページ以降も数える。
        let hasGapInCurrentChapter = durations.contains(where: { $0 == nil })
        guard hasGapInCurrentChapter == false else { return lead }

        var chapterNumber = context.chapterNumber + 1
        while true {
            let summary = store.summary(novelID: context.novelID, chapterNumber: chapterNumber)
            if summary.entryCount == 0 { break }
            lead += summary.audioSeconds
            chapterNumber += 1
            // 何時間も先まで数えても判断は変わらないので、適当な所で切り上げる。
            if lead >= VoicevoxCacheLead.keepGeneratingBelowSeconds { break }
        }
        return lead
    }
}
#endif
