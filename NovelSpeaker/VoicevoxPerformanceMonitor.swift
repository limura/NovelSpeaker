//
//  VoicevoxPerformanceMonitor.swift
//  NovelSpeaker
//
//  VOICEVOX 合成の実性能(RTF)と、プロセスの CPU 使用率を実測してログに残すための計測器。
//
//  なぜ必要か:
//  バックグラウンド再生中に iOS の「60秒平均 CPU 80%」上限でプロセスが強制終了される
//  問題(bug_type 206 / cpu_resource_fatal)を追っている。実機(iPhone 17 Pro Max /
//  iOS 26.6, バッテリー駆動)では以下の2件を確認している。
//
//    01:26 kill … 48s cpu / 58s = 82%  (先行合成の絞り込み前。再生開始から約1分で死亡)
//    02:31 kill … 48s cpu / 54s = 89%  (絞り込み後。約36分生存してから死亡)
//
//  重要なのは、先行合成を「次の1ブロックだけ」に絞った後の方が CPU 率が高い(82%→89%)事。
//  つまり死因は「先読みし過ぎ」ではなく、再生に追いつくための**定常的な**合成負荷そのもの。
//  36分持ってから死んだのは、合成を回し続けて端末が温まりクロックが落ち、同じ仕事の
//  CPU 率が上がっていった(=ゆっくりした死のスパイラル)ためと考えられる。
//
//  必要な CPU 使用率はおおよそ
//      必要CPU率 = 再生速度倍率 × RTF(1倍音声1秒あたりの CPU 秒)
//  で決まるため、RTF と実 CPU 率を実測できれば
//   - 背面・バッテリー時に RTF がどれだけ悪化するか
//   - 発熱でどう推移するか
//   - 上限 80% を割るには再生速度をいくつにすればよいか
//   - どれだけの「貯金」(合成済みバッファ)が要るか
//  が定量的に判断できる。本ファイルはその計測のみを行い、制御は行わない
//  (ここで得たデータを元に、後段で適応的な再生速度制御などを設計する)。
//
//  なお本計測器は、将来そのまま制御側のセンサーとして流用できるように作ってある。
//

import Foundation
import Darwin

/// プロセス全体の CPU 使用時間を取得するユーティリティ。
enum ProcessCPUClock {
    /// mach absolute time → 秒 への換算係数(初回に一度だけ取得)。
    private static let timebaseSecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return 0 }
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }()

    /// このプロセスが消費した CPU 時間(user+system, 全スレッドの合計)を秒で返す。
    /// OS のバックグラウンド CPU 上限も「全スレッド合計の CPU 時間 ÷ 実時間」で判定されるため、
    /// これと同じ土俵の値になる(1コアを100%使い切っている状態が 1.0)。
    static func totalCPUSeconds() -> Double? {
        var info = task_absolutetime_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_absolutetime_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_ABSOLUTETIME_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS, timebaseSecondsPerTick > 0 else { return nil }
        let ticks = Double(info.total_user) + Double(info.total_system)
        return ticks * timebaseSecondsPerTick
    }
}

/// 直近 windowSeconds 間の CPU 使用率を求めるためのサンプル窓(純粋ロジック・テスト可能)。
struct CPUDutyWindow {
    struct Sample: Equatable {
        let wallTime: Double
        let cpuSeconds: Double
    }

    let windowSeconds: Double
    private(set) var samples: [Sample] = []

    init(windowSeconds: Double = 60.0) {
        self.windowSeconds = windowSeconds
    }

    mutating func add(wallTime: Double, cpuSeconds: Double) {
        samples.append(Sample(wallTime: wallTime, cpuSeconds: cpuSeconds))
        // 窓からはみ出した古いサンプルを捨てる。ただし「窓の左端の基準点」として
        // 1つだけは窓の外に残す必要があるので、2番目が窓に入るまでしか削らない。
        while samples.count >= 2, let newest = samples.last, newest.wallTime - samples[1].wallTime >= windowSeconds {
            samples.removeFirst()
        }
    }

