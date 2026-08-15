//
//  VoicevoxPerformanceMonitorTest.swift
//  NovelSpeakerTests
//
//  バックグラウンド再生時の CPU 上限超過(cpu_resource_fatal)を追うための
//  実測ロジック(CPU使用率の窓・RTF集計)のテスト。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxPerformanceMonitorTest: XCTestCase {

    // MARK: - CPUDutyWindow

    // 実機で観測された「48秒CPU / 58秒 = 82%」を再現できること。
    func testDutyRatioReproducesObservedCrashNumbers() {
        var window = CPUDutyWindow(windowSeconds: 60)
        window.add(wallTime: 0, cpuSeconds: 0)
        window.add(wallTime: 58, cpuSeconds: 48)
        let duty = try! XCTUnwrap(window.dutyRatio)
        XCTAssertEqual(duty, 48.0 / 58.0, accuracy: 0.0001)
        XCTAssertEqual(duty, 0.8275, accuracy: 0.001, "実機の82%と一致するはず")
        XCTAssertGreaterThan(duty, VoicevoxPerformanceMonitor.osBackgroundCPUDutyLimit, "80%上限を超えている判定になるはず")
    }

    // 2件目の kill「48秒CPU / 54秒 = 89%」も同様に。
    func testDutyRatioReproducesSecondCrashNumbers() {
        var window = CPUDutyWindow(windowSeconds: 60)
        window.add(wallTime: 100, cpuSeconds: 1000)
        window.add(wallTime: 154, cpuSeconds: 1048)
        let duty = try! XCTUnwrap(window.dutyRatio)
        XCTAssertEqual(duty, 0.8889, accuracy: 0.001, "実機の89%と一致するはず")
    }

    func testDutyRatioIsNilWithoutEnoughSamples() {
        var window = CPUDutyWindow(windowSeconds: 60)
        XCTAssertNil(window.dutyRatio, "サンプル0件では算出できない")
        window.add(wallTime: 0, cpuSeconds: 0)
        XCTAssertNil(window.dutyRatio, "サンプル1件では算出できない")
    }

    // 窓からはみ出た古いサンプルは捨てるが、窓の左端の基準点は1つ残す。
    func testWindowKeepsOnlyRecentSamplesButRetainsBaseline() {
        var window = CPUDutyWindow(windowSeconds: 60)
        // 0秒から200秒まで、常に50%使用で10秒毎にサンプル。
        for i in 0...20 {
            let t = Double(i) * 10
            window.add(wallTime: t, cpuSeconds: t * 0.5)
        }
        let duty = try! XCTUnwrap(window.dutyRatio)
        XCTAssertEqual(duty, 0.5, accuracy: 0.0001, "一定50%ならいつ測っても50%")
        XCTAssertLessThanOrEqual(window.spannedSeconds, 70, "窓が無制限に伸びていない")
        XCTAssertGreaterThanOrEqual(window.spannedSeconds, 60, "60秒ぶんは覆えている")
    }

    // 直近だけ跳ね上がった場合、窓の平均として反映される(古い低負荷に薄められ過ぎない)。
    func testRecentSpikeIsReflected() {
        var window = CPUDutyWindow(windowSeconds: 60)
        for i in 0...10 { // 0〜100秒: 10%
            let t = Double(i) * 10
            window.add(wallTime: t, cpuSeconds: t * 0.1)
        }
        // 100〜160秒: 100%
        for i in 1...6 {
            let t = 100 + Double(i) * 10
            window.add(wallTime: t, cpuSeconds: 10 + Double(i) * 10)
        }
        let duty = try! XCTUnwrap(window.dutyRatio)
        XCTAssertGreaterThan(duty, 0.9, "直近60秒がほぼ100%なら高く出るはず。実際: \(duty)")
    }

    // MARK: - RTFAccumulator

    func testRTFCalculation() {
        var acc = RTFAccumulator()
        // 10秒の音声を5.5秒のCPUで作れた → RTF 0.55
        acc.add(audioSeconds: 10, cpuSeconds: 5.5, wallSeconds: 6.0)
        XCTAssertEqual(try XCTUnwrap(acc.cpuRTF), 0.55, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(acc.wallRTF), 0.60, accuracy: 0.0001)
        XCTAssertEqual(acc.sampleCount, 1)
    }

    func testRTFIgnoresZeroLengthAudio() {
        var acc = RTFAccumulator()
        acc.add(audioSeconds: 0, cpuSeconds: 1.0, wallSeconds: 1.0)
        XCTAssertNil(acc.cpuRTF)
        XCTAssertEqual(acc.sampleCount, 0)
    }

    // 実機の状況(1.5倍速・RTF0.55 → 必要82%)を再現し、
    // 「速度を落とせば上限を割れる」という関係を確認する。
    func testRequiredDutyAndSustainableRateMatchObservedCrash() {
        let rtf = 0.55
        let required = RTFAccumulator.requiredCPUDuty(rtf: rtf, playbackRate: 1.5)
        XCTAssertEqual(required, 0.825, accuracy: 0.001, "1.5倍速×RTF0.55で約82%(実機の観測値)")
        XCTAssertGreaterThan(required, VoicevoxPerformanceMonitor.osBackgroundCPUDutyLimit, "上限超過になるはず")

        let sustainable = try! XCTUnwrap(RTFAccumulator.sustainablePlaybackRate(rtf: rtf, cpuDutyLimit: 0.80))
        XCTAssertEqual(sustainable, 1.4545, accuracy: 0.001, "80%を割るには約1.45倍まで")
        // その速度なら必要CPU率が上限ちょうど以下に収まる。
        XCTAssertLessThanOrEqual(RTFAccumulator.requiredCPUDuty(rtf: rtf, playbackRate: sustainable), 0.8001)
    }

    func testSustainableRateIsNilForInvalidRTF() {
        XCTAssertNil(RTFAccumulator.sustainablePlaybackRate(rtf: 0, cpuDutyLimit: 0.8))
    }

    func testRecentRTFAverageTracksLatestSamples() {
        var acc = RTFAccumulator(recentCapacity: 3)
        acc.add(audioSeconds: 1, cpuSeconds: 1.0, wallSeconds: 1.0) // RTF 1.0
        acc.add(audioSeconds: 1, cpuSeconds: 0.5, wallSeconds: 0.5) // 0.5
        acc.add(audioSeconds: 1, cpuSeconds: 0.5, wallSeconds: 0.5) // 0.5
        acc.add(audioSeconds: 1, cpuSeconds: 0.5, wallSeconds: 0.5) // 0.5 (最初の1.0が押し出される)
        XCTAssertEqual(try XCTUnwrap(acc.recentCPURTFAverage), 0.5, accuracy: 0.0001)
        // 累計の方は最初のサンプルも含んだままである事。
        XCTAssertEqual(try XCTUnwrap(acc.cpuRTF), 2.5 / 4.0, accuracy: 0.0001)
    }

    // MARK: - 音声秒数の換算

    // VOICEVOX の出力は 24kHz / mono / 16bit。1秒 = 48000バイト + ヘッダ44バイト。
    func testAudioSecondsFromWavByteCount() {
        let oneSecond = Int(24000 * 2) + 44
        XCTAssertEqual(VoicevoxPerformanceMonitor.audioSeconds(wavByteCount: oneSecond), 1.0, accuracy: 0.0001)
        XCTAssertEqual(VoicevoxPerformanceMonitor.audioSeconds(wavByteCount: 44), 0.0, accuracy: 0.0001)
        // ヘッダより短い不正な値でも負にならない事。
        XCTAssertEqual(VoicevoxPerformanceMonitor.audioSeconds(wavByteCount: 0), 0.0, accuracy: 0.0001)
    }

    // MARK: - プロセスCPU時間の取得

    // 実際に CPU 時間が取得でき、単調増加する事(mach timebase 換算が壊れていない事の確認)。
    func testProcessCPUClockIsAvailableAndMonotonic() throws {
        let first = try XCTUnwrap(ProcessCPUClock.totalCPUSeconds(), "プロセスCPU時間が取得できるはず")
        XCTAssertGreaterThan(first, 0, "テスト実行中なので0より大きいはず")
        // 少しCPUを使う
        var sum = 0.0
        for i in 0..<2_000_000 { sum += Double(i).squareRoot() }
        XCTAssertGreaterThan(sum, 0)
        let second = try XCTUnwrap(ProcessCPUClock.totalCPUSeconds())
        XCTAssertGreaterThan(second, first, "CPUを使った後は増えているはず")
        // 妥当な桁である事(秒単位。ナノ秒のまま等になっていない)。
        XCTAssertLessThan(second - first, 60, "この程度の計算で60秒もかかるはずがない(単位換算の誤りを検出)")
    }
}

