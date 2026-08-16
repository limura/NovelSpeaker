//
//  VoicevoxThreadPolicyTest.swift
//  NovelSpeakerTests
//
//  合成に使う CPU スレッド数を状況に応じて切り替えるポリシーのテスト。
//
//  実測(iPhone 17 Pro Max / iOS 26.6):
//   - スレッド数1  : RTF≒0.85(CPU秒/文字が最良)だが実時間では1.2倍速程度が限界
//   - 自動(全コア): RTF≒1.43(効率は悪い)だが CPU 292% を使えて実時間2倍速相当
//  背面バッテリー時は使えるCPUが1コア相当に制限されるので前者、
//  前景/充電中は制限が無いので後者が良い、という逆転がある。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxThreadPolicyTest: XCTestCase {

    // 背面かつバッテリー駆動 = iOSのCPU上限(60秒平均80%)が効く状況。
    // ここで全コアを使うと即座に強制終了されるので、必ず1にする。
    func testUsesASingleThreadWhenTheBackgroundCPULimitApplies() {
        XCTAssertEqual(
            VoicevoxThreadPolicy.automaticThreadCount(isBackground: true, isOnExternalPower: false, isLowPowerModeEnabled: false),
            1
        )
    }

    // 背面でも外部電源に繋がっていればCPU上限は適用されないので、全力で作ってよい。
    func testUsesAllCoresInBackgroundWhileOnExternalPower() {
        XCTAssertEqual(
            VoicevoxThreadPolicy.automaticThreadCount(isBackground: true, isOnExternalPower: true, isLowPowerModeEnabled: false),
            0
        )
    }

    // 前景はCPU上限の対象外。バッテリー駆動でも全力で作ってよい
    // (1スレッドだと1.45倍速の再生に追いつけず、無音で途切れてしまう)。
    func testUsesAllCoresInForegroundEvenOnBattery() {
        XCTAssertEqual(
            VoicevoxThreadPolicy.automaticThreadCount(isBackground: false, isOnExternalPower: false, isLowPowerModeEnabled: false),
            0
        )
    }

    // 低電力モードは「電池を使うな」という明示的な意思表示なので、
    // 前景でも充電中でもCPU秒あたりの効率が最良になる1にする。
    func testLowPowerModeAlwaysUsesASingleThread() {
        XCTAssertEqual(
            VoicevoxThreadPolicy.automaticThreadCount(isBackground: false, isOnExternalPower: true, isLowPowerModeEnabled: true),
            1
        )
    }

    // 計測用の明示指定は状況に関わらず尊重する。
    func testFixedModeIgnoresTheSituation() {
        XCTAssertEqual(
            VoicevoxThreadPolicy.desiredThreadCount(mode: .fixed(4), isBackground: true, isOnExternalPower: false, isLowPowerModeEnabled: false),
            4
        )
        XCTAssertEqual(
            VoicevoxThreadPolicy.desiredThreadCount(mode: .fixed(0), isBackground: true, isOnExternalPower: false, isLowPowerModeEnabled: false),
            0,
            "明示的に選んだ「自動(全コア)」も尊重する"
        )
    }

    func testAutomaticModeFollowsTheSituation() {
        XCTAssertEqual(
            VoicevoxThreadPolicy.desiredThreadCount(mode: .automatic, isBackground: true, isOnExternalPower: false, isLowPowerModeEnabled: false),
            1
        )
        XCTAssertEqual(
            VoicevoxThreadPolicy.desiredThreadCount(mode: .automatic, isBackground: false, isOnExternalPower: false, isLowPowerModeEnabled: false),
            0
        )
    }

    // 0 は「全コア」なので、数値としては小さくても「一番多い」として扱う事。
    // これを間違えると、危険な方向(増やす)を即座に、安全な方向(減らす)を遅延、
    // という真逆の挙動になる。
    func testZeroCountsAsTheLargestThreadCount() {
        XCTAssertGreaterThan(VoicevoxThreadPolicy.weight(of: 0), VoicevoxThreadPolicy.weight(of: 8))
    }

    // 減らす方向(=これ以上CPUを使うと殺される側)は間隔を空けずに即座に行う事。
    // 「前景で再生開始 → ロック画面 → 電源を抜く」で全コアのまま走り続けると
    // 強制終了されるため、ここが遅延してはいけない。
    func testDecreasingIsAppliedImmediately() {
        XCTAssertTrue(VoicevoxThreadPolicy.shouldReconfigure(current: 0, desired: 1, secondsSinceLastChange: 0))
        XCTAssertTrue(VoicevoxThreadPolicy.shouldReconfigure(current: 4, desired: 1, secondsSinceLastChange: 0))
    }

    // 増やす方向は急がないので間隔を空ける。
    // synthesizer の作り直しには音声モデルの再ロードが伴うため、電源の抜き差しで
    // 往復されるとその度に合成が止まってしまう。
    func testIncreasingIsDelayedToAvoidThrashing() {
        XCTAssertFalse(VoicevoxThreadPolicy.shouldReconfigure(current: 1, desired: 0, secondsSinceLastChange: 1))
        XCTAssertTrue(VoicevoxThreadPolicy.shouldReconfigure(current: 1, desired: 0, secondsSinceLastChange: 60))
    }

    func testNoChangeMeansNoReconfigure() {
        XCTAssertFalse(VoicevoxThreadPolicy.shouldReconfigure(current: 1, desired: 1, secondsSinceLastChange: 9999))
        XCTAssertFalse(VoicevoxThreadPolicy.shouldReconfigure(current: 0, desired: 0, secondsSinceLastChange: 9999))
    }
}
