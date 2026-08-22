//
//  VoicevoxSynthesisScheduler.swift
//  NovelSpeaker
//
//  「次に何を合成するか」を決める者を一人にするための、一本の待ち行列。
//
//  以前は決定者が二人いた。先行合成の待ち行列(再生位置の少し先を埋める)と、
//  裏の作り足し(再生位置から小説の最後までを埋める)である。二人は同じ場所
//  (再生位置の直前)を別々の判断で埋めようとし、互いの作りかけが見えないため、
//  実機では合成のちょうど半分が「作り終えてから、既にあったと分かる」
//  二度手間になっていた(CPUの半分を捨てていた)。
//
//  ここでは全ての合成要求を一本の行列に積む。同じ鍵は行列に一つしか入らないので、
//  二度合成は**設計上できない**。「相手の作りかけが見えているか」を人間が
//  気にする必要も、進行中の帳簿(旧 VoicevoxSynthesisInProgress)も要らなくなる。
//
//  優先度は三段。
//   1. 再生が今必要としている物(待たせた時間がそのまま無音になる)
//   2. 先行合成(再生位置に近い物ほど先)
//   3. 作り足し(積まれた順)
//
//  合成の実体(VOICEVOX の C 呼び出し)は VoicevoxSynthesisEngine の向こう側にあり、
//  テストでは偽物に差し替えられる。置き場所(メモリ/ディスク)の読み書きも
//  クロージャで注入するので、このファイルは帳簿の理屈だけでできている。
//

import Foundation

/// 合成の実体を差し替えるための口。
///
/// 本物は VoicevoxCore(CPU予算・分割・スレッド数の調整込み)。
/// テストでは、C 呼び出しをせずに呼び出し履歴だけ記録する偽物を与える。
protocol VoicevoxSynthesisEngine: Sendable {
    /// 1ブロックぶんを合成して WAV を返す。
    func synthesizeBlock(text: String, styleId: UInt32) async throws -> Data
}

final class VoicevoxSynthesisScheduler: @unchecked Sendable {

    struct Request: Equatable, Sendable {
        /// キャッシュの鍵(メモリ・ディスク共通)。呼び出し側が計算して渡す。
        let key: String
        let text: String
        let styleId: UInt32
    }

    /// 作り足しの1件が持つ「どこへ置くか」。
    ///
    /// 再生に伴う合成の置き場所は再生状況(diskCacheContext)から決まるが、
    /// 作り足しは再生していない話も作るので、要求自身が置き場所を運ぶ必要がある。
    struct FillDestination: Equatable, Sendable {
        let novelID: String
        let chapterNumber: Int
        /// 利用者が明示的に「作って」と言った分(作成済みとして残す)か、
        /// 読み上げ中の自動の作り足し(一時分。聴き終わったら消えてよい)か。
        let isPermanent: Bool
    }

    enum KeyStatus {
        case notQueued
        case pending
        case inFlight
    }

    /// 置き場所の読み書き。VoicevoxCore が実体(VoicevoxAudioProvider 等)を繋ぐ。
    struct Storage: Sendable {
        /// メモリ層にあれば WAV を返す。
        let peekMemory: @Sendable (Request) -> Data?
        /// ディスク層にあれば(圧縮された)音声を返す。
        /// 作り足しの要求には置き場所(再生中とは別の話の事がある)が付いてくる。
        let peekDisk: @Sendable (Request, FillDestination?) -> Data?
        /// ディスク層にあるか(音声そのものは読まない)。
        let isOnDisk: @Sendable (Request, FillDestination?) -> Bool
        /// 先行合成の完成品をメモリ層へ置く。
        let storeToMemory: @Sendable (Request, Data) -> Void
        /// 完成品をディスク層へ置く(置くかどうか・どの区画かの判断も含めて任せる)。
        /// FillDestination が付いていればその場所へ、無ければ再生状況から決める。
        let storeToDisk: @Sendable (Request, Data, FillDestination?) -> Void
        /// 誰も待っていない合成が失敗した時の報告先(待っている人がいればエラーで返す)。
        let onUnobservedError: @Sendable (Request, Error) -> Void
    }

    private let engine: VoicevoxSynthesisEngine
    private let storage: Storage

