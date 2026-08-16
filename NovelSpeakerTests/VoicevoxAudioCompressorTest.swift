//
//  VoicevoxAudioCompressorTest.swift
//  NovelSpeakerTests
//
//  ディスクに貯める音声の圧縮のテスト。
//
//  VOICEVOX が返す WAV は 24kHz/mono/16bit で、1秒あたり約48KB。
//  1作品を丸ごと貯めると数百MB〜GB級になり、そのままでは置けない。
//  AAC に落とすと約1/10になる(20分で 57MB → 5MB程度)。
//
//  再生側(VoicevoxSpeaker)は Data を一時ファイルに書いて AVAudioFile で読むので、
//  m4a のまま渡しても再生できる。よってここでは
//   - 圧縮した物が AVAudioFile で読める事(=再生できる事)
//   - 長さが保たれる事(合計時間の集計と、再生位置の計算に効く)
//  を担保する。
//

import XCTest
import AVFoundation
@testable import NovelSpeaker

class VoicevoxAudioCompressorTest: XCTestCase {

    private let sampleRate = 24000

    /// VOICEVOX の出力と同じ 24kHz/mono/16bit の WAV を作る。
    private func makeWav(seconds: Double) -> Data {
        let sampleCount = Int(Double(sampleRate) * seconds)
        var payload = Data()
        payload.reserveCapacity(sampleCount * 2)
        for i in 0..<sampleCount {
            // 無音だと圧縮が効き過ぎて「本当に音が入っているか」の確認にならないので、
            // 440Hz 相当の波を入れておく。
            let value = Int16(sin(Double(i) * 2.0 * Double.pi * 440.0 / Double(sampleRate)) * 12000)
            payload.append(UInt8(truncatingIfNeeded: value))
            payload.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        return VoicevoxAudioCompressorTest.wavData(payload: payload, sampleRate: sampleRate)
    }

    static func wavData(payload: Data, sampleRate: Int) -> Data {
        var data = Data()
        func appendUInt32(_ value: UInt32) {
            data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff)); data.append(UInt8((value >> 24) & 0xff))
        }
        func appendUInt16(_ value: UInt16) {
            data.append(UInt8(value & 0xff)); data.append(UInt8((value >> 8) & 0xff))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + payload.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func durationSeconds(ofEncoded data: Data) throws -> Double {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + VoicevoxDiskCacheStore.fileExtension)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // 圧縮した物が「再生できる音声」である事。
    // 再生側は Data を一時ファイルに書いて AVAudioFile で読むので、これが通れば再生できる。
    func testEncodedDataIsReadableAsAudio() throws {
        let encoded = try VoicevoxAudioCompressor.encode(wav: makeWav(seconds: 1.0))
        XCTAssertFalse(encoded.isEmpty)
        let duration = try durationSeconds(ofEncoded: encoded)
        XCTAssertEqual(duration, 1.0, accuracy: 0.1)
    }

    // 十分に小さくなる事(これが目的なので、効いていなければ意味が無い)。
    // 生は 1秒あたり約48KB。
    func testEncodedDataIsMuchSmallerThanWav() throws {
        let wav = makeWav(seconds: 5.0)
        let encoded = try VoicevoxAudioCompressor.encode(wav: wav)
        XCTAssertLessThan(encoded.count, wav.count / 4, "生のWAVの1/4未満にはなるはず")
    }

    // 長さが保たれる事。ここがずれると、貯めた合計時間(管理画面の「何分ぶん」)も
    // 再生位置の計算も狂う。
    func testDurationIsPreserved() throws {
        for seconds in [0.5, 3.0, 12.0] {
            let encoded = try VoicevoxAudioCompressor.encode(wav: makeWav(seconds: seconds))
            let duration = try durationSeconds(ofEncoded: encoded)
            XCTAssertEqual(duration, seconds, accuracy: 0.15, "\(seconds)秒の音声で長さが変わった")
        }
    }

    // WAV から長さを求められる事(保存時にファイル名へ書く値になる)。
    func testDurationSecondsOfWav() {
        XCTAssertEqual(VoicevoxAudioCompressor.durationSeconds(wav: makeWav(seconds: 2.5)), 2.5, accuracy: 0.01)
        XCTAssertEqual(VoicevoxAudioCompressor.durationSeconds(wav: Data()), 0, accuracy: 0.001)
    }

    // 壊れた入力で落ちない事(合成に失敗した場合など)。
    func testInvalidWavThrows() {
        XCTAssertThrowsError(try VoicevoxAudioCompressor.encode(wav: Data([0x00, 0x01, 0x02])))
    }

    // 極端に短い物でも扱える事(「あ」だけのブロック等)。
    func testVeryShortAudioIsHandled() throws {
        let encoded = try VoicevoxAudioCompressor.encode(wav: makeWav(seconds: 0.05))
        XCTAssertFalse(encoded.isEmpty)
    }
}
