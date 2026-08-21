//
//  VoicevoxSilenceReporterTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxSilenceReporterTest: XCTestCase {

    private var reporter: VoicevoxSilenceReporter!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        reporter = VoicevoxSilenceReporter()
        reporter.resetForTesting()
    }

    // MARK: - 何を無音として数えるか

    func testLongGapIsReported() {
        reporter.notePlaybackEnded(intentionalDelay: 0, at: start)
        let gap = reporter.notePlaybackStarting(at: start.addingTimeInterval(5))
        XCTAssertEqual(gap ?? 0, 5, accuracy: 0.001)
    }

    // 短い途切れは端末の都合でも起きるので拾わない(拾うと通知が意味を失う)。
    func testShortGapIsIgnored() {
        reporter.notePlaybackEnded(intentionalDelay: 0, at: start)
        XCTAssertNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(0.5)))
    }

    // ★「間の設定」による意図的なポーズは無音ではない。
    // 引かないと、間を長く設定している人ほど途切れた事にされてしまう。
    func testIntentionalDelayIsSubtracted() {
        reporter.notePlaybackEnded(intentionalDelay: 4, at: start)
        XCTAssertNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(5)),
                     "意図的な間まで無音として数えている")
    }

    func testIntentionalDelayStillLeavesRealGap() {
        reporter.notePlaybackEnded(intentionalDelay: 1, at: start)
        let gap = reporter.notePlaybackStarting(at: start.addingTimeInterval(6))
        XCTAssertEqual(gap ?? 0, 5, accuracy: 0.001)
    }

    // ★停止・一時停止は無音ではない。数えると誤検出だらけになる。
    func testUserStopIsNotSilence() {
        reporter.notePlaybackEnded(intentionalDelay: 0, at: start)
        reporter.notePlaybackInterrupted()
        XCTAssertNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(60)))
    }

    // 鳴らし終えた記録が無い状態(最初の一本)では何も起きない。
    func testFirstPlaybackIsNotAGap() {
        XCTAssertNil(reporter.notePlaybackStarting(at: start))
    }

    // 一度数えた区間を二重に数えない。
    func testGapIsCountedOnlyOnce() {
        reporter.notePlaybackEnded(intentionalDelay: 0, at: start)
        XCTAssertNotNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(5)))
        XCTAssertNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(10)))
    }

    // MARK: - 文面とまとめ方

    // 問い合わせで効くのは「何回・合計何秒・最長何秒・なぜ」。
    func testSummaryMessageSaysCountTotalWorstAndWhy() {
        let message = VoicevoxSilenceReporter.summaryMessage(
            totalCount: 217, totalSeconds: 940, worstSeconds: 14.0, latestSeconds: 3.25,
            cause: .synthesisWasTooSlow)
        XCTAssertTrue(message.contains("217回"), message)
        XCTAssertTrue(message.contains("940秒"), message)
        XCTAssertTrue(message.contains("14.0秒"), message)
        XCTAssertTrue(message.contains("合成が再生に間に合わなかった"), message)
    }

    // 理由が分からない事もある。その時も数字は出す。
    func testSummaryMessageWithoutCause() {
        let message = VoicevoxSilenceReporter.summaryMessage(
            totalCount: 1, totalSeconds: 3, worstSeconds: 3, latestSeconds: 3, cause: nil)
        XCTAssertTrue(message.contains("1回"), message)
        XCTAssertFalse(message.contains("理由"), message)
    }

    // ★長さの分布が残る事。これが無いと「2秒が200回」なのか
    // 「14秒が200回」なのかが区別できない(実機ログで実際に区別できなかった)。
    func testLengthDistributionIsKept() {
        XCTAssertEqual(VoicevoxSilenceReporter.bucketIndex(forSeconds: 2.5), 0)
        XCTAssertEqual(VoicevoxSilenceReporter.bucketIndex(forSeconds: 3.0), 1)
        XCTAssertEqual(VoicevoxSilenceReporter.bucketIndex(forSeconds: 7.0), 2)
        XCTAssertEqual(VoicevoxSilenceReporter.bucketIndex(forSeconds: 14.0), 3)
        XCTAssertEqual(VoicevoxSilenceReporter.bucketIndex(forSeconds: 60.0), 4)
    }

    // 分布の1行表示。0件の区切りは出さない(読みにくくなるだけなので)。
    func testBucketTextShowsOnlyNonEmptyBuckets() {
        let text = VoicevoxSilenceReporter.bucketText(counts: [12, 0, 3, 0, 1])
        XCTAssertTrue(text.contains("2-3s:12"), text)
        XCTAssertTrue(text.contains("5-10s:3"), text)
        XCTAssertTrue(text.contains("20s-:1"), text)
        XCTAssertFalse(text.contains(":0"), text)
    }

    // 先行合成に出せていなかった場合は、端末の速さではなく取りこぼしを疑う事になる。
    func testNotScheduledCauseIsDistinguished() {
        reporter.notePlaybackEnded(intentionalDelay: 0, at: start)
        reporter.noteCacheMiss(wasQueuedForPrefetch: false)
        XCTAssertNotNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(5)))
        XCTAssertEqual(VoicevoxSilenceReporter.Cause.notScheduled.text, "先行合成に出せていなかった")
    }
}
