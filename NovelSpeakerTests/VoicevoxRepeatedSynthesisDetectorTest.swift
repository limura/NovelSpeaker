//
//  VoicevoxRepeatedSynthesisDetectorTest.swift
//  NovelSpeakerTests
//
//  「同じ本文を二度合成していないか」の見張りのテスト。
//
//  この見張りが要るのは、二度手間が**実験でしか気づけなかった**ため。
//  端末が冷えるのを待って30分読み上げさせ、貯金が増えるかを見る、という
//  手間のかかる確かめ方しか無かった。実際、合成のちょうど半分を捨てている
//  状態が数日続いていた。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxRepeatedSynthesisDetectorTest: XCTestCase {

    override func setUp() {
        super.setUp()
        VoicevoxRepeatedSynthesisDetector.shared.reset()
    }

    override func tearDown() {
        VoicevoxRepeatedSynthesisDetector.shared.reset()
        super.tearDown()
    }

    // 違う本文を順に合成していくだけなら、作り直しは0であるべき。
    func testDistinctTextsAreNotCountedAsRepeats() {
        let detector = VoicevoxRepeatedSynthesisDetector.shared
        for i in 0..<50 {
            XCTAssertFalse(detector.noteSynthesisStarting(key: "block\(i)"))
        }
        XCTAssertEqual(detector.counts.repeated, 0)
        XCTAssertTrue(detector.isHealthy())
    }

    // 同じ鍵が二度出てきたら二度目として数える事。
    func testSameKeyIsReportedAsRepeat() {
        let detector = VoicevoxRepeatedSynthesisDetector.shared
        XCTAssertFalse(detector.noteSynthesisStarting(key: "同じ本文"))
        XCTAssertTrue(detector.noteSynthesisStarting(key: "同じ本文"))
        XCTAssertEqual(detector.counts.total, 2)
        XCTAssertEqual(detector.counts.repeated, 1)
    }

    // 実機で起きていた状態(全てのブロックを二度ずつ合成)を、
    // 30分の実験ではなくその場で異常と判定できる事。
    func testEveryBlockSynthesizedTwiceIsDetectedAsUnhealthy() {
        let detector = VoicevoxRepeatedSynthesisDetector.shared
        for i in 0..<50 {
            detector.noteSynthesisStarting(key: "block\(i)")
            detector.noteSynthesisStarting(key: "block\(i)")   // 相手も同じ物を作ってしまった
        }
        XCTAssertEqual(detector.repeatedRatio, 0.5, accuracy: 0.001)
        XCTAssertFalse(detector.isHealthy(), "半分を捨てている状態は異常と判定されるべき")
    }

    // 巻き戻しでの作り直しが数本混ざる程度では、異常とは言わない事。
    func testAFewRewindsDoNotTripTheAlarm() {
        let detector = VoicevoxRepeatedSynthesisDetector.shared
        for i in 0..<100 {
            detector.noteSynthesisStarting(key: "block\(i)")
        }
        for i in 0..<3 {
            detector.noteSynthesisStarting(key: "block\(i)")   // 少し戻して聴き直した
        }
        XCTAssertTrue(detector.isHealthy())
    }

    // 本数が少ないうちは判定しない事(最初の数本では揺れるため)。
    func testDoesNotJudgeBeforeEnoughSamples() {
        let detector = VoicevoxRepeatedSynthesisDetector.shared
        detector.noteSynthesisStarting(key: "A")
        detector.noteSynthesisStarting(key: "A")
        XCTAssertTrue(detector.isHealthy(), "2本で異常と言い出してはいけない")
    }

    // 覚えておく数を超えた分は忘れる(際限なくメモリを食わない)。
    // 忘れた所を作り直しても、それは二度目として数えられない。
    func testOldKeysAreForgotten() {
        let detector = VoicevoxRepeatedSynthesisDetector.shared
        detector.noteSynthesisStarting(key: "最初のブロック")
        for i in 0..<VoicevoxRepeatedSynthesisDetector.capacity {
            detector.noteSynthesisStarting(key: "block\(i)")
        }
        XCTAssertFalse(detector.noteSynthesisStarting(key: "最初のブロック"),
                       "溢れて忘れた鍵は二度目として数えられない")
    }
}
