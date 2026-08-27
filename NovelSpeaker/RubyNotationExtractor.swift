//
//  RubyNotationExtractor.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2026/08/27.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import Foundation
import RealmSwift

/// 小説本文から見つけたルビ表記1つ分。
struct RubyNotationCandidate {
    /// ルビが振られていた側の文字列(読み替え前になる)
    let before:String
    /// ルビとして振られていた文字列(読み替え後になる)
    let after:String
    /// ルビ付きで出てきた回数と、それが何章にわたっていたか
    var rubyCount:Int = 0
    var rubyChapterCount:Int = 0
    /// ルビが振られていない状態(裸)で出てきた回数と、それが何章にわたっていたか。
    /// 「読みの修正として登録したら新たに直る箇所の数」がこれになるので、これが最も重要な指標になる。
    var bareCount:Int = 0
    var bareChapterCount:Int = 0
    /// 裸で出てきた直後が敬称(さん、様、等)だった回数。人名らしさの手がかりに使う。
    var honorificCount:Int = 0
    /// 他の候補の一部になっている(例: 「魔導」が「魔導書」の一部)。
    /// 読み替えは単純な部分文字列の置換なので、こういう語は意図しない所で発火する事を伝えたい。
    var isPartOfOtherCandidate:Bool = false
    /// 最初にルビ付きで出てきた章番号
    var firstChapterNumber:Int = 0

    /// 読み替え前が1文字しかないもの。「王」を登録すると「魔王」の中でも発火してしまうので、既定では隠す。
    var isShortBefore:Bool {
        return before.count <= 1
    }
}

/// 小説本文を全部舐めてルビ表記を集めるやつです。
///
/// 本文は RealmStoryBulk に 100章ずつ deflate + JSON で固めて置かれているので、
/// bulk 単位で読んでは捨てるという形で回します(全部メモリに載せると 1万章で 90MB 近くになるため)。
///
/// 2回本文を舐めます。
///  - パス1: ルビ表記そのものを集める
///  - パス2: パス1で集めた「読み替え前」が、ルビ無しの裸の状態で何回出てくるかを数える
/// パス2は候補語が数千個になるので、1語ずつ検索していたら到底終わりません。
/// Aho-Corasick で全候補語を同時に1パスで数える事で、本文の長さにしか比例しないようにしてあります。
///
/// iPhone SE(第2世代) 実機で 1万章(本文 86MB) を 4.7秒、ピークメモリ 22MB で処理できる事を確認済み。
class RubyNotationExtractor {
    /// 1回のパス2で同時に数える候補語の上限。
    /// Aho-Corasick の遷移表が候補語数に比例して大きくなるので、これを超えたら分割して複数回舐めます。
    /// (そんな小説はまず無いはずですが、青天井にはしておきたくないため)
    static let maxPatternCountPerPass = 4000

    enum ExtractError : Error {
        case canceled
        case novelNotFound
    }

    // MARK: - UTF-8 バイト列の判定

    // ルビ表記の区切り文字を UTF-8 のバイト列のまま判定します。
    // String の Index を進めるのは非常に遅く、NSRegularExpression も NSString への変換が要るので、
    // ここだけはバイト列を直接見る事にしています(実測で正規表現の10倍近く速い)。

