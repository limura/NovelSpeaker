//
//  VoicevoxCPUGovernor.swift
//  NovelSpeaker
//
//  背面再生中の CPU 使用率上限(60秒平均80%)超過による強制終了を防ぐための予算管理。
//
//  なぜ「開始前」に判断しないといけないのか:
//  voicevox の合成は同期的なC呼び出しで、走り始めたら途中で止められない。
//  iPhone SE2(熱=serious)の実測では1ブロックに30〜45秒かかっており、
//  60秒の判定窓の中で「走らせてから減速する」事は原理的に不可能。
//  そのため、合成に入る前に「この1本を今走らせたら上限を超えるか」を見積もって判断する。
//
//  見積りは実測(文字数あたりの CPU 秒)から作る。同じ文字数でも端末と発熱状態で数倍違う:
//    iPhone 17 Pro Max        ≒ 0.13 秒/文字
//    iPhone SE2 (熱=serious)  ≒ 0.33 秒/文字
//  ので固定値では役に立たない。過小評価はそのまま強制終了になるため、
//  直近で最も重かった実測に合わせ、さらに安全係数を掛けて高めに見積もる。
//
//  なお「1本の合成だけで予算(48秒)を超える」場合は、いくら待っても背面では実行できない
//  (SE2 で160文字のブロックが該当する)。この時は待たずに諦める。無音になるが、
//  強制終了されると再生自体が止まってしまうので、そちらよりは軽い。
//

import Foundation

final class VoicevoxCPUGovernor {

    private struct UsageRecord {
        let time: Double
        let cpuSeconds: Double
    }

    private let lock = NSLock()
    private let windowSeconds: Double
    private let safetyFactor: Double
    private let fixedOverheadSeconds: Double

    private var usageRecords: [UsageRecord] = []
    /// 文字数あたりの CPU 秒の実測。直近のものだけを持ち、その最大値を見積りに使う。
    private var costPerCharacterSamples: [Double] = []
    private let costSampleCapacity = 8

    /// 実測がまだ無い間に使う、保守的な既定値(秒/文字)。
    /// 実測の重い側(SE2 の熱serious ≒ 0.33)に寄せてある。過大評価なら先行合成が
    /// 少し控えめになるだけだが、過小評価は強制終了に直結するため。
    static let defaultCostPerCharacter = 0.35

    init(windowSeconds: Double = 60, safetyFactor: Double = 1.25, fixedOverheadSeconds: Double = 1.0) {
        self.windowSeconds = windowSeconds
        self.safetyFactor = safetyFactor
        self.fixedOverheadSeconds = fixedOverheadSeconds
    }

    var hasMeasurement: Bool {
        lock.lock()
        defer { lock.unlock() }
        return costPerCharacterSamples.isEmpty == false
    }

    var recordCountForTesting: Int {
        lock.lock()
        defer { lock.unlock() }
        return usageRecords.count
    }

    /// 実際に行われた合成の実績を記録する(見積りの材料と、窓の使用量の両方になる)。
    func recordSynthesis(cpuSeconds: Double, characterCount: Int, at now: Double) {
        lock.lock()
        defer { lock.unlock() }
        usageRecords.append(UsageRecord(time: now, cpuSeconds: cpuSeconds))
        usageRecords.removeAll { $0.time <= now - windowSeconds }
        if characterCount > 0 && cpuSeconds > 0 {
            costPerCharacterSamples.append(cpuSeconds / Double(characterCount))
            if costPerCharacterSamples.count > costSampleCapacity {
                costPerCharacterSamples.removeFirst(costPerCharacterSamples.count - costSampleCapacity)
            }
        }
    }

    /// 指定文字数の合成に必要な CPU 秒の見積り(高めに出す)。
    func estimatedCPUSeconds(forCharacterCount characterCount: Int) -> Double {
        lock.lock()
        let costPerCharacter = costPerCharacterSamples.max() ?? Self.defaultCostPerCharacter
        lock.unlock()
        return (Double(characterCount) * costPerCharacter + fixedOverheadSeconds) * safetyFactor
    }

    /// 指定した CPU 秒に収まる最大の文字数(1文字未満にはしない)。
    /// 「どのくらいの長さなら分割せずに合成できるか」の判断に使う。
    func maxCharacterCount(withinCPUSeconds cpuSeconds: Double) -> Int {
        lock.lock()
        let costPerCharacter = costPerCharacterSamples.max() ?? Self.defaultCostPerCharacter
        lock.unlock()
        guard costPerCharacter > 0, safetyFactor > 0 else { return Int.max }
        let available = cpuSeconds / safetyFactor - fixedOverheadSeconds
        if available <= 0 { return 1 }
        return max(1, Int(available / costPerCharacter))
    }

    /// この合成を始めてよくなるまで、あと何秒待つべきか。
    /// - Returns: 0 なら今すぐ開始してよい。`.infinity` なら、1本だけで予算を超えるため
    ///            いくら待っても背面では実行できない。
    func waitSeconds(forCharacterCount characterCount: Int, limitRatio: Double, at now: Double) -> Double {
        let estimate = estimatedCPUSeconds(forCharacterCount: characterCount)
        let budget = windowSeconds * limitRatio
        if estimate > budget { return .infinity }

        lock.lock()
        let records = usageRecords.filter { $0.time > now - windowSeconds }.sorted { $0.time < $1.time }
        lock.unlock()

        var used = records.reduce(0.0) { $0 + $1.cpuSeconds }
        if used + estimate <= budget { return 0 }
        // 古い記録から順に窓の外へ出していき、収まるようになる時刻を求める。
        for record in records {
            used -= record.cpuSeconds
            if used + estimate <= budget {
                return max(0, record.time + windowSeconds - now)
            }
        }
        return 0
    }

    /// 読み上げ停止やスタイル変更等で集計をやり直す時に使う。
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        usageRecords.removeAll()
        costPerCharacterSamples.removeAll()
    }
}
