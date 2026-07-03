//
//  StoryTextClassifierVoicevoxTest.swift
//  NovelSpeakerTests
//
//  ConcatinateSameVoiceSettingSpeechBlock が、VOICEVOXブロックについては
//  (句読点等の区切りが見つからない場合でも)一定の絶対上限を超えては連結しないことを確認する。
//  実機では区切りの無い長文でブロックが際限なく巨大化し、ONNX Runtimeのメモリ確保失敗
//  ("Failed to allocate memory for requested buffer of size 684345600") を引き起こしていた。
//

import XCTest
@testable import NovelSpeaker

class StoryTextClassifierVoicevoxTest: XCTestCase {

    private func makeBlock(text: String, type: String) -> SpeechBlockInfo {
        return SpeechBlockInfo(speechText: text, displayText: text, voiceIdentifier: "1", locale: "ja-JP", pitch: 1, rate: 1, volume: 1, delay: 0, isMod: false, type: type)
    }

    // 区切り文字が一切無い(hasValidSuffixが常にfalseの)長文でも、VOICEVOXブロックは
    // ハード上限(120字)を超えて連結され続けない事を確認する。
    func testVoicevoxBlocksAreCappedEvenWithoutValidSuffix() {
        let piece = "あいうえおかきくけこ" // 10文字、句読点なし
        let blocks = Array(repeating: makeBlock(text: piece, type: "VOICEVOX"), count: 20) // 計200文字
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: blocks, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        XCTAssertGreaterThan(combined.count, 1, "区切りが無くてもVOICEVOXは複数ブロックに分かれるべき")
        for block in combined {
            XCTAssertLessThanOrEqual(block.displayText.count, 120, "VOICEVOXブロックはハード上限を超えてはいけない")
        }
    }

    // 同じ入力でも AVSpeechSynthesizer 側は既存動作のまま
    // (区切りが無ければ1ブロックに巨大化してもよい)である事を確認する。回帰防止。
    func testAVSpeechBlocksKeepExistingUnboundedBehavior() {
        let piece = "あいうえおかきくけこ"
        let blocks = Array(repeating: makeBlock(text: piece, type: "AVSpeechSynthesizer"), count: 20) // 計200文字
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: blocks, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        XCTAssertEqual(combined.count, 1, "AVSpeechSynthesizerは従来通り区切りが無ければ1ブロックのまま")
        XCTAssertEqual(combined.first?.displayText.count, 200)
    }
}