    /// '|' か '｜' であればそのバイト数を返します
    @inline(__always) static func rubyStartMarkerLength(_ b:UnsafeBufferPointer<UInt8>, _ i:Int) -> Int {
        if b[i] == 0x7C { return 1 }                                                    // |
        if b[i] == 0xEF, i + 2 < b.count, b[i+1] == 0xBD, b[i+2] == 0x9C { return 3 }    // ｜
        return 0
    }
    /// '《' '(' '（' であればそのバイト数を返します
    @inline(__always) static func rubyOpenBracketLength(_ b:UnsafeBufferPointer<UInt8>, _ i:Int) -> Int {
        if b[i] == 0x28 { return 1 }                                                    // (
        if b[i] == 0xE3, i + 2 < b.count, b[i+1] == 0x80, b[i+2] == 0x8A { return 3 }    // 《
        if b[i] == 0xEF, i + 2 < b.count, b[i+1] == 0xBC, b[i+2] == 0x88 { return 3 }    // （
        return 0
    }
    /// '》' ')' '）' であればそのバイト数を返します
    @inline(__always) static func rubyCloseBracketLength(_ b:UnsafeBufferPointer<UInt8>, _ i:Int) -> Int {
        if b[i] == 0x29 { return 1 }                                                    // )
        if b[i] == 0xE3, i + 2 < b.count, b[i+1] == 0x80, b[i+2] == 0x8B { return 3 }    // 》
        if b[i] == 0xEF, i + 2 < b.count, b[i+1] == 0xBC, b[i+2] == 0x89 { return 3 }    // ）
        return 0
    }
    /// '《' であるかどうか(区切り記号無しのルビ表記は 《》 の時だけ認めるため)
    @inline(__always) static func isKuroKakkoOpen(_ b:UnsafeBufferPointer<UInt8>, _ i:Int) -> Bool {
        return b[i] == 0xE3 && i + 2 < b.count && b[i+1] == 0x80 && b[i+2] == 0x8A
    }

    /// i の位置から始まる3バイト文字のコードポイントを返します(3バイト文字でなければ nil)
    @inline(__always) static func threeByteCodePoint(_ b:UnsafeBufferPointer<UInt8>, _ i:Int) -> UInt32? {
        guard i >= 0, i + 2 < b.count else { return nil }
        let b0 = b[i], b1 = b[i+1], b2 = b[i+2]
        guard b0 >= 0xE0, b0 <= 0xEF, (b1 & 0xC0) == 0x80, (b2 & 0xC0) == 0x80 else { return nil }
        return (UInt32(b0 & 0x0F) << 12) | (UInt32(b1 & 0x3F) << 6) | UInt32(b2 & 0x3F)
    }
    /// 漢字(と、漢字の一部として扱いたい 々 〇)かどうか
    @inline(__always) static func isKanjiCodePoint(_ cp:UInt32) -> Bool {
        if cp == 0x3005 || cp == 0x3007 { return true }         // 々 〇
        if cp >= 0x3400 && cp <= 0x4DBF { return true }         // CJK拡張A
        if cp >= 0x4E00 && cp <= 0x9FFF { return true }         // CJK統合漢字
        if cp >= 0xF900 && cp <= 0xFAFF { return true }         // CJK互換漢字
        return false
    }
    /// 平仮名・片仮名・長音符かどうか
    @inline(__always) static func isKanaCodePoint(_ cp:UInt32) -> Bool {
        if cp >= 0x3041 && cp <= 0x309F { return true }         // 平仮名
        if cp >= 0x30A0 && cp <= 0x30FF { return true }         // 片仮名(長音符 30FC 含む)
        return false
    }

    /// end の直前から遡って、続いている漢字の並びの開始位置を返します。
    /// 漢字が無ければ end を返します。(区切り記号無しの 漢字《かな》 形式のため)
    static let maxKanjiRunCharacterCount = 12
    @inline(__always) static func kanjiRunStart(_ b:UnsafeBufferPointer<UInt8>, before end:Int) -> Int {
        var start = end
        var count = 0
        while count < maxKanjiRunCharacterCount {
            let candidate = start - 3
            guard candidate >= 0, let cp = threeByteCodePoint(b, candidate), isKanjiCodePoint(cp) else { break }
            start = candidate
            count += 1
        }
        return start
    }
    /// バイト列全体が平仮名・片仮名だけで構成されているか
    @inline(__always) static func isAllKana(_ b:UnsafeBufferPointer<UInt8>, _ range:Range<Int>) -> Bool {
        var i = range.lowerBound
        if i >= range.upperBound { return false }
        while i < range.upperBound {
            guard let cp = threeByteCodePoint(b, i), isKanaCodePoint(cp) else { return false }
            i += 3
        }
        return true
    }

    // MARK: - ルビ表記の走査

    /// 読み替え前として長すぎるものは扱わない(文章まるごとにルビが振られている等の事故を弾く)
    static let maxBeforeByteCount = 90
    /// ルビ側も同様に長すぎるものは扱わない
    static let maxAfterByteCount = 120

