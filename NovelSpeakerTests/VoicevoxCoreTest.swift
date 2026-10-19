//
//  VoicevoxCoreTest.swift
//  NovelSpeakerTests
//
//  VOICEVOX_IOS_INTEGRATION.md §7 の最小検証:
//  init_once → open_jtalk → synthesizer → VVMロード → tts("こんにちは") → WAVがRIFFで始まること。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCoreTest: XCTestCase {

    func testSynthesizeProducesRiffWav() async throws {
        guard let dictPath = Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil) else {
            XCTFail("同梱の open_jtalk_dic_utf_8-1.11 がバンドルに見つかりません")
            return
        }
        guard let vvmPath = VoicevoxTestVoiceModel.path() else {
            throw XCTSkip("テスト用の 0.vvm がありません。scripts/fetch_voicevox_vendor.sh を実行してください")
        }

        let core = VoicevoxCore.shared
        try await core.setUp(dictDirectoryPath: dictPath, voiceModelFilePaths: [vvmPath])

        let styles = await core.styles
        XCTAssertFalse(styles.isEmpty, "0.vvm からスタイルが1つも取れませんでした")
        guard let style = styles.first else { return }

        let wav = try await core.synthesize(text: "こんにちは", styleId: style.styleId)
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(wav.prefix(4), Data("RIFF".utf8))
    }
}

final class VoicevoxModelLifetimeTest: XCTestCase {
    private final class GenerationValue: @unchecked Sendable {
        private let lock = NSLock()
        private var value: UInt64?
        func store(_ value: UInt64) { lock.lock(); self.value = value; lock.unlock() }
        func load() -> UInt64? { lock.lock(); defer { lock.unlock() }; return value }
    }

    func testOldModelOwnersCannotReleaseNewSessionOwners() {
        let lifetime = VoicevoxModelLifetime(delay: 1)
        var old: VoicevoxModelUse? = lifetime.beginUse()
        lifetime.invalidateAllUses()
        let current = lifetime.beginUse()
        old = nil
        XCTAssertEqual(lifetime.activeUseCount, 1)
        withExtendedLifetime((old, current)) {}
    }

    func testOverlappingSessionsOnlyReleaseAfterLastOwnerEnds() {
        let lifetime = VoicevoxModelLifetime(delay: 0.05)
        let idle = expectation(description: "last user ended")
        lifetime.setIdleHandler { _ in idle.fulfill() }
        var playback: VoicevoxModelUse? = lifetime.beginUse()
        var generation: VoicevoxModelUse? = lifetime.beginUse()
        XCTAssertEqual(lifetime.activeUseCount, 2)
        playback = nil
        XCTAssertEqual(lifetime.activeUseCount, 1)
        generation = nil
        XCTAssertEqual(lifetime.activeUseCount, 0)
        wait(for: [idle], timeout: 2)
        withExtendedLifetime((playback, generation)) {}
    }

    func testResumeInvalidatesIdleCallbackAlreadyDispatchedToActor() {
        let lifetime = VoicevoxModelLifetime(delay: 0.01)
        let idle = expectation(description: "idle callback queued")
        let idleGeneration = GenerationValue()
        lifetime.setIdleHandler { value in
            idleGeneration.store(value)
            idle.fulfill()
        }
        var use: VoicevoxModelUse? = lifetime.beginUse()
        use = nil
        wait(for: [idle], timeout: 2)
        let oldGeneration = idleGeneration.load()!
        XCTAssertTrue(lifetime.isIdle(generation: oldGeneration))
        let resumed = lifetime.beginUse()
        XCTAssertFalse(lifetime.isIdle(generation: oldGeneration))
        withExtendedLifetime((use, resumed)) {}
    }

    func testWorkInsideSessionDoesNotScheduleUnloadBetweenBlocks() {
        let lifetime = VoicevoxModelLifetime(delay: 0.02)
        let unexpected = expectation(description: "no unload during batch")
        unexpected.isInverted = true
        lifetime.setIdleHandler { _ in unexpected.fulfill() }
        let batch = lifetime.beginUse()
        for _ in 0..<5 {
            autoreleasepool {
                let work = lifetime.beginUse()
                withExtendedLifetime(work) {}
            }
        }
        wait(for: [unexpected], timeout: 0.1)
        XCTAssertEqual(lifetime.activeUseCount, 1)
        lifetime.setIdleHandler { _ in }
        withExtendedLifetime(batch) {}
    }
}