    /// 直近の窓での CPU 使用率(1.0 = 1コアを100%使い切り)。サンプルが足りなければ nil。
    var dutyRatio: Double? {
        guard let oldest = samples.first, let newest = samples.last else { return nil }
        let wallDelta = newest.wallTime - oldest.wallTime
        guard wallDelta > 0 else { return nil }
        return (newest.cpuSeconds - oldest.cpuSeconds) / wallDelta
    }

    /// 現在の窓が実際に何秒ぶんを覆っているか(短いうちは dutyRatio の信頼度が低い)。
    var spannedSeconds: Double {
        guard let oldest = samples.first, let newest = samples.last else { return 0 }
        return newest.wallTime - oldest.wallTime
    }
}

/// RTF(実時間比)の集計(純粋ロジック・テスト可能)。
/// RTF = 合成に使った CPU 秒 ÷ 生成された音声の秒数(1倍速換算)。
/// 1.0 未満なら「実時間より速く作れている」。
struct RTFAccumulator {
    private(set) var totalAudioSeconds: Double = 0
    private(set) var totalCPUSeconds: Double = 0
    private(set) var totalWallSeconds: Double = 0
    private(set) var sampleCount: Int = 0
    /// 直近のサンプルだけの RTF も見たいので、末尾数件を保持する。
    private(set) var recentRTFs: [Double] = []
    private let recentCapacity: Int

    init(recentCapacity: Int = 10) {
        self.recentCapacity = recentCapacity
    }

    mutating func add(audioSeconds: Double, cpuSeconds: Double, wallSeconds: Double) {
        guard audioSeconds > 0 else { return }
        totalAudioSeconds += audioSeconds
        totalCPUSeconds += cpuSeconds
        totalWallSeconds += wallSeconds
        sampleCount += 1
        recentRTFs.append(cpuSeconds / audioSeconds)
        if recentRTFs.count > recentCapacity {
            recentRTFs.removeFirst(recentRTFs.count - recentCapacity)
        }
    }

    /// 累計での RTF(CPU秒/音声秒)。
    var cpuRTF: Double? {
        guard totalAudioSeconds > 0 else { return nil }
        return totalCPUSeconds / totalAudioSeconds
    }

    /// 実時間ベースの RTF(実時間秒/音声秒)。並列合成があると cpuRTF より小さくなる。
    var wallRTF: Double? {
        guard totalAudioSeconds > 0 else { return nil }
        return totalWallSeconds / totalAudioSeconds
    }

    var recentCPURTFAverage: Double? {
        guard recentRTFs.isEmpty == false else { return nil }
        return recentRTFs.reduce(0, +) / Double(recentRTFs.count)
    }

    /// この RTF のもとで、指定した再生速度を維持するのに必要な CPU 使用率。
    /// 必要CPU率 = 再生速度倍率 × RTF
    static func requiredCPUDuty(rtf: Double, playbackRate: Double) -> Double {
        return rtf * playbackRate
    }

    /// この RTF のもとで、CPU 使用率を上限以下に保てる最大の再生速度倍率。
    static func sustainablePlaybackRate(rtf: Double, cpuDutyLimit: Double) -> Double? {
        guard rtf > 0 else { return nil }
        return cpuDutyLimit / rtf
    }
}