    /// ルビ表記1つ分の位置情報
    struct RubyNotationRange {
        /// ルビ表記全体(読み替え前の直前の区切り記号や漢字から、閉じ括弧まで)
        let notationRange:Range<Int>
        let beforeRange:Range<Int>
        let afterRange:Range<Int>
    }

    /// i の位置がルビ表記の開始(または閉じ括弧を含む一連の並び)であればその範囲を返します。
    ///
    /// 相手にする形式は以下です(「ルビはルビだけ読む」の実装 StoryTextClassifier.GenerateRubyModString と揃えてあります)。
    ///  - `|読み替え前《ルビ》` `｜読み替え前(ルビ)` … 区切り記号があるものは括弧の種類を問わない
    ///  - `漢字《ルビ》`                              … 区切り記号が無い場合、《》 なら中身を問わない
    ///  - `漢字(ルビ)` `漢字（ルビ）`                  … 丸括弧は本文中の普通の括弧と紛らわしいので、中身が仮名だけの時のみ
    @inline(__always) static func scanRubyNotation(_ b:UnsafeBufferPointer<UInt8>, at i:Int) -> RubyNotationRange? {
        let n = b.count
        let markerLength = rubyStartMarkerLength(b, i)
        let beforeStart:Int
        let notationStart:Int
        let openSearchStart:Int
        if markerLength > 0 {
            beforeStart = i + markerLength
            notationStart = i
            openSearchStart = i + markerLength
        } else {
            // 区切り記号が無い形式は、括弧の位置から漢字を遡って探す形になるので、
            // 「括弧に当たった時」に処理する。ここでは括弧でなければ何もしない。
            guard rubyOpenBracketLength(b, i) > 0 else { return nil }
            let runStart = kanjiRunStart(b, before: i)
            guard runStart < i else { return nil }
            beforeStart = runStart
            notationStart = runStart
            openSearchStart = i
        }
        // 開き括弧を探す。
        // 見つからないまま延々と先まで探しに行くと、括弧の対応が取れていない本文で
        // 全体が O(文字数^2) になってしまうので、長さで打ち切ります。
        var openIndex = openSearchStart
        var openLength = 0
        let openSearchLimit = min(n, openSearchStart + maxBeforeByteCount)
        while openIndex < openSearchLimit {
            if b[openIndex] == 0x0A { break }               // 改行を跨ぐルビは無い
            let length = rubyOpenBracketLength(b, openIndex)
            if length > 0 { openLength = length; break }
            if rubyStartMarkerLength(b, openIndex) > 0 { break }
            openIndex += 1
        }
        guard openLength > 0, openIndex > beforeStart else { return nil }
        // 閉じ括弧を探す
        var closeIndex = openIndex + openLength
        var closeLength = 0
        let closeSearchLimit = min(n, closeIndex + maxAfterByteCount)
        while closeIndex < closeSearchLimit {
            if b[closeIndex] == 0x0A { break }
            let length = rubyCloseBracketLength(b, closeIndex)
            if length > 0 { closeLength = length; break }
            closeIndex += 1
        }
        guard closeLength > 0, closeIndex > openIndex + openLength else { return nil }
        let afterRange = (openIndex + openLength)..<closeIndex
        if markerLength <= 0, !isKuroKakkoOpen(b, openIndex), !isAllKana(b, afterRange) {
            // 区切り記号が無くて 《》 でもない(＝丸括弧)場合、中身が仮名でなければ
            // 単なる本文中の括弧書きなので、ルビとは見なさない。
            return nil
        }
        return RubyNotationRange(
            notationRange: notationStart..<(closeIndex + closeLength),
            beforeRange: beforeStart..<openIndex,
            afterRange: afterRange)
    }

    // MARK: - パス1: ルビ表記を集める

    private struct RubyWork {
        var after:String
        var rubyCount:Int
        var rubyChapterCount:Int
        var lastChapterNumber:Int
        var firstChapterNumber:Int
    }

