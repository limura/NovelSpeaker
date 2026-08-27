//
//  RubyNotationExtractorTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2026/08/27.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker

class RubyNotationExtractorTest: XCTestCase {

    func find(_ text:String) -> [String] {
        return RubyNotationExtractor.FindRubyNotationArray(text: text).map({ "\($0.before)→\($0.after)" })
    }

    // MARK: - 区切り記号があるもの

    func testVerticalBarWithVariousBrackets() throws {
        // ことせかい がダウンロード時に作る形式
        XCTAssertEqual(find("彼は|魔導書(グリモワール)を開いた。"), ["魔導書→グリモワール"])
        // 小説家になろう の記法
        XCTAssertEqual(find("彼は｜魔導書《グリモワール》を開いた。"), ["魔導書→グリモワール"])
        XCTAssertEqual(find("彼は|魔導書《グリモワール》を開いた。"), ["魔導書→グリモワール"])
        XCTAssertEqual(find("彼は｜魔導書（グリモワール）を開いた。"), ["魔導書→グリモワール"])
        // 区切り記号がある場合はルビ側が仮名でなくても拾う(当て字)
        XCTAssertEqual(find("|本気(Serious)"), ["本気→Serious"])
        // 読み替え前が漢字でなくても拾う
        XCTAssertEqual(find("|あいつ(あのひと)"), ["あいつ→あのひと"])
    }

    func testMultipleNotationInOneText() throws {
        XCTAssertEqual(
            find("|剣聖(ソードマスター)と|竜王(ドラゴンキング)が戦う。"),
            ["剣聖→ソードマスター", "竜王→ドラゴンキング"])
    }

    // MARK: - 区切り記号が無いもの

    func testKanjiRunWithKuroKakko() throws {
        // 《》 は本文中の普通の記号ではないので、漢字の後ろにあればルビと見なす
        XCTAssertEqual(find("彼は魔導書《グリモワール》を開いた。"), ["魔導書→グリモワール"])
        // 《》 ならルビ側が仮名でなくてもよい
        XCTAssertEqual(find("魔導書《Grimoire》"), ["魔導書→Grimoire"])
        // 漢字が前に無ければルビではない
        XCTAssertEqual(find("あいつ《あのひと》"), [])
    }

    func testKanjiRunWithParenthesis() throws {
        // 丸括弧は本文中の括弧書きと紛らわしいので、中身が仮名の時だけルビと見なす
        XCTAssertEqual(find("彼は魔導書(グリモワール)を開いた。"), ["魔導書→グリモワール"])
        XCTAssertEqual(find("彼は魔導書（ぐりもわーる）を開いた。"), ["魔導書→ぐりもわーる"])
        // 中身が仮名でない括弧書きはルビではない(ここを拾ってしまうと本文中の注釈を全部誤検出する)
        XCTAssertEqual(find("東京(23区)へ向かった。"), [])
        XCTAssertEqual(find("設定(Settings)を開く。"), [])
    }

    func testKanjiRunLength() throws {
        // 直前に続いている漢字を全部読み替え前とする。
        // 平仮名や読点は漢字ではないので、そこで止まる(小説家になろう のルビの扱いと同じ)
        XCTAssertEqual(find("その古代魔導書《グリモワール》"), ["古代魔導書→グリモワール"])
        XCTAssertEqual(find("その、古代魔導書《グリモワール》"), ["古代魔導書→グリモワール"])
        XCTAssertEqual(find("彼は魔導書《グリモワール》"), ["魔導書→グリモワール"])
        // 々 は漢字の一部として扱う
        XCTAssertEqual(find("その人々《ひとびと》"), ["人々→ひとびと"])
        // 漢字が延々と続いていても、遡る長さには上限がある
        let longKanji = String(repeating: "魔", count: 30)
        let found = RubyNotationExtractor.FindRubyNotationArray(text: "\(longKanji)《よみ》")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.before.count, RubyNotationExtractor.maxKanjiRunCharacterCount)
        XCTAssertEqual(found.first?.after, "よみ")
    }

    // MARK: - ルビとして扱わないもの

    func testNotRubyNotation() throws {
        // 閉じ括弧が無い
        XCTAssertEqual(find("|魔導書(グリモワール"), [])
        // 中身が空
        XCTAssertEqual(find("|魔導書()"), [])
        // 読み替え前が空
        XCTAssertEqual(find("|(グリモワール)"), [])
        // 改行を跨ぐものは拾わない
        XCTAssertEqual(find("|魔導書\n(グリモワール)"), [])
        XCTAssertEqual(find("|魔導書(グリモ\nワール)"), [])
    }

    func testTooLongNotationIsIgnored() throws {
        // 文章まるごとにルビが振られているようなものは相手にしない
        let longBefore = String(repeating: "あ", count: 200)
        XCTAssertEqual(find("|\(longBefore)(よみ)"), [])
    }

    func testSurrogatePairAndEmojiDoesNotBreakScan() throws {
        // 絵文字(4バイト文字)や結合文字が混ざっていても、その後ろのルビが壊れずに拾えること。
        // (NSRange と Character の数がずれる問題に引っかからない事の確認)
        XCTAssertEqual(find("🐉😀𩸽 の話。|魔導書(グリモワール)"), ["魔導書→グリモワール"])
        // 絵文字の直後の 《》 は漢字が前に無いのでルビにならない
        XCTAssertEqual(find("🐉《どらごん》"), [])
    }

    // MARK: - 集計

    func testMarkPartOfOtherCandidate() throws {
        var candidates = [
            RubyNotationCandidate(before: "魔導", after: "まどう"),
            RubyNotationCandidate(before: "魔導書", after: "グリモワール"),
            RubyNotationCandidate(before: "竜王", after: "ドラゴンキング"),
        ]
        RubyNotationExtractor.markPartOfOtherCandidate(&candidates)
        XCTAssertTrue(candidates[0].isPartOfOtherCandidate, "「魔導」は「魔導書」の一部なので印が付く")
        XCTAssertFalse(candidates[1].isPartOfOtherCandidate, "「魔導書」は他のどれの一部でもない")
        XCTAssertFalse(candidates[2].isPartOfOtherCandidate, "「竜王」は他のどれの一部でもない")
    }

    func testSortByBareChapterCount() throws {
        var few = RubyNotationCandidate(before: "少", after: "すく")
        few.bareChapterCount = 3
        few.bareCount = 10
        var many = RubyNotationCandidate(before: "多", after: "おお")
        many.bareChapterCount = 100
        many.bareCount = 5
        let sorted = RubyNotationExtractor.Sort(candidates: [few, many], sortType: .bareChapterCount)
        XCTAssertEqual(sorted.first?.before, "多", "裸の出現章数が多い方が上に来る")

        let sortedByCount = RubyNotationExtractor.Sort(candidates: [many, few], sortType: .bareCount)
        XCTAssertEqual(sortedByCount.first?.before, "少", "裸の出現回数が多い方が上に来る")
    }
}
