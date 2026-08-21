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
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 0) // 0.1秒/文字
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
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 0)
        // t=100 に終わった 40秒の合成 = 区間 [60, 100] を占めていた。
        governor.recordSynthesis(cpuSeconds: 40, wallSeconds: 40, characterCount: 400, at: 100)
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
        governor.recordSynthesis(cpuSeconds: 40, wallSeconds: 40, characterCount: 400, at: 100)
        let wait = governor.waitSeconds(forCharacterCount: 400, limitRatio: 0.8, at: 100)
        XCTAssertGreaterThan(wait, 0, "直後には始められない")
        XCTAssertLessThan(wait, 60, "終了から丸ごと60秒待つ必要は無い")
    }

    // 窓から出た使用量は勘定に入らない事。
    func testUsageOutsideTheWindowIsForgotten() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 0)
        governor.recordSynthesis(cpuSeconds: 45, wallSeconds: 45, characterCount: 450, at: 10)
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 200)
        XCTAssertEqual(wait, 0, accuracy: 0.001, "60秒窓より古い使用量は無視されるべき")
    }

    // 1本の合成の見積りが予算そのものを超える場合は、いくら待っても実行できない。
    // iPhone SE2(熱serious, 0.33秒/文字)で160文字のブロックを合成すると
    // 50秒以上かかり、48秒の予算に収まらない。この場合は「不可能」と分かる必要がある
    // (待てば実行できると誤認すると、待った挙句に上限を超えて殺される)。
    func testReportsImpossibleWhenOneSynthesisExceedsTheWholeBudget() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 33, wallSeconds: 33, characterCount: 100, at: 0) // 0.33秒/文字
        let wait = governor.waitSeconds(forCharacterCount: 160, limitRatio: 0.8, at: 1000)
        XCTAssertTrue(wait.isInfinite, "1本で予算(48秒)を超える合成は、待っても実行できない")
    }

    // 見積りは文字数に比例し、実測が反映される事。
    func testEstimateScalesWithCharacterCountAndFollowsMeasurements() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 13, wallSeconds: 13, characterCount: 100, at: 0) // 0.13秒/文字
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), 13, accuracy: 0.01)
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 50), 6.5, accuracy: 0.01)
    }

    // 発熱等で急に遅くなった時に、平均に薄められて過小評価しないこと。
    // 直近の最も重い実測に合わせる(過小評価はそのまま強制終了に繋がるため、
    // 見積りは高めに外す方が安全)。
    func testEstimateFollowsTheHeaviestRecentMeasurement() {
        let governor = makeGovernor()
        for i in 0..<5 {
            governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: Double(i)) // 0.1秒/文字
        }
        governor.recordSynthesis(cpuSeconds: 33, wallSeconds: 33, characterCount: 100, at: 10) // 急に0.33秒/文字へ悪化
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
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 0)
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
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 0)

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
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 0)
        governor.recordSynthesis(cpuSeconds: 30, wallSeconds: 30, characterCount: 300, at: 100)
        // 予算48秒(0.8)なら 100文字(10秒)はまだ入る。
        XCTAssertEqual(governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 100), 0, accuracy: 0.001)
        // 予算36秒(0.6)なら入らないので待たされる。
        XCTAssertGreaterThan(governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.6, at: 100), 0)
    }

    // 記録が無制限に増え続けない事(窓の外の記録は捨てる)。
    func testOldRecordsAreDiscarded() {
        let governor = makeGovernor()
        for i in 0..<1000 {
            governor.recordSynthesis(cpuSeconds: 0.01, wallSeconds: 0.01, characterCount: 1, at: Double(i))
        }
        XCTAssertLessThan(governor.recordCountForTesting, 100, "60秒窓を大きく超える記録は保持しない")
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
            governor.recordSynthesis(cpuSeconds: sample.cpu, wallSeconds: sample.cpu, characterCount: sample.chars, at: now)
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

    // ★実機で起きた事故そのもの。
    //
    // 2026-08-21 の実機ログ:
    //   直近60秒 121% (上限80%) / 待ち 0.0秒 / 見積り 2.3秒 に対し実測 8.2秒
    //   isCPULimitApplied=true / thermalState=nominal / threadCount=1
    // 87文字を 2.3秒 と見積もっていたが、実測は 8.2秒 だった。
    // 逆算すると、その時の単価は 0.0097秒/文字 = **下限値 minimumCostPerCharacter そのもの**。
    //
    // 原因は、単価の学習が `max(0, cpuSeconds - 固定費) / 文字数` の最大値を採る事。
    // 固定費(1.0秒)より軽い合成は、どれも 0 として扱われる。
    // 軽い合成が続いて手持ちのサンプルが全部 0 になると、最大値が 0 になり、
    // 下限の 0.01 まで落ちる。**「実測が無い時の 0.35」より遥かに小さい値**になり、
    // 見積りが甘くなって予算管理が一度も待たせなくなる(実機で waitedSeconds=0.0)。
    //
    // 情報の無いサンプルしか無い時は、下限ではなく**保守的な既定値**に落ちなければならない。
    func testDoesNotCollapseToTheFloorWhenAllSamplesAreTooShortToLearnFrom() {
        let governor = makeGovernor()
        // 固定費(1.0秒)を下回る軽い合成ばかりが続いた状況。
        feed(governor, [(5, 0.4), (6, 0.5), (4, 0.3), (7, 0.6),
                        (5, 0.4), (6, 0.5), (4, 0.3), (7, 0.6)])

        let estimate = governor.estimatedCPUSeconds(forCharacterCount: 87)
        // 下限(0.01/文字)まで落ちていると 2.3秒 になる。実機はそれで殺されかけた。
        XCTAssertGreaterThan(estimate, 2.5,
                             "学べるサンプルが無いのに、下限まで落ちて甘い見積りになっている")
        // 実測 8.2秒 を下回らない事(下回ると予算を食い越す)。
        XCTAssertGreaterThanOrEqual(estimate, 8.2,
                                    "実機の実測(8.2秒)を下回る見積りは、そのまま強制終了に繋がる")
    }

    // 学べるサンプルが1つでもあれば、そちらを使う事(上のフォールバックが効き過ぎない事)。
    func testUsesRealMeasurementEvenIfShortSamplesAreMixedIn() {
        let governor = makeGovernor()
        feed(governor, [(5, 0.4), (87, 8.2), (6, 0.5)])

        let estimate = governor.estimatedCPUSeconds(forCharacterCount: 87)
        XCTAssertGreaterThanOrEqual(estimate, 8.2, "実測を下回ってはいけない")
        // 既定値(0.35/文字)まで戻ると 87文字で38秒を超える。実測があるならそこまで要らない。
        XCTAssertLessThan(estimate, 20.0, "実測があるのに既定値の保守的な見積りに戻っている")
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

/// 窓(60秒)の勘定が「実時間」で行われているかを見るテスト。
///
/// 合成が窓のどこをどれだけ占めていたかは、CPU 秒ではなく実時間で置かないと合わない。
/// 全コアで走れば 17 CPU秒 の合成でも実時間は4秒ほどしかない。
class VoicevoxCPUGovernorWindowTest: XCTestCase {

    // 60秒窓・上限80% → 予算48秒。見積りに係数を掛けず、素の勘定だけを見る。
    private func makeGovernor() -> VoicevoxCPUGovernor {
        return VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 0)
    }

    // ★2026-08-21 の実機事故の再現。
    //
    // 全コアで走ると、17 CPU秒 の合成でも実時間は4秒ほどしかかからない。
    // それを「17秒間占めていた」ものとして記録すると、窓(実時間の60秒)から
    // はみ出た分が捨てられ、窓の中の使用量を実際より少なく見積もってしまう。
    // 実機ではプロセス全体が直近60秒で 159%(上限80%)に達していたのに、
    // 予算管理は一度も待たせていなかった(waitedSeconds = 0.00)。
    func testCountsCPUByWallClockIntervalNotByCPUSeconds() {
        let governor = makeGovernor()
        // 予算は 0.8 × 60 = 48秒。
        // 実時間で 12秒ずつ、4本で 48 CPU秒 を使い切ったところ。
        // 全コアなので、実時間の合計は 48秒ではなく 48/4 = 12秒しか経っていない。
        for i in 0..<4 {
            let end = Double(i) * 3 + 3
            governor.recordSynthesis(cpuSeconds: 12, wallSeconds: 3, characterCount: 120, at: end)
        }
        // t=12 の時点で、直近60秒には 48 CPU秒 が丸ごと入っている。もう空きは無い。
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 12)
        XCTAssertGreaterThan(wait, 0, "実時間で数えれば窓は埋まっている。待たせなければならない")
    }

    // 同じ 48 CPU秒 でも、どれだけの時間に詰め込まれていたかで待つべき長さが変わる。
    //
    // 1スレッドで48秒かけて使ったのなら、時間が経つにつれ窓の外へこぼれていくので、
    // 少し待てば空きができる。全コアで12秒に詰め込んだのなら、窓の中に固まって
    // 残っているので、窓がその塊を追い越すまで待たなければならない。
    // CPU 秒だけを見ていると、この2つが区別できない。
    func testSameCPUSecondsWaitLongerWhenPackedIntoAShorterTime() {
        let spread = makeGovernor()
        // 1スレッド。区間 [0, 48] に 48 CPU秒。
        spread.recordSynthesis(cpuSeconds: 48, wallSeconds: 48, characterCount: 480, at: 48)
        // 100文字(=10 CPU秒)を今から始めると終わるのは t=58。窓は [-2, 58] で 48秒ぶんが丸ごと入る。
        // 窓の左端が t=10 まで進めば入るのは 38秒ぶんになり、38 + 10 = 48 で予算に収まる。
        XCTAssertEqual(spread.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 48),
                       12, accuracy: 1.0, "窓の外へ出ていった分は数えない")

        let packed = makeGovernor()
        // 全コア(4並列)。同じ 48 CPU秒 が区間 [36, 48] に固まっている。
        packed.recordSynthesis(cpuSeconds: 48, wallSeconds: 12, characterCount: 480, at: 48)
        let packedWait = packed.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 48)
        XCTAssertGreaterThan(packedWait, 40,
                             "短時間に詰め込まれた CPU は窓の中に固まって残るので、ずっと長く待つ必要がある")
    }

    // 区間が窓の端に半分だけ掛かっている時は、その割合ぶんだけ数える。
    func testPartiallyOverlappingRecordIsProrated() {
        let governor = makeGovernor()
        // 実時間 [0, 10] に 40 CPU秒(=4並列)。
        governor.recordSynthesis(cpuSeconds: 40, wallSeconds: 10, characterCount: 400, at: 10)
        // 窓の左端が t=5 に来る時刻を作る。区間の半分だけが窓に入るので 20 CPU秒。
        // 100文字(10 CPU秒)を足しても 30秒で、予算48秒に収まる。
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 64)
        XCTAssertEqual(wait, 0, accuracy: 0.001, "窓に掛かっている割合ぶんだけ数える")
    }

    // 実時間が測れなかった場合でも、CPU 秒を取り零さない事。
    // (点として、終了時刻に全部使ったものとして数える = 安全側)
    func testRecordWithoutWallClockIsCountedAsAPoint() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 48, wallSeconds: 0, characterCount: 480, at: 0)
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 0)
        XCTAssertGreaterThan(wait, 0, "実時間が測れなくても、使った CPU を無かった事にしてはいけない")
    }

    // 並列度を学んだ後は、これから走らせる合成も「実時間では短い」ものとして扱う。
    // 窓の終わりが手前に来るので、直近に使った CPU がより多く窓に入る = 安全側に倒れる。
    func testFutureSynthesisIsProjectedWithLearnedParallelism() {
        let singleThreaded = makeGovernor()
        let multiThreaded = makeGovernor()
        // 単価は同じ(0.1 CPU秒/文字)。違うのは並列度だけ。
        for i in 0..<4 {
            let end = Double(i) * 10 + 10
            singleThreaded.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: end)
        }
        for i in 0..<4 {
            let end = Double(i) * 10 + 10
            multiThreaded.recordSynthesis(cpuSeconds: 10, wallSeconds: 2.5, characterCount: 100, at: end)
        }
        // どちらも窓の中身は 40 CPU秒。予算 48秒に対し、次の 100文字(10秒)を足すと 50秒。
        // 並列度が高い方は「窓の終わり」が手前に来るぶん、古い分が抜けにくく、より待つ。
        let waitSingle = singleThreaded.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 40)
        let waitMulti = multiThreaded.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 40)
        XCTAssertGreaterThanOrEqual(waitMulti, waitSingle,
                                    "並列度が高いほど CPU が短時間に詰まるので、安全側(待つ側)に倒れるべき")
    }

    // スレッド数を変えて学習結果を切り替えても、
    // 既に使った CPU の記録は消えない事(前景→背面の遷移がまさにこれ)。
    func testSwitchingThreadCountProfileKeepsUsageRecords() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 48, wallSeconds: 12, characterCount: 480, at: 12)
        governor.useThreadCountProfile(1)
        XCTAssertEqual(governor.recordCountForTesting, 1, "使った CPU の記録まで消してはいけない")
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 12)
        XCTAssertGreaterThan(wait, 0, "直前まで使っていた事を忘れてはいけない")
    }

    // ★スレッド数を行き来しても、既定値には戻らない事。
    //
    // 実機ログで、背面に落ちてスレッド数を1にした直後の1本を
    // 46文字=21.4秒(単価0.35=既定値そのもの)と見積もって実測8.8秒、
    // その結果29秒待たされていた。学習をスレッド数ごとに仕舞っておけば起きない。
    func testCostModelIsRememberedPerThreadCount() {
        let governor = makeGovernor()
        // 全コア(0)で 0.2秒/文字 を学ぶ。
        governor.recordSynthesis(cpuSeconds: 20, wallSeconds: 5, characterCount: 100, at: 10)
        let allCoreEstimate = governor.estimatedCPUSeconds(forCharacterCount: 100)

        // 1スレッドに切り替え。ここはまだ何も知らないので既定値になる。
        governor.useThreadCountProfile(1)
        XCTAssertFalse(governor.hasMeasurement, "別のスレッド数の実測を流用してはいけない")
        // 1スレッドで 0.1秒/文字 を学ぶ。
        governor.recordSynthesis(cpuSeconds: 10, wallSeconds: 10, characterCount: 100, at: 20)
        let singleEstimate = governor.estimatedCPUSeconds(forCharacterCount: 100)

        // 全コアへ戻すと、さっきの全コアの実測が戻ってくる。
        governor.useThreadCountProfile(0)
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), allCoreEstimate,
                       accuracy: 0.001, "戻したら前に測った全コアの見積りに戻るべき")
        // もう一度1スレッドへ。こちらも覚えている。
        governor.useThreadCountProfile(1)
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 100), singleEstimate,
                       accuracy: 0.001, "行き来しても既定値に戻ってはいけない")
        XCTAssertNotEqual(allCoreEstimate, singleEstimate, accuracy: 0.001,
                          "スレッド数が違えば見積りも違うはず(テストの前提)")
    }

    // 同じスレッド数を指定し直した時に、学習を捨ててしまわない事。
    // 合成の度に applyThreadCountIfNeeded 経由で呼ばれうるため。
    func testSwitchingToTheSameThreadCountKeepsTheModel() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 20, wallSeconds: 5, characterCount: 100, at: 10)
        governor.useThreadCountProfile(0)
        XCTAssertTrue(governor.hasMeasurement, "同じスレッド数なら学習は残るべき")
    }
}