    /// 文字列1つからルビ表記を取り出します。出てきた順に、重複もそのまま返します。
    static func FindRubyNotationArray(text:String) -> [(before:String, after:String)] {
        var result:[(before:String, after:String)] = []
        var mutableText = text
        mutableText.withUTF8 { buffer in
            let n = buffer.count
            var i = 0
            while i < n {
                guard let found = scanRubyNotation(buffer, at: i) else { i += 1; continue }
                if found.beforeRange.count <= maxBeforeByteCount {
                    let before = String(decoding: UnsafeBufferPointer(rebasing: buffer[found.beforeRange]), as: UTF8.self)
                    let after = String(decoding: UnsafeBufferPointer(rebasing: buffer[found.afterRange]), as: UTF8.self)
                    result.append((before: before, after: after))
                }
                i = found.notationRange.upperBound
            }
        }
        return result
    }

    private static func collectRubyNotation(text:String, chapterNumber:Int, into work:inout [String:RubyWork]) {
        var mutableText = text
        mutableText.withUTF8 { buffer in
            let n = buffer.count
            var i = 0
            while i < n {
                guard let found = scanRubyNotation(buffer, at: i) else { i += 1; continue }
                if found.beforeRange.count <= maxBeforeByteCount {
                    let before = String(decoding: UnsafeBufferPointer(rebasing: buffer[found.beforeRange]), as: UTF8.self)
                    if work[before] != nil {
                        work[before]!.rubyCount += 1
                        if work[before]!.lastChapterNumber != chapterNumber {
                            work[before]!.lastChapterNumber = chapterNumber
                            work[before]!.rubyChapterCount += 1
                        }
                    } else {
                        let after = String(decoding: UnsafeBufferPointer(rebasing: buffer[found.afterRange]), as: UTF8.self)
                        work[before] = RubyWork(after: after, rubyCount: 1, rubyChapterCount: 1, lastChapterNumber: chapterNumber, firstChapterNumber: chapterNumber)
                    }
                }
                i = found.notationRange.upperBound
            }
        }
    }

    // MARK: - パス2: 裸の出現回数を数える

    /// 敬称。裸で出てきた直後にこれが来ていたら人名らしいと見なします。
    static let honorificStringArray = ["さん", "様", "君", "ちゃん", "殿", "氏", "先生", "さま", "くん"]

    /// 複数の文字列を同時に探すための Aho-Corasick。
    /// 遷移表は「パターン中に実際に出てくるバイト」だけに圧縮した上で密な配列にしてあります
    /// (日本語のパターンだと 256 種類中 100 種類程度しか使わないので、表が半分以下になる)。
    fileprivate final class MultiStringMatcher {
        private var byteToSymbol = [Int32](repeating: 0, count: 256)  // 0 は「パターンに出てこないバイト」
        private var symbolCount = 1
        private var transition:[Int32] = []
        private var output:[Int32] = []
        private(set) var nodeCount = 0

        init(patterns:[String]) {
            let patternBytes = patterns.map { Array($0.utf8) }
            for bytes in patternBytes {
                for byte in bytes where byteToSymbol[Int(byte)] == 0 {
                    byteToSymbol[Int(byte)] = Int32(symbolCount)
                    symbolCount += 1
                }
            }
            // goto を作る
            var goto_:[[Int32]] = [[Int32](repeating: -1, count: symbolCount)]
            output = [-1]
            for (patternIndex, bytes) in patternBytes.enumerated() {
                var node = 0
                for byte in bytes {
                    let symbol = Int(byteToSymbol[Int(byte)])
                    let next = goto_[node][symbol]
                    if next < 0 {
                        goto_.append([Int32](repeating: -1, count: symbolCount))
                        output.append(-1)
                        goto_[node][symbol] = Int32(goto_.count - 1)
                        node = goto_.count - 1
                    } else {
                        node = Int(next)
                    }
                }
                // patterns は辞書のキー由来なので重複は無い前提
                output[node] = Int32(patternIndex)
            }
            nodeCount = goto_.count
            // fail を求めつつ、失敗遷移を畳み込んだ密な表にする
            var fail = [Int32](repeating: 0, count: nodeCount)
            var queue:[Int] = []
            for symbol in 0..<symbolCount {
                let next = goto_[0][symbol]
                if next < 0 { goto_[0][symbol] = 0 } else { fail[Int(next)] = 0; queue.append(Int(next)) }
            }
            var queueIndex = 0
            while queueIndex < queue.count {
                let node = queue[queueIndex]; queueIndex += 1
                if output[node] < 0 { output[node] = output[Int(fail[node])] }
                for symbol in 0..<symbolCount {
                    let next = goto_[node][symbol]
                    if next < 0 {
                        goto_[node][symbol] = goto_[Int(fail[node])][symbol]
                    } else {
                        fail[Int(next)] = goto_[Int(fail[node])][symbol]
                        queue.append(Int(next))
                    }
                }
            }
            transition = [Int32](repeating: 0, count: nodeCount * symbolCount)
            for node in 0..<nodeCount {
                for symbol in 0..<symbolCount { transition[node * symbolCount + symbol] = goto_[node][symbol] }
            }
        }

        /// buffer の range の範囲を走査して、パターンが見つかる度に
        /// (パターン番号, 一致した部分の直後の位置) を渡します。
        @inline(__always) func enumerateMatches(_ buffer:UnsafeBufferPointer<UInt8>, range:Range<Int>, state:inout Int, found:(Int, Int)->Void) {
            let symbolCount = self.symbolCount
            byteToSymbol.withUnsafeBufferPointer { symbolTable in
            transition.withUnsafeBufferPointer { transitionTable in
            output.withUnsafeBufferPointer { outputTable in
                var current = state
                var i = range.lowerBound
                while i < range.upperBound {
                    current = Int(transitionTable[current * symbolCount + Int(symbolTable[Int(buffer[i])])])
                    i += 1
                    let patternIndex = outputTable[current]
                    if patternIndex >= 0 { found(Int(patternIndex), i) }
                }
                state = current
            }}}
        }
    }

