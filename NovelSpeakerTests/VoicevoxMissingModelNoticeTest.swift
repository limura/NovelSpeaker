//
//  VoicevoxMissingModelNoticeTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxMissingModelNoticeTest: XCTestCase {

    // ★お知らせの文面で伝えるべき事は3つ。
    // 「代わりに読んだ」「設定は壊していない」「取り直せば戻る」。
    // どれが欠けても「勝手に話者が変わった」と読まれる。
    func testMessageSaysWhatHappenedAndHowToRecover() {
        let message = VoicevoxMissingModelNotice.message(styleId: 22, displayName: "ずんだもん - ささやき")
        XCTAssertTrue(message.contains("ずんだもん - ささやき"), message)
        // 代わりに読むエンジンの呼び名は SpeechEngineType 側に1つだけ持たせてあるので、
        // 文面もそれと同じ言葉になっている事を見る(片方だけ直る事故を防ぐ)。
        XCTAssertTrue(message.contains(SpeechEngineType.avSpeechSynthesizer.localizedName), message)
        XCTAssertTrue(message.contains("読み上げました"), message)
        XCTAssertTrue(message.contains("話者設定はそのまま"), message)
        XCTAssertTrue(message.contains("元の声に戻ります"), message)
    }

    // 名前が引けない時でも、どの話者の話なのかを番号で示す。
    func testMessageFallsBackToStyleNumber() {
        let message = VoicevoxMissingModelNotice.message(styleId: 999, displayName: nil)
        XCTAssertTrue(message.contains("999"), message)
    }

    // 同じ話者で何度読み上げてもお知らせが積まれないよう、まとめる鍵は styleId ごと。
    func testDedupeKeyIsPerStyleId() {
        XCTAssertEqual(VoicevoxMissingModelNotice.dedupeKey(styleId: 3),
                       VoicevoxMissingModelNotice.dedupeKey(styleId: 3))
        XCTAssertNotEqual(VoicevoxMissingModelNotice.dedupeKey(styleId: 3),
                          VoicevoxMissingModelNotice.dedupeKey(styleId: 5))
    }

    // お知らせのボタンから styleId が取り出せる事(ここが繋がらないと取得画面へ飛べない)。
    func testStyleIdRoundTripsThroughTheAction() throws {
        let action = AppInformationLogAction(
            title: "音声モデルを取得する",
            actionType: VoicevoxMissingModelNotice.actionType,
            payload: ["styleId": AnyCodable("22")])
        XCTAssertEqual(VoicevoxMissingModelNotice.styleId(from: action), 22)
    }

    func testOtherActionsAreIgnored() {
        let action = AppInformationLogAction(
            title: "取り込み設定を確認する",
            actionType: "openNovelImportSetting",
            payload: ["siteInfoId": AnyCodable("x")])
        XCTAssertNil(VoicevoxMissingModelNotice.styleId(from: action))
    }

    // 名前は同梱カタログから引ける(手元に音声モデルが無くても引ける事が肝心)。
    func testDisplayNameComesFromTheCatalogWhenNotDownloaded() throws {
        let file = try XCTUnwrap(
            VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(bundle: Bundle(for: VoicevoxCore.self))
                ?? VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(bundle: Bundle(for: type(of: self))))
        let catalog = try XCTUnwrap(file.catalog(
            readableVvmFormatVersions: VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions))
        let entry = try XCTUnwrap(catalog.entry(forStyleId: 22))
        XCTAssertEqual(VoicevoxMissingModelNotice.displayName(styleId: 22), entry.displayName)
    }
}
