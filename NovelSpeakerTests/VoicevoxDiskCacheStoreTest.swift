//
//  VoicevoxDiskCacheStoreTest.swift
//  NovelSpeakerTests
//
//  VOICEVOX の合成済み音声をディスクに貯めておく保存層のテスト。
//
//  背景: 背面バッテリー駆動では iOS の CPU 上限(60秒平均で1コア相当の80%)により、
//  実測で iPhone 17 Pro Max ですら 1.45倍速に届かず(必要CPU率128%)、
//  iPhone SE2 では 226% と全く歯が立たない。スケジューラ側の改善は理論下限に
//  到達済みで、事前に作って貯めておく以外に無音を無くす方法が無い。
//
//  設計の要点:
//   - 鍵は内容アドレス方式(styleId と読み上げ文字列から決まる)。読み替え辞書を
//     変更しても、変わったブロックだけが作り直しになる。
//   - 索引ファイルを持たない。壊れた索引の整合性を取る処理を書きたくないため、
//     音声の長さはファイル名自体に持たせ、容量も合計時間もディレクトリを
//     見るだけで求まるようにする。
//   - 小説ごとのディレクトリに分ける。管理画面での「この小説だけ削除」と
//     集計がそれだけで成立する。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxDiskCacheStoreTest: XCTestCase {

    private var rootDirectory: URL!
    private var store: VoicevoxDiskCacheStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VoicevoxDiskCacheStoreTest-\(UUID().uuidString)")
        store = VoicevoxDiskCacheStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootDirectory)
        try super.tearDownWithError()
    }

    private func makeData(bytes: Int) -> Data {
        return Data(repeating: 0x41, count: bytes)
    }

    // MARK: - 鍵

    // 同じ内容からは常に同じ鍵が得られる事(内容アドレス方式の前提)。
    func testKeyIsStableForTheSameContent() {
        let a = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        let b = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        XCTAssertEqual(a, b)
    }

    // 話者が違えば別の音声なので、鍵も別である事。
    func testKeyDiffersByStyleId() {
        let a = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        let b = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 4)
        XCTAssertNotEqual(a, b)
    }

    func testKeyDiffersByText() {
        let a = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        let b = VoicevoxDiskCacheStore.key(text: "こんばんは", styleId: 3)
        XCTAssertNotEqual(a, b)
    }

    // 鍵はそのままファイル名になるので、ファイル名に使えない文字を含まない事。
    func testKeyIsFileNameSafe() {
        let key = VoicevoxDiskCacheStore.key(text: "/../危険な\u{0}文字列\n", styleId: 0)
        XCTAssertFalse(key.isEmpty)
        XCTAssertNil(key.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted),
                     "英数字だけである事(パス区切りやヌル文字が混ざるとディレクトリの外に書ける)")
    }

    // MARK: - 保存と取り出し

    func testStoreAndLoad() throws {
        let key = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        try store.store(novelID: "novel-A", key: key, data: makeData(bytes: 100), durationSeconds: 1.5)
        XCTAssertEqual(store.load(novelID: "novel-A", key: key)?.count, 100)
    }

    func testLoadReturnsNilForUnknownKey() {
        XCTAssertNil(store.load(novelID: "novel-A", key: VoicevoxDiskCacheStore.key(text: "無い", styleId: 0)))
    }

    // 保存していない小説を読んでも(ディレクトリが無くても)落ちない事。
    func testLoadOnMissingDirectoryIsSafe() {
        XCTAssertNil(store.load(novelID: "存在しない小説", key: "deadbeef"))
        XCTAssertEqual(store.summary(novelID: "存在しない小説").entryCount, 0)
    }

    // 同じ鍵に二度書いても重複せず、上書きになる事。
    func testStoringTwiceOverwritesInsteadOfDuplicating() throws {
        let key = VoicevoxDiskCacheStore.key(text: "こんにちは", styleId: 3)
        try store.store(novelID: "novel-A", key: key, data: makeData(bytes: 100), durationSeconds: 1.5)
        try store.store(novelID: "novel-A", key: key, data: makeData(bytes: 200), durationSeconds: 3.0)
        XCTAssertEqual(store.load(novelID: "novel-A", key: key)?.count, 200)
        let summary = store.summary(novelID: "novel-A")
        XCTAssertEqual(summary.entryCount, 1)
        XCTAssertEqual(summary.audioSeconds, 3.0, accuracy: 0.01)
    }

    // MARK: - 集計(管理画面の「何分ぶん作れたか」)

    // 索引ファイル無しで、合計の長さと容量が求まる事。
    func testSummaryCountsDurationAndBytes() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 100), durationSeconds: 12.5)
        try store.store(novelID: "novel-A", key: "bbbb", data: makeData(bytes: 300), durationSeconds: 7.5)
        let summary = store.summary(novelID: "novel-A")
        XCTAssertEqual(summary.entryCount, 2)
        XCTAssertEqual(summary.audioSeconds, 20.0, accuracy: 0.01)
        XCTAssertEqual(summary.byteCount, 400)
    }

    // 長さは秒未満まで保てる事(ブロックは数秒〜数十秒なので、丸めると合計が狂う)。
    func testDurationSurvivesSubSecondPrecision() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 10), durationSeconds: 3.456)
        XCTAssertEqual(store.summary(novelID: "novel-A").audioSeconds, 3.456, accuracy: 0.002)
    }

    // 小説ごとに分かれていて、集計が混ざらない事。
    func testSummaryIsPerNovel() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 100), durationSeconds: 10)
        try store.store(novelID: "novel-B", key: "bbbb", data: makeData(bytes: 100), durationSeconds: 20)
        XCTAssertEqual(store.summary(novelID: "novel-A").audioSeconds, 10, accuracy: 0.01)
        XCTAssertEqual(store.summary(novelID: "novel-B").audioSeconds, 20, accuracy: 0.01)
        XCTAssertEqual(store.totalSummary().audioSeconds, 30, accuracy: 0.01)
    }

    // 小説IDにファイル名として使えない文字(URLや「/」を含む事がある)が来ても、
    // ディレクトリの外に書き出したりせずに扱える事。
    func testNovelIDWithPathCharactersIsHandled() throws {
        let novelID = "https://example.com/novel/../../etc/passwd"
        try store.store(novelID: novelID, key: "aaaa", data: makeData(bytes: 10), durationSeconds: 1)
        XCTAssertEqual(store.load(novelID: novelID, key: "aaaa")?.count, 10)
        XCTAssertEqual(store.summary(novelID: novelID).entryCount, 1)
        // 保存先が root の下から出ていない事。
        let contents = try FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.count, 1)
    }

    // MARK: - 削除

    func testRemoveNovelRemovesOnlyThatNovel() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 100), durationSeconds: 10)
        try store.store(novelID: "novel-B", key: "bbbb", data: makeData(bytes: 100), durationSeconds: 20)
        store.remove(novelID: "novel-A")
        XCTAssertEqual(store.summary(novelID: "novel-A").entryCount, 0)
        XCTAssertEqual(store.summary(novelID: "novel-B").entryCount, 1)
    }

    func testRemoveAllRemovesEverything() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 100), durationSeconds: 10)
        try store.store(novelID: "novel-B", key: "bbbb", data: makeData(bytes: 100), durationSeconds: 20)
        store.removeAll()
        XCTAssertEqual(store.totalSummary().entryCount, 0)
    }

    // 読み替え辞書の変更などで内容が変わった時、要らなくなった物だけを消せる事
    // (作り直しに数十分かかるので、全消しにはできない)。
    func testRemovingEntriesNotInTheKeepListLeavesTheRest() throws {
        try store.store(novelID: "novel-A", key: "keep1", data: makeData(bytes: 10), durationSeconds: 1)
        try store.store(novelID: "novel-A", key: "keep2", data: makeData(bytes: 10), durationSeconds: 1)
        try store.store(novelID: "novel-A", key: "stale", data: makeData(bytes: 10), durationSeconds: 1)
        store.removeEntries(novelID: "novel-A", notIn: ["keep1", "keep2"])
        XCTAssertNotNil(store.load(novelID: "novel-A", key: "keep1"))
        XCTAssertNotNil(store.load(novelID: "novel-A", key: "keep2"))
        XCTAssertNil(store.load(novelID: "novel-A", key: "stale"))
    }

    // MARK: - 存在確認

    // 生成の再開時に「どこまで作れているか」を数えるため、
    // 中身を読まずに有無だけを高速に判定できる事。
    func testContainsDoesNotRequireReadingTheData() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 10), durationSeconds: 1)
        XCTAssertTrue(store.contains(novelID: "novel-A", key: "aaaa"))
        XCTAssertFalse(store.contains(novelID: "novel-A", key: "bbbb"))
    }

    // MARK: - バックアップ除外

    // iCloud/iTunes バックアップに含めない事。
    // 合成し直せる物であり、1作品で数十MBになるため、含めると利用者の
    // バックアップ容量を無断で食い潰す事になる。
    func testCacheDirectoryIsExcludedFromBackup() throws {
        try store.store(novelID: "novel-A", key: "aaaa", data: makeData(bytes: 10), durationSeconds: 1)
        let values = try rootDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: - 並行アクセス

    // 生成中(書き込み)に再生(読み出し)が走っても壊れない事。
    func testConcurrentStoreAndLoadIsSafe() {
        DispatchQueue.concurrentPerform(iterations: 100) { i in
            try? self.store.store(novelID: "novel-A", key: "key\(i)", data: self.makeData(bytes: 50), durationSeconds: 1)
            _ = self.store.load(novelID: "novel-A", key: "key\(i / 2)")
        }
        XCTAssertEqual(store.summary(novelID: "novel-A").entryCount, 100)
    }
}
