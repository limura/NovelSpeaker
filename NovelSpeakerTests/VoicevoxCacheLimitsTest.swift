//
//  VoicevoxCacheLimitsTest.swift
//  NovelSpeakerTests
//
//  音声ディスクキャッシュの容量制限のテスト。
//
//  音声1時間ぶんで約15MBなので、長編を何作も貯めると簡単に数GBになる。
//  「気付いたらストレージが足りない」を避けるための線引きが、
//  ちゃんと引かれている事を確かめる。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCacheLimitsTest: XCTestCase {

    private var savedMaximum: Any?
    private var savedMinimumFree: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedMaximum = UserDefaults.standard.object(forKey: VoicevoxCacheLimits.maximumTotalMegabytesUserDefaultsKey)
        savedMinimumFree = UserDefaults.standard.object(forKey: VoicevoxCacheLimits.minimumFreeMegabytesUserDefaultsKey)
    }

    override func tearDownWithError() throws {
        restore(key: VoicevoxCacheLimits.maximumTotalMegabytesUserDefaultsKey, value: savedMaximum)
        restore(key: VoicevoxCacheLimits.minimumFreeMegabytesUserDefaultsKey, value: savedMinimumFree)
        try super.tearDownWithError()
    }

    private func restore(key: String, value: Any?) {
        if let value = value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func megabytes(_ value: Int) -> Int64 { return Int64(value) * 1024 * 1024 }

    func testDefaults() {
        UserDefaults.standard.removeObject(forKey: VoicevoxCacheLimits.maximumTotalMegabytesUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: VoicevoxCacheLimits.minimumFreeMegabytesUserDefaultsKey)
        XCTAssertEqual(VoicevoxCacheLimits.maximumTotalMegabytes, VoicevoxCacheLimits.defaultMaximumTotalMegabytes)
        XCTAssertEqual(VoicevoxCacheLimits.minimumFreeMegabytes, VoicevoxCacheLimits.defaultMinimumFreeMegabytes)
    }

    // 上限に達したら止まる事。
    func testStopsWhenTotalLimitIsReached() {
        VoicevoxCacheLimits.maximumTotalMegabytes = 1000
        VoicevoxCacheLimits.minimumFreeMegabytes = 0
        XCTAssertNil(VoicevoxCacheLimits.stopCause(usedBytes: megabytes(999), freeBytes: nil))
        guard case .totalLimit? = VoicevoxCacheLimits.stopCause(usedBytes: megabytes(1000), freeBytes: nil) else {
            XCTFail("上限に達したら止まるべき")
            return
        }
    }

    // 上限0は「無制限」である事(貯め放題にしたい人がいる)。
    func testZeroMaximumMeansUnlimited() {
        VoicevoxCacheLimits.maximumTotalMegabytes = 0
        VoicevoxCacheLimits.minimumFreeMegabytes = 0
        XCTAssertNil(VoicevoxCacheLimits.stopCause(usedBytes: megabytes(100_000), freeBytes: nil))
    }

    // 空き容量が下限を切ったら止まる事。
    // 上限に余裕があっても、端末が埋まるのは避けなければならない。
    func testStopsWhenFreeSpaceIsLow() {
        VoicevoxCacheLimits.maximumTotalMegabytes = 0
        VoicevoxCacheLimits.minimumFreeMegabytes = 500
        XCTAssertNil(VoicevoxCacheLimits.stopCause(usedBytes: 0, freeBytes: megabytes(501)))
        guard case .freeSpace? = VoicevoxCacheLimits.stopCause(usedBytes: 0, freeBytes: megabytes(500)) else {
            XCTFail("空き容量が下限に達したら止まるべき")
            return
        }
    }

    // 空き容量が取れない環境でも、上限判定だけは効く事(取れないから止め放題、にしない)。
    func testUnknownFreeSpaceDoesNotBlockButLimitStillApplies() {
        VoicevoxCacheLimits.maximumTotalMegabytes = 100
        VoicevoxCacheLimits.minimumFreeMegabytes = 500
        XCTAssertNil(VoicevoxCacheLimits.stopCause(usedBytes: megabytes(50), freeBytes: nil))
        XCTAssertNotNil(VoicevoxCacheLimits.stopCause(usedBytes: megabytes(100), freeBytes: nil))
    }

    // 止まった理由が利用者に伝わる文言になっている事。
    func testStopCauseMessageIsUnderstandable() {
        let cause = VoicevoxCacheLimits.StopCause.totalLimit(usedBytes: megabytes(2048), limitBytes: megabytes(2048))
        XCTAssertTrue(cause.message.contains("2.0GB"))
        let freeCause = VoicevoxCacheLimits.StopCause.freeSpace(freeBytes: megabytes(400), minimumBytes: megabytes(500))
        XCTAssertTrue(freeCause.message.contains("500MB"))
        XCTAssertTrue(freeCause.message.contains("400MB"))
    }
}
