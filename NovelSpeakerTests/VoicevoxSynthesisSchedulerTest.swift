//
//  VoicevoxSynthesisSchedulerTest.swift
//  NovelSpeakerTests
//
//  一本の待ち行列(VoicevoxSynthesisScheduler)の性質のテスト。
//
//  合成の実体を偽物(SchedulerFakeEngine)に差し替えてあるので、
//  VOICEVOX 本体もモデルも要らず、数秒で回る。
//  以前は「端末が冷えるのを待って30分読み上げさせ、貯金が伸びるかを見る」
//  以外に確かめる手段が無かった性質を、ここで固定する。
//

import XCTest
@testable import NovelSpeaker

/// 指名された本文の合成を、開けてもらえるまで進めない偽エンジン。
/// 「合成中にほかの要求が積まれた」という状況を作るために使う。
private final class SchedulerFakeEngine: VoicevoxSynthesisEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var startedTexts: [String] = []
    private var gatedTexts: Set<String> = []
    private var gateContinuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    /// 本文 → 投げるエラー(登録されていれば合成失敗にする)。
    private var errors: [String: Error] = [:]
    /// 出来事の記録(合成の開始と、置き場所への書き込みの順序を確かめる用)。
    let events = SchedulerEventLog()

    var synthesizedTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return startedTexts
    }

    func gate(text: String) {
        lock.lock()
        gatedTexts.insert(text)
        lock.unlock()
    }

    func openGate(text: String) {
        lock.lock()
        gatedTexts.remove(text)
        let waiting = gateContinuations.removeValue(forKey: text) ?? []
        lock.unlock()
        for continuation in waiting {
            continuation.resume()
        }
    }

    func fail(text: String, with error: Error) {
        lock.lock()
        errors[text] = error
        lock.unlock()
    }

    func synthesizeBlock(text: String, styleId: UInt32) async throws -> Data {
        lock.lock()
        startedTexts.append(text)
        let isGated = gatedTexts.contains(text)
        lock.unlock()
        events.append("synthesize:\(text)")
        if isGated {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if gatedTexts.contains(text) {
                    gateContinuations[text, default: []].append(continuation)
                    lock.unlock()
                } else {
                    lock.unlock()
                    continuation.resume()
                }
            }
        }
        lock.lock()
        let error = errors[text]
        lock.unlock()
        if let error = error { throw error }
        return Data("wav:\(text)".utf8)
    }
}

private final class SchedulerEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var eventsUnsafe: [String] = []
    func append(_ event: String) {
        lock.lock()
        eventsUnsafe.append(event)
        lock.unlock()
    }
    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return eventsUnsafe
    }
}

/// メモリ層・ディスク層の偽物。
private final class SchedulerFakeStores: @unchecked Sendable {
    private let lock = NSLock()
    private var memoryUnsafe: [String: Data] = [:]
    private var diskUnsafe: [String: Data] = [:]
    private var diskDestinationsUnsafe: [String: VoicevoxSynthesisScheduler.FillDestination?] = [:]
    private var unobservedErrorsUnsafe: [String] = []
    let events: SchedulerEventLog

    init(events: SchedulerEventLog = SchedulerEventLog()) {
        self.events = events
    }

    func putMemory(key: String, data: Data) {
        lock.lock(); memoryUnsafe[key] = data; lock.unlock()
    }
    func putDisk(key: String, data: Data) {
        lock.lock(); diskUnsafe[key] = data; lock.unlock()
    }
    var disk: [String: Data] {
        lock.lock(); defer { lock.unlock() }
        return diskUnsafe
    }
    var memory: [String: Data] {
        lock.lock(); defer { lock.unlock() }
        return memoryUnsafe
    }
    func diskDestination(key: String) -> VoicevoxSynthesisScheduler.FillDestination? {
        lock.lock(); defer { lock.unlock() }
        return diskDestinationsUnsafe[key] ?? nil
    }
    var unobservedErrors: [String] {
        lock.lock(); defer { lock.unlock() }
        return unobservedErrorsUnsafe
    }

    var storage: VoicevoxSynthesisScheduler.Storage {
        return VoicevoxSynthesisScheduler.Storage(
            peekMemory: { [self] request in
                lock.lock(); defer { lock.unlock() }
                return memoryUnsafe[request.key]
            },
            peekDisk: { [self] request, _ in
                lock.lock(); defer { lock.unlock() }
                return diskUnsafe[request.key]
            },
            isOnDisk: { [self] request, _ in
                lock.lock(); defer { lock.unlock() }
                return diskUnsafe[request.key] != nil
            },
            storeToMemory: { [self] request, data in
                lock.lock(); memoryUnsafe[request.key] = data; lock.unlock()
                events.append("storeMemory:\(request.text)")
            },
            storeToDisk: { [self] request, data, destination in
                lock.lock()
                diskUnsafe[request.key] = data
                diskDestinationsUnsafe[request.key] = destination
                lock.unlock()
                events.append("storeDisk:\(request.text)")
            },
            onUnobservedError: { [self] request, _ in
                lock.lock(); unobservedErrorsUnsafe.append(request.text); lock.unlock()
            }
        )
    }
}

