//
//  VoicevoxCacheGenerator.swift
//  NovelSpeaker
//
//  利用者が明示的に指示して、音声キャッシュを前から順に作っていく役。
//
//  「端末を起動しっぱなしにして放置しておく」使い方を前提にしている。
//  iOS から短時間だけ割り当てられる背面実行(BGProcessingTask)で作る方式は、
//  実行されない夜もあって主役にはできないので、まずはこちらを作る。
//  (こちらで作った資産はそのまま背面生成でも使えるが、逆は成り立たない)
//
//  開始位置は「今の再生位置」から。1ページ目から作られても
//  「100ページ目まではもう聴いた」という状況では役に立たないため。
//

import Foundation
#if !os(watchOS)
import UIKit
import RealmSwift

final class VoicevoxCacheGenerator {

    static let shared = VoicevoxCacheGenerator()

    /// 進捗が変わった事を画面へ知らせる。
    static let progressDidChangeNotification = Notification.Name("NovelSpeaker.VoicevoxCacheGenerator.progressDidChange")

    /// 残りディスク容量がこれを下回ったら生成を止める。
    /// 長編を丸ごと作ると数百MB〜数GBになるので、端末を埋め尽くす前に止める必要がある。
    static let minimumFreeBytes: Int64 = 500 * 1024 * 1024

    enum StopReason {
        case finished
        case stoppedByUser
        case diskFull
        case failed(String)

        var message: String {
            switch self {
            case .finished: return "最後まで作り終えました"
            case .stoppedByUser: return "生成を止めました"
            case .diskFull: return "端末の空き容量が少ないため止めました"
            case .failed(let text): return "生成に失敗したため止めました(\(text))"
            }
        }
    }

    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var runningNovelIDUnsafe: String?
    private var progressUnsafe: VoicevoxCacheGenerationProgress?
    private var lastStopReasonUnsafe: StopReason?

    private init() {}

    var runningNovelID: String? {
        lock.lock(); defer { lock.unlock() }
        return runningNovelIDUnsafe
    }

    var isRunning: Bool { return runningNovelID != nil }

    var progress: VoicevoxCacheGenerationProgress? {
        lock.lock(); defer { lock.unlock() }
        return progressUnsafe
    }

    var lastStopReason: StopReason? {
        lock.lock(); defer { lock.unlock() }
        return lastStopReasonUnsafe
    }

    // MARK: - 開始と停止

    func start(novelID: String) {
        stop()
        VoicevoxCacheGenerationState.shared.setEnabled(true, novelID: novelID)
        lock.lock()
        runningNovelIDUnsafe = novelID
        lastStopReasonUnsafe = nil
        lock.unlock()
        // 「放置しておけば作れている」ためには画面を消させない。
        // 消えると背面に落ち、スレッド数が1に絞られて生成が何倍も遅くなる。
        setIdleTimerDisabled(true)
        notifyProgressChanged()

        task = Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let reason = await self.run(novelID: novelID)
            self.finish(reason: reason)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        let wasRunning = runningNovelID != nil
        lock.lock()
        runningNovelIDUnsafe = nil
        lock.unlock()
        if wasRunning {
            setIdleTimerDisabled(false)
            notifyProgressChanged()
        }
    }

