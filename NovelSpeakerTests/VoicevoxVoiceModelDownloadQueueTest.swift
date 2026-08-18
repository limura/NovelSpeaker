//
//  VoicevoxVoiceModelDownloadQueueTest.swift
//  NovelSpeakerTests
//

import XCTest
@testable import NovelSpeaker

class VoicevoxVoiceModelDownloadQueueTest: XCTestCase {

    private func request(_ id: String, byteSize: Int64 = 58_000_000,
                         styles: Set<UInt32> = []) -> VoicevoxVoiceModelDownloadRequest {
        return VoicevoxVoiceModelDownloadRequest(
            modelID: id, url: URL(string: "https://example.com/\(id).vvm")!,
            byteSize: byteSize, expectedStyleIds: styles)
    }

    // MARK: - 取得してよいかの判断

    // ★モバイル通信では既定で取得しない事。
    // 60MB級を勝手に落とすと、従量制の人には実害が出る。
    func testCellularIsBlockedByDefault() {
        XCTAssertEqual(
            VoicevoxVoiceModelDownloadPolicy.blocker(
                byteSize: 58_000_000, isAlreadyStored: false,
                isOnCellular: true, allowsCellular: false, freeBytes: 10_000_000_000),
            .needsWiFi)
    }

    // 明示的に許可されていればモバイル通信でも取得する。
    func testCellularIsAllowedWhenPermitted() {
        XCTAssertNil(
            VoicevoxVoiceModelDownloadPolicy.blocker(
                byteSize: 58_000_000, isAlreadyStored: false,
                isOnCellular: true, allowsCellular: true, freeBytes: 10_000_000_000))
    }

    // ★空き容量を使い切らない事。
    // ファイルの大きさぶんだけでなく、余白を残して判断する。
    func testNotEnoughSpaceIsBlocked() {
        let size: Int64 = 58_000_000
        // ぎりぎり足りない(ファイル分はあるが余白が無い)
        let blocker = VoicevoxVoiceModelDownloadPolicy.blocker(
            byteSize: size, isAlreadyStored: false, isOnCellular: false,
            allowsCellular: false, freeBytes: size + 100)
        guard case .notEnoughSpace(let required, let free)? = blocker else {
            return XCTFail("空き容量不足として弾かれていない: \(String(describing: blocker))")
        }
        XCTAssertGreaterThan(required, size, "ファイルの大きさぴったりで判断してはいけない")
        XCTAssertEqual(free, size + 100)
    }

    func testEnoughSpaceIsAllowed() {
        XCTAssertNil(
            VoicevoxVoiceModelDownloadPolicy.blocker(
                byteSize: 58_000_000, isAlreadyStored: false, isOnCellular: false,
                allowsCellular: false,
                freeBytes: 58_000_000 + VoicevoxVoiceModelDownloadPolicy.minimumFreeBytesAfterDownload))
    }

    // 既に持っている物は落とし直さない(通信の無駄)。
    func testAlreadyStoredIsBlocked() {
        XCTAssertEqual(
            VoicevoxVoiceModelDownloadPolicy.blocker(
                byteSize: 58_000_000, isAlreadyStored: true, isOnCellular: false,
                allowsCellular: false, freeBytes: 10_000_000_000),
            .alreadyStored)
    }

    // MARK: - 待ち行列

    // ★同時に走るのは1本だけである事。
    // 60MB級を並行して落とすと、どれも中途半端に終わって
    // 「何も使えるようにならない」時間が長くなる。
    func testOnlyOneDownloadRunsAtATime() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0"))
        queue.enqueue(request("5"))

        XCTAssertEqual(queue.startNext()?.modelID, "0")
        XCTAssertNil(queue.startNext(), "1本走っている間は次を始めない")
        XCTAssertEqual(queue.activeModelID, "0")
        XCTAssertEqual(queue.waitingModelIDs, ["5"])

