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

    /// 誰が始めた生成か。止め方と、途中で待つ条件が変わる。
    enum Mode {
        /// 利用者が明示的に始めた(端末を放置しておく前提)。
        case manual
        /// 読み上げ中に、貯金が心細いので自動で作り足している。
        case followingPlayback
    }

    enum StopReason {
        case finished
        case stoppedByUser
        case limitReached(VoicevoxCacheLimits.StopCause)
        case failed(String)

        var message: String {
            switch self {
            case .finished: return "最後まで作り終えました"
            case .stoppedByUser: return "生成を止めました"
            case .limitReached(let cause): return cause.message
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
    private var runningModeUnsafe: Mode = .manual
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

    var runningMode: Mode {
        lock.lock(); defer { lock.unlock() }
        return runningModeUnsafe
    }

    var progress: VoicevoxCacheGenerationProgress? {
        lock.lock(); defer { lock.unlock() }
        return progressUnsafe
    }

    var lastStopReason: StopReason? {
        lock.lock(); defer { lock.unlock() }
        return lastStopReasonUnsafe
    }

    // MARK: - 開始と停止

    func start(novelID: String, mode: Mode = .manual) {
        stop()
        // 前回の小説の物が残っていると、鍵が食い違って全部作り直しになる。
        speechSettings = nil
        speechSettingsNovelID = nil
        speakerCache = StoryTextClassifier.SpeakerSettingCache()
        loadedStories.removeAll()
        loadedStoriesNovelID = nil
        VoicevoxCacheGenerationState.shared.setEnabled(true, novelID: novelID)
        lock.lock()
        runningNovelIDUnsafe = novelID
        runningModeUnsafe = mode
        lastStopReasonUnsafe = nil
        lock.unlock()
        if mode == .manual {
            // 「放置しておけば作れている」ためには画面を消させない。
            // 消えると背面に落ち、スレッド数が1に絞られて生成が何倍も遅くなる。
            //
            // 読み上げ中の自動生成では触らない。画面を点けっぱなしにするかどうかは
            // 読み上げ側の設定(isNeedDisableIdleTimerWhenSpeechTime)が決めている事なので、
            // ここで横から書き換えるべきではない。
            setIdleTimerDisabled(true)
        }
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
        let wasManual = runningMode == .manual
        lock.lock()
        runningNovelIDUnsafe = nil
        lock.unlock()
        if wasRunning {
            if wasManual { setIdleTimerDisabled(false) }
            ActivityIndicatorManager.disable(id: Self.activityIndicatorID)
            notifyProgressChanged()
        }
    }

    /// 読み上げに追従して自動で走っている分だけを止める。
    /// 利用者が明示的に始めた生成は、読み上げを止めても続ける。
    func stopIfFollowingPlayback() {
        guard runningNovelID != nil, runningMode == .followingPlayback else { return }
        stop()
    }

    private func finish(reason: StopReason) {
        let wasManual = runningMode == .manual
        lock.lock()
        runningNovelIDUnsafe = nil
        lastStopReasonUnsafe = reason
        lock.unlock()
        if wasManual { setIdleTimerDisabled(false) }
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
            if let cause = Self.currentStopCause() { return .limitReached(cause) }

            guard let story = story(novelID: novelID, chapterNumber: chapterNumber) else {
                // 未ダウンロードの話などは飛ばす(あとから落とされたら次回作られる)。
                chapterNumber += 1
                blockIndex = 0
                continue
            }

            let targets = VoicevoxCacheBlockSource.synthesisTargets(story: story, settings: settings(novelID: novelID))
            var generatedCount = targets.filter { $0.blockIndex < blockIndex }.count

            for target in targets where target.blockIndex >= blockIndex {
                if Task.isCancelled { return .stoppedByUser }
                await waitWhilePaused(novelID: novelID, story: story, generatedCount: generatedCount, totalCount: targets.count)
                if Task.isCancelled { return .stoppedByUser }

                // 画面が消えないようにし続ける。読み上げの停止処理などが
                // isIdleTimerDisabled を false に戻す事があるため、都度入れ直す。
                if runningMode == .manual { setIdleTimerDisabled(true) }

                if VoicevoxDiskCacheStore.shared.contains(novelID: novelID, chapterNumber: chapterNumber, key: target.key) {
                    generatedCount += 1
                    continue
                }
                if let cause = Self.currentStopCause() { return .limitReached(cause) }

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
        // 読み上げに追従した自動生成は、背面でこそ効かせたい
        //(背面バッテリー再生こそが、キャッシュが無いと無音だらけになる状況そのもの)。
        // CPU の使い過ぎは CPUガバナーとスレッド数の自動切り替えが抑えるので、
        // ここで止める必要は無い。
        let pausesInBackground = (runningMode == .manual)
        while true {
            if Task.isCancelled { return }
            let isBackground = pausesInBackground && VoicevoxPrefetchThrottleMonitor.shared.isBackground
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
            guard let story = self.story(novelID: novelID, chapterNumber: start.chapterNumber) else {
                self.notifyProgressChanged()
                return
            }
            let targets = VoicevoxCacheBlockSource.synthesisTargets(story: story, settings: self.settings(novelID: novelID))
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

    /// 本文を塊(bulk)単位で先読みしておくための入れ物。
    ///
    /// 本文は100ページ単位で zip + JSON に固めて保存されており、1ページ読むだけでも
    /// その塊を丸ごと展開し直す(実測で1ページあたり約0.28秒)。ページを順に舐める
    /// この処理では、既に作ってあるページを飛ばすだけでもその展開が毎回走ってしまい、
    /// 1000ページの作り直しでは展開だけで5分近くを捨てる事になる。
    /// 塊ごとに1回だけ読んで持っておく。
    private var loadedStories: [Int: Story] = [:]
    private var loadedStoriesNovelID: String?

    /// 読み上げ設定。小説の中では変わらないのに、組み立てには Realm から
    /// 5000件超の読み替え辞書を読む必要があり1回で数百ミリ秒かかる。
    /// ページごとにやり直すと、ページ数に比例して無駄に重くなる。
    private var speechSettings: StoryTextClassifier.StorySpeechSettings?
    private var speechSettingsNovelID: String?
    private var speakerCache = StoryTextClassifier.SpeakerSettingCache()

    private func settings(novelID: String) -> StoryTextClassifier.StorySpeechSettings {
        if speechSettingsNovelID == novelID, let settings = speechSettings { return settings }
        let speakerCache = self.speakerCache
        let settings = RealmUtil.RealmBlock { realm in
            return StoryTextClassifier.GatherStorySpeechSettings(realm: realm, novelID: novelID, speakerCache: speakerCache)
        }
        speechSettings = settings
        speechSettingsNovelID = novelID
        return settings
    }

    private func story(novelID: String, chapterNumber: Int) -> Story? {
        if loadedStoriesNovelID == novelID, let story = loadedStories[chapterNumber] {
            return story
        }
        // その塊(100ページ)ぶんをまとめて読む。
        let bulkFirstChapter = ((chapterNumber - 1) / RealmStoryBulk.bulkCount) * RealmStoryBulk.bulkCount + 1
        let chapterNumbers = Array(bulkFirstChapter..<(bulkFirstChapter + RealmStoryBulk.bulkCount))
        loadedStories = VoicevoxCacheBlockSource.stories(novelID: novelID, chapterNumbers: chapterNumbers)
        loadedStoriesNovelID = novelID
        return loadedStories[chapterNumber]
    }

    private static func lastChapterNumber(novelID: String) -> Int? {
        return RealmUtil.RealmBlock { (realm) -> Int? in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.lastChapterNumber
        }
    }

    /// 今これ以上作ってよいか(駄目ならその理由)。
    /// 容量の合計は毎回ディレクトリを読み直すのではなく、保存層が持っている
    /// 一覧から求まるので、ブロックごとに呼んでも重くない。
    static func currentStopCause() -> VoicevoxCacheLimits.StopCause? {
        return VoicevoxCacheLimits.stopCause(
            usedBytes: Int64(VoicevoxDiskCacheStore.shared.totalSummary().byteCount),
            freeBytes: freeBytes()
        )
    }

    static func freeBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else { return nil }
        return values.volumeAvailableCapacityForImportantUsage
    }
}
#endif
