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

    private func makeBlock(text: String, type: String, delay: TimeInterval) -> SpeechBlockInfo {
        return SpeechBlockInfo(speechText: text, displayText: text, voiceIdentifier: "1", locale: "ja-JP", pitch: 1, rate: 1, volume: 1, delay: delay, isMod: false, type: type)
    }

    // 元々の1ピースがハード上限(120字)を超えている場合でも、VOICEVOXブロックは
    // 上限以下に分割される事を確認する。初期分割は moreSplitMinimumLetterCount(既定200)を
    // 超えてから次の句読点で切る仕様のため、200文字超の単独ピースは普通に発生する。
    // 従来の上限判定は「ピース同士の連結を止める」だけで単独の長いピースは素通しだったため、
    // 実機で234文字のブロックがそのままONNX Runtimeに渡り、その入力サイズに応じた
    // 内部メモリ(解放されず使い回される)が確保されて「メモリがガツンと増えて戻らない」
    // 現象の一因になっていた。
    func testOversizedSinglePieceIsSplitForVoicevox() {
        // 句読点を含む長文(1ピース233文字)を1つのピースとして渡す
        let longText = String(repeating: "あいうえおかきくけこさしすせそ、たちつてとなにぬねの。", count: 9) // 26*9=234文字
        let blocks = [makeBlock(text: longText, type: "VOICEVOX")]
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: blocks, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: ["。", "、"])
        XCTAssertGreaterThan(combined.count, 1, "上限超えの単独ピースは分割されるべき")
        for block in combined {
            XCTAssertLessThanOrEqual(block.displayText.count, 120, "分割後の各ブロックはハード上限以下であるべき")
        }
        // 分割しても本文が欠けたり重複したりしない事
        XCTAssertEqual(combined.map { $0.displayText }.joined(), longText)
        // 区切り文字での分割なので、各ピースは句読点で終わっているはず(最後のピース以外)
        for block in combined.dropLast() {
            let last = block.displayText.last
            XCTAssertTrue(last == "。" || last == "、", "自然な区切り(句読点)で分割されるべき。実際: \(String(describing: last))")
        }
    }

    // 上限超えピースにdelayが付いていた場合、分割後は最後のピースにだけdelayが引き継がれる事を確認する
    // (delayはブロック再生完了「後」に挟まる待ち時間のため)。
    func testOversizedPieceSplitKeepsDelayOnLastPiece() {
        let longText = String(repeating: "あいうえおかきくけこ、", count: 15) // 165文字
        let blocks = [makeBlock(text: longText, type: "VOICEVOX", delay: 3.0)]
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: blocks, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: ["。", "、"])
        XCTAssertGreaterThan(combined.count, 1)
        for block in combined.dropLast() {
            XCTAssertEqual(block.delay, 0, "途中のピースにdelayが入ってはいけない")
        }
        XCTAssertEqual(combined.last?.delay, 3.0, "delayは最後のピースに引き継がれるべき")
    }

    // AVSpeechSynthesizer側は従来通り長い単独ピースも分割されない事を確認する(回帰防止)。
    func testOversizedSinglePieceIsNotSplitForAVSpeech() {
        let longText = String(repeating: "あいうえおかきくけこさしすせそ、たちつてとなにぬねの。", count: 9)
        let blocks = [makeBlock(text: longText, type: "AVSpeechSynthesizer")]
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: blocks, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: ["。", "、"])
        XCTAssertEqual(combined.count, 1, "AVSpeechSynthesizerのピースは従来通り分割されない")
        XCTAssertEqual(combined.first?.displayText, longText)
    }

    // delayを持つピースの直後に、delay=0の短いピースが続いても同じブロックへ merge されない事を
    // 確認する(mergeされてしまうと、delayが実際に効くタイミングが本来より後ろへずれてしまう)。
    // 実機で「短いピースに設定した「読み上げ時の間」が、直後のテキストとまとめて読まれた後まで
    // 遅れて発動する(結果、意図した位置では間が無いように聞こえる)」という形で確認された不具合。
    func testDelayBearingPieceDoesNotAbsorbFollowingText() {
        let delayPiece = makeBlock(text: "ことせかいという名前は、", type: "VOICEVOX", delay: 3.0)
        let followingPiece = makeBlock(text: "iOSの音声合成エンジンが", type: "VOICEVOX", delay: 0)
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: [delayPiece, followingPiece], moreSplitMinimumLetterCount: 40, splitTargetLastLetters: ["。", "、"])
        XCTAssertEqual(combined.count, 2, "delayを持つピースの後には別のピースを追加してはいけない")
        XCTAssertEqual(combined.first?.displayText, "ことせかいという名前は、")
        XCTAssertEqual(combined.first?.delay, 3.0)
    }
}
