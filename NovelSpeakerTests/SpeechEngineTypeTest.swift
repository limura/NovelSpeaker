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
}
