//
//  VoicevoxStyleSelectionTest.swift
//  NovelSpeakerTests
//
//  「音声モデルを消したら話者設定が書き換わって戻らない」を起こさないための固定。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxStyleSelectionTest: XCTestCase {

    private let available: Set<UInt32> = [2, 3, 8, 10]

    // 使えるスタイルはそのまま使える。
    func testAvailableStyleIsAvailable() {
        XCTAssertEqual(
            VoicevoxStyleSelectionResolver.resolve(voiceIdentifier: "3", availableStyleIds: available),
            .available(styleId: 3))
    }

    // ★本命: 音声モデルが未取得なだけの設定を「壊れている」と判定しない事。
    //
    // ここが .notAStyleId になると、呼び出し側が一覧の先頭に書き換えて保存してしまい、
    // 「5.vvm を消したら全部の小説の話者が四国めたんになって、取り直しても戻らない」
    // という取り返しのつかない壊れ方をする。
    func testNotDownloadedStyleIsKeptAsIs() {
        let selection = VoicevoxStyleSelectionResolver.resolve(voiceIdentifier: "22", availableStyleIds: available)
        XCTAssertEqual(selection, .notDownloaded(styleId: 22))
        XCTAssertFalse(selection.canBeRepaired, "未取得なだけの設定を書き換えてはいけない")
        XCTAssertEqual(selection.styleId, 22, "styleId は保たれていなければならない")
    }

    // エンジンを切り替えた残骸は直してよい。
    // (この救済が、そもそも従来の書き換え処理の目的だった)
    func testAVSpeechIdentifierLeftoverCanBeRepaired() {
        let selection = VoicevoxStyleSelectionResolver.resolve(
            voiceIdentifier: "com.apple.voice.compact.ja-JP.Kyoko", availableStyleIds: available)
        XCTAssertEqual(selection, .notAStyleId)
        XCTAssertTrue(selection.canBeRepaired)
        XCTAssertNil(selection.styleId)
    }

    // 空文字も styleId ではない。
    func testEmptyIdentifierCanBeRepaired() {
        XCTAssertEqual(
            VoicevoxStyleSelectionResolver.resolve(voiceIdentifier: "", availableStyleIds: available),
            .notAStyleId)
    }

    // 数字に見えるが数値でない物を、うっかり styleId と見なさない事。
    // ここを緩めると、AVSpeech の識別子の一部が styleId として保存され得る。
    func testLooseNumbersAreNotStyleIds() {
        for identifier in [" 3", "3 ", "-1", "3.0", "0x3", "３"] {
            XCTAssertEqual(
                VoicevoxStyleSelectionResolver.resolve(voiceIdentifier: identifier, availableStyleIds: available),
                .notAStyleId,
                "\"\(identifier)\" を styleId と見なしてはいけない")
        }
    }

    // UInt32("+3") は 3 として解釈される(Swift の仕様)。
    // 実際の保存値に "+3" が現れる事は無く、AVSpeech の識別子は上のテストの通り
    // 弾かれるので、これは害の無い寛容さとして受け入れる。
    // (厳しくする方に倒すと、意味のある設定を「残骸」と誤判定する側に振れてしまう)
    func testLeadingPlusIsAcceptedAsStyleId() {
        XCTAssertEqual(
            VoicevoxStyleSelectionResolver.resolve(voiceIdentifier: "+3", availableStyleIds: available),
            .available(styleId: 3))
    }

    // 一覧が空(音声モデルを1つも持っていない = 同梱をやめた直後の状態)でも、
    // 保存されている styleId を壊さない事。
    func testNothingAvailableStillKeepsSavedStyleId() {
        let selection = VoicevoxStyleSelectionResolver.resolve(voiceIdentifier: "3", availableStyleIds: [])
        XCTAssertEqual(selection, .notDownloaded(styleId: 3))
        XCTAssertFalse(selection.canBeRepaired)
    }

    // 未取得の表示は「何かが選ばれている」事が分かる形になっている事。
    func testNotDownloadedLabelShowsWhatIsSelected() {
        let named = VoicevoxStyleSelectionResolver.notDownloadedLabel(styleId: 22, knownName: "ずんだもん - ささやき")
        XCTAssertTrue(named.contains("ずんだもん - ささやき"), "名前が分かるなら見せる")

        // カタログにも無い場合でも、番号だけは見せる(空欄にしない)。
        let unnamed = VoicevoxStyleSelectionResolver.notDownloadedLabel(styleId: 22, knownName: nil)
        XCTAssertTrue(unnamed.contains("22"), "名前が分からなくても番号は見せる: \(unnamed)")
        XCTAssertFalse(unnamed.isEmpty)

        // 名前が空文字でも、番号にフォールバックする。
        let empty = VoicevoxStyleSelectionResolver.notDownloadedLabel(styleId: 22, knownName: "")
        XCTAssertTrue(empty.contains("22"))
    }
}
