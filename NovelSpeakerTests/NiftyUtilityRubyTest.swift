//
//  NiftyUtilityRubyTest.swift
//  NovelSpeakerTests
//
//  ルビタグ(<ruby>...</ruby>)を「|ベース(ルビ)」形式へ変換する
//  ConvertRubyTagToVerticalBarRubyText の回帰テスト。
//

import XCTest
@testable import NovelSpeaker

class NiftyUtilityRubyTest: XCTestCase {

    // <rb>/<rt>/<rp> を含む一般的なルビ。最後の <rt> の後ろに残る閉じ側の <rp>）</rp> の
    // 中身「）」が本文に残ってしまわない事を確認する(残っていたのが今回の不具合)。
    func testRubyWithRbAndRpTags() {
        let input = "<ruby><rb>親譲</rb><rp>（</rp><rt>おやゆず</rt><rp>）</rp></ruby>りの"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: input)
        XCTAssertEqual(result, "|親譲(おやゆず)りの")
    }

    // 連続した rb/rt/rp(1文字ずつ傍点のように振る)でも、末尾に余分な「)」が残らない事。
    func testRubyWithMultipleRbRpSequences() {
        let input = "<ruby><rb>赤</rb><rp>(</rp><rt>・</rt><rp>)</rp><rb>い</rb><rp>(</rp><rt>・</rt><rp>)</rp></ruby>"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: input)
        XCTAssertEqual(result, "|赤(・)|い(・)")
    }

    // rp を含まない単純なルビは従来通り変換される事(回帰防止)。
    func testRubyWithoutRpTags() {
        let input = "<ruby>漢字<rt>かんじ</rt></ruby>"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: input)
        XCTAssertEqual(result, "|漢字(かんじ)")
    }
}
