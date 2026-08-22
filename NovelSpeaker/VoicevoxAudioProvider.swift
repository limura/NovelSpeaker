//
//  VoicevoxAudioProvider.swift
//  NovelSpeaker
//
//  合成済み音声の「置き場所」を隠す層。
//
//  音声は メモリ(先行合成キャッシュ) → ディスク(作成済み/一時) の順に探す。
//  以前は呼ぶ側が peekCache と peekDiskCache を順に叩いていて、
//  片方だけ見る書き忘れが実際に起きた(再生側の低速パスがディスクを見ておらず、
//  裏の作り足しが置いた音声を見落として同じ物をもう一度合成していた)。
//  参照の入り口をここ一つに絞る事で、この種の見落としを構造的に無くす。
//
//  actor(VoicevoxCore)には属させない。actor 隔離だと、即返せるはずの参照ですら
//  実行中の合成(1本12秒前後のC呼び出し)の完了までactorへ入れず待たされるため。
//

import Foundation

final class VoicevoxAudioProvider {

    // MARK: - 今どの小説のどの話を読んでいるか
    //
    // どの小説のどの話を再生中かはここからは分からないので、
    // 再生側(StorySpeaker)が話を切り替える度にここへ教える。

    struct DiskCacheContext {
        let novelID: String
        let chapterNumber: Int

        /// ディスクへ書き足してよいか(利用者がその小説でキャッシュ生成を有効にしている時だけ true)。
        /// 普通に聴いているだけで断りなくストレージを使い始めない、という線引き。
        ///
        /// ここは保持せず、その都度調べる。読み上げ中の小説について後から生成を
        /// 有効にする(詳細画面から「生成する」を押す)事があり、作った時点の値を
        /// 覚えていると、その回の読み上げでは一切ディスクに積まれなくなる。
        var isWritable: Bool {
            return VoicevoxCacheGenerationState.shared.isEnabled(novelID: novelID)
        }
    }

    private let contextLock = NSLock()
    private var contextUnsafe: DiskCacheContext?

    var diskCacheContext: DiskCacheContext? {
        contextLock.lock()
        defer { contextLock.unlock() }
        return contextUnsafe
    }

    /// 今どの小説のどの話を読んでいるかを教える(nil で解除)。
    func setDiskCacheContext(novelID: String?, chapterNumber: Int) {
        let context: DiskCacheContext? = novelID.map { DiskCacheContext(novelID: $0, chapterNumber: chapterNumber) }
        contextLock.lock()
        contextUnsafe = context
        contextLock.unlock()
    }

    // MARK: - メモリ層(先行合成キャッシュ)

    // 現在再生中のブロックより先のブロックを、再生が追いつく前に合成しておくためのもの。
    // 追い出しの順序が要点なので、実体は VoicevoxWavCache に切り出してある。
    // 会話文の相槌等の短い文字列が再利用されるので、エントリ数は多めに持つ。
    private let wavCache = VoicevoxWavCache(entryCapacity: 64, totalByteLimit: 16 * 1024 * 1024)

    func memoryAudio(key: String) -> Data? {
        return wavCache.peek(key: key)
    }

    /// 指定の鍵が先行合成済みなら、その WAV のバイト数を返す(未合成なら nil)。
    /// 「未再生の貯金が何秒あるか」を数えるために使う。
    ///
    /// あえてメモリ層だけを見る。貯金の計算は「再生が途切れずに進めるか」ではなく
    /// 「先行合成をこれ以上急ぐ必要があるか」の判断材料なので、
    /// ディスクに作り置きがあるかどうかとは別の数字として扱う。
    func memoryByteCount(key: String) -> Int? {
        return wavCache.byteCount(key: key)
    }

    func storeToMemory(key: String, data: Data) {
        wavCache.store(key: key, data: data)
    }

    /// 再生で使い終わった事を記録する。キャッシュが上限に達した時、
    /// これが付いている物から先に捨てる。
    func markPlayed(key: String) {
        wavCache.markPlayed(key: key)
    }

    func clearMemory() {
        wavCache.clear()
    }

    /// ログ用: 現在メモリに持っている音声の合計秒数。
    func memoryAudioSecondsForLogging() -> Double {
        return wavCache.totalAudioSeconds()
    }

    // MARK: - ディスク層(作成済み/一時)

    /// 既にディスクに作ってあるか(音声そのものは読まない)。
    func isStoredOnDisk(key: String) -> Bool {
        guard let context = diskCacheContext else { return false }
        return VoicevoxDiskCacheStore.shared.contains(novelID: context.novelID, chapterNumber: context.chapterNumber, key: key)
    }

    func diskAudio(key: String) -> Data? {
        guard let context = diskCacheContext else { return nil }
        guard let data = VoicevoxDiskCacheStore.shared.load(novelID: context.novelID, chapterNumber: context.chapterNumber, key: key) else { return nil }
        VoicevoxCPUUsageReporter.shared.noteDiskCacheHit()
        return data
    }

    // MARK: - 統合参照(この一段だけを使うのが基本)

    enum Source {
        case memory
        case disk
    }

    /// 置き場所を意識せずに音声を探す。メモリ → ディスクの順。
    /// メモリ層は WAV、ディスク層は圧縮音声(m4a)を返すが、再生側はどちらも扱える。
    func audio(key: String) -> (data: Data, source: Source)? {
        if let data = memoryAudio(key: key) { return (data, .memory) }
        if let data = diskAudio(key: key) { return (data, .disk) }
        return nil
    }

    /// どこかの層に既にあるか(音声そのものは読まない)。
    func isAvailable(key: String) -> Bool {
        if memoryByteCount(key: key) != nil { return true }
        return isStoredOnDisk(key: key)
    }
}
