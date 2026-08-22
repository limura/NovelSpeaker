//
//  VoicevoxRepeatedSynthesisDetector.swift
//  NovelSpeaker
//
//  「同じ本文を、この読み上げの中で二度合成していないか」を見張る。
//
//  なぜ要るのか:
//  音声の作り置きは、時期の違う三つの仕組みが積み重なってできている
//  (メモリに貯める → 事前に作ってファイルに置く → 読み上げ中に一時ファイルへ貯める)。
//  「次に何を作るか」を決める者が二人(先行合成の待ち行列と、裏の作り足し)居るため、
//  互いの作りかけが見えていないと、同じ物を二度作ってしまう。
//
//  実機ログでは**合成のちょうど半分**が二度手間になっていた時期がある。
//  CPUの半分を捨てていたので、作っても作っても貯金が増えず、無音が19〜28%出ていた。
//  にもかかわらず、この症状は「端末が冷えた状態から30分読み上げさせて、
//  貯金が増えるかを見る」という手間のかかる実験でしか気づけなかった。
//
//  この二度手間には、条件に依らない単純な言い方がある:
//
//    **同じ鍵の音声を、一回の読み上げの中で二度合成したら、それは必ず無駄撃ちである。**
//
//  熱の状態にも端末の速さにも依らない。だから、実験ではなく**その場で**数えられる。
//  ここはその一点だけを見張る。合成の入口(performSynthesizeWithinBudget)は
//  一箇所しか無いので、そこを通る鍵を覚えておけばよい。
//
//  なお「利用者が巻き戻して、キャッシュから溢れた所をもう一度作った」も
//  ここでは二度目として数える。これは無駄撃ちではないが、
//  読み上げ中に何度も起こるものではないので、割合が上がったら異常と見てよい。
//

import Foundation

final class VoicevoxRepeatedSynthesisDetector {

    static let shared = VoicevoxRepeatedSynthesisDetector()

    /// 覚えておく鍵の数。長い小説でも数十分ぶんに相当する。
    /// 際限なく持つとメモリを食うので、古い物から捨てる。
    static let capacity = 2048

    private let lock = NSLock()
    private var seen = Set<String>()
    private var order: [String] = []
    private var totalCount = 0
    private var repeatedCount = 0

    private init() {}

    /// これから1本合成する事を伝える。
    /// - Returns: 同じ鍵を既に合成していたら true(=二度目)。
    @discardableResult
    func noteSynthesisStarting(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        totalCount += 1
        if seen.contains(key) {
            repeatedCount += 1
            return true
        }
        seen.insert(key)
        order.append(key)
        if order.count > Self.capacity {
            let removed = order.removeFirst()
            seen.remove(removed)
        }
        return false
    }

    /// 読み上げを止めた時などに数え直す。
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        seen.removeAll()
        order.removeAll()
        totalCount = 0
        repeatedCount = 0
    }

    /// これまでの合計(合成した本数, そのうち二度目だった本数)。
    var counts: (total: Int, repeated: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (totalCount, repeatedCount)
    }

    /// 二度目の割合。見張る値はこれ一つでよい。
    ///
    /// 正常なら 0 に近い。0.1 を超えていたら、
    /// 「作った物が相手から見えていない」類の不具合が起きていると考えてよい。
    var repeatedRatio: Double {
        let (total, repeated) = counts
        guard total > 0 else { return 0 }
        return Double(repeated) / Double(total)
    }

    /// この割合を超えたら異常とみなす。
    /// 巻き戻しでの作り直しが混ざるので、0 ちょうどにはしない。
    static let unhealthyRatio: Double = 0.1

    /// 仕組みが壊れていないか。
    /// - Parameter minimumCount: これだけ合成していないと判断しない(最初の数本では揺れるため)。
    func isHealthy(minimumCount: Int = 20) -> Bool {
        let (total, _) = counts
        guard total >= minimumCount else { return true }
        return repeatedRatio < Self.unhealthyRatio
    }
}