    // MARK: - 本体

    /// 小説の本文を全部読んで、ルビ表記の一覧を作ります。
    /// 時間がかかるのでバックグラウンドスレッドから呼ぶ事を想定しています。
    ///
    /// - Parameters:
    ///   - novelID: 対象の小説
    ///   - notRubyCharacterString: これらの文字だけで出来ているルビは無視します(既定の「・、 　?？!！」＝傍点等)
    ///   - progress: 0.0〜1.0 の進捗。呼び出し元のスレッドで呼ばれます
    ///   - isCanceled: true を返したら中断します
    /// - Returns: 裸の出現章数の多い順に並べた候補の一覧
    static func Extract(novelID:String, notRubyCharacterString:String, progress:@escaping (Float)->Void, isCanceled:@escaping ()->Bool) throws -> [RubyNotationCandidate] {
        // ---- パス1 ----
        var work:[String:RubyWork] = [:]
        try forEachStory(novelID: novelID, progressRange: 0.0 ..< 0.5, progress: progress, isCanceled: isCanceled) { content, chapterNumber in
            collectRubyNotation(text: content, chapterNumber: chapterNumber, into: &work)
        }

        // ---- 候補の絞り込み ----
        let notRubyCharacterSet = Set(notRubyCharacterString)
        var candidates:[RubyNotationCandidate] = []
        for (before, entry) in work {
            if before.count <= 0 || entry.after.count <= 0 { continue }
            // 読み替えても何も変わらないもの
            if before == entry.after { continue }
            // 傍点(・・・)のような、ルビとして読ませたいわけではないもの
            if entry.after.allSatisfy({ notRubyCharacterSet.contains($0) }) { continue }
            candidates.append(RubyNotationCandidate(
                before: before,
                after: entry.after,
                rubyCount: entry.rubyCount,
                rubyChapterCount: entry.rubyChapterCount,
                firstChapterNumber: entry.firstChapterNumber))
        }
        work.removeAll()
        if candidates.count <= 0 { return [] }
        if isCanceled() { throw ExtractError.canceled }

        // ---- パス2: 裸の出現回数を数える ----
        // 候補が多すぎる時は、Aho-Corasick の遷移表が大きくなりすぎないように分割して数えます。
        let chunkCount = (candidates.count + maxPatternCountPerPass - 1) / maxPatternCountPerPass
        for chunkIndex in 0..<chunkCount {
            let start = chunkIndex * maxPatternCountPerPass
            let end = min(start + maxPatternCountPerPass, candidates.count)
            let patterns = candidates[start..<end].map({ $0.before })
            let matcher = MultiStringMatcher(patterns: patterns)
            var bareCount = [Int](repeating: 0, count: patterns.count)
            var bareChapterCount = [Int](repeating: 0, count: patterns.count)
            var lastChapterNumber = [Int](repeating: -1, count: patterns.count)
            var honorificCount = [Int](repeating: 0, count: patterns.count)
            let honorificBytes = honorificStringArray.map({ Array($0.utf8) })

            let rangeStart = 0.5 + 0.5 * Float(chunkIndex) / Float(chunkCount)
            let rangeEnd = 0.5 + 0.5 * Float(chunkIndex + 1) / Float(chunkCount)
            try forEachStory(novelID: novelID, progressRange: rangeStart ..< rangeEnd, progress: progress, isCanceled: isCanceled) { content, chapterNumber in
                var mutableText = content
                mutableText.withUTF8 { buffer in
                    let n = buffer.count
                    var state = 0
                    // ルビが振られている箇所は「裸」ではないので数えません。
                    // (そこは「ルビはルビだけ読む」で既に正しく読まれるため、登録しても新たな効果が無い)
                    // なので、ルビ表記の位置を探し、その手前までの区間だけをまとめて走査します。
                    var spanStart = 0
                    var i = 0
                    while i < n {
                        guard let found = scanRubyNotation(buffer, at: i) else { i += 1; continue }
                        let spanEnd = max(spanStart, found.notationRange.lowerBound)
                        if spanStart < spanEnd {
                            matcher.enumerateMatches(buffer, range: spanStart..<spanEnd, state: &state) { patternIndex, matchEnd in
                                countBare(patternIndex: patternIndex, matchEnd: matchEnd, chapterNumber: chapterNumber, buffer: buffer, honorificBytes: honorificBytes, bareCount: &bareCount, bareChapterCount: &bareChapterCount, lastChapterNumber: &lastChapterNumber, honorificCount: &honorificCount)
                            }
                        }
                        state = 0
                        i = found.notationRange.upperBound
                        spanStart = i
                    }
                    if spanStart < n {
                        matcher.enumerateMatches(buffer, range: spanStart..<n, state: &state) { patternIndex, matchEnd in
                            countBare(patternIndex: patternIndex, matchEnd: matchEnd, chapterNumber: chapterNumber, buffer: buffer, honorificBytes: honorificBytes, bareCount: &bareCount, bareChapterCount: &bareChapterCount, lastChapterNumber: &lastChapterNumber, honorificCount: &honorificCount)
                        }
                    }
                }
            }
            for index in 0..<patterns.count {
                candidates[start + index].bareCount = bareCount[index]
                candidates[start + index].bareChapterCount = bareChapterCount[index]
                candidates[start + index].honorificCount = honorificCount[index]
            }
        }

        // ---- 他の候補の一部になっているものに印を付ける ----
        markPartOfOtherCandidate(&candidates)

        // 裸の出現章数の多い順(＝登録した時に効く範囲が広い順)
        candidates.sort(by: { CompareByBareChapterCount(lhs: $0, rhs: $1) })
        progress(1.0)
        return candidates
    }

