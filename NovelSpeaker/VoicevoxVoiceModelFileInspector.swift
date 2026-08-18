//
//  VoicevoxVoiceModelFileInspector.swift
//  NovelSpeaker
//
//  VVM ファイルの中身を、コアを通さずに覗く。
//
//  用途は「取ってきたファイルを保存場所に置いてよいか」の検証。
//  壊れた物や、このアプリのコアが読めない形式の物を置いてしまうと、
//  再生しようとした時に初めて失敗する事になり、原因が分かりにくい。
//  置く前に弾く。
//
//  VVM は**無圧縮の zip** で、先頭に manifest.json と metas.json が
//  平文で並んでいる(保護されているのは models/*.bin だけ)。
//  そのため zip 展開の仕組みを持ち出さなくても、
//  先頭を数十KB読んで local file header を辿るだけで中身が分かる。
//  60MB のファイル全体を読む必要は無い。
//

import Foundation

struct VoicevoxVoiceModelFileInfo: Equatable {
    let vvmFormatVersion: Int
    let speakers: [Speaker]

    struct Speaker: Equatable {
        let name: String
        let uuid: String
        let styles: [Style]
    }
    struct Style: Equatable {
        let name: String
        let styleId: UInt32
    }

    var allStyleIds: Set<UInt32> {
        return Set(speakers.flatMap { $0.styles.map { $0.styleId } })
    }
}

enum VoicevoxVoiceModelFileInspectorError: Error, Equatable {
    /// zip として読めない(そもそも別物・途中で切れている)
    case notAZipFile
    /// 期待するファイルが先頭に見つからない
    case entryNotFound(String)
    /// 無圧縮でない(VVM の作り方が変わった)
    case unexpectedCompression(String)
    /// 先頭を読んだ範囲に収まっていない
    case truncated(String)
    case malformedJSON(String)
}

enum VoicevoxVoiceModelFileInspector {
    /// これだけ読めば manifest.json と metas.json は入っている(実測で合わせて数KB)。
    /// 万一足りなくなっても truncated として弾くだけで、誤った情報は返さない。
    static let headBytes = 256 * 1024

    static func inspect(fileURL: URL) throws -> VoicevoxVoiceModelFileInfo {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let head = handle.readData(ofLength: headBytes)
        return try inspect(head: head)
    }

    static func inspect(head: Data) throws -> VoicevoxVoiceModelFileInfo {
        let entries = try readEntries(head: head, wanted: ["manifest.json", "metas.json"])
        guard let manifestData = entries["manifest.json"] else {
            throw VoicevoxVoiceModelFileInspectorError.entryNotFound("manifest.json")
        }
        guard let metasData = entries["metas.json"] else {
            throw VoicevoxVoiceModelFileInspectorError.entryNotFound("metas.json")
        }

        struct Manifest: Decodable { let vvm_format_version: Int }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
            throw VoicevoxVoiceModelFileInspectorError.malformedJSON("manifest.json")
        }

        struct MetaStyle: Decodable { let name: String; let id: UInt32 }
        struct Meta: Decodable { let name: String; let styles: [MetaStyle]; let speaker_uuid: String }
        guard let metas = try? JSONDecoder().decode([Meta].self, from: metasData) else {
            throw VoicevoxVoiceModelFileInspectorError.malformedJSON("metas.json")
        }

        return VoicevoxVoiceModelFileInfo(
            vvmFormatVersion: manifest.vvm_format_version,
            speakers: metas.map { meta in
                VoicevoxVoiceModelFileInfo.Speaker(
                    name: meta.name, uuid: meta.speaker_uuid,
                    styles: meta.styles.map {
                        VoicevoxVoiceModelFileInfo.Style(name: $0.name, styleId: $0.id)
                    })
            })
    }

    /// 無圧縮 zip の先頭から、欲しいファイル名の中身を取り出す。
    ///
    /// 中央ディレクトリ(末尾にある)は見ない。見ようとすると結局ファイル全体が要るため、
    /// local file header を先頭から順に辿る。
    private static func readEntries(head: Data, wanted: Set<String>) throws -> [String: Data] {
        // Data の添字は元のインデックスを引き継ぐので、必ず先頭からの相対で扱う。
        let bytes = [UInt8](head)
        guard bytes.count >= 4, bytes[0] == 0x50, bytes[1] == 0x4B,
              bytes[2] == 0x03, bytes[3] == 0x04 else {
            throw VoicevoxVoiceModelFileInspectorError.notAZipFile
        }

        func value(at offset: Int, bytes count: Int) -> UInt64 {
            var result: UInt64 = 0
            for index in stride(from: count - 1, through: 0, by: -1) {
                result = (result << 8) | UInt64(bytes[offset + index])
            }
            return result
        }

        var found: [String: Data] = [:]
        var offset = 0
        while offset + 30 <= bytes.count,
              bytes[offset] == 0x50, bytes[offset + 1] == 0x4B,
              bytes[offset + 2] == 0x03, bytes[offset + 3] == 0x04 {
            let method = Int(value(at: offset + 8, bytes: 2))
            let compressedSize = Int(value(at: offset + 18, bytes: 4))
            let uncompressedSize = Int(value(at: offset + 22, bytes: 4))
            let nameLength = Int(value(at: offset + 26, bytes: 2))
            let extraLength = Int(value(at: offset + 28, bytes: 2))

            let nameStart = offset + 30
            guard nameStart + nameLength <= bytes.count else {
                throw VoicevoxVoiceModelFileInspectorError.truncated("file name")
            }
            let name = String(decoding: bytes[nameStart ..< nameStart + nameLength], as: UTF8.self)
            let bodyStart = nameStart + nameLength + extraLength

            if wanted.contains(name) {
                guard method == 0 else {
                    throw VoicevoxVoiceModelFileInspectorError.unexpectedCompression(name)
                }
                guard bodyStart + uncompressedSize <= bytes.count else {
                    throw VoicevoxVoiceModelFileInspectorError.truncated(name)
                }
                found[name] = Data(bytes[bodyStart ..< bodyStart + uncompressedSize])
                if found.count == wanted.count { return found }
            }
            let next = bodyStart + compressedSize
            // 進まなくなったら無限ループになるので打ち切る(壊れたファイル対策)。
            guard next > offset else { break }
            offset = next
        }
        return found
    }
}