// MARK: - PlaybackGapAccumulator
// 「未再生の貯金が108秒あるのに、再生できていた時間は全体の約半分だった」という
// 実機の観測を受けて追加した、再生の途切れ(意図しない無音)の集計テスト。
class VoicevoxPlaybackGapTest: XCTestCase {

    // 実機で観測された状況の再現: 再生248秒に対し無音254秒 → 無音率が約50%と出る事。
    func testSilenceRatioReproducesObservedHalfSilence() {
        var acc = PlaybackGapAccumulator()
        acc.addPlayback(wallSeconds: 248)
        acc.addGap(seconds: 254)
        let ratio = try! XCTUnwrap(acc.silenceRatio)
        XCTAssertEqual(ratio, 0.506, accuracy: 0.01, "発話していたはずの時間の約半分が無音、と出るはず")
    }

    func testSilenceRatioIsZeroWhenNoGaps() {
        var acc = PlaybackGapAccumulator()
        acc.addPlayback(wallSeconds: 100)
        XCTAssertEqual(try XCTUnwrap(acc.silenceRatio), 0.0, accuracy: 0.0001)
    }

    func testSilenceRatioIsNilWithoutAnyData() {
        let acc = PlaybackGapAccumulator()
        XCTAssertNil(acc.silenceRatio)
        XCTAssertNil(acc.cacheHitRatio)
        XCTAssertNil(acc.averageGapSeconds)
        XCTAssertNil(acc.averageMissWaitSeconds)
    }

