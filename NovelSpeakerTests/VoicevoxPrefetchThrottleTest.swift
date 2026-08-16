//
//  VoicevoxPrefetchThrottleTest.swift
//  NovelSpeakerTests
//
//  バックグラウンド再生中に iOS の CPU 上限(60秒平均80%)で強制終了された
//  (cpu_resource_fatal / "Action taken: Process killed")件への対策である、
//  先行合成の絞り込みポリシーのテスト。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxPrefetchThrottleTest: XCTestCase {

    private let normal = VoicevoxPrefetchThrottlePolicy.normal
    private let throttled = VoicevoxPrefetchThrottlePolicy.throttled

    // 前景では従来どおりの積極的な先読みを維持する(このCPU上限は背面のみ対象のため)。
    func testForegroundIsNotThrottled() {
        for onExternalPower in [true, false] {
            for lowPower in [true, false] {
                let p = VoicevoxPrefetchThrottlePolicy.parameters(isBackground: false, isOnExternalPower: onExternalPower, isLowPowerModeEnabled: lowPower)
                XCTAssertEqual(p, normal, "前景では絞らないはず (power=\(onExternalPower) lowPower=\(lowPower))")
            }
        }
    }

    // 実機で落ちた条件そのもの: 背面 + バッテリー駆動 → 絞る。
    func testBackgroundOnBatteryIsThrottled() {
        let p = VoicevoxPrefetchThrottlePolicy.parameters(isBackground: true, isOnExternalPower: false, isLowPowerModeEnabled: false)
        XCTAssertEqual(p, throttled, "背面+バッテリーでは絞るはず")
    }

    // 実機で落ちなかった条件: 背面でも AC 接続中は CPU 上限が適用されないので絞らない。
    func testBackgroundOnExternalPowerIsNotThrottled() {
        let p = VoicevoxPrefetchThrottlePolicy.parameters(isBackground: true, isOnExternalPower: true, isLowPowerModeEnabled: false)
        XCTAssertEqual(p, normal, "背面でも充電中は絞らないはず")
    }

    // 低電力モードでは CPU クロックが落ちて追いつけなくなるので、充電中でも絞る。
    func testLowPowerModeIsThrottledEvenOnExternalPower() {
        let p = VoicevoxPrefetchThrottlePolicy.parameters(isBackground: true, isOnExternalPower: true, isLowPowerModeEnabled: true)
        XCTAssertEqual(p, throttled, "低電力モードでは充電中でも絞るはず")
    }

    // 絞った側が前景側を上回らない事(定数を後から触った時の保険)。
    //
    // かつては「背面では厳しく絞る」のが CPU 上限対策の主役だったが、現在は
    // VoicevoxCPUGovernor が合成の直前に予算を見て待たせる方式になっている。
    // ここで絞り過ぎるとむしろ有害で、予約が尽きてワーカーが手空きになり、
    // 予算が余っているのに合成が止まってしまう(実機で確認)。
    // そのため「厳密に小さい」ではなく「上回らない」を保証する。
    func testThrottledParametersAreNotLargerThanNormal() {
        XCTAssertLessThanOrEqual(throttled.maxBlockCountToQueue, normal.maxBlockCountToQueue)
        XCTAssertLessThanOrEqual(throttled.targetCharacterCount, normal.targetCharacterCount)
        XCTAssertLessThanOrEqual(throttled.minimumBlockCount, normal.minimumBlockCount)
        XCTAssertLessThanOrEqual(throttled.maxBlocksToScan, normal.maxBlocksToScan)
        // 予約が尽きるとワーカーが手空きになるので、次の1つだけ、では足りない。
        XCTAssertGreaterThanOrEqual(throttled.maxBlockCountToQueue, 2)
        XCTAssertGreaterThanOrEqual(throttled.minimumBlockCount, 1)
    }

    // 総リード量の上限。これが効かないと、1回あたりのブロック数を絞っても
    // 先行合成が延々と CPU を焼き続け、(a)背面CPU上限で強制終了され、
    // (b)再生に必要な合成が待ち行列に並ばされて無音になる、の両方が起きる。
    func testTargetLeadSecondsIsBoundedAndSmallerWhenThrottled() {
        XCTAssertGreaterThan(throttled.targetLeadSeconds, 0, "背面でも次のブロックぶんは貯める")
        XCTAssertLessThan(throttled.targetLeadSeconds, normal.targetLeadSeconds,
                          "背面バッテリー時の方が貯金の上限は小さいはず")
        // 前景/充電中でも無制限にはしない(メモリとキャッシュ容量の都合)。
        XCTAssertLessThanOrEqual(normal.targetLeadSeconds, 600)
    }
}