/// 再生の「途切れ」を数える集計(純粋ロジック・テスト可能)。
///
/// 実機の測定で、未再生の貯金が108秒もあるのに再生できていた時間が全体の約半分しか
/// 無い、という結果が出た。合成が間に合っていないのであれば貯金は減るはずで、
/// 貯金が増え続けているのに無音がある以上、原因は合成速度ではなく再生側にある。
/// ここでは「発話しているつもりなのに音が出ていない時間」を直接数えて、
/// 再生パイプラインの取りこぼしを定量化する。
///
/// なお「間の設定」による意図的なポーズは無音として数えない(それは仕様どおりの間なので)。
struct PlaybackGapAccumulator {
    private(set) var totalPlaybackWallSeconds: Double = 0
    private(set) var totalGapSeconds: Double = 0
    private(set) var gapCount: Int = 0
    private(set) var maxGapSeconds: Double = 0
    private(set) var cacheHitCount: Int = 0
    private(set) var cacheMissCount: Int = 0
    private(set) var totalMissWaitSeconds: Double = 0
    /// MISS のうち「先行合成に予約はされていたが間に合わなかった」件数(= 時間の問題)。
    private(set) var missQueuedCount: Int = 0
    /// MISS のうち「そもそも先行合成に予約されていなかった」件数(= 取りこぼしの不具合)。
    private(set) var missNotQueuedCount: Int = 0

    mutating func addMissCause(wasQueuedForPrefetch: Bool) {
        if wasQueuedForPrefetch { missQueuedCount += 1 } else { missNotQueuedCount += 1 }
    }

    /// 1ブロックぶんの音声を実際に鳴らした実時間(倍速適用後)。
    mutating func addPlayback(wallSeconds: Double) {
        guard wallSeconds > 0 else { return }
        totalPlaybackWallSeconds += wallSeconds
    }

    /// ブロックとブロックの間にできた「意図しない無音」の秒数。
    mutating func addGap(seconds: Double) {
        guard seconds > 0 else { return }
        totalGapSeconds += seconds
        gapCount += 1
        maxGapSeconds = max(maxGapSeconds, seconds)
    }

    /// 再生のために合成を要求した時の結果(先行合成が間に合っていたか)。
    mutating func addSynthesisRequest(wasCacheHit: Bool, waitSeconds: Double) {
        if wasCacheHit {
            cacheHitCount += 1
        } else {
            cacheMissCount += 1
            totalMissWaitSeconds += max(0, waitSeconds)
        }
    }

    /// 発話していたはずの時間のうち、無音だった割合。これが本丸の指標。
    var silenceRatio: Double? {
        let total = totalPlaybackWallSeconds + totalGapSeconds
        guard total > 0 else { return nil }
        return totalGapSeconds / total
    }

    /// 再生時に先行合成が間に合っていた割合。
    var cacheHitRatio: Double? {
        let total = cacheHitCount + cacheMissCount
        guard total > 0 else { return nil }
        return Double(cacheHitCount) / Double(total)
    }

    var averageGapSeconds: Double? {
        guard gapCount > 0 else { return nil }
        return totalGapSeconds / Double(gapCount)
    }

    /// キャッシュMISS1回あたりの平均待ち時間(MISSが無音の主因かどうかの判別に使う)。
    var averageMissWaitSeconds: Double? {
        guard cacheMissCount > 0 else { return nil }
        return totalMissWaitSeconds / Double(cacheMissCount)
    }
}

/// 実測値を集めてログに出す本体。
final class VoicevoxPerformanceMonitor {
    static let shared = VoicevoxPerformanceMonitor()

    /// VOICEVOX の出力フォーマット(24kHz / mono / 16bit)。音声秒数の算出に使う。
    static let outputSampleRate: Double = 24000
    static let outputBytesPerFrame: Double = 2
    static let wavHeaderByteCount = 44

    /// OS がバックグラウンドアプリに課す CPU 上限(60秒平均で 80%)。
    static let osBackgroundCPUDutyLimit: Double = 0.80
    static let osBackgroundCPUWindowSeconds: Double = 60.0