    private func finish(reason: StopReason) {
        lock.lock()
        runningNovelIDUnsafe = nil
        lastStopReasonUnsafe = reason
        lock.unlock()
        setIdleTimerDisabled(false)
        AppInformationLogger.AddLog(message: "[VOICEVOX音声生成] \(reason.message)", isForDebug: true)
        notifyProgressChanged()
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = disabled
        }
    }

    private func notifyProgressChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.progressDidChangeNotification, object: nil)
        }
    }

    // MARK: - 本体

    private func run(novelID: String) async -> StopReason {
        guard let start = startPosition(novelID: novelID) else {
            return .failed("読み込む話が見つかりません")
        }
        guard let lastChapterNumber = Self.lastChapterNumber(novelID: novelID) else {
            return .failed("話数が分かりません")
        }

        var chapterNumber = start.chapterNumber
        var blockIndex = start.blockIndex

        while chapterNumber <= lastChapterNumber {
            if Task.isCancelled { return .stoppedByUser }
            if Self.hasEnoughFreeSpace() == false { return .diskFull }

            guard let story = Self.story(novelID: novelID, chapterNumber: chapterNumber) else {
                // 未ダウンロードの話などは飛ばす(あとから落とされたら次回作られる)。
                chapterNumber += 1
                blockIndex = 0
                continue
            }

            let targets = VoicevoxCacheBlockSource.synthesisTargets(story: story)
            var generatedCount = targets.filter { $0.blockIndex < blockIndex }.count

            for target in targets where target.blockIndex >= blockIndex {
                if Task.isCancelled { return .stoppedByUser }
                await waitWhileBackgrounded()
                if Task.isCancelled { return .stoppedByUser }

                // 画面が消えないようにし続ける。読み上げの停止処理などが
                // isIdleTimerDisabled を false に戻す事があるため、都度入れ直す。
                setIdleTimerDisabled(true)

                if VoicevoxDiskCacheStore.shared.contains(novelID: novelID, chapterNumber: chapterNumber, key: target.key) {
                    generatedCount += 1
                    continue
                }
                if Self.hasEnoughFreeSpace() == false { return .diskFull }

                do {
                    let wav = try await VoicevoxCore.shared.synthesizeForDiskCache(text: target.text, styleId: target.styleId)
                    let encoded = try VoicevoxAudioCompressor.encode(wav: wav)
                    try VoicevoxDiskCacheStore.shared.store(
                        novelID: novelID,
                        chapterNumber: chapterNumber,
                        key: target.key,
                        data: encoded,
                        durationSeconds: VoicevoxAudioCompressor.durationSeconds(wav: wav)
                    )
                } catch {
                    // 1ブロックの失敗で全体を止めない(記号だけのブロック等で形態素解析に
                    // 失敗する事がある)。数十分かけた生成が1件で止まる方が困る。
                    AppInformationLogger.AddLog(message: "[VOICEVOX音声生成] 1ブロックの生成に失敗(飛ばします): \(error.localizedDescription)", isForDebug: true)
                }

                generatedCount += 1
                VoicevoxCacheGenerationState.shared.setResumePosition(chapterNumber: chapterNumber, blockIndex: target.blockIndex + 1, novelID: novelID)
                updateProgress(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: targets.count)
            }

            chapterNumber += 1
            blockIndex = 0
            VoicevoxCacheGenerationState.shared.setResumePosition(chapterNumber: chapterNumber, blockIndex: 0, novelID: novelID)
        }
        return .finished
    }

    /// 背面にいる間は生成しない。
    ///
    /// 「起動しっぱなしで放置」させる機能なので、背面に落ちた=利用者が別の事を
    /// 始めた、という事。そのまま作り続けると電池を焼くし、背面のCPU上限で
    /// 何倍も遅くなる(スレッド数が1に絞られる)ので、前景に戻るまで待つ。
    private func waitWhileBackgrounded() async {
        while VoicevoxPrefetchThrottleMonitor.shared.isBackground {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func updateProgress(novelID: String, story: Story, generatedCount: Int, totalCount: Int) {
        let summary = VoicevoxDiskCacheStore.shared.summary(novelID: novelID)
        let progress = VoicevoxCacheGenerationProgress(
            chapterNumber: story.chapterNumber,
            chapterTitle: story.subtitle,
            generatedBlockCount: generatedCount,
            totalBlockCount: totalCount,
            totalAudioSeconds: summary.audioSeconds
        )
        lock.lock()
        progressUnsafe = progress
        lock.unlock()
        notifyProgressChanged()
    }

    // MARK: - 開始位置

    /// 続きから作る。初めてなら「今の再生位置」から。
    private func startPosition(novelID: String) -> VoicevoxCacheGenerationState.Position? {
        if let resume = VoicevoxCacheGenerationState.shared.resumePosition(novelID: novelID) {
            return resume
        }
        return RealmUtil.RealmBlock { (realm) -> VoicevoxCacheGenerationState.Position? in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return nil }
            let chapterNumber = novel.readingChapterNumber ?? 1
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber) else {
                return VoicevoxCacheGenerationState.Position(chapterNumber: chapterNumber, blockIndex: 0)
            }
            // 読んでいる途中なら、その位置を含むブロックから作る。
            // 手前を作っても聴き直さないなら無駄になるため。
            let readLocation = story.readLocation(realm: realm)
            let blockIndex = Self.blockIndex(story: story, displayLocation: readLocation)
            return VoicevoxCacheGenerationState.Position(chapterNumber: chapterNumber, blockIndex: blockIndex)
        }
    }

    /// SpeechBlockSpeaker.SetSpeechLocation() と同じ手順で、表示位置からブロック番号を求める。
    private static func blockIndex(story: Story, displayLocation: Int) -> Int {
        guard displayLocation > 0 else { return 0 }
        var remaining = displayLocation
        for (index, block) in VoicevoxCacheBlockSource.blocks(story: story).enumerated() {
            let length = block.displayText.unicodeScalars.count
            if remaining >= length {
                remaining -= length
                continue
            }
            return index
        }
        return 0
    }

    // MARK: - Realm / ディスク

    private static func story(novelID: String, chapterNumber: Int) -> Story? {
        return RealmUtil.RealmBlock { (realm) -> Story? in
            return RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber)
        }
    }

    private static func lastChapterNumber(novelID: String) -> Int? {
        return RealmUtil.RealmBlock { (realm) -> Int? in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.lastChapterNumber
        }
    }

    static func hasEnoughFreeSpace() -> Bool {
        return freeBytes().map { $0 > minimumFreeBytes } ?? true
    }

    static func freeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }
}
#endif
