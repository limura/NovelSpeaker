//
//  VoicevoxAudioCompressor.swift
//  NovelSpeaker
//
//  ディスクに貯める音声を AAC に圧縮する。
//
//  VOICEVOX が返す WAV は 24kHz/mono/16bit で 1秒あたり約48KB。
//  1作品を丸ごと貯めると数百MB〜GB級になるので、そのままでは置けない。
//  AAC(32kbps mono)なら約1/10(20分で 57MB → 5MB程度)に収まる。
//
//  再生側(VoicevoxSpeaker)は Data を一時ファイルへ書いて AVAudioFile で読むので、
//  m4a のまま渡してもそのまま再生できる。復号は不要。
//

import Foundation
import AVFoundation

enum VoicevoxAudioCompressorError: Error {
    case invalidWav
    case encodeFailed(String)
}

enum VoicevoxAudioCompressor {

    /// 圧縮後のビットレート。音声(単一話者のナレーション)なので 32kbps でも実用上十分。
    static let bitRate = 32000

    /// WAV(24kHz/mono/16bit)を AAC(.m4a)に圧縮する。
    static func encode(wav: Data) throws -> Data {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let sourceURL = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        let destinationURL = temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + VoicevoxDiskCacheStore.fileExtension)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }

        do {
            try wav.write(to: sourceURL)
        } catch {
            throw VoicevoxAudioCompressorError.encodeFailed(error.localizedDescription)
        }

        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            // WAV として読めない = 合成に失敗している。
            throw VoicevoxAudioCompressorError.invalidWav
        }

        let format = sourceFile.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: bitRate,
        ]

        do {
            let destinationFile = try AVAudioFile(forWriting: destinationURL, settings: settings)
            // 一度に全部読むとメモリを食うので、1秒ぶんずつ流し込む。
            let chunkFrameCount = AVAudioFrameCount(format.sampleRate)
            while sourceFile.framePosition < sourceFile.length {
                let remaining = AVAudioFrameCount(sourceFile.length - sourceFile.framePosition)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: min(chunkFrameCount, remaining)) else {
                    throw VoicevoxAudioCompressorError.encodeFailed("PCMバッファを作れませんでした")
                }
                try sourceFile.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try destinationFile.write(from: buffer)
            }
        } catch let error as VoicevoxAudioCompressorError {
            throw error
        } catch {
            throw VoicevoxAudioCompressorError.encodeFailed(error.localizedDescription)
        }

        do {
            return try Data(contentsOf: destinationURL)
        } catch {
            throw VoicevoxAudioCompressorError.encodeFailed(error.localizedDescription)
        }
    }

    /// WAV(24kHz/mono/16bit・44バイトヘッダ)の再生時間。
    /// 保存時にファイル名へ書き込む値になる。
    static func durationSeconds(wav: Data) -> Double {
        guard wav.count > VoicevoxPerformanceMonitor.wavHeaderByteCount else { return 0 }
        let payloadBytes = wav.count - VoicevoxPerformanceMonitor.wavHeaderByteCount
        return Double(payloadBytes) / (VoicevoxPerformanceMonitor.outputSampleRate * VoicevoxPerformanceMonitor.outputBytesPerFrame)
    }
}
