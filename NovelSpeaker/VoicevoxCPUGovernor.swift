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

    /// 実際に行われた合成1本ぶんの CPU 使用。
    ///
    /// 合成は CPU を占有し続けるので、40秒かかった合成は「終了時刻の40秒前から終了時刻まで」を
    /// 占めていた事になる。これを終了時刻の一点で使ったものとして数えると、実際には空いている
    /// 窓を埋まっていると誤認して必要以上に待ってしまう(実機で CPU 率が20%前後にしかならず、
    /// 上限80%に対して予算を大きく余らせる原因になっていた)。区間として扱う。
    private struct UsageRecord {
        let endTime: Double
        let cpuSeconds: Double
        var startTime: Double { return endTime - cpuSeconds }

        /// 指定区間と重なっている CPU 秒。
        func overlap(from: Double, to: Double) -> Double {
            return max(0, min(endTime, to) - max(startTime, from))
        }
    }

    private let lock = NSLock()
    private let windowSeconds: Double
    private let safetyFactor: Double
    private let fixedOverheadSeconds: Double

    private struct CostSample {
        let characterCount: Int
        let cpuSeconds: Double
    }

    private var usageRecords: [UsageRecord] = []
    /// 合成の実測(文字数と CPU 秒)。直近のものだけを持つ。
    private var costSamples: [CostSample] = []
    private let costSampleCapacity = 8

    /// 実測がまだ無い間に使う、保守的な既定値(秒/文字)。
    /// 実測の重い側(SE2 の熱serious ≒ 0.33)に寄せてある。過大評価なら先行合成が
    /// 少し控えめになるだけだが、過小評価は強制終了に直結するため。
    static let defaultCostPerCharacter = 0.35

    /// 単価の学習に使ってよいサンプルの最小文字数。
    ///
    /// 短い合成は中身のほとんどが固定費で、単価の情報をほとんど持たない。
    /// それを混ぜると、固定費を引いた残りが 0 になって単価を押し下げてしまう。
    /// 会話文の続く場面では「はい。」「そうか。」のような短いブロックが並ぶので、
    /// これを弾かないと手持ちのサンプルが全部そういう物で埋まる。
    static let minimumCharacterCountToLearn = 10
    /// 単価がこれを下回る事は無いとみなす下限。
    /// 0 になると「何文字でも入る」という判断になってしまうため。
    static let minimumCostPerCharacter = 0.01

    init(windowSeconds: Double = 60, safetyFactor: Double = 1.25, fixedOverheadSeconds: Double = 1.0) {
        self.windowSeconds = windowSeconds
        self.safetyFactor = safetyFactor
        self.fixedOverheadSeconds = fixedOverheadSeconds
    }

    var hasMeasurement: Bool {
        lock.lock()
        defer { lock.unlock() }
        return costSamples.isEmpty == false
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
        usageRecords.append(UsageRecord(endTime: now, cpuSeconds: cpuSeconds))
        usageRecords.removeAll { $0.endTime <= now - windowSeconds }
        // ★単価の材料にするのは「学べるサンプル」だけ。
        //
        // 短い合成や、固定費に埋もれる軽い合成を混ぜると、
        // `max(0, cpuSeconds - 固定費) / 文字数` が 0 になって単価を押し下げる。
        // 手持ち(8件)が全部そうなると最大値が 0 になり、単価が下限 0.01 まで落ちる。
        // これは「実測が無い時の既定値 0.35」より遥かに小さく、見積りが35倍甘くなる。
        //
        // 2026-08-21 の実機で実際にこれが起きた。87文字を 2.3秒 と見積もって
        // 実測 8.2秒、予算管理は一度も待たせず(waitedSeconds=0.0)、CPU率 121%。
        // 会話文が続く場面では短いブロックが8個並ぶのは普通に起きる。
        //
        // 弾いたサンプルも「使った CPU」としては上の usageRecords に入っているので、
        // 窓の勘定から漏れる事は無い。ここで捨てるのは単価の材料としてだけ。
        if characterCount >= Self.minimumCharacterCountToLearn && cpuSeconds > fixedOverheadSeconds {
            costSamples.append(CostSample(characterCount: characterCount, cpuSeconds: cpuSeconds))
            if costSamples.count > costSampleCapacity {
                costSamples.removeFirst(costSamples.count - costSampleCapacity)
            }
        }
    }

    /// 実測から求めた合成コストのモデル `固定費 + 文字あたり単価 × 文字数`。
    ///
    /// **固定費は学習しない。単価だけ実測から学ぶ。**
    ///
    /// 以前は両方を最小二乗で分離し、更に「どの実測も下回らないよう固定費を上へ倒す」
    /// ラチェットを入れていた。見積りが実測を下回ると CPU 上限の超過(=強制終了)に
    /// 直結するので必ず上側に倒す、という意図だったが、これが壊れていた。
    ///
    /// iPhone SE2 は熱状態で単価が2倍以上動く(0.16〜0.35 CPU秒/文字)。
    /// 熱いサンプルと冷えたサンプルが混ざると傾きが低く出て、その分が全部
    /// ラチェットで固定費に吸収される。しかも上がった固定費が分割を細かくし、
    /// 短いサンプルばかりになって更に切片が上がる、という自己成就になっていた。
    /// 実機で「固定費20秒」と見えていたのはこの産物で、実在しない
    /// (実機で測り直した実測は下表)。
    ///
    /// | | 固定費 | 単価 | R² |
    /// |---|---|---|---|
    /// | iPhone SE2 実機 | 1.60秒 | 0.346秒/文字 | 0.997 |
    /// | 母艦のシミュレータ | 1.11秒 | 0.114秒/文字 | 0.9994 |
    ///
    /// **端末で3倍動くのは単価の方で、固定費はほとんど動かない。**
    /// だから動く方だけ学べばよく、固定費を学習させる必要が無い。
    ///
    /// 単価は「固定費を引いてから文字数で割る」。引かずに割ると、短いサンプルほど
    /// 固定費が単価に化けて過大になる(10文字なら実測5.2秒÷10=0.52/文字。真値は0.346)。
    /// その上で最大値を採り、安全側に倒す。
    ///
    /// なお `fixedOverheadSeconds` は実測(1.1〜1.6秒)より少し低めに置いてある。
    /// 高く置くと、短いサンプルから学ぶ単価がその分低く出て、長文を過小評価する
    /// (=強制終了側に倒れる)ため。低めに置けば単価が高めに出て、安全側になる。
    private func fittedCost() -> (overhead: Double, perCharacter: Double) {
        // lock は呼び出し側で取っている前提。
        let overhead = fixedOverheadSeconds
        guard costSamples.isEmpty == false else {
            return (overhead, Self.defaultCostPerCharacter)
        }
        let perCharacter = costSamples.map { sample in
            max(0, sample.cpuSeconds - overhead) / Double(sample.characterCount)
        }.max() ?? Self.defaultCostPerCharacter
        // ★情報の無いサンプルしか無かった場合は、下限ではなく**既定値**に落ちる事。
        // 下限(0.01)は「単価が 0 になって何文字でも入る事にならないように」置いた歯止めで、
        // 「分からない時に使ってよい値」ではない。分からないなら保守的な側へ倒す。
        if perCharacter <= 0 {
            return (overhead, Self.defaultCostPerCharacter)
        }
        return (overhead, max(perCharacter, Self.minimumCostPerCharacter))
    }

    /// 指定文字数の合成に必要な CPU 秒の見積り(高めに出す)。
    func estimatedCPUSeconds(forCharacterCount characterCount: Int) -> Double {
        lock.lock()
        let cost = fittedCost()
        lock.unlock()
        return (cost.overhead + Double(characterCount) * cost.perCharacter) * safetyFactor
    }

    /// 指定した CPU 秒に収まる最大の文字数(1文字未満にはしない)。
    /// 「どのくらいの長さなら分割せずに合成できるか」の判断に使う。
    func maxCharacterCount(withinCPUSeconds cpuSeconds: Double) -> Int {
        lock.lock()
        let cost = fittedCost()
        lock.unlock()
        guard cost.perCharacter > 0, safetyFactor > 0 else { return Int.max }
        let available = cpuSeconds / safetyFactor - cost.overhead
        if available <= 0 { return 1 }
        return max(1, Int(available / cost.perCharacter))
    }

    /// この合成を始めてよくなるまで、あと何秒待つべきか。
    /// - Returns: 0 なら今すぐ開始してよい。`.infinity` なら、1本だけで予算を超えるため
    ///            いくら待っても背面では実行できない。
    func waitSeconds(forCharacterCount characterCount: Int, limitRatio: Double, at now: Double) -> Double {
        let estimate = estimatedCPUSeconds(forCharacterCount: characterCount)
        let budget = windowSeconds * limitRatio
        if estimate > budget { return .infinity }

        lock.lock()
        let records = usageRecords
        lock.unlock()

        // 判定するのは「この合成が終わる瞬間」の60秒窓。合成中ずっと CPU を使い続けるので、
        // 終了時点が最も窓の中身が多くなる。d 秒後に始めるとすると、
        // 窓は [now + d + estimate - windowSeconds, now + d + estimate]。
        // その窓に入る過去の使用量 + 自分の見積り が予算に収まる最小の d を探す。
        var d = 0.0
        while d <= windowSeconds * 2 {
            let windowEnd = now + d + estimate
            let windowStart = windowEnd - windowSeconds
            let used = records.reduce(0.0) { $0 + $1.overlap(from: windowStart, to: windowEnd) }
            if used + estimate <= budget { return d }
            d += 1
        }
        return .infinity
    }

    /// 読み上げ停止やスタイル変更等で集計をやり直す時に使う。
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        usageRecords.removeAll()
        costSamples.removeAll()
    }

    /// 文字数あたりのコストの見積りだけを作り直す(実際に使った CPU の記録は残す)。
    ///
    /// スレッド数を切り替えた時に使う。スレッド数が変わると文字数あたりの CPU 秒は
    /// 変わるので見積りは作り直す必要があるが、**既に使った CPU の記録は消してはいけない**。
    /// 消すと「直前まで全コアで回していた」事を忘れ、背面に移った直後の60秒窓で
    /// 予算超過(=強制終了)を招く。前景→背面はまさにその危険な遷移そのもの。
    func resetCostModel() {
        lock.lock()
        defer { lock.unlock() }
        costSamples.removeAll()
    }
}