    private let lock = NSLock()
    private var dutyWindow = CPUDutyWindow(windowSeconds: osBackgroundCPUWindowSeconds)
    private var rtf = RTFAccumulator()
    private var lastLoggedAt: Double = 0
    private var lastPersistedAt: Double = 0
    /// 現在の再生速度倍率(VoicevoxSpeaker が設定時に教えてくれる)。
    private var playbackRate: Double = 1.0
    /// 未再生の「貯金」秒数(SpeechBlockSpeaker が先読み更新時に教えてくれる)。
    /// キャッシュ全体の秒数と違い、再生済みのぶんを含まない実際の余裕。
    private var unplayedLeadSeconds: Double = 0
    /// 再生の途切れ(意図しない無音)の集計。
    private var gaps = PlaybackGapAccumulator()
    /// 直前に「音を鳴らし終えた」時刻と、その時点で予定されていた「間の設定」の秒数。
    ///
    /// これは話者(VoicevoxSpeakerインスタンス)ごとではなく **アプリ全体で1つ** でなければ
    /// ならない。会話文で話者が変わると別インスタンスが鳴るため、インスタンスごとに
    /// 持つと「他の話者が喋っている間ずっと、この話者の無音」として二重計上され、
    /// 実測で経過時間(約400秒)より長い無音(631秒)が計上される・最大無音が170秒になる、
    /// といった明らかに誤った値が出る。発話自体は MultiVoiceSpeaker が直列化しているので、
    /// グローバルに1つ持つのが正しい。
    private var lastPlaybackEndedAt: Date? = nil
    private var lastIntentionalDelay: TimeInterval = 0
    /// 直近の出来事(先行合成の開始/完了・発話発注・HIT/MISS)の記録。
    /// 無音が起きた瞬間の前後で「先行合成が何をしていたか」を後から追うためのもの。
    /// NSLog だけだと Console.app 経由でしか読めず、実機を無接続で測る今回の運用では
    /// 回収できないため、長い無音を検出した時にまとめてアプリ内ログへ吐き出す。
    private var eventRing: [(at: Date, text: String)] = []
    private let eventRingCapacity = 40
    /// トレースを吐き出す無音の長さのしきい値と、吐き出し過ぎを防ぐ間隔。
    private let traceDumpGapThreshold: Double = 3.0
    private var lastTraceDumpAt: Date? = nil
    /// ログが出過ぎないように、最短でもこの間隔をあける。
    private let logIntervalSeconds: Double = 10.0
    /// アプリ内ログ(設定画面から見られる方)へ残す間隔。
    /// AppInformationLogger.AddLog は呼び出しスレッドで UserDefaults の
    /// 配列全体(最大1000件)を読み書きする同期処理なので、合成スレッドを塞がないよう
    /// NSLog より粗い間隔にし、かつ書き込み自体は別キューに逃がす。
    private let persistIntervalSeconds: Double = 30.0
    /// アプリ内ログへの書き込みを合成スレッドから追い出すための専用キュー。
    private let persistQueue = DispatchQueue(label: "NovelSpeaker.VoicevoxPerf.persist", qos: .utility)

    private init() {}

    /// 現在の再生速度倍率を記録する。「必要CPU率 = 再生速度倍率 × RTF」の判断に使う。
    func updatePlaybackRate(_ rate: Double) {
        lock.lock()
        playbackRate = rate
        lock.unlock()
    }

    /// 1ブロックぶんの音声を実際に鳴らした実時間(倍速適用後)を記録する。
    func recordPlayback(wallSeconds: Double) {
        lock.lock()
        gaps.addPlayback(wallSeconds: wallSeconds)
        lock.unlock()
    }

    /// 出来事を記録する(無音時のトレース用)。
    func recordEvent(_ text: String) {
        lock.lock()
        eventRing.append((at: Date(), text: text))
        if eventRing.count > eventRingCapacity {
            eventRing.removeFirst(eventRing.count - eventRingCapacity)
        }
        lock.unlock()
    }

    /// あるブロックの音声を鳴らし終えた事を記録する(次に音が出るまでが無音になる)。
    /// - Parameter intentionalDelay: この後に入る「間の設定」由来の意図的なポーズ秒数。
    func notePlaybackEnded(intentionalDelay: TimeInterval) {
        lock.lock()
        lastPlaybackEndedAt = Date()
        lastIntentionalDelay = intentionalDelay
        lock.unlock()
    }

