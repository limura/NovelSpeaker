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

    // MARK: - 表記に何が入るか

    // VOICEVOX にも適用される読み替えなら、VOICEVOX が目にするのは読み替え「後」。
    func testSurfaceIsAfterWhenAppliedToVoicevox() {
        XCTAssertEqual(entry(before: "橋", after: "ハシ", isAppliedToVoicevox: true)?.surface, "ハシ")
    }

    // ★端末の音声専用の読み替えなら、VOICEVOX には元の文字列が届く。
    //
    // 「実際」→「"実際"」のような引用符の細工は端末の音声の癖を避けるためのもので、
    // VOICEVOX には適用しない。この時 VOICEVOX が読むのは「実際」なので、
    // 「"実際"」を登録しても一致しない(記号入りの表記はそもそも受け付けられない)。
    func testSurfaceIsBeforeWhenNotAppliedToVoicevox() {
        XCTAssertEqual(entry(before: "実際", after: "\"実際\"", isAppliedToVoicevox: false)?.surface, "実際")
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
        XCTAssertNil(entry(after: "", isAppliedToVoicevox: true))
        XCTAssertNil(entry(before: "", isAppliedToVoicevox: false))
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
        let low = entry(after: "ハシ", priority: 3)!
        let high = entry(after: "ハシ", pronunciation: "ハシ", accentType: 2, priority: 8)!
        let result = VoicevoxUserDictionaryBuilder.deduplicated([low, high])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.accentType, 2)
    }

    // 並びが決まっていないと、同じ内容でも署名が変わってキャッシュが無駄になる。
    func testDeduplicatedIsSortedBySurface() {
        let a = entry(after: "アア")!
        let b = entry(after: "イイ")!
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.deduplicated([b, a]).map({ $0.surface }), ["アア", "イイ"])
    }

    // MARK: - キャッシュの鍵に混ぜる署名

    // ★辞書を使っていない本文の鍵は、これまでと同じままである事。
    // ここが変わると、既に作ってある音声が全部使われなくなる。
    func testSignatureIsEmptyWhenNothingApplies() {
        let entries = [entry(after: "ハシ")!]
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.signature(forText: "こんにちは", entries: entries), "")
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.signature(forText: "こんにちは", entries: []), "")
    }

    // ★その語を含む本文だけ署名が付く事。
    // 辞書全体の版番号を混ぜると、1語直しただけで何時間ぶんもの作り置きが
    // 一斉に無駄になってしまう。
    func testSignatureOnlyCoversEntriesThatAppearInTheText() {
        let entries = [entry(after: "ハシ")!, entry(after: "ヤマ", pronunciation: "ヤマ")!]
        let signature = VoicevoxUserDictionaryBuilder.signature(forText: "ハシをわたる", entries: entries)
        XCTAssertTrue(signature.contains("ハシ"))
        XCTAssertFalse(signature.contains("ヤマ"))
    }

    // アクセントだけ変えても署名は変わる(音が変わるので作り直しが要る)。
    func testSignatureChangesWhenAccentChanges() {
        let flat = [entry(after: "ハシ", accentType: 0)!]
        let head = [entry(after: "ハシ", accentType: 1)!]
        XCTAssertNotEqual(VoicevoxUserDictionaryBuilder.signature(forText: "ハシ", entries: flat),
                          VoicevoxUserDictionaryBuilder.signature(forText: "ハシ", entries: head))
    }

    // 同じ内容なら署名も同じである事(でないと毎回作り直しになる)。
    func testSignatureIsStableForTheSameContent() {
        let a = [entry(after: "ハシ", accentType: 1)!]
        let b = [entry(after: "ハシ", accentType: 1)!]
        XCTAssertEqual(VoicevoxUserDictionaryBuilder.signature(forText: "ハシ", entries: a),
                       VoicevoxUserDictionaryBuilder.signature(forText: "ハシ", entries: b))
    }

    // MARK: - 今有効な辞書の入れ替え

    // 中身が変わっていない時に「変わった」と言ってはいけない。
    // 変わったと言うと作り置きを捨ててしまう。
    func testReplaceReportsWhetherItActuallyChanged() {
        let dictionary = VoicevoxUserDictionary.shared
        defer { dictionary.replace(with: []) }
        XCTAssertTrue(dictionary.replace(with: [entry(after: "ハシ", accentType: 1)!]))
        XCTAssertFalse(dictionary.replace(with: [entry(after: "ハシ", accentType: 1)!]))
        XCTAssertTrue(dictionary.replace(with: [entry(after: "ハシ", accentType: 0)!]))
    }

    // 並び順の違いだけでは「変わった」にならない事。
    func testReplaceIgnoresOrder() {
        let dictionary = VoicevoxUserDictionary.shared
        defer { dictionary.replace(with: []) }
        let a = entry(after: "アア")!
        let b = entry(after: "イイ")!
        XCTAssertTrue(dictionary.replace(with: [a, b]))
        XCTAssertFalse(dictionary.replace(with: [b, a]))
    }
}
