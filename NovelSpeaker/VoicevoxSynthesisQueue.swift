//
//  VoicevoxSynthesisQueue.swift
//  NovelSpeaker
//
//  VOICEVOX の先行合成における「次に何を合成すべきか」の帳簿。
//  合成そのものは行わない(重いC呼び出しは VoicevoxCore の actor 側の仕事)。
//
//  なぜ actor から切り離すのか:
//  従来はこの帳簿処理も VoicevoxCore の actor 隔離の内側にあった。voicevox の合成は
//  1本あたり12秒前後かかる同期的なC呼び出しで、その間 actor は占有される。結果として
//  「次に再生するブロックを最優先で予約する」という数マイクロ秒で終わるはずの帳簿処理が
//  合成の完了待ちに巻き込まれ、実機トレースでは予約が登録されるまで19秒かかっていた。
//  優先度をどう調整しても、この待ちの内側では効かない。
//  そこでこのクラスはロック(NSLock)だけで完結させ、合成中でも予約・優先度変更・
//  キャンセルが待たされずに反映されるようにする。
//
//  優先度は「再生順で手前にあるほど高い」という一点で決まる(blockIndex の小ささ)。
//  以前のような urgent フラグや投入順の直列鎖は不要になる。
//

import Foundation

final class VoicevoxSynthesisQueue {

    struct Request: Equatable {
        let blockIndex: Int
        let text: String
        let styleId: UInt32
        /// cancelAll() を跨いだ古い合成結果を見分けるための世代番号。
        fileprivate let generation: Int

        fileprivate var key: String { return VoicevoxSynthesisQueue.key(text: text, styleId: styleId) }
    }

    /// キャッシュのキー(メモリ・ディスクと同一。鍵は一つだけにする)。
    static func key(text: String, styleId: UInt32) -> String {
        return VoicevoxDiskCacheStore.key(text: text, styleId: styleId)
    }

    private let lock = NSLock()
    private var pending: [String: Request] = [:]
    private var inFlight: [String: Request] = [:]
    private var playbackIndex = Int.min
    private var generation = 0

    /// 待機中の予約として保持できる本数の上限。
    /// 積み過ぎると、手前のブロックが後ろのバックログに埋もれて再生に間に合わなくなる
    /// (実機で30件以上積まれ、予約から完了まで218秒かかる状態になっていた)。
    private let capacity: Int

    /// 既に合成済みかどうかの判定(VoicevoxCore のキャッシュ参照を注入する)。
    /// テストでは VOICEVOX 実体なしで差し替えられる。
    private let isAlreadySynthesized: (String, UInt32) -> Bool

    init(capacity: Int = 4, isAlreadySynthesized: @escaping (String, UInt32) -> Bool) {
        self.capacity = max(1, capacity)
        self.isAlreadySynthesized = isAlreadySynthesized
    }

    /// 現在の再生位置を伝える。これより手前の予約は「追い越された」ものとして捨てる。
    func setPlaybackIndex(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        playbackIndex = index
        for (key, request) in pending where request.blockIndex < index {
            pending.removeValue(forKey: key)
        }
    }

    /// 先行合成の予約を積む。
    /// - Returns: 実際に積まれたら true。既に合成済み/予約済み、再生位置を過ぎている、
    ///            上限が埋まっていて自分より手前の予約しか無い場合は false。
    @discardableResult
    func enqueue(blockIndex: Int, text: String, styleId: UInt32) -> Bool {
        // キャッシュ参照はロックの外で行う(VoicevoxCore 側が別のロックを持つため、
        // ロックを入れ子にしないでおく)。
        if isAlreadySynthesized(text, styleId) { return false }
        let key = Self.key(text: text, styleId: styleId)

        lock.lock()
        defer { lock.unlock() }
        if blockIndex < playbackIndex { return false }
        if inFlight[key] != nil { return false }
        if let existing = pending[key] {
            // 同じ内容が、より手前のブロックとしても必要になった場合は優先度を上げる。
            if blockIndex < existing.blockIndex {
                pending[key] = Request(blockIndex: blockIndex, text: text, styleId: styleId, generation: generation)
            }
            return false
        }
        if pending.count >= capacity {
            guard let farthest = pending.values.max(by: { $0.blockIndex < $1.blockIndex }),
                  blockIndex < farthest.blockIndex else {
                // 新しい予約の方が遠いなら、手前の予約を押し出してまで積む価値はない。
                return false
            }
            pending.removeValue(forKey: farthest.key)
        }
        pending[key] = Request(blockIndex: blockIndex, text: text, styleId: styleId, generation: generation)
        return true
    }

    /// 次に合成すべき(=再生位置に最も近い)予約を取り出して合成中にする。
    func takeNext() -> Request? {
        lock.lock()
        defer { lock.unlock() }
        guard let next = pending.values.min(by: { $0.blockIndex < $1.blockIndex }) else { return nil }
        pending.removeValue(forKey: next.key)
        inFlight[next.key] = next
        return next
    }

    /// 合成の完了(成功・失敗を問わず)を報告する。
    func complete(_ request: Request) {
        lock.lock()
        defer { lock.unlock() }
        if inFlight[request.key]?.generation == request.generation {
            inFlight.removeValue(forKey: request.key)
        }
    }

