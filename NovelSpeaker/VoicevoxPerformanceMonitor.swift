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
        fields.append("合成済み貯金=\(String(format: "%.1f", VoicevoxCore.shared.cachedAudioSecondsForLogging()))秒")

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
        lastLoggedAt = 0
        lock.unlock()
    }
}
