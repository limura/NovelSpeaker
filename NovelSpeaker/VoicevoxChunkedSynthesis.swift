//
//  VoicevoxChunkedSynthesis.swift
//  NovelSpeaker
//
//  1本の合成が背面の CPU 予算(60秒窓×割合)に収まらない場合に、句読点で分割して
//  合成し、出来た音声を繋いで1つのブロックとして扱うための道具立て。
//
//  分割は「最後の手段」である事:
//  分割して別々に合成した音声を繋ぐと、一度に合成した場合と比べて繋ぎ目に
//  気になる「間」ができる(VOICEVOX が発話の前後に無音を付けるため)。
//  音質のためには分割しないのが最善なので、分割は「そうしないと背面では合成できない」
//  時だけ行う。判断の閾値は端末の実測から決まる:
//    iPhone 17 Pro Max      ≒ 0.13 秒/文字 → 300文字超まで分割不要(実質起きない)
//    iPhone SE2 (低電力)    ≒ 0.33〜0.8 秒/文字 → 100文字級でも分割が必要
//
//  繋ぎ目の「間」は、自分で作った分割位置に限って前後の無音を削って緩和する。
//  ブロック全体の先頭・末尾の無音には触らない(そこは元々の発話の一部なので)。
//

import Foundation

enum VoicevoxTextChunker {

    /// そこで区切っても不自然になりにくい文字。
    /// StoryTextClassifier のブロック分割と同じ考え方(句読点・改行・空白)。
    static let boundaryCharacters: Set<Character> = ["。", "、", "！", "？", "!", "?", "\n", "．", "，", " ", "　"]

    /// これ以上細かくは分割しない長さ。
    ///
    /// 合成には文字数に依らない固定費がある(実機の iPhone SE2 低電力では20秒超)。
    /// 細かく分けるほど固定費を何度も払う事になり、合計 CPU 時間はむしろ増える。
    /// 実機では 102文字が8分割、132文字が9分割まで細かくなり、1ブロックの発話に
    /// 5分以上かかる状態になっていた。分割は「予算に収めるための最後の手段」なので、
    /// 収まらないとしてもここより細かくはしない(収まらない分は待って対処する)。
    static let defaultMinimumCharacterCount = 40

    /// テキストを、各断片が maxCharacterCount 以下になるように句読点で分割する。
    /// 上限に収まっているなら分割しない(そのまま1つで返す)。
    /// - Parameter minimumCharacterCount: これ以上細かくは分割しない長さ。
    static func split(text: String, maxCharacterCount: Int, minimumCharacterCount: Int = defaultMinimumCharacterCount) -> [String] {
        if text.isEmpty { return [] }
        let limit = max(1, max(maxCharacterCount, minimumCharacterCount))
        if text.count <= limit { return [text] }

        // 予算に収まる範囲で最も少ない個数に分け、その個数で長さを揃える。
        // 合成の固定費は断片の長さに関係なく毎回かかるので、個数が少ないほど、
        // また極端に短い断片が無いほど有利になる
        // (上限一杯で切っていくと末尾だけ数文字、という分け方になり、その数文字にも
        //  丸ごと固定費がかかってしまう)。
        let pieceCount = Int((Double(text.count) / Double(limit)).rounded(.up))
        let balancedLimit = max(1, Int((Double(text.count) / Double(pieceCount)).rounded(.up)))

        var result: [String] = []
        var remaining = Substring(text)
        while remaining.count > balancedLimit {
            let windowEnd = remaining.index(remaining.startIndex, offsetBy: balancedLimit)
            let window = remaining[remaining.startIndex..<windowEnd]
            // 上限の範囲内で一番後ろにある区切り文字の直後で切る(できるだけ長く取り、
            // 繋ぎ目の数を減らす)。一つも無ければ諦めて上限位置でぶつ切りにする。
            var cutIndex = windowEnd
            var searchIndex = window.endIndex
            while searchIndex > window.startIndex {
                searchIndex = window.index(before: searchIndex)
                if boundaryCharacters.contains(window[searchIndex]) {
                    cutIndex = window.index(after: searchIndex)
                    break
                }
            }
            result.append(String(remaining[remaining.startIndex..<cutIndex]))
            remaining = remaining[cutIndex...]
        }
        if remaining.isEmpty == false {
            result.append(String(remaining))
        }
        return mergingWhitespaceOnlyChunks(result)
    }