    /// ユーザー操作による停止/一時停止など、無音として数えるべきでない中断を記録する。
    func notePlaybackInterrupted() {
        lock.lock()
        lastPlaybackEndedAt = nil
        lastIntentionalDelay = 0
        lock.unlock()
    }

    /// これから音を鳴らす事を記録し、直前の再生終了からの間隔を「意図しない無音」として数える。
    func notePlaybackStarting() {
        lock.lock()
        guard let endedAt = lastPlaybackEndedAt else {
            lock.unlock()
            return
        }
        let seconds = Date().timeIntervalSince(endedAt) - lastIntentionalDelay
        lastPlaybackEndedAt = nil
        lastIntentionalDelay = 0
        gaps.addGap(seconds: seconds)
        let total = gaps.totalGapSeconds
        let count = gaps.gapCount
        lock.unlock()
        if seconds >= 0.5 {
            NSLog("NovelSpeaker.VoicevoxPerf: [\(VoicevoxCore.logTimestamp())] [無音検出] \(String(format: "%.2f", seconds))秒 (通算 \(String(format: "%.1f", total))秒 / \(count)回)")
        }
        if seconds >= traceDumpGapThreshold {
            dumpTraceIfNeeded(gapSeconds: seconds)
        }
    }

    /// 長い無音が起きた時に、その直前までの出来事をアプリ内ログへ1件としてまとめて残す。
    /// (1回の無音につき1エントリ。連続して出し過ぎないよう間隔を空ける)
    private func dumpTraceIfNeeded(gapSeconds: Double) {
        let now = Date()
        lock.lock()
        if let last = lastTraceDumpAt, now.timeIntervalSince(last) < 20 {
            lock.unlock()
            return
        }
        lastTraceDumpAt = now
        let events = eventRing
        lock.unlock()
        guard let first = events.first?.at else { return }
        var lines: [String] = []
        for event in events {
            let offset = event.at.timeIntervalSince(first)
            lines.append(String(format: "  +%.2f %@", offset, event.text))
        }
        let body = "[VOICEVOX無音トレース] " + String(format: "%.2f", gapSeconds) + "秒の無音。直前の出来事:\n" + lines.joined(separator: "\n")
        persistQueue.async {
            AppInformationLogger.AddLog(message: body, isForDebug: true)
        }
    }

    /// キャッシュMISS の原因(予約済みで未完了か、そもそも未予約か)を記録する。
    func recordPlaybackCacheMiss(wasQueuedForPrefetch: Bool) {
        lock.lock()
        gaps.addMissCause(wasQueuedForPrefetch: wasQueuedForPrefetch)
        lock.unlock()
    }

    /// 再生のために合成を要求した結果(先行合成が間に合っていたか)を記録する。
    func recordPlaybackSynthesisRequest(wasCacheHit: Bool, waitSeconds: Double) {
        lock.lock()
        gaps.addSynthesisRequest(wasCacheHit: wasCacheHit, waitSeconds: waitSeconds)
        lock.unlock()
    }

    /// 未再生の貯金(合成済みで、まだ再生していない音声の秒数)を記録する。
    /// ディスクキャッシュを何秒ぶん用意すべきかの判断に直結する数値。
    func updateUnplayedLeadSeconds(_ seconds: Double) {
        lock.lock()
        unplayedLeadSeconds = seconds
        lock.unlock()
    }

    /// WAV のバイト数から音声の秒数(1倍速換算)を求める。
    static func audioSeconds(wavByteCount: Int) -> Double {
        let payload = Double(max(0, wavByteCount - wavHeaderByteCount))
        return payload / (outputSampleRate * outputBytesPerFrame)
    }

