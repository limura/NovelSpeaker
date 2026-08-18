//
//  VoicevoxVoiceModelStore.swift
//  NovelSpeaker
//
//  取得した VVM(音声モデル)の置き場所。
//
//  置き場所は Application Support 配下 + バックアップ除外。
//  1ファイル60MB前後で、消えても公式から取り直せる物なので、
//  iCloud バックアップに入れるとただの迷惑になる。
//  (Caches に置くと OS に勝手に消されるので、そちらも駄目)
//
//  **形式ごとにディレクトリを分ける。**
//
//      VoicevoxVoiceModels/f1/0.vvm     ← vvm_format_version = 1
//      VoicevoxVoiceModels/f2/3.vvm     ← vvm_format_version = 2
//
//  こうしておくと、コアを上げて新しい形式を読めるようになった後も、
//  **既に取得済みの古い形式のファイルをそのまま使い続けられる**
//  (新しいコアは古い形式も読める)。1.4GB の取り直しを強いずに済む。
//  ファイル名に紛れ込ませず、ディレクトリで分けるのは、
//  「この形式はもう読めない」となった時に**ディレクトリごと捨てられる**ため。
//
//  同じ音声モデルを複数の形式で持つ事はしない(取得前に isStored で弾く)。
//  持ってしまうと同じ styleId を2つのファイルが名乗る事になる。
//  それでも混ざった場合に備えて、列挙時は新しい形式の方を採る。
//

import Foundation

enum VoicevoxVoiceModelStoreError: Error, Equatable {
    /// 中身が確認できなかった(壊れている・別物)
    case unreadable
    /// このアプリのコアが読めない形式だった
    case unsupportedFormat(Int)
    /// 期待していたスタイルが入っていなかった(取り違え)
    case missingExpectedStyles(Set<UInt32>)
}

class VoicevoxVoiceModelStore {
    static let shared = VoicevoxVoiceModelStore()

    let rootDirectory: URL

    /// - Parameter rootDirectory: 省略時は Application Support 配下。テストでは差し替える。
    init(rootDirectory: URL? = nil) {
        if let rootDirectory = rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.rootDirectory = base.appendingPathComponent("VoicevoxVoiceModels", isDirectory: true)
        }
    }

    // MARK: - 置き場所

    func directoryURL(forFormat format: Int) -> URL {
        return rootDirectory.appendingPathComponent("f\(format)", isDirectory: true)
    }

    func fileURL(forModelID modelID: String, format: Int) -> URL {
        return directoryURL(forFormat: format).appendingPathComponent("\(modelID).vvm")
    }

    private func prepareDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        excludeFromBackup(rootDirectory)
    }

    /// 再取得できる物なので iCloud バックアップから外す。
    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? target.setResourceValues(values)
    }

    // MARK: - 何を持っているか

    /// その音声モデルを持っていれば、置き場所と形式を返す。
    /// 複数の形式で持っていた場合は**新しい形式の方**を返す。
    func stored(modelID: String, readableFormats: Set<Int>) -> (url: URL, format: Int)? {
        for format in readableFormats.sorted(by: >) {
            let url = fileURL(forModelID: modelID, format: format)
            if FileManager.default.fileExists(atPath: url.path) {
                return (url, format)
            }
        }
        return nil
    }

    func isStored(modelID: String, readableFormats: Set<Int>) -> Bool {
        return stored(modelID: modelID, readableFormats: readableFormats) != nil
    }

    /// 持っている音声モデルの一覧(音声モデルID → 形式)。
    func storedModelIDs(readableFormats: Set<Int>) -> [String: Int] {
        var result: [String: Int] = [:]
        // 古い形式から順に見て、新しい形式で上書きする。
        for format in readableFormats.sorted() {
            let directory = directoryURL(forFormat: format)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for entry in entries where entry.hasSuffix(".vvm") {
                result[String(entry.dropLast(4))] = format
            }
        }
        return result
    }

    /// コアに渡すファイルの一覧。
    /// **同じ音声モデルが重複しないよう、形式ごとに1つに絞ってある。**
    /// 重複させると、同じ styleId を2つのファイルが名乗る事になる。
    func modelFileURLs(readableFormats: Set<Int>) -> [URL] {
        return storedModelIDs(readableFormats: readableFormats)
            .sorted { lhs, rhs in
                (Int(lhs.key) ?? Int.max, lhs.key) < (Int(rhs.key) ?? Int.max, rhs.key)
            }
            .map { fileURL(forModelID: $0.key, format: $0.value) }
    }

    func totalBytes(readableFormats: Set<Int>) -> Int64 {
        return modelFileURLs(readableFormats: readableFormats).reduce(Int64(0)) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber
            return total + (size?.int64Value ?? 0)
        }
    }

    // MARK: - 置く / 消す

    /// 取ってきたファイルを検証してから置く。
    ///
    /// **検証を通るまで保存場所に入れない。** 壊れた物を置いてしまうと、
    /// 「取得済み」として扱われた挙句、再生しようとした時に初めて失敗する事になる。
    ///
    /// - Parameters:
    ///   - expectedStyleIds: カタログが「これが入っているはず」と言っているスタイル。
    ///     取り違え(別の番号のファイルを掴んだ等)を検出するために照合する。
    @discardableResult
    func store(temporaryFileURL: URL, modelID: String,
               expectedStyleIds: Set<UInt32>, readableFormats: Set<Int>) throws -> URL {
        let info: VoicevoxVoiceModelFileInfo
        do {
            info = try VoicevoxVoiceModelFileInspector.inspect(fileURL: temporaryFileURL)
        } catch {
            throw VoicevoxVoiceModelStoreError.unreadable
        }
        guard readableFormats.contains(info.vvmFormatVersion) else {
            throw VoicevoxVoiceModelStoreError.unsupportedFormat(info.vvmFormatVersion)
        }
        let missing = expectedStyleIds.subtracting(info.allStyleIds)
        guard missing.isEmpty else {
            throw VoicevoxVoiceModelStoreError.missingExpectedStyles(missing)
        }

        let destination = fileURL(forModelID: modelID, format: info.vvmFormatVersion)
        try prepareDirectory(destination.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryFileURL, to: destination)
        return destination
    }

    /// その音声モデルを、どの形式の物も消す。
    func remove(modelID: String, readableFormats: Set<Int>) {
        for format in readableFormats {
            let url = fileURL(forModelID: modelID, format: format)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    /// もう読めなくなった形式のディレクトリを丸ごと捨てる。
    /// (コアの都合で形式が読めなくなった場合の後始末。今のところ起きない想定)
    func removeUnreadableFormats(readableFormats: Set<Int>) {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: rootDirectory.path)) ?? []
        for entry in entries where entry.hasPrefix("f") {
            guard let format = Int(entry.dropFirst()) else { continue }
            if readableFormats.contains(format) == false {
                try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(entry))
            }
        }
    }
}
