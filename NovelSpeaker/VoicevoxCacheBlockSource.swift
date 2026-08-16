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
