//
//  VoicevoxTemporaryAudioTest.swift
//  NovelSpeakerTests
//
//  読み上げ中に作った音声(一時分)の置き場所と消え方。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxTemporaryAudioTest: XCTestCase {

    private var root: URL!
    private var store: VoicevoxDiskCacheStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vvtemp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = VoicevoxDiskCacheStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func put(_ novelID: String, chapter: Int, text: String, styleId: UInt32 = 3,
                     seconds: Double = 30, area: VoicevoxDiskCacheStore.Area,
                     modifiedAt: Date? = nil) throws -> String {
        let key = VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
        try store.store(novelID: novelID, chapterNumber: chapter, key: key,
                        data: Data(repeating: 0xAB, count: 1024),
                        durationSeconds: seconds, area: area)
        if let modifiedAt = modifiedAt {
            // 「古い順に消す」の検証のため、作った時刻を後から動かす。
            // ディレクトリ名は小説IDのハッシュで外から作れないので、置いた物を探して当てる。
            let milliseconds = Int((seconds * 1000).rounded())
            let fileName = "\(key)_\(milliseconds).m4a"
            let url = try XCTUnwrap(findFile(named: fileName), "置いたはずの \(fileName) が見つからない")
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        }
        return key
    }

    private func findFile(named fileName: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == fileName {
            return url
        }
        return nil
    }

    // MARK: - 置き場所が分かれている事

    // ★「作成済み」に一時分が混ざらない事。混ざると
    // 「作らせた覚えの無い容量」が増えていく事になる。
    func testTemporaryIsNotCountedAsGenerated() throws {
        try put("novel-1", chapter: 1, text: "作らせた分", seconds: 10, area: .permanent)
        try put("novel-1", chapter: 1, text: "読み上げ中に作った分", seconds: 20, area: .temporary)

        XCTAssertEqual(store.summary(novelID: "novel-1").audioSeconds, 10, accuracy: 0.01)
        XCTAssertEqual(store.temporaryTotalSummary().audioSeconds, 20, accuracy: 0.01)
        XCTAssertEqual(store.totalSummary().audioSeconds, 10, accuracy: 0.01,
                       "作成済みの合計に一時分が混ざっている")
    }

    // 再生側から見れば区別は無く、どちらからも読める事。
    func testBothAreasAreReadable() throws {
        let permanentKey = try put("novel-1", chapter: 1, text: "作らせた分", area: .permanent)
        let temporaryKey = try put("novel-1", chapter: 1, text: "一時分", area: .temporary)

        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: permanentKey))
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: temporaryKey))
        XCTAssertNotNil(store.load(novelID: "novel-1", chapterNumber: 1, key: temporaryKey))
        XCTAssertEqual(store.durationSeconds(novelID: "novel-1", chapterNumber: 1, key: temporaryKey) ?? 0,
                       30, accuracy: 0.01)
    }

    // MARK: - 別の小説に移った時

    // ★一時分は「今読んでいる小説のための物」。他の小説の分は捨てる。
    func testOtherNovelsTemporaryIsRemoved() throws {
        let keptKey = try put("novel-1", chapter: 1, text: "今の小説", area: .temporary)
        try put("novel-2", chapter: 1, text: "前の小説", area: .temporary)

        XCTAssertGreaterThan(store.removeTemporary(exceptNovelID: "novel-1"), 0)
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: keptKey))
        XCTAssertEqual(store.temporaryNovelIDs(), ["novel-1"])
    }

    // ★作らせた分は、別の小説に移っても消さない。
    func testSwitchingNovelsKeepsGeneratedAudio() throws {
        let key = try put("novel-2", chapter: 1, text: "作らせた分", area: .permanent)
        try put("novel-2", chapter: 1, text: "一時分", area: .temporary)

        store.removeTemporary(exceptNovelID: "novel-1")
        XCTAssertTrue(store.contains(novelID: "novel-2", chapterNumber: 1, key: key),
                      "作らせた分まで消えている")
        XCTAssertEqual(store.summary(novelID: "novel-2").audioSeconds, 30, accuracy: 0.01)
    }

    // MARK: - 古い物から消える事

    // ★新しい方(=読み上げの先へ作った分)が残り、古い方(=聴き終わった分)から消える事。
    func testOldestTemporaryIsRemovedFirst() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let oldKey = try put("novel-1", chapter: 1, text: "聴き終わった分", seconds: 60,
                             area: .temporary, modifiedAt: base)
        let newKey = try put("novel-1", chapter: 1, text: "これから聴く分", seconds: 60,
                             area: .temporary, modifiedAt: base.addingTimeInterval(600))

        // 60秒ぶんだけ残す = 古い方の1件が消える。
        XCTAssertGreaterThan(store.trimTemporary(novelID: "novel-1", keepingSeconds: 60), 0)
        XCTAssertFalse(store.contains(novelID: "novel-1", chapterNumber: 1, key: oldKey),
                       "古い方が残っている")
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: newKey),
                      "新しい方(これから聴く分)まで消えている")
    }

    // 収まっている時は何も消さない。
    func testTrimKeepsEverythingWithinBudget() throws {
        let key = try put("novel-1", chapter: 1, text: "一時分", seconds: 30, area: .temporary)
        XCTAssertEqual(store.trimTemporary(novelID: "novel-1", keepingSeconds: 600), 0)
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: key))
    }

    // ★整理しても作らせた分は減らない。
    func testTrimDoesNotTouchGeneratedAudio() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let key = try put("novel-1", chapter: 1, text: "作らせた分", seconds: 600, area: .permanent)
        try put("novel-1", chapter: 1, text: "一時分", seconds: 600, area: .temporary, modifiedAt: base)

        store.trimTemporary(novelID: "novel-1", keepingSeconds: 0)
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: key))
        XCTAssertEqual(store.summary(novelID: "novel-1").audioSeconds, 600, accuracy: 0.01)
    }

    // MARK: - 貯めてよい長さ

    // 後ろに残す分と先へ作り足す分の合計。新しい設定値は作らない。
    func testBudgetIsTheSumOfExistingSettings() {
        let behind = VoicevoxTemporaryAudio.keepBehindMinutes
        let ahead = VoicevoxCacheLead.keepGeneratingBelowMinutes
        XCTAssertEqual(VoicevoxTemporaryAudio.budgetSeconds(),
                       max(Double(behind + ahead) * 60, 60), accuracy: 0.01)
    }

    // MARK: - 版の掃除との関係

    // ★版の掃除で一時分まで消さない事(消すと読み上げ中に貯めた分が毎回飛ぶ)。
    func testOutdatedLayoutCleanupKeepsTemporary() throws {
        let key = try put("novel-1", chapter: 1, text: "一時分", area: .temporary)
        let stale = root.appendingPathComponent("v99", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)

        store.removeOutdatedLayouts()
        XCTAssertTrue(store.contains(novelID: "novel-1", chapterNumber: 1, key: key),
                      "版の掃除で一時分まで消えている")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    }
}
