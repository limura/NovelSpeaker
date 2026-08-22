//
//  VoicevoxCPUUsageReporter.swift
//  NovelSpeaker
//
//  「背面でCPUを使い過ぎて強制終了された」時の切り分けのための計測。
//
//  なぜ要るのか:
//  2026-08-21 の実機で2回強制終了されたが、片方(充電中)は原因が特定できた一方、
//  もう片方(バッテリー・背面)は **CPU予算(VoicevoxCPUGovernor)が効いているはずの
//  条件なのに 94% まで上がっていた**。ここから先は
//   - そもそもガバナーが効いていなかったのか
//   - 効いていたが見積りが甘くて足りなかったのか
//   - 合成以外(再生・保存など)の CPU が乗っていたのか
//  のどれなのかを、クラッシュレポートだけでは決められない。
//
//  ガバナーは **合成呼び出しの CPU 秒しか台帳に持っていない**が、
//  OS が見るのは**プロセス全体**の CPU である。この差が犯人かどうかも、
//  実際に両方を並べて記録しないと分からない。
//
//  そこで、合成のたびに
//   - プロセス全体の直近60秒の CPU 使用率(= OS が見ているものと同じ土俵)
//   - ガバナーが効く条件だったか、実際に何秒待たせたか
//   - 端末の熱状態(熱で単価が上がると見積りが置いていかれる)
//   - 見積りと実測のズレ
//  を1行にして「アプリ内エラーのお知らせ(デバッグ用)」に残す。
//
//  常時ログを吐くと邪魔なので、**「今までで一番悪かった時」だけ**を残す。
//  ただしそれだけだと、使用率が頭打ちになった後に一行も出なくなる。
//  そこで**一定時間ごと(と熱状態が変わった時)に、その間の平均を1行だけ**足す。
//  「熱を持ってから何倍速で作れていたのか」は、そこにしか残らない。
//
//  ここで dedupeKey は使えない。AppInformationLogger の dedupe は
//  「最初のログの内容を残して回数だけ増やす」実装なので、
//  それだと起動直後のまだCPUを使っていない値が残り、
//  **肝心の一番危なかった時の数字が消えてしまう**。
//  代わりに、これまでの最悪値を上回った時にだけ1件足す。
//  最悪値は単調に増えるので件数は増え続けない(実際には数件で止まる)。
//

import Foundation

final class VoicevoxCPUUsageReporter {
    static let shared = VoicevoxCPUUsageReporter()

    /// OS の判定窓と同じ。これと同じ長さで使用率を出さないと比較にならない。
    static let windowSeconds: Double = 60
    /// これを下回っている間は、最悪値を更新しても記録しない(平常運転なので見る価値が無い)。
    /// OS の上限は 80% なので、その手前から見えるようにしておく。
    static let reportFloorUtilization: Double = 0.50
    /// 前回残した最悪値をこれだけ上回ったら記録する。
    /// 少しずつ更新される度に1件増えるのを防ぐ。
    static let worseningStep: Double = 0.05

    private struct Sample {
        let uptime: Double
        let cpuSeconds: Double
    }

    private let lock = NSLock()
    private var samples: [Sample] = []
    /// これまでに記録した中で最も悪かった使用率。
    private var reportedWorstUtilization: Double = 0
    /// 一度も記録していない間は、最初の1件を必ず残す(仕組みが動いている事の確認用)。
    private var hasReportedOnce = false

    /// 定期の要約の間隔。
    static let summaryIntervalSeconds: Double = 300

    /// 前回の要約から今までの積み上げ。
    private struct Summary {
        var count = 0
        var characterCount = 0
        var audioSeconds: Double = 0
        var wallSeconds: Double = 0
        var cpuSeconds: Double = 0
        var waitedSeconds: Double = 0
        var slowestSpeed: Double = .greatestFiniteMagnitude
    }
    private var summary = Summary()
    private var lastSummaryReportedAt: Double? = nil
    private var lastSummaryThermalState: ProcessInfo.ThermalState? = nil

    private init() {}

    /// プロセス全体の、直近 `windowSeconds` の CPU 使用率。
    ///
    /// 1.0 が「1コアを使い切っている」状態。OS の背面上限もこの土俵で
    /// 「60秒平均 80%」と判定される。
    /// 窓を埋めるだけの記録がまだ無い場合は nil。
    func currentUtilization(at now: Double = ProcessInfo.processInfo.systemUptime) -> Double? {
        guard let cpu = ProcessCPUClock.totalCPUSeconds() else { return nil }
        lock.lock()
        defer { lock.unlock() }
        samples.append(Sample(uptime: now, cpuSeconds: cpu))
        // 窓の外は捨てるが、窓の左端を跨ぐ1件は残す(それが無いと差分を取れない)。
        if let lastOutsideIndex = samples.lastIndex(where: { $0.uptime <= now - Self.windowSeconds }),
           lastOutsideIndex > 0 {
            samples.removeFirst(lastOutsideIndex)
        }
        guard let oldest = samples.first else { return nil }
        let elapsed = now - oldest.uptime
        // 窓の半分も溜まっていないうちは、値が跳ねるので出さない。
        guard elapsed >= Self.windowSeconds / 2 else { return nil }
        return (cpu - oldest.cpuSeconds) / elapsed
    }

