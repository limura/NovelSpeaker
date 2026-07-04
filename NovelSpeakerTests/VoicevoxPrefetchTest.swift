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
        let vvmDirectory = (vvmPath as NSString).deletingLastPathComponent
        try await VoicevoxCore.shared.setUp(dictDirectoryPath: dictPath, voiceModelDirectoryPaths: [vvmDirectory])
        let styles = await VoicevoxCore.shared.styles
        guard let style = styles.first else {
            XCTFail("0.vvm からスタイルが取れませんでした")
            return 0
        }
        return style.styleId
    }

    func testPrefetchedTextIsServedFromCache() async throws {
        let styleId = try await setUpCore()
        await VoicevoxCore.shared.clearPrefetchCache()

        let text = "これは先行合成のテストです"
        await VoicevoxCore.shared.prefetch(text: text, styleId: styleId)

        // prefetch の完了を待つ(Task内部完了待ちのポーリング。数秒あれば十分)。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if await VoicevoxCore.shared.isPrefetchedForTesting(text: text, styleId: styleId) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let wasPrefetched = await VoicevoxCore.shared.isPrefetchedForTesting(text: text, styleId: styleId)
        XCTAssertTrue(wasPrefetched, "prefetchが時間内に完了しませんでした")

        let data = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
        XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
        // 同じ文字列が本文中に複数回登場するケース(会話文の相槌等)で、2回目以降も
        // キャッシュヒットで済むように、synthesize() はヒットしてもキャッシュを消費しない。
        let stillCached = await VoicevoxCore.shared.isPrefetchedForTesting(text: text, styleId: styleId)
        XCTAssertTrue(stillCached, "synthesize()でヒットしてもキャッシュは消費されず残っているべき(同一文字列の再登場に備えるため)")

        // 実際に、同じキーへの2回目の synthesize() も(再合成せず)キャッシュから返る事を確認する。
        let secondData = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
        XCTAssertEqual(secondData, data, "2回目の synthesize() も同じキャッシュ内容を返すべき")
    }

    func testClearPrefetchCacheDropsPendingEntries() async throws {
        let styleId = try await setUpCore()
        await VoicevoxCore.shared.prefetch(text: "何か適当な文章です", styleId: styleId)
        await VoicevoxCore.shared.clearPrefetchCache()
        let cached = await VoicevoxCore.shared.isPrefetchedForTesting(text: "何か適当な文章です", styleId: styleId)
        XCTAssertFalse(cached)
    }

    // cancelPendingPrefetch() は、まだ着手していない先読みのバックログをキャンセルしつつ、
    // 既に完成しているキャッシュは残す事を確認する(読み上げ停止時の挙動)。
    func testCancelPendingPrefetchKeepsCompletedCache() async throws {
        let styleId = try await setUpCore()
        await VoicevoxCore.shared.clearPrefetchCache()

        // 1つ先行合成して完成させる
        let doneText = "これは完成済みのキャッシュです"
        await VoicevoxCore.shared.prefetch(text: doneText, styleId: styleId)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if await VoicevoxCore.shared.isPrefetchedForTesting(text: doneText, styleId: styleId) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let doneBeforeCancel = await VoicevoxCore.shared.isPrefetchedForTesting(text: doneText, styleId: styleId)
        XCTAssertTrue(doneBeforeCancel, "先行合成が完了しているべき")

        // バックログをキャンセルしても、完成済みのキャッシュは残るべき
        await VoicevoxCore.shared.cancelPendingPrefetch()
        let doneAfterCancel = await VoicevoxCore.shared.isPrefetchedForTesting(text: doneText, styleId: styleId)
        XCTAssertTrue(doneAfterCancel, "cancelPendingPrefetch() 後も完成済みキャッシュは残るべき")
    }
}
