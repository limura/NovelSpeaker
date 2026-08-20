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
        let path = VoicevoxTestVoiceModel.path()
        try XCTSkipIf(path == nil, "0.vvm が無い(scripts/fetch_voicevox_vendor.sh を実行のこと)")
        return URL(fileURLWithPath: path!)
    }

    /// 手元の 0.vvm の形式。コアを上げると変わる(0.16.4なら1、0.17.0なら2)ので、
    /// 直に書かずにファイルから読む。こうしておけば次にコアを上げても落ちない。
    private func realVvmFormat() throws -> Int {
        return try VoicevoxVoiceModelFileInspector.inspect(fileURL: try realVvmURL()).vvmFormatVersion
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
        // ★手元の 0.vvm は、このアプリのコアが読める形式でなければならない。
        // ここが食い違うのは fetch スクリプトとコアの版がずれている時。
        XCTAssertTrue(VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions
                        .contains(info.vvmFormatVersion),
                      "テスト用の 0.vvm の形式(\(info.vvmFormatVersion))をこのアプリのコアが読めない"
                      + "(scripts/fetch_voicevox_vendor.sh を実行し直すこと)")
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
        let format = try realVvmFormat()
        let stored = try store.store(temporaryFileURL: incoming, modelID: "0",
                                     expectedStyleIds: [3], readableFormats: [format])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        // 形式ごとのディレクトリに入っている事
        XCTAssertEqual(stored.deletingLastPathComponent().lastPathComponent, "f\(format)")
        XCTAssertTrue(store.isStored(modelID: "0", readableFormats: [format]))
        XCTAssertEqual(store.storedModelIDs(readableFormats: [format]), ["0": format])
        XCTAssertGreaterThan(store.totalBytes(readableFormats: [format]), 1_000_000)
        // 元の場所からは移動している(コピーを残さない)
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.path))
    }

    // ★このアプリのコアが読めない形式の物は置かない事。
    // 置いてしまうと「取得済み」として扱われ、再生時に初めて失敗する。
    func testStoreRejectsUnsupportedFormat() throws {
        let incoming = try copyOfRealVvm()
        let format = try realVvmFormat()
        // 手元の物とは違う形式しか読めない、という状況を作る
        XCTAssertThrowsError(try store.store(temporaryFileURL: incoming, modelID: "0",
                                             expectedStyleIds: [], readableFormats: [format + 1])) {
            XCTAssertEqual($0 as? VoicevoxVoiceModelStoreError, .unsupportedFormat(format))
        }
        XCTAssertFalse(store.isStored(modelID: "0", readableFormats: [format, format + 1]))
    }

    // ★期待したスタイルが入っていない物は置かない事(取り違えの検出)。
    func testStoreRejectsWrongContent() throws {
        let incoming = try copyOfRealVvm()
        let format = try realVvmFormat()
        XCTAssertThrowsError(try store.store(temporaryFileURL: incoming, modelID: "5",
                                             expectedStyleIds: [22], readableFormats: [format])) {
            XCTAssertEqual($0 as? VoicevoxVoiceModelStoreError, .missingExpectedStyles([22]))
        }
        XCTAssertFalse(store.isStored(modelID: "5", readableFormats: [format]))
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
        let format = try realVvmFormat()
        let incoming = try copyOfRealVvm()
        try store.store(temporaryFileURL: incoming, modelID: "0",
                        expectedStyleIds: [], readableFormats: [format])
        // コアを上げて次の形式も読めるようになった、という状況
        XCTAssertTrue(store.isStored(modelID: "0", readableFormats: [format, format + 1]))
        XCTAssertEqual(store.storedModelIDs(readableFormats: [format, format + 1]), ["0": format])
        XCTAssertEqual(store.modelFileURLs(readableFormats: [format, format + 1]).count, 1)
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

    // ★新しい形式を置いたら、同じ音声モデルの古い形式は消える事。
    //
    // 消さないと、使われない60MBがそのまま居座る。
    // (「更新があります」から取り直した時に、まさにこの状況になる)
    func testStoringNewerFormatRemovesOlderOne() throws {
        // 手元の物と同じ形式で持っている状態を作る
        let format = try realVvmFormat()
        let old = store.fileURL(forModelID: "0", format: format)
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))

        // 本物を別の形式として置く事はできないので、
        // ここでは同じ形式に置き直した時に古い方が残らない事だけ確かめ、
        // 形式をまたぐ場合は下の掃除のテストで見る。
        let incoming = try copyOfRealVvm()
        let stored = try store.store(temporaryFileURL: incoming, modelID: "0",
                                     expectedStyleIds: [], readableFormats: [format])
        XCTAssertEqual(stored, old, "同じ形式なら置き換わる")
        XCTAssertEqual(store.storedModelIDs(readableFormats: [format, format + 1]), ["0": format])
    }

    // ★取り残された古い形式を掃除できる事(置いた直後に落ちた場合など)。
    func testSupersededDuplicatesAreReclaimed() throws {
        for (format, size) in [(1, 4096), (2, 8192)] {
            let url = store.fileURL(forModelID: "0", format: format)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(repeating: 0, count: size).write(to: url)
        }
        // 形式1にしか無い物は消してはいけない
        let onlyOld = store.fileURL(forModelID: "5", format: 1)
        try Data(repeating: 0, count: 2048).write(to: onlyOld)

        XCTAssertEqual(store.reclaimableBytes(readableFormats: [1, 2]), 4096,
                       "消せるのは、新しい形式で持っている物の古い方だけ")

        let freed = store.removeSupersededDuplicates()
        XCTAssertEqual(freed, 4096)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(forModelID: "0", format: 1).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(forModelID: "0", format: 2).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: onlyOld.path),
                      "その形式でしか持っていない物を消してはいけない")
        // もう一度呼んでも何も起きない
        XCTAssertEqual(store.removeSupersededDuplicates(), 0)
    }

    // ★もう読めない形式の分も「消せる無駄」として数える事。
    func testUnreadableFormatCountsAsReclaimable() throws {
        let url = store.fileURL(forModelID: "0", format: 9)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024).write(to: url)
        XCTAssertEqual(store.reclaimableBytes(readableFormats: [1, 2]), 1024)
        store.removeUnreadableFormats(readableFormats: [1, 2])
        XCTAssertEqual(store.reclaimableBytes(readableFormats: [1, 2]), 0)
    }

    // 無駄が無い時は0を返す事(管理画面に「0MB削除できます」と出さないため)。
    func testNothingReclaimableWhenClean() throws {
        let format = try realVvmFormat()
        let incoming = try copyOfRealVvm()
        try store.store(temporaryFileURL: incoming, modelID: "0",
                        expectedStyleIds: [], readableFormats: [format])
        XCTAssertEqual(store.reclaimableBytes(readableFormats: [format, format + 1]), 0)
        XCTAssertEqual(store.removeSupersededDuplicates(), 0)
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
        let format = try realVvmFormat()
        let incoming = try copyOfRealVvm()
        try store.store(temporaryFileURL: incoming, modelID: "0",
                        expectedStyleIds: [], readableFormats: [format])
        store.remove(modelID: "0", readableFormats: [format, format + 1])
        XCTAssertFalse(store.isStored(modelID: "0", readableFormats: [format, format + 1]))
        XCTAssertEqual(store.totalBytes(readableFormats: [format]), 0)
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
