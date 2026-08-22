//
//  SpeechEngineTypeTest.swift
//  NovelSpeakerTests
//
//  「この読み替えをどの音声合成に適用するか」の判定。
//
//  ★ここを間違えると被害が大きい。
//  標準の読み替え辞書(5000件超)は AVSpeechSynthesizer の癖を避けるために
//  作られたものが多く(「実際」→「"実際"」と引用符で囲う等)、VOICEVOX に
//  当てると余計な記号が読まれて不自然になる。
//  逆に厳しくし過ぎると、読み替えが丸ごと効かなくなる。
//

import XCTest
@testable import NovelSpeaker

class SpeechEngineTypeTest: XCTestCase {

    // NovelSpeakerUtility.SpeechModSetting(JSON用)と名前が同じなので、明示して区別する。
    private func mod(_ types: [SpeechEngineType]) -> NovelSpeaker.SpeechModSetting {
        return NovelSpeaker.SpeechModSetting(before: "橋", after: "ハシ", isUseRegularExpression: false,
                                             targetSpeechEngineTypeArray: types)
    }

    // 未指定(これまでのバージョンで作られたデータは全部これ)は、どこにでも適用する。
    // ここを「どこにも適用しない」と読むと、更新した瞬間に全員の読み替えが死ぬ。
    func testEmptyMeansEveryEngine() {
        XCTAssertTrue(mod([]).isAppliedTo(speechEngineType: "AVSpeechSynthesizer"))
        XCTAssertTrue(mod([]).isAppliedTo(speechEngineType: "VOICEVOX"))
    }

    // 明示的な「すべて」も同じく全部に適用する。
    func testAnyMeansEveryEngine() {
        XCTAssertTrue(mod([.any]).isAppliedTo(speechEngineType: "AVSpeechSynthesizer"))
        XCTAssertTrue(mod([.any]).isAppliedTo(speechEngineType: "VOICEVOX"))
    }

    // ★本題。端末の音声専用の読み替えを VOICEVOX に当ててはいけない。
    func testAVSpeechOnlyIsNotAppliedToVoicevox() {
        XCTAssertTrue(mod([.avSpeechSynthesizer]).isAppliedTo(speechEngineType: "AVSpeechSynthesizer"))
        XCTAssertFalse(mod([.avSpeechSynthesizer]).isAppliedTo(speechEngineType: "VOICEVOX"))
    }

    func testVoicevoxOnlyIsNotAppliedToAVSpeech() {
        XCTAssertTrue(mod([.voicevox]).isAppliedTo(speechEngineType: "VOICEVOX"))
        XCTAssertFalse(mod([.voicevox]).isAppliedTo(speechEngineType: "AVSpeechSynthesizer"))
    }

    // 知らないエンジンには適用する側に倒す。
    // 落とす側に倒すと、エンジンが増えた時にそのエンジンでだけ読み替えが
    // 全部効かなくなり、利用者からは原因の分からない不具合に見える。
    func testUnknownEngineIsTreatedAsApplicable() {
        XCTAssertTrue(mod([.avSpeechSynthesizer]).isAppliedTo(speechEngineType: "SomeFutureEngine"))
    }

    // MARK: - 文字列との対応

    // 話者設定の type に入っている文字列と往復できる事。
    // ここがずれると、読み替えが誰にも適用されなくなる。
    func testTypeStringRoundTrip() {
        for type in SpeechEngineType.selectableTypes {
            guard let text = type.typeString else {
                XCTFail("選べるエンジンには必ず type 文字列がある")
                continue
            }
            XCTAssertEqual(SpeechEngineType(typeString: text), type)
        }
        XCTAssertNil(SpeechEngineType.any.typeString, "「すべて」は特定のエンジンを指さない")
        XCTAssertNil(SpeechEngineType(typeString: "AVSpeechSynthesiser"), "綴り違いを受け付けてはいけない")
    }

    // 保存される数値。既存データを読み違えないよう、値を固定しておく。
    func testRawValuesAreStable() {
        XCTAssertEqual(SpeechEngineType.any.rawValue, 0)
        XCTAssertEqual(SpeechEngineType.avSpeechSynthesizer.rawValue, 1)
        XCTAssertEqual(SpeechEngineType.voicevox.rawValue, 2)
    }