class VoicevoxSynthesisSchedulerTest: XCTestCase {

    private var engine: SchedulerFakeEngine!
    private var stores: SchedulerFakeStores!
    private var scheduler: VoicevoxSynthesisScheduler!

    override func setUp() {
        super.setUp()
        engine = SchedulerFakeEngine()
        stores = SchedulerFakeStores(events: engine.events)
        scheduler = VoicevoxSynthesisScheduler(engine: engine, storage: stores.storage)
    }

    private func request(_ text: String, styleId: UInt32 = 1) -> VoicevoxSynthesisScheduler.Request {
        return VoicevoxSynthesisScheduler.Request(key: "\(styleId)::\(text)", text: text, styleId: styleId)
    }

    private func fillDestination(isPermanent: Bool = false) -> VoicevoxSynthesisScheduler.FillDestination {
        return VoicevoxSynthesisScheduler.FillDestination(novelID: "novel", chapterNumber: 1, isPermanent: isPermanent)
    }

    /// 条件が満たされるまで待つ(最大2秒)。
    private func waitUntil(timeoutSeconds: Double = 2.0, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - 二度合成しない(今回の不具合そのもの)

    /// 同じ鍵を、先行合成・再生・作り足しの三者が同時に欲しがっても、合成は一度だけ。
    /// 実機では二者(先行合成と作り足し)の重なりだけで合成の半分が二度手間になっていた。
    func testSameKeyRequestedByEveryoneIsSynthesizedOnlyOnce() async throws {
        // 別の合成で行列を塞いでおいて、その間に三者から同じ鍵を要求する。
        engine.gate(text: "先客")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("先客"))
        await waitUntil { self.engine.synthesizedTexts.contains("先客") }

        let target = request("三者が欲しがるブロック")
        scheduler.enqueuePrefetch(blockIndex: 1, request: target)
        async let playbackData = scheduler.resultForPlayback(request: target)
        async let fillData = scheduler.resultForBackgroundFill(request: target, destination: fillDestination())
        await waitUntil { self.scheduler.isPlaybackSynthesisPending }

        engine.openGate(text: "先客")
        let playback = try await playbackData
        let fill = try await fillData

        XCTAssertEqual(playback, Data("wav:三者が欲しがるブロック".utf8))
        XCTAssertEqual(fill, playback, "全員が同じ結果を受け取るべき")
        XCTAssertEqual(engine.synthesizedTexts.filter { $0 == "三者が欲しがるブロック" }.count, 1,
                       "同じ鍵は一度しか合成されないべき")
    }

    /// 合成が終わった物は、ディスクへ置き終わるまでが1件の仕事。
    /// 次の合成は、その置き終わりの後にしか始まらない
    /// (「作り終えたのに、まだどこにも見えない」隙があると、その間に
    ///  同じ物がもう一度作られる。実機で合成の3〜5割がこれだった)。
    func testDiskStoreCompletesBeforeNextSynthesisStarts() async throws {
        engine.gate(text: "一つ目")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("一つ目"))
        await waitUntil { self.engine.synthesizedTexts.contains("一つ目") }
        scheduler.enqueuePrefetch(blockIndex: 1, request: request("二つ目"))
        engine.openGate(text: "一つ目")