    /// 空白・改行だけの断片を隣へ合流させる。
    /// VOICEVOX は発話しうる文字が無いテキストを渡されると
    /// 「入力テキストの解析に失敗しました」で合成に失敗するため、単独では出さない。
    /// (実機の本文が "\n\u{3000}意外な状況で…" のように改行+全角空白で始まっており、
    ///  上限内の最後の区切り文字が全角空白だったために発生した)
    private static func mergingWhitespaceOnlyChunks(_ chunks: [String]) -> [String] {
        var result: [String] = []
        var carried = ""
        for chunk in chunks {
            let merged = carried + chunk
            if merged.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // まだ発話しうる文字が無いので、次の断片へ持ち越す。
                carried = merged
                continue
            }
            carried = ""
            result.append(merged)
        }
        if carried.isEmpty == false {
            // 末尾が空白だけだった場合は、最後の断片にくっつける(捨てない)。
            if let last = result.popLast() {
                result.append(last + carried)
            } else {
                result.append(carried)
            }
        }
        return result
    }
}

/// 分割して合成した WAV を1本に繋ぐ。
/// 入力は voicevox の出力(24kHz/mono/16bit PCM)を想定しているが、
/// フォーマットは先頭の WAV から読み取って使う。
enum VoicevoxWavJoiner {

    struct ParsedWav {
        let sampleRate: Int
        let channelCount: Int
        let bitsPerSample: Int
        let payload: Data
    }

    /// 繋ぎ目で削ってよい無音の最大長(秒)。これ以上は削らない
    /// (「、」等での自然な間まで消してしまうと、逆に忙しない発話になる)。
    private static let maxTrimSeconds = 0.25
    /// 無音と見なす振幅(16bit のフルスケール32767に対して十分小さい値)。
    private static let silenceAmplitudeThreshold: Int16 = 64

    static func parse(wav: Data) -> ParsedWav? {
        guard wav.count >= 44,
              wav.prefix(4).elementsEqual("RIFF".utf8),
              wav.dropFirst(8).prefix(4).elementsEqual("WAVE".utf8) else { return nil }

        func readUInt32(at offset: Int) -> UInt32? {
            guard offset + 4 <= wav.count else { return nil }
            let bytes = Array(wav[wav.startIndex.advanced(by: offset)..<wav.startIndex.advanced(by: offset + 4)])
            return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
        }
        func readUInt16(at offset: Int) -> UInt16? {
            guard offset + 2 <= wav.count else { return nil }
            let bytes = Array(wav[wav.startIndex.advanced(by: offset)..<wav.startIndex.advanced(by: offset + 2)])
            return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        }
        func chunkId(at offset: Int) -> String? {
            guard offset + 4 <= wav.count else { return nil }
            return String(bytes: wav[wav.startIndex.advanced(by: offset)..<wav.startIndex.advanced(by: offset + 4)], encoding: .ascii)
        }

        var channelCount = 0
        var sampleRate = 0
        var bitsPerSample = 0
        var payload: Data? = nil
        // RIFF は "fmt " や "data" 以外のチャンク(LIST等)を含み得るので、順に辿る。
        var offset = 12
        while offset + 8 <= wav.count {
            guard let id = chunkId(at: offset), let size = readUInt32(at: offset + 4) else { return nil }
            let bodyOffset = offset + 8
            let bodySize = Int(size)
            guard bodyOffset + bodySize <= wav.count else { break }
            if id == "fmt " && bodySize >= 16 {
                channelCount = Int(readUInt16(at: bodyOffset + 2) ?? 0)
                sampleRate = Int(readUInt32(at: bodyOffset + 4) ?? 0)
                bitsPerSample = Int(readUInt16(at: bodyOffset + 14) ?? 0)
            } else if id == "data" {
                payload = wav.subdata(in: wav.startIndex.advanced(by: bodyOffset)..<wav.startIndex.advanced(by: bodyOffset + bodySize))
            }
            // チャンクは偶数境界に揃う。
            offset = bodyOffset + bodySize + (bodySize % 2)
        }
        guard let payload = payload, channelCount > 0, sampleRate > 0, bitsPerSample == 16 else { return nil }
        return ParsedWav(sampleRate: sampleRate, channelCount: channelCount, bitsPerSample: bitsPerSample, payload: payload)
    }

