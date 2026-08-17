//
//  StoryTextClassifierBenchmarkTest.swift
//  NovelSpeakerTests
//
//  ブロック分割の各段階に、どれだけ時間が掛かっているかを測る。
//
//  背景: 実機で「作成済み音声の調査」に14ページで8.2秒かかり、内訳は
//  本文読み出し0.06秒 / ブロック分割8.22秒だった(=1ページ約590ms)。
//  分割のどこが重いのかが分からないと手の打ちようが無いので、段階ごとに測る。
//
//  ここは「速いこと」を assert するテストではなく、数値をログに出す計測用。
//  実行環境(母艦のMac)は実機よりずっと速いので、絶対値ではなく**比率**を見る。
//

import XCTest
@testable import NovelSpeaker

class StoryTextClassifierBenchmarkTest: XCTestCase {

    /// 標準の読み替え辞書(実機で実際に効いている物)。5000件超ある。
    /// JSON の型(NovelSpeakerUtility.SpeechModSetting)と分割で使う型
    /// (StoryTextClassifier.swift の SpeechModSetting)は別物なので変換する。
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

    /// ごく普通の本文(約3000文字)。
    private func plainText(characterCount: Int = 3000) -> String {
        let sentence = "　少女は窓の外を眺めながら、そう答えた。空は抜けるように青く、遠くの山並みまではっきりと見えている。\n「なあ、春菜。この村から出た事あるか？」\n「ううん、一度も無いよ」\n"
        var text = ""
        while text.count < characterCount { text += sentence }
        return String(text.prefix(characterCount))
    }

    /// ルビだらけの本文(青空文庫の「坊っちゃん」のような、1ページに大量のルビがある物)。
    private func rubyRichText(characterCount: Int = 3000) -> String {
        let sentence = "｜親譲《おやゆず》りの｜無鉄砲《むてっぽう》で｜小供《こども》の時から｜損《そん》ばかりしている。｜小学校《しょうがっこう》に｜居《い》る時分｜学校《がっこう》の｜二階《にかい》から｜飛《と》び｜降《お》りて｜一週間《いっしゅうかん》ほど｜腰《こし》を｜抜《ぬ》かした｜事《こと》がある。\n"
        var text = ""
        while text.count < characterCount { text += sentence }
        return String(text.prefix(characterCount))
    }

    private func measureSeconds(_ label: String, iterations: Int = 1, _ block: () -> Void) -> Double {
        let start = Date()
        for _ in 0..<iterations { block() }
        let elapsed = Date().timeIntervalSince(start) / Double(iterations)
        NSLog("NovelSpeaker.Benchmark: %@ = %.1f ms", label, elapsed * 1000)
        return elapsed
    }

    func testBlockSplitCostBreakdown() throws {
        let defaultModArray = loadDefaultSpeechModArray()
        XCTAssertGreaterThan(defaultModArray.count, 1000, "標準の読み替え辞書が読めていない")
        NSLog("NovelSpeaker.Benchmark: 読み替え辞書 %d件(うち正規表現 %d件)",
              defaultModArray.count, defaultModArray.filter { $0.isUseRegularExpression }.count)

        let content = plainText()
        let ruby = rubyRichText()
        let narrator = makeSpeakerSetting(type: "VOICEVOX", voiceIdentifier: "2")
        let dialogue = makeSpeakerSetting(type: "VOICEVOX", voiceIdentifier: "3")
        let sectionConfigList = [SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: dialogue)]
        let splitTargets = ["。", "、", "　", "\n"]

        // 1. 並べ替えと重複除去(ページごとに毎回やっている)
        _ = measureSeconds("① 辞書の並べ替え+重複除去(5000件)", iterations: 5) {
            _ = StoryTextClassifier.UniqSpeechModArray(
                speechModArray: StoryTextClassifier.SpeechModArraySort(speechModArray: defaultModArray))
        }

        let sorted = StoryTextClassifier.UniqSpeechModArray(
            speechModArray: StoryTextClassifier.SpeechModArraySort(speechModArray: defaultModArray))

        // 2. 先頭文字での索引作り(ページごとに毎回やっている)
        _ = measureSeconds("② 辞書の索引作り(5000件)", iterations: 5) {
            _ = StoryTextClassifier.IndexSpeechModArray(sortedSpeechModArray: sorted)
        }

        // 3. 本体(索引作り込み)
        _ = measureSeconds("③ 分割本体(辞書あり・普通の本文3000字)", iterations: 3) {
            _ = StoryTextClassifier.CategorizeStoryText(
                content: content, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
                defaultSpeaker: narrator, sectionConfigList: sectionConfigList, waitConfigList: [],
                sortedSpeechModArray: sorted)
        }

        // 4. 辞書なし(=索引作りと読み替えの影響を外した素の分割)
        _ = measureSeconds("④ 分割本体(辞書なし・普通の本文3000字)", iterations: 3) {
            _ = StoryTextClassifier.CategorizeStoryText(
                content: content, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
                defaultSpeaker: narrator, sectionConfigList: sectionConfigList, waitConfigList: [],
                sortedSpeechModArray: [])
        }

        // 5. 正規表現の展開込み(実際に呼ばれている経路)
        _ = measureSeconds("⑤ 正規表現の展開+分割(普通の本文3000字)", iterations: 3) {
            _ = StoryTextClassifier.CategorizeStoryText(
                content: content, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
                defaultSpeaker: narrator, sectionConfigList: sectionConfigList, waitConfigList: [],
                speechModArray: defaultModArray)
        }

        // 6. ルビの読み替え生成(ルビだらけの本文)
        _ = measureSeconds("⑥ ルビの読み替え生成(ルビだらけ3000字)", iterations: 3) {
            _ = StoryTextClassifier.GenerateRubyModString(text: ruby, notRubyString: "", isDisableNarouRuby: false)
        }

        // 7. ルビだらけの本文を通しで
        let rubyMods = StoryTextClassifier.GenerateRubyModString(text: ruby, notRubyString: "", isDisableNarouRuby: false)
        NSLog("NovelSpeaker.Benchmark: ルビ由来の読み替え %d件", rubyMods.count)
        _ = measureSeconds("⑦ 正規表現の展開+分割(ルビだらけ3000字)", iterations: 3) {
            _ = StoryTextClassifier.CategorizeStoryText(
                content: ruby, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
                defaultSpeaker: narrator, sectionConfigList: sectionConfigList, waitConfigList: [],
                speechModArray: defaultModArray + rubyMods)
        }

        // 8. VOICEVOX とそれ以外で差が出るか(VOICEVOX向けの結合処理を後から足しているため)
        let avNarrator = makeSpeakerSetting(type: "AVSpeechSynthesizer", voiceIdentifier: "com.apple.voice.compact.ja-JP.Kyoko")
        _ = measureSeconds("⑧ 分割本体(AVSpeech話者・辞書あり)", iterations: 3) {
            _ = StoryTextClassifier.CategorizeStoryText(
                content: content, withMoreSplitTargets: splitTargets, moreSplitMinimumLetterCount: 200,
                defaultSpeaker: avNarrator, sectionConfigList: [], waitConfigList: [],
                sortedSpeechModArray: sorted)
        }
    }
}