    // MARK: - 保存する形への正規化

    // 「今ある全部」を並べて保存すると、将来エンジンが増えた時に
    // その新しいエンジンだけ除外された状態になってしまう。
    func testSelectingEverythingIsStoredAsAny() {
        let normalized = CreateSpeechModSettingViewControllerSwift.normalizeForStorage(SpeechEngineType.selectableTypes)
        XCTAssertEqual(normalized, [.any])
    }

    func testSelectingOneIsStoredAsItself() {
        XCTAssertEqual(CreateSpeechModSettingViewControllerSwift.normalizeForStorage([.voicevox]), [.voicevox])
    }

    func testAnyStaysAny() {
        XCTAssertEqual(CreateSpeechModSettingViewControllerSwift.normalizeForStorage([.any, .voicevox]), [.any])
    }

    // MARK: - 標準の読み替え辞書のJSON

    func testJSONTagIsDecoded() {
        let json = """
        [{"before":"魔石","after":"ませき","targetSpeechEngineTypeArray":["AVSpeechSynthesizer"]},
         {"before":"黒剣","after":"コッケン","targetSpeechEngineTypeArray":["any"]},
         {"before":"未確認","after":"みかくにん"}]
        """
        guard let decoded = try? JSONDecoder().decode([NovelSpeakerUtility.SpeechModSetting].self,
                                                      from: Data(json.utf8)) else {
            XCTFail("読めなかった")
            return
        }
        XCTAssertEqual(decoded[0].speechEngineTypes, [.avSpeechSynthesizer])
        XCTAssertEqual(decoded[1].speechEngineTypes, [.any])
        // ★未指定は「まだ確認していない」。空のままにして、従来どおりの推測に任せる。
        // ここを「すべて」と読むと、まだ聞いて確かめていない2000件以上が
        // 一斉に VOICEVOX へ適用されてしまう。
        XCTAssertEqual(decoded[2].speechEngineTypes, [])
    }

    func testUnknownJSONTagIsIgnored() {
        let json = """
        [{"before":"あ","after":"い","targetSpeechEngineTypeArray":["SomeFutureEngine","VOICEVOX"]}]
        """
        guard let decoded = try? JSONDecoder().decode([NovelSpeakerUtility.SpeechModSetting].self,
                                                      from: Data(json.utf8)) else {
            XCTFail("読めなかった")
            return
        }
        XCTAssertEqual(decoded[0].speechEngineTypes, [.voicevox])
    }
    // MARK: - 指定が無い時に何が効くか

    // ★ここを間違えると被害が大きいので、実データで確かめる。
    //
    // 対象エンジンをデータで持つ前に作られた読み替えは全部「指定なし」になる。
    // その時に何が効くかは、標準の読み替え辞書のタグと読み替え後の中身で決まる。

    private func effectiveTypes(before: String, after: String, isRegexp: Bool = false,
                                stored: [SpeechEngineType] = []) -> [SpeechEngineType] {
        let setting = RealmSpeechModSetting()
        setting.before = before
        setting.after = after
        setting.isUseRegularExpression = isRegexp
        setting.targetSpeechEngineTypeArray.append(objectsIn: stored.map({ $0.rawValue }))
        return NovelSpeakerUtility.EffectiveSpeechEngineTypes(of: setting)
    }

    // 自分で選んだ指定が最優先。推測に上書きされてはいけない。
    func testStoredValueWins() {
        XCTAssertEqual(effectiveTypes(before: "実際", after: "\"実際\"", stored: [.any]), [.any])
        XCTAssertEqual(effectiveTypes(before: "橋", after: "ハシ", stored: [.voicevox]), [.voicevox])
    }

    // ★利用者が自分で足した読み替えでも、引用符で囲う細工が入っていたら
    // VOICEVOX には当てない。標準辞書と同じ細工をしている可能性が高く、
    // そのまま渡すと引用符が読まれてしまう。
    func testQuotedReplacementIsKeptAwayFromVoicevox() {
        XCTAssertEqual(effectiveTypes(before: "ほげ", after: "\"ほげ\""), [.avSpeechSynthesizer])
    }

    // 普通の読み替えは今までどおり全部に適用する(空 = 未指定 = すべて)。
    func testPlainUserReplacementAppliesToEveryEngine() {
        XCTAssertEqual(effectiveTypes(before: "ほげ", after: "ホゲ"), [])
    }

