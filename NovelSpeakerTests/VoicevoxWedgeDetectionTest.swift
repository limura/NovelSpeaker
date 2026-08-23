//
//  VoicevoxWedgeDetectionTest.swift
//  NovelSpeakerTests
//
//  「発話中のつもりなのに、音も出ず合成もしていない」状態の判定。
//
//  ★2026-08-21 に実機で起きた事故:
//   無音の報告が5回続いた後ぱたりと止まり(=再生が二度と始まらない)、6分ほど無音のまま。
//   アプリ自体は生きていて音声の作り置きは動き続けていた。
//   利用者が再生ボタンを押すと即座に復帰した。
//   それまで VOICEVOX は固着検出の対象外(`if type == "VOICEVOX" { return }`)だったため、
//   誰も気付けず、手で直すしかなかった。
//
//  誤検出は実害が大きい(長いブロックの合成を固着と誤認して延々作り直し、CPUと電池を焼く)
//  ので、「合成中は固着ではない」を特に固めておく。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxWedgeDetectionTest: XCTestCase {

    /// 既定は「固着している」状態。各テストで1つだけ崩して、判定が false になる事を見る。
    private func isWedged(isSpeaking: Bool = true,
                          isSameGeneration: Bool = true,
                          didWillSpeakRangeProgress: Bool = false,
                          didBlockMove: Bool = false,
                          isPlaybackSynthesisPending: Bool = false,
                          isAudioSessionInterrupted: Bool = false) -> Bool {
        return SpeechBlockSpeaker.isVoicevoxWedged(
            isSpeaking: isSpeaking,
            isSameGeneration: isSameGeneration,
            didWillSpeakRangeProgress: didWillSpeakRangeProgress,
            didBlockMove: didBlockMove,
            isPlaybackSynthesisPending: isPlaybackSynthesisPending,
            isAudioSessionInterrupted: isAudioSessionInterrupted)
    }

    // ★音楽アプリ等に音声セッションを取られている最中は固着ではない。
    //
    // 実機で確認された症状: ことせかい で読み上げ中に音楽アプリで再生を始めると、
    // 15〜30秒ほどしてから ことせかい が「止まっている」と誤判断して再生し直し、
    // 音声セッションを奪い返して**音楽アプリの再生を止めてしまう**。
    // (利用者から見ると「再生ボタンを押したのに再生が始まらない」)
    // 取られている間は、止まっているのが正常。
    func testDoesNotFireWhileTheAudioSessionIsTakenByAnotherApp() {
        XCTAssertFalse(isWedged(isAudioSessionInterrupted: true),
                       "他アプリに音を取られている間に再生し直すと、そちらの再生を止めてしまう")
    }

    // 取られていない時は、これまでどおり検出する(上の逃げ道で全部素通りしない事)。
    func testStillDetectsWhenTheSessionIsNotInterrupted() {
        XCTAssertTrue(isWedged(isAudioSessionInterrupted: false))
    }

    // 既定は「取られていない」。誰も立てなければ従来どおり動く事。
    func testInterruptedFlagDefaultsToFalse() {
        XCTAssertFalse(SpeechBlockSpeaker.isAudioSessionInterrupted)
    }

    // ★実機で起きた状態。発話中のつもりで、何も進まず、合成もしていない。
    func testDetectsTheRealDeviceStall() {
        XCTAssertTrue(isWedged(), "発話中のつもりで何も起きていないなら固着と判断すべき")
    }

    // ★これが一番大事。長いブロックの合成中は何も起きないのが正常。
    // ここを誤検出すると、合成を延々作り直して CPU と電池を焼く。
    func testDoesNotFireWhileSynthesisIsInFlight() {
        XCTAssertFalse(isWedged(isPlaybackSynthesisPending: true),
                       "合成中は正常。固着と判断してはいけない")
    }

    // CPU予算待ちで待たされている間も isPlaybackSynthesisPending は true になる。
    // 背面では最大2分ほど待つ事があるので、ここを取り違えると必ず誤検出する。
    func testDoesNotFireWhileWaitingForCPUBudget() {
        XCTAssertFalse(isWedged(isPlaybackSynthesisPending: true))
    }

    // 発話位置が進んでいれば動いている。
    func testDoesNotFireWhenSpeechProgressed() {
        XCTAssertFalse(isWedged(didWillSpeakRangeProgress: true))
    }

    // 次のブロックへ移っていれば動いている。
    func testDoesNotFireWhenBlockMoved() {
        XCTAssertFalse(isWedged(didBlockMove: true))
    }

    // 止めた後は見張る必要が無い。
    func testDoesNotFireWhenNotSpeaking() {
        XCTAssertFalse(isWedged(isSpeaking: false))
    }

    // 停止→同じブロックで再生し直し、を跨いだ誤回復を防ぐ。
    func testDoesNotFireAfterGenerationChanged() {
        XCTAssertFalse(isWedged(isSameGeneration: false),
                       "世代が変わった watcher は現役ではない")
    }

    // 条件が複数崩れていても当然 false。
    func testDoesNotFireWhenSeveralConditionsAreHealthy() {
        XCTAssertFalse(isWedged(didWillSpeakRangeProgress: true, isPlaybackSynthesisPending: true))
    }
}
