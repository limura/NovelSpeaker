//
//  VoicevoxCoreTest.swift
//  NovelSpeakerTests
//
//  VOICEVOX_IOS_INTEGRATION.md §7 の最小検証:
//  init_once → open_jtalk → synthesizer → VVMロード → tts("こんにちは") → WAVがRIFFで始まること。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCoreTest: XCTestCase {

    func testSynthesizeProducesRiffWav() async throws {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else {
            XCTFail("同梱の open_jtalk_dic_utf_8-1.11 がバンドルに見つかりません")
            return
        }
        guard let vvmPath = VoicevoxTestVoiceModel.path() else {
            throw XCTSkip("テスト用の 0.vvm がありません。scripts/fetch_voicevox_vendor.sh を実行してください")
        }

        let core = VoicevoxCore.shared
        try await core.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])

        let styles = await core.styles
        XCTAssertFalse(styles.isEmpty, "0.vvm からスタイルが1つも取れませんでした")
        guard let style = styles.first else { return }

        let wav = try await core.synthesize(text: "こんにちは", styleId: style.styleId)
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(wav.prefix(4), Data("RIFF".utf8))
    }
}
