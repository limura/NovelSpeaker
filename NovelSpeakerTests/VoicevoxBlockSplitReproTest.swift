//
//  VoicevoxBlockSplitReproTest.swift
//  NovelSpeakerTests
//
//  読み替え(mod)+「間の設定」(wait config)が絡むと、ブロックが語の途中
//  ("読み上げ|る")で分割され、かつ間が本来より前で発動してしまう不具合の
//  再現・回帰テスト。原因は generateBlockFromSpeechMod が「間」の遅延をチャンクの
//  最後のピースではなく最初のピースに付けていたこと(遅延付きピースは連結できない
//  ため、mod で分かれたチャンクの先頭に遅延が乗ると語の途中で分断されていた)。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxBlockSplitReproTest: XCTestCase {

    private func makeVoicevoxSpeakerSetting(styleId: UInt32) -> SpeakerSetting {
        let realmSetting = RealmSpeakerSetting()
        realmSetting.type = "VOICEVOX"
        realmSetting.voiceIdentifier = "\(styleId)"
        realmSetting.locale = "ja-JP"
        return SpeakerSetting(from: realmSetting)
    }

    private func makeWaitConfig(target: String, delay: Float) -> NovelSpeaker.SpeechWaitConfig {
        let realm = RealmSpeechWaitConfig()
        realm.targetText = target
        realm.delayTimeInSec = delay
        return NovelSpeaker.SpeechWaitConfig(from: realm)
    }

    // 標準辞書に実在するエントリを再現: る奴→るヤツ, 例え→たとえ
    private let mods = [
        SpeechModSetting(before: "る奴", after: "るヤツ", isUseRegularExpression: false),
        SpeechModSetting(before: "例え", after: "たとえ", isUseRegularExpression: false),
    ]

    // 標準辞書由来(targetSpeechEngineTypeArray=["AVSpeechSynthesizer"])の読み替えは、VOICEVOX話者には
    // 適用されず、AVSpeechSynthesizer話者には適用される事を確認する。
    // 実機の「実際→"実際" の読み替えで " が入り、その " の位置でブロックが分割される」
    // という不具合はこれで解消される(VOICEVOXでは " が入らないので分割もされない)。
    func testDefaultDictionaryModIsSkippedForVoicevox() {
        let text = "をタップすることで実際に読み替えが行われた"
        // 「実際」→「"実際"」(標準辞書由来を想定して AVSpeechSynthesizer 専用にする)
        let avSpeechOnlyMod = SpeechModSetting(before: "実際", after: "\"実際\"", isUseRegularExpression: false, targetSpeechEngineTypeArray: ["AVSpeechSynthesizer"])

        // VOICEVOX話者: 標準辞書modは適用されない → 発話テキストに " が入らない
        let voicevoxBlocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeVoicevoxSpeakerSetting(styleId: 3),
            sectionConfigList: [],
            waitConfigList: [],
            sortedSpeechModArray: [avSpeechOnlyMod]
        )
        let voicevoxSpeech = voicevoxBlocks.map { $0.speechText }.joined()
        XCTAssertFalse(voicevoxSpeech.contains("\""), "VOICEVOXでは標準辞書modが適用されず \" が入らないはず。実際: \(voicevoxSpeech)")
        XCTAssertEqual(voicevoxSpeech, text, "VOICEVOXでは読み替えされず元テキストのままのはず")

        // AVSpeechSynthesizer話者: 標準辞書modは従来通り適用される → " が入る
        let dummy = RealmSpeakerSetting()
        dummy.type = "AVSpeechSynthesizer"
        let avSpeechBlocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: SpeakerSetting(from: dummy),
            sectionConfigList: [],
            waitConfigList: [],
            sortedSpeechModArray: [avSpeechOnlyMod]
        )
        let avSpeechSpeech = avSpeechBlocks.map { $0.speechText }.joined()
        XCTAssertTrue(avSpeechSpeech.contains("\"実際\""), "AVSpeechSynthesizerでは標準辞書modが適用され \"実際\" になるはず。実際: \(avSpeechSpeech)")
    }

    func testDumpBlocksForModScenario() {
        let text = "今作ってるアプリはWeb小説を読み上げる奴なんだけどさ、色々読み間違えるんだよね。例えば"
        let blocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeVoicevoxSpeakerSetting(styleId: 3),
            sectionConfigList: [],
            waitConfigList: [],
            sortedSpeechModArray: mods
        )
        for (i, b) in blocks.enumerated() {
            NSLog("NOSECTION BLOCK[\(i)] display=\"\(b.displayText)\" speech=\"\(b.speechText)\"")
        }
        for b in blocks {
            XCTAssertFalse(b.displayText.hasSuffix("読み上げ"), "「読み上げる」が途中で切れている: \(b.displayText)")
        }
    }

    // 実機シナリオ: 「」で囲まれた会話文に別話者(VOICEVOX)を割り当てた状態。
    // この時に「読み上げる」が「読み上げ」「る」で分断される不具合を再現する。
    func testDumpBlocksForModScenarioWithSection() {
        let text = "「今作ってるアプリはWeb小説を読み上げる奴なんだけどさ、色々読み間違えるんだよね。例えば」"
        let sectionConfigList = [SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: makeVoicevoxSpeakerSetting(styleId: 6))]
        let blocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeVoicevoxSpeakerSetting(styleId: 3),
            sectionConfigList: sectionConfigList,
            waitConfigList: [],
            sortedSpeechModArray: mods
        )
        for (i, b) in blocks.enumerated() {
            NSLog("SECTION BLOCK[\(i)] display=\"\(b.displayText)\" speech=\"\(b.speechText)\"")
        }
        for b in blocks {
            XCTAssertFalse(b.displayText.hasSuffix("読み上げ"), "「読み上げる」が途中で切れている: \(b.displayText)")
        }
    }

    // 「間の設定」(wait config)が 。 と 、 に設定されている場合。delay付きピースは連結を拒否する
    // ガードがあるため、これが「読み上げ|る」の分断を誘発するか検証する。
    func testDumpBlocksWithWaitConfig() {
        let text = "「今作ってるアプリはWeb小説を読み上げる奴なんだけどさ、色々読み間違えるんだよね。例えば」"
        let sectionConfigList = [SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: makeVoicevoxSpeakerSetting(styleId: 6))]
        let waitConfigList = [
            makeWaitConfig(target: "。", delay: 0.5),
            makeWaitConfig(target: "、", delay: 0.2),
        ]
        let blocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeVoicevoxSpeakerSetting(styleId: 3),
            sectionConfigList: sectionConfigList,
            waitConfigList: waitConfigList,
            sortedSpeechModArray: mods
        )
        for (i, b) in blocks.enumerated() {
            NSLog("WAIT BLOCK[\(i)] display=\"\(b.displayText)\" speech=\"\(b.speechText)\" delay=\(b.delay)")
        }
        for b in blocks {
            XCTAssertFalse(b.displayText.hasSuffix("読み上げ"), "「読み上げる」が途中で切れている: \(b.displayText)")
            // 「間の設定」由来の遅延は、その句読点で終わるブロックにのみ付くべき
            //(句読点を含まない・途中のブロックに遅延が付いていてはいけない)。
            if b.delay > 0 {
                let last = b.displayText.last
                XCTAssertTrue(last == "。" || last == "、" || last == "」",
                              "遅延は句読点で終わるブロックに付くべき。実際の末尾: \(String(describing: last)) (\(b.displayText))")
            }
        }
    }

    // 実機シナリオにより近い、第1段落全体(「」の外にも本文があり、「」の中に『』の入れ子セクションもある)。
    func testDumpBlocksForFullParagraph() {
        let text = "ことせかい という名前は、iOS の音声合成エンジンが「異世界」という単語を「ことせかい」と発話した事からきています。 「今作ってるアプリはWeb小説を読み上げる奴なんだけどさ、色々読み間違えるんだよね。例えば『異世界』を『ことせかい』って読むから笑っちゃうんだよ」という感じで説明していたら"
        let sectionConfigList = [
            SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: makeVoicevoxSpeakerSetting(styleId: 3)),
            SpeechSectionConfig(startText: "『", endText: "』", speakerSetting: makeVoicevoxSpeakerSetting(styleId: 6)),
        ]
        let allMods = [
            SpeechModSetting(before: "異世界", after: "イセカイ", isUseRegularExpression: false),
            SpeechModSetting(before: "る奴", after: "るヤツ", isUseRegularExpression: false),
            SpeechModSetting(before: "例え", after: "たとえ", isUseRegularExpression: false),
        ]
        let blocks = StoryTextClassifier.CategorizeStoryText(
            content: text,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 200,
            defaultSpeaker: makeVoicevoxSpeakerSetting(styleId: 8),
            sectionConfigList: sectionConfigList,
            waitConfigList: [],
            sortedSpeechModArray: allMods
        )
        for (i, b) in blocks.enumerated() {
            NSLog("FULL BLOCK[\(i)] display=\"\(b.displayText)\" speech=\"\(b.speechText)\"")
        }
        for b in blocks {
            XCTAssertFalse(b.displayText.hasSuffix("読み上げ"), "「読み上げる」が途中で切れている: \(b.displayText)")
        }
    }
}
