//
//  VoicevoxPromoteToPermanentTest.swift
//  NovelSpeakerTests
//
//  「作って」と言われた範囲が、読み上げの裏で作った一時分に既にある時の話。
//
//  合成し直しはしない(`contains` は一時分も見る)ので、そこは元から無駄が無い。
//  問題はその後で、飛ばすだけだと音声は一時分に残ったままになる:
//   - 「作成済み」は作らせた分しか数えないので、その分が表示に出ない
//   - 一時分なので後で刈り取りに消され、**作ったはずの所に穴が空く**
//     (生成側は「出来ている」と見て通り過ぎているので、戻って来ない)
//  同じディスクの中なので、ファイルを移すだけで済む。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxPromoteToPermanentTest: XCTestCase {

    private var root: URL!
    private var store: VoicevoxDiskCacheStore!
    private let novelID = "promote-novel"

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vvpromote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = VoicevoxDiskCacheStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func put(_ chapterNumber: Int, seconds: Double, area: VoicevoxDiskCacheStore.Area) throws -> String {
        let key = VoicevoxDiskCacheStore.key(text: "promote-\(chapterNumber)話", styleId: 3)
        try store.store(novelID: novelID, chapterNumber: chapterNumber, key: key,
                        data: Data(repeating: 0xCD, count: 2048),
                        durationSeconds: seconds, area: area)
        return key
    }

    /// 一時分にある物を移すと「作成済み」に数えられるようになる。
    func testPromotedTemporaryAudioBecomesPermanent() throws {
        let key = try put(1, seconds: 12, area: .temporary)

        XCTAssertEqual(store.summary(novelID: novelID, chapterNumber: 1).entryCount, 0,
                       "移す前は「作成済み」に数えられていないはず")
        XCTAssertEqual(store.temporarySummary(novelID: novelID).entryCount, 1)

        XCTAssertTrue(store.promoteToPermanent(novelID: novelID, chapterNumber: 1, key: key))

        XCTAssertEqual(store.summary(novelID: novelID, chapterNumber: 1).entryCount, 1,
                       "移した後は「作成済み」に数えられるはず")
        XCTAssertEqual(store.summary(novelID: novelID, chapterNumber: 1).audioSeconds, 12, accuracy: 0.01)
        XCTAssertEqual(store.temporarySummary(novelID: novelID).entryCount, 0,
                       "一時分からは居なくなっているはず")
    }

    /// 移した後は、一時分の刈り取りに消されない。これが本題。
    func testPromotedAudioSurvivesTemporaryTrim() throws {
        // 再生は5話にいて、1話は聴き終わった後ろ側。刈り取りの最初の標的になる。
        let key = try put(1, seconds: 600, area: .temporary)
        try put(5, seconds: 600, area: .temporary)

        XCTAssertTrue(store.promoteToPermanent(novelID: novelID, chapterNumber: 1, key: key))

        store.trimTemporary(novelID: novelID, keepingSeconds: 1, playbackChapterNumber: 5)

        XCTAssertTrue(store.contains(novelID: novelID, chapterNumber: 1, key: key),
                      "作らせた分へ移してあるので、刈り取りに消されてはいけない")
        XCTAssertEqual(store.summary(novelID: novelID, chapterNumber: 1).entryCount, 1)
    }

    /// 移す前は刈り取りに消される(上のテストが何を守っているかを固定しておく)。
    func testTemporaryAudioIsTrimmedWhenNotPromoted() throws {
        let key = try put(1, seconds: 600, area: .temporary)
        try put(5, seconds: 600, area: .temporary)

        store.trimTemporary(novelID: novelID, keepingSeconds: 1, playbackChapterNumber: 5)

        XCTAssertFalse(store.contains(novelID: novelID, chapterNumber: 1, key: key),
                       "一時分のままなら、聴き終わった分として消される")
    }

    /// 音声は読み直せる(移した先を指せている)。
    func testPromotedAudioIsStillReadable() throws {
        let key = try put(2, seconds: 8, area: .temporary)
        XCTAssertTrue(store.promoteToPermanent(novelID: novelID, chapterNumber: 2, key: key))

        let data = store.load(novelID: novelID, chapterNumber: 2, key: key)
        XCTAssertEqual(data?.count, 2048)
        XCTAssertEqual(store.durationSeconds(novelID: novelID, chapterNumber: 2, key: key) ?? 0, 8, accuracy: 0.01)
    }

    /// 元から作らせた分にある物、そもそも無い物では何もしない。
    func testPromoteDoesNothingWhenThereIsNothingToMove() throws {
        let permanentKey = try put(3, seconds: 5, area: .permanent)
        XCTAssertFalse(store.promoteToPermanent(novelID: novelID, chapterNumber: 3, key: permanentKey))
        XCTAssertEqual(store.summary(novelID: novelID, chapterNumber: 3).entryCount, 1,
                       "何もしないだけで、消してはいけない")

        let missingKey = VoicevoxDiskCacheStore.key(text: "どこにも無い", styleId: 3)
        XCTAssertFalse(store.promoteToPermanent(novelID: novelID, chapterNumber: 3, key: missingKey))
    }
}