    /// 合成1回ぶんの実測値を記録する。`performSynthesize` の前後で呼ぶ。
    /// - Note: cpuSeconds はプロセス全体の CPU 時間の差分なので、合成以外の処理も
    ///   わずかに含む。ただし合成中は合成が支配的なうえ、onnxruntime が内部で複数スレッドを
    ///   使う分も取りこぼさずに数えられるため、この用途ではこちらが適切。
    func recordSynthesis(wavByteCount: Int, cpuSeconds: Double, wallSeconds: Double, styleId: UInt32) {
        let audio = Self.audioSeconds(wavByteCount: wavByteCount)
        guard audio > 0 else { return }
        lock.lock()
        rtf.add(audioSeconds: audio, cpuSeconds: cpuSeconds, wallSeconds: wallSeconds)
        let snapshotRTF = rtf
        lock.unlock()
        let instantRTF = cpuSeconds / audio
        NSLog("NovelSpeaker.VoicevoxPerf: [\(VoicevoxCore.logTimestamp())] [合成計測] styleId=\(styleId) 音声=\(String(format: "%.2f", audio))秒 CPU=\(String(format: "%.2f", cpuSeconds))秒 実時間=\(String(format: "%.2f", wallSeconds))秒 RTF=\(String(format: "%.3f", instantRTF)) 累計RTF=\(String(format: "%.3f", snapshotRTF.cpuRTF ?? 0))")
        sampleAndLogIfNeeded()
    }

