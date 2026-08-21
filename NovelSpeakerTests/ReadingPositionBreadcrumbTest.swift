//
//  ReadingPositionBreadcrumbTest.swift
//  NovelSpeakerTests
//
//  控えを栞へ書き戻してよいかの判断。
//  ここを誤ると、他の端末で読み進めた分を巻き戻す事になるので固めておく。
//

import XCTest
@testable import NovelSpeaker

class ReadingPositionBreadcrumbTest: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func breadcrumb(storyID: String = "novel_1",
                            location: Int = 500,
                            savedSecondsAgo: TimeInterval = 60) -> ReadingPositionBreadcrumb {
        return ReadingPositionBreadcrumb(
            novelID: "novel",
            storyID: storyID,
            location: location,
            savedAt: now.addingTimeInterval(-savedSecondsAgo))
    }

    // ★本命: 殺されて章の頭に戻っている状態から、控えの位置へ復帰できる事。
    func testAppliesWhenBreadcrumbIsAheadInTheSameChapter() {
        XCTAssertTrue(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(location: 500),
            currentStoryID: "novel_1",
            currentLocation: 0,
            now: now))
    }

    // ★他の端末で別の章まで読み進めていた場合に巻き戻さない事。
    func testDoesNotApplyWhenChapterDiffers() {
        XCTAssertFalse(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(storyID: "novel_1", location: 500),
            currentStoryID: "novel_2",
            currentLocation: 0,
            now: now))
    }

    // ★同じ章でも、栞の方が先にいるなら触らない事。
    func testDoesNotApplyWhenBookmarkIsAlreadyAhead() {
        XCTAssertFalse(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(location: 500),
            currentStoryID: "novel_1",
            currentLocation: 900,
            now: now))
    }

    // 同じ位置なら書き戻す意味が無い(無駄な同期通信を起こさない)。
    func testDoesNotApplyWhenSamePosition() {
        XCTAssertFalse(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(location: 500),
            currentStoryID: "novel_1",
            currentLocation: 500,
            now: now))
    }

    // 古い控えは蘇らせない。
    // (何日も前の控えが残っていると、その後に動かした位置を巻き戻しかねない)
    func testDoesNotApplyWhenTooOld() {
        XCTAssertFalse(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(location: 500, savedSecondsAgo: ReadingPositionBreadcrumbStore.expirationSeconds + 1),
            currentStoryID: "novel_1",
            currentLocation: 0,
            now: now))
    }

    // 期限の境目では使える事。
    func testAppliesAtTheExpirationBoundary() {
        XCTAssertTrue(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(location: 500, savedSecondsAgo: ReadingPositionBreadcrumbStore.expirationSeconds),
            currentStoryID: "novel_1",
            currentLocation: 0,
            now: now))
    }

    // 端末の時計が巻き戻った等で未来の控えになっていたら使わない。
    func testDoesNotApplyWhenSavedInTheFuture() {
        XCTAssertFalse(ReadingPositionBreadcrumbStore.shouldApply(
            breadcrumb(location: 500, savedSecondsAgo: -60),
            currentStoryID: "novel_1",
            currentLocation: 0,
            now: now))
    }

    // MARK: - 保存と読み出し

    func testSaveLoadClear() throws {
        let suiteName = "ReadingPositionBreadcrumbTest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let original = ReadingPositionBreadcrumbStore.userDefaults
        ReadingPositionBreadcrumbStore.userDefaults = defaults
        defer {
            ReadingPositionBreadcrumbStore.userDefaults = original
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertNil(ReadingPositionBreadcrumbStore.load())
        let saved = breadcrumb(location: 123)
        ReadingPositionBreadcrumbStore.save(saved)
        XCTAssertEqual(ReadingPositionBreadcrumbStore.load(), saved)
        ReadingPositionBreadcrumbStore.clear()
        XCTAssertNil(ReadingPositionBreadcrumbStore.load())
    }
}