    /// パス2 の中で、一致した1件を数える処理。
    @inline(__always) private static func countBare(patternIndex:Int, matchEnd:Int, chapterNumber:Int, buffer:UnsafeBufferPointer<UInt8>, honorificBytes:[[UInt8]], bareCount:inout [Int], bareChapterCount:inout [Int], lastChapterNumber:inout [Int], honorificCount:inout [Int]) {
        bareCount[patternIndex] += 1
        if lastChapterNumber[patternIndex] != chapterNumber {
            lastChapterNumber[patternIndex] = chapterNumber
            bareChapterCount[patternIndex] += 1
        }
        let n = buffer.count
        for honorific in honorificBytes {
            guard matchEnd + honorific.count <= n else { continue }
            var isMatch = true
            for (offset, byte) in honorific.enumerated() where buffer[matchEnd + offset] != byte { isMatch = false; break }
            if isMatch { honorificCount[patternIndex] += 1; return }
        }
    }

    /// 「魔導」が「魔導書」の一部である、というような関係を調べて印を付けます。
    /// 読み替えは単純な部分文字列の置換なので、そういう語は他の語の中でも発火してしまう事を伝えたいためです。
    static func markPartOfOtherCandidate(_ candidates:inout [RubyNotationCandidate]) {
        // 候補同士を総当たりすると候補数の2乗になってしまうので、
        // 「各候補の(自分自身を除く)部分文字列」を全部集合に入れておいて、
        // その集合に入っているかどうかを見る形にします。候補数に比例した手間で済みます。
        let maxSubstringCharacterCount = 12
        var substringSet = Set<String>()
        for candidate in candidates {
            let characterArray = Array(candidate.before)
            if characterArray.count <= 1 { continue }
            for start in 0..<characterArray.count {
                for length in 1...(characterArray.count - start) {
                    if length > maxSubstringCharacterCount { break }
                    // 自分自身は「他の語の一部」ではない
                    if start == 0 && length == characterArray.count { continue }
                    substringSet.insert(String(characterArray[start..<(start + length)]))
                }
            }
        }
        for index in candidates.indices where substringSet.contains(candidates[index].before) {
            candidates[index].isPartOfOtherCandidate = true
        }
    }

