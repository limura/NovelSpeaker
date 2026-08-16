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
    // 句読点が一切無い場合でも、絶対上限で必ず区切られる事(メモリ保護)。
    func testVoicevoxBlocksAreCappedEvenWithoutValidSuffix() {
        let piece = "あいうえおかきくけこ" // 10文字、句読点なし
        let blocks = Array(repeating: makeBlock(text: piece, type: "VOICEVOX"), count: 30) // 計300文字
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: blocks, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        XCTAssertGreaterThan(combined.count, 1, "区切りが無くてもVOICEVOXは複数ブロックに分かれるべき")
        for block in combined {
            // 句読点で終われない場合は絶対上限まで伸ばすが、そこは必ず超えない。
            XCTAssertLessThanOrEqual(block.displayText.count, 160, "VOICEVOXブロックは絶対上限を超えてはいけない")
        }
    }

    // ハード上限に達しても、語の途中(句読点等で終わっていない)ならもう少し伸ばして
    // 自然な切れ目で閉じる。実機で「一応志望」|「校のＡ判定にはぎりぎり…」や
    // 「彼」|「らの学力は決して低くない」のように語の途中で分断され、
    // 不自然な発話になっていたための対処。
    func testVoicevoxBlockPrefersPunctuationBoundaryOverHardCap() {
        // 10文字のピースを並べ、120文字を超えた直後ではなく「。」で終わる位置で閉じさせる。
        var pieces = Array(repeating: makeBlock(text: "あいうえおかきくけこ", type: "VOICEVOX"), count: 13) // 130文字
        pieces.append(makeBlock(text: "さしすせそ。", type: "VOICEVOX")) // ここで自然に閉じられる
        pieces.append(contentsOf: Array(repeating: makeBlock(text: "たちつてとなにぬねの", type: "VOICEVOX"), count: 3))
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: pieces, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        let first = try! XCTUnwrap(combined.first)
        XCTAssertTrue(first.displayText.hasSuffix("。"),
                      "上限を少し超えてでも句読点で閉じるべき。実際の末尾: \(String(first.displayText.suffix(8)))")
        XCTAssertLessThanOrEqual(first.displayText.count, 160, "絶対上限は超えない")
    }

    // 絶対上限まで待っても自然な切れ目が来ない原因が「次のピースが長い」場合、
    // そのピースの先頭にある句読点までだけを取り込んでブロックを閉じる。
    //
    // 実機で観測された例:
    //   [17] 148文字 …「全国模試でも常に順位三桁」
    //   [18]  57文字 「を叩きだしており、目指す大学の…」
    // 148文字の時点では絶対上限(160)に達していないので閉じないが、次のピースを丸ごと
    // 足すと160を超えるため、語の途中(「順位三桁」|「を叩きだしており、」)で分断されていた。
    // 「を叩きだしており、」までなら157文字で収まるので、そこまで取り込んで閉じたい。
    func testVoicevoxBlockAbsorbsLeadingFragmentUpToPunctuationInsteadOfCuttingMidWord() {
        var pieces = Array(repeating: makeBlock(text: "あいうえおかきくけこ", type: "VOICEVOX"), count: 14) // 140文字、句読点なし
        pieces.append(makeBlock(text: "さしすせそ", type: "VOICEVOX")) // 計145文字、まだ語の途中
        // 丸ごと足すと絶対上限(160)を超える長いピース。先頭に「、」がある。
        pieces.append(makeBlock(text: "をたたきだしており、めざすだいがくのごうかくりつはずっと", type: "VOICEVOX"))
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: pieces, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        let first = try! XCTUnwrap(combined.first)
        XCTAssertTrue(first.displayText.hasSuffix("、"),
                      "次のピースの「、」までを取り込んで閉じるべき。実際の末尾: \(String(first.displayText.suffix(12)))")
        XCTAssertLessThanOrEqual(first.displayText.count, 160, "絶対上限は超えない")
        // 取り込んだ残りは失われず、次のブロックの先頭になる事。
        let second = try! XCTUnwrap(combined.dropFirst().first)
        XCTAssertTrue(second.displayText.hasPrefix("めざすだいがく"),
                      "残りが次のブロックの先頭になるべき。実際: \(String(second.displayText.prefix(12)))")
        // 全体の文字列が欠けたり重複したりしていない事。
        let joined = combined.map { $0.displayText }.joined()
        XCTAssertEqual(joined, pieces.map { $0.displayText }.joined(), "分割で文字列が失われてはいけない")
    }

    // 先頭の句読点までを取り込んでも絶対上限を超えてしまう場合は、無理に取り込まない。
    func testVoicevoxBlockDoesNotAbsorbFragmentThatWouldExceedTheAbsoluteMax() {
        var pieces = Array(repeating: makeBlock(text: "あいうえおかきくけこ", type: "VOICEVOX"), count: 15) // 150文字
        // 「、」が遠すぎて、取り込むと160を超えてしまうピース。
        pieces.append(makeBlock(text: "あいうえおかきくけこさしすせそ、たちつてと", type: "VOICEVOX"))
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: pieces, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        for block in combined {
            XCTAssertLessThanOrEqual(block.displayText.count, 160, "絶対上限は超えない")
        }
        let joined = combined.map { $0.displayText }.joined()
        XCTAssertEqual(joined, pieces.map { $0.displayText }.joined(), "分割で文字列が失われてはいけない")
    }

    // 読み替え(mod)で表示文字列と発話文字列が異なるピースは、分割位置の対応関係を
    // 安全に保てないので取り込み分割の対象にしない(既存の分割処理と同じ方針)。
    func testModPieceIsNotSplitForAbsorption() {
        var pieces = Array(repeating: makeBlock(text: "あいうえおかきくけこ", type: "VOICEVOX"), count: 15) // 150文字
        pieces.append(SpeechBlockInfo(speechText: "カネにいとめ、をつけずに", displayText: "金に糸目、をつけずに", voiceIdentifier: "1", locale: "ja-JP", pitch: 1, rate: 1, volume: 1, delay: 0, isMod: true, type: "VOICEVOX"))
        let combined = StoryTextClassifier.ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: pieces, moreSplitMinimumLetterCount: 200, splitTargetLastLetters: [])
        // mod ピースは丸ごとのまま次のブロックへ回る(途中で切られない)。
        XCTAssertTrue(combined.contains { $0.displayText.contains("金に糸目、をつけずに") },
                      "modピースは分割されずにそのまま残るべき")
        XCTAssertTrue(combined.contains { $0.speechText.contains("カネにいとめ、をつけずに") },
                      "modピースの発話文字列も保たれるべき")
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
