//
//  VoicevoxWavCacheTest.swift
//  NovelSpeakerTests
//
//  先行合成した音声(WAV)を保持するキャッシュのテスト。
//
//  背景: 実機(iPhone 17 Pro Max / 前景・AC接続・スレッド数自動)で、性能的には
//  完全に足りている(無音率0.8%、再生時HIT率96.6%、必要CPU率207%に対して292%出せる)
//  にも関わらず、数分に一度だけ無音が出ていた。
//  ログを追うと「未再生の貯金」が 233秒 → 146 → 116 → 77 → 30 → 2.4秒 と
//  単調に減り続け、0になった所で無音が発生していた。この間キャッシュの合計は
//  332〜348秒で一定、つまり容量上限(16MB ≒ 349秒)に張り付いていた。
//
//  原因は追い出しの順序。合成は再生順に進むので「挿入が最も古いもの」は
//  「一番先に再生するはずのもの」であり、それを捨てていた。用意できていたのに
//  再生する直前に消える、という形で 再生MISS(未予約) になっていた。
//  背面バッテリーでは合成が遅くて貯金が0秒のままなので表面化せず、
//  性能が足りている時にだけ出る不具合だった。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxWavCacheTest: XCTestCase {

    private func makeData(bytes: Int) -> Data {
        return Data(repeating: 0, count: bytes)
    }

    // 入れた物が取り出せる、という最低限の性質。
    func testStoreAndPeek() {
        let cache = VoicevoxWavCache(entryCapacity: 8, totalByteLimit: 1024)
        cache.store(key: "a", data: makeData(bytes: 10))
        XCTAssertEqual(cache.peek(key: "a")?.count, 10)
        XCTAssertNil(cache.peek(key: "b"))
    }

    // 再生で使い終わった物から先に追い出す事。
    //
    // これが無いと、合成が再生順に進む以上「最も古い＝次に再生する物」を捨ててしまう。
    // 実機ではこれで、用意できていたはずのブロックが再生直前に消えていた。
    func testEvictsAlreadyPlayedEntriesFirst() {
        let cache = VoicevoxWavCache(entryCapacity: 3, totalByteLimit: 10_000)
        cache.store(key: "再生済み", data: makeData(bytes: 100))
        cache.store(key: "次に再生", data: makeData(bytes: 100))
        cache.store(key: "その次", data: makeData(bytes: 100))
        cache.markPlayed(key: "再生済み")

        cache.store(key: "新入り", data: makeData(bytes: 100))

        XCTAssertNil(cache.peek(key: "再生済み"), "再生済みの物が最初に捨てられるべき")
        XCTAssertNotNil(cache.peek(key: "次に再生"), "まだ再生していない物を捨ててはいけない")
        XCTAssertNotNil(cache.peek(key: "その次"))
        XCTAssertNotNil(cache.peek(key: "新入り"))
    }

    // 再生済みが無ければ、やむを得ず古い物から捨てる(容量は守る必要があるため)。
    func testFallsBackToOldestWhenNothingHasBeenPlayed() {
        let cache = VoicevoxWavCache(entryCapacity: 2, totalByteLimit: 10_000)
        cache.store(key: "古い", data: makeData(bytes: 100))
        cache.store(key: "新しい", data: makeData(bytes: 100))
        cache.store(key: "最新", data: makeData(bytes: 100))
        XCTAssertNil(cache.peek(key: "古い"))
        XCTAssertNotNil(cache.peek(key: "最新"))
    }

    // 合計バイト数の上限でも、再生済みから先に捨てる事。
    // 実機で効いていたのはこちら(16MB上限)だった。
    func testTotalByteLimitAlsoEvictsPlayedEntriesFirst() {
        let cache = VoicevoxWavCache(entryCapacity: 100, totalByteLimit: 300)
        cache.store(key: "再生済み", data: makeData(bytes: 100))
        cache.store(key: "未再生1", data: makeData(bytes: 100))
        cache.store(key: "未再生2", data: makeData(bytes: 100))
        cache.markPlayed(key: "再生済み")

        cache.store(key: "新入り", data: makeData(bytes: 100))

        XCTAssertNil(cache.peek(key: "再生済み"))
        XCTAssertNotNil(cache.peek(key: "未再生1"))
        XCTAssertNotNil(cache.peek(key: "未再生2"))
        XCTAssertLessThanOrEqual(cache.totalByteCount, 300)
    }

    // 再生でヒットしても内容は残る事(同じ文字列が再登場した時に再利用するため)。
    // 「使い終わった」という印を付けるだけで、消しはしない。
    func testMarkPlayedKeepsTheEntryUsable() {
        let cache = VoicevoxWavCache(entryCapacity: 8, totalByteLimit: 10_000)
        cache.store(key: "相槌", data: makeData(bytes: 10))
        cache.markPlayed(key: "相槌")
        XCTAssertNotNil(cache.peek(key: "相槌"), "印を付けただけで消してはいけない")
    }

    // 一度再生した物が再び先行合成された場合、印は消えて「未再生」に戻り、
    // かつ「新しく入れた物」として扱われる事(また必要になったという事なので)。
    func testStoringAgainClearsThePlayedMarkAndRefreshesTheOrder() {
        let cache = VoicevoxWavCache(entryCapacity: 2, totalByteLimit: 10_000)
        cache.store(key: "A", data: makeData(bytes: 100))
        cache.store(key: "B", data: makeData(bytes: 100))
        cache.markPlayed(key: "A")
        cache.store(key: "A", data: makeData(bytes: 100)) // 再登場して合成し直された

        cache.store(key: "C", data: makeData(bytes: 100))

        XCTAssertNotNil(cache.peek(key: "A"), "合成し直した物は未再生かつ新しい物として扱うべき")
        XCTAssertNil(cache.peek(key: "B"), "最も古い未再生のBが捨てられるべき")
    }

    // 上限を超える大きさの物を1つ入れても、それ自体は保持する
    // (捨ててしまうと永久に合成し直しになる)。
    func testKeepsASingleEntryEvenIfItExceedsTheLimit() {
        let cache = VoicevoxWavCache(entryCapacity: 8, totalByteLimit: 100)
        cache.store(key: "巨大", data: makeData(bytes: 500))
        XCTAssertNotNil(cache.peek(key: "巨大"))
    }

    func testClearRemovesEverything() {
        let cache = VoicevoxWavCache(entryCapacity: 8, totalByteLimit: 10_000)
        cache.store(key: "A", data: makeData(bytes: 10))
        cache.clear()
        XCTAssertNil(cache.peek(key: "A"))
        XCTAssertEqual(cache.totalByteCount, 0)
    }

    // 複数スレッドから同時に叩いても壊れない事。
    func testConcurrentAccessIsSafe() {
        let cache = VoicevoxWavCache(entryCapacity: 32, totalByteLimit: 100_000)
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            cache.store(key: "key\(i)", data: self.makeData(bytes: 100))
            _ = cache.peek(key: "key\(i / 2)")
            if i % 3 == 0 { cache.markPlayed(key: "key\(i)") }
        }
        XCTAssertLessThanOrEqual(cache.totalByteCount, 100_000)
    }
}