    enum ClaimResult {
        /// そもそも先行合成の対象から漏れていた(取りこぼしの不具合)。
        case notQueued
        /// 待機中だった。予約は取り消したので、呼び出し側がその場で合成してよい。
        case pending
        /// ワーカーが今まさに合成中。呼び出し側は自分で合成せず、その完成を待つべき。
        case inFlight
    }

    /// 再生側が cache MISS した時に、待機中の同じ予約を取り消して自分でその場合成するための入り口。
    /// ワーカーが同じ物を重ねて合成しないようにする。
    ///
    /// 合成中(inFlight)だった場合に呼び出し側が自分でも合成すると、同じ物を二重に合成して
    /// CPU 予算を食い合い、どちらも進まなくなる(実機で、同じブロックに対する
    /// 「分割合成」が二重に走り、互いの予算待ちで1ブロックに4分以上かかっていた)。
    @discardableResult
    func claimForImmediateSynthesis(text: String, styleId: UInt32) -> ClaimResult {
        let key = Self.key(text: text, styleId: styleId)
        lock.lock()
        defer { lock.unlock() }
        if inFlight[key] != nil { return .inFlight }
        if pending.removeValue(forKey: key) != nil { return .pending }
        return .notQueued
    }

    /// 待機中の予約を全て破棄する(読み上げ停止・シーク等)。
    /// 実行中のC呼び出し1本はプリエンプトできないが、その結果は isStale() で用済みと判定できる。
    func cancelAll() {
        lock.lock()
        defer { lock.unlock() }
        pending.removeAll()
        inFlight.removeAll()
        generation += 1
    }

    /// cancelAll() より前に取り出した(=もう不要な)合成かどうか。
    /// 取り出した1件を、これから重いC呼び出しに入れてよいか。
    ///
    /// 積んだ時点で未合成でも、順番を待っている間に別の経路
    /// (読み上げの裏で走っている作り足し)が同じブロックを作り終えている事がある。
    /// 作り足しは再生位置から前へ進むので、待ち行列とは必ず重なる。
    /// 積む時にしか確かめていなかったため、実機では合成の**ちょうど半分**が
    /// 「作り終えてから、既にあったと分かる」二度手間になっていた。
    func isStillNeeded(_ request: Request) -> Bool {
        // キャッシュ参照はロックの外で行う(enqueue と同じ理由)。
        if isAlreadySynthesized(request.text, request.styleId) { return false }
        return isStale(request) == false
    }

    func isStale(_ request: Request) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return request.generation != generation
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func isPending(text: String, styleId: UInt32) -> Bool {
        let key = Self.key(text: text, styleId: styleId)
        lock.lock()
        defer { lock.unlock() }
        return pending[key] != nil
    }

    func isInFlight(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return inFlight[key] != nil
    }

    func isInFlight(text: String, styleId: UInt32) -> Bool {
        let key = Self.key(text: text, styleId: styleId)
        lock.lock()
        defer { lock.unlock() }
        return inFlight[key] != nil
    }
}

/// 「今この音声を誰かが作っている」を、再生側と裏の作り足しの間で共有する帳簿。
///
/// なぜ要るのか:
/// 合成そのものは actor で直列化されているので、二つが同時にC呼び出しへ入る事は無い。
/// それでも二度手間は起きる。**作り終えてからディスクに置き終わるまでに間がある**ためで、
/// その隙に相手が「まだ無い」と判断してもう一度作ってしまう。
/// 実機ログでは、作り足し側の確認を直した後も合成の3〜5割が
/// 「再生側の二度手間」として残っていた(84本中42本など)。
///
/// 出来上がった物(メモリ・ディスク)だけを見ていては塞げない。
/// **これから作る物**も見えるようにする必要がある。
final class VoicevoxSynthesisInProgress {

    enum Side {
        /// 再生側(先行合成・再生時の合成)。
        case playback
        /// 読み上げの裏で走っている作り足し。
        case generator
    }

    static let shared = VoicevoxSynthesisInProgress()

    private let lock = NSLock()
    /// 同じ鍵に対して「合成中」と「書き出し中」が重なるので、数で持つ。
    private var entries: [String: (side: Side, count: Int)] = [:]

    /// 作り始める(または書き出し始める)。
    func begin(key: String, side: Side) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = entries[key] {
            entries[key] = (existing.side, existing.count + 1)
        } else {
            entries[key] = (side, 1)
        }
    }

    /// 終わった事を伝える。
    func end(key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let existing = entries[key] else { return }
        if existing.count <= 1 {
            entries.removeValue(forKey: key)
        } else {
            entries[key] = (existing.side, existing.count - 1)
        }
    }

    /// その鍵を、指定した側が今作っているか。
    func isInProgress(key: String, by side: Side) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]?.side == side
    }

    func isInProgress(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[key] != nil
    }

    /// 出来上がるまで待つ。待ちきれなければ false(その時は自分で作るしかない)。
    ///
    /// 待つ方が速い。合成は直列なので、自分でも作ると
    /// 「相手の完了を待ってから自分の合成」= 二回ぶん待つ事になる。
    func waitForCompletion(key: String, timeoutSeconds: Double, pollSeconds: Double = 0.1) async -> Bool {
        let maxCount = max(1, Int(timeoutSeconds / pollSeconds))
        for _ in 0..<maxCount {
            if isInProgress(key: key) == false { return true }
            try? await Task.sleep(nanoseconds: UInt64(pollSeconds * 1_000_000_000))
        }
        return false
    }

    /// テスト用。
    func removeAllForTesting() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
