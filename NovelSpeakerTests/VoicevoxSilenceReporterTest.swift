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

    // MARK: - 文面

    // 問い合わせで効くのは「何秒・何回目・なぜ」の3つ。
    func testMessageSaysHowLongHowManyAndWhy() {
        let message = VoicevoxSilenceReporter.message(
            gapSeconds: 3.25, totalCount: 4, cause: .synthesisWasTooSlow)
        XCTAssertTrue(message.contains("3.2秒"), message)
        XCTAssertTrue(message.contains("4回目"), message)
        XCTAssertTrue(message.contains("合成が再生に間に合わなかった"), message)
    }

    // 理由が分からない事もある。その時も秒数と回数は出す。
    func testMessageWithoutCause() {
        let message = VoicevoxSilenceReporter.message(gapSeconds: 3, totalCount: 1, cause: nil)
        XCTAssertTrue(message.contains("3.0秒"), message)
        XCTAssertFalse(message.contains("理由"), message)
    }

    // 先行合成に出せていなかった場合は、端末の速さではなく取りこぼしを疑う事になる。
    func testNotScheduledCauseIsDistinguished() {
        reporter.notePlaybackEnded(intentionalDelay: 0, at: start)
        reporter.noteCacheMiss(wasQueuedForPrefetch: false)
        XCTAssertNotNil(reporter.notePlaybackStarting(at: start.addingTimeInterval(5)))
        XCTAssertEqual(VoicevoxSilenceReporter.Cause.notScheduled.text, "先行合成に出せていなかった")
    }
}