    /// 現在のプロセス CPU 使用率をサンプリングし、必要ならまとめてログに出す。
    /// 合成のたびに呼ばれるので、再生中は自然に定期サンプリングになる。
    func sampleAndLogIfNeeded(force: Bool = false) {
        guard let cpuSeconds = ProcessCPUClock.totalCPUSeconds() else { return }
        let now = Date().timeIntervalSince1970
        lock.lock()
        dutyWindow.add(wallTime: now, cpuSeconds: cpuSeconds)
        let duty = dutyWindow.dutyRatio
        let spanned = dutyWindow.spannedSeconds
        let shouldLog = force || (now - lastLoggedAt) >= logIntervalSeconds
        if shouldLog { lastLoggedAt = now }
        let shouldPersist = shouldLog && ((now - lastPersistedAt) >= persistIntervalSeconds)
        if shouldPersist { lastPersistedAt = now }
        let snapshotRTF = rtf
        let currentPlaybackRate = playbackRate
        let currentLead = unplayedLeadSeconds
        let snapshotGaps = gaps
        lock.unlock()
        guard shouldLog else { return }

        let throttle = VoicevoxPrefetchThrottleMonitor.shared
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalText: String
        switch thermal {
        case .nominal: thermalText = "nominal"
        case .fair: thermalText = "fair"
        case .serious: thermalText = "serious"
        case .critical: thermalText = "critical"
        @unknown default: thermalText = "unknown"
        }

        var fields: [String] = []
        fields.append("状態=\(throttle.isBackground ? "背面" : "前景")")
        fields.append("電源=\(throttle.isOnExternalPower ? "AC" : "バッテリー")")
        fields.append("低電力=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        fields.append("熱=\(thermalText)")
        if let duty = duty {
            // OS の判定と同じ「60秒平均の CPU 率」。0.80 を超えると背面では殺される。
            fields.append("CPU率=\(String(format: "%.1f", duty * 100))%(直近\(String(format: "%.0f", spanned))秒)")
            fields.append("上限まで=\(String(format: "%+.1f", (Self.osBackgroundCPUDutyLimit - duty) * 100))pt")
        }
        // どのスレッド数設定での実測値かがログだけで判別できるようにする(比較計測用)。
        let threads = VoicevoxCore.configuredCPUNumThreads
        fields.append("スレッド数=\(threads == 0 ? "自動" : "\(threads)")")
        fields.append("再生速度=\(String(format: "%.2f", currentPlaybackRate))倍")
        if let cpuRTF = snapshotRTF.cpuRTF {
            fields.append("累計RTF=\(String(format: "%.3f", cpuRTF))")
            // 「必要CPU率 = 再生速度倍率 × RTF」。これが 80% を超えていると背面では詰む。
            let required = RTFAccumulator.requiredCPUDuty(rtf: cpuRTF, playbackRate: currentPlaybackRate)
            fields.append("必要CPU率=\(String(format: "%.1f", required * 100))%")
            // この RTF なら、上限 80% を割るのに再生速度をいくつまでにできるか。
            if let sustainable = RTFAccumulator.sustainablePlaybackRate(rtf: cpuRTF, cpuDutyLimit: Self.osBackgroundCPUDutyLimit) {
                fields.append("持続可能速度=\(String(format: "%.2f", sustainable))倍")
            }
        }
        if let recent = snapshotRTF.recentCPURTFAverage {
            fields.append("直近RTF=\(String(format: "%.3f", recent))")
        }
        fields.append("合成回数=\(snapshotRTF.sampleCount)")
        fields.append("生成音声計=\(String(format: "%.1f", snapshotRTF.totalAudioSeconds))秒")
        // 実際の余裕(未再生ぶんだけ)と、キャッシュ全体(再生済みも含む)を区別して出す。
        // 「発話しているつもりなのに音が出ていない時間」の割合。合成速度とは別の、
        // 再生パイプライン由来の取りこぼしを見るための本丸の指標。
        if let silence = snapshotGaps.silenceRatio {
            fields.append("無音率=\(String(format: "%.1f", silence * 100))%")
            fields.append("無音計=\(String(format: "%.1f", snapshotGaps.totalGapSeconds))秒/\(snapshotGaps.gapCount)回")
            if let average = snapshotGaps.averageGapSeconds {
                fields.append("平均無音=\(String(format: "%.2f", average))秒")
            }
            fields.append("最大無音=\(String(format: "%.2f", snapshotGaps.maxGapSeconds))秒")
        }
        if let hitRatio = snapshotGaps.cacheHitRatio {
            fields.append("再生時HIT率=\(String(format: "%.1f", hitRatio * 100))%(\(snapshotGaps.cacheHitCount)/\(snapshotGaps.cacheHitCount + snapshotGaps.cacheMissCount))")
            if let missWait = snapshotGaps.averageMissWaitSeconds {
                fields.append("MISS平均待ち=\(String(format: "%.2f", missWait))秒")
            }
            // MISS の内訳。予約済みなら「間に合わなかった」= 時間の問題、
            // 未予約なら「先読みが取りこぼした」= ロジックの不具合。
            fields.append("MISS内訳=予約済\(snapshotGaps.missQueuedCount)/未予約\(snapshotGaps.missNotQueuedCount)")
        }
        fields.append("未再生の貯金=\(String(format: "%.1f", currentLead))秒")
        fields.append("キャッシュ計=\(String(format: "%.1f", VoicevoxCore.shared.cachedAudioSecondsForLogging()))秒")

        let line = fields.joined(separator: " ")
        NSLog("NovelSpeaker.VoicevoxPerf: [\(VoicevoxCore.logTimestamp())] [状況] \(line)")

        // Mac に繋がずに実機で測れるよう、アプリ内ログ(設定→「アプリ内エラーのお知らせ
        // (デバッグ用も含む)」から閲覧・コピーできる)にも残す。USB接続すると AC 給電になり
        // そもそもバックグラウンドCPU上限が適用されなくなるため、無線/非接続で測れる事が重要。
        if shouldPersist {
            persistQueue.async {
                AppInformationLogger.AddLog(message: "[VOICEVOX性能] \(line)", isForDebug: true)
            }
        }
    }

    /// テスト用に集計をリセットする。
    func resetForTesting() {
        lock.lock()
        dutyWindow = CPUDutyWindow(windowSeconds: Self.osBackgroundCPUWindowSeconds)
        rtf = RTFAccumulator()
        gaps = PlaybackGapAccumulator()
        lastPlaybackEndedAt = nil
        lastIntentionalDelay = 0
        lastLoggedAt = 0
        lock.unlock()
    }
}
