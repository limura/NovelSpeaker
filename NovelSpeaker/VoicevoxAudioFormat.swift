//
//  VoicevoxAudioFormat.swift
//  NovelSpeaker
//
//  VOICEVOX が返す WAV の形。
//
//  「このバイト数は何秒ぶんの音声か」は、貯金の秒数を数える所や
//  ディスクキャッシュの長さを求める所など、あちこちで必要になる。
//  合成結果は 24kHz / mono / 16bit の WAV で一定なので、
//  ヘッダを除いたバイト数から割り算だけで求まる。
//

import Foundation

enum VoicevoxAudioFormat {
    /// VOICEVOX の出力フォーマット(24kHz / mono / 16bit)。
    static let sampleRate: Double = 24000
    static let bytesPerFrame: Double = 2
    static let wavHeaderByteCount = 44

    /// WAV のバイト数から音声の秒数(1倍速換算)を求める。
    static func audioSeconds(wavByteCount: Int) -> Double {
        let payload = Double(max(0, wavByteCount - wavHeaderByteCount))
        return payload / (sampleRate * bytesPerFrame)
    }
}