#if !targetEnvironment(macCatalyst) && !os(watchOS)
import AVFoundation
import Darwin

/// 実モデル・実再生を使うため、通常の短い単体テストとは分けて選択実行できる。
@MainActor
final class VoicevoxModelUnloadIntegrationTest: XCTestCase {
    private final class AudibleSpeaker: VoicevoxSpeaker {
        override func Speech(text: String) { performSpeech(text: text) }
    }
    private final class Finished: SpeakRangeDelegate {
        var finished = false
        var cancelled = false
        func willSpeakRange(range: NSRange) {}
        func finishSpeak(isCancel: Bool, speechString: String) {
            finished = true; cancelled = isCancel
        }
    }
    private let body = "静かな朝、町の図書館まで歩きました。窓から柔らかな光が差し込み、机には新しい本が並んでいます。今日は少し長い文章を読み、合成と再生を繰り返した後のメモリ使用量を確かめます。"

    private func prepare() async throws -> UInt32 {
        UserDefaults.standard.set(false, forKey: RealmUtil.UseCloudRealmKey)
        NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
        let dictionary = try XCTUnwrap(Bundle.main.path(forResource: "open_jtalk_dic_utf_8-1.11", ofType: nil))
        let core = VoicevoxCore.shared
        try await core.setUp(dictDirectoryPath: dictionary, voiceModelFilePaths: [VoicevoxTestVoiceModel.requirePath()])
        core.clearPrefetchCache()
        core.setDiskCacheContext(novelID: nil, chapterNumber: 1)
        // 他の実合成テストが残したロード済みモデルを基準値に混ぜない。
        let existing = await core.modelLifecycleSnapshot()
        if existing.loadedModels > 0 { _ = try await waitForUnload() }
        let styles = await core.styles
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        return try XCTUnwrap(styles.first?.styleId)
    }

