//
//  VoicevoxCPUGovernorTest.swift
//  NovelSpeakerTests
//
//  背面での CPU 使用率上限(60秒平均80%)超過による強制終了を防ぐための、
//  合成開始前の「予算チェック」のテスト。
//
//  重要な前提: voicevox の合成は同期的なC呼び出しで、走り始めたら途中で止められない。
//  iPhone SE2(熱=serious)の実測では1ブロック30〜45秒かかっており、60秒窓の中で
//  「走らせてから減速する」事は不可能。したがって判断は必ず「開始前」に行う必要があり、
//  そのためには合成にどれだけ CPU 時間がかかるかを事前に見積もらなければならない。
//
//  見積りは実測(文字数あたりの CPU 秒)から作る。同じ文字数でも端末と発熱状態で
//  数倍違う(実測: iPhone 17 Pro Max ≒ 0.13秒/文字、iPhone SE2(熱serious) ≒ 0.33秒/文字)ため、
//  固定値では役に立たない。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCPUGovernorTest: XCTestCase {

    // 60秒窓・上限80% → 予算48秒。実際にはもう少し手前で止める運用にする。
    private func makeGovernor() -> VoicevoxCPUGovernor {
        return VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 0)
    }

    // まだ何も使っていなければ、すぐに合成してよい。
    func testAllowsImmediatelyWhenNothingHasBeenUsed() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0) // 0.1秒/文字
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 1000)
        XCTAssertEqual(wait, 0, accuracy: 0.001, "窓の中に何も無いなら即座に合成してよい")
    }

    // 直前に使い切っていたら、窓に空きができるまで待たされる事。
    // これが無いと、合成が終わった直後に次の合成へ突入して上限を超える。
    //
    // 待ち時間は「合成が終わる時点の60秒窓」で判定する。
    // 合成は CPU を占有し続けるので、40秒の合成は「終了時刻の40秒前から現在まで」を
    // 占めている。これを終了時刻の一点で使ったものとして数えると、実際には空いている
    // 窓を埋まっていると誤認して、必要以上に待ってしまう(実機で CPU 率が20%前後に
    // しかならず、上限80%に対して予算を大きく余らせる原因になっていた)。
    func testWaitsUntilThereIsRoomInTheWindowAtCompletionTime() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)
        // t=100 に終わった 40秒の合成 = 区間 [60, 100] を占めていた。
        governor.recordSynthesis(cpuSeconds: 40, characterCount: 400, at: 100)
        // 予算は 0.8 × 60 = 48秒。次の合成(100文字=10秒)が終わる時点の窓に、
        // 古い区間が38秒までしか入らなければよい。
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 100)
        XCTAssertEqual(wait, 12, accuracy: 1.0, "窓に空きができるまでの分だけ待つべき(丸ごと60秒ではない)")
    }

    // 合成の所要時間ぶん、実際に占有している区間として数える事の確認。
    // 60秒窓に対して45秒の合成を繰り返す場合、終わった直後にもう一度始められるはずはないが、
    // 「終了から60秒」も待つ必要はない。
    func testLongSynthesisIsCountedAsAnIntervalNotAPoint() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 40, characterCount: 400, at: 100)
        let wait = governor.waitSeconds(forCharacterCount: 400, limitRatio: 0.8, at: 100)
        XCTAssertGreaterThan(wait, 0, "直後には始められない")
        XCTAssertLessThan(wait, 60, "終了から丸ごと60秒待つ必要は無い")
    }

    // 窓から出た使用量は勘定に入らない事。
    func testUsageOutsideTheWindowIsForgotten() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)
        governor.recordSynthesis(cpuSeconds: 45, characterCount: 450, at: 10)
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 200)
        XCTAssertEqual(wait, 0, accuracy: 0.001, "60秒窓より古い使用量は無視されるべき")
    }

    // 1本の合成の見積りが予算そのものを超える場合は、いくら待っても実行できない。
    // iPhone SE2(熱serious, 0.33秒/文字)で160文字のブロックを合成すると
    // 50秒以上かかり、48秒の予算に収まらない。この場合は「不可能」と分かる必要がある
    // (待てば実行できると誤認すると、待った挙句に上限を超えて殺される)。
    func testReportsImpossibleWhenOneSynthesisExceedsTheWholeBudget() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 33, characterCount: 100, at: 0) // 0.33秒/文字
        let wait = governor.waitSeconds(forCharacterCount: 160, limitRatio: 0.8, at: 1000)
        XCTAssertTrue(wait.isInfinite, "1本で予算(48秒)を超える合成は、待っても実行できない")
    }

    // 見積りは文字数に比例し、実測が反映される事。
    func testEstimateScalesWithCharacterCountAndFollowsMeasurements() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 13, characterCount: 100, at: 0) // 0.13秒/文字
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), 13, accuracy: 0.01)
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 50), 6.5, accuracy: 0.01)
    }

    // 発熱等で急に遅くなった時に、平均に薄められて過小評価しないこと。
    // 直近の最も重い実測に合わせる(過小評価はそのまま強制終了に繋がるため、
    // 見積りは高めに外す方が安全)。
    func testEstimateFollowsTheHeaviestRecentMeasurement() {
        let governor = makeGovernor()
        for i in 0..<5 {
            governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: Double(i)) // 0.1秒/文字
        }
        governor.recordSynthesis(cpuSeconds: 33, characterCount: 100, at: 10) // 急に0.33秒/文字へ悪化
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), 33, accuracy: 0.01,
                       "直近で最も重かった実測に合わせるべき(平均で薄めない)")
    }

    // 実測がまだ無い間は、保守的な既定値で見積もる事(0秒扱いにして突入しない)。
    func testUsesConservativeDefaultBeforeAnyMeasurement() {
        let governor = makeGovernor()
        XCTAssertGreaterThan(governor.estimatedCPUSeconds(forCharacterCount: 100), 0,
                             "実測が無くても0秒と見積もってはいけない")
        XCTAssertFalse(governor.hasMeasurement)
    }

    // 安全係数が効いている事(見積りは実測より高めに出す)。
    func testSafetyFactorInflatesTheEstimate() {
        let governor = VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.25, fixedOverheadSeconds: 0)
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), 12.5, accuracy: 0.01)
    }

    // 短いテキストでも固定の立ち上がりコストがある事を見込む
    // (文字数比例だけだと、短いブロックを大量に積んだ時に過小評価する)。
    //
    // 単価は「固定費を引いてから文字数で割る」。
    // 引かずに割ると固定費を二重に数える事になり、
    // **自分が学習したサンプル自身を過大に見積もる**という妙な状態になる
    // (100文字10秒を食わせて、その100文字を11秒と見積もっていた)。
    func testFixedOverheadIsIncluded() {
        let governor = VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 1.0)
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)

        // 10秒のうち1秒が固定費なので、単価は 9秒/100文字 = 0.09/文字。
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 10), 1.9, accuracy: 0.01,
                       "1秒(固定) + 0.9秒(10文字ぶん)")
        // 学習したサンプル自身は、そのまま言い当てられる。
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), 10.0, accuracy: 0.01,
                       "食わせた実測(100文字10秒)を再現する")
    }

    // 先行合成は再生より先に止める(同じ予算を食い合うため)。
    // limitRatio を小さくすると、より早い段階で待たされる事。
    func testLowerLimitRatioStopsEarlier() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)
        governor.recordSynthesis(cpuSeconds: 30, characterCount: 300, at: 100)
        // 予算48秒(0.8)なら 100文字(10秒)はまだ入る。
        XCTAssertEqual(governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 100), 0, accuracy: 0.001)
        // 予算36秒(0.6)なら入らないので待たされる。
        XCTAssertGreaterThan(governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.6, at: 100), 0)
    }

    // 記録が無制限に増え続けない事(窓の外の記録は捨てる)。
    func testOldRecordsAreDiscarded() {
        let governor = makeGovernor()
        for i in 0..<1000 {
            governor.recordSynthesis(cpuSeconds: 0.01, characterCount: 1, at: Double(i))
        }
        XCTAssertLessThan(governor.recordCountForTesting, 100, "60秒窓を大きく超える記録は保持しない")
    }
}