    /// 合成1本ぶんの結果を記録する。必要なら「お知らせ」に1行残す。
    ///
    /// - Parameters:
    ///   - characterCount: 合成した文字数。
    ///   - estimatedCPUSeconds: ガバナーの見積り。
    ///   - actualCPUSeconds: 実際にかかった CPU 秒。
    ///   - audioSeconds: 出来上がった音声の長さ。
    ///     これが無いと「実時間の何倍の速さで作れているのか」が分からない。
    ///     読み上げ速度がこれを上回っていれば、貯金は必ず減っていく。
    ///   - actualWallSeconds: 実際にかかった時間(壁時計)。
    ///     CPU 秒との比が、その合成の実効並列度になる。窓の勘定が合っているかを
    ///     後から確かめるのに要る(1スレッドを仮定していた頃はここが食い違っていた)。
    ///   - waitedSeconds: ガバナーの指示で待った秒数。
    ///   - isCPULimitApplied: ガバナーが効く条件だったか。
    func report(characterCount: Int,
                estimatedCPUSeconds: Double,
                actualCPUSeconds: Double,
                actualWallSeconds: Double,
                audioSeconds: Double,
                waitedSeconds: Double,
                isCPULimitApplied: Bool,
                now: Double = ProcessInfo.processInfo.systemUptime) {
        let thermalState = ProcessInfo.processInfo.thermalState
        lock.lock()
        summary.count += 1
        summary.characterCount += characterCount
        summary.audioSeconds += audioSeconds
        summary.wallSeconds += actualWallSeconds
        summary.cpuSeconds += actualCPUSeconds
        summary.waitedSeconds += waitedSeconds
        if actualWallSeconds > 0 {
            summary.slowestSpeed = min(summary.slowestSpeed, audioSeconds / actualWallSeconds)
        }
        lock.unlock()
        if let (message, appendix) = makeSummaryLog(now: now, thermalState: thermalState) {
            AppInformationLogger.AddLogWithStruct(message: message, appendix: appendix, isForDebug: VoicevoxDiagnostics.isForDebug)
        }

        guard let utilization = currentUtilization(at: now) else { return }

        lock.lock()
        // 1件目は必ず残す(この仕組みが動いている事と、平常時の水準が分かる)。
        // 以降は「見る価値のある水準」かつ「今までで一番悪い」時だけ。
        let shouldReport: Bool
        if hasReportedOnce == false {
            shouldReport = true
        } else {
            shouldReport = utilization >= Self.reportFloorUtilization
                && utilization >= reportedWorstUtilization + Self.worseningStep
        }
        if shouldReport {
            hasReportedOnce = true
            reportedWorstUtilization = max(reportedWorstUtilization, utilization)
        }
        lock.unlock()
        guard shouldReport else { return }

        let monitor = VoicevoxPrefetchThrottleMonitor.shared
        // 見積りが実測を下回っていると、そのぶん予算を食い越す。
        // 1.0 未満が「見積りが甘かった」= 危ない側。
        let estimateRatio = actualCPUSeconds > 0 ? estimatedCPUSeconds / actualCPUSeconds : 0

        AppInformationLogger.AddLogWithStruct(
            message: String(format: "[VOICEVOX CPU] 直近60秒 %.0f%% (上限80%%) / 待ち %.1f秒 / 見積り %.1f秒 に対し実測 %.1f秒 / 実時間の %.2f倍速で生成",
                            utilization * 100, waitedSeconds, estimatedCPUSeconds, actualCPUSeconds,
                            actualWallSeconds > 0 ? audioSeconds / actualWallSeconds : 0),
            appendix: [
                "utilization": AnyCodable(String(format: "%.3f", utilization)),
                "isCPULimitApplied": AnyCodable(isCPULimitApplied ? "true" : "false"),
                "isBackground": AnyCodable(monitor.isBackground ? "true" : "false"),
                "isOnExternalPower": AnyCodable(monitor.isOnExternalPower ? "true" : "false"),
                "isLowPowerMode": AnyCodable(ProcessInfo.processInfo.isLowPowerModeEnabled ? "true" : "false"),
                "thermalState": AnyCodable(Self.thermalStateText(thermalState)),
                "threadCount": AnyCodable("\(VoicevoxCore.activeCPUNumThreads)"),
                "characterCount": AnyCodable("\(characterCount)"),
                "estimatedCPUSeconds": AnyCodable(String(format: "%.2f", estimatedCPUSeconds)),
                "actualCPUSeconds": AnyCodable(String(format: "%.2f", actualCPUSeconds)),
                "actualWallSeconds": AnyCodable(String(format: "%.2f", actualWallSeconds)),
                "parallelism": AnyCodable(actualWallSeconds > 0 ? String(format: "%.2f", actualCPUSeconds / actualWallSeconds) : "-"),
                "audioSeconds": AnyCodable(String(format: "%.1f", audioSeconds)),
                // 実時間の何倍の速さで音声を作れているか。読み上げ速度がこれを超えると
                // 貯金は必ず減る。1.0 を割っていれば、等速再生にすら追いつけない。
                "generationSpeed": AnyCodable(actualWallSeconds > 0 ? String(format: "%.2f", audioSeconds / actualWallSeconds) : "-"),
                // CPU秒あたりどれだけ音声を作れたか(RTF の逆数)。
                "audioPerCPUSecond": AnyCodable(actualCPUSeconds > 0 ? String(format: "%.2f", audioSeconds / actualCPUSeconds) : "-"),
                "estimateRatio": AnyCodable(String(format: "%.2f", estimateRatio)),
                "waitedSeconds": AnyCodable(String(format: "%.2f", waitedSeconds)),
            ],
            isForDebug: true)
    }