        queue.finish(modelID: "0")
        XCTAssertEqual(queue.startNext()?.modelID, "5")
    }

    // 積んだ順に取得する。
    func testQueueIsFirstInFirstOut() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        for id in ["3", "1", "2"] { queue.enqueue(request(id)) }
        var order: [String] = []
        while let next = queue.startNext() {
            order.append(next.modelID)
            queue.finish(modelID: next.modelID)
        }
        XCTAssertEqual(order, ["3", "1", "2"])
    }

    // 同じ物を二重に積まない。
    func testDuplicateEnqueueIsIgnored() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        XCTAssertTrue(queue.enqueue(request("0")))
        XCTAssertFalse(queue.enqueue(request("0")), "待ち行列にいる物は積み直さない")
        XCTAssertEqual(queue.waitingModelIDs, ["0"])

        _ = queue.startNext()
        XCTAssertFalse(queue.enqueue(request("0")), "走っている物は積み直さない")
        XCTAssertTrue(queue.waitingModelIDs.isEmpty)
    }

    // 待っている物も走っている物も取り消せる。
    func testCancel() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0"))
        queue.enqueue(request("5"))
        _ = queue.startNext()

        XCTAssertFalse(queue.cancel(modelID: "5"), "待っているだけの物の取り消しは false")
        XCTAssertTrue(queue.waitingModelIDs.isEmpty)

        XCTAssertTrue(queue.cancel(modelID: "0"), "走っている物の取り消しは true(実タスクも止める必要がある)")
        XCTAssertNil(queue.activeModelID)
        XCTAssertTrue(queue.isEmpty)
    }

    func testCancelAll() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0"))
        queue.enqueue(request("5"))
        _ = queue.startNext()
        XCTAssertEqual(queue.cancelAll(), "0")
        XCTAssertTrue(queue.isEmpty)
        XCTAssertTrue(queue.allStates().isEmpty)
    }

    // MARK: - 進捗

    func testProgress() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0", byteSize: 100))
        XCTAssertEqual(queue.state(ofModelID: "0"), .queued)
        XCTAssertEqual(queue.state(ofModelID: "0")?.fraction, 0)

        _ = queue.startNext()
        queue.update(modelID: "0", receivedBytes: 25, totalBytes: 100)
        XCTAssertEqual(queue.state(ofModelID: "0")?.fraction, 0.25)

        queue.finish(modelID: "0")
        XCTAssertNil(queue.state(ofModelID: "0"), "終わった物の進捗は残さない")
    }

    // ★取り消した後に遅れて届く進捗で、状態が復活しない事。
    // URLSession の通知は非同期に届くので、これが無いと
    // 「取り消したのに進捗が動き続ける」ように見える。
    func testProgressAfterCancelIsIgnored() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0", byteSize: 100))
        _ = queue.startNext()
        _ = queue.cancel(modelID: "0")

        queue.update(modelID: "0", receivedBytes: 50, totalBytes: 100)
        XCTAssertNil(queue.state(ofModelID: "0"))
        XCTAssertNil(queue.activeModelID)
    }

    // 全体の総量が分からない場合でも、積んだ時の大きさで進捗を出せる。
    func testProgressFallsBackToKnownByteSize() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0", byteSize: 200))
        _ = queue.startNext()
        queue.update(modelID: "0", receivedBytes: 100, totalBytes: -1)
        XCTAssertEqual(queue.state(ofModelID: "0")?.fraction, 0.5)
    }

    // 失敗は理由付きで残り、次の取得は妨げない。
    func testFailureIsRecordedAndDoesNotBlockOthers() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0"))
        queue.enqueue(request("5"))
        _ = queue.startNext()
        queue.fail(modelID: "0", reason: "通信できませんでした")

        XCTAssertEqual(queue.state(ofModelID: "0"), .failed("通信できませんでした"))
        XCTAssertNil(queue.activeModelID)
        XCTAssertEqual(queue.startNext()?.modelID, "5", "失敗が次を止めてはいけない")

        queue.clearFailure(modelID: "0")
        XCTAssertNil(queue.state(ofModelID: "0"))
    }

    // 失敗した物を積み直せる事(「もう一度」を押せる)。
    func testFailedRequestCanBeEnqueuedAgain() {
        let queue = VoicevoxVoiceModelDownloadQueue()
        queue.enqueue(request("0"))
        _ = queue.startNext()
        queue.fail(modelID: "0", reason: "だめでした")
        XCTAssertTrue(queue.enqueue(request("0")))
        XCTAssertEqual(queue.startNext()?.modelID, "0")
    }
}
