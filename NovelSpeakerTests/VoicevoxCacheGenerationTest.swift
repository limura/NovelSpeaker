//
//  VoicevoxCacheGenerationTest.swift
//  NovelSpeakerTests
//
//  音声キャッシュの生成まわりの、VOICEVOX 実体に依らない部分のテスト。
//   - 進捗の表示(「第20話『タイトル』の50%まで生成済み、合計3時間12分」)
//   - 再生位置から先に「途切れずに」貯まっている秒数の計算
//   - 再生中も生成を続けるかどうかの判断
//   - 生成の有効/無効と再開位置の記憶
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCacheGenerationProgressTest: XCTestCase {

    func testPercentOfChapter() {
        let progress = VoicevoxCacheGenerationProgress(
            chapterNumber: 20, chapterTitle: "邂逅", generatedBlockCount: 15, totalBlockCount: 30, totalAudioSeconds: 0)
        XCTAssertEqual(progress.chapterPercent, 50)
    }

    // ブロックが0個の話(空ページ等)で 0除算しない事。
    func testPercentWithNoBlocksDoesNotCrash() {
        let progress = VoicevoxCacheGenerationProgress(
            chapterNumber: 1, chapterTitle: "", generatedBlockCount: 0, totalBlockCount: 0, totalAudioSeconds: 0)
        XCTAssertEqual(progress.chapterPercent, 100, "作る物が無い話は作り終えている扱いにする")
    }

    // 進捗が全体を超えて見えない事(先読みが話をまたいだ時など)。
    func testPercentIsClamped() {
        let progress = VoicevoxCacheGenerationProgress(
            chapterNumber: 1, chapterTitle: "", generatedBlockCount: 40, totalBlockCount: 30, totalAudioSeconds: 0)
        XCTAssertEqual(progress.chapterPercent, 100)
    }

    // 「ここまで作れてるなら持ち出していいかな」の判断に使う表示。
    func testDescriptionShowsChapterTitleAndTotalDuration() {
        let progress = VoicevoxCacheGenerationProgress(
            chapterNumber: 20, chapterTitle: "邂逅", generatedBlockCount: 15, totalBlockCount: 30,
            totalAudioSeconds: 3 * 3600 + 12 * 60)
        let text = progress.description
        XCTAssertTrue(text.contains("20"), "何話目かが分かる事")
        XCTAssertTrue(text.contains("邂逅"), "話のタイトルが分かる事")
        XCTAssertTrue(text.contains("50%"), "その話のどこまでかが分かる事")
        XCTAssertTrue(text.contains("3時間12分"), "合計で何分ぶんかが分かる事")
    }

    func testDurationTextFormats() {
        XCTAssertEqual(VoicevoxCacheGenerationProgress.durationText(seconds: 0), "0秒")
        XCTAssertEqual(VoicevoxCacheGenerationProgress.durationText(seconds: 45), "45秒")
        XCTAssertEqual(VoicevoxCacheGenerationProgress.durationText(seconds: 62), "1分2秒")
        XCTAssertEqual(VoicevoxCacheGenerationProgress.durationText(seconds: 3600), "1時間0分")
        XCTAssertEqual(VoicevoxCacheGenerationProgress.durationText(seconds: 3 * 3600 + 12 * 60 + 30), "3時間12分")
    }
}

class VoicevoxCacheLeadTest: XCTestCase {

    // 「この先どれだけ持つか」は、途切れずに繋がっている分だけを数える事。
    // 穴の向こうに1時間ぶんあっても、穴に当たった時点で無音になるので意味が無い。
    func testContiguousSecondsStopsAtTheFirstGap() {
        let durations: [Double?] = [10, 20, nil, 3600]
        XCTAssertEqual(VoicevoxCacheLead.contiguousSeconds(upcomingDurations: durations), 30, accuracy: 0.01)
    }

    func testContiguousSecondsWithNoCache() {
        XCTAssertEqual(VoicevoxCacheLead.contiguousSeconds(upcomingDurations: [nil, 10]), 0, accuracy: 0.01)
        XCTAssertEqual(VoicevoxCacheLead.contiguousSeconds(upcomingDurations: []), 0, accuracy: 0.01)
    }

    func testContiguousSecondsWithEverythingCached() {
        XCTAssertEqual(VoicevoxCacheLead.contiguousSeconds(upcomingDurations: [10, 20, 30]), 60, accuracy: 0.01)
    }

