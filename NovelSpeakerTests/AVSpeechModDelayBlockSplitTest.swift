//
//  AVSpeechModDelayBlockSplitTest.swift
//  NovelSpeakerTests
//
//  AVSpeechSynthesizer 話者でも、読み替え(mod)+「間の設定」(wait config)が絡むと
//  ブロックが「最後の読み替えヒット位置」で分断されてしまう問題の回帰テスト。
//  (Apple Watch 実機の [BLOCKDUMP] で「…コーネリアは快人」/「たちと共に…移動していた。」の
//   ように語の途中で分割されているのが観測された)
//  原因は「delay 付きピースは前のブロックへ連結できない」という Add() の制約で、
//  VOICEVOX では AbsorbTrailingDelayBlock による吸収で解決済みだったものを
//  全エンジンに適用することで、ブロックが句読点(delay の付く位置)まで
//  一つの発話単位に纏まることを確認する。
//

import XCTest
@testable import NovelSpeaker

class AVSpeechModDelayBlockSplitTest: XCTestCase {

    private func makeAVSpeechSpeakerSetting() -> SpeakerSetting {
        let realmSetting = RealmSpeakerSetting()
        realmSetting.type = "AVSpeechSynthesizer"
        return SpeakerSetting(from: realmSetting)
    }

    private func makeWaitConfig(target: String, delay: Float) -> NovelSpeaker.SpeechWaitConfig {
        let realm = RealmSpeechWaitConfig()
        realm.targetText = target
        realm.delayTimeInSec = delay
        return NovelSpeaker.SpeechWaitConfig(from: realm)
    }

    // Watch 実機で観測されたパターンの縮小再現:
    // 「。」に 0.1 秒の間 + 文中に読み替えヒットがあると、
    // 修正前は「…コーネリアは快人」と「たちと共に…移動していた。」の2ブロックに割れていた。
    func testModHitDoesNotSplitBlockForAVSpeech() {
        let text = "予想外の事態ではあるがエリスとコーネリアは快人たちと共に移動していた。問題は今後の展開である。"
        let mods = [
            SpeechModSetting(before: "快人", after: "かいと", isUseRegularExpression: false),
            SpeechModSetting(before: "今後", after: "コンご", isUseRegularExpression: false),
        ]
        let blocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeAVSpeechSpeakerSetting(),
            sectionConfigList: [],
            waitConfigList: [makeWaitConfig(target: "。", delay: 0.1)],
            speechModArray: mods
        )
        XCTAssertEqual(blocks.count, 2, "文単位(「。」区切り)の2ブロックになるはず。実際: \(blocks.map { $0.displayText })")
        guard blocks.count == 2 else { return }

        XCTAssertEqual(blocks[0].displayText, "予想外の事態ではあるがエリスとコーネリアは快人たちと共に移動していた。")
        XCTAssertEqual(blocks[0].speechText, "予想外の事態ではあるがエリスとコーネリアはかいとたちと共に移動していた。", "読み替えが前後と繋がったまま1ブロックに入るはず")
        XCTAssertEqual(blocks[0].delay, TimeInterval(Float(0.1)), accuracy: 0.001, "間は文末(「。」の後)に付くはず")

        XCTAssertEqual(blocks[1].displayText, "問題は今後の展開である。")
        XCTAssertEqual(blocks[1].speechText, "問題はコンごの展開である。")
        XCTAssertEqual(blocks[1].delay, TimeInterval(Float(0.1)), accuracy: 0.001)
    }

    // 読み替えの無い文はこれまで通り文単位のまま(吸収処理が余計な結合をしない)事の確認。
    func testPlainSentencesKeepSentenceBoundary() {
        let text = "一つ目の文である。二つ目の文である。"
        let blocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeAVSpeechSpeakerSetting(),
            sectionConfigList: [],
            waitConfigList: [makeWaitConfig(target: "。", delay: 0.1)],
            speechModArray: []
        )
        XCTAssertEqual(blocks.map { $0.displayText }, ["一つ目の文である。", "二つ目の文である。"])
        for block in blocks {
            XCTAssertEqual(block.delay, TimeInterval(Float(0.1)), accuracy: 0.001)
        }
    }
}
