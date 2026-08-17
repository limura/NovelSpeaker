//
//  VoicevoxStyleSelection.swift
//  NovelSpeaker
//
//  話者設定に保存されている voiceIdentifier が、VOICEVOX のスタイルとして
//  どういう状態なのかを判定する。
//
//  **なぜこれが要るか(重要)**
//
//  VOICEVOX の話者設定は voiceIdentifier に styleId を文字列で持っている。
//  従来はここが「今この端末で使えるスタイルの一覧」に無いと、
//  一覧の先頭のスタイルに**書き換えて保存**していた。
//  同梱の音声モデルが1つだけで増減しなかった頃はこれで正しかった。
//
//  ところが音声モデルを取得/削除できるようになると、これは事故になる:
//
//    「ずんだもん ささやき」(5.vvm)を使っていた
//     → 容量のために 5.vvm を消す
//     → 全ての小説の話者設定が「四国めたん あまあま」に書き換わって保存される
//     → 5.vvm を取り直しても戻らない
//
//  読み上げ設定は利用者が手で育てるデータなので、これは避けなければならない。
//
//  **区別すべき2つの「一覧に無い」**
//
//  1. 保存値が数値ですらない(例: "com.apple.voice.compact.ja-JP.Kyoko")
//     = 読み上げエンジンを AVSpeechSynthesizer から VOICEVOX に切り替えた時の残骸。
//       これは意味のある設定ではないので、直してしまってよい。
//  2. 保存値は数値だが、その音声モデルが未取得
//     = 利用者が選んだ結果。**絶対に書き換えない。**
//
//  この2つを混同していたのが従来の実装だった。
//

import Foundation

/// 話者設定の voiceIdentifier を VOICEVOX のスタイルとして見た時の状態。
enum VoicevoxStyleSelection: Equatable {
    /// この端末で今すぐ使える。
    case available(styleId: UInt32)
    /// styleId ではあるが、その音声モデルが未取得。**保存値を書き換えてはいけない。**
    case notDownloaded(styleId: UInt32)
    /// styleId ですらない(エンジンを切り替えた時の残骸など)。書き換えて直してよい。
    case notAStyleId

    /// 保存値を書き換えて直してよいか。
    var canBeRepaired: Bool {
        switch self {
        case .notAStyleId: return true
        case .available, .notDownloaded: return false
        }
    }

    var styleId: UInt32? {
        switch self {
        case .available(let styleId), .notDownloaded(let styleId): return styleId
        case .notAStyleId: return nil
        }
    }
}

enum VoicevoxStyleSelectionResolver {
    /// - Parameters:
    ///   - voiceIdentifier: 話者設定に保存されている文字列
    ///   - availableStyleIds: 今この端末で使えるスタイルの styleId
    static func resolve(voiceIdentifier: String, availableStyleIds: Set<UInt32>) -> VoicevoxStyleSelection {
        // UInt32(_:) は前後の空白・小数点・16進表記・全角数字を弾く(先頭の "+" だけは通すが、
        // 保存値にそれが現れる事は無いので害は無い)。AVSpeech の音声IDは確実に弾かれる。
        // ここは寛容な方に倒しておく。厳しくすると、意味のある設定を「残骸」と誤判定して
        // 書き換えてしまう側に振れるため。
        guard let styleId = UInt32(voiceIdentifier) else { return .notAStyleId }
        if availableStyleIds.contains(styleId) { return .available(styleId: styleId) }
        return .notDownloaded(styleId: styleId)
    }

    /// 未取得のスタイルを選択行に表示するための文字列。
    ///
    /// 名前が分かるなら見せる。分からない(カタログにも無い)場合でも、
    /// 番号だけは見せる。「何かが選ばれている」事が分からないと、
    /// 利用者は「勝手に変わった」と受け取るため。
    /// - Parameter knownName: カタログ等から引けた表示名。引けなければ nil
    static func notDownloadedLabel(styleId: UInt32, knownName: String?) -> String {
        let format = NSLocalizedString("VoicevoxStyleSelection_NotDownloadedLabelFormat",
                                       comment: "(未取得) %@")
        if let knownName = knownName, knownName.isEmpty == false {
            return String(format: format, knownName)
        }
        let unknownFormat = NSLocalizedString("VoicevoxStyleSelection_UnknownStyleNameFormat",
                                              comment: "スタイル番号 %u")
        return String(format: format, String(format: unknownFormat, styleId))
    }
}