    // 「間の設定」を差し引いた結果が0以下になる場合は無音として数えない
    // (意図的なポーズを無音率に混ぜない)。
    func testNonPositiveGapsAreIgnored() {
        var acc = PlaybackGapAccumulator()
        acc.addPlayback(wallSeconds: 10)
        acc.addGap(seconds: 0)
        acc.addGap(seconds: -0.3)
        XCTAssertEqual(acc.gapCount, 0, "0以下の値は無音として数えない")
        XCTAssertEqual(try XCTUnwrap(acc.silenceRatio), 0.0, accuracy: 0.0001)
    }

    func testGapStatistics() {
        var acc = PlaybackGapAccumulator()
        acc.addGap(seconds: 1.0)
        acc.addGap(seconds: 3.0)
        acc.addGap(seconds: 2.0)
        XCTAssertEqual(acc.gapCount, 3)
        XCTAssertEqual(acc.totalGapSeconds, 6.0, accuracy: 0.0001)
        XCTAssertEqual(acc.maxGapSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(acc.averageGapSeconds), 2.0, accuracy: 0.0001)
    }

    // 先行合成が間に合っていたかの割合と、MISS時の平均待ち時間。
    // MISSが無音の主因なのか、それとも別の要因なのかを切り分けるための指標。
    func testCacheHitRatioAndMissWait() {
        var acc = PlaybackGapAccumulator()
        acc.addSynthesisRequest(wasCacheHit: true, waitSeconds: 0)
        acc.addSynthesisRequest(wasCacheHit: true, waitSeconds: 0)
        acc.addSynthesisRequest(wasCacheHit: true, waitSeconds: 0)
        acc.addSynthesisRequest(wasCacheHit: false, waitSeconds: 2.0)
        XCTAssertEqual(try XCTUnwrap(acc.cacheHitRatio), 0.75, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(acc.averageMissWaitSeconds), 2.0, accuracy: 0.0001)
        XCTAssertEqual(acc.cacheMissCount, 1)
    }

    // HIT率が100%なのに無音率が高い、という状態を表現できる事。
    // (これが観測されたら「合成は間に合っているのに再生側で落としている」証拠になる)
    func testFullCacheHitWithHighSilenceIsRepresentable() {
        var acc = PlaybackGapAccumulator()
        for _ in 0..<10 {
            acc.addSynthesisRequest(wasCacheHit: true, waitSeconds: 0)
            acc.addPlayback(wallSeconds: 5)
            acc.addGap(seconds: 5)
        }
        XCTAssertEqual(try XCTUnwrap(acc.cacheHitRatio), 1.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(acc.silenceRatio), 0.5, accuracy: 0.0001)
    }
}
