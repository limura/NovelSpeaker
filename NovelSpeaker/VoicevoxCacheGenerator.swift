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

    /// 画面上部の活動インジケータ(小説の更新確認でも使っている物)に出すための識別子。
    /// どの画面にいても「今CPUを使っている」事が分かるようにする。
    private static let activityIndicatorID = "VoicevoxCacheGenerator"

    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var runningNovelIDUnsafe: String?
    private var progressUnsafe: VoicevoxCacheGenerationProgress?
    private var lastStopReasonUnsafe: StopReason?
    /// 進捗表示を組み立てる時に使う、生成中ずっと変わらない情報。
    private var lastChapterNumberUnsafe: Int?

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
        ActivityIndicatorManager.enable(id: Self.activityIndicatorID)

        // 最初の1ブロックが出来るまで進捗が空だと、押した直後に
        // 「生成中」としか出ず「本当に動いているのか」が分からない
        //(1ブロックに数十秒かかる端末があるので、その間ずっと不安になる)。
        // 先に 0% の進捗を出しておく。
        publishInitialProgress(novelID: novelID)

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
            ActivityIndicatorManager.disable(id: Self.activityIndicatorID)
            notifyProgressChanged()
        }
    }

    private func finish(reason: StopReason) {
        lock.lock()
        runningNovelIDUnsafe = nil
        lastStopReasonUnsafe = reason
        lock.unlock()
        setIdleTimerDisabled(false)
        ActivityIndicatorManager.disable(id: Self.activityIndicatorID)
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
        lock.lock()
        lastChapterNumberUnsafe = lastChapterNumber
        lock.unlock()

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
                await waitWhilePaused(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: targets.count)
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
                updateProgress(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: targets.count)
            }

            chapterNumber += 1
            blockIndex = 0
        }
        return .finished
    }

    /// 生成を進めてよくなるまで待つ。止めるのではなく待つのは、
    /// 「数十分かけて作っている途中で勝手に終わっていた」方が困るため
    /// (待っている間は理由を進捗に出すので、止まって見えても不安にならない)。
    ///
    ///  - 背面にいる間: 「起動しっぱなしで放置」させる機能なので、背面に落ちた
    ///    = 利用者が別の事を始めた、という事。そのまま作り続けると電池を焼くし、
    ///    背面のCPU上限でスレッド数が1に絞られて何倍も遅くなる。
    ///  - 小説の更新確認(ダウンロード)中: 更新確認自体がかなり重い処理で、
    ///    同時に走らせると両方が遅くなる。生成は急ぐ物ではないので譲る。
    ///    利用者が明示的に始めた生成を勝手に終わらせはせず、確認が終われば自分で再開する。
    private func waitWhilePaused(novelID: String, story: Story, generatedCount: Int, totalCount: Int) async {
        var didPause = false
        while true {
            if Task.isCancelled { return }
            let isBackground = VoicevoxPrefetchThrottleMonitor.shared.isBackground
            let isDownloading = NovelDownloadQueue.shared.GetCurrentDownloadCount() > 0
            if isBackground == false && isDownloading == false { break }
            updateProgress(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: totalCount,
                           isPausedByBackground: isBackground, isPausedByDownload: isBackground == false && isDownloading)
            didPause = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        if didPause {
            updateProgress(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: totalCount)
        }
    }

    private func updateProgress(novelID: String, story: Story, generatedCount: Int, totalCount: Int,
                                isPausedByBackground: Bool = false, isPausedByDownload: Bool = false) {
        let summary = VoicevoxDiskCacheStore.shared.summary(novelID: novelID)
        let generatedChapterCount = VoicevoxDiskCacheStore.shared.chapterNumbers(novelID: novelID).count
        lock.lock()
        let lastChapterNumber = lastChapterNumberUnsafe
        lock.unlock()
        let progress = VoicevoxCacheGenerationProgress(
            chapterNumber: story.chapterNumber,
            chapterTitle: story.subtitle,
            generatedBlockCount: generatedCount,
            totalBlockCount: totalCount,
            totalAudioSeconds: summary.audioSeconds,
            lastChapterNumber: lastChapterNumber,
            generatedChapterCount: generatedChapterCount,
            isPausedByBackground: isPausedByBackground,
            isPausedByDownload: isPausedByDownload
        )
        lock.lock()
        progressUnsafe = progress
        lock.unlock()
        notifyProgressChanged()
    }

    /// 開始直後に出す進捗。
    /// 最初の1ブロックが出来るまで何も出ないと、押した直後に「本当に動いているのか」が
    /// 分からない(1ブロックに数十秒かかる端末がある)。
    private func publishInitialProgress(novelID: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let start = self.startPosition(novelID: novelID) else {
                self.notifyProgressChanged()
                return
            }
            let lastChapterNumber = Self.lastChapterNumber(novelID: novelID)
            self.lock.lock()
            self.lastChapterNumberUnsafe = lastChapterNumber
            self.lock.unlock()
            guard let story = Self.story(novelID: novelID, chapterNumber: start.chapterNumber) else {
                self.notifyProgressChanged()
                return
            }
            let targets = VoicevoxCacheBlockSource.synthesisTargets(story: story)
            let generatedCount = targets.filter { $0.blockIndex < start.blockIndex }.count
            self.updateProgress(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: targets.count)
        }
    }

    // MARK: - 開始位置

    /// **常に「今の読み上げ位置」から**始める。前回の続きからではない。
    ///
    /// 前回の到達点から再開すると、読み上げ位置を前に戻してから生成を始めた時に
    /// 「読んでいる所ではなく、ずっと先の続きが作られる」事になり、期待と食い違う。
    /// 既に作ってある分は `contains` で即座に飛ばせる(音声を読まずに判定できる)ので、
    /// 作成済みの範囲を通り抜けるコストはページの分割処理だけで済む。
    /// これで「読んでいる所から先を埋める」という一貫した意味になり、
    /// 「どこから作ったか」を覚えておく必要も無くなる。
    private func startPosition(novelID: String) -> VoicevoxCacheGenerationState.Position? {
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