    private func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        XCTAssertEqual(result, KERN_SUCCESS)
        return Double(info.phys_footprint) / 1048576
    }

    private func record(_ phase: String) async -> VoicevoxCore.ModelLifecycleSnapshot {
        let state = await VoicevoxCore.shared.modelLifecycleSnapshot()
        print("VOICEVOX_LIFETIME phase=\(phase) footprintMiB=\(footprint()) loads=\(state.loads) unloads=\(state.unloads) loaded=\(state.loadedModels) users=\(state.activeUses) cachedSeconds=\(VoicevoxCore.shared.cachedAudioSecondsForLogging()) generatedBlocks=\(VoicevoxCacheGenerator.shared.progress?.generatedBlockCount ?? -1) generationChapter=\(VoicevoxCacheGenerator.shared.progress?.chapterNumber ?? -1) generationPaused=\(VoicevoxCacheGenerator.shared.progress?.pauseReasonText ?? "none") uptime=\(ProcessInfo.processInfo.systemUptime)")
        return state
    }

    private func waitForUnload() async throws -> VoicevoxCore.ModelLifecycleSnapshot {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let state = await VoicevoxCore.shared.modelLifecycleSnapshot()
            if state.loadedModels == 0 && state.activeUses == 0 { return await record("idle_unloaded") }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTFail("停止後にモデルがアンロードされなかった")
        return await record("unload_timeout")
    }

    private func makeGenerationNovel(style: UInt32) -> String {
        let id = "voicevox-unload-test-" + UUID().uuidString
        RealmUtil.Write { realm in
            let speaker = RealmSpeakerSetting()
            speaker.name = id; speaker.type = "VOICEVOX"; speaker.voiceIdentifier = String(style)
            realm.add(speaker, update: .modified)
            let novel = RealmNovel()
            novel.novelID = id; novel.title = id; novel.defaultSpeakerID = id; novel.type = .UserCreated
            novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: id, chapterNumber: 20)
            realm.add(novel, update: .modified)
            for chapter in 1...20 {
                var story = Story()
                story.novelID = id; story.chapterNumber = chapter
                story.content = String(repeating: self.body, count: 4) + "生成の第\(chapter)章です。"
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
            }
        }
        return id
    }

    private func removeGenerationNovel(_ id: String) {
        VoicevoxCacheGenerator.shared.stop()
        VoicevoxDiskCacheStore.shared.remove(novelID: id)
        VoicevoxCacheGenerationState.shared.setEnabled(false, novelID: id)
        RealmUtil.Write { realm in
            RealmStoryBulk.RemoveAllStoryWith(realm: realm, novelID: id)
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: id) { realm.delete(novel) }
            if let speaker = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: id) { realm.delete(speaker) }
        }
    }

    func testOldPlaybackCannotAdvanceOrReloadAfterSwitchAndResume() async throws {
        let style = try await prepare()
        let core = VoicevoxCore.shared
        final class CountingSpeaker: VoicevoxSpeaker {
            var calls = 0
            override func Speech(text: String) { calls += 1 }
            override func Stop() {} // このテストの完了通知は下で手動配送する。
        }
        let blockSpeaker = StorySpeaker.shared.speaker
        blockSpeaker.StopSpeech()
        let oldDelegate = blockSpeaker.delegate
        let oldStoryID = StorySpeaker.shared.storyID
        let key = "VOICEVOX:\(style)"
        let oldEngine = blockSpeaker.speaker.speakerCache[key]
        let oldLeadMinutes = VoicevoxCacheLead.keepGeneratingBelowMinutes
        VoicevoxCacheLead.keepGeneratingBelowMinutes = 15
        let novelID = makeGenerationNovel(style: style)
        core.setDiskCacheContext(novelID: novelID, chapterNumber: 1)
        StorySpeaker.shared.storyID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 1)
        let engine = CountingSpeaker(styleId: style)
        blockSpeaker.speaker.speakerCache["VOICEVOX:\(style)"] = engine
        let settings = SpeakerSetting(type: "VOICEVOX", voiceIdentifier: String(style))
        let dialogue = SpeechSectionConfig(startText: "「", endText: "」",
            speakerSetting: SpeakerSetting(pitch: 1.1, type: "VOICEVOX", voiceIdentifier: String(style)))
        blockSpeaker.SetText(content: "最初の文章です。「次の文章です。」最後の文章です。", withMoreSplitTargets: ["。"],
            moreSplitMinimumLetterCount: 12, defaultSpeaker: settings,
            sectionConfigList: [dialogue], waitConfigList: [], speechModArray: [])
        let finished = Finished()
        blockSpeaker.delegate = finished
        defer {
            blockSpeaker.StopSpeech()
            blockSpeaker.delegate = oldDelegate
            StorySpeaker.shared.storyID = oldStoryID
            blockSpeaker.speaker.speakerCache[key] = oldEngine
            VoicevoxCacheLead.keepGeneratingBelowMinutes = oldLeadMinutes
            core.setDiskCacheContext(novelID: nil, chapterNumber: 1)
            removeGenerationNovel(novelID)
        }
        blockSpeaker.StartSpeech()
        let firstDeadline = Date().addingTimeInterval(5)
        while engine.calls < 1 && Date() < firstDeadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(engine.calls, 1)
        let oldIndex = blockSpeaker.currentBlockIndex
        try await core.suspendForEngineSwitch()
        try await core.resumeAfterEngineSwitch()
        VoicevoxCacheAutoGeneration.shared.evaluate()
        XCTAssertFalse(VoicevoxCacheGenerator.shared.isRunning, "古い読み上げから自動生成を起動しない")
        XCTAssertEqual(core.scheduler.pendingCount, 0)
        // 切り替え前に鳴らし始めた音声の完了が、再有効化後に遅れて届く場合。
        blockSpeaker.finishSpeak(isCancel: false, speechString: "最初の文章です。")
        XCTAssertFalse(blockSpeaker.isSpeaking)
        XCTAssertEqual(engine.calls, 1)
        XCTAssertEqual(blockSpeaker.currentBlockIndex, oldIndex)
        XCTAssertTrue(finished.cancelled)
        StorySpeaker.shared.finishSpeak(isCancel: true, speechString: "遅れて届いた古い完了通知")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(blockSpeaker.isSpeaking, "小説読み上げ側の自動再開も抑止する")
        XCTAssertEqual(engine.calls, 1)
        blockSpeaker.StartSpeech()
        let secondDeadline = Date().addingTimeInterval(5)
        while engine.calls < 2 && Date() < secondDeadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(engine.calls, 2, "新しく開始した読み上げは受け付ける")
        blockSpeaker.StopSpeech()
        try await core.suspendForEngineSwitch()
        try await core.resumeAfterEngineSwitch()
    }

    func testEngineSwitchDrainsNativeSynthesisAndRejectsStaleWorkUntilExplicitResume() async throws {
        let core = VoicevoxCore.shared
        let style = try await prepare()
        let initial = await record("switch_initial")
        let novelID = makeGenerationNovel(style: style)
        defer { removeGenerationNovel(novelID) }
        let oldSession = core.newSynthesisSession()
        let text = body + "切り替え前の合成です。"
        let baseline = footprint()
        let running = Task { try await core.synthesize(text: text, styleId: style, session: oldSession) }
        let deadline = Date().addingTimeInterval(20)
        while footprint() < baseline + 200 && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let during = footprint()
        XCTAssertGreaterThan(during, baseline + 200, "native合成でメモリを確保している最中に切り替える")
        XCTAssertEqual(core.scheduler.status(key: VoicevoxCore.cacheKey(text: text, styleId: style)), .inFlight)
        XCTAssertTrue(core.schedulePrefetch(blockIndex: 1, text: "取り消す先読みです。", styleId: style, session: oldSession))
        let pendingText = "取り消す事前生成です。"
        let pending = Task {
            try await core.synthesizeForBackgroundFill(text: pendingText, styleId: style,
                novelID: novelID, chapterNumber: 1, isPermanent: true, session: oldSession)
        }
        VoicevoxCacheGenerator.shared.start(novelID: novelID, mode: .manual)
        // actorへ入らずに予約状態を見るので、実行中C呼び出しの完了待ちにならない。
        let queuedDeadline = Date().addingTimeInterval(2)
        while core.scheduler.status(key: VoicevoxCore.cacheKey(text: pendingText, styleId: style)) == .notQueued,
              Date() < queuedDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let switchedAt = Date()
        try await core.suspendForEngineSwitch()
        let elapsed = Date().timeIntervalSince(switchedAt)
        let suspended = await record("switch_suspended")
        print("VOICEVOX_SWITCH elapsedSeconds=\(elapsed) beforeMiB=\(during) afterMiB=\(footprint())")
        XCTAssertLessThan(elapsed, VoicevoxModelLifetime.idleDelay)
        XCTAssertEqual(suspended.loadedModels, 0)
        XCTAssertEqual(suspended.activeUses, 0)
        XCTAssertFalse(core.isAcceptingSynthesisRequests)
        XCTAssertEqual(suspended.loads, initial.loads + 1)
        XCTAssertEqual(suspended.unloads, initial.unloads + 1)
        XCTAssertLessThan(footprint(), during - 150)
        _ = await running.result
        do { try await pending.value; XCTFail("待機中の事前生成は取り消す") }
        catch is CancellationError {} catch { XCTFail("unexpected: \(error)") }
        for _ in 0..<3 {
            XCTAssertFalse(core.schedulePrefetch(blockIndex: 2, text: "停止中の先読みです。", styleId: style))
            do { _ = try await core.synthesize(text: "停止中の発話です。", styleId: style); XCTFail("受付停止中") }
            catch is CancellationError {} catch { XCTFail("unexpected: \(error)") }
            VoicevoxCacheGenerator.shared.start(novelID: novelID, mode: .manual)
            VoicevoxCacheAutoGeneration.shared.evaluate()
            XCTAssertFalse(VoicevoxCacheGenerator.shared.isRunning)
        }
        try await Task.sleep(nanoseconds: 35_000_000_000)
        let stillSuspended = await record("switch_still_suspended")
        XCTAssertEqual(stillSuspended.loads, suspended.loads)
        XCTAssertEqual(stillSuspended.loadedModels, 0)
        try await core.resumeAfterEngineSwitch()
        // 古い生産者が遅れて届いても、新しく受付を開いた世代へ持ち越さない。
        XCTAssertFalse(core.schedulePrefetch(blockIndex: 2, text: "古い先読みです。", styleId: style, session: oldSession))
        do {
            try await core.synthesizeForBackgroundFill(text: "古い生成バッチです。", styleId: style,
                novelID: novelID, chapterNumber: 1, isPermanent: true, session: oldSession)
            XCTFail("古い生成バッチは再開後も拒否する")
        } catch is CancellationError {} catch { XCTFail("unexpected: \(error)") }
        let engine = AudibleSpeaker(styleId: style)
        let finished = Finished()
        engine.delegate = finished
        engine.performSpeech(text: "切り替え後に、もう一度読み上げます。")
        let playbackDeadline = Date().addingTimeInterval(90)
        while !finished.finished && Date() < playbackDeadline { try await Task.sleep(nanoseconds: 200_000_000) }
        XCTAssertTrue(finished.finished)
        XCTAssertFalse(finished.cancelled)
        let resumed = await record("switch_resumed_playback_finished")
        XCTAssertEqual(resumed.loads, suspended.loads + 1)
        XCTAssertEqual(resumed.unloads, suspended.unloads)
        XCTAssertEqual(resumed.loadedModels, 1, "通常終了では30秒の猶予を維持する")
        let idle = try await waitForUnload()
        XCTAssertEqual(idle.unloads, suspended.unloads + 1)
        engine.delegate = nil
    }

    func testPlaybackWithPrefetchAndFollowingGenerationUnloadsAfterStopAndResumes() async throws {
        let style = try await prepare()
        let initial = await record("initial")
        // 以前約1GiB残った入力を先に合成。停止後に同じ領域が実際に戻るか測る。
        for cycle in 1...4 {
            _ = try await VoicevoxCore.shared.synthesize(text: body + "計測は第\(cycle)回です。", styleId: style)
        }
        let before = footprint()
        _ = await record("long_warmed")
        let blockSpeaker = StorySpeaker.shared.speaker
        let oldDelegate = blockSpeaker.delegate
        let cacheKey = "VOICEVOX:\(style)"
        let oldEngine = blockSpeaker.speaker.speakerCache[cacheKey]
        let oldLeadMinutes = VoicevoxCacheLead.keepGeneratingBelowMinutes
        VoicevoxCacheLead.keepGeneratingBelowMinutes = 15
        let engine = AudibleSpeaker(styleId: style)
        blockSpeaker.speaker.speakerCache[cacheKey] = engine
        let settings = SpeakerSetting(rate: 0.25, type: "VOICEVOX", voiceIdentifier: String(style))
        let dialogue = SpeechSectionConfig(startText: "「", endText: "」",
            speakerSetting: SpeakerSetting(pitch: 1.1, rate: 0.25, type: "VOICEVOX", voiceIdentifier: String(style)))
        blockSpeaker.SetText(content: String(repeating: body + "「次の本を探します。」", count: 2),
            withMoreSplitTargets: ["。"], moreSplitMinimumLetterCount: 12,
            defaultSpeaker: settings, sectionConfigList: [dialogue], waitConfigList: [], speechModArray: [])
        let finished = Finished()
        blockSpeaker.delegate = finished
        let novelID = makeGenerationNovel(style: style)
        defer {
            blockSpeaker.StopSpeech()
            blockSpeaker.delegate = oldDelegate
            blockSpeaker.speaker.speakerCache[cacheKey] = oldEngine
            VoicevoxCacheLead.keepGeneratingBelowMinutes = oldLeadMinutes
            VoicevoxCore.shared.setDiskCacheContext(novelID: nil, chapterNumber: 1)
            removeGenerationNovel(novelID)
        }
        VoicevoxCore.shared.setDiskCacheContext(novelID: novelID, chapterNumber: 1)
        // 生成の実処理が進んだことを先に確認し、そのバッチを継続したまま再生を始める。
        VoicevoxCacheGenerator.shared.start(novelID: novelID, mode: .followingPlayback)
        let generationDeadline = Date().addingTimeInterval(60)
        while (VoicevoxCacheGenerator.shared.progress?.generatedBlockCount ?? 0) == 0 && Date() < generationDeadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertGreaterThan(VoicevoxCacheGenerator.shared.progress?.generatedBlockCount ?? 0, 0)
        blockSpeaker.StartSpeech()
        VoicevoxCacheAutoGeneration.shared.evaluate()
        let started = Date()
        var sawPrefetch = false
        repeat {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            sawPrefetch = sawPrefetch || VoicevoxCore.shared.cachedAudioSecondsForLogging() > 0
            let state = await record("playing_and_generating")
            XCTAssertEqual(state.loads, initial.loads + 1)
            XCTAssertEqual(state.unloads, initial.unloads)
            XCTAssertEqual(state.loadedModels, 1)
        } while Date().timeIntervalSince(started) < VoicevoxModelLifetime.idleDelay + 5
        XCTAssertTrue(blockSpeaker.isSpeaking)
        XCTAssertTrue(VoicevoxCacheGenerator.shared.isRunning)
        XCTAssertGreaterThan(VoicevoxCacheGenerator.shared.progress?.generatedBlockCount ?? 0, 0)
        XCTAssertGreaterThan(blockSpeaker.willSpeakRangeCallCount, 0)
        XCTAssertTrue(sawPrefetch, "実際に先読みが完成したこと")
        // 追従生成は一時領域。作成済み(永続領域)だけのsummaryでは数えない。
        let storedBytes = (1...20).reduce(0) {
            $0 + VoicevoxDiskCacheStore.shared.summaryInAnyArea(novelID: novelID, chapterNumber: $1).byteCount
        }
        XCTAssertGreaterThan(storedBytes, 0)
        blockSpeaker.StopSpeech()
        VoicevoxCacheGenerator.shared.stopIfFollowingPlayback(reason: "アンロード統合テスト")
        _ = await record("stopped")
        let unloaded = try await waitForUnload()
        XCTAssertEqual(unloaded.unloads, initial.unloads + 1)
        XCTAssertGreaterThan(VoicevoxCore.shared.cachedAudioSecondsForLogging(), 0, "モデル解放後も先読み音声は残す")
        XCTAssertLessThan(footprint(), before - 200, "長文合成で確保した領域が解放されること")

        VoicevoxCacheLead.keepGeneratingBelowMinutes = 0
        finished.finished = false; finished.cancelled = false
        blockSpeaker.SetText(content: "モデルを解放した後、もう一度読み上げます。", withMoreSplitTargets: ["。"],
            moreSplitMinimumLetterCount: 12, defaultSpeaker: settings,
            sectionConfigList: [], waitConfigList: [], speechModArray: [])
        blockSpeaker.StartSpeech()
        let deadline = Date().addingTimeInterval(90)
        while !finished.finished && Date() < deadline { try await Task.sleep(nanoseconds: 200_000_000) }
        XCTAssertTrue(finished.finished); XCTAssertFalse(finished.cancelled)
        let resumed = await record("resumed_and_finished")
        XCTAssertEqual(resumed.loads, initial.loads + 2)
        XCTAssertEqual(resumed.unloads, initial.unloads + 1)
        _ = try await waitForUnload()
    }

    func testManualGenerationKeepsModelAcrossBlocksAndReleasesAfterStop() async throws {
        let style = try await prepare()
        let initial = await record("manual_initial")
        let novelID = makeGenerationNovel(style: style)
        defer { removeGenerationNovel(novelID) }
        VoicevoxCacheGenerator.shared.start(novelID: novelID, mode: .manual)
        let started = Date()
        repeat {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let state = await record("manual_generating")
            XCTAssertLessThanOrEqual(state.loads, initial.loads + 1)
            XCTAssertEqual(state.unloads, initial.unloads)
        } while Date().timeIntervalSince(started) < VoicevoxModelLifetime.idleDelay + 5
        XCTAssertTrue(VoicevoxCacheGenerator.shared.isRunning)
        XCTAssertGreaterThan(VoicevoxDiskCacheStore.shared.summary(novelID: novelID).byteCount, 0)
        let running = await record("manual_before_stop")
        XCTAssertEqual(running.loads, initial.loads + 1)
        VoicevoxCacheGenerator.shared.stop()
        let idle = try await waitForUnload()
        XCTAssertEqual(idle.unloads, initial.unloads + 1)
        XCTAssertGreaterThan(VoicevoxDiskCacheStore.shared.summary(novelID: novelID).byteCount, 0)
    }
}
#endif
