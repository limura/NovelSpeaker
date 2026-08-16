//
//  VoicevoxCacheKeyAlignmentTest.swift
//  NovelSpeakerTests
//
//  「作ったキャッシュが使われる」ための、鍵が揃っている事のテスト。
//
//  ディスクキャッシュの鍵は(話者ID + 実際に合成する文字列)から決まるので、
//  再生時に渡す文字列が1文字でも違えば、作ってあっても命中しない。
//  この機能で最も怖い失敗は「数十分かけて作ったのに全く使われない」であり、
//  しかもそれは「無音が減らない」という形でしか現れず、原因が非常に分かりにくい。
//
//  特に危ないのが、ブロックの途中から再生を開始した場合。
//  1000文字を100文字ずつに分けてキャッシュしてある所を50文字目から再生する時、
//  もし「50文字目から150文字目」を1ブロック目として切り出すような実装だと、
//  以降のブロック境界が全部ずれて、2番目以降のキャッシュも全滅する。
//
//  現在の実装は SetStory の時点で本文全体を一度だけ分割し、開始位置は
//  「そのオフセットがどのブロックに入るか」を探すだけなので、ずれるのは
//  中断位置の1ブロック目だけで済む。壊れても命中率が下がるだけで気付きにくいので、
//  この性質をテストで固定しておく。
//

import XCTest
@testable import NovelSpeaker

class VoicevoxCacheKeyAlignmentTest: XCTestCase {

    private static let content = """
　ファーレーン王国の王都からほど近い小さな村に、ひとりの少女が住んでいた。名前を宏という。
「なあ、春菜。この村から出た事あるか？」
「ううん、一度も無いよ。だって、外は危ないって皆が言うんだもの」
　少女は窓の外を眺めながら、そう答えた。空は抜けるように青く、遠くの山並みまではっきりと見えている。
　こんな日は、どこか遠くへ行ってみたくなる。けれども、村の外に出るには相応の覚悟が必要だった。
「せやけどな、いつまでもここにおるわけにもいかんやろ」
　宏の言葉に、春菜は小さく頷いた。
"""

    private func makeSpeakerSetting(voiceIdentifier: String) -> SpeakerSetting {
        let realmSetting = RealmSpeakerSetting()
        realmSetting.type = "VOICEVOX"
        realmSetting.voiceIdentifier = voiceIdentifier
        realmSetting.locale = "ja-JP"
        return SpeakerSetting(from: realmSetting)
    }