    /// 読み上げの停止などで、窓の中身をやり直す。
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        reportedWorstUtilization = 0
        hasReportedOnce = false
        summary = Summary()
        lastSummaryReportedAt = nil
        lastSummaryThermalState = nil
    }

    /// 定期の要約を出すべきなら、その1行を作って返す(呼び出し側でログに出す)。
    ///
    /// 最悪値方式だけだと、**使用率が頭打ちになった後は一行も出なくなる**。
    /// 実際 2026-08-22 の前景・電源接続のログでは、開始3分で 296% に張り付いた後
    /// 57分間まったく記録が残らず、「熱が上がってから何倍速で作れていたのか」が
    /// 分からなくなった。生成速度と熱状態は**平常時こそ**見たいので、
    /// 熱状態が変わった時と、一定時間ごとに、その間の平均を1行だけ残す。
    private func makeSummaryLog(now: Double, thermalState: ProcessInfo.ThermalState) -> (String, [String: AnyCodable])? {
        lock.lock()
        defer { lock.unlock() }
        guard summary.count > 0 else { return nil }
        let thermalChanged = lastSummaryThermalState != nil && lastSummaryThermalState != thermalState
        let elapsed = now - (lastSummaryReportedAt ?? now)
        if lastSummaryReportedAt == nil {
            // 1本目は「いつから数え始めたか」を決めるだけ。ここで出しても 0分間の要約にしかならない。
            lastSummaryReportedAt = now
            lastSummaryThermalState = thermalState
            return nil
        }
        guard thermalChanged || elapsed >= Self.summaryIntervalSeconds else { return nil }
        let current = summary
        summary = Summary()
        lastSummaryReportedAt = now
        lastSummaryThermalState = thermalState
        let averageSpeed = current.wallSeconds > 0 ? current.audioSeconds / current.wallSeconds : 0
        let slowestSpeed = current.slowestSpeed == .greatestFiniteMagnitude ? averageSpeed : current.slowestSpeed
        let message = String(format: "[VOICEVOX CPU] この %.0f分で %d本 / 平均 %.2f倍速(最も遅い時で %.2f倍速) / 熱 %@",
                             max(elapsed, 0) / 60, current.count, averageSpeed, slowestSpeed,
                             Self.thermalStateText(thermalState))
        return (message, [
            "durationSeconds": AnyCodable(String(format: "%.0f", max(elapsed, 0))),
            "synthesisCount": AnyCodable("\(current.count)"),
            "characterCount": AnyCodable("\(current.characterCount)"),
            "audioSeconds": AnyCodable(String(format: "%.1f", current.audioSeconds)),
            "wallSeconds": AnyCodable(String(format: "%.1f", current.wallSeconds)),
            "cpuSeconds": AnyCodable(String(format: "%.1f", current.cpuSeconds)),
            "averageGenerationSpeed": AnyCodable(String(format: "%.2f", averageSpeed)),
            "slowestGenerationSpeed": AnyCodable(String(format: "%.2f", slowestSpeed)),
            "parallelism": AnyCodable(current.wallSeconds > 0 ? String(format: "%.2f", current.cpuSeconds / current.wallSeconds) : "-"),
            "waitedSeconds": AnyCodable(String(format: "%.1f", current.waitedSeconds)),
            "thermalState": AnyCodable(Self.thermalStateText(thermalState)),
            "isBackground": AnyCodable(VoicevoxPrefetchThrottleMonitor.shared.isBackground ? "true" : "false"),
            "isOnExternalPower": AnyCodable(VoicevoxPrefetchThrottleMonitor.shared.isOnExternalPower ? "true" : "false"),
            "threadCount": AnyCodable("\(VoicevoxCore.activeCPUNumThreads)"),
        ])
    }

    static func thermalStateText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
