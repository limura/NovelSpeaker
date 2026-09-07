//
//  VoicevoxUserDictionaryTest.swift
//  NovelSpeakerTests
//
//  「読みの修正」から VOICEVOX 本体のユーザー辞書を組み立てる所。
//
//  ★表記(surface)に何を入れるかが全て。
//  ユーザー辞書は「VOICEVOX が読む文字列」に効くので、その読み替えが
//  VOICEVOX にも適用されるかどうかで、入れるべき文字列が変わる。
//  ここを取り違えると、登録しても一致せず、何も起きない
//  (しかも黙って何も起きないので、原因が分からない類の不具合になる)。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxUserDictionaryTest: XCTestCase {

    private func entry(before: String = "橋",
                       after: String = "ハシ",
                       isUseRegularExpression: Bool = false,
                       isAppliedToVoicevox: Bool = true,
                       pronunciation: String = "ハシ",
                       accentType: Int = 0,
                       priority: Int = VoicevoxUserDictionaryEntry.defaultPriority) -> VoicevoxUserDictionaryEntry? {
        return VoicevoxUserDictionaryBuilder.entry(
            before: before, after: after,
            isUseRegularExpression: isUseRegularExpression,
            isAppliedToVoicevox: isAppliedToVoicevox,
            pronunciation: pronunciation, accentType: accentType, priority: priority)
    }

    // MARK: - どの行を登録するか

    // ★読みを指定した行では VOICEVOX 向けの置換を行わないので、
    // VOICEVOX が目にするのは元の文字列(読み替え前)。
    //
    // 置換してしまうと辞書が探す文字列が本文から消えるので、
    // 両方を効かせる事はできない。細かく指定できる辞書の方を採る。
    func testSurfaceIsTheOriginalText() {
        XCTAssertEqual(entry(before: "橋", after: "ハシ", isAppliedToVoicevox: true)?.surface, "橋")
    }

    func testWordTypeIsPreservedForTheVoicevoxEntry() {
        let result = VoicevoxUserDictionaryBuilder.entry(
            before: "造作もない", after: "造作もない", isUseRegularExpression: false,
            isAppliedToVoicevox: true, pronunciation: "ゾウサモナイ", accentType: 5,
            priority: VoicevoxUserDictionaryEntry.preferredPriority, wordType: .adjective)
        XCTAssertEqual(result?.wordType, .adjective)
    }

    // ★VOICEVOX が対象でない行は、読みとアクセントも効かない。
    //
    // 「適用する音声合成」で VOICEVOX を外した = この読みの修正は VOICEVOX には
    // 効かない、という指定なので、その一部であるここも効かない。
    // 以前は「代わりに読み替え前の文字列へ読みを与える」という作りにしていたが、
    // 同じ項目に2つの意味を持たせる事になり、設定から受ける印象と正反対に動いていた。
    func testNotRegisteredWhenVoicevoxIsNotTargeted() {
        XCTAssertNil(entry(before: "実際", after: "\"実際\"", isAppliedToVoicevox: false))
        XCTAssertNil(entry(before: "橋", after: "ハシ", isAppliedToVoicevox: false))
    }

    // MARK: - 登録しない場合

    // 読みが空 = この行ではこの機能を使っていない。
    func testNoPronunciationMeansNoEntry() {
        XCTAssertNil(entry(pronunciation: ""))
        XCTAssertNil(entry(pronunciation: "   "))
    }

    // 正規表現の行では登録できない。
    // 読み替え後が "$1" のようなテンプレートで、実際に何という文字列になるのかが
    // 登録の時点では決まらないため。
    func testRegularExpressionRowIsNotRegistered() {
        XCTAssertNil(entry(isUseRegularExpression: true))
    }

    // 表記が空になる組み合わせでは登録しない。
    func testEmptySurfaceIsNotRegistered() {
        XCTAssertNil(entry(before: "", isAppliedToVoicevox: true))
    }

    // MARK: - 値の範囲

    func testPriorityIsClamped() {
        XCTAssertEqual(entry(priority: 99)?.priority, 10)
        XCTAssertEqual(entry(priority: -5)?.priority, 0)
    }

    func testNegativeAccentTypeIsTreatedAsFlat() {
        XCTAssertEqual(entry(accentType: -1)?.accentType, 0)
    }

    // MARK: - 同じ表記が2つある場合

    // VOICEVOX は同じ表記を2つ登録できないので、こちらで決める必要がある。
    func testSameSurfaceKeepsHigherPriority() {
        let low = entry(before: "橋", priority: 3)!
        let high = entry(before: "橋", pronunciation: "ハシ", accentType: 2, priority: 8)!
        let result = VoicevoxUserDictionaryBuilder.deduplicated([low, high])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.accentType, 2)
    }

    // 並びが決まっていないと、同じ内容でも署名が変わってキャッシュが無駄になる。
    func testDeduplicatedIsSortedBySurface() {
        let a = entry(before: "アア")!
        let b = entry(before: "イイ")!
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.deduplicated([b, a]).map({ $0.surface }), ["アア", "イイ"])
    }

    // MARK: - キャッシュの鍵に混ぜる署名

    // ★辞書を使っていない本文の鍵は、これまでと同じままである事。
    // ここが変わると、既に作ってある音声が全部使われなくなる。
    func testSignatureIsEmptyWhenNothingApplies() {
        let entries = [entry(before: "橋")!]
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.signature(forText: "こんにちは", entries: entries), "")
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.signature(forText: "こんにちは", entries: []), "")
    }

    // MARK: - 読みを指定した行では置換しない

    // 置換と辞書は同時に効かせられない(置換すると辞書が探す文字列が消える)。
    // 細かく指定できる辞書の方を採るので、VOICEVOX への置換は行わない。
    func testSubstitutionIsSkippedForVoicevoxWhenPronunciationIsGiven() {
        let mod = NovelSpeaker.SpeechModSetting(
            before: "橋", after: "ハシ", isUseRegularExpression: false,
            targetSpeechEngineTypeArray: [.any], hasVoicevoxPronunciation: true)
        XCTAssertFalse(mod.isAppliedTo(speechEngineType: "VOICEVOX"),
                       "読みを指定した行では VOICEVOX に置換を当ててはいけない")
        XCTAssertTrue(mod.isAppliedTo(speechEngineType: "AVSpeechSynthesizer"),
                      "端末の音声には今までどおり置換が効く")
    }

    // 読みを指定していなければ、今までどおり置換が効く。
    func testSubstitutionStillAppliesWhenNoPronunciationIsGiven() {
        let mod = NovelSpeaker.SpeechModSetting(
            before: "橋", after: "ハシ", isUseRegularExpression: false,
            targetSpeechEngineTypeArray: [.any], hasVoicevoxPronunciation: false)
        XCTAssertTrue(mod.isAppliedTo(speechEngineType: "VOICEVOX"))
    }

    // 対象から外れている行は、読みの有無に関わらず何も効かない。
    func testNothingAppliesWhenVoicevoxIsNotTargeted() {
        let mod = NovelSpeaker.SpeechModSetting(
            before: "橋", after: "ハシ", isUseRegularExpression: false,
            targetSpeechEngineTypeArray: [.avSpeechSynthesizer], hasVoicevoxPronunciation: true)
        XCTAssertFalse(mod.isAppliedTo(speechEngineType: "VOICEVOX"))
        XCTAssertNil(entry(isAppliedToVoicevox: false))
    }

    // ★その語を含む本文だけ署名が付く事。
    // 辞書全体の版番号を混ぜると、1語直しただけで何時間ぶんもの作り置きが
    // 一斉に無駄になってしまう。
    func testSignatureOnlyCoversEntriesThatAppearInTheText() {
        let entries = [entry(before: "橋")!, entry(before: "山", pronunciation: "ヤマ")!]
        let signature = VoicevoxUserDictionaryBuilder.signature(forText: "橋をわたる", entries: entries)
        XCTAssertTrue(signature.contains("橋"))
        XCTAssertFalse(signature.contains("山"))
    }

    // アクセントだけ変えても署名は変わる(音が変わるので作り直しが要る)。
    func testSignatureChangesWhenAccentChanges() {
        let flat = [entry(before: "橋", accentType: 0)!]
        let head = [entry(before: "橋", accentType: 1)!]
        XCTAssertNotEqual(VoicevoxUserDictionaryBuilder.signature(forText: "橋", entries: flat),
                          VoicevoxUserDictionaryBuilder.signature(forText: "橋", entries: head))
    }

    // 同じ内容なら署名も同じである事(でないと毎回作り直しになる)。
    func testSignatureIsStableForTheSameContent() {
        let a = [entry(before: "橋", accentType: 1)!]
        let b = [entry(before: "橋", accentType: 1)!]
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.signature(forText: "橋", entries: a),
                       VoicevoxUserDictionaryBuilder.signature(forText: "橋", entries: b))
    }

    // MARK: - 今有効な辞書の入れ替え

    // 中身が変わっていない時に「変わった」と言ってはいけない。
    // 変わったと言うと作り置きを捨ててしまう。
    func testReplaceReportsWhetherItActuallyChanged() {
        let dictionary = VoicevoxUserDictionary.shared
        defer { dictionary.replace(with: []) }
        XCTAssertTrue(dictionary.replace(with: [entry(before: "橋", accentType: 1)!]))
        XCTAssertFalse(dictionary.replace(with: [entry(before: "橋", accentType: 1)!]))
        XCTAssertTrue(dictionary.replace(with: [entry(before: "橋", accentType: 0)!]))
    }

    // 並び順の違いだけでは「変わった」にならない事。
    func testReplaceIgnoresOrder() {
        let dictionary = VoicevoxUserDictionary.shared
        defer { dictionary.replace(with: []) }
        let a = entry(before: "アア")!
        let b = entry(before: "イイ")!
        XCTAssertTrue(dictionary.replace(with: [a, b]))
        XCTAssertFalse(dictionary.replace(with: [b, a]))
    }
    // MARK: - アクセントの見せ方

    // 下がる位置に印を付ける。印は「下がる直前のモーラの後ろ」。
    func testMarkedKanaPutsTheMarkAfterTheDroppingMora() {
        let moras = ["ハ", "シ"]
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: moras, accentType: 0), "ハシ")
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: moras, accentType: 1), "ハ\u{A71C}シ")
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: moras, accentType: 2), "ハシ\u{A71C}")
    }

    // ★モーラは1文字とは限らない(「キャ」は2文字で1モーラ)。
    // 文字数で数えると印の位置がずれる。
    func testMarkedKanaCountsMorasNotCharacters() {
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: ["キャ", "ク"], accentType: 1), "キャ\u{A71C}ク")
    }

    // 範囲外の値では印を付けない(壊れた表示を出さない)。
    func testMarkedKanaIgnoresOutOfRangeAccent() {
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: ["ハ", "シ"], accentType: 9), "ハシ")
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: ["ハ", "シ"], accentType: -1), "ハシ")
    }

    func testTypeNames() {
        XCTAssertEqual(VoicevoxAccentDisplay.typeName(accentType: 0, moraCount: 3), "平板")
        XCTAssertEqual(VoicevoxAccentDisplay.typeName(accentType: 1, moraCount: 3), "頭高")
        XCTAssertEqual(VoicevoxAccentDisplay.typeName(accentType: 2, moraCount: 3), "中高")
        XCTAssertEqual(VoicevoxAccentDisplay.typeName(accentType: 3, moraCount: 3), "尾高")
        // 1モーラの語では、1 は頭高でもあり尾高でもある。頭高を優先する。
        XCTAssertEqual(VoicevoxAccentDisplay.typeName(accentType: 1, moraCount: 1), "頭高")
    }

    // 候補は 0 〜 モーラ数(平板を含めてモーラ数+1個)。
    func testCandidatesCoverFlatToFinal() {
        XCTAssertEqual(VoicevoxAccentDisplay.candidates(moraCount: 3), [0, 1, 2, 3])
        XCTAssertEqual(VoicevoxAccentDisplay.candidates(moraCount: 0), [])
    }

    // ★聞き比べる時は助詞を付ける。
    // 付けないと平板と尾高がまったく同じ音になり、選び分けられない。
    func testPreviewTextHasAParticle() {
        let text = VoicevoxAccentDisplay.previewText(kana: "ハシ")
        XCTAssertTrue(text.hasPrefix("ハシ"))
        XCTAssertGreaterThan(text.count, "ハシ".count, "助詞が付いていない")
    }
    // MARK: - モーラの区切り

    // ★VOICEVOX の解析を使ってはいけない。
    // analyze は「実際にどう発音するか」を返すので、「イジョウチ」が
    // 「イ / ジョ / オ / チ」になって、利用者が入れた文字と違う表示になる。
    // 区切りだけが必要なので、書いた文字のまま数える。
    func testMorasKeepTheCharactersAsTyped() {
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: "イジョウチ"), ["イ", "ジョ", "ウ", "チ"])
    }

    // 小書きの仮名は直前にくっついて1モーラ。
    func testSmallKanaJoinsThePreviousMora() {
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: "キャク"), ["キャ", "ク"])
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: "ファイト"), ["ファ", "イ", "ト"])
    }

    // 「ン」「ッ」「ー」はそれぞれ1モーラ(日本語の数え方どおり)。
    func testSpecialMorasAreCountedSeparately() {
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: "コッケン"), ["コ", "ッ", "ケ", "ン"])
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: "ラーメン"), ["ラ", "ー", "メ", "ン"])
    }

    // 小書きの仮名で始まっていても落ちない。
    func testLeadingSmallKanaDoesNotCrash() {
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: "ャ"), ["ャ"])
        XCTAssertEqual(VoicevoxAccentDisplay.moras(fromKatakana: ""), [])
    }

    // 実機で起きた表示の揺れ。同じ読みなら何度数えても同じ結果になる事。
    func testMorasAreStable() {
        let first = VoicevoxAccentDisplay.moras(fromKatakana: "イジョウチ")
        let second = VoicevoxAccentDisplay.moras(fromKatakana: "イジョウチ")
        XCTAssertEqual(first, second)
        XCTAssertEqual(VoicevoxAccentDisplay.markedKana(moras: first, accentType: 3), "イジョウ\u{A71C}チ")
    }
}
