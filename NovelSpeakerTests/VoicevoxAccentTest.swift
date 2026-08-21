//
//  VoicevoxAccentTest.swift
//  NovelSpeakerTests
//
//  VOICEVOX 本体に読みとアクセントを渡す所を、実物で確かめる。
//
//  ここは C の構造体とポインタを直接触るので、単体テストで型が合っているだけでは
//  足りない(voicevox_user_dict_word_make が返す構造体は渡した C 文字列の
//  ポインタを**そのまま持つ**ため、寿命を間違えると解放済みメモリを読む)。
//  実際に登録して、実際に音が変わる事まで見る。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxAccentTest: XCTestCase {

    private func setUpCore() async throws -> (VoicevoxCore, VoicevoxStyle) {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else {
            throw XCTSkip("同梱の open_jtalk_dic_utf_8-1.11 がバンドルに見つかりません")
        }
        guard let vvmPath = VoicevoxTestVoiceModel.path() else {
            throw XCTSkip("テスト用の 0.vvm がありません。scripts/fetch_voicevox_vendor.sh を実行してください")
        }
        let core = VoicevoxCore.shared
        try await core.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])
        let styles = await core.styles
        guard let style = styles.first else {
            throw XCTSkip("0.vvm からスタイルが取れませんでした")
        }
        return (core, style)
    }

    override func tearDown() async throws {
        // 他のテストへ持ち越さない。
        await VoicevoxCore.shared.applyUserDictionary([])
    }

    // MARK: - 解析

    // ★声のモデルが要らない事が肝。
    // 音声モデルを1つも持っていない端末でも、アクセントの設定画面は開けて
    // 読みも出せる(聞けないだけ)。
    func testAnalyzeReturnsKanaAndAccent() async throws {
        let (core, _) = try await setUpCore()
        let phrases = try await core.analyze(text: "橋を渡る")
        XCTAssertFalse(phrases.isEmpty, "解析結果が空")
        let kana = phrases.kana
        XCTAssertFalse(kana.isEmpty, "読みが取れていない")
        // 漢字がそのまま残っていたら読めていない。
        XCTAssertFalse(kana.contains("橋"), "カタカナになっていない: \(kana)")
        for phrase in phrases {
            XCTAssertGreaterThanOrEqual(phrase.accent, 0)
            XCTAssertLessThanOrEqual(phrase.accent, phrase.moras.count,
                                     "アクセント核はモーラ数を超えない")
        }
    }

    // 利用者が入れるのは漢字混じりとは限らない。カタカナでもそのまま解析できる事。
    func testAnalyzeAcceptsKatakana() async throws {
        let (core, _) = try await setUpCore()
        let phrases = try await core.analyze(text: "ハシ")
        XCTAssertEqual(phrases.kana, "ハシ")
    }

    // MARK: - 登録

    // ★本題。アクセント型を変えると、実際に出てくる音が変わる事。
    //
    // 「読みの修正」は文字列を置換するだけなので、カタカナに置き換えても
    // アクセントは変えられない(「橋」も「箸」も「端」も「ハシ」)。
    // ユーザー辞書だけがこれを変えられる。ここが効いていなければ、
    // この機能には存在価値が無い。
    func testAccentTypeChangesTheAudio() async throws {
        let (core, style) = try await setUpCore()

        await core.applyUserDictionary([])
        let plain = try await core.synthesize(text: "ハシ", styleId: style.styleId)

        await core.applyUserDictionary([
            VoicevoxUserDictionaryEntry(surface: "ハシ", pronunciation: "ハシ", accentType: 0,
                                        priority: VoicevoxUserDictionaryEntry.preferredPriority)
        ])
        let flat = try await core.synthesize(text: "ハシ", styleId: style.styleId)

        await core.applyUserDictionary([
            VoicevoxUserDictionaryEntry(surface: "ハシ", pronunciation: "ハシ", accentType: 1,
                                        priority: VoicevoxUserDictionaryEntry.preferredPriority)
        ])
        let head = try await core.synthesize(text: "ハシ", styleId: style.styleId)

        XCTAssertNotEqual(flat, head, "アクセント型を変えても音が変わっていない")
        XCTAssertTrue(plain != flat || plain != head,
                      "辞書を登録しても何も変わっていない")
    }

    // ★平板(0)と尾高(モーラ数と同じ値)は、**その語だけでは音が同じになる**。
    //
    // 日本語のアクセントとして正しい挙動で、不具合ではない。
    // 両者の違いは「後ろに付く助詞が下がるかどうか」だけなので、
    // 語を単独で鳴らすと区別が付かない。
    //
    // 画面でアクセントを選ばせる時に「聞いて確かめる」のであれば、
    // **語の後ろに助詞を付けて鳴らさないと、この2つを選び分けられない。**
    // ここを忘れると「同じ音しか出ない」と言われる事になるので、固定しておく。
    func testFlatAndFinalAccentSoundTheSameAlone() async throws {
        let (core, style) = try await setUpCore()
        func audio(accentType: Int, text: String) async throws -> Data {
            await core.applyUserDictionary([
                VoicevoxUserDictionaryEntry(surface: "ハシ", pronunciation: "ハシ", accentType: accentType,
                                            priority: VoicevoxUserDictionaryEntry.preferredPriority)
            ])
            return try await core.synthesize(text: text, styleId: style.styleId)
        }
        // 単独では同じ。
        let flatAlone = try await audio(accentType: 0, text: "ハシ")
        let finalAlone = try await audio(accentType: 2, text: "ハシ")
        XCTAssertEqual(flatAlone, finalAlone, "単独では平板と尾高は同じ音になるはず")

        // 助詞を付ければ違う。
        let flatWithParticle = try await audio(accentType: 0, text: "ハシが")
        let finalWithParticle = try await audio(accentType: 2, text: "ハシが")
        XCTAssertNotEqual(flatWithParticle, finalWithParticle,
                          "助詞を付ければ平板と尾高は違う音になるはず")
    }

    // 漢字の表記にも読みを与えられる事(置換を使わずに直せる)。
    func testKanjiSurfaceGetsTheGivenReading() async throws {
        let (core, _) = try await setUpCore()
        await core.applyUserDictionary([])
        let before = try await core.analyze(text: "黒剣").kana

        await core.applyUserDictionary([
            VoicevoxUserDictionaryEntry(surface: "黒剣", pronunciation: "コッケン", accentType: 0,
                                        priority: VoicevoxUserDictionaryEntry.preferredPriority)
        ])
        let after = try await core.analyze(text: "黒剣").kana
        XCTAssertEqual(after, "コッケン", "登録した読みが使われていない(登録前は \(before))")
    }

    // 受け付けられない語が混じっていても、他の語は生きる事。
    // 表記に記号が入っている物は弾かれるが、そこで全部を諦めてはいけない。
    func testRejectedWordDoesNotBreakTheRest() async throws {
        let (core, _) = try await setUpCore()
        await core.applyUserDictionary([
            VoicevoxUserDictionaryEntry(surface: "\"実際\"", pronunciation: "ジッサイ", accentType: 1, priority: 10),
            VoicevoxUserDictionaryEntry(surface: "黒剣", pronunciation: "コッケン", accentType: 0, priority: 10),
        ])
        let kana = try await core.analyze(text: "黒剣").kana
        XCTAssertEqual(kana, "コッケン")
    }

    // 空の辞書を渡したら、登録が消える事。
    func testEmptyDictionaryClearsPreviousRegistration() async throws {
        let (core, _) = try await setUpCore()
        await core.applyUserDictionary([
            VoicevoxUserDictionaryEntry(surface: "黒剣", pronunciation: "コッケン", accentType: 0, priority: 10)
        ])
        let registered = try await core.analyze(text: "黒剣").kana
        XCTAssertEqual(registered, "コッケン")
        await core.applyUserDictionary([])
        let cleared = try await core.analyze(text: "黒剣").kana
        XCTAssertNotEqual(cleared, "コッケン")
    }
}
