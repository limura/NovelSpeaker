//
//  VoicevoxWavCache.swift
//  NovelSpeaker
//
//  先行合成した音声(WAV)を保持するキャッシュ。
//
//  actor(VoicevoxCore)の隔離ではなく専用ロックで守る。actor 隔離のままだと、
//  既にキャッシュ済みで即返せるはずの参照(cache HIT)ですら、actor が別の
//  (無関係で低優先度な)先行合成を実行中だとその完了まで待たされてしまうため。
//
//  追い出しは「再生で使い終わった物」から先に行うのが要点。
//  合成は再生順に進むので、単純に挿入順(古い順)で捨てると
//  「一番先に再生するはずの物」を捨ててしまう。
//  実機(iPhone 17 Pro Max / 前景・AC・スレッド数自動)では、性能的には足りている
//  (無音率0.8%、再生時HIT率96.6%)のに数分に一度だけ無音が出ており、
//  「未再生の貯金」が 233秒 → 146 → 77 → 30 → 2.4秒 と単調に減って0になった所で
//  無音になっていた。その間キャッシュ合計は 332〜348秒(=16MB上限)で張り付いており、
//  用意できていたブロックが再生直前に押し出されていた。
//

import Foundation

final class VoicevoxWavCache {

    private struct Entry {
        let data: Data
        /// 再生で使い終わったか。追い出しはここが true の物から行う。
        var isPlayed: Bool
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    /// 挿入順(古い順)。同じ条件なら古い物から捨てる。
    private var insertionOrder: [String] = []
    private var totalBytes = 0

    /// 際限なく貯め込まないためのエントリ数上限。
    private let entryCapacity: Int
    /// WAVは 24kHz/mono/16bit で1秒あたり約48KB。長いブロックだと1本で数MBになるので、
    /// エントリ数だけでなく合計バイト数でも制限する。
    private let totalByteLimit: Int

    init(entryCapacity: Int, totalByteLimit: Int) {
        self.entryCapacity = max(1, entryCapacity)
        self.totalByteLimit = max(1, totalByteLimit)
    }

    func peek(key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]?.data
    }

    func byteCount(key: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]?.data.count
    }

    func store(key: String, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let old = entries[key] {
            totalBytes -= old.data.count
            // 同じ内容が改めて合成されたという事は、また必要になったという事なので、
            // 新しく入れた物として扱う(古い物から捨てる順序の後ろに回す)。
            if let index = insertionOrder.firstIndex(of: key) {
                insertionOrder.remove(at: index)
            }
        }
        insertionOrder.append(key)
        // 合成し直した物は「未再生」に戻す(同じ文字列が再登場したケース)。
        entries[key] = Entry(data: data, isPlayed: false)
        totalBytes += data.count
        evictIfNeeded(protecting: key)
    }

    /// 再生で使い終わった事を記録する。内容は残す
    /// (同じ文字列が本文中に再登場した時に再利用できるため)。
    func markPlayed(key: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[key]?.isPlayed = true
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        insertionOrder.removeAll()
        totalBytes = 0
    }

    var totalByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalBytes
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// 保持している音声の合計秒数(ログ用)。
    func totalAudioSeconds() -> Double {
        lock.lock()
        let bytes = totalBytes
        let count = entries.count
        lock.unlock()
        // 各エントリに WAV ヘッダ分が含まれるので差し引いてから秒数換算する。
        let payloadBytes = max(0, bytes - count * VoicevoxPerformanceMonitor.wavHeaderByteCount)
        return Double(payloadBytes) / (VoicevoxPerformanceMonitor.outputSampleRate * VoicevoxPerformanceMonitor.outputBytesPerFrame)
    }

    /// - Parameter protecting: 今入れたばかりのキー。これだけは追い出さない
    ///   (捨ててしまうと永久に合成し直しになる)。
    private func evictIfNeeded(protecting protectedKey: String) {
        // lock は呼び出し側で取っている前提。
        while entries.count > entryCapacity || (totalBytes > totalByteLimit && entries.count > 1) {
            guard let victim = nextVictimKey(protecting: protectedKey) else { return }
            if let removed = entries.removeValue(forKey: victim) {
                totalBytes -= removed.data.count
            }
            if let index = insertionOrder.firstIndex(of: victim) {
                insertionOrder.remove(at: index)
            }
        }
    }

    /// 次に捨てるべきキー。再生済みの物を古い順に、無ければ未再生の物を古い順に。
    private func nextVictimKey(protecting protectedKey: String) -> String? {
        for key in insertionOrder where key != protectedKey && entries[key]?.isPlayed == true {
            return key
        }
        for key in insertionOrder where key != protectedKey {
            return key
        }
        return nil
    }
}