    // 標準の読み替え辞書に同じ内容がある場合。
    // タグが付いていなければ「まだ VOICEVOX で確かめていない」ので端末の音声だけ。
    func testUntaggedDefaultEntryStaysOnAVSpeechSynthesizer() {
        // バンドルの JSON に必ずある物(サンプルとして先頭に置かれている)。
        XCTAssertEqual(effectiveTypes(before: "黒剣", after: "コッケン"), [.avSpeechSynthesizer])
    }
    // MARK: - 一度だけの書き込み

    // ★利用者が自分で選んだ指定を潰してはいけない。
    func testMigrationDoesNotTouchExplicitChoices() {
        let before = "移行テスト用-自分で選んだ-\(UUID().uuidString)"
        RealmUtil.Write { realm in
            let setting = RealmSpeechModSetting()
            setting.before = before
            setting.after = "\"かっこつき\""   // 判定なら端末の音声だけになる内容
            setting.setSpeechEngineTypes([.voicevox])
            realm.add(setting, update: .modified)
        }
        defer { deleteSetting(before: before) }

        UserDefaults.standard.set(0, forKey: NovelSpeakerUtility.speechModEngineTypeMigrationVersionKey)
        NovelSpeakerUtility.MigrateSpeechModEngineTypesIfNeeded()

        RealmUtil.RealmBlock { realm in
            guard let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before) else {
                XCTFail("消えている")
                return
            }
            XCTAssertEqual(setting.speechEngineTypes, [.voicevox], "自分で選んだ指定が上書きされている")
        }
    }

    // 指定の無い物には、判定した結果が書き込まれる。
    // 「すべて」の時も空のままにしない(空だと次も照合してしまう)。
    func testMigrationWritesTheInferredValue() {
        let plain = "移行テスト用-ふつう-\(UUID().uuidString)"
        let quoted = "移行テスト用-かっこ-\(UUID().uuidString)"
        RealmUtil.Write { realm in
            let a = RealmSpeechModSetting()
            a.before = plain
            a.after = "フツウ"
            realm.add(a, update: .modified)
            let b = RealmSpeechModSetting()
            b.before = quoted
            b.after = "\"かっこつき\""
            realm.add(b, update: .modified)
        }
        defer {
            deleteSetting(before: plain)
            deleteSetting(before: quoted)
        }

        UserDefaults.standard.set(0, forKey: NovelSpeakerUtility.speechModEngineTypeMigrationVersionKey)
        NovelSpeakerUtility.MigrateSpeechModEngineTypesIfNeeded()

        RealmUtil.RealmBlock { realm in
            XCTAssertEqual(RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: plain)?.speechEngineTypes,
                           [.any], "「すべて」も明示的に書かれるべき")
            XCTAssertEqual(RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: quoted)?.speechEngineTypes,
                           [.avSpeechSynthesizer], "引用符入りは端末の音声だけになるべき")
        }
    }

    // 一度走ったら二度と走らない。
    func testMigrationRunsOnlyOnce() {
        UserDefaults.standard.set(0, forKey: NovelSpeakerUtility.speechModEngineTypeMigrationVersionKey)
        NovelSpeakerUtility.MigrateSpeechModEngineTypesIfNeeded()
        XCTAssertEqual(UserDefaults.standard.integer(forKey: NovelSpeakerUtility.speechModEngineTypeMigrationVersionKey),
                       NovelSpeakerUtility.speechModEngineTypeMigrationVersion)

        let before = "移行テスト用-二度目-\(UUID().uuidString)"
        RealmUtil.Write { realm in
            let setting = RealmSpeechModSetting()
            setting.before = before
            setting.after = "フツウ"
            realm.add(setting, update: .modified)
        }
        defer { deleteSetting(before: before) }
        NovelSpeakerUtility.MigrateSpeechModEngineTypesIfNeeded()
        RealmUtil.RealmBlock { realm in
            XCTAssertTrue(RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before)?.speechEngineTypes.isEmpty ?? false,
                          "済んでいるのにもう一度書き込んでいる")
        }
    }

    private func deleteSetting(before: String) {
        RealmUtil.Write { realm in
            guard let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before) else { return }
            realm.delete(setting)
        }
    }
}