    private func makeBlocks() -> [CombinedSpeechBlock] {
        return StoryTextClassifier.CategorizeStoryText(
            content: Self.content,
            withMoreSplitTargets: ["。", "、", "　", "\n"],
            moreSplitMinimumLetterCount: 100,
            defaultSpeaker: makeSpeakerSetting(voiceIdentifier: "2"),
            sectionConfigList: [SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: makeSpeakerSetting(voiceIdentifier: "3"))],
            waitConfigList: [],
            sortedSpeechModArray: []
        )
    }

    /// SpeechBlockSpeaker.SetSpeechLocation() と同じ手順で、
    /// 表示位置からブロック番号とブロック内オフセットを求める。
    private func locate(blocks: [CombinedSpeechBlock], displayLocation: Int) -> (blockIndex: Int, offsetInBlock: Int)? {
        var remaining = displayLocation
        for (index, block) in blocks.enumerated() {
            let length = block.displayText.unicodeScalars.count
            if remaining >= length {
                remaining -= length
                continue
            }
            return (index, remaining)
        }
        return nil
    }

    /// 実際に発話(=合成)される文字列を、再生開始位置を与えて並べる。
    /// SpeechBlockSpeaker は「開始ブロックだけ途中から、以降は先頭から」進むので、それを再現する。
    private func spokenTexts(blocks: [CombinedSpeechBlock], startingAtDisplayLocation displayLocation: Int) -> [String] {
        guard let (startIndex, offsetInBlock) = locate(blocks: blocks, displayLocation: displayLocation) else { return [] }
        var result: [String] = []
        for index in startIndex..<blocks.count {
            let offset = (index == startIndex) ? offsetInBlock : 0
            result.append(blocks[index].GenerateSpeechTextFrom(displayLocation: offset))
        }
        return result
    }

    // 先頭から再生した時、実際に合成される文字列が block.speechText と一致する事。
    //
    // 先行合成(先読み)は block.speechText で鍵を作り、再生側は
    // GenerateSpeechTextFrom(displayLocation:) の結果で鍵を作る。
    // ここがずれていると、先読みした物が再生時に一度も使われない。
    func testSpokenTextMatchesPrefetchTextWhenStartingFromTheBeginning() {
        let blocks = makeBlocks()
        XCTAssertGreaterThan(blocks.count, 3, "テストとして意味のある数に分割されている事")
        for (index, block) in blocks.enumerated() {
            XCTAssertEqual(block.GenerateSpeechTextFrom(displayLocation: 0), block.speechText,
                           "block[\(index)] で先読みの鍵と再生の鍵がずれる")
        }
    }

    // ブロックの途中から再生を開始しても、**その次のブロック以降**は先頭から再生した時と
    // 完全に同じ文字列になる事(=作ってあるキャッシュがそのまま使える事)。
    //
    // これが崩れると、途中再開しただけで以降のキャッシュが全滅する。
    func testResumingMidBlockKeepsAllLaterBlocksIdentical() {
        let blocks = makeBlocks()
        let fromStart = spokenTexts(blocks: blocks, startingAtDisplayLocation: 0)

        // 2ブロック目の途中から始める。
        let firstBlockLength = blocks[0].displayText.unicodeScalars.count
        let secondBlockLength = blocks[1].displayText.unicodeScalars.count
        let midOfSecondBlock = firstBlockLength + secondBlockLength / 2
        guard let (startIndex, offsetInBlock) = locate(blocks: blocks, displayLocation: midOfSecondBlock) else {
            XCTFail("開始位置を求められませんでした")
            return
        }
        XCTAssertEqual(startIndex, 1)
        XCTAssertGreaterThan(offsetInBlock, 0, "ブロックの途中から始まっている事")

        let fromMiddle = spokenTexts(blocks: blocks, startingAtDisplayLocation: midOfSecondBlock)
        // 先頭は途中からなので違って当然。2つ目以降(=元のブロック2以降)が一致する事。
        XCTAssertEqual(Array(fromMiddle.dropFirst()),
                       Array(fromStart.dropFirst(startIndex + 1)),
                       "途中再開すると、以降のブロックの合成文字列が変わってしまっている")
    }

    // どのブロックの途中から始めても同じ事が言える(境界の作りに依存していない事の確認)。
    func testResumingAtEveryBlockKeepsLaterBlocksIdentical() {
        let blocks = makeBlocks()
        let fromStart = spokenTexts(blocks: blocks, startingAtDisplayLocation: 0)
        var displayOffset = 0
        for (index, block) in blocks.enumerated() {
            let length = block.displayText.unicodeScalars.count
            if length >= 2 {
                let fromMiddle = spokenTexts(blocks: blocks, startingAtDisplayLocation: displayOffset + length / 2)
                XCTAssertEqual(Array(fromMiddle.dropFirst()),
                               Array(fromStart.dropFirst(index + 1)),
                               "block[\(index)] の途中から再開すると以降がずれる")
            }
            displayOffset += length
        }
    }

    // 鍵は「話者 + 合成する文字列」で決まるので、途中再開した最初の1つだけが
    // 新しい鍵になり、残りは作ってある物と同じ鍵になる事を、鍵の形でも確かめる。
    func testOnlyTheFirstPartialBlockGetsANewCacheKey() {
        let blocks = makeBlocks()
        let styleId: UInt32 = 2
        let generatedKeys = Set(blocks.map { VoicevoxDiskCacheStore.key(text: $0.speechText, styleId: styleId) })

        let firstBlockLength = blocks[0].displayText.unicodeScalars.count
        let fromMiddle = spokenTexts(blocks: blocks, startingAtDisplayLocation: firstBlockLength / 2)
        let playbackKeys = fromMiddle.map { VoicevoxDiskCacheStore.key(text: $0, styleId: styleId) }

        XCTAssertFalse(generatedKeys.contains(playbackKeys[0]), "途中から切り出した先頭は新しい鍵になる(=作り直しになる)")
        for (offset, key) in playbackKeys.dropFirst().enumerated() {
            XCTAssertTrue(generatedKeys.contains(key), "\(offset + 1)番目の鍵が作ってある物と一致しない")
        }
    }
}