    /// - Parameter trimJoinSilence: 分割位置の無音を削るか。
    ///   既定は true。false は「削らないとどう聞こえるか」を聞き比べるための debug 用。
    static func join(wavs: [Data], trimJoinSilence: Bool = true) -> Data? {
        guard wavs.isEmpty == false else { return nil }
        // 1本だけなら一切加工せずそのまま返す(触らないのが最善)。
        if wavs.count == 1 {
            return parse(wav: wavs[0]) == nil ? nil : wavs[0]
        }
        var parsedList: [ParsedWav] = []
        for wav in wavs {
            guard let parsed = parse(wav: wav) else { return nil }
            parsedList.append(parsed)
        }
        guard let first = parsedList.first else { return nil }
        let bytesPerFrame = first.channelCount * first.bitsPerSample / 8
        let maxTrimBytes = Int(Double(first.sampleRate) * maxTrimSeconds) * bytesPerFrame

        var joined = Data()
        for (index, parsed) in parsedList.enumerated() {
            // 自分で作った分割位置(=断片の内側の境界)だけ無音を削る。
            let trimLeading = trimJoinSilence && index > 0
            let trimTrailing = trimJoinSilence && index < parsedList.count - 1
            joined.append(trimmedPayload(parsed.payload,
                                         trimLeading: trimLeading,
                                         trimTrailing: trimTrailing,
                                         maxTrimBytes: maxTrimBytes,
                                         bytesPerFrame: bytesPerFrame))
        }
        return wavData(payload: joined, format: first)
    }

    /// 前後の無音を削る。削り過ぎて音声を消してしまわないよう、削る量には上限を設ける。
    private static func trimmedPayload(_ payload: Data, trimLeading: Bool, trimTrailing: Bool, maxTrimBytes: Int, bytesPerFrame: Int) -> Data {
        guard payload.count >= bytesPerFrame else { return payload }
        let samples = payload.withUnsafeBytes { raw -> [Int16] in
            let count = payload.count / 2
            var result = [Int16](repeating: 0, count: count)
            for i in 0..<count {
                let low = Int16(raw[i * 2])
                let high = Int16(bitPattern: UInt16(raw[i * 2 + 1]) << 8)
                result[i] = high | low
            }
            return result
        }
        let maxTrimSamples = maxTrimBytes / 2
        var start = 0
        var end = samples.count
        if trimLeading {
            let limit = min(maxTrimSamples, samples.count)
            while start < limit && abs(Int(samples[start])) <= Int(silenceAmplitudeThreshold) {
                start += 1
            }
        }
        if trimTrailing {
            let limit = max(start, samples.count - maxTrimSamples)
            while end > limit && abs(Int(samples[end - 1])) <= Int(silenceAmplitudeThreshold) {
                end -= 1
            }
        }
        guard start < end else { return payload }
        return payload.subdata(in: payload.startIndex.advanced(by: start * 2)..<payload.startIndex.advanced(by: end * 2))
    }

    private static func wavData(payload: Data, format: ParsedWav) -> Data {
        var data = Data()
        func appendUInt32(_ value: UInt32) {
            data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff)); data.append(UInt8((value >> 24) & 0xff))
        }
        func appendUInt16(_ value: UInt16) {
            data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
        }
        let bytesPerFrame = format.channelCount * format.bitsPerSample / 8
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + payload.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(UInt16(format.channelCount))
        appendUInt32(UInt32(format.sampleRate))
        appendUInt32(UInt32(format.sampleRate * bytesPerFrame))
        appendUInt16(UInt16(bytesPerFrame))
        appendUInt16(UInt16(format.bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }
}
