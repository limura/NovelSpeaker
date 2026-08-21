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
    ///   - actualWallSeconds: 実際にかかった時間(壁時計)。
    ///     CPU 秒との比が、その合成の実効並列度になる。窓の勘定が合っているかを
    ///     後から確かめるのに要る(1スレッドを仮定していた頃はここが食い違っていた)。
    ///   - waitedSeconds: ガバナーの指示で待った秒数。
    ///   - isCPULimitApplied: ガバナーが効く条件だったか。
    func report(characterCount: Int,
                estimatedCPUSeconds: Double,
                actualCPUSeconds: Double,
                actualWallSeconds: Double,
                waitedSeconds: Double,
                isCPULimitApplied: Bool,
                now: Double = ProcessInfo.processInfo.systemUptime) {
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
            message: String(format: "[VOICEVOX CPU] 直近60秒 %.0f%% (上限80%%) / 待ち %.1f秒 / 見積り %.1f秒 に対し実測 %.1f秒",
                            utilization * 100, waitedSeconds, estimatedCPUSeconds, actualCPUSeconds),
            appendix: [
                "utilization": AnyCodable(String(format: "%.3f", utilization)),
                "isCPULimitApplied": AnyCodable(isCPULimitApplied ? "true" : "false"),
                "isBackground": AnyCodable(monitor.isBackground ? "true" : "false"),
                "isOnExternalPower": AnyCodable(monitor.isOnExternalPower ? "true" : "false"),
                "isLowPowerMode": AnyCodable(ProcessInfo.processInfo.isLowPowerModeEnabled ? "true" : "false"),
                "thermalState": AnyCodable(Self.thermalStateText(ProcessInfo.processInfo.thermalState)),
                "threadCount": AnyCodable("\(VoicevoxCore.activeCPUNumThreads)"),
                "characterCount": AnyCodable("\(characterCount)"),
                "estimatedCPUSeconds": AnyCodable(String(format: "%.2f", estimatedCPUSeconds)),
                "actualCPUSeconds": AnyCodable(String(format: "%.2f", actualCPUSeconds)),
                "actualWallSeconds": AnyCodable(String(format: "%.2f", actualWallSeconds)),
                "parallelism": AnyCodable(actualWallSeconds > 0 ? String(format: "%.2f", actualCPUSeconds / actualWallSeconds) : "-"),
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
