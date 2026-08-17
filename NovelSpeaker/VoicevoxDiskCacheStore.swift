//
//  VoicevoxDiskCacheStore.swift
//  NovelSpeaker
//
//  VOICEVOX の合成済み音声をディスクに貯めておく保存層。
//
//  なぜ必要か:
//  背面バッテリー駆動では iOS の CPU 上限(60秒平均で1コア相当の80%)が効くため、
//  実測で iPhone 17 Pro Max ですら 1.45倍速に必要な CPU 率は 128%、
//  iPhone SE2 では 226% で、どうやっても実時間で合成し切れない
//  (スケジューラ側は既に理論下限まで詰めてある)。
//  事前に作って貯めておく以外に、無音を無くす方法が無い。
//
//  設計:
//   - **索引ファイルを持たない**。壊れた索引の整合性を取る処理を書かなくて済むよう、
//     音声の長さをファイル名自体(`<鍵>_<ミリ秒>.m4a`)に持たせる。
//     容量も合計時間もディレクトリを読むだけで求まり、途中で電源が切れても
//     「中途半端なファイルが1つ余分にある」以上の壊れ方をしない。
//   - **鍵は内容アドレス方式**(styleId と読み上げ文字列から決まる)。
//     読み替え辞書を変更しても、変わったブロックだけが作り直しになる。
//   - **小説ごと・話ごとのディレクトリ**。
//       `<小説の鍵>/<話番号>/<ブロックの鍵>_<ミリ秒>.m4a`
//     話ごとに掘るのは、1ディレクトリのファイル数を数十に抑えるためだけでなく、
//     「20話目の何%まで作れたか」がそのディレクトリを数えるだけで求まるため。
//   - 保存先は Application Support(Caches は OS に勝手に消される)+ バックアップ除外。
//   - **端末ローカル限定**。他端末では話者(VVM)がダウンロードされているとは限らず、
//     読み替え辞書も同じとは限らないので、共有しても使えない。
//     よって Realm には持たせない(バックアップ/同期/コピーの並行リストが増えるため)。
//

import Foundation
import CryptoKit

/// キャッシュの集計結果(管理画面の「何分ぶん作れたか」用)。
struct VoicevoxDiskCacheSummary: Equatable {
    let entryCount: Int
    let audioSeconds: Double
    let byteCount: Int

    static let empty = VoicevoxDiskCacheSummary(entryCount: 0, audioSeconds: 0, byteCount: 0)

    static func + (lhs: VoicevoxDiskCacheSummary, rhs: VoicevoxDiskCacheSummary) -> VoicevoxDiskCacheSummary {
        return VoicevoxDiskCacheSummary(
            entryCount: lhs.entryCount + rhs.entryCount,
            audioSeconds: lhs.audioSeconds + rhs.audioSeconds,
            byteCount: lhs.byteCount + rhs.byteCount
        )
    }
}

final class VoicevoxDiskCacheStore {

    static let shared = VoicevoxDiskCacheStore(rootDirectory: VoicevoxDiskCacheStore.defaultRootDirectory())

    /// 保存する音声のファイル拡張子。生の WAV は 1秒あたり約48KB(1時間で約170MB)あるので、
    /// AAC に圧縮して置く(1時間で約15MB)。
    static let fileExtension = "m4a"

    /// 小説ディレクトリに置く、小説IDを書いた印。
    ///
    /// ディレクトリ名は小説IDのハッシュなので元に戻せない。管理画面で
    /// 「どの小説のキャッシュか」を出すためにこれを読む。
    /// 失われても音声そのものは無事で、「不明な小説」として削除だけはできる
    /// (索引と違って、壊れても整合性を取り直す必要が無い)。
    private static let novelIDMarkerFileName = "novelID.txt"

    private let rootDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    /// ディレクトリの内容をメモリ上に写したもの(話ディレクトリのパス → 鍵 → 実体)。
    /// 索引「ファイル」ではないので壊れる心配は無く、初回参照時に readdir 1回で作れる。
    /// 「もう作ってあるか」の判定を毎回ディレクトリを読まずに済ませるためのもの。
    private var listings: [String: [String: Entry]] = [:]