    // 貯金が少なければ、再生中でも生成を続ける事。
    //
    // キャッシュから再生している間は合成の CPU がゼロなので、80% の予算が丸ごと空く。
    // 生成には最も good な条件で、ここで作っておかないと、
    // キャッシュを使い切った瞬間から無音だらけの実時間合成に戻ってしまう。
    func testKeepsGeneratingWhenTheLeadIsShort() {
        XCTAssertTrue(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 0))
        XCTAssertTrue(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 60))
    }

    // 十分に貯まっていれば作らない事(聴き終わらないかもしれない分を作るのは電池の無駄)。
    func testStopsGeneratingWhenTheLeadIsLong() {
        XCTAssertFalse(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 3600))
    }

    // 閾値の前後で反転する事。
    func testThresholdBoundary() {
        let threshold = VoicevoxCacheLead.keepGeneratingBelowSeconds
        XCTAssertTrue(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: threshold - 1))
        XCTAssertFalse(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: threshold + 1))
    }

    // 閾値は設定から変えられる事。
    // 適切な値は「どのくらい先まで聴き続けるか」「端末の速さ」で変わるので、
    // 実測だけで決め打ちにはできない。
    func testThresholdIsConfigurable() {
        let key = VoicevoxCacheLead.keepGeneratingBelowMinutesUserDefaultsKey
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original = original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(VoicevoxCacheLead.keepGeneratingBelowMinutes, VoicevoxCacheLead.defaultKeepGeneratingBelowMinutes)

        VoicevoxCacheLead.keepGeneratingBelowMinutes = 30
        XCTAssertEqual(VoicevoxCacheLead.keepGeneratingBelowSeconds, 1800, accuracy: 0.01)
        XCTAssertTrue(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 1200))

        // 0 にすると「再生中は生成しない」になる事。
        VoicevoxCacheLead.keepGeneratingBelowMinutes = 0
        XCTAssertFalse(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 0))
    }

    // 明示的に閾値を渡す形でも動く事(設定に触らずに判断を組み立てられる)。
    func testExplicitThreshold() {
        XCTAssertTrue(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 10, thresholdSeconds: 60))
        XCTAssertFalse(VoicevoxCacheLead.shouldKeepGenerating(contiguousLeadSeconds: 100, thresholdSeconds: 60))
    }
}

class VoicevoxCacheGenerationStateTest: XCTestCase {

    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var state: VoicevoxCacheGenerationState!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "VoicevoxCacheGenerationStateTest-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        state = VoicevoxCacheGenerationState(userDefaults: userDefaults)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // 何もしていない小説には、勝手にディスクを使わない事。
    // 普通に聴いているだけでストレージを消費し始めるのは、断りなくやってよい事ではない。
    func testDisabledByDefault() {
        XCTAssertFalse(state.isEnabled(novelID: "novel-A"))
    }

    func testEnableAndDisable() {
        state.setEnabled(true, novelID: "novel-A")
        XCTAssertTrue(state.isEnabled(novelID: "novel-A"))
        XCTAssertFalse(state.isEnabled(novelID: "novel-B"), "他の小説には影響しない事")
        state.setEnabled(false, novelID: "novel-A")
        XCTAssertFalse(state.isEnabled(novelID: "novel-A"))
    }

    // 中断して再開できる事(数十分かかるので、毎回最初からでは終わらない)。
    func testResumePositionRoundTrip() {
        XCTAssertNil(state.resumePosition(novelID: "novel-A"))
        state.setResumePosition(chapterNumber: 20, blockIndex: 15, novelID: "novel-A")
        let position = state.resumePosition(novelID: "novel-A")
        XCTAssertEqual(position?.chapterNumber, 20)
        XCTAssertEqual(position?.blockIndex, 15)
    }

    // 生成をやめた時に再開位置も消える事(次に始める時は今の再生位置からになる)。
    func testDisablingClearsTheResumePosition() {
        state.setEnabled(true, novelID: "novel-A")
        state.setResumePosition(chapterNumber: 20, blockIndex: 15, novelID: "novel-A")
        state.setEnabled(false, novelID: "novel-A")
        XCTAssertNil(state.resumePosition(novelID: "novel-A"))
    }

    // 有効にした小説を一覧できる事(管理画面と、再生時に「ディスクへ書くか」の判定に使う)。
    func testEnabledNovelIDsCanBeListed() {
        state.setEnabled(true, novelID: "novel-A")
        state.setEnabled(true, novelID: "novel-B")
        state.setEnabled(false, novelID: "novel-B")
        XCTAssertEqual(state.enabledNovelIDs(), ["novel-A"])
    }
}
