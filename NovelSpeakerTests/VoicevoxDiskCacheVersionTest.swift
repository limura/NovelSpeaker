//
//  VoicevoxDiskCacheVersionTest.swift
//  NovelSpeakerTests
//
//  作り置きした音声の置き場所に入れた「版」まわり。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxDiskCacheVersionTest: XCTestCase {

    private var root: URL!
    private var store: VoicevoxDiskCacheStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vvcache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = VoicevoxDiskCacheStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func currentVersionDirectory() -> URL {
        return root.appendingPathComponent(
            VoicevoxDiskCacheStore.versionDirectoryName(VoicevoxDiskCacheStore.formatVersion),
            isDirectory: true)
    }

    private func store(novelID: String, chapterNumber: Int, text: String, styleId: UInt32) throws {
        try store.store(novelID: novelID, chapterNumber: chapterNumber,
                        key: VoicevoxDiskCacheStore.key(text: text, styleId: styleId),
                        data: Data(repeating: 0xAB, count: 1024), durationSeconds: 3.5)
    }

    // MARK: - 版の下に置かれる事

    func testAudioIsStoredUnderTheVersionDirectory() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: currentVersionDirectory().path),
                      "版のディレクトリが掘られていない")
        // 版の下に小説ディレクトリがある事(直下ではない事)。
        let underVersion = try FileManager.default.contentsOfDirectory(atPath: currentVersionDirectory().path)
        XCTAssertTrue(underVersion.contains { $0.count == 64 }, "版の下に小説ディレクトリが無い: \(underVersion)")
        let underRoot = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(underRoot.contains { $0.count == 64 }, "版を通さずに直下に置かれている: \(underRoot)")
    }

    func testStoredAudioIsStillFound() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        let key = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: key))
        XCTAssertNotNil(store.load(novelID: "novel-1", chapterNumber: 1, key: key))
        XCTAssertEqual(store.cachedNovelIDs(), ["novel-1"])
    }

    // MARK: - 古い置き方の掃除

    // ★版を上げた時に古い分が丸ごと消える事。
    // これが効かないと「辞書を直したのに古い音が鳴り続ける」事になる。
    func testOtherVersionsAreRemoved() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        let other = root.appendingPathComponent("v99", isDirectory: true)
            .appendingPathComponent("somenovel", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2048).write(to: other.appendingPathComponent("x.m4a"))

        XCTAssertEqual(store.removeOutdatedLayouts(), 2048, "消した容量が合わない")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("v99").path), "古い版が残っている")
        // 今の版は消さない。
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1,
                                     key: VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)))
    }

    // 版が無かった時代(直下に小説ディレクトリ)の分も、同じ仕組みで消える。
    func testLayoutFromBeforeVersioningIsRemoved() throws {
        let legacyName = String(repeating: "a", count: 64)
        let legacyChapter = root.appendingPathComponent(legacyName, isDirectory: true)
            .appendingPathComponent("1", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyChapter, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 512).write(to: legacyChapter.appendingPathComponent("deadbeef_3500.m4a"))

        XCTAssertEqual(store.removeOutdatedLayouts(), 512)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(legacyName).path), "古い置き方が残っている")
        XCTAssertEqual(store.cachedNovelIDs(), [])
    }

    // 今の版だけがある時は何も消さない(掃除の度に作り置きが飛んだら大事故)。
    func testCurrentVersionIsNeverTouched() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        XCTAssertEqual(store.removeOutdatedLayouts(), 0)
        XCTAssertEqual(store.cachedNovelIDs(), ["novel-1"])
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1,
                                     key: VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)))
    }

    func testNothingToCleanIsNotAnError() {
        XCTAssertEqual(store.removeOutdatedLayouts(), 0)
    }
}