    // MARK: - 並び順

    enum SortType : Int {
        /// 裸の出現章数の多い順(既定)
        case bareChapterCount
        /// 裸の出現回数の多い順
        case bareCount
        /// 本文に出てきた順
        case appearance
        /// 読み替え前の文字列順
        case beforeString
    }

    static func CompareByBareChapterCount(lhs:RubyNotationCandidate, rhs:RubyNotationCandidate) -> Bool {
        if lhs.bareChapterCount != rhs.bareChapterCount { return lhs.bareChapterCount > rhs.bareChapterCount }
        if lhs.bareCount != rhs.bareCount { return lhs.bareCount > rhs.bareCount }
        // 敬称が付いていた事があるものは人名らしいので、同じ数なら上に持ってくる
        if lhs.honorificCount != rhs.honorificCount { return lhs.honorificCount > rhs.honorificCount }
        return lhs.before < rhs.before
    }

    static func Sort(candidates:[RubyNotationCandidate], sortType:SortType) -> [RubyNotationCandidate] {
        switch sortType {
        case .bareChapterCount:
            return candidates.sorted(by: { CompareByBareChapterCount(lhs: $0, rhs: $1) })
        case .bareCount:
            return candidates.sorted(by: {
                if $0.bareCount != $1.bareCount { return $0.bareCount > $1.bareCount }
                return CompareByBareChapterCount(lhs: $0, rhs: $1)
            })
        case .appearance:
            return candidates.sorted(by: {
                if $0.firstChapterNumber != $1.firstChapterNumber { return $0.firstChapterNumber < $1.firstChapterNumber }
                return $0.before < $1.before
            })
        case .beforeString:
            return candidates.sorted(by: { $0.before < $1.before })
        }
    }

    // MARK: - 本文の読み出し

    /// 小説の全ての章を、bulk 単位で読んでは捨てながら渡します。
    /// 全部の本文を配列に貯めると 1万章で 90MB 近くになるので、必ずこの形で回して下さい。
    private static func forEachStory(novelID:String, progressRange:Range<Float>, progress:@escaping (Float)->Void, isCanceled:@escaping ()->Bool, body:(String, Int)throws ->Void) throws {
        try RealmUtil.RealmBlock { (realm) throws -> Void in
            guard let bulkArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: novelID) else {
                throw ExtractError.novelNotFound
            }
            let bulkCount = bulkArray.count
            if bulkCount <= 0 { return }
            var chapterNumber = 0
            var bulkIndex = 0
            for bulk in bulkArray {
                if isCanceled() { throw ExtractError.canceled }
                try autoreleasepool {
                    guard let storyArray = bulk.LoadStoryArray() else { return }
                    for story in storyArray {
                        chapterNumber += 1
                        try body(story.content, chapterNumber)
                    }
                }
                bulkIndex += 1
                progress(progressRange.lowerBound + (progressRange.upperBound - progressRange.lowerBound) * Float(bulkIndex) / Float(bulkCount))
            }
        }
    }
}
