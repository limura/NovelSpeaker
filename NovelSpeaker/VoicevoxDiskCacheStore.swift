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
//   - **小説ごとのディレクトリ**。管理画面での「この小説だけ削除」と集計が
//     ディレクトリ操作だけで成立する。
//   - 保存先は Application Support(Caches は OS に勝手に消される)+ バックアップ除外。
//

import Foundation
import CryptoKit

/// キャッシュの集計結果(管理画面の「何分ぶん作れたか」用)。
struct VoicevoxDiskCacheSummary: Equatable {
    let entryCount: Int
    let audioSeconds: Double
    let byteCount: Int

    static let empty = VoicevoxDiskCacheSummary(entryCount: 0, audioSeconds: 0, byteCount: 0)
}

final class VoicevoxDiskCacheStore {

    static let shared = VoicevoxDiskCacheStore(rootDirectory: VoicevoxDiskCacheStore.defaultRootDirectory())

    /// 保存する音声のファイル拡張子。生の WAV は 1秒あたり約48KB(20分で57MB)あるので、
    /// AAC に圧縮して置く(20分で約5MB)。
    static let fileExtension = "m4a"

    private let rootDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    /// ディレクトリの内容をメモリ上に写したもの(小説ディレクトリ名 → 鍵 → 実体)。
    /// 索引「ファイル」ではないので壊れる心配は無く、初回参照時にディレクトリを
    /// 1回読むだけで作れる。有無の判定を毎回 readdir せずに済ませるためのもの。
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

    // MARK: - 保存と取り出し

    func store(novelID: String, key: String, data: Data, durationSeconds: Double) throws {
        let directoryName = Self.directoryName(novelID: novelID)
        let directory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try prepareDirectories(novelDirectory: directory)

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
        var listing = listings[directoryName] ?? loadListingUnsafe(directoryName: directoryName, directory: directory)
        // 同じ鍵で長さの違う古いファイルが残っていたら消す(上書きではなく別名になるため)。
        if let old = listing[key], old.fileName != fileName {
            try? fileManager.removeItem(at: directory.appendingPathComponent(old.fileName))
        }
        listing[key] = Entry(fileName: fileName, byteCount: data.count, durationSeconds: Double(milliseconds) / 1000)
        listings[directoryName] = listing
        lock.unlock()
    }

    func load(novelID: String, key: String) -> Data? {
        guard let (directory, entry) = entryFor(novelID: novelID, key: key) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(entry.fileName))
    }

    /// 中身を読まずに有無だけを判定する(生成の再開時に「どこまで作れているか」を数えるため)。
    func contains(novelID: String, key: String) -> Bool {
        return entryFor(novelID: novelID, key: key) != nil
    }

    private func entryFor(novelID: String, key: String) -> (URL, Entry)? {
        let directoryName = Self.directoryName(novelID: novelID)
        let directory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
        lock.lock()
        defer { lock.unlock() }
        let listing = listings[directoryName] ?? loadListingUnsafe(directoryName: directoryName, directory: directory)
        guard let entry = listing[key] else { return nil }
        return (directory, entry)
    }

    // MARK: - 集計

    func summary(novelID: String) -> VoicevoxDiskCacheSummary {
        let directoryName = Self.directoryName(novelID: novelID)
        let directory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
        lock.lock()
        let listing = listings[directoryName] ?? loadListingUnsafe(directoryName: directoryName, directory: directory)
        lock.unlock()
        return Self.summarize(listing.values)
    }

    func totalSummary() -> VoicevoxDiskCacheSummary {
        guard let directoryNames = try? fileManager.contentsOfDirectory(atPath: rootDirectory.path) else {
            return .empty
        }
        var entries: [Entry] = []
        for directoryName in directoryNames {
            let directory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
            lock.lock()
            let listing = listings[directoryName] ?? loadListingUnsafe(directoryName: directoryName, directory: directory)
            lock.unlock()
            entries.append(contentsOf: listing.values)
        }
        return Self.summarize(entries)
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
        let directoryName = Self.directoryName(novelID: novelID)
        try? fileManager.removeItem(at: rootDirectory.appendingPathComponent(directoryName, isDirectory: true))
        lock.lock()
        listings[directoryName] = [:]
        lock.unlock()
    }

    func removeAll() {
        try? fileManager.removeItem(at: rootDirectory)
        lock.lock()
        listings.removeAll()
        lock.unlock()
    }

    /// 残す鍵の一覧に無いものを消す。
    /// 読み替え辞書の変更等で内容が変わった時に使う。作り直しには数十分かかるので、
    /// 全消しではなく「変わった分だけ」を消せる必要がある。
    func removeEntries(novelID: String, notIn keysToKeep: Set<String>) {
        let directoryName = Self.directoryName(novelID: novelID)
        let directory = rootDirectory.appendingPathComponent(directoryName, isDirectory: true)
        lock.lock()
        var listing = listings[directoryName] ?? loadListingUnsafe(directoryName: directoryName, directory: directory)
        for (key, entry) in listing where keysToKeep.contains(key) == false {
            try? fileManager.removeItem(at: directory.appendingPathComponent(entry.fileName))
            listing.removeValue(forKey: key)
        }
        listings[directoryName] = listing
        lock.unlock()
    }

    // MARK: - ディレクトリ

    private func prepareDirectories(novelDirectory: URL) throws {
        if fileManager.fileExists(atPath: rootDirectory.path) == false {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        // 合成し直せる物であり1作品で数十MBになるため、バックアップには含めない。
        // (含めると利用者のバックアップ容量を無断で食い潰す事になる)
        var root = rootDirectory
        if (try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? root.setResourceValues(values)
        }
        if fileManager.fileExists(atPath: novelDirectory.path) == false {
            try fileManager.createDirectory(at: novelDirectory, withIntermediateDirectories: true)
        }
    }

    /// ディレクトリを1回読んで、鍵→実体の対応を作る。lock は呼び出し側で取っている前提。
    @discardableResult
    private func loadListingUnsafe(directoryName: String, directory: URL) -> [String: Entry] {
        var listing: [String: Entry] = [:]
        if let names = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            for name in names {
                guard let entry = Self.parse(fileName: name) else { continue }
                let byteCount = (try? fileManager.attributesOfItem(atPath: directory.appendingPathComponent(name).path)[.size] as? Int) ?? nil
                listing[entry.key] = Entry(fileName: name, byteCount: byteCount ?? 0, durationSeconds: entry.durationSeconds)
            }
        }
        listings[directoryName] = listing
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