        await waitUntil { self.stores.disk.keys.contains(self.request("二つ目").key) }
        let events = engine.events.events
        guard let storeFirst = events.firstIndex(of: "storeDisk:一つ目"),
              let synthesizeSecond = events.firstIndex(of: "synthesize:二つ目") else {
            XCTFail("期待した出来事が記録されていない: \(events)")
            return
        }
        XCTAssertLessThan(storeFirst, synthesizeSecond,
                          "一つ目の置き終わりの前に二つ目の合成が始まっている(見えない隙がある): \(events)")
    }

    // MARK: - 優先度

    /// 再生が今必要としている物は、積まれている先行合成・作り足しを追い越す。
    func testPlaybackRequestOvertakesPrefetchAndFill() async throws {
        engine.gate(text: "先客")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("先客"))
        await waitUntil { self.engine.synthesizedTexts.contains("先客") }

        scheduler.enqueuePrefetch(blockIndex: 5, request: request("先行合成"))
        async let fillData = scheduler.resultForBackgroundFill(request: request("作り足し"), destination: fillDestination())
        async let playbackData = scheduler.resultForPlayback(request: request("再生が今欲しい物"))
        await waitUntil { self.scheduler.isPlaybackSynthesisPending }

        engine.openGate(text: "先客")
        _ = try await playbackData
        _ = try await fillData
        await waitUntil { self.engine.synthesizedTexts.count >= 4 }

        let order = engine.synthesizedTexts
        XCTAssertEqual(order.first, "先客")
        XCTAssertEqual(order.dropFirst().first, "再生が今欲しい物", "再生に必要な物が最優先のはず: \(order)")
        XCTAssertEqual(order.last, "作り足し", "作り足しは最後のはず: \(order)")
    }

    /// 先行合成は再生位置に近い物から合成される。
    func testPrefetchRunsInBlockIndexOrder() async throws {
        engine.gate(text: "先客")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("先客"))
        await waitUntil { self.engine.synthesizedTexts.contains("先客") }

        scheduler.enqueuePrefetch(blockIndex: 7, request: request("遠い"))
        scheduler.enqueuePrefetch(blockIndex: 3, request: request("近い"))
        scheduler.enqueuePrefetch(blockIndex: 5, request: request("中くらい"))
        engine.openGate(text: "先客")

        await waitUntil { self.engine.synthesizedTexts.count >= 4 }
        XCTAssertEqual(engine.synthesizedTexts, ["先客", "近い", "中くらい", "遠い"])
    }

    /// 追い越された(もう再生されない)先行合成の予約は捨てられる。
    func testOvertakenPrefetchIsDropped() async throws {
        engine.gate(text: "先客")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("先客"))
        await waitUntil { self.engine.synthesizedTexts.contains("先客") }

        scheduler.enqueuePrefetch(blockIndex: 3, request: request("追い越される"))
        scheduler.enqueuePrefetch(blockIndex: 8, request: request("まだ先"))
        scheduler.setPlaybackIndex(5)
        engine.openGate(text: "先客")

        await waitUntil { self.engine.synthesizedTexts.contains("まだ先") }
        XCTAssertFalse(engine.synthesizedTexts.contains("追い越される"),
                       "再生位置より手前の予約は合成されないべき")
    }

    // MARK: - 積み過ぎ防止

    /// 先行合成の予約は上限を超えて積めず、超える時は一番遠い物が押し出される。
    func testPrefetchCapacityEvictsFarthest() async throws {
        engine.gate(text: "先客")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("先客"))
        await waitUntil { self.engine.synthesizedTexts.contains("先客") }

        // 上限は4。5件目に近い物を積むと、一番遠い物が押し出される。
        scheduler.enqueuePrefetch(blockIndex: 11, request: request("ブロック11"))
        scheduler.enqueuePrefetch(blockIndex: 12, request: request("ブロック12"))
        scheduler.enqueuePrefetch(blockIndex: 13, request: request("ブロック13"))
        scheduler.enqueuePrefetch(blockIndex: 14, request: request("ブロック14"))
        let enqueuedNear = scheduler.enqueuePrefetch(blockIndex: 10, request: request("ブロック10"))
        let rejectedFar = scheduler.enqueuePrefetch(blockIndex: 15, request: request("ブロック15"))
        XCTAssertTrue(enqueuedNear, "近い予約は(遠い物を押し出して)積めるべき")
        XCTAssertFalse(rejectedFar, "満杯の時、一番遠い予約より更に遠い物は積めないべき")

        engine.openGate(text: "先客")
        await waitUntil { self.engine.synthesizedTexts.count >= 5 }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(engine.synthesizedTexts.contains("ブロック14"), "一番遠い物が押し出されるべき")
        XCTAssertFalse(engine.synthesizedTexts.contains("ブロック15"))
        XCTAssertTrue(engine.synthesizedTexts.contains("ブロック10"))
    }

    // MARK: - 既に出来ている物は作らない

    /// 既にディスクに置いてある物の先行合成予約は、合成せずに済ませる。
    func testPrefetchForBlockAlreadyOnDiskDoesNotSynthesize() async throws {
        let target = request("もう出来ている")
        stores.putDisk(key: target.key, data: Data("encoded".utf8))
        scheduler.enqueuePrefetch(blockIndex: 1, request: target)
        // 何も合成されない事の確認なので、少しだけ待ってから見る。
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(engine.synthesizedTexts, [])
    }

    /// メモリに完成品がある物への作り足し要求は、合成せずディスクへ写すだけで済ませる。
    func testFillRequestForMemoryCachedBlockCopiesWithoutSynthesis() async throws {
        let target = request("メモリにある")
        stores.putMemory(key: target.key, data: Data("wav".utf8))
        let data = try await scheduler.resultForBackgroundFill(request: target, destination: fillDestination(isPermanent: true))
        XCTAssertEqual(data, Data("wav".utf8))
        XCTAssertEqual(engine.synthesizedTexts, [], "合成し直す必要は無いはず")
        await waitUntil { self.stores.disk[target.key] != nil }
        XCTAssertEqual(stores.disk[target.key], Data("wav".utf8), "メモリの完成品がディスクへ写されるべき")
        XCTAssertEqual(stores.diskDestination(key: target.key)?.isPermanent, true, "頼まれた置き場所(作成済み)に置くべき")
    }

    // MARK: - キャンセル

    /// 停止/シークでは、待機中の先行合成の予約だけが捨てられる。
    /// 完成を待っている人(再生・作り足し)は見捨てられない。
    func testCancelPendingPrefetchKeepsWaiters() async throws {
        engine.gate(text: "先客")
        scheduler.enqueuePrefetch(blockIndex: 0, request: request("先客"))
        await waitUntil { self.engine.synthesizedTexts.contains("先客") }

        scheduler.enqueuePrefetch(blockIndex: 5, request: request("捨てられる予約"))
        async let fillData = scheduler.resultForBackgroundFill(request: request("待ち人あり"), destination: fillDestination())
        await waitUntil { self.scheduler.pendingCount >= 2 }
        scheduler.cancelPendingPrefetch()
        engine.openGate(text: "先客")

        let fill = try await fillData
        XCTAssertEqual(fill, Data("wav:待ち人あり".utf8), "待ち人のいる要求はキャンセル後も完成するべき")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(engine.synthesizedTexts.contains("捨てられる予約"))
    }

    /// キャンセルを跨いで完成した古い先行合成は、メモリ層には置かれない。
    func testPrefetchResultAcrossCancelIsNotStoredToMemory() async throws {
        engine.gate(text: "古い先行合成")
        scheduler.enqueuePrefetch(blockIndex: 1, request: request("古い先行合成"))
        await waitUntil { self.engine.synthesizedTexts.contains("古い先行合成") }
        scheduler.cancelPendingPrefetch()
        engine.openGate(text: "古い先行合成")
        await waitUntil { self.stores.disk[self.request("古い先行合成").key] != nil }
        XCTAssertNil(stores.memory[request("古い先行合成").key],
                     "停止/シークを跨いだ完成品は新しい本文には場所塞ぎでしかない")
    }

    // MARK: - 失敗と状態

    /// 合成の失敗は、待っている全員へエラーとして届く。
    func testFailureIsDeliveredToWaiters() async throws {
        struct FakeError: Error {}
        engine.fail(text: "失敗する", with: FakeError())
        do {
            _ = try await scheduler.resultForPlayback(request: request("失敗する"))
            XCTFail("エラーが投げられるべき")
        } catch {
            XCTAssertTrue(error is FakeError)
        }
    }

    /// 誰も待っていない先行合成の失敗は、報告先へ届く(黙って消えない)。
    func testUnobservedFailureIsReported() async throws {
        struct FakeError: Error {}
        engine.fail(text: "静かに失敗する", with: FakeError())
        scheduler.enqueuePrefetch(blockIndex: 1, request: request("静かに失敗する"))
        await waitUntil { self.stores.unobservedErrors.isEmpty == false }
        XCTAssertEqual(stores.unobservedErrors, ["静かに失敗する"])
    }

    /// 再生が待っている間は isPlaybackSynthesisPending が true(固着検出が頼りにする)。
    func testIsPlaybackSynthesisPendingDuringPlaybackRequest() async throws {
        engine.gate(text: "再生が待つ物")
        XCTAssertFalse(scheduler.isPlaybackSynthesisPending)
        async let data = scheduler.resultForPlayback(request: request("再生が待つ物"))
        await waitUntil { self.scheduler.isPlaybackSynthesisPending }
        XCTAssertTrue(scheduler.isPlaybackSynthesisPending)
        engine.openGate(text: "再生が待つ物")
        _ = try await data
        XCTAssertFalse(scheduler.isPlaybackSynthesisPending)
    }

    /// 先行合成の完成品はメモリ層に置かれ、ディスク層にも積まれる。
    func testPrefetchResultIsStoredToMemoryAndDisk() async throws {
        let target = request("普通の先行合成")
        scheduler.enqueuePrefetch(blockIndex: 1, request: target)
        await waitUntil { self.stores.memory[target.key] != nil && self.stores.disk[target.key] != nil }
        XCTAssertEqual(stores.memory[target.key], Data("wav:普通の先行合成".utf8))
        XCTAssertEqual(stores.disk[target.key], Data("wav:普通の先行合成".utf8))
    }
}