// 合成に使う CPU スレッド数の設定の持ち方。
//
// スレッド数は synthesizer の生成時オプションなので、変えるには作り直しが必要
// (音声モデルの再ロードを伴う)。それでも固定せず状況に応じて切り替えるのは、
// 「どちらが得か」が状況で逆転するため:
//  - 背面バッテリー … CPU上限(1コア相当の80%)が効くので、CPU秒あたりの効率が
//                     最良のスレッド数1が最良。全コアにしても強制終了されるだけ。
//  - 前景/充電中   … 上限が無いので、効率は悪くても実時間で倍近く速い全コアが良い
//                     (1スレッドだと1.45倍速の再生に追いつけない)。
// 切り替えの判断そのものは VoicevoxThreadPolicyTest で見る。
class VoicevoxCPUNumThreadsDefaultTest: XCTestCase {

    private let key = VoicevoxCore.cpuNumThreadsUserDefaultsKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    // 一度も設定していない状態では「状況に応じて自動」である事。
    func testDefaultIsAutomaticControl() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(VoicevoxCore.threadCountMode, .automatic)
    }

    // 明示的に設定した値はそのまま使われる事(計測用に「全コア」も選べる)。
    func testExplicitValueIsRespectedIncludingAllCores() {
        VoicevoxCore.threadCountMode = .fixed(4)
        XCTAssertEqual(VoicevoxCore.threadCountMode, .fixed(4))
        XCTAssertEqual(VoicevoxCore.configuredCPUNumThreads, 4)
        VoicevoxCore.threadCountMode = .fixed(0)
        XCTAssertEqual(VoicevoxCore.configuredCPUNumThreads, 0, "明示的に選んだ「全コア」は尊重する")
    }

    // 自動に戻すと、設定は消えて状況判断に委ねられる事。
    func testSwitchingBackToAutomaticRemovesTheStoredValue() {
        VoicevoxCore.threadCountMode = .fixed(2)
        VoicevoxCore.threadCountMode = .automatic
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        XCTAssertEqual(VoicevoxCore.threadCountMode, .automatic)
    }
}

