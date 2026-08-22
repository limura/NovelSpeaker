//
//  VoicevoxSynthesisQueueTest.swift
//  NovelSpeakerTests
//
//  先行合成の待ち行列(VoicevoxSynthesisQueue)のテスト。
//
//  背景: 従来は「予約する」という帳簿処理まで VoicevoxCore の actor 隔離の内側にあり、
//  actor が1本12秒前後かかる同期的なC呼び出しで占有されている間は、予約の登録も
//  キャンセルも順番待ちさせられていた(実機トレースで、次に再生するブロックの確保を
//  決めてから実際に予約が登録されるまで19秒かかっていた)。
//  そのため優先度をどう調整しても効かず、無音が解消しなかった。
//
//  そこで「次に何を合成すべきか」の帳簿だけを actor の外(ロックのみ)に切り出す。
//  このテストが守るのはその中核の性質:
//    - 再生位置が進んだら、次に合成すべき対象が入れ替わる
//    - 合成中(in flight)でも、予約・キャンセルが即座に反映される
//

import XCTest
@testable import NovelSpeaker

class VoicevoxSynthesisQueueTest: XCTestCase {

    private func makeQueue(capacity: Int = 8, synthesized: Set<String> = []) -> VoicevoxSynthesisQueue {
        return VoicevoxSynthesisQueue(capacity: capacity) { text, styleId in
            return synthesized.contains(VoicevoxSynthesisQueue.key(text: text, styleId: styleId))
        }
    }

