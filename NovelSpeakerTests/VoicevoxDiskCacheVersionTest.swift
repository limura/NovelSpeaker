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

    // MARK: - 版が無かった時代の分の引き継ぎ

    // ★消さずに移す事。作り置きは1作品で数百MBあり、捨てると作り直しに何時間もかかる。
    func testLegacyLayoutIsMigratedNotDeleted() throws {
        // 版が無かった時代の形(直下に小説ディレクトリ)を手で作る。
        let legacyName = String(repeating: "a", count: 64)
        let legacyChapter = root.appendingPathComponent(legacyName, isDirectory: true)
            .appendingPathComponent("1", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyChapter, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: legacyChapter.appendingPathComponent("deadbeef_3500.m4a"))
        try Data("novel-old".utf8).write(
            to: root.appendingPathComponent(legacyName, isDirectory: true)
                .appendingPathComponent("novelID.txt"))

        XCTAssertEqual(store.migrateLegacyLayoutIfNeeded(), 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: currentVersionDirectory().appendingPathComponent(legacyName)
                .appendingPathComponent("1").appendingPathComponent("deadbeef_3500.m4a").path),
                      "移したはずの音声が無い")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(legacyName).appendingPathComponent("1").path),
                       "移動元が残っている")
        // 移した後は普通に見つかる。
        XCTAssertEqual(store.cachedNovelIDs(), ["novel-old"])
    }

    func testMigrationIsANoOpWhenThereIsNothingOld() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        XCTAssertEqual(store.migrateLegacyLayoutIfNeeded(), 0)
        XCTAssertEqual(store.cachedNovelIDs(), ["novel-1"])
    }

    // 移行の途中で落ちて両方にある場合は、新しい方(版の下)を残す。
    func testMigrationKeepsTheNewerOneOnCollision() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        let name = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(atPath: currentVersionDirectory().path)
                .first { $0.count == 64 })
        // 同じ名前のディレクトリを直下にも作る(移行の途中で落ちた状態)。
        let legacy = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("novelID.txt"))

        XCTAssertEqual(store.migrateLegacyLayoutIfNeeded(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "古い方が残っている")
        let key = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: key),
                      "新しい方が壊れている")
    }

    // MARK: - 古い版の掃除

    // ★版を上げた時に古い分が丸ごと消える事。
    // これが効かないと「辞書を直したのに古い音が鳴り続ける」事になる。
    func testOtherVersionsAreRemoved() throws {
        try store(novelID: "novel-1", chapterNumber: 1, text: "こんにちは", styleId: 3)
        // 別の版のディレクトリを手で作る。
        let other = root.appendingPathComponent("v99", isDirectory: true)
            .appendingPathComponent("somenovel", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 2048).write(to: other.appendingPathComponent("x.m4a"))

        let freed = store.removeOtherFormatVersions()
        XCTAssertEqual(freed, 2048, "消した容量が合わない")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("v99").path), "古い版が残っている")
        // 今の版は消さない。
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1,
                                     key: VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)))
    }

    // 見覚えのない物は触らない(v で始まっていても数字でなければ残す)。
    func testUnknownDirectoriesAreLeftAlone() throws {
        let unknown = root.appendingPathComponent("vsomething", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)
        XCTAssertEqual(store.removeOtherFormatVersions(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    }

    func testNothingToCleanIsNotAnError() {
        XCTAssertEqual(store.removeOtherFormatVersions(), 0)
        XCTAssertEqual(store.migrateLegacyLayoutIfNeeded(), 0)
    }
}