// MARK: - 合成コストの見積り(2026-08-18 実機で取り直した後)

/// 「固定費20秒」という誤った見立てを二度と作らないための固定。
///
/// 以前は最小二乗＋ラチェット(どの実測も下回らないよう固定費を上へ倒す)で
/// 固定費と単価の両方を学習しており、発熱によるばらつきが全部固定費に吸収されて
/// 20秒まで膨れ上がっていた。実在する固定費は1〜3秒(VoicevoxStageTimingTest の実測)。
class VoicevoxCPUGovernorCostModelTest: XCTestCase {

    /// iPhone SE2 実機の実測(VoicevoxStageTimingTest, 2026-08-18)。
    /// 当てはめは CPU秒 = 1.60 + 0.346 × 文字数 (R^2=0.997)。
    private let realDeviceSamples: [(chars: Int, cpu: Double)] = [
        (10, 5.18), (20, 9.68), (40, 15.74), (80, 29.78),
        (120, 41.07), (160, 54.79), (240, 86.81),
    ]

    private func makeGovernor() -> VoicevoxCPUGovernor {
        return VoicevoxCPUGovernor()
    }

    private func feed(_ governor: VoicevoxCPUGovernor,
                      _ samples: [(chars: Int, cpu: Double)]) {
        var now: Double = 0
        for sample in samples {
            governor.recordSynthesis(cpuSeconds: sample.cpu, characterCount: sample.chars, at: now)
            now += 1
        }
    }

    // ★実機の実測を食わせた時、見積りが実測から大きく外れない事。
    //
    // 以前のモデル(固定費20秒 + 0.16/文字)は、10文字を +317%、240文字を -33% 外していた。
    // 短い方を過大に見積もると分割が無駄に細かくなり、
    // 長い方を過小に見積もると CPU 上限を超えて強制終了する。
    func testEstimateTracksRealDeviceMeasurements() {
        let governor = makeGovernor()
        feed(governor, realDeviceSamples)

        for sample in realDeviceSamples {
            let estimate = governor.estimatedCPUSeconds(forCharacterCount: sample.chars)
            // 安全率1.25が掛かるので、実測を下回らず、かつ2倍は超えない範囲に収まるはず。
            XCTAssertGreaterThanOrEqual(
                estimate, sample.cpu,
                "\(sample.chars)文字の見積り \(estimate) が実測 \(sample.cpu) を下回っている(強制終了の危険)")
            XCTAssertLessThan(
                estimate, sample.cpu * 2.0,
                "\(sample.chars)文字の見積り \(estimate) が実測 \(sample.cpu) に対し過大(無駄に細かく分割される)")
        }
    }

    // ★発熱でばらついたサンプルが、固定費を押し上げない事。
    //
    // これが以前の不具合の正体。熱い時の短いサンプルと冷えた時の長いサンプルが
    // 混ざると、ラチェットが差分を全部固定費に吸収して20秒まで膨らんでいた。
    func testThermalVarianceDoesNotInflateFixedCost() {
        let governor = makeGovernor()
        // 熱い時の短い合成(単価が倍)と、冷えた時の長い合成を混ぜる
        feed(governor, [(40, 28.0), (240, 84.6), (30, 21.0), (200, 70.0)])

        // 0文字の見積り ≒ 固定費。ここが20秒級になっていたのが以前の姿。
        let overheadEstimate = governor.estimatedCPUSeconds(forCharacterCount: 0)
        XCTAssertLessThan(overheadEstimate, 5.0,
                          "固定費が \(overheadEstimate) 秒に膨らんでいる(発熱のばらつきを吸収してしまっている)")
    }

