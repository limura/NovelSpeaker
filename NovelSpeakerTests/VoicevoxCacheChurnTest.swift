//
//  VoicevoxCacheChurnTest.swift
//  NovelSpeakerTests
//
//  「裏の作り足し」と「一時分の刈り取り」が噛み合って、
//  再生の目の前の音声を延々と作り直し続ける状態を再現するテスト。
//
//  実機ログ(2026-08-22, 3時間半の連続再生)で観測したもの:
//   - 同じ本文の作り直しが、生成の6〜9割に達する時間帯が周期的に現れる
//   - その間ずっと「貯めてあった分」が 0本、貯金は45秒前後で張り付き
//   - 10〜16秒の長い無音が、その時間帯にだけ集中する
//
//  原因は2つで、片方だけでは起きない:
//   A. 貯金の集計が次話以降を `permanent` でしか見ておらず、
//      裏の作り足しが置く `temporary` が数えられない。
//      → 「15分貯まったら止める」に永遠に到達せず、小説の最後まで作り続ける。
//   B. 刈り取りが更新時刻の古い順に消すため、A で何十話も先まで作られると
//      聴き終わった分を消し尽くした後、**一番古い = 再生ヘッドのすぐ前**を消し始める。
//      → 消される → 再生側が作り直す → 書き込みがまた刈り取りを呼ぶ、の自己増殖。
//
//  どちらも3時間動かさないと出ない類なので、ここで固定しておく。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCacheChurnTest: XCTestCase {

    private var root: URL!
    private var store: VoicevoxDiskCacheStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vvchurn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = VoicevoxDiskCacheStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private let novelID = "churn-novel"

    /// 1話ぶんの一時分を置く。作った時刻は「作り足しが前から順に書いた」順にする。
    @discardableResult
    private func putChapter(_ chapterNumber: Int, seconds: Double, writtenAt: Date? = nil) throws -> String {
        let text = "churn-\(chapterNumber)話"
        let key = VoicevoxDiskCacheStore.key(text: text, styleId: 3)
        try store.store(novelID: novelID, chapterNumber: chapterNumber, key: key,
                        data: Data(repeating: 0xAB, count: 1024),
                        durationSeconds: seconds, area: .temporary)
        if let writtenAt = writtenAt {
            let fileName = "\(key)_\(Int((seconds * 1000).rounded())).m4a"
            let url = try XCTUnwrap(findFile(named: fileName), "置いたはずの \(fileName) が見つからない")
            try FileManager.default.setAttributes([.modificationDate: writtenAt], ofItemAtPath: url.path)
        }
        return key
    }

    private func hasChapter(_ chapterNumber: Int) -> Bool {
        let key = VoicevoxDiskCacheStore.key(text: "churn-\(chapterNumber)話", styleId: 3)
        return store.contains(novelID: novelID, chapterNumber: chapterNumber, key: key)
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

    // MARK: - A: 貯金の集計

    // ★裏の作り足しが置いた分(一時分)も貯金として数える事。
    //
    // 数えられないと「まだ15分に足りない」と判定し続け、
    // 作り足しが小説の最後まで止まらなくなる(これが B の前提条件になる)。
    func testLeadCountsTemporaryAudioOfFollowingChapters() throws {
        try putChapter(2, seconds: 300)
        try putChapter(3, seconds: 300)

        // 今の話は最後まで揃っている(穴が無い)ので、次話以降も数えにいく。
        let lead = VoicevoxCacheLead.contiguousLeadSeconds(
            store: store, novelID: novelID, chapterNumber: 1,
            upcomingDurations: [10, 10])

        XCTAssertEqual(lead, 620, accuracy: 0.01,
                       "次話以降の一時分が貯金に数えられていない(=作り足しが止まらなくなる)")
    }

    // 作らせた分だけを数えていた頃の挙動が、そのまま残っている事の確認。
    func testLeadStillCountsPermanentAudioOfFollowingChapters() throws {
        let key = VoicevoxDiskCacheStore.key(text: "churn-2話-permanent", styleId: 3)
        try store.store(novelID: novelID, chapterNumber: 2, key: key,
                        data: Data(repeating: 0xAB, count: 1024),
                        durationSeconds: 300, area: .permanent)

        let lead = VoicevoxCacheLead.contiguousLeadSeconds(
            store: store, novelID: novelID, chapterNumber: 1,
            upcomingDurations: [10])
        XCTAssertEqual(lead, 310, accuracy: 0.01)
    }

    // 今の話に穴がある間は、次話以降を数えない(穴に当たった時点で無音になるため)。
    func testLeadStopsAtAGapInTheCurrentChapter() throws {
        try putChapter(2, seconds: 300)

        let lead = VoicevoxCacheLead.contiguousLeadSeconds(
            store: store, novelID: novelID, chapterNumber: 1,
            upcomingDurations: [10, nil, 10])
        XCTAssertEqual(lead, 10, accuracy: 0.01)
    }

    // MARK: - 起動と停止の往復

    // ★止める線と始める線をずらしてある事。
    //
    // 同じ線だと、閾値ちょうどで止まった直後に再生が少し進んで下回り、
    // また始まって少し作っては止まる、を繰り返す
    // (実機で30秒ごとに20分間で30往復した)。
    func testGeneratorDoesNotRestartRightAfterReachingTheThreshold() {
        let threshold = VoicevoxCacheLead.keepGeneratingBelowSeconds
        // 閾値をちょっと下回っただけ = まだ始めない。
        XCTAssertFalse(VoicevoxCacheLead.shouldResumeGenerating(contiguousLeadSeconds: threshold - 10),
                       "止めた直後にまた始まってしまう")
        // 十分に減ったら始める。
        XCTAssertTrue(VoicevoxCacheLead.shouldResumeGenerating(contiguousLeadSeconds: threshold * 0.5))
        // 走っている間は下限まで作り続ける(こちらは従来どおり)。
        XCTAssertTrue(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: threshold - 10))
        XCTAssertFalse(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: threshold + 10))
    }

    // MARK: - B: 刈り取りが再生の目の前を消さない事

    // ★これから再生する所を刈り取らない事。
    //
    // 作り足しは前から順に書くので、**再生ヘッドの直前が一番古い**。
    // 更新時刻だけで消すと、聴き終わった分を消し尽くした後に
    // 「次に鳴らす1本」を消し始め、作り直し→書き込み→また刈り取り、と回り続ける。
    func testTrimDoesNotRemoveAudioAtOrAheadOfPlayback() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        // 作り足しは1話から順に書いていったので、話番号の順に古い。
        for chapterNumber in 1...5 {
            try putChapter(chapterNumber, seconds: 300,
                           writtenAt: base.addingTimeInterval(Double(chapterNumber) * 60))
        }

        // 合計25分。10分ぶんだけ残す = 3話ぶんが消える。
        // 今読んでいるのは3話なので、消えてよいのは 1話・2話(聴き終わった分)と
        // 一番先の5話であって、3話・4話ではない。
        store.trimTemporary(novelID: novelID, keepingSeconds: 600, playbackChapterNumber: 3)

        XCTAssertTrue(hasChapter(3), "今まさに読んでいる話が刈り取られている")
        XCTAssertTrue(hasChapter(4), "次に読む話が刈り取られている")
        XCTAssertFalse(hasChapter(1), "一番後ろの聴き終わった分が残っている")
        XCTAssertFalse(hasChapter(2), "聴き終わった分が残っている")
        XCTAssertFalse(hasChapter(5), "一番先の分が残っている")
    }

    // 聴き終わった分だけで収まるなら、先の分には手を付けない事。
    func testTrimRemovesOnlyListenedChaptersWhenThatIsEnough() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for chapterNumber in 1...5 {
            try putChapter(chapterNumber, seconds: 300,
                           writtenAt: base.addingTimeInterval(Double(chapterNumber) * 60))
        }

        // 合計25分を20分に。1話(一番後ろ)だけ消えれば足りる。
        store.trimTemporary(novelID: novelID, keepingSeconds: 1200, playbackChapterNumber: 3)

        XCTAssertFalse(hasChapter(1))
        for chapterNumber in 2...5 {
            XCTAssertTrue(hasChapter(chapterNumber), "\(chapterNumber)話まで消えている")
        }
    }

    // 今の話だけで予算を超えていても、今の話は消さない
    // (消せば次に鳴らす1本が無くなり、作り直しの堂々巡りに戻るため)。
    func testTrimKeepsTheChapterBeingPlayedEvenWhenItAloneExceedsTheBudget() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        try putChapter(1, seconds: 300, writtenAt: base)
        try putChapter(2, seconds: 1800, writtenAt: base.addingTimeInterval(60))

        store.trimTemporary(novelID: novelID, keepingSeconds: 600, playbackChapterNumber: 2)

        XCTAssertTrue(hasChapter(2), "今読んでいる話が丸ごと消えている")
        XCTAssertFalse(hasChapter(1))
    }

    // 再生位置が分からない時は、これまでどおり古い順に消す。
    func testTrimFallsBackToOldestFirstWhenPlaybackPositionIsUnknown() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for chapterNumber in 1...3 {
            try putChapter(chapterNumber, seconds: 300,
                           writtenAt: base.addingTimeInterval(Double(chapterNumber) * 60))
        }

        store.trimTemporary(novelID: novelID, keepingSeconds: 600, playbackChapterNumber: nil)

        XCTAssertFalse(hasChapter(1))
        XCTAssertTrue(hasChapter(2))
        XCTAssertTrue(hasChapter(3))
    }
}