    // 積んだ順ではなく「再生位置に近い順」に取り出される事。
    // 実機では投入順の直列鎖にしていたため、後から必要になったブロックが
    // 遠い先のブロックのバックログの後ろに回されて間に合わなかった。
    func testTakeNextReturnsNearestBlockFirst() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 12, text: "遠い", styleId: 3)
        queue.enqueue(blockIndex: 5, text: "近い", styleId: 3)
        queue.enqueue(blockIndex: 8, text: "中くらい", styleId: 3)

        XCTAssertEqual(queue.takeNext()?.text, "近い")
        XCTAssertEqual(queue.takeNext()?.text, "中くらい")
        XCTAssertEqual(queue.takeNext()?.text, "遠い")
        XCTAssertNil(queue.takeNext())
    }

    // 同じ物を二度渡さない(ワーカーが複数居ても二重合成にならない)。
    func testTakeNextDoesNotHandOutTheSameRequestTwice() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "A", styleId: 3)
        XCTAssertEqual(queue.takeNext()?.text, "A")
        XCTAssertNil(queue.takeNext(), "合成中の物をもう一度渡してはいけない")
    }

    // 再生位置が進んだら、次に合成すべき対象が入れ替わる事。
    // 併せて、追い越されてしまった(=再生位置より手前の)予約は捨てられる事。
    func testPlaybackAdvanceChangesNextTarget() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 3, text: "3番", styleId: 3)
        queue.enqueue(blockIndex: 4, text: "4番", styleId: 3)
        queue.enqueue(blockIndex: 5, text: "5番", styleId: 3)

        queue.setPlaybackIndex(4)

        XCTAssertEqual(queue.takeNext()?.text, "4番", "再生位置が進んだら次の対象が変わるはず")
        XCTAssertEqual(queue.pendingCount, 1, "追い越された3番は捨てられるはず")
        XCTAssertEqual(queue.takeNext()?.text, "5番")
    }

    // 既に再生位置を過ぎているブロックは、そもそも受け付けない。
    func testEnqueueOfAlreadyPassedBlockIsRejected() {
        let queue = makeQueue()
        queue.setPlaybackIndex(10)
        XCTAssertFalse(queue.enqueue(blockIndex: 9, text: "過ぎた", styleId: 3))
        XCTAssertEqual(queue.pendingCount, 0)
    }

    // 合成中(重いC呼び出しの最中に相当)でも、新しい予約が即座に反映される事。
    // これが従来 actor 隔離のせいで19秒待たされていた部分。
    func testEnqueueIsReflectedImmediatelyWhileSynthesisIsInFlight() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 20, text: "長い段落", styleId: 3)
        let inFlight = queue.takeNext()
        XCTAssertEqual(inFlight?.text, "長い段落")

        // 合成中に、もっと手前のブロックが必要になった。
        XCTAssertTrue(queue.enqueue(blockIndex: 1, text: "次に再生する", styleId: 3))
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(queue.takeNext()?.text, "次に再生する",
                       "合成の完了を待たずに次の対象として取り出せるはず")
    }

    // 合成中でもキャンセルが即座に反映される事。
    // 完了報告は「もう不要になった結果」として弾かれる(帳簿が汚れない)。
    func testCancelAllIsReflectedImmediatelyWhileSynthesisIsInFlight() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "合成中", styleId: 3)
        queue.enqueue(blockIndex: 2, text: "待機中", styleId: 3)
        guard let inFlight = queue.takeNext() else { return XCTFail("取り出せるはず") }

        queue.cancelAll()

        XCTAssertEqual(queue.pendingCount, 0, "待機中の予約は即座に消えるはず")
        XCTAssertTrue(queue.isStale(inFlight), "キャンセル前に取り出した合成は用済み扱いになるはず")
        XCTAssertNil(queue.takeNext())
    }

    // 同じ内容(styleId とテキストが同じ)を重ねて予約しても二重には積まれない事。
    // ただし、より手前のブロックとして必要になった場合は優先度が上がる事。
    func testDuplicateEnqueueIsDedupedAndNearerIndexWins() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 30, text: "はい", styleId: 3)
        queue.enqueue(blockIndex: 12, text: "うん", styleId: 3)
        queue.enqueue(blockIndex: 2, text: "はい", styleId: 3)

        XCTAssertEqual(queue.pendingCount, 2, "同じ内容は1件にまとまるはず")
        XCTAssertEqual(queue.takeNext()?.text, "はい", "より手前の位置で必要になった方が優先されるはず")
    }

    // styleId が違えば別物として扱われる事(話者ごとに合成結果が違うため)。
    func testSameTextWithDifferentStyleIsSeparateRequest() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "同じ文", styleId: 3)
        queue.enqueue(blockIndex: 2, text: "同じ文", styleId: 8)
        XCTAssertEqual(queue.pendingCount, 2)
    }

    // 既に合成済みの物は積まない(無駄撃ちしない)。
    func testAlreadySynthesizedIsNotEnqueued() {
        let queue = makeQueue(synthesized: [VoicevoxSynthesisQueue.key(text: "合成済み", styleId: 3)])
        XCTAssertFalse(queue.enqueue(blockIndex: 1, text: "合成済み", styleId: 3))
        XCTAssertTrue(queue.enqueue(blockIndex: 2, text: "未合成", styleId: 3))
        XCTAssertEqual(queue.pendingCount, 1)
    }

    // 上限を超えたら、最も遠い(必要になるのが最も先の)予約から捨てる事。
    // 手前の予約が押し出されると、そのまま再生時の無音になる。
    func testCapacityDropsTheFarthestRequest() {
        let queue = makeQueue(capacity: 3)
        queue.enqueue(blockIndex: 1, text: "A", styleId: 3)
        queue.enqueue(blockIndex: 2, text: "B", styleId: 3)
        queue.enqueue(blockIndex: 3, text: "C", styleId: 3)
        XCTAssertTrue(queue.enqueue(blockIndex: 2, text: "割り込み", styleId: 3))

        XCTAssertEqual(queue.pendingCount, 3)
        XCTAssertFalse(queue.isPending(text: "C", styleId: 3), "最も遠いCが押し出されるはず")
        XCTAssertTrue(queue.isPending(text: "割り込み", styleId: 3))
    }

    // 上限が埋まっていて、新しい予約の方が全部より遠い場合は、単に受け付けない
    // (手前の予約を押し出してはいけない)。
    func testCapacityRejectsAFartherNewRequest() {
        let queue = makeQueue(capacity: 2)
        queue.enqueue(blockIndex: 1, text: "A", styleId: 3)
        queue.enqueue(blockIndex: 2, text: "B", styleId: 3)
        XCTAssertFalse(queue.enqueue(blockIndex: 9, text: "遠い", styleId: 3))
        XCTAssertTrue(queue.isPending(text: "A", styleId: 3))
        XCTAssertTrue(queue.isPending(text: "B", styleId: 3))
    }

    // 完了報告で帳簿から消える事(消えないと、以後ずっと合成中扱いで再合成できない)。
    func testCompleteClearsInFlight() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "A", styleId: 3)
        guard let request = queue.takeNext() else { return XCTFail("取り出せるはず") }
        XCTAssertTrue(queue.isInFlight(text: "A", styleId: 3))
        queue.complete(request)
        XCTAssertFalse(queue.isInFlight(text: "A", styleId: 3))
        XCTAssertEqual(queue.pendingCount, 0)
    }

    // 合成に失敗した物は帳簿から外れ、必要なら積み直せる事。
    func testFailedRequestCanBeEnqueuedAgain() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "A", styleId: 3)
        guard let request = queue.takeNext() else { return XCTFail("取り出せるはず") }
        queue.complete(request)
        XCTAssertTrue(queue.enqueue(blockIndex: 1, text: "A", styleId: 3), "失敗後は積み直せるはず")
    }

    // 合成中の物は「予約済み」として扱われ、二重に積まれない事。
    func testInFlightRequestIsNotEnqueuedAgain() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "A", styleId: 3)
        _ = queue.takeNext()
        XCTAssertFalse(queue.enqueue(blockIndex: 1, text: "A", styleId: 3))
    }

    // MISS 時に再生側が「自分の分を最優先で合成する」ために、
    // 待機中の予約を横取り(取り消して自分で合成)できる事。
    func testClaimRemovesPendingSoTheWorkerDoesNotDuplicateIt() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 5, text: "今すぐ要る", styleId: 3)
        XCTAssertEqual(queue.claimForImmediateSynthesis(text: "今すぐ要る", styleId: 3), .pending,
                       "待機中だった事が分かるはず")
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(queue.takeNext(), "ワーカーが同じ物を重ねて合成してはいけない")
    }

    // 予約されていなかった物の横取りは「未予約だった」と分かる事
    // (先行合成の取りこぼしなのか、単に間に合わなかっただけなのかの切り分けに使う)。
    func testClaimReportsWhenItWasNotQueued() {
        let queue = makeQueue()
        XCTAssertEqual(queue.claimForImmediateSynthesis(text: "未予約", styleId: 3), .notQueued)
    }

    // 合成中の物を横取りしようとした時は「合成中」と分かる事。
    // ここで自分でも合成すると同じ物を二重に合成してしまい、CPU予算を食い合って
    // どちらも進まなくなる(実機で1ブロックに4分以上かかる原因になっていた)。
    func testClaimReportsInFlightSoTheCallerCanWaitInsteadOfDuplicating() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "合成中", styleId: 3)
        _ = queue.takeNext()
        XCTAssertEqual(queue.claimForImmediateSynthesis(text: "合成中", styleId: 3), .inFlight)
        XCTAssertTrue(queue.isInFlight(text: "合成中", styleId: 3), "横取りしても合成中のままであるべき")
    }

    // 待っている間に別経路(読み上げの裏で走る作り足し)が同じブロックを作り終えたら、
    // 重いC呼び出しには入らない事。
    //
    // 実機ログでは、合成の**ちょうど半分**が「作り終えてから既にあったと分かる」
    // 二度手間になっていた(132本中66本、108本中54本…)。積む時にしか
    // 確かめていなかったため、順番待ちの間に作られた物を見落としていた。
    func testIsStillNeededBecomesFalseWhenAnotherPathFinishedItWhileWaiting() {
        var synthesized: Set<String> = []
        let queue = VoicevoxSynthesisQueue(capacity: 8) { text, styleId in
            return synthesized.contains(VoicevoxSynthesisQueue.key(text: text, styleId: styleId))
        }
        queue.enqueue(blockIndex: 1, text: "重なるブロック", styleId: 3)
        guard let request = queue.takeNext() else {
            XCTFail("取り出せるはず"); return
        }
        XCTAssertTrue(queue.isStillNeeded(request), "まだ誰も作っていないなら合成してよい")

        // 順番待ちの間に、裏の作り足しが同じブロックを作り終えた。
        synthesized.insert(VoicevoxSynthesisQueue.key(text: "重なるブロック", styleId: 3))
        XCTAssertFalse(queue.isStillNeeded(request), "既に出来ている物をもう一度作ってはいけない")
    }

    // 停止/シークで用済みになった物も、同じ入口で弾かれる事。
    func testIsStillNeededBecomesFalseAfterCancelAll() {
        let queue = makeQueue()
        queue.enqueue(blockIndex: 1, text: "捨てられる", styleId: 3)
        guard let request = queue.takeNext() else {
            XCTFail("取り出せるはず"); return
        }
        queue.cancelAll()
        XCTAssertFalse(queue.isStillNeeded(request), "世代が変わった予約は合成しない")
    }

    // ロックで守られている事の最低限の確認(複数スレッドから同時に叩いても壊れない)。
    func testConcurrentAccessDoesNotCorruptTheQueue() {
        let queue = makeQueue(capacity: 64)
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            queue.enqueue(blockIndex: i, text: "block\(i)", styleId: 3)
            if i % 3 == 0 {
                if let request = queue.takeNext() {
                    queue.complete(request)
                }
            }
            if i % 50 == 0 {
                queue.setPlaybackIndex(i)
            }
        }
        XCTAssertLessThanOrEqual(queue.pendingCount, 64)
    }
}
