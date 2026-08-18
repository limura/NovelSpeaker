//
//  VoicevoxSpeakerTest.swift
//  NovelSpeakerTests
//
//  再生パイプライン(AVAudioEngine + AVAudioPlayerNode)を実際に一往復させて確認する。
//  過去に、engine初期化時に nil フォーマットで接続していたため VOICEVOX の
//  モノラル24kHzバッファを scheduleBuffer した瞬間に
//  "_outputFormat.channelCount == buffer.format.channelCount" でクラッシュする不具合があった
//  (実機の話者設定画面「発話テスト」で踏んだ)。ここで実際に最後まで再生できることを確認する。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxSpeakerTest: XCTestCase {

    private class RecordingDelegate: SpeakRangeDelegate {
        var finishedIsCancel: Bool?
        let expectation: XCTestExpectation
        init(expectation: XCTestExpectation) {
            self.expectation = expectation
        }
        func willSpeakRange(range: NSRange) {}
        func finishSpeak(isCancel: Bool, speechString: String) {
            finishedIsCancel = isCancel
            expectation.fulfill()
        }
    }

    func testSpeechPlaysWithoutCrashingOnFormatMismatch() async throws {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil),
              let vvmPath = Bundle.main.path(forResource: "0", ofType: "vvm") else {
            XCTFail("同梱の辞書/0.vvm がバンドルに見つかりません")
            return
        }
        try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])
        let styles = await VoicevoxCore.shared.styles
        guard let style = styles.first else {
            XCTFail("0.vvm からスタイルが取れませんでした")
            return
        }

        let expectation = expectation(description: "finishSpeak")
        let delegate = RecordingDelegate(expectation: expectation)
        let speaker = VoicevoxSpeaker(styleId: style.styleId)
        speaker.delegate = delegate

        await MainActor.run {
            speaker.performSpeech(text: "こんにちは")
        }

        await fulfillment(of: [expectation], timeout: 10)
        XCTAssertEqual(delegate.finishedIsCancel, false)
    }

    // delay(「読み上げ時の間の設定」由来のポーズ)が、実際に再生完了からfinishSpeakまでの
    // 待ち時間として反映されている事を確認する。
    func testDelayIsHonoredBeforeFinishSpeak() async throws {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil),
              let vvmPath = Bundle.main.path(forResource: "0", ofType: "vvm") else {
            XCTFail("同梱の辞書/0.vvm がバンドルに見つかりません")
            return
        }
        try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])
        let styles = await VoicevoxCore.shared.styles
        guard let style = styles.first else {
            XCTFail("0.vvm からスタイルが取れませんでした")
            return
        }

        let expectation = expectation(description: "finishSpeak")
        let delegate = RecordingDelegate(expectation: expectation)
        let speaker = VoicevoxSpeaker(styleId: style.styleId)
        speaker.delegate = delegate
        speaker.delay = 1.0

        let startDate = Date()
        await MainActor.run {
            speaker.performSpeech(text: "こんにちは")
        }
        await fulfillment(of: [expectation], timeout: 15)
        let elapsed = Date().timeIntervalSince(startDate)
        // 合成+再生自体にも時間がかかるので厳密な上限は付けず、下限(delayが尊重されているか)だけ見る。
        XCTAssertGreaterThanOrEqual(elapsed, 1.0, "delayで指定した間がfinishSpeakまでの時間に反映されていない")
    }
}
