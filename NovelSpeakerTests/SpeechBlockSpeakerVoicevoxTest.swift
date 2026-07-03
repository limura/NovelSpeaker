//
//  SpeechBlockSpeakerVoicevoxTest.swift
//  NovelSpeakerTests
//
//  hasNoSpeakableCharacter() が、句読点・記号・空白だけの文字列("。。。。。。。。。。。。。。。。。"
//  のような装飾的な区切り線等)を正しく検出できることを確認する。実機ではこの種のテキストを
//  VOICEVOXに渡すとOpenJTalkの形態素解析が失敗し("First mora should not be short pause")、
//  そのブロックが無音でスキップされ続ける現象が確認された。
//

import XCTest
@testable import NovelSpeaker

class SpeechBlockSpeakerVoicevoxTest: XCTestCase {

    func testPunctuationOnlyTextHasNoSpeakableCharacter() {
        XCTAssertTrue(SpeechBlockSpeaker.hasNoSpeakableCharacter("。。。。。。。。。。。。。。。。。"))
        XCTAssertTrue(SpeechBlockSpeaker.hasNoSpeakableCharacter("……"))
        XCTAssertTrue(SpeechBlockSpeaker.hasNoSpeakableCharacter("\n\n  \t"))
        XCTAssertTrue(SpeechBlockSpeaker.hasNoSpeakableCharacter(""))
    }

    func testNormalTextHasSpeakableCharacter() {
        XCTAssertFalse(SpeechBlockSpeaker.hasNoSpeakableCharacter("あいうえお。"))
        XCTAssertFalse(SpeechBlockSpeaker.hasNoSpeakableCharacter("こんにちは"))
    }
}
