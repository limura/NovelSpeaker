//
//  VoicevoxCacheBlockSource.swift
//  NovelSpeaker
//
//  「再生する時のブロック列」と「事前生成する時のブロック列」を必ず一致させるための入口。
//
//  ディスクキャッシュの鍵は(話者ID + 実際に合成する文字列)から決まるので、
//  生成時と再生時でブロックの切れ目が1文字でも違えば、作ってあっても命中しない。
//  しかもそれは「無音が減らない」という形でしか現れず、原因が極めて分かりにくい。
//
//  そこで、生成側が独自にブロックを組み立てられないよう、経路をここ1つに絞る。
//  分割パラメータも再生側(StorySpeaker)が実際に使っている値をそのまま読む
//  (定数をコピーすると、片方だけ変えた時に静かに壊れる)。
//

import Foundation

#if !os(watchOS)
import RealmSwift

enum VoicevoxCacheBlockSource {

    /// 再生側が実際に使っている分割設定。
    static var withMoreSplitTargets: [String] {
        return StorySpeaker.shared.withMoreSplitTargets
    }

    static var moreSplitMinimumLetterCount: Int {
        return StorySpeaker.shared.moreSplitMinimumLetterCount
    }

    /// その話を読み上げる時のブロック列。再生側(SpeechBlockSpeaker.SetStory)と同じ物を返す。
    static func blocks(story: Story) -> [CombinedSpeechBlock] {
        return StoryTextClassifier.CategorizeStoryText(
            story: story,
            withMoreSplitTargets: withMoreSplitTargets,
            moreSplitMinimumLetterCount: moreSplitMinimumLetterCount
        )
    }

    /// VOICEVOX で合成する必要があるブロックだけを、
    /// (何番目のブロックか, 合成する文字列, 話者ID, ディスクキャッシュの鍵) の形で返す。
    ///
    /// 読み上げるべき文字を含まないブロック(改行や記号だけ等)は、再生時にも合成されず
    /// 読み飛ばされるので、生成対象からも外す(合成しようとしても失敗する)。
    static func synthesisTargets(story: Story) -> [(blockIndex: Int, text: String, styleId: UInt32, key: String)] {
        var result: [(blockIndex: Int, text: String, styleId: UInt32, key: String)] = []
        for (index, block) in blocks(story: story).enumerated() {
            guard block.type == "VOICEVOX" else { continue }
            let text = block.speechText
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if hasNoSpeakableCharacter(text) { continue }
            let styleId = VoicevoxCore.styleId(fromVoiceIdentifier: block.voiceIdentifier)
            result.append((index, text, styleId, VoicevoxDiskCacheStore.key(text: text, styleId: styleId)))
        }
        return result
    }

    /// 指定したページの本文をまとめて読み出す。
    ///
    /// **1ページずつ `RealmStoryBulk.SearchStoryWith()` を呼んではいけない。**
    /// 本文は100ページ単位の塊(bulk)を zip + JSON で固めた形で保存されており、
    /// 1ページ読むだけでもその塊を丸ごと展開し直す。塊のキャッシュは既定で無効
    /// (`isLoadStoryArrayCacheEnabled = false`)で、効くのは「直前と同じ1ページ」だけなので、
    /// ページを順に舐めると毎回展開が走る。
    /// 実機では14ページ調べるのに4秒かかっていた(=1ページあたり約0.28秒が全部これ)。
    /// 塊ごとに1回だけ展開すれば、100ページぶんが1回の展開で手に入る。
    static func stories(novelID: String, chapterNumbers: [Int]) -> [Int: Story] {
        let wanted = Set(chapterNumbers)
        guard wanted.isEmpty == false else { return [:] }
        let startedAt = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed >= 0.5 {
                NSLog("NovelSpeaker.VoicevoxCacheBlockSource: 本文読み出し \(String(format: "%.2f", elapsed))秒 (\(wanted.count)ページ)")
            }
        }
        return RealmUtil.RealmBlock { (realm) -> [Int: Story] in
            var result: [Int: Story] = [:]
            guard let bulkList = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: novelID) else { return result }
            for bulk in bulkList {
                autoreleasepool {
                    // その塊に欲しいページが1つも無いなら、展開せずに飛ばす。
                    //
                    // 塊の chapterNumber は CalcBulkChapterNumber() の値、つまり
                    // 「(ページ番号-1)/100*100」で 0, 100, 200… となる(先頭ページ番号ではない)。
                    // ここを先頭ページ番号だと思って 0…99 で判定すると、
                    // 100ページ目(や200ページ目)だけが塊から漏れる。
                    // 漏れたページは「本文が無い」扱いになり、
                    // 「今の設定で使われない音声」として消されてしまう。
                    let bulkFirstChapter = bulk.chapterNumber + 1
                    let bulkLastChapter = bulk.chapterNumber + RealmStoryBulk.bulkCount
                    guard wanted.contains(where: { $0 >= bulkFirstChapter && $0 <= bulkLastChapter }) else { return }
                    guard let storyArray = bulk.LoadStoryArray() else { return }
                    for story in storyArray where wanted.contains(story.chapterNumber) {
                        result[story.chapterNumber] = story
                    }
                }
            }
            return result
        }
    }

    /// 今の設定で、その小説に必要な音声の鍵をページごとに集める。
    ///
    /// 発話設定(話者・読み替え辞書・会話文の話者割り当て等)を変えると、
    /// 同じ本文でも合成する文字列や話者IDが変わり、鍵が変わる。
    /// 古い鍵の音声は二度と使われないのに場所だけ取り続けるので、これで洗い出して消す。
    /// 鍵はハッシュだが逆算は要らない。**今の設定で作り直した鍵の集合に無い物**を消せばよい。
    /// - Returns: ページ番号 → そのページで使う鍵の集合。
    static func currentKeysByChapter(novelID: String, chapterNumbers: [Int]) -> [Int: Set<String>] {
        let storyByChapter = stories(novelID: novelID, chapterNumbers: chapterNumbers)
        var result: [Int: Set<String>] = [:]
        for chapterNumber in chapterNumbers {
            guard let story = storyByChapter[chapterNumber] else {
                // 本文が無いページ(削除された等)の音声は、もう使いようが無い。
                result[chapterNumber] = []
                continue
            }
            result[chapterNumber] = Set(synthesisTargets(story: story).map { $0.key })
        }
        return result
    }

    /// SpeechBlockSpeaker.hasNoSpeakableCharacter() と同じ基準。
    /// VOICEVOX は句読点・記号・空白だけの文字列を渡すと形態素解析に失敗するため、
    /// 再生側でも合成せずに読み飛ばしている。
    static func hasNoSpeakableCharacter(_ text: String) -> Bool {
        for character in text {
            if character.isWhitespace || character.isNewline { continue }
            if character.isPunctuation || character.isSymbol { continue }
            return false
        }
        return true
    }
}
#endif