    private struct Entry {
        let fileName: String
        let byteCount: Int
        let durationSeconds: Double
    }

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    static func defaultRootDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("VoicevoxAudioCache", isDirectory: true)
    }

    // MARK: - 鍵

    /// 音声の内容から決まる鍵。話者と読み上げ文字列が同じなら同じ音声になる。
    /// そのままファイル名にするので、英数字のみ(SHA256 の16進表記)である事が必要。
    static func key(text: String, styleId: UInt32) -> String {
        return sha256Hex("\(styleId)::\(text)")
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 小説IDはURL等でファイル名に使えない文字を含み得るので、そのまま使わない。
    private static func directoryName(novelID: String) -> String {
        return sha256Hex(novelID)
    }

    // MARK: - 場所

    private func novelDirectory(novelID: String) -> URL {
        return rootDirectory.appendingPathComponent(Self.directoryName(novelID: novelID), isDirectory: true)
    }

    private func chapterDirectory(novelID: String, chapterNumber: Int) -> URL {
        return novelDirectory(novelID: novelID).appendingPathComponent("\(chapterNumber)", isDirectory: true)
    }

    // MARK: - 保存と取り出し

    func store(novelID: String, chapterNumber: Int, key: String, data: Data, durationSeconds: Double) throws {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        try prepareDirectories(novelID: novelID, chapterDirectory: directory)

        let milliseconds = max(0, Int((durationSeconds * 1000).rounded()))
        let fileName = "\(key)_\(milliseconds).\(Self.fileExtension)"
        let destination = directory.appendingPathComponent(fileName)

        // 途中で電源が切れても半端なファイルを掴まないよう、書いてから置き換える。
        let temporary = directory.appendingPathComponent("tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)

        lock.lock()
        var listing = listingUnsafe(directory: directory)
        // 同じ鍵で長さの違う古いファイルが残っていたら消す(名前が変わるので上書きにならない)。
        if let old = listing[key], old.fileName != fileName {
            try? fileManager.removeItem(at: directory.appendingPathComponent(old.fileName))
        }
        listing[key] = Entry(fileName: fileName, byteCount: data.count, durationSeconds: Double(milliseconds) / 1000)
        listings[directory.path] = listing
        lock.unlock()
    }

    func load(novelID: String, chapterNumber: Int, key: String) -> Data? {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        guard let entry = entry(directory: directory, key: key) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(entry.fileName))
    }

    /// 中身を読まずに有無だけを判定する(生成の再開時に「どこまで作れているか」を数えるため)。
    func contains(novelID: String, chapterNumber: Int, key: String) -> Bool {
        return entry(directory: chapterDirectory(novelID: novelID, chapterNumber: chapterNumber), key: key) != nil
    }

    /// 保存してある音声の長さ。中身を読まずに求まる(ファイル名に入っているため)。
    /// 「この先どれだけ再生ぶんが貯まっているか」の計算に使う。
    func durationSeconds(novelID: String, chapterNumber: Int, key: String) -> Double? {
        return entry(directory: chapterDirectory(novelID: novelID, chapterNumber: chapterNumber), key: key)?.durationSeconds
    }

    private func entry(directory: URL, key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return listingUnsafe(directory: directory)[key]
    }

    // MARK: - 集計

    func summary(novelID: String, chapterNumber: Int) -> VoicevoxDiskCacheSummary {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        lock.lock()
        let listing = listingUnsafe(directory: directory)
        lock.unlock()
        return Self.summarize(listing.values)
    }

    func summary(novelID: String) -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for chapterNumber in chapterNumbers(novelID: novelID) {
            total = total + summary(novelID: novelID, chapterNumber: chapterNumber)
        }
        return total
    }

    /// 指定ページより前(そのページ自身は含まない)に貯まっている分。
    /// 「もう聴き終わった所を消す」時に、消える量を先に見せるために使う。
    func summary(novelID: String, beforeChapterNumber: Int) -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for chapterNumber in chapterNumbers(novelID: novelID) where chapterNumber < beforeChapterNumber {
            total = total + summary(novelID: novelID, chapterNumber: chapterNumber)
        }
        return total
    }

    /// 指定ページより前(そのページ自身は含まない)を消す。
    func removeChapters(novelID: String, beforeChapterNumber: Int) {
        for chapterNumber in chapterNumbers(novelID: novelID) where chapterNumber < beforeChapterNumber {
            remove(novelID: novelID, chapterNumber: chapterNumber)
        }
    }

    func totalSummary() -> VoicevoxDiskCacheSummary {
        var total = VoicevoxDiskCacheSummary.empty
        for novelID in cachedNovelIDs() {
            total = total + summary(novelID: novelID)
        }
        return total
    }

    /// キャッシュを持っている話の番号(小さい順)。
    func chapterNumbers(novelID: String) -> [Int] {
        let directory = novelDirectory(novelID: novelID)
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { Int($0) }.sorted()
    }

    /// キャッシュを持っている小説のID(管理画面用)。
    /// ディレクトリ名はハッシュで元に戻せないので、置いてある印から読む。
    func cachedNovelIDs() -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path) else { return [] }
        var result: [String] = []
        for name in names {
            let markerURL = rootDirectory.appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(Self.novelIDMarkerFileName)
            guard let data = try? Data(contentsOf: markerURL),
                  let novelID = String(data: data, encoding: .utf8) else { continue }
            result.append(novelID)
        }
        return result
    }

    private static func summarize<S: Sequence>(_ entries: S) -> VoicevoxDiskCacheSummary where S.Element == Entry {
        var count = 0
        var seconds = 0.0
        var bytes = 0
        for entry in entries {
            count += 1
            seconds += entry.durationSeconds
            bytes += entry.byteCount
        }
        return VoicevoxDiskCacheSummary(entryCount: count, audioSeconds: seconds, byteCount: bytes)
    }

    // MARK: - 削除

    func remove(novelID: String) {
        let directory = novelDirectory(novelID: novelID)
        try? fileManager.removeItem(at: directory)
        forgetListings(under: directory)
    }

    func remove(novelID: String, chapterNumber: Int) {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        try? fileManager.removeItem(at: directory)
        forgetListings(under: directory)
    }

    func removeAll() {
        try? fileManager.removeItem(at: rootDirectory)
        lock.lock()
        listings.removeAll()
        lock.unlock()
    }

    /// 残す鍵の一覧に無いものが、どれだけあるか(消さずに数えるだけ)。
    /// 「今の設定だと x時間y分ぶん(zMB)が無駄になっています」を、
    /// 実際に消す前に見せるために使う。
    func summary(novelID: String, chapterNumber: Int, notIn keysToKeep: Set<String>) -> VoicevoxDiskCacheSummary {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        lock.lock()
        let listing = listingUnsafe(directory: directory)
        lock.unlock()
        return Self.summarize(listing.filter { keysToKeep.contains($0.key) == false }.values)
    }

    /// 残す鍵の一覧に無いものを消す。
    /// 読み替え辞書の変更等で内容が変わった時に使う。作り直しには数十分かかるので、
    /// 全消しではなく「変わった分だけ」を消せる必要がある。
    func removeEntries(novelID: String, chapterNumber: Int, notIn keysToKeep: Set<String>) {
        let directory = chapterDirectory(novelID: novelID, chapterNumber: chapterNumber)
        lock.lock()
        var listing = listingUnsafe(directory: directory)
        for (key, entry) in listing where keysToKeep.contains(key) == false {
            try? fileManager.removeItem(at: directory.appendingPathComponent(entry.fileName))
            listing.removeValue(forKey: key)
        }
        listings[directory.path] = listing
        lock.unlock()
    }

    private func forgetListings(under directory: URL) {
        lock.lock()
        for path in listings.keys where path == directory.path || path.hasPrefix(directory.path + "/") {
            listings.removeValue(forKey: path)
        }
        lock.unlock()
    }

    // MARK: - ディレクトリ

    private func prepareDirectories(novelID: String, chapterDirectory: URL) throws {
        if fileManager.fileExists(atPath: rootDirectory.path) == false {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        // 合成し直せる物であり1作品で数百MBになるため、バックアップには含めない。
        // (含めると利用者のバックアップ容量を無断で食い潰す事になる)
        var root = rootDirectory
        if (try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
        }
        if fileManager.fileExists(atPath: chapterDirectory.path) == false {
            try fileManager.createDirectory(at: chapterDirectory, withIntermediateDirectories: true)
        }
        let markerURL = novelDirectory(novelID: novelID).appendingPathComponent(Self.novelIDMarkerFileName)
        if fileManager.fileExists(atPath: markerURL.path) == false {
            try? Data(novelID.utf8).write(to: markerURL, options: .atomic)
        }
    }

    /// ディレクトリを1回読んで、鍵→実体の対応を作る。lock は呼び出し側で取っている前提。
    private func listingUnsafe(directory: URL) -> [String: Entry] {
        if let cached = listings[directory.path] { return cached }
        var listing: [String: Entry] = [:]
        if let names = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            for name in names {
                guard let parsed = Self.parse(fileName: name) else { continue }
                let attributes = try? fileManager.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
                let byteCount = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                listing[parsed.key] = Entry(fileName: name, byteCount: byteCount, durationSeconds: parsed.durationSeconds)
            }
        }
        listings[directory.path] = listing
        return listing
    }

    /// `<鍵>_<ミリ秒>.m4a` を読み解く。読めない名前(書きかけの tmp-… 等)は無視する。
    private static func parse(fileName: String) -> (key: String, durationSeconds: Double)? {
        guard fileName.hasSuffix(".\(fileExtension)") else { return nil }
        let base = String(fileName.dropLast(fileExtension.count + 1))
        guard let separator = base.lastIndex(of: "_") else { return nil }
        let key = String(base[base.startIndex..<separator])
        let millisecondsText = String(base[base.index(after: separator)...])
        guard key.isEmpty == false, let milliseconds = Int(millisecondsText) else { return nil }
        return (key, Double(milliseconds) / 1000)
    }
}