    /// 待機中の先行合成として溜めておける本数。
    ///
    /// 積み過ぎると、手前のブロックが後ろのバックログに埋もれて完了までの時間が伸びる。
    /// 実機では一度に30件以上が積まれ、予約から完了まで218秒かかる状態になっていた
    /// (その間ずっと「未再生の貯金=0秒」で無音)。積むより先に手前から順に
    /// 完成させる方が、再生には遥かに有利。
    private let prefetchCapacity: Int

    init(engine: VoicevoxSynthesisEngine, storage: Storage, prefetchCapacity: Int = 4) {
        self.engine = engine
        self.storage = storage
        self.prefetchCapacity = max(1, prefetchCapacity)
    }

    // MARK: - 行列の中身

    private final class Entry {
        let request: Request
        /// 先行合成としての優先度(再生位置からの近さ)。nil なら作り足しのみ。
        var blockIndex: Int?
        /// 再生が今この音声を待っているか(最優先)。
        var isNeededForPlaybackNow = false
        /// 先行合成として積まれたか(完成したらメモリ層にも置く)。
        var isPrefetch = false
        /// 作り足しとしての置き場所(付いていれば、完成品を必ずディスクへ置く)。
        var fillDestination: FillDestination?
        /// 作り足し同士の順序(積まれた順)。
        var fillOrder = Int.max
        /// 完成(または失敗)を待っている人たち。全員に同じ結果を渡す。
        var waiters: [CheckedContinuation<Data, Error>] = []
        var isInFlight = false
        /// cancelAll() を跨いだ古い合成の完成品をメモリ層に置かないための世代番号。
        let generation: Int

        init(request: Request, generation: Int) {
            self.request = request
            self.generation = generation
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var playbackIndex = Int.min
    private var generation = 0
    private var nextFillOrder = 0
    private var isWorkerRunning = false

    // MARK: - 積む

    /// 先行合成の予約を積む(積むだけで、完成は待たない)。
    /// - Returns: 実際に積まれたら true。既に予約済み・再生位置を過ぎている・
    ///            上限が埋まっていて自分より手前の予約しか無い場合は false。
    @discardableResult
    func enqueuePrefetch(blockIndex: Int, request: Request) -> Bool {
        lock.lock()
        let enqueued = enqueuePrefetchLocked(blockIndex: blockIndex, request: request)
        lock.unlock()
        if enqueued { startWorkerIfNeeded() }
        return enqueued
    }

    private func enqueuePrefetchLocked(blockIndex: Int, request: Request) -> Bool {
        if blockIndex < playbackIndex { return false }
        if let existing = entries[request.key] {
            // 同じ内容が、より手前のブロックとしても必要になった場合は優先度を上げる。
            existing.isPrefetch = true
            if existing.blockIndex == nil || blockIndex < existing.blockIndex! {
                existing.blockIndex = blockIndex
            }
            return false
        }
        // 上限は「純粋な先行合成の予約」だけで数える。誰かが完成を待っている物や
        // 合成中の物は、押し出しても意味が無い(待っている人は消えない)。
        let evictable = entries.values.filter {
            $0.isInFlight == false && $0.waiters.isEmpty && $0.fillDestination == nil && $0.blockIndex != nil
        }
        if evictable.count >= prefetchCapacity {
            guard let farthest = evictable.max(by: { ($0.blockIndex ?? 0) < ($1.blockIndex ?? 0) }),
                  blockIndex < (farthest.blockIndex ?? Int.max) else {
                // 新しい予約の方が遠いなら、手前の予約を押し出してまで積む価値はない。
                return false
            }
            entries.removeValue(forKey: farthest.request.key)
        }
        let entry = Entry(request: request, generation: generation)
        entry.isPrefetch = true
        entry.blockIndex = blockIndex
        entries[request.key] = entry
        return true
    }

    /// 再生が今必要としている音声を、最優先で作ってもらって受け取る。
    ///
    /// 同じ鍵が既に(先行合成や作り足しとして)行列に居ればそれに相乗りする。
    /// 合成中でも、完成すれば同じ結果を受け取れる。ここで待った時間が
    /// そのまま無音になるので、行列の中では常に先頭に来る。
    func resultForPlayback(request: Request) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let entry = entries[request.key] ?? {
                let created = Entry(request: request, generation: generation)
                entries[request.key] = created
                return created
            }()
            entry.isNeededForPlaybackNow = true
            entry.waiters.append(continuation)
            lock.unlock()
            startWorkerIfNeeded()
        }
    }

