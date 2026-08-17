//
//  StoryTextClassifierSpeechModOrderTest.swift
//  NovelSpeakerTests
//
//  読み替え辞書を「本文に依らない分は先に並べ替えておいて、本文ごとに変わる分だけを
//  後から併合する」高速化を入れた。その結果が、従来どおり全部まとめて並べ替えた場合と
//  **完全に同じブロック列**になる事を確かめる。
//
//  ここが1文字でもずれると、同じ本文から違うブロックが出来て、事前に作ってある
//  VOICEVOX 音声キャッシュが一切命中しなくなる。しかもその症状は「無音が減らない」
//  という形でしか現れず、原因が極めて分かりにくい。
//

import XCTest
@testable import NovelSpeaker

class StoryTextClassifierSpeechModOrderTest: XCTestCase {

    private func loadDefaultSpeechModArray() -> [NovelSpeaker.SpeechModSetting] {
        guard let path = Bundle.main.path(forResource: "DefaultSpeechModList", ofType: "json"),
              let data = FileManager.default.contents(atPath: path),
              let array = try? JSONDecoder().decode([NovelSpeakerUtility.SpeechModSetting].self, from: data) else {
            return []
        }
        return array.map {
            NovelSpeaker.SpeechModSetting(before: $0.before, after: $0.after, isUseRegularExpression: $0.isRegexp ?? false)
        }
    }

    private func makeSpeakerSetting(type: String, voiceIdentifier: String) -> SpeakerSetting {
        let realmSetting = RealmSpeakerSetting()
        realmSetting.type = type
        realmSetting.voiceIdentifier = voiceIdentifier
        realmSetting.locale = "ja-JP"
        return SpeakerSetting(from: realmSetting)
    }

    private static let plainText = """
　少女は窓の外を眺めながら、そう答えた。空は抜けるように青く、遠くの山並みまではっきりと見えている。
「なあ、春菜。この村から出た事あるか？　実際、100話くらい読んだんだけどさ」
「ううん、一度も無いよ。だって、外は危ないって皆が言うんだもの」
　こんな日は、どこか遠くへ行ってみたくなる。けれども、村の外に出るには相応の覚悟が必要だった。
"""

    private static let rubyText = """
｜親譲《おやゆず》りの｜無鉄砲《むてっぽう》で｜小供《こども》の時から｜損《そん》ばかりしている。
｜小学校《しょうがっこう》に｜居《い》る時分｜学校《がっこう》の｜二階《にかい》から｜飛《と》び｜降《お》りて｜一週間《いっしゅうかん》ほど｜腰《こし》を｜抜《ぬ》かした｜事《こと》がある。
「なぜそんな｜無闇《むやみ》をしたと｜聞《き》く人があるかも知れぬ」
"""

    /// 従来の経路(全部まとめて並べ替え)と、新しい経路(先に並べ替えた分と併合)の
    /// 結果が一致する事を確かめる。
    private func assertSameBlocks(content: String, additionalMods: [NovelSpeaker.SpeechModSetting], file: StaticString = #filePath, line: UInt = #line) {
        let defaultMods = loadDefaultSpeechModArray()
        XCTAssertGreaterThan(defaultMods.count, 1000, "標準の読み替え辞書が読めていない", file: file, line: line)

        let narrator = makeSpeakerSetting(type: "VOICEVOX", voiceIdentifier: "2")
        let dialogue = makeSpeakerSetting(type: "VOICEVOX", voiceIdentifier: "3")
        let sectionConfigList = [SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: dialogue)]
        let splitTargets = ["。", "、", "　", "\n"]

        let old = StoryTextClassifier.CategorizeStoryText(
            content: content, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
            defaultSpeaker: narrator, sectionConfigList: sectionConfigList, waitConfigList: [],
            speechModArray: defaultMods + additionalMods)

