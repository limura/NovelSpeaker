//
//  VoicevoxVoiceModelStoreTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxVoiceModelStoreTest: XCTestCase {

    private var root: URL!
    private var store: VoicevoxVoiceModelStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VoicevoxVoiceModelStoreTest-\(UUID().uuidString)")
        store = VoicevoxVoiceModelStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 手元にある本物の VVM。無ければテストを飛ばす
    /// (scripts/fetch_voicevox_vendor.sh を走らせていない環境でも落とさない)。
    private func realVvmURL() throws -> URL {
        let path = Bundle.main.path(forResource: "0", ofType: "vvm")
        try XCTSkipIf(path == nil, "0.vvm が無い(scripts/fetch_voicevox_vendor.sh を実行のこと)")
        return URL(fileURLWithPath: path!)
    }

    private func copyOfRealVvm() throws -> URL {
        let source = try realVvmURL()
        let destination = root.appendingPathComponent("incoming-\(UUID().uuidString).vvm")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    // MARK: - 中身を覗く

    // 本物の VVM を、コアを通さずに読めている事。
    func testInspectRealVoiceModelFile() throws {
        let info = try VoicevoxVoiceModelFileInspector.inspect(fileURL: try realVvmURL())
        XCTAssertEqual(info.vvmFormatVersion, 1, "同梱の 0.vvm は形式1のはず")
        XCTAssertEqual(info.speakers.count, 4, "0.vvm は4キャラ入っている")
        XCTAssertEqual(info.allStyleIds, [0, 1, 2, 3, 4, 5, 6, 7, 8, 10])
        XCTAssertTrue(info.speakers.contains { $0.name == "ずんだもん" })
    }

    // zip ですら無い物を掴んでも、落ちずに弾ける事。
    func testInspectRejectsNonZip() {
        XCTAssertThrowsError(try VoicevoxVoiceModelFileInspector.inspect(head: Data("これはzipではない".utf8))) {
            XCTAssertEqual($0 as? VoicevoxVoiceModelFileInspectorError, .notAZipFile)
        }
    }

    // 途中で切れているファイル(通信が落ちた等)を弾ける事。
    func testInspectRejectsTruncatedFile() throws {
        let full = try Data(contentsOf: try realVvmURL())
        // local file header だけ残して本体を削る
        XCTAssertThrowsError(try VoicevoxVoiceModelFileInspector.inspect(head: full.prefix(40)))
    }

    // 中身が空でも無限ループしない事。
    func testInspectDoesNotHangOnGarbage() {
        var garbage = Data([0x50, 0x4B, 0x03, 0x04])
        garbage.append(Data(repeating: 0, count: 4096))
        XCTAssertThrowsError(try VoicevoxVoiceModelFileInspector.inspect(head: garbage))
    }

    // MARK: - 置く

    func testStoreAndFindRealVoiceModel() throws {
        let incoming = try copyOfRealVvm()
        let stored = try store.store(temporaryFileURL: incoming, modelID: "0",
                                     expectedStyleIds: [3], readableFormats: [1])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        // 形式ごとのディレクトリに入っている事
        XCTAssertEqual(stored.deletingLastPathComponent().lastPathComponent, "f1")
        XCTAssertTrue(store.isStored(modelID: "0", readableFormats: [1]))
        XCTAssertEqual(store.storedModelIDs(readableFormats: [1]), ["0": 1])
        XCTAssertGreaterThan(store.totalBytes(readableFormats: [1]), 1_000_000)
        // 元の場所からは移動している(コピーを残さない)
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
    }

    // ★このアプリのコアが読めない形式の物は置かない事。
    // 置いてしまうと「取得済み」として扱われ、再生時に初めて失敗する。
    func testStoreRejectsUnsupportedFormat() throws {
        let incoming = try copyOfRealVvm()
        XCTAssertThrowsError(try store.store(temporaryFileURL: incoming, modelID: "0",
                                             expectedStyleIds: [], readableFormats: [2])) {
            XCTAssertEqual($0 as? VoicevoxVoiceModelStoreError, .unsupportedFormat(1))
        }
        XCTAssertFalse(store.isStored(modelID: "0", readableFormats: [1, 2]))
    }

    // ★期待したスタイルが入っていない物は置かない事(取り違えの検出)。
    func testStoreRejectsWrongContent() throws {
        let incoming = try copyOfRealVvm()
        XCTAssertThrowsError(try store.store(temporaryFileURL: incoming, modelID: "5",
                                             expectedStyleIds: [22], readableFormats: [1])) {
            XCTAssertEqual($0 as? VoicevoxVoiceModelStoreError, .missingExpectedStyles([22]))
        }
        XCTAssertFalse(store.isStored(modelID: "5", readableFormats: [1]))
    }

    // 壊れた物は置かない事。
    func testStoreRejectsBrokenFile() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let broken = root.appendingPathComponent("broken.vvm")
        try Data("壊れています".utf8).write(to: broken)
        XCTAssertThrowsError(try store.store(temporaryFileURL: broken, modelID: "0",
                                             expectedStyleIds: [], readableFormats: [1])) {
            XCTAssertEqual($0 as? VoicevoxVoiceModelStoreError, .unreadable)
        }
        XCTAssertFalse(store.isStored(modelID: "0", readableFormats: [1]))
    }

    // MARK: - 形式が混ざった時

    // ★コアを上げた後も、古い形式で取得済みの物を使い続けられる事。
    // これが成り立たないと、コア更新のたびに1.4GBの取り直しになる。
    func testOlderFormatFilesRemainUsableAfterCoreUpgrade() throws {
        let incoming = try copyOfRealVvm()
        try store.store(temporaryFileURL: incoming, modelID: "0",
                        expectedStyleIds: [], readableFormats: [1])
        // コアを上げて形式2も読めるようになった、という状況
        XCTAssertTrue(store.isStored(modelID: "0", readableFormats: [1, 2]))
        XCTAssertEqual(store.storedModelIDs(readableFormats: [1, 2]), ["0": 1])
        XCTAssertEqual(store.modelFileURLs(readableFormats: [1, 2]).count, 1)
    }

    // ★同じ音声モデルが複数の形式で置かれてしまっても、コアには1つしか渡さない事。
    // 2つ渡すと、同じ styleId を2つのファイルが名乗る事になる。
    func testDuplicateAcrossFormatsIsCollapsedToNewest() throws {
        for format in [1, 2] {
            let url = store.fileURL(forModelID: "0", format: format)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(repeating: 0, count: 16).write(to: url)
        }
        XCTAssertEqual(store.storedModelIDs(readableFormats: [1, 2]), ["0": 2], "新しい形式を採る")
        let urls = store.modelFileURLs(readableFormats: [1, 2])
        XCTAssertEqual(urls.count, 1, "同じ音声モデルを2つ渡してはいけない")
        XCTAssertEqual(urls.first?.deletingLastPathComponent().lastPathComponent, "f2")
        XCTAssertEqual(store.stored(modelID: "0", readableFormats: [1, 2])?.format, 2)
    }

    // 読めなくなった形式のディレクトリを丸ごと捨てられる事。
    func testUnreadableFormatDirectoryCanBeDropped() throws {
        for format in [1, 9] {
            let url = store.fileURL(forModelID: "0", format: format)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(repeating: 0, count: 16).write(to: url)
        }
        store.removeUnreadableFormats(readableFormats: [1])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directoryURL(forFormat: 1).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directoryURL(forFormat: 9).path))
    }

    // MARK: - 消す

    func testRemove() throws {
        let incoming = try copyOfRealVvm()
        try store.store(temporaryFileURL: incoming, modelID: "0",
                        expectedStyleIds: [], readableFormats: [1])
        store.remove(modelID: "0", readableFormats: [1, 2])
        XCTAssertFalse(store.isStored(modelID: "0", readableFormats: [1, 2]))
        XCTAssertEqual(store.totalBytes(readableFormats: [1]), 0)
    }

    // 何も持っていない状態でも、問い合わせが素直に答える事。
    func testEmptyStore() {
        XCTAssertFalse(store.isStored(modelID: "0", readableFormats: [1]))
        XCTAssertTrue(store.storedModelIDs(readableFormats: [1]).isEmpty)
        XCTAssertTrue(store.modelFileURLs(readableFormats: [1]).isEmpty)
        XCTAssertEqual(store.totalBytes(readableFormats: [1]), 0)
        store.removeAll()
        store.remove(modelID: "0", readableFormats: [1])
    }
}
