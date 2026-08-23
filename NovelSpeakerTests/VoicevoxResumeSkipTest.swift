//
//  VoicevoxResumeSkipTest.swift
//  NovelSpeakerTests
//
//  割り込み(アラーム等)から戻る時に、音声を途中まで飛ばして鳴らす所。
//
//  なぜこの形か:
//  割り込みはブロックの途中で音を奪う。途中の位置から頼み直すと
//  「その位置から末尾まで」が別の本文になり、作り置きが当たらず合成のやり直しになる
//  (実機で「アラームを止めた瞬間に声が出ない」として確認)。
//  かといってブロックの頭から鳴らすと、長いブロックでは200文字ほど聞き直す事になる。
//  そこで **頼むのはブロック丸ごと(作り置きが当たる)・鳴らす時に音声を飛ばす**。
//

import XCTest
import AVFoundation
@testable import NovelSpeaker

class VoicevoxResumeSkipTest: XCTestCase {

    /// 1秒あたり 100 フレームの、値が「フレーム番号」になっている音声を作る。
    /// どこから始まったかが値で分かるようにしてある。
    private func makeBuffer(seconds: Double, sampleRate: Double = 100) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            channel[0][frame] = Float(frame)
        }
        return buffer
    }

    // ★飛ばした分だけ短くなり、中身も飛ばした所から始まる事。
    func testSkippingDropsTheHeadOfTheAudio() throws {
        let source = try makeBuffer(seconds: 10)   // 1000フレーム
        let result = try XCTUnwrap(VoicevoxSpeaker.buffer(source, skippingSeconds: 3))

        XCTAssertEqual(result.frameLength, 700, "3秒(300フレーム)ぶん短くなっているべき")
        let channel = try XCTUnwrap(result.floatChannelData)
        XCTAssertEqual(channel[0][0], 300, accuracy: 0.001, "飛ばした所から始まっていない")
        XCTAssertEqual(channel[0][699], 999, accuracy: 0.001, "末尾まで運べていない")
    }

    // 形式は変えない(同じ経路にそのまま流すため)。
    func testSkippingKeepsTheFormat() throws {
        let source = try makeBuffer(seconds: 10)
        let result = try XCTUnwrap(VoicevoxSpeaker.buffer(source, skippingSeconds: 1))
        XCTAssertEqual(result.format, source.format)
    }

    // 飛ばす必要が無い時は nil(元のバッファをそのまま使う)。
    func testNoSkipReturnsNil() throws {
        let source = try makeBuffer(seconds: 10)
        XCTAssertNil(VoicevoxSpeaker.buffer(source, skippingSeconds: 0))
        XCTAssertNil(VoicevoxSpeaker.buffer(source, skippingSeconds: -1))
    }

    // ★全部飛ばしてしまわない事。ここを取り違えると、戻った瞬間に
    // 「何も鳴らずに次のブロックへ進む」という飛ばし読みになる。
    func testSkippingBeyondTheEndReturnsNil() throws {
        let source = try makeBuffer(seconds: 10)
        XCTAssertNil(VoicevoxSpeaker.buffer(source, skippingSeconds: 10))
        XCTAssertNil(VoicevoxSpeaker.buffer(source, skippingSeconds: 11))
    }

    // 少し手前から鳴らすための重なりは、0 では無い事
    // (ぴったりの位置から鳴らすと、推定位置の誤差で語の途中から始まる)。
    func testResumeOverlapIsNotZero() {
        XCTAssertGreaterThan(VoicevoxSpeaker.resumeOverlapSecondsForTesting, 0)
    }
}
