import XCTest
import AVFoundation
@testable import NovelSpeaker

// XcodeのNovelSpeakerスキームで実行できる停止の回帰テスト。
// CLI例（使用するXcodeはDEVELOPER_DIRで選択）:
// xcodebuild -workspace novelspeaker.xcworkspace -scheme NovelSpeaker \
//   -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
//   -parallel-testing-enabled NO -only-testing:NovelSpeakerTests/SpeechWaitStopTest \
//   CODE_SIGNING_ALLOWED=NO test
final class SpeechWaitStopTest: XCTestCase {
    private final class RecordingDelegate: SpeakRangeDelegate {
        var cancellations = 0
        var completions = 0
        var ranges = 0
        var cancelled: XCTestExpectation?
        var finished: XCTestExpectation?
        func willSpeakRange(range: NSRange) { ranges += 1 }
        func finishSpeak(isCancel: Bool, speechString: String) {
            if isCancel {
                cancellations += 1
                cancelled?.fulfill()
            } else {
                completions += 1
                finished?.fulfill()
            }
        }
    }

    // このテストでは発話終了の観測・expectationの設定はメインスレッドで行う。
    private final class ObservedSpeaker: Speaker, @unchecked Sendable {
        let utteranceFinished: XCTestExpectation
        init(utteranceFinished: XCTestExpectation) {
            self.utteranceFinished = utteranceFinished
            super.init()
        }
        override func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            super.speechSynthesizer(synthesizer, didFinish: utterance)
            utteranceFinished.fulfill()
        }
    }

    private func makeQueuedSpeaker() -> (MultiVoiceSpeaker, Speaker) {
        let multi = MultiVoiceSpeaker()
        let engine = Speaker()
        engine.delegate = multi
        multi.speakerCache[multi.defaultVoice.identifier] = engine
        multi.Speech(text: "確認。", voiceIdentifier: multi.defaultVoice.identifier, locale: "ja-JP", delay: 60)
        return (multi, engine)
    }

    private func enterWait(_ engine: Speaker) {
        // OSの発話終了通知と同じ入口を呼ぶ。音声の有無・再生速度によらず、
        // 実際のSpeechCompletionWaitを必ず開始できる再現手順。
        engine.speechSynthesizer(engine.synthesizer, didFinish: AVSpeechUtterance(string: "確認。"))
        XCTAssertTrue(engine.isSpeaking())
        XCTAssertFalse(engine.synthesizer.isSpeaking)
    }

    func testStopWhileWaitingReturnsAndNotifiesExactlyOnce() {
        let (multi, engine) = makeQueuedSpeaker()
        defer { engine.delegate = nil; multi.delegate = nil }
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        enterWait(engine)
        let stopped = expectation(description: "Stop returns without reacquiring its own lock")
        let cancelled = expectation(description: "one cancellation")
        delegate.cancelled = cancelled

        // 修正前はここで同じNSLockを再取得して停止する。
        // ワーカースレッドで止めることで、テスト自体はタイムアウトで失敗を記録できる。
        DispatchQueue.global().async {
            multi.Stop()
            stopped.fulfill()
        }
        let result = XCTWaiter.wait(for: [stopped, cancelled], timeout: 2)
        guard result == .completed else {
            XCTFail("待機中のStopが戻らないか、キャンセル通知が届かない（\(result.rawValue)）")
            return
        }
        XCTAssertFalse(engine.isSpeaking())
        XCTAssertFalse(multi.isSpeaking)
        XCTAssertEqual(delegate.cancellations, 1)
        XCTAssertEqual(delegate.completions, 0)
        multi.Stop()
        XCTAssertEqual(delegate.cancellations, 1)
    }

    func testOldCancellationDoesNotConsumeImmediatelyRestartedSpeech() {
        let (multi, engine) = makeQueuedSpeaker()
        defer { engine.delegate = nil; multi.delegate = nil }
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        enterWait(engine)
        multi.Stop()
        multi.Speech(text: "次の発話。", voiceIdentifier: multi.defaultVoice.identifier, locale: "ja-JP", delay: 60)
        enterWait(engine)

        let drained = expectation(description: "previous cancellation has been processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(delegate.cancellations, 0)
        XCTAssertTrue(multi.isSpeaking, "古いキャンセル通知が新しいキューを消費してはいけない")

        let cancelled = expectation(description: "new speech cancellation")
        delegate.cancelled = cancelled
        multi.Stop()
        wait(for: [cancelled], timeout: 2)
        XCTAssertFalse(multi.isSpeaking)
        XCTAssertEqual(delegate.cancellations, 1)
    }

    func testStopWhileWaitIsPausedAlsoCancelsIt() {
        let (multi, engine) = makeQueuedSpeaker()
        defer { engine.delegate = nil; multi.delegate = nil }
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        enterWait(engine)
        engine.Pause()
        XCTAssertTrue(engine.isPaused())
        let cancelled = expectation(description: "paused wait cancellation")
        delegate.cancelled = cancelled
        multi.Stop()
        wait(for: [cancelled], timeout: 2)
        XCTAssertFalse(engine.isPaused())
        XCTAssertFalse(engine.isSpeaking())
        XCTAssertFalse(multi.isSpeaking)
        XCTAssertEqual(delegate.cancellations, 1)
    }

    func testOldCancellationDoesNotConsumeSpeechRestartedWithAnotherVoice() {
        let (multi, firstEngine) = makeQueuedSpeaker()
        let secondEngine = Speaker()
        defer {
            firstEngine.delegate = nil
            secondEngine.delegate = nil
            multi.delegate = nil
            secondEngine.reloadSynthesizer()
        }
        secondEngine.delegate = multi
        let secondVoice = "wait-stop-test-second-voice"
        multi.speakerCache[secondVoice] = secondEngine
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        enterWait(firstEngine)
        multi.Stop()
        multi.Speech(text: "別の話者。", voiceIdentifier: secondVoice, locale: "ja-JP", delay: 60)
        enterWait(secondEngine)
        let drained = expectation(description: "previous voice cancellation has been processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(delegate.cancellations, 0)
        XCTAssertTrue(multi.isSpeaking, "別の話者の古い通知でも新しいキューを消費してはいけない")
        let cancelled = expectation(description: "second voice cancellation")
        delegate.cancelled = cancelled
        multi.Stop()
        wait(for: [cancelled], timeout: 2)
        XCTAssertFalse(multi.isSpeaking)
        XCTAssertEqual(delegate.cancellations, 1)
    }

    func testQueuedSpeechAdvancesAndOldCallbacksAreIgnored() throws {
        let (multi, firstEngine) = makeQueuedSpeaker()
        let firstDelegate = try XCTUnwrap(firstEngine.delegate)
        let secondEngine = Speaker()
        defer { firstEngine.delegate = nil; secondEngine.delegate = nil; multi.delegate = nil }
        secondEngine.delegate = multi
        let secondVoice = "wait-stop-test-queued-voice"
        multi.speakerCache[secondVoice] = secondEngine
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        multi.Speech(text: "次の話者。", voiceIdentifier: secondVoice, locale: "ja-JP", delay: 0.02)

        firstEngine.delay = 0
        firstEngine.speechSynthesizer(firstEngine.synthesizer, didFinish: AVSpeechUtterance(string: "確認。"))
        XCTAssertEqual(secondEngine.delay, 0.02, "次の発話が実際にキューから開始されたこと")
        enterWait(secondEngine)
        firstDelegate.willSpeakRange(range: NSRange(location: 0, length: 1))
        firstDelegate.finishSpeak(isCancel: false, speechString: "確認。")
        XCTAssertEqual(delegate.ranges, 0)
        XCTAssertEqual(delegate.completions, 0)
        XCTAssertTrue(multi.isSpeaking)
        secondEngine.delegate?.willSpeakRange(range: NSRange(location: 0, length: 1))
        XCTAssertEqual(delegate.ranges, 1)
        let finished = expectation(description: "queued speech finishes normally after wait")
        delegate.finished = finished
        wait(for: [finished], timeout: 2)
        XCTAssertFalse(multi.isSpeaking)
        XCTAssertEqual(delegate.completions, 1)
        XCTAssertEqual(delegate.cancellations, 0)
    }

    func testReloadInvalidatesPendingCancellation() {
        let (multi, engine) = makeQueuedSpeaker()
        defer { engine.delegate = nil; multi.delegate = nil }
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        enterWait(engine)
        multi.Stop()
        engine.reloadSynthesizer()
        let drained = expectation(description: "pending cancellation has been processed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(delegate.cancellations, 0)
    }

    func testStopDuringActualPostSpeechWait() throws {
        let voice = try XCTUnwrap(AVSpeechSynthesisVoice(language: "ja-JP"))
        let multi = MultiVoiceSpeaker()
        let finished = expectation(description: "actual utterance finishes and enters wait")
        let engine = ObservedSpeaker(utteranceFinished: finished)
        defer { engine.delegate = nil; multi.delegate = nil }
        engine.delegate = multi
        multi.speakerCache[voice.identifier] = engine
        let delegate = RecordingDelegate()
        multi.delegate = delegate
        multi.Speech(text: "確認。", voiceIdentifier: voice.identifier, locale: "ja-JP", delay: 5)

        // Speaker.Speechは通常の単体テスト中には発話しないため、この検証だけ
        // 同じsynthesizerを直接動かす。発話完了以降はすべてアプリの実処理を通る。
        let utterance = AVSpeechUtterance(string: "確認。")
        utterance.voice = voice
        utterance.rate = 0.5
        engine.synthesizer.speak(utterance)
        guard XCTWaiter.wait(for: [finished], timeout: 30) == .completed else {
            engine.reloadSynthesizer()
            XCTFail("実際の発話終了に到達しなかったため、停止の検証は成立していない")
            return
        }
        XCTAssertTrue(engine.isSpeaking())
        XCTAssertFalse(engine.synthesizer.isSpeaking)
        let cancelled = expectation(description: "actual wait cancelled")
        delegate.cancelled = cancelled
        let stopped = expectation(description: "actual wait Stop returns")
        DispatchQueue.global().async {
            multi.Stop()
            stopped.fulfill()
        }
        guard XCTWaiter.wait(for: [stopped, cancelled], timeout: 2) == .completed else {
            XCTFail("実発話後の間の待機中にStopが戻らないか、キャンセル通知が届かない")
            return
        }
        XCTAssertFalse(engine.isSpeaking())
        XCTAssertFalse(multi.isSpeaking)
        XCTAssertEqual(delegate.cancellations, 1)
        XCTAssertEqual(delegate.completions, 0)
    }
}