    /// 作り足し(裏で先まで作っておく)の1件を頼み、ディスクへ置き終わるまで待つ。
    ///
    /// 優先度は最も低い。再生が必要とする合成・先行合成が空いた時だけ進む。
    /// (以前の「再生側の合成が終わるまで最大30秒待つ」ポーリングは、
    ///  行列の優先度がその役割を果たすので要らなくなった)
    /// - Returns: 出来上がった音声(既に出来ていた場合も含む)。
    @discardableResult
    func resultForBackgroundFill(request: Request, destination: FillDestination) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let entry = entries[request.key] ?? {
                let created = Entry(request: request, generation: generation)
                entries[request.key] = created
                return created
            }()
            if entry.fillDestination == nil {
                entry.fillDestination = destination
                entry.fillOrder = nextFillOrder
                nextFillOrder += 1
            }
            entry.waiters.append(continuation)
            lock.unlock()
            startWorkerIfNeeded()
        }
    }

    // MARK: - 再生位置・キャンセル

    /// 現在の再生位置を伝える。これより手前の(追い越された)先行合成の予約は捨てる。
    /// ロックだけで完結するので、合成中でも即座に反映される。
    func setPlaybackIndex(_ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        playbackIndex = index
        for (key, entry) in entries {
            guard let blockIndex = entry.blockIndex, blockIndex < index else { continue }
            guard entry.isInFlight == false, entry.waiters.isEmpty, entry.fillDestination == nil else { continue }
            entries.removeValue(forKey: key)
        }
    }

    /// 待機中の先行合成の予約を全て捨てる(読み上げ停止・シーク等)。
    /// 誰かが完成を待っている物と、実行中の1本は止められないのでそのまま
    /// (実行中のC呼び出しはプリエンプトできない。完成品は世代番号で見分けて、
    ///  メモリ層には置かない)。
    func cancelPendingPrefetch() {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        for (key, entry) in entries {
            guard entry.isInFlight == false, entry.waiters.isEmpty, entry.fillDestination == nil else { continue }
            entries.removeValue(forKey: key)
        }
    }

    // MARK: - 状態の参照

    /// 再生が今必要としている合成が進行中(順番待ち・CPU予算待ちを含む)か。
    /// 固着検出(SpeechBlockSpeaker)が「発話中のつもりなのに音も出ていないし
    /// 合成もしていない」を判定するのに使う。
    var isPlaybackSynthesisPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.contains { $0.isNeededForPlaybackNow }
    }

    /// その鍵が行列の中でどういう状態か(無音の原因の切り分けログ用)。
    func status(key: String) -> KeyStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return .notQueued }
        return entry.isInFlight ? .inFlight : .pending
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.filter { $0.isInFlight == false }.count
    }

    // MARK: - ワーカー(一人しかいない)

    /// 行列から1件ずつ取り出して合成し続けるワーカーを、走っていなければ起動する。
    /// 同時に走るのは常に1本(voicevox のC呼び出しは直列でしか走れないので、
    /// 複数走らせても速くならず、CPU上限に近づくだけ)。
    ///
    /// 優先度は .userInitiated。再生が今必要としている合成もこのワーカーが作るので、
    /// 低い優先度で始めると、CPUが埋まっている時にワーカー自体が後回しにされて
    /// そのぶん無音が伸びる(3コアを合成で埋め切っている間 .utility は
    /// 後回しにされ続ける事を、ディスク書き出しの遅延で実測済み)。
    private func startWorkerIfNeeded() {
        lock.lock()
        if isWorkerRunning {
            lock.unlock()
            return
        }
        isWorkerRunning = true
        lock.unlock()

        Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            while let entry = self.takeNextEntry() {
                await self.process(entry)
            }
            self.lock.lock()
            self.isWorkerRunning = false
            self.lock.unlock()
            // 終了を決めた直後に積まれた分を取り零さないよう、もう一度だけ確認する。
            if self.hasPendingEntry() {
                self.startWorkerIfNeeded()
            }
        }
    }

    private func hasPendingEntry() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.contains { $0.isInFlight == false }
    }

    /// 次に合成すべき1件。
    ///  1. 再生が今必要としている物(その中では再生位置に近い物)
    ///  2. 先行合成(再生位置に近い物)
    ///  3. 作り足し(積まれた順)
    private func takeNextEntry() -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        let pending = entries.values.filter { $0.isInFlight == false }
        let next = pending.filter({ $0.isNeededForPlaybackNow }).min(by: { ($0.blockIndex ?? Int.max) < ($1.blockIndex ?? Int.max) })
            ?? pending.filter({ $0.blockIndex != nil }).min(by: { $0.blockIndex! < $1.blockIndex! })
            ?? pending.filter({ $0.fillDestination != nil }).min(by: { $0.fillOrder < $1.fillOrder })
        guard let next = next else { return nil }
        next.isInFlight = true
        return next
    }

    /// 1件を仕上げる。合成するのは「どの置き場所にも無い」と分かった時だけ。
    private func process(_ entry: Entry) async {
        let request = entry.request

        // 既に出来ている物は作らない(これが「同じ鍵を二度合成しない」の実体)。
        if let wav = storage.peekMemory(request) {
            // 先に行列から外して結果を渡す(外した後に来た要求は新しい1件として扱われる)。
            let flags = resolve(entry, with: .success(wav))
            // 作り足しとして頼まれていた(=ディスクに置いてほしい)なら、
            // メモリの完成品を写すだけで済む。合成し直す必要は無い。
            if let destination = flags.fillDestination, storage.isOnDisk(request, destination) == false {
                storage.storeToDisk(request, wav, destination)
            }
            return
        }
        let destination = currentFillDestination(of: entry)
        if hasWaiters(entry) {
            if let data = storage.peekDisk(request, destination) {
                resolve(entry, with: .success(data))
                return
            }
        } else if storage.isOnDisk(request, destination) {
            // 誰も音声そのものを待っていないなら、有無の確認だけで済ませる
            // (先行合成の予約が、待っている間にディスクへ置かれていた場合)。
            // 確認してから外すまでの間に待ち人が現れたら、この近道は使えない
            // (何も渡さずに外すと、その人が永遠に待つ事になる)ので読み直す。
            if resolveIfNoWaiters(entry) { return }
            if let data = storage.peekDisk(request, destination) {
                resolve(entry, with: .success(data))
                return
            }
        }

        do {
            let wav = try await engine.synthesizeBlock(text: request.text, styleId: request.styleId)
            // 待っている人(再生・作り足し)を先に起こす。置く作業で再生を待たせない。
            let flags = resolve(entry, with: .success(wav))
            if flags.storesToMemory {
                storage.storeToMemory(request, wav)
            }
            // ディスクへは**ここで置き終えてから**次の合成へ進む。
            // 以前は別タスクへ逃がしていたため「作り終えたのに、まだどこにも
            // 見えない」時間が生まれ、その隙に同じ物がもう一度作られていた。
            // 置く作業は合成の 0.62%(実測)しかかからないので、直列で構わない。
            storage.storeToDisk(request, wav, flags.fillDestination)
        } catch {
            let flags = resolve(entry, with: .failure(error))
            if flags.hadWaiters == false {
                storage.onUnobservedError(request, error)
            }
        }
    }

    /// 待ち人がいないままなら行列から外す(いたら false)。
    private func resolveIfNoWaiters(_ entry: Entry) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard entry.waiters.isEmpty else { return false }
        entries.removeValue(forKey: entry.request.key)
        return true
    }

    private func hasWaiters(_ entry: Entry) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entry.waiters.isEmpty == false
    }

    private func currentFillDestination(of entry: Entry) -> FillDestination? {
        lock.lock()
        defer { lock.unlock() }
        return entry.fillDestination
    }

    /// 行列から取り除き、待っている全員に結果を渡す。
    @discardableResult
    private func resolve(_ entry: Entry,
                         with result: Result<Data, Error>) -> (storesToMemory: Bool, fillDestination: FillDestination?, hadWaiters: Bool) {
        lock.lock()
        entries.removeValue(forKey: entry.request.key)
        let waiters = entry.waiters
        entry.waiters = []
        // 停止/シークを跨いだ古い先行合成の完成品は、メモリ層に置かない
        // (新しい本文にとってはただの場所塞ぎのため)。待ち人には普通に渡す。
        let storesToMemory = entry.isPrefetch && entry.generation == generation
        let fillDestination = entry.fillDestination
        lock.unlock()
        for waiter in waiters {
            waiter.resume(with: result)
        }
        return (storesToMemory, fillDestination, waiters.isEmpty == false)
    }
}