        // 実際の使われ方と同じ切り分け方をする:
        //  本文に依らない分(正規表現でない標準辞書)= 先に並べ替えておく
        //  本文ごとに変わる分(正規表現・ルビ・利用者の追加)= 毎回並べ替えて併合する
        let isContentDependent: (NovelSpeaker.SpeechModSetting) -> Bool = { mod in
            if mod.isUseRegularExpression { return true }
            return additionalMods.contains(where: { extra in extra.before == mod.before && extra.after == mod.after })
        }
        let preSorted = StoryTextClassifier.IndexSpeechModArray(
            sortedSpeechModArray: StoryTextClassifier.UniqSpeechModArray(
                speechModArray: StoryTextClassifier.SpeechModArraySort(
                    speechModArray: (defaultMods + additionalMods).filter { isContentDependent($0) == false })))
        let contentDependent = (defaultMods + additionalMods).filter { isContentDependent($0) }
        let new = StoryTextClassifier.CategorizeStoryText(
            content: content, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
            defaultSpeaker: narrator, sectionConfigList: sectionConfigList, waitConfigList: [],
            indexedPreSortedSpeechModArray: preSorted, contentDependentSpeechModArray: contentDependent)

        XCTAssertEqual(old.count, new.count, "ブロックの数が変わっている", file: file, line: line)
        for (index, oldBlock) in old.enumerated() {
            guard index < new.count else { break }
            XCTAssertEqual(oldBlock.speechText, new[index].speechText, "block[\(index)] の合成する文字列が変わっている", file: file, line: line)
            XCTAssertEqual(oldBlock.displayText, new[index].displayText, "block[\(index)] の表示文字列が変わっている", file: file, line: line)
            XCTAssertEqual(oldBlock.voiceIdentifier, new[index].voiceIdentifier, "block[\(index)] の話者が変わっている", file: file, line: line)
        }
    }

    func testSameResultForPlainText() {
        assertSameBlocks(content: Self.plainText, additionalMods: [])
    }

    // ルビ由来の読み替え(本文ごとに変わる)が混ざっても同じになる事。
    func testSameResultWithRubyMods() {
        let rubyMods = StoryTextClassifier.GenerateRubyModString(text: Self.rubyText, notRubyString: "", isDisableNarouRuby: false)
        XCTAssertGreaterThan(rubyMods.count, 10, "ルビ由来の読み替えが作られていない")
        assertSameBlocks(content: Self.rubyText, additionalMods: rubyMods)
    }

    // 利用者が足した読み替え(標準辞書と同じ before を別の after で上書きする等)が
    // 混ざっても同じになる事。並べ替えの同着の扱いが変わりやすい所なので確かめる。
    func testSameResultWithUserModsThatCollideWithDefaults() {
        let mods = [
            NovelSpeaker.SpeechModSetting(before: "実際", after: "ジッサイ", isUseRegularExpression: false),
            NovelSpeaker.SpeechModSetting(before: "春菜", after: "ハルナ", isUseRegularExpression: false),
            NovelSpeaker.SpeechModSetting(before: "[0-9]+話", after: "話数", isUseRegularExpression: true),
        ]
        assertSameBlocks(content: Self.plainText, additionalMods: mods)
    }

    // 併合そのものが、連結してから並べ替えた物と同じ順になる事。
    func testMergeMatchesFullSort() {
        let defaultMods = loadDefaultSpeechModArray().filter { $0.isUseRegularExpression == false }
        let extra = [
            NovelSpeaker.SpeechModSetting(before: "あ", after: "ア", isUseRegularExpression: false),
            NovelSpeaker.SpeechModSetting(before: "実際", after: "ジッサイ", isUseRegularExpression: false),
            NovelSpeaker.SpeechModSetting(before: "とてもながいよみかえたいもじれつ", after: "長い", isUseRegularExpression: false),
        ]
        let merged = StoryTextClassifier.UniqSpeechModArray(speechModArray:
            StoryTextClassifier.MergeSortedSpeechModArray(
                StoryTextClassifier.SpeechModArraySort(speechModArray: defaultMods),
                StoryTextClassifier.SpeechModArraySort(speechModArray: extra)))
        let fullySorted = StoryTextClassifier.UniqSpeechModArray(speechModArray:
            StoryTextClassifier.SpeechModArraySort(speechModArray: defaultMods + extra))
        XCTAssertEqual(merged.count, fullySorted.count)
        for (index, entry) in fullySorted.enumerated() {
            guard index < merged.count else { break }
            XCTAssertEqual(merged[index].before, entry.before, "\(index)番目の before が違う")
            XCTAssertEqual(merged[index].after, entry.after, "\(index)番目の after が違う")
        }
    }
}
