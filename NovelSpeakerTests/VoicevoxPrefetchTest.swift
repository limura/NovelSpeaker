//
//  VoicevoxPrefetchTest.swift
//  NovelSpeakerTests
//
//  先行合成キャッシュ(VoicevoxCore.prefetch/synthesize)が実際に機能し、
//  prefetch済みのテキストは synthesize() が(再合成せず)キャッシュを使う事を確認する。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxPrefetchTest: XCTestCase {

    private func setUpCore() async throws -> UInt32 {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil),
              let vvmPath = Bundle.main.path(forResource: "0", ofType: "vvm") else {
            XCTFail("同梱の辞書/0.vvm がバンドルに見つかりません")
            return 0
        }
        try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])
        let styles = await VoicevoxCore.shared.styles
        guard let style = styles.first else {
            XCTFail("0.vvm からスタイルが取れませんでした")
            return 0
        }
        return style.styleId
    }

    func testPrefetchedTextIsServedFromCache() async throws {
        let styleId = try await setUpCore()
        VoicevoxCore.shared.clearPrefetchCache()

        let text = "これは先行合成のテストです"
        VoicevoxCore.shared.schedulePrefetch(blockIndex: 1, text: text, styleId: styleId)

        // prefetch の完了を待つ(Task内部完了待ちのポーリング。数秒あれば十分)。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if VoicevoxCore.shared.isPrefetchedForTesting(text: text, styleId: styleId) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let wasPrefetched = VoicevoxCore.shared.isPrefetchedForTesting(text: text, styleId: styleId)
        XCTAssertTrue(wasPrefetched, "prefetchが時間内に完了しませんでした")

        let data = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        // 同じ文字列が本文中に複数回登場するケース(会話文の相槌等)で、2回目以降も
        // キャッシュヒットで済むように、synthesize() はヒットしてもキャッシュを消費しない。
        let stillCached = VoicevoxCore.shared.isPrefetchedForTesting(text: text, styleId: styleId)
        XCTAssertTrue(stillCached, "synthesize()でヒットしてもキャッシュは消費されず残っているべき(同一文字列の再登場に備えるため)")

        // 実際に、同じキーへの2回目の synthesize() も(再合成せず)キャッシュから返る事を確認する。
        let secondData = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
        XCTAssertEqual(secondData, data, "2回目の synthesize() も同じキャッシュ内容を返すべき")
    }

    func testClearPrefetchCacheDropsPendingEntries() async throws {
        let styleId = try await setUpCore()
        VoicevoxCore.shared.schedulePrefetch(blockIndex: 1, text: "何か適当な文章です", styleId: styleId)
        VoicevoxCore.shared.clearPrefetchCache()
        let cached = VoicevoxCore.shared.isPrefetchedForTesting(text: "何か適当な文章です", styleId: styleId)
        XCTAssertFalse(cached)
    }

    // cancelPendingPrefetch() は、まだ着手していない先読みのバックログをキャンセルしつつ、
    // 既に完成しているキャッシュは残す事を確認する(読み上げ停止時の挙動)。
    func testCancelPendingPrefetchKeepsCompletedCache() async throws {
        let styleId = try await setUpCore()
        VoicevoxCore.shared.clearPrefetchCache()

        // 1つ先行合成して完成させる
        let doneText = "これは完成済みのキャッシュです"
        VoicevoxCore.shared.schedulePrefetch(blockIndex: 1, text: doneText, styleId: styleId)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if VoicevoxCore.shared.isPrefetchedForTesting(text: doneText, styleId: styleId) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let doneBeforeCancel = VoicevoxCore.shared.isPrefetchedForTesting(text: doneText, styleId: styleId)
        XCTAssertTrue(doneBeforeCancel, "先行合成が完了しているべき")

        // バックログをキャンセルしても、完成済みのキャッシュは残るべき
        VoicevoxCore.shared.cancelPendingPrefetch()
        let doneAfterCancel = VoicevoxCore.shared.isPrefetchedForTesting(text: doneText, styleId: styleId)
        XCTAssertTrue(doneAfterCancel, "cancelPendingPrefetch() 後も完成済みキャッシュは残るべき")
    }
}

// 以前は投入順の直列鎖で実行していたため、積み過ぎると鎖の後ろに回った物ほど
// 完了が遅れた。実機では一度に30件以上積まれ、予約から完了まで218秒かかる状態になり、
// その間ずっと「未再生の貯金=0秒」で無音になっていた。
// 現在は待ち行列が「再生順で手前のものほど優先」で選ぶので、後から要求した
// 「次に再生するブロック」が先に完成する事を、実際の合成を通して確認する。
extension VoicevoxPrefetchTest {
    func testNearerBlockIsNotStarvedByBacklog() async throws {
        try XCTSkipUnless(VoicevoxCore.isAvailableOnThisOS, "VOICEVOXが利用できない環境")
        await VoicevoxCore.setUpFromBundleIfNeeded()
        let isSetUp = await VoicevoxCore.shared.isSetUp
        try XCTSkipUnless(isSetUp, "VOICEVOXのセットアップができない環境")

        VoicevoxCore.shared.schedulePrefetchCacheClear()
        // 先に「もっと先のブロック」を沢山積む(実機で起きていたバックログ)。
        for i in 0..<10 {
            VoicevoxCore.shared.schedulePrefetch(blockIndex: 100 + i, text: "これは先の方のブロック\(i)です。", styleId: 3)
        }
        // その後で「次に再生するブロック」(=再生順で手前)を要求する。
        let urgentText = "これは今すぐ必要なブロックです。"
        VoicevoxCore.shared.schedulePrefetch(blockIndex: 1, text: urgentText, styleId: 3)

        // バックログ全部の完了を待たずに、優先ぶんが先に用意される事。
        let deadline = Date().addingTimeInterval(60)
        var isReady = false
        while Date() < deadline {
            if VoicevoxCore.shared.cachedWavByteCount(text: urgentText, styleId: 3) != nil {
                isReady = true
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(isReady, "最優先で要求したブロックが、積まれた先行合成に埋もれて完成しない")
    }
}
