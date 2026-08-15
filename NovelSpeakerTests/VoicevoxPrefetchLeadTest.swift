//
//  VoicevoxPrefetchLeadTest.swift
//  NovelSpeakerTests
//
//  「未再生の貯金が何秒あるか」の算出テスト。
//  先行合成キャッシュは再生済みのブロックも保持し続けるため、キャッシュ全体の
//  バイト数から換算すると実際の余裕より大きく出てしまう(実機ログで162秒と出ていた)。
//  実際に効くのは「次のブロックから連続して合成済みである区間」なので、そこだけを
//  数えている事を確認する。この値はディスクキャッシュを何秒ぶん用意すべきかの
//  設計判断に直結する。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxPrefetchLeadTest: XCTestCase {

    /// 指定秒数ぶんの WAV バイト数(24kHz/mono/16bit + ヘッダ)。
    private func wavBytes(seconds: Double) -> Int {
        return Int(seconds * VoicevoxPerformanceMonitor.outputSampleRate * VoicevoxPerformanceMonitor.outputBytesPerFrame) + VoicevoxPerformanceMonitor.wavHeaderByteCount
    }

    private func makeBlock(text: String, type: String = "VOICEVOX", styleId: UInt32 = 3) -> CombinedSpeechBlock {
        let info = SpeechBlockInfo(speechText: text, displayText: text, voiceIdentifier: "\(styleId)", locale: "ja-JP", pitch: 1, rate: 1, volume: 1, delay: 0, isMod: false, type: type)
        return CombinedSpeechBlock(block: info)
    }

    // 連続して合成済みの区間だけが貯金として数えられ、未合成のブロックで打ち切られる事。
    func testLeadStopsAtFirstUncachedBlock() {
        let blocks = [
            makeBlock(text: "再生中"),
            makeBlock(text: "A"), // 合成済み 10秒
            makeBlock(text: "B"), // 合成済み 5秒
            makeBlock(text: "C"), // 未合成 → ここで打ち切り
            makeBlock(text: "D"), // 合成済みだが C で止まるので数えない
        ]
        let cached: [String: Double] = ["A": 10, "B": 5, "D": 100]
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 1) { text, _ in
            guard let seconds = cached[text] else { return nil }
            return self.wavBytes(seconds: seconds)
        }
        XCTAssertEqual(lead, 15.0, accuracy: 0.01, "A(10秒)+B(5秒)だけが数えられ、Cで打ち切られるはず")
    }

    // 再生済み(fromIndex より前)のブロックは、たとえキャッシュに残っていても数えない。
    // これがキャッシュ全体を数えていた時との違い(実機ログの過大表示の原因)。
    func testAlreadyPlayedBlocksAreNotCounted() {
        let blocks = [
            makeBlock(text: "再生済み1"),
            makeBlock(text: "再生済み2"),
            makeBlock(text: "再生中"),
            makeBlock(text: "次"),
        ]
        // 全部キャッシュに残っている状態(実機で起きていた状況)。
        let cached: [String: Double] = ["再生済み1": 100, "再生済み2": 100, "再生中": 100, "次": 7]
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 3) { text, _ in
            guard let seconds = cached[text] else { return nil }
            return self.wavBytes(seconds: seconds)
        }
        XCTAssertEqual(lead, 7.0, accuracy: 0.01, "未再生の「次」だけが貯金。再生済みの300秒は数えない")
    }

    // VOICEVOX以外(AVSpeech等)のブロックは先行合成の対象外なので、
    // 貯金の切れ目とは見なさずに読み飛ばす。
    func testNonVoicevoxBlocksDoNotBreakTheRun() {
        let blocks = [
            makeBlock(text: "再生中"),
            makeBlock(text: "A"),
            makeBlock(text: "AV", type: "AVSpeechSynthesizer"),
            makeBlock(text: "B"),
        ]
        let cached: [String: Double] = ["A": 3, "B": 4]
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 1) { text, _ in
            guard let seconds = cached[text] else { return nil }
            return self.wavBytes(seconds: seconds)
        }
        XCTAssertEqual(lead, 7.0, accuracy: 0.01, "AVSpeechブロックを挟んでも A+B が数えられるはず")
    }

    // 発話しない空白のみのブロックも切れ目にはしない(合成に出していないため)。
    func testWhitespaceOnlyBlocksDoNotBreakTheRun() {
        let blocks = [
            makeBlock(text: "再生中"),
            makeBlock(text: "A"),
            makeBlock(text: "  \n "),
            makeBlock(text: "B"),
        ]
        let cached: [String: Double] = ["A": 2, "B": 3]
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 1) { text, _ in
            guard let seconds = cached[text] else { return nil }
            return self.wavBytes(seconds: seconds)
        }
        XCTAssertEqual(lead, 5.0, accuracy: 0.01, "空白のみのブロックを挟んでも A+B が数えられるはず")
    }

    func testNothingCachedGivesZeroLead() {
        let blocks = [makeBlock(text: "再生中"), makeBlock(text: "A")]
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 1) { _, _ in nil }
        XCTAssertEqual(lead, 0.0, accuracy: 0.0001)
    }

    func testEndOfBookGivesZeroLead() {
        let blocks = [makeBlock(text: "最後")]
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 1) { _, _ in
            return self.wavBytes(seconds: 10)
        }
        XCTAssertEqual(lead, 0.0, accuracy: 0.0001, "最終ブロックより先は無いので0秒")
    }

    // 走査数の上限を超えて延々と数え続けない事。
    func testScanCountIsBounded() {
        let blocks = (0..<500).map { makeBlock(text: "block\($0)") }
        let lead = SpeechBlockSpeaker.contiguousPrefetchedLeadSeconds(blocks: blocks, fromIndex: 0, maxScanCount: 10) { _, _ in
            return self.wavBytes(seconds: 1)
        }
        XCTAssertEqual(lead, 10.0, accuracy: 0.01, "maxScanCount で打ち切られるはず")
    }
}
