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

    // 直前に使い切っていたら、古い記録が60秒窓から出るまで待たされる事。
    // これが無いと、合成が終わった直後に次の合成へ突入して上限を超える。
    func testWaitsUntilOldUsageLeavesTheWindow() {
        let governor = makeGovernor()
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)
        // t=100 の時点で 40秒ぶん使った(窓には40秒ぶんある)。
        governor.recordSynthesis(cpuSeconds: 40, characterCount: 400, at: 100)
        // 予算は 0.8 × 60 = 48秒。あと 100文字(=10秒)積むと 50秒で超える。
        let wait = governor.waitSeconds(forCharacterCount: 100, limitRatio: 0.8, at: 100)
        // t=160 に 40秒ぶんが窓から出るので、そこまで待てばよい。
        XCTAssertEqual(wait, 60, accuracy: 0.001, "古い使用量が窓から出るまで待つべき")
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
    func testFixedOverheadIsIncluded() {
        let governor = VoicevoxCPUGovernor(windowSeconds: 60, safetyFactor: 1.0, fixedOverheadSeconds: 1.0)
        governor.recordSynthesis(cpuSeconds: 10, characterCount: 100, at: 0)
        XCTAssertEqual(governor.estimatedCPUSeconds(forCharacterCount: 10), 2.0, accuracy: 0.01,
                       "1秒(固定) + 1秒(10文字ぶん)")
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