    // ★短いサンプルしか無い状態から、長文を過小評価しない事。
    //
    // 分割が細かくなると短いサンプルばかりになる。そこから長文の見積りを外すと、
    // 「たまに長いブロックを投げた時だけ強制終了する」という追いにくい壊れ方をする。
    func testDoesNotUnderestimateLongTextFromShortSamples() {
        let governor = makeGovernor()
        feed(governor, [(10, 5.18), (20, 9.68), (30, 12.0)])

        let estimate = governor.estimatedCPUSeconds(forCharacterCount: 240)
        XCTAssertGreaterThanOrEqual(estimate, 86.81,
                                    "短いサンプルからの外挿が実機の実測(86.8秒)を下回っている")
    }

    // 実測が無い間は、既定値による保守的な見積りに落ちる事。
    func testFallsBackToDefaultsWithoutSamples() {
        let governor = makeGovernor()
        let estimate = governor.estimatedCPUSeconds(forCharacterCount: 100)
        XCTAssertGreaterThan(estimate, 0)
        // 既定 0.35/文字 × 100 に安全率が掛かる程度
        XCTAssertGreaterThan(estimate, 35.0)
    }

    // ★分割の粒度が、実機で実用になる大きさになる事。
    //
    // 以前は固定費20秒のせいで「1窓(予算48秒)に40文字しか入らない」と判断していた。
    // 実測(1.6 + 0.346/文字)なら、48秒あれば100文字前後は入るはず。
    func testChunkSizeIsPracticalOnRealDevice() {
        let governor = makeGovernor()
        feed(governor, realDeviceSamples)

        let maxCount = governor.maxCharacterCount(withinCPUSeconds: 48)
        XCTAssertGreaterThan(maxCount, 60,
                             "1窓に \(maxCount) 文字しか入らない判断になっている(分割が細かすぎる)")
        // 実測 1.6 + 0.346×n に安全率1.25 を掛けて48秒に収まるのは 100文字強まで
        XCTAssertLessThan(maxCount, 160,
                          "1窓に \(maxCount) 文字入る判断は楽観的すぎる(CPU上限を超える)")
    }

    // ★アプリ内計測(2026-08-18, iPhone SE2, ケーブルを抜いて前面)で取った実測。
    //
    // どちらも固定費は1〜3秒で、20秒ではない。R² も 0.999台で直線に乗っている。
    // 低電力ONは1スレッド(並列度1.0)、OFFは全コア(並列度2.8)。
    // 単価が CPU秒で見て近い(0.32 対 0.37)のは、並列化しても
    // 「同じ仕事にかかるCPU秒」はあまり変わらない(むしろ少し増える)ため。
    func testTracksInAppMeasurementsOnRealDevice() {
        // 低電力ON: 固定費2.63秒 + 0.3215/文字 (R²=0.9998)
        let lowPowerSamples: [(chars: Int, cpu: Double)] = [
            (20, 8.86), (40, 15.75), (80, 28.34), (120, 41.17),
        ]
        // 低電力OFF: 固定費1.21秒 + 0.3745/文字 (R²=0.9992)
        let fullPowerSamples: [(chars: Int, cpu: Double)] = [
            (20, 8.71), (40, 16.50), (80, 30.49), (120, 46.49),
        ]

        for (label, samples) in [("低電力ON", lowPowerSamples), ("低電力OFF", fullPowerSamples)] {
            let governor = makeGovernor()
            feed(governor, samples)
            for sample in samples {
                let estimate = governor.estimatedCPUSeconds(forCharacterCount: sample.chars)
                XCTAssertGreaterThanOrEqual(
                    estimate, sample.cpu,
                    "\(label) \(sample.chars)文字の見積り \(estimate) が実測 \(sample.cpu) を下回っている")
                XCTAssertLessThan(
                    estimate, sample.cpu * 1.5,
                    "\(label) \(sample.chars)文字の見積り \(estimate) が実測 \(sample.cpu) に対し過大")
            }
            // 固定費が実測(1〜3秒)からかけ離れていない事
            XCTAssertLessThan(governor.estimatedCPUSeconds(forCharacterCount: 0), 5.0,
                              "\(label) の固定費が膨らんでいる")
        }
    }

    // 予算より大きい文字数を求められても、1文字以上は返す(前に進まなくなるのを防ぐ)。
    func testAlwaysAllowsAtLeastOneCharacter() {
        let governor = makeGovernor()
        feed(governor, realDeviceSamples)
        XCTAssertGreaterThanOrEqual(governor.maxCharacterCount(withinCPUSeconds: 0.1), 1)
    }
}
