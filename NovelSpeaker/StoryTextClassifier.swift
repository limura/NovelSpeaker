//
//  StoryTextClassifier.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
#if !os(watchOS)
import RealmSwift
#endif
import AVFoundation

struct SpeechBlockInfo {
    let speechText:String
    let displayText:String
    let voiceIdentifier:String?
    let locale:String?
    let pitch:Float
    let rate:Float
    let volume:Float
    let delay:TimeInterval
    let isMod:Bool
    let type:String
}

struct SpeechSectionConfig {
    let startText:String
    let endText:String
    let speakerSetting:SpeakerSetting
}

struct SpeakerSetting {
    let pitch : Float
    let rate : Float
    let lmd : Float
    let acc : Float
    let base : Int32
    let volume : Float
    let type : String
    let voiceIdentifier : String
    let locale : String
    #if !os(watchOS)
    init(from:RealmSpeakerSetting) {
        pitch = from.pitch
        rate = from.rate
        lmd = from.lmd
        acc = from.acc
        base = from.base
        volume = from.volume
        type = from.type
        voiceIdentifier = from.voiceIdentifier
        locale = from.locale
    }
    #endif
    // 既定値は RealmSpeakerSetting の既定値に合わせてあります(watchOS 等 Realm の無い環境用)
    init(pitch:Float = 1.0, rate:Float = 0.5, lmd:Float = 1.0, acc:Float = 1.0, base:Int32 = 1, volume:Float = 1.0, type:String = "AVSpeechSynthesizer", voiceIdentifier:String = "", locale:String = "ja-JP") {
        self.pitch = pitch
        self.rate = rate
        self.lmd = lmd
        self.acc = acc
        self.base = base
        self.volume = volume
        self.type = type
        self.voiceIdentifier = voiceIdentifier
        self.locale = locale
    }
}
struct SpeechWaitConfig {
    let targetText : String
    let delayTimeInSec : Float
    #if !os(watchOS)
    init(from:RealmSpeechWaitConfig) {
        targetText = from.targetText
        delayTimeInSec = from.delayTimeInSec
    }
    #endif
    init(targetText:String, delayTimeInSec:Float) {
        self.targetText = targetText
        self.delayTimeInSec = delayTimeInSec
    }
}
struct SpeechModSetting {
    let before : String
    let after : String
    let isUseRegularExpression : Bool
    // この読み替えをどの音声合成エンジン(type)向けに適用するかの一覧。
    // 空配列 = 「どのエンジンにも適用する」(未設定扱い)。
    // 特定のエンジン type("AVSpeechSynthesizer" / "VOICEVOX" 等)を列挙すると、
    // そのエンジンの話者のブロックにのみ適用される。
    //
    // 標準の読み替え辞書(DefaultSpeechModList.json)由来のエントリは、AVSpeechSynthesizer が
    // 前後の文字に影響されて変な読み方をするのを避けるためのもの(例: 「実際」→「"実際"」で囲う等)が
    // 多く、VOICEVOX 等にそのまま適用すると余計な記号(")が入って不自然な分割・発話を招くため、
    // ["AVSpeechSynthesizer"] を指定して VOICEVOX 等には適用しないようにする。
    // ユーザー追加の読み替えやルビ由来の読み替えは空配列(=全エンジン)にしておく。
    // (将来は読み替え辞書のデータ自体にこの対象エンジン情報を持たせるのが正しい)
    let targetSpeechEngineTypeArray : [String]

    // before / after の文字数を最初に1回だけ数えて持っておく。
    //
    // 並べ替えの比較関数はこれを1回の比較で最大4回参照するので、その都度 String.count を
    // 呼ぶと、10000件の並べ替えで50万回以上の文字数計算が走る。
    // しかも Realm から取り出した String は NSString のまま橋渡しされている事があり、
    // その状態の .count は桁違いに遅い。
    // 実測(母艦・10107件): 並べ替えだけで 383.8ms かかっていたのが、
    // 同じ件数のJSON由来(素のSwift String)では 17.6ms しかかからなかった。
    let beforeCount : Int
    let afterCount : Int

    // 指定した話者エンジンtypeにこの読み替えを適用すべきか。
    func isAppliedTo(speechEngineType:String) -> Bool {
        if targetSpeechEngineTypeArray.isEmpty { return true } // 未設定=全エンジン
        return targetSpeechEngineTypeArray.contains(speechEngineType)
    }

    #if !os(watchOS)
    init(from:RealmSpeechModSetting, targetSpeechEngineTypeArray:[String] = []) {
        // Realm から来た String は NSString のまま橋渡しされている事があり、
        // その状態だと .count や比較が極端に遅い。ここで素の Swift String に写しておく。
        self.init(before: String(from.before), after: String(from.after), isUseRegularExpression: from.isUseRegularExpression, targetSpeechEngineTypeArray: targetSpeechEngineTypeArray)
    }
    #endif
    init(before:String, after:String, isUseRegularExpression:Bool, targetSpeechEngineTypeArray:[String] = []) {
        self.before = before
        self.after = after
        self.isUseRegularExpression = isUseRegularExpression
        self.targetSpeechEngineTypeArray = targetSpeechEngineTypeArray
        self.beforeCount = before.count
        self.afterCount = after.count
    }
}

// 連続した同じ発話設定の SpeechBlockInfo を纏めて一つの Block として扱うためのclass。
// 読み替え前と読み替え後が同じ文字列になる場合は nil を入れる事で消費メモリに少し優しくなります。
// また、読み替え前と読み替え後が違う場合の物を個別に登録する事で、
// 読み上げ時の読み上げ中の位置の取得や、読み上げ開始位置の指定をした時の文字の位置をより正しく計算できるようになります。
class CombinedSpeechBlock: Identifiable {
    struct speechBlock {
        let displayText:String
        let speechText:String? // displayText と同じ場合は nil を入れるという事にします。
        let isMod:Bool
    }
    var speechBlockArray:[speechBlock] = []
    let voiceIdentifier:String?
    let locale:String?
    let pitch:Float
    let rate:Float
    let volume:Float
    var delay:TimeInterval
    let type:String

    init(block:SpeechBlockInfo) {
        voiceIdentifier = block.voiceIdentifier
        locale = block.locale
        pitch = block.pitch
        rate = block.rate
        volume = block.volume
        delay = block.delay
        type = block.type
        let speechText:String?
        if block.displayText == block.speechText {
            speechText = nil
        }else{
            speechText = block.speechText
        }
        speechBlockArray = [speechBlock(displayText: block.displayText, speechText: speechText, isMod: block.isMod)]
    }
    
    var displayText:String {
        get {
            var displayText = ""
            for block in speechBlockArray {
                displayText += block.displayText
            }
            return displayText
        }
    }
    var speechText:String {
        get {
            var speechText = ""
            for block in speechBlockArray {
                let blockSpeechText:String
                if let s = block.speechText {
                    blockSpeechText = s
                }else{
                    blockSpeechText = block.displayText
                }
                speechText += blockSpeechText
            }
            return speechText
        }
    }
    
    func Add(block:SpeechBlockInfo) -> Bool {
        func checkFloatEqual(a:Float, b:Float) -> Bool {
            return fabsf(a - b) < Float.ulpOfOne
        }
        func checkDoubleEqual(a:Double, b:Double) -> Bool {
            return fabs(a - b) < Double.ulpOfOne
        }
        guard checkDoubleEqual(a: 0.0, b: self.delay) // このブロック自体が既にdelayを持っているなら、
            // それ以上何も追加してはいけない(追加してしまうと、delayが実際に効く位置が
            // 本来の場所より後ろにずれてしまう)。
            && checkDoubleEqual(a: 0.0, b: block.delay) // delay があるなら合成してはいけません
            && checkFloatEqual(a: pitch, b: block.pitch)
            && checkFloatEqual(a: rate, b: block.rate)
            && checkFloatEqual(a: volume, b: block.volume)
            && voiceIdentifier == block.voiceIdentifier
            && type == block.type
            else { return false }
        let speechText:String?
        if block.displayText == block.speechText {
            speechText = nil
        }else{
            speechText = block.speechText
        }
        speechBlockArray.append(speechBlock(displayText: block.displayText, speechText: speechText, isMod: block.isMod))
        return true
    }

    // 後続ピースが delay(「間の設定」由来のポーズ)を持っている場合でも、
    // それを「このブロックの最後のピース」として吸収し、delay はブロック全体の後ろの間として
    // 引き継いでブロックを閉じる(この後は何も追加できない、呼び出し側で閉じること)。
    // delay は元々「そのピースを読み終えた後の間」なので、末尾ピースとして取り込む分には
    // 意味が変わらない。これにより読み替え(mod)で切れたピースが、後続の delay 付きピースへ
    // 連結できずに単独ブロックとして孤立し、句読点以外の場所(直前の読み替えヒット位置)で
    // ブロックが分断される問題を防ぐ。
    // (元々は VOICEVOX の不自然な間対策として VOICEVOX 専用だったが、AVSpeechSynthesizer でも
    //  同じ分断が起きていた(特に watchOS でブロック境界の無音が耳につく)ため全エンジンに適用)
    // 話者設定(pitch/rate/volume/voiceIdentifier/type)が一致し、かつ自身がまだ delay を
    // 持っていない場合のみ吸収する。
    func AbsorbTrailingDelayBlock(block:SpeechBlockInfo) -> Bool {
        func checkFloatEqual(a:Float, b:Float) -> Bool {
            return fabsf(a - b) < Float.ulpOfOne
        }
        func checkDoubleEqual(a:Double, b:Double) -> Bool {
            return fabs(a - b) < Double.ulpOfOne
        }
        guard checkDoubleEqual(a: 0.0, b: self.delay) // 自身が既に delay を持つ = 既に閉じている
            && block.delay > 0.0 // 吸収対象は delay を持つピースだけ(delay=0 は通常の Add で連結される)
            && checkFloatEqual(a: pitch, b: block.pitch)
            && checkFloatEqual(a: rate, b: block.rate)
            && checkFloatEqual(a: volume, b: block.volume)
            && voiceIdentifier == block.voiceIdentifier
            && type == block.type
            else { return false }
        let speechText:String?
        if block.displayText == block.speechText {
            speechText = nil
        }else{
            speechText = block.speechText
        }
        speechBlockArray.append(speechBlock(displayText: block.displayText, speechText: speechText, isMod: block.isMod))
        self.delay = block.delay
        return true
    }

    func GenerateSpeechTextFrom(displayLocation:Int) -> String {
        var location = displayLocation
        if location < 0 { return "" }
        var speechText = ""
        for block in speechBlockArray {
            if location <= 0 {
                if let blockSpeechText = block.speechText {
                    speechText += blockSpeechText
                }else{
                    speechText += block.displayText
                }
                continue
            }
            let displayTextCount = block.displayText.unicodeScalars.count
            if location > displayTextCount {
                location -= displayTextCount
                continue
            }
            let blockSpeechText:String
            if let s = block.speechText {
                blockSpeechText = s
            }else{
                blockSpeechText = block.displayText
            }
            let blockSpeechTextCount = blockSpeechText.unicodeScalars.count
            let displayTextLength = Float(displayTextCount)
            let speechTextLength = Float(blockSpeechTextCount)
            let speechStartLocationFloat = Float(location) * speechTextLength / displayTextLength
            let speechStartLocation:Int
            if speechStartLocationFloat.isNaN || speechStartLocationFloat.isInfinite {
                speechStartLocation = 0
            }else{
                speechStartLocation = Int(speechStartLocationFloat)
            }
            let speechTextStartIndex = blockSpeechText.unicodeScalars.index(blockSpeechText.startIndex, offsetBy: speechStartLocation)
            speechText = String(blockSpeechText.unicodeScalars[speechTextStartIndex..<blockSpeechText.unicodeScalars.endIndex])
            location = 0
        }
        return speechText
    }
    func GenerateSpeechTextFrom(range:NSRange) -> String {
        let startLocation = range.location
        let endLocation = range.location + range.length
        var location = 0
        if startLocation < 0 || endLocation < startLocation { return "" }
        var result = Substring()
        for block in speechBlockArray {
            let displayTextLength = block.displayText.unicodeScalars.count
            if displayTextLength <= 0 { continue }
            if location + displayTextLength <= startLocation || location > endLocation {
                location += displayTextLength
                continue
            }
            let speechText:String
            if let s = block.speechText {
                speechText = s
            }else{
                speechText = block.displayText
            }
            let speechTextLength = speechText.unicodeScalars.count
            var blockStartLocation = startLocation - location
            var blockEndLocation = endLocation - location
            if blockStartLocation < 0 {
                blockStartLocation = 0
            }
            if blockEndLocation > displayTextLength {
                blockEndLocation = displayTextLength
            }
            // 最初の時と最後の時以外はそのまま全部突っ込む。
            // これは、これ以後の計算は「だいたい合ってる」でしかなく、1文字分位は切り捨てられてしまったりするので
            // 1文字だけの場合とか、1文字から3文字に変わってる時とかに計算がずれてしまうため。
            if blockStartLocation > 0 || blockEndLocation < displayTextLength {
                let speechStartLocation = Int(Float(blockStartLocation) * Float(speechTextLength) / Float(displayTextLength))
                let speechEndLocation = Int(Float(blockEndLocation) * Float(speechTextLength) / Float(displayTextLength))
                let speechStartIndex = speechText.unicodeScalars.index(speechText.unicodeScalars.startIndex, offsetBy: speechStartLocation)
                let speechEndIndex = speechText.unicodeScalars.index(speechText.unicodeScalars.startIndex, offsetBy: speechEndLocation)
                result += String(speechText.unicodeScalars[speechStartIndex..<speechEndIndex])
            }else{
                result += speechText
            }
            location += displayTextLength
        }
        return String(result)
    }
    func ComputeDisplayLocationFrom(speechLocation:Int) -> Int {
        var speechLocation = speechLocation
        var displayLocation = 0
        for block in speechBlockArray {
            let blockSpeechText:String
            if let s = block.speechText {
                blockSpeechText = s
            }else{
                blockSpeechText = block.displayText
            }
            let blockSpeechTextCount = blockSpeechText.unicodeScalars.count
            let blockDisplayTextCount = block.displayText.unicodeScalars.count
            if speechLocation > blockSpeechTextCount {
                speechLocation -= blockSpeechTextCount
                displayLocation += blockDisplayTextCount
                continue
            }
            let displayTextLength = Float(blockDisplayTextCount)
            let speechTextLength = Float(blockSpeechTextCount)
            let displayStartLocationFloat = Float(speechLocation) * displayTextLength / speechTextLength
            let displayStartLocation:Int
            if displayStartLocationFloat.isInfinite || displayStartLocationFloat.isNaN {
                displayStartLocation = 0
            }else{
                displayStartLocation = Int(displayStartLocationFloat)
            }
            displayLocation += displayStartLocation
            break
        }
        return displayLocation
    }
    
    func ComputeSpeechLocationFrom(displayLocation:Int) -> Int {
        var displayLocation = displayLocation
        var speechLocation = 0
        for block in speechBlockArray {
            let blockSpeechText:String
            if let s = block.speechText {
                blockSpeechText = s
            }else{
                blockSpeechText = block.displayText
            }
            let blockDisplayTextCount = block.displayText.unicodeScalars.count
            let blockSpeechTextCount = blockSpeechText.unicodeScalars.count
            if displayLocation > blockDisplayTextCount {
                displayLocation -= blockDisplayTextCount
                speechLocation += blockSpeechTextCount
                continue
            }
            let displayTextLength = Float(blockDisplayTextCount)
            let speechTextLength = Float(blockSpeechTextCount)
            let speechStartLocationFloat = Float(displayLocation) * speechTextLength / displayTextLength
            let speechStartLocation:Int
            if speechStartLocationFloat.isNaN || speechStartLocationFloat.isInfinite {
                speechStartLocation = 0
            }else{
                speechStartLocation = Int(Float(displayLocation) * speechTextLength / displayTextLength)
            }
            speechLocation += speechStartLocation
            break
        }
        return speechLocation
    }
}

extension CombinedSpeechBlock: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.speechText)
    }
    
    static func == (lhs:CombinedSpeechBlock, rhs:CombinedSpeechBlock) -> Bool {
        return lhs.speechText == rhs.speechText
    }
}

class StoryTextClassifier {
    // 「URIを読み上げない」設定で使う URI 検出用正規表現。
    // iOS 側(CategorizeStoryText(story:))と watchOS 側(WatchSpeechPlayer)の両方から使う
    static let ignoreURIStringRegexpPattern = "[a-zA-Z][0-9a-zA-Z-+.]*:(//((%[0-9a-f][0-9a-f]|[0-9a-zA-Z-._~!$&'()*+,;=:])*@)?(\\[(::(ffff:([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}|(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,5})?)|([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,4})?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,3})?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,2})?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3}))?)?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})?|(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){3})))))|v[0-9a-fA-F]\\.([0-9a-zA-Z-._~!$&'()*+,;=:])+)\\]|(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=])*)(:[1-9][0-9]*)?)?(/(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=:@])*)*(\\?(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=:@/?])*)?(#(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=:@/?])*)?"

    #if !os(watchOS)
    // RealmSpeechSectionConfig を SpeechSectionConfig に変換します。
    // 単に speakerID を RealmSpeakerSetting に変えるだけです。
    // RealmSpeakerSetting を検索する部分はキャッシュを使って無駄に Realm上 での検索を走らせない程度のことはします。
    static func ConvertSpeechSectionConfig(realm: Realm, fromArray:[RealmSpeechSectionConfig], defaultSpeaker:RealmSpeakerSetting) -> [SpeechSectionConfig] {
        var speakerIDToSpeakerSettingDictionary:[String:SpeakerSetting] = [:]
        var result:[SpeechSectionConfig] = []
        for sectionConfig in fromArray {
            let speaker:SpeakerSetting
            if let sectionSpeaker = speakerIDToSpeakerSettingDictionary[sectionConfig.speakerID] {
                speaker = sectionSpeaker
            }else if let sectionSpeaker = sectionConfig.speakerWith(realm: realm) {
                speaker = SpeakerSetting(from: sectionSpeaker)
                speakerIDToSpeakerSettingDictionary[sectionConfig.speakerID] = speaker
            }else{
                speaker = SpeakerSetting(from: defaultSpeaker)
            }
            result.append(SpeechSectionConfig(startText: sectionConfig.startText, endText: sectionConfig.endText, speakerSetting: speaker))
        }
        return result
    }
    #endif

    // 同じ話者の設定SpeechBlockInfoが連続している物を纏めた CombiledSpeechBlock へと変換します。
    // 一応、表示用の文字列長が moreSplitMinimumLetterCount よりも長い文字列になるようならそこで分割しようとします。
    // ただ、元々の文字列長が長すぎる場合はそのままの長さで残ってしまいますし、
    // 日本語として切れて良い場所かどうかは考慮に入れていないために不自然な所で区切られた文になる可能性もある
    // という事を理解しておいてください。
    // VOICEVOXはブロック全体を一括合成してから再生開始する方式でRTF≈1(合成時間 ≈ 音声長)のため、
    // AVSpeechSynthesizer向けにチューニングされた moreSplitMinimumLetterCount(既定200)をそのまま
    // 使うと、発話開始までの待ちが長くなる(実機で10秒以上)上に、巨大な入力でONNX Runtimeの
    // メモリ確保に失敗してクラッシュする("Failed to allocate memory for requested buffer of
    // size 684345600" 等)。VOICEVOXの推奨値(VOICEVOX_IOS_INTEGRATION.md §6-1)に合わせて
    // ブロックだけ大幅に小さい閾値で区切る。
    private static let voicevoxMoreSplitMinimumLetterCount = 40
    // hasValidSuffix(句読点等の区切り)が見つからないまま延々連結され続けるのを防ぐための絶対上限。
    // これが無いと、区切り文字の無い長文(改行の連続等)でブロックが際限なく巨大化してしまう。
    private static let voicevoxHardCapLetterCount = 120

    // ハード上限(voicevoxHardCapLetterCount)は「ピース同士の連結を止める」ためのものなので、
    // 元々の1ピースがそれより長い場合(初期分割は moreSplitMinimumLetterCount(既定200)を
    // 超えてから次の句読点で切る仕様のため、200文字超のピースが普通に発生する)は
    // そのまま素通ししてしまっていた。VOICEVOX(ONNX Runtime)は一度でも大きな入力を
    // 合成するとその入力サイズに応じた内部メモリ(アリーナ)を確保し、以後解放せずに
    // 使い回すため、長いブロックが一発通るだけでアプリのメモリ消費が段階的に増えて
    // 戻らなくなる(実機のInstrumentsで512MB等の巨大mallocとして観測された)。
    // これを防ぐため、上限を超える単独ピースは連結前にここで分割する。
    // 読み替え(mod)で表示文字列と発話文字列が異なるピースは、分割位置の対応関係を
    // 安全に保てないため分割しない(読み替え結果は通常短い単語なので実害はない)。
    private static let voicevoxPieceSplitBoundaryCharacters: Set<Character> = ["。", "、", "！", "？", "!", "?", "\n", "．", "，", " ", "　"]
    // ハード上限に達した時、ブロックは「読み替え(mod)で区切られたピース」単位でしか
    // 閉じられない。そのため上限に達した瞬間がたまたま読み替え境界だと、
    // 「一応志望」|「校のＡ判定にはぎりぎり…」のように語の途中で閉じてしまい、
    // 実機で不自然な発話として確認された(「彼」|「らの学力は決して低くない」等)。
    // そこで、上限に達しても句読点等で終わっていなければ、この絶対上限までは
    // 追加を続けて自然な切れ目を待つ。合成1回あたりの入力が大きくなり過ぎると
    // メモリ(ONNXのアリーナ)も増えるため、待つ幅は限定する。
    private static let voicevoxAbsoluteMaxLetterCount = 160

    /// 句読点等、そこで区切っても不自然にならない文字で終わっているか。
    private static func endsWithSplitBoundary(_ text:String) -> Bool {
        guard let last = text.last else { return false }
        return voicevoxPieceSplitBoundaryCharacters.contains(last)
    }

    /// 絶対上限に達してしまう時に、次のピースの「最初の区切り文字まで」だけを切り出す。
    ///
    /// 上限に達しても句読点等で終わっていなければ絶対上限まで待つ、という仕組みだけでは、
    /// 次のピース自体が長い場合に「丸ごと足すと上限超過 → 足さずに閉じる」となり、結局
    /// 語の途中で分断されてしまう(実機で 148文字「…常に順位三桁」|「を叩きだしており、…」)。
    /// 先頭の「、」までなら収まるので、そこだけ取り込んで自然な位置で閉じる。
    ///
    /// 読み替え(mod)で表示文字列と発話文字列が異なるピースは、分割位置の対応関係を
    /// 安全に保てないため対象外(splitOversizedVoicevoxPieceIfNeeded と同じ方針)。
    /// - Parameter maxHeadLetterCount: 切り出してよい先頭部分の最大文字数
    /// - Returns: (先頭部分, 残り)。切り出せない場合は nil。
    private static func splitLeadingFragmentUpToBoundary(block:SpeechBlockInfo, maxHeadLetterCount:Int) -> (SpeechBlockInfo, SpeechBlockInfo)? {
        guard maxHeadLetterCount > 0,
              block.isMod == false,
              block.displayText == block.speechText else { return nil }
        let text = block.displayText
        guard text.count > maxHeadLetterCount else { return nil }
        let windowEnd = text.index(text.startIndex, offsetBy: maxHeadLetterCount)
        var cutIndex:String.Index? = nil
        var searchIndex = text.startIndex
        while searchIndex < windowEnd {
            if voicevoxPieceSplitBoundaryCharacters.contains(text[searchIndex]) {
                cutIndex = text.index(after: searchIndex)
                break
            }
            searchIndex = text.index(after: searchIndex)
        }
        guard let cutIndex = cutIndex, cutIndex < text.endIndex else { return nil }
        let head = String(text[text.startIndex..<cutIndex])
        let tail = String(text[cutIndex...])
        // delay(ピースを読み終えた後の間)は最後のピースにだけ残す。
        let headBlock = SpeechBlockInfo(speechText: head, displayText: head, voiceIdentifier: block.voiceIdentifier, locale: block.locale, pitch: block.pitch, rate: block.rate, volume: block.volume, delay: 0, isMod: false, type: block.type)
        let tailBlock = SpeechBlockInfo(speechText: tail, displayText: tail, voiceIdentifier: block.voiceIdentifier, locale: block.locale, pitch: block.pitch, rate: block.rate, volume: block.volume, delay: block.delay, isMod: false, type: block.type)
        return (headBlock, tailBlock)
    }

    private static func splitOversizedVoicevoxPieceIfNeeded(block:SpeechBlockInfo) -> [SpeechBlockInfo] {
        guard block.type == "VOICEVOX",
              block.displayText.count > voicevoxHardCapLetterCount,
              block.isMod == false,
              block.displayText == block.speechText else {
            return [block]
        }
        var pieces:[String] = []
        var remaining = Substring(block.displayText)
        while remaining.count > voicevoxHardCapLetterCount {
            let windowEnd = remaining.index(remaining.startIndex, offsetBy: voicevoxHardCapLetterCount)
            let window = remaining[remaining.startIndex..<windowEnd]
            // 上限までの範囲内で、一番後ろにある「切って良い文字」の直後で切る。
            // 一つも無ければ諦めて上限位置でぶつ切りにする(不自然になるが、
            // メモリ保護の方を優先する)。
            var cutIndex = windowEnd
            var searchIndex = window.endIndex
            while searchIndex > window.startIndex {
                searchIndex = window.index(before: searchIndex)
                if voicevoxPieceSplitBoundaryCharacters.contains(window[searchIndex]) {
                    cutIndex = window.index(after: searchIndex)
                    break
                }
            }
            pieces.append(String(remaining[remaining.startIndex..<cutIndex]))
            remaining = remaining[cutIndex...]
        }
        if remaining.count > 0 {
            pieces.append(String(remaining))
        }
        // delay(「読み上げ時の間の設定」由来のポーズ)はブロックの再生完了「後」に挟まる
        // 待ち時間なので、分割した場合は最後のピースにだけ引き継がせる。
        return pieces.enumerated().map { (i, text) in
            SpeechBlockInfo(speechText: text, displayText: text, voiceIdentifier: block.voiceIdentifier, locale: block.locale, pitch: block.pitch, rate: block.rate, volume: block.volume, delay: i == pieces.count - 1 ? block.delay : 0, isMod: false, type: block.type)
        }
    }

    static func ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray:[SpeechBlockInfo], moreSplitMinimumLetterCount:Int, splitTargetLastLetters:[String]) -> [CombinedSpeechBlock] {
        var result:[CombinedSpeechBlock] = []
        var currentBlock:CombinedSpeechBlock? = nil
        var currentDisplayTextCount = 0
        let speechBlockArray = speechBlockArray.flatMap { splitOversizedVoicevoxPieceIfNeeded(block: $0) }
        for block in speechBlockArray {
            let displayText = block.displayText
            let blockDisplayTextCount = displayText.count
            let isVoicevox = block.type == "VOICEVOX"
            let effectiveMinimumLetterCount = isVoicevox ? voicevoxMoreSplitMinimumLetterCount : moreSplitMinimumLetterCount
            var hasValidSuffix = false
            for lastLetter in splitTargetLastLetters {
                if displayText.hasSuffix(lastLetter) {
                    hasValidSuffix = true
                    break
                }
            }
            if let current = currentBlock {
                let combinedCount = currentDisplayTextCount + blockDisplayTextCount
                // 上限に達していても、語の途中(=句読点等で終わっていない)なら
                // 絶対上限まではもう少しだけ伸ばして自然な切れ目で閉じる。
                let forceCloseForVoicevoxCap = isVoicevox
                    && combinedCount >= voicevoxHardCapLetterCount
                    && (Self.endsWithSplitBoundary(current.displayText)
                        || combinedCount >= voicevoxAbsoluteMaxLetterCount)
                // 語の途中で閉じるしかない状況(絶対上限に達したのに句読点等で終わっていない)なら、
                // 次のピースの先頭にある句読点までだけを取り込んでから閉じる。
                if forceCloseForVoicevoxCap,
                   Self.endsWithSplitBoundary(current.displayText) == false,
                   let (head, tail) = Self.splitLeadingFragmentUpToBoundary(block: block, maxHeadLetterCount: voicevoxAbsoluteMaxLetterCount - currentDisplayTextCount),
                   current.Add(block: head) {
                    result.append(current)
                    currentBlock = CombinedSpeechBlock(block: tail)
                    currentDisplayTextCount = tail.displayText.count
                    continue
                }
                if forceCloseForVoicevoxCap {
                    // ハード上限に達する場合は、このピースを「足してから閉じる」のではなく
                    // 「足さずに閉じて、このピースから新しいブロックを始める」。
                    // 足してから閉じると、上限(120)前後のピース2つで最大240文字近い
                    // ブロックが作られてしまい、上限の意味が無くなるため
                    // (実際にテストで108+108=216文字のブロックが検出された)。
                    result.append(current)
                    currentBlock = CombinedSpeechBlock(block: block)
                    currentDisplayTextCount = blockDisplayTextCount
                    continue
                }
                // 後続ピースが「間の設定」由来の delay を持っていても、同一話者なら
                // このブロックの末尾ピースとして吸収してブロックを閉じる。読み替え(mod)で切れた
                // 直前ピースが delay 付きピースへ連結できずに孤立するのを防ぎ、句読点(delayの付く
                // 位置)まで一つの発話単位にまとめる。
                // 元々は VOICEVOX 限定だった(AVSpeechSynthesizer の既存分割挙動を守るため)が、
                // AVSpeechSynthesizer でも読み替えヒット位置でブロックが分断されて
                // 語の途中で発話が途切れる問題(特に watchOS で顕著)があったため全エンジンに適用する。
                if block.delay > 0.0 && current.AbsorbTrailingDelayBlock(block: block) {
                    result.append(current)
                    currentBlock = nil
                    currentDisplayTextCount = 0
                    continue
                }
                let shouldKeepGrowing = combinedCount < effectiveMinimumLetterCount || hasValidSuffix == false
                if shouldKeepGrowing && current.Add(block: block) {
                    currentDisplayTextCount = combinedCount
                    continue
                }
                if !shouldKeepGrowing && current.Add(block: block) {
                    result.append(current)
                    currentBlock = nil
                    currentDisplayTextCount = 0
                    continue
                }
                result.append(current)
            }
            currentBlock = CombinedSpeechBlock(block: block)
            // 元々の実装は、ブロックの最初の1ピース(コンストラクタで入る分)を
            // currentDisplayTextCount に含めない仕様だった(AVSpeech向けの既存挙動はそのまま維持する)。
            // VOICEVOXのハード上限判定はこの分の誤差(最大で1ピース分)も許さず厳密に効かせたいので、
            // VOICEVOXの時だけ最初のピースの文字数から数え始める。
            currentDisplayTextCount = isVoicevox ? blockDisplayTextCount : 0
        }
        if let current = currentBlock {
            result.append(current)
        }
        return result
    }
    
    // 読み上げ対象文字列をテキトーな長さに分割します。
    // かなりややこしい動作をするのでこの関数の目的と内部での動作をメモしておきます。
    //
    // 目的としては、読み上げに使われる文字列(読み替えを適用する「前」のもの)について、
    // 読み上げに使う話者設定や、間の設定(読み替えによる間の設定ではない場合のもの)が変化する所で
    // 文字列を分割することが目的です。
    // 例えば、
    //
    // あいうえお「あいうえお。あいうえお」あいうえお
    //
    // という文字列があって、句読点では delay が、会話文(「」で括られる文)では話者設定が変わるようにしたいとすると
    // AVSpeechSynthesizer に渡す文字列は例えば以下の4つに分割される必要があります
    //
    // あいうえお     ← 標準の話者設定
    // 「あいうえお。  ← 会話文用の話者設定
    // あいうえお」   ← 会話文用の話者設定で、delay が入る
    // あいうえお     ← 標準の話者設定
    //
    // このような分割を行うのが本methodの目的です。
    //
    // また、watchOS においては、読み上げ時に willSpeakRange のイベントを受け取るために
    // delegate に willSpeakRange の method を用意すると、
    // 40MBytes程度のメモリを消費してしまうという問題があったため、
    // ある程度の文字数毎に勝手に表示を分けるためにも本文を分割するという用途が求められました。
    // これによって分割された文字列が読み終わるたびに finishSpeak のイベントを受け取ることによって
    // willSpeakRange イベントを受け取らずとも、
    // ある程度の長さの単位で読み上げが進んでいることを感知することができるようになります。
    // ただ、細かい単位での分割時に文章の途中で分割してしまうと、
    // 読み替え対象の文字列の途中で分割されてしまう可能性があるため、
    // 分割自体は句読点や空白、改行といった文字についてのみ行うような仕組みも同時に求められました。
    // そのため、分割点を指示するための withMoreSplitTargets と、
    // あまりにも細かい単位での分割はしないようにするための moreSplitMinimuLetterCount
    // のそれぞれが引数に追加されています。
    //
    // また、読み替え辞書の適用もこの文字列の分割時点で行います。
    static func CategorizeStoryText(content:String, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int, defaultSpeaker:SpeakerSetting, sectionConfigList:[SpeechSectionConfig], waitConfigList:[SpeechWaitConfig], sortedSpeechModArray:[SpeechModSetting]) -> [CombinedSpeechBlock] {
        return CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, indexedSpeechModArray: IndexSpeechModArray(sortedSpeechModArray: sortedSpeechModArray))
    }

    /// 読み替え辞書の索引を外から渡す版。
    ///
    /// 索引作り(5000件超)はページごとにやると馬鹿にならないので、
    /// 何ページも続けて処理する時は作った物を使い回す。
    static func CategorizeStoryText(content:String, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int, defaultSpeaker:SpeakerSetting, sectionConfigList:[SpeechSectionConfig], waitConfigList:[SpeechWaitConfig], indexedSpeechModArray:[Character:[SpeechModSetting]]) -> [CombinedSpeechBlock] {
        guard content.count > 0 else { return [] }
        
        //let startDate = Date()
        var result:[SpeechBlockInfo] = []

        var speakerList:[SpeechSectionConfig] = [SpeechSectionConfig(startText: "", endText: "", speakerSetting: defaultSpeaker)]
        
        var indexedSectionConfigList:[Character:[SpeechSectionConfig]] = [:]
        for sectionConfig in sectionConfigList {
            guard let c = sectionConfig.startText.first else { continue }
            if var list = indexedSectionConfigList[c] {
                list.append(sectionConfig)
                indexedSectionConfigList[c] = list
            }else{
                indexedSectionConfigList[c] = [sectionConfig]
            }
        }
        var indexedWaitConfigList:[Character:[SpeechWaitConfig]] = [:]
        for waitConfig in waitConfigList {
            guard let c = waitConfig.targetText.first else { continue }
            if var list = indexedWaitConfigList[c] {
                list.append(waitConfig)
                indexedWaitConfigList[c] = list
            }else{
                indexedWaitConfigList[c] = [waitConfig]
            }
        }
        var index = content.startIndex
        var currentTextStartIndex = index
        var currentCharacterTarget = Set<Character>()
        for c in indexedWaitConfigList.keys {
            currentCharacterTarget.insert(c)
        }
        for c in indexedSectionConfigList.keys {
            currentCharacterTarget.insert(c)
        }
        for targetString in withMoreSplitTargets {
            if let c = targetString.first {
                currentCharacterTarget.insert(c)
            }
        }
        var speakerEndTextFirstCharacter:Character? = nil
        var currentWaitconfig:SpeechWaitConfig? = nil
        indexLoop: while index < content.endIndex {
            let c = content[index]
            if currentCharacterTarget.contains(c) != true
            && (speakerEndTextFirstCharacter == nil || (speakerEndTextFirstCharacter != c)){
                index = content.index(index, offsetBy: 1)
                continue
            }
            guard let currentSpeakerSetting = speakerList.last else { break }
            let targetString = content[index..<content.endIndex]
            currentWaitconfig = nil
            if let waitConfigList = indexedWaitConfigList[c] {
                for waitSetting in waitConfigList {
                    if waitSetting.delayTimeInSec > 0 && waitSetting.targetText.count > 0 && targetString.starts(with: waitSetting.targetText) {
                        currentWaitconfig = waitSetting
                        break
                    }
                }
            }
            if let sc = speakerEndTextFirstCharacter, sc == c, speakerList.count > 1, let endText = speakerList.last?.endText, endText.count > 0 {
                if targetString.starts(with: endText), let newIndex = content.index(index, offsetBy: endText.count, limitedBy: content.endIndex) {
                    index = newIndex
                    if content.endIndex <= index {
                        index = content.endIndex
                    }
                    let displayText = String(content[currentTextStartIndex..<index])
                    let newBlockArray = generateBlockFromSpeechMod(text: displayText, indexedSpeechModArray: indexedSpeechModArray, speakerSetting: currentSpeakerSetting.speakerSetting, waitConfig: currentWaitconfig)
                    result.append(contentsOf: newBlockArray)
                    currentTextStartIndex = index
                    speakerList.removeLast()
                    if speakerList.count > 1 {
                        if let endText = speakerList.last?.endText, endText.count > 0 {
                            speakerEndTextFirstCharacter = endText[endText.startIndex]
                        }
                    }else{
                        speakerEndTextFirstCharacter = nil
                    }
                    continue
                }
            }
            if let sectionConfigList = indexedSectionConfigList[c] {
                for sectionConfig in sectionConfigList {
                    if targetString.starts(with: sectionConfig.startText), let newIndex = content.index(index, offsetBy: sectionConfig.startText.count, limitedBy: content.endIndex) {
                        if currentTextStartIndex < index {
                            if content.endIndex <= index {
                                index = content.endIndex
                            }
                            let displayText = String(content[currentTextStartIndex..<index])
                            let newBlockArray = generateBlockFromSpeechMod(text: displayText, indexedSpeechModArray: indexedSpeechModArray, speakerSetting: currentSpeakerSetting.speakerSetting, waitConfig: currentWaitconfig)
                            result.append(contentsOf: newBlockArray)
                        }
                        currentTextStartIndex = index
                        index = newIndex
                        speakerList.append(sectionConfig)
                        if sectionConfig.endText.count > 0 {
                            speakerEndTextFirstCharacter = sectionConfig.endText[sectionConfig.endText.startIndex]
                        }
                        continue indexLoop
                    }
                }
            }
            if content[currentTextStartIndex..<index].count > moreSplitMinimumLetterCount {
                for char in withMoreSplitTargets {
                    if targetString.starts(with: char), let newIndex = content.index(index, offsetBy: char.count, limitedBy: content.endIndex) {
                        index = newIndex
                        if content.endIndex <= index {
                            index = content.endIndex
                        }
                        let displayText = String(content[currentTextStartIndex..<index])
                        let newBlockArray = generateBlockFromSpeechMod(text: displayText, indexedSpeechModArray: indexedSpeechModArray, speakerSetting: currentSpeakerSetting.speakerSetting, waitConfig: currentWaitconfig)
                        result.append(contentsOf: newBlockArray)
                        currentTextStartIndex = index
                        continue indexLoop
                    }
                }
            }
            if let waitConfig = currentWaitconfig, let newIndex = content.index(index, offsetBy: waitConfig.targetText.count, limitedBy: content.endIndex) {
                index = newIndex
                if content.endIndex <= index {
                    index = content.endIndex
                }
                let displayText = String(content[currentTextStartIndex..<index])
                let newBlockArray = generateBlockFromSpeechMod(text: displayText, indexedSpeechModArray: indexedSpeechModArray, speakerSetting: currentSpeakerSetting.speakerSetting, waitConfig: waitConfig)
                result.append(contentsOf: newBlockArray)
                currentTextStartIndex = index
                continue indexLoop
            }
            index = content.index(index, offsetBy: 1)
        }
        if currentTextStartIndex < content.endIndex {
            let currentSpeaker = speakerList.last?.speakerSetting ?? defaultSpeaker
            let displayText = String(content[currentTextStartIndex..<content.endIndex])
            let newBlockArray = generateBlockFromSpeechMod(text: displayText, indexedSpeechModArray: indexedSpeechModArray, speakerSetting: currentSpeaker, waitConfig: currentWaitconfig)
            result.append(contentsOf: newBlockArray)
        }
        let combinedResult = ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray: result, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, splitTargetLastLetters: withMoreSplitTargets)
        //print("diffDate: \(Date().timeIntervalSince(startDate))")
        return combinedResult
    }
    
    /// 読み替え設定の並び順。長い before から順に見る必要があるのでこの順序になっている。
    /// 並べ替えと併合で必ず同じ物を使う(食い違うと同じ本文から違うブロックが出来て、
    /// 作ってある音声キャッシュが命中しなくなる)。
    static func SpeechModSettingIsOrderedBefore(_ a:SpeechModSetting, _ b:SpeechModSetting) -> Bool {
        if a.beforeCount > b.beforeCount { return true }
        if a.beforeCount < b.beforeCount { return false }
        if a.before == b.before {
            if a.afterCount > b.afterCount { return true }
            if a.afterCount < b.afterCount { return false }
            return a.after < b.after
        }
        return a.before < b.before
    }

    static func SpeechModArraySort(speechModArray:[SpeechModSetting]) -> [SpeechModSetting] {
        return speechModArray.sorted(by: SpeechModSettingIsOrderedBefore)
    }

    /// 並べ替え済みの2つを併合する。
    ///
    /// 標準の読み替え辞書は5000件超あり、これをページごとに並べ替え直すと
    /// 1ページあたり十数ミリ秒を捨てる事になる(本文に依存しないのに)。
    /// 本文に依らない分を小説ごとに1回だけ並べ替えておき、本文ごとに変わる分
    /// (正規表現の展開結果とルビ)だけを並べ替えて、ここで併合する。
    ///
    /// 同じ比較関数で並んでいる2つを併合した結果は、連結してから並べ替えた物と同じ順になる
    /// (before と after が完全に同じ物同士の前後だけは決まらないが、それは元の
    ///  `sorted(by:)` も安定並べ替えではないので元から決まっていないし、
    ///  重複除去でどちらを残しても同じ物になる)。
    static func MergeSortedSpeechModArray(_ a:[SpeechModSetting], _ b:[SpeechModSetting]) -> [SpeechModSetting] {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        var result:[SpeechModSetting] = []
        result.reserveCapacity(a.count + b.count)
        var indexA = 0
        var indexB = 0
        while indexA < a.count && indexB < b.count {
            if SpeechModSettingIsOrderedBefore(b[indexB], a[indexA]) {
                result.append(b[indexB])
                indexB += 1
            } else {
                result.append(a[indexA])
                indexA += 1
            }
        }
        if indexA < a.count { result.append(contentsOf: a[indexA...]) }
        if indexB < b.count { result.append(contentsOf: b[indexB...]) }
        return result
    }
    
    static func UniqSpeechModArray(speechModArray:[SpeechModSetting]) -> [SpeechModSetting] {
        var result:[SpeechModSetting] = []
        var currentBeforeText = ""
        for modSetting in speechModArray {
            if modSetting.before == currentBeforeText {
                continue
            }
            result.append(modSetting)
            currentBeforeText = modSetting.before
        }
        return result
    }
    
    /// 読み替え設定を「before の先頭文字」で引けるようにまとめる。
    /// 渡す配列は並べ替え済みである事が前提(各引き出しの中でも並び順が保たれる)。
    ///
    /// 注意: 以前ここは
    ///   `if var settingArray = result[c] { settingArray.append(setting) }`
    /// と書かれていて、**コピーに追記して書き戻していなかった**ため、
    /// 同じ先頭文字を持つ2件目以降が全て捨てられていた。
    /// (この関数自体はどこからも使われていなかったので実害は出ていなかった)
    /// `result[c, default: []].append()` なら、その場で書き換わる上に
    /// 配列の複製も起きない。
    static func IndexSpeechModArray(sortedSpeechModArray:[SpeechModSetting]) -> [Character:[SpeechModSetting]] {
        var result:[Character:[SpeechModSetting]] = [:]
        for setting in sortedSpeechModArray {
            guard let c = setting.before.first else { continue }
            result[c, default: []].append(setting)
        }
        return result
    }

    /// 索引に、本文ごとに変わる読み替え(正規表現の展開結果やルビ)を差し込む。
    ///
    /// 引き出しごとに併合して重複除去する。同じ before は必ず同じ先頭文字なので、
    /// 引き出し単位で重複除去しても、全体を並べ替えてから重複除去したのと同じ結果になる。
    /// 触る引き出しだけを作り直すので、辞書全体(5000件超)を毎ページ作り直さずに済む。
    /// - Parameter sortedContentDependentArray: 並べ替え済みの、本文ごとに変わる読み替え。
    static func MergeIntoIndexedSpeechModArray(_ indexed:[Character:[SpeechModSetting]], sortedContentDependentArray:[SpeechModSetting]) -> [Character:[SpeechModSetting]] {
        guard sortedContentDependentArray.isEmpty == false else { return indexed }
        var addedByCharacter:[Character:[SpeechModSetting]] = [:]
        for setting in sortedContentDependentArray {
            guard let c = setting.before.first else { continue }
            addedByCharacter[c, default: []].append(setting)
        }
        var result = indexed
        for (c, added) in addedByCharacter {
            result[c] = UniqSpeechModArray(speechModArray: MergeSortedSpeechModArray(indexed[c] ?? [], added))
        }
        return result
    }
    
    static func ApplySpeechModTo(text:String, indexedSpeechModArray:[Character:[SpeechModSetting]]) -> String {
        var result = ""
        var index = text.startIndex
        whileLoop: while index < text.endIndex {
            let c = text[index]
            guard let sortedSpeechModArray = indexedSpeechModArray[c] else {
                result.append(text[index])
                index = text.index(index, offsetBy: 1)
                continue
            }
            let targetText = text[index..<text.endIndex]
            for speechMod in sortedSpeechModArray {
                if targetText.starts(with: speechMod.before) {
                    result += speechMod.after
                    index = text.index(index, offsetBy: speechMod.before.count)
                    continue whileLoop
                }
            }
            result.append(text[index])
            index = text.index(index, offsetBy: 1)
        }
        return result
    }
    
    static func generateBlockFromSpeechMod(text:String, indexedSpeechModArray:[Character:[SpeechModSetting]], speakerSetting: SpeakerSetting, waitConfig: SpeechWaitConfig?) -> [SpeechBlockInfo] {
        var result:[SpeechBlockInfo] = []
        var index = text.startIndex
        var currentStartIndex = index
        // この関数に渡されるチャンクは、呼び出し側(CategorizeStoryText)が「間の設定」(wait config)の
        // 対象文字(。、等)で区切った単位で、必ずその対象文字がチャンク末尾に来る。
        // よって遅延(間)は「その句読点の後」= このチャンクの最後のピースに付けるべき。
        // 以前は最初のピースに付けていたため、チャンク内が読み替え(mod)で複数ピースに割れると
        // 遅延が先頭ピースに乗ってしまい、(a)間が本来より前で発動する、(b)遅延付きピースは
        // それ以上連結できない(ConcatinateのAdd()ガード)ため、"読み上げ|る" のように語の途中で
        // ブロックが分断される、という2つの不具合を起こしていた。全ピースをdelay=0で作り、
        // 最後に末尾ピースへだけ遅延を移す。
        let waitDelayTimeInSec = TimeInterval(waitConfig?.delayTimeInSec ?? 0.0)
        whileLoop: while index < text.endIndex {
            let c = text[index]
            guard let sortedSpeechModArray = indexedSpeechModArray[c] else {
                index = text.index(index, offsetBy: 1)
                continue
            }
            let targetText = text[index..<text.endIndex]
            for speechMod in sortedSpeechModArray {
                // この読み替えが対象としているエンジン以外(例: 標準辞書=AVSpeechSynthesizer専用を
                // VOICEVOX話者へ)は適用しない。
                if speechMod.isAppliedTo(speechEngineType: speakerSetting.type) == false { continue }
                if targetText.starts(with: speechMod.before) {
                    if currentStartIndex != index {
                        let displayText = String(text[currentStartIndex..<index])
                        let speechText = displayText
                        let blockInfo = SpeechBlockInfo(speechText: speechText, displayText: displayText, voiceIdentifier: speakerSetting.voiceIdentifier, locale: speakerSetting.locale, pitch: speakerSetting.pitch, rate: speakerSetting.rate, volume: speakerSetting.volume, delay: 0.0, isMod: false, type: speakerSetting.type)
                        result.append(blockInfo)
                    }
                    let nextIndex = text.index(index, offsetBy: speechMod.before.count)
                    let displayText = String(text[index..<nextIndex])
                    let speechText = speechMod.after
                    let blockInfo = SpeechBlockInfo(speechText: speechText, displayText: displayText, voiceIdentifier: speakerSetting.voiceIdentifier, locale: speakerSetting.locale, pitch: speakerSetting.pitch, rate: speakerSetting.rate, volume: speakerSetting.volume, delay: 0.0, isMod: true, type: speakerSetting.type)
                    result.append(blockInfo)
                    index = nextIndex
                    currentStartIndex = nextIndex
                    continue whileLoop
                }
            }
            index = text.index(index, offsetBy: 1)
        }
        if currentStartIndex != index {
            let displayText = String(text[currentStartIndex..<index])
            let speechText = displayText
            let blockInfo = SpeechBlockInfo(speechText: speechText, displayText: displayText, voiceIdentifier: speakerSetting.voiceIdentifier, locale: speakerSetting.locale, pitch: speakerSetting.pitch, rate: speakerSetting.rate, volume: speakerSetting.volume, delay: 0.0, isMod: false, type: speakerSetting.type)
            result.append(blockInfo)
        }
        // 遅延(間)はこのチャンクの最後のピースに付ける。
        if waitDelayTimeInSec > 0, let last = result.last {
            result[result.count - 1] = SpeechBlockInfo(speechText: last.speechText, displayText: last.displayText, voiceIdentifier: last.voiceIdentifier, locale: last.locale, pitch: last.pitch, rate: last.rate, volume: last.volume, delay: waitDelayTimeInSec, isMod: last.isMod, type: last.type)
        }
        return result
    }
    
    static func GenerateRubyModString(text:String, notRubyString:String, isDisableNarouRuby:Bool) -> [SpeechModSetting] {
        let rubyPatternList:[String]
        if isDisableNarouRuby == false {
            // 小説家になろうでのルビの扱い https://syosetu.com/man/ruby/ に準拠します
            // 正規表現における文字集合の書き方
            // 平仮名 \p{Hiragana}
            // カタカナ \p{Katakana}
            // 漢字 \p{Han}
            rubyPatternList = [
                "\\|([^|《(（]+?)[《(（]([^》)）]+?)[》)）]", // | のある場合
                "\\｜([^｜《(（]+?)[《(（]([^》)）]+?)[》)）]", // ｜ のある場合
                "([\\p{Han}]+?)[《(（]([^》)）]+?)[》)）]", // 《 》 の前が漢字
                "([\\p{Han}]+?)[《(（]([\\p{Hiragana}\\p{Katakana}]+?)[》)）]", // () の前が漢字かつ、() の中がカタカナまたは平仮名
            ]
        }else{
            // ことせかい 由来のルビ表記を相手にします
            rubyPatternList = ["\\|([^|(]+?)[(]([^)]+?)[)]"]
        }
        var notRubyRegexp:NSRegularExpression? = nil
        if notRubyString.count > 0, let notRubyRe = try? NSRegularExpression(pattern: "^[\(notRubyString)]+$", options: []) {
            notRubyRegexp = notRubyRe
        }
        var result:[SpeechModSetting] = []
        let nsString = text as NSString
        for pattern in rubyPatternList {
            guard let regexp = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let hitList = regexp.matches(in: text, options: [], range: NSMakeRange(0, text.count))
            for hit in hitList {
                guard hit.numberOfRanges == 3 else { continue }
                let allRange = hit.range(at: 0)
                if allRange.length <= 0 { continue }
                let toRange = hit.range(at: 2)
                // String.index(_,offsetBy:)が非常に遅い
                // 参考: https://stackoverflow.com/questions/47336928/swift-4-string-index-offset-by-too-slow-while-processing-a-large-string
                // ので、NSString.substring(with:) を使う事にします。
                let toString = nsString.substring(with: toRange)
//                let fromIndex = text.index(text.startIndex, offsetBy: toRange.location)
//                let toIndex = text.index(text.startIndex, offsetBy: toRange.location + toRange.length)
//                let toString = String(text[fromIndex..<toIndex])
                if let notRubyRegexp = notRubyRegexp, notRubyRegexp.matches(in: toString, options: [], range: NSMakeRange(0, toString.count)).count > 0 { continue }
                let fromString = nsString.substring(with: allRange)
//                let allFromIndex = text.index(text.startIndex, offsetBy: allRange.location)
//                let allToIndex = text.index(text.startIndex, offsetBy: allRange.location + allRange.length)
//                let fromString = String(text[allFromIndex..<allToIndex])
                
                let setting = SpeechModSetting(before: fromString, after: toString, isUseRegularExpression: false)
                result.append(setting)
            }
        }
        return result
    }
    
    //
    #if !os(watchOS)

    /// 1つの小説について、読み上げに使う設定一式。
    ///
    /// これを求めるには Realm から話者・会話文の話者割り当て・間の設定・読み替え辞書
    /// (標準辞書だけで5000件超)を読み出して組み立てる必要があり、**1ページあたり数百ミリ秒**
    /// かかる。ページごとに毎回作り直すと、本文を舐める処理(音声キャッシュの生成や、
    /// 使われなくなった音声の調査)がページ数に比例して重くなる。
    /// 小説の中では変わらない値なので、まとめて処理する側は一度だけ作って使い回す。
    ///
    /// ルビ由来の読み替えだけは本文ごとに変わるので、ここには含めずページ単位で足す。
    struct StorySpeechSettings {
        let defaultSpeaker:SpeakerSetting
        let sectionConfigList:[SpeechSectionConfig]
        let waitConfigList:[SpeechWaitConfig]
        /// ルビ由来を除いた読み替え設定。
        let speechModSettingList:[SpeechModSetting]
        let isOverrideRubyEnabled:Bool
        let notRubyCharactorStringArray:String
        let isDisableNarouRuby:Bool

        /// 本文に依らない(正規表現でない)読み替えを、並べ替えて索引まで作った状態で持っておく。
        /// 標準の読み替え辞書だけで5000件超あり、並べ替えも索引作りも本文に依らないのに
        /// ページごとにやり直すと、ページの長さと関係なく毎回その分を捨てる事になる。
        let indexedPreSortedSpeechModArray:[Character:[SpeechModSetting]]
        /// 本文ごとに展開が変わる(正規表現の)読み替え。
        let regexpSpeechModArray:[SpeechModSetting]

        init(defaultSpeaker:SpeakerSetting, sectionConfigList:[SpeechSectionConfig], waitConfigList:[SpeechWaitConfig], speechModSettingList:[SpeechModSetting], isOverrideRubyEnabled:Bool, notRubyCharactorStringArray:String, isDisableNarouRuby:Bool) {
            self.defaultSpeaker = defaultSpeaker
            self.sectionConfigList = sectionConfigList
            self.waitConfigList = waitConfigList
            self.speechModSettingList = speechModSettingList
            self.isOverrideRubyEnabled = isOverrideRubyEnabled
            self.notRubyCharactorStringArray = notRubyCharactorStringArray
            self.isDisableNarouRuby = isDisableNarouRuby
            self.indexedPreSortedSpeechModArray = StoryTextClassifier.IndexSpeechModArray(
                sortedSpeechModArray: StoryTextClassifier.UniqSpeechModArray(
                    speechModArray: StoryTextClassifier.SpeechModArraySort(
                        speechModArray: speechModSettingList.filter { $0.isUseRegularExpression == false })))
            self.regexpSpeechModArray = speechModSettingList.filter { $0.isUseRegularExpression }
        }
    }

    /// 段階ごとの所要時間をログに出すか(遅い所を実機で特定するため)。
    nonisolated(unsafe) static var isGatherStorySpeechSettingsProfilingEnabled = false
    /// データの規模のログは1回だけでよい。
    nonisolated(unsafe) private static var isDataShapeLogged = false
    static func resetSpeechSettingsDataShapeLog() { isDataShapeLogged = false }

    static func GatherStorySpeechSettings(novelID:String) -> StorySpeechSettings {
        return RealmUtil.RealmBlock { (realm) -> StorySpeechSettings in
            return GatherStorySpeechSettings(realm: realm, novelID: novelID)
        }
    }

    /// 既に開いてある Realm を使う版。
    /// 何作品もまとめて処理する時は、Realm を開き直さずにこちらを使う。
    static func GatherStorySpeechSettings(realm:Realm, novelID:String) -> StorySpeechSettings {
        return { () -> StorySpeechSettings in
            let profiling = isGatherStorySpeechSettingsProfilingEnabled
            if profiling && isDataShapeLogged == false {
                isDataShapeLogged = true
                // どこが重いのかは、どのデータがどれだけあるかで決まる。
                // 手元で再現できるように、実機のデータの規模を1回だけ出す。
                let sectionConfigs = realm.objects(RealmSpeechSectionConfig.self).filter("isDeleted = false")
                let modSettings = realm.objects(RealmSpeechModSetting.self).filter("isDeleted = false")
                let sectionTargetTotal = sectionConfigs.reduce(0) { $0 + $1.targetNovelIDArray.count }
                let modTargetTotal = modSettings.reduce(0) { $0 + $1.targetNovelIDArray.count }
                NSLog("NovelSpeaker.SpeechSettingsDataShape: 小説=%d 話者設定=%d 会話文設定=%d(対象小説の延べ数=%d) 読み替え=%d(対象小説の延べ数=%d) 間の設定=%d",
                      realm.objects(RealmNovel.self).filter("isDeleted = false").count,
                      realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false").count,
                      sectionConfigs.count, sectionTargetTotal,
                      modSettings.count, modTargetTotal,
                      realm.objects(RealmSpeechWaitConfig.self).filter("isDeleted = false").count)
            }
            var phaseStart = Date()
            var phaseLog = ""
            func recordPhase(_ name:String) {
                guard profiling else { return }
                phaseLog += String(format: " %@=%.0fms", name, Date().timeIntervalSince(phaseStart) * 1000)
                phaseStart = Date()
            }
            let defaultSpeaker:RealmSpeakerSetting
            if let novelDefaultSpeaker = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.defaultSpeakerWith(realm: realm) {
                defaultSpeaker = novelDefaultSpeaker
            }else if let globalStateDefaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) {
                defaultSpeaker = globalStateDefaultSpeaker
            }else{
                defaultSpeaker = RealmSpeakerSetting()
            }
            
            recordPhase("話者")

            let sectionConfigList:[SpeechSectionConfig]
            if let speechSectionConfigDictValues = RealmSpeechSectionConfig.SearchSettingsFor(realm: realm, novelID: novelID) {
                recordPhase("会話文の検索")
                sectionConfigList = ConvertSpeechSectionConfig(realm: realm, fromArray: Array(speechSectionConfigDictValues), defaultSpeaker: defaultSpeaker)
            }else{
                sectionConfigList = []
            }
            recordPhase("会話文の変換")

            var waitConfigList:[SpeechWaitConfig] = []
            if let allWaitConfigList = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm)?.map({ SpeechWaitConfig(from: $0) }) {
                waitConfigList = Array(allWaitConfigList)
            }
            var speechModSettingList:[SpeechModSetting] = []
            // 非推奨型であれば読み替え辞書に登録する形にします。
            if let isWaitExperimentalWait = RealmGlobalState.GetInstanceWith(realm: realm)?.isSpeechWaitSettingUseExperimentalWait, isWaitExperimentalWait == true {
                for waitConfig in waitConfigList {
                    let count = Int(waitConfig.delayTimeInSec * 10)
                    if count <= 0 { continue }
                    let modSetting = RealmSpeechModSetting()
                    modSetting.before = waitConfig.targetText
                    modSetting.after = "。" + String(repeating: "_。", count: count)
                    modSetting.isUseRegularExpression = false
                    speechModSettingList.append(SpeechModSetting(from: modSetting))
                }
                waitConfigList = []
            }
            
            // 正規表現周りでゴニョゴニョする奴や、
            // URLを読まないようにするなどといった動的に読み替え辞書を生成するのはここでやります。
            // 標準の読み替え辞書由来のエントリは「AVSpeechSynthesizer向け」とみなして印を付ける
            //(VOICEVOX 話者のブロックではこの印の付いた読み替えを適用しない)。
            recordPhase("間の設定")

            let defaultSpeechModKeySet = NovelSpeakerUtility.GetDefaultSpeechModKeySet()
            recordPhase("標準辞書の鍵集合")
            if let modSettingListFromSetting = RealmSpeechModSetting.SearchSettingsFor(realm: realm, novelID: novelID)?.map({ (realmModSetting) -> SpeechModSetting in
                let key = NovelSpeakerUtility.DefaultSpeechModKey(before: realmModSetting.before, after: realmModSetting.after, isRegexp: realmModSetting.isUseRegularExpression)
                // 標準辞書由来のエントリは AVSpeechSynthesizer 専用として扱う。それ以外(ユーザー追加)は
                // 空配列=全エンジンに適用。
                let targetEngines:[String] = defaultSpeechModKeySet.contains(key) ? ["AVSpeechSynthesizer"] : []
                return SpeechModSetting(from: realmModSetting, targetSpeechEngineTypeArray: targetEngines)
            }) {
                speechModSettingList.append(contentsOf: modSettingListFromSetting)
            }
            recordPhase("読み替え辞書(\(speechModSettingList.count)件)")
            
            var isOverrideRubyEnabled = false
            var notRubyCharactorStringArray = ""
            var isIgnoreURIStringSpeechEnabled = false
            var isDisableNarouRuby = false
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled == true {
                    let modSetting = SpeechModSetting(
                        before: "\\s+",
                        after: "α",
                        isUseRegularExpression: true)
                    speechModSettingList.append(modSetting)
                }
                isOverrideRubyEnabled = globalState.isOverrideRubyIsEnabled
                notRubyCharactorStringArray = globalState.notRubyCharactorStringArray
                isIgnoreURIStringSpeechEnabled = globalState.isIgnoreURIStringSpeechEnabled
                isDisableNarouRuby = globalState.isDisableNarouRuby
            }
            if isIgnoreURIStringSpeechEnabled {
                let modSetting = SpeechModSetting(
                    before: ignoreURIStringRegexpPattern,
                    after: "",
                    isUseRegularExpression: true
                )
                speechModSettingList.append(modSetting)
            }
            recordPhase("その他")
            defer {
                if profiling {
                    NSLog("NovelSpeaker.GatherSpeechSettings:%@", phaseLog)
                }
            }
            return StorySpeechSettings(
                defaultSpeaker: SpeakerSetting(from: defaultSpeaker),
                sectionConfigList: sectionConfigList,
                waitConfigList: waitConfigList,
                speechModSettingList: speechModSettingList,
                isOverrideRubyEnabled: isOverrideRubyEnabled,
                notRubyCharactorStringArray: notRubyCharactorStringArray,
                isDisableNarouRuby: isDisableNarouRuby
            )
        }()
    }

    /// 設定を渡してブロック分割する。まとめて処理する側はこちらを使う
    /// (設定の組み立てを小説ごとに1回で済ませられる)。
    static func CategorizeStoryText(story:Story, settings:StorySpeechSettings, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int) -> [CombinedSpeechBlock] {
        // 本文に依らない分は settings が並べ替え済みで持っているので、
        // 本文ごとに変わる分(正規表現の展開結果とルビ)だけを並べ替えて併合する。
        // 出来上がるブロックは、全部まとめて並べ替えた場合と同一になる
        //(StoryTextClassifierSpeechModOrderTest で確認している)。
        // ここが食い違うと、同じ本文から違うブロックが出来てしまい、
        // 作ってある音声キャッシュが命中しなくなる。
        var contentDependent = settings.regexpSpeechModArray
        if settings.isOverrideRubyEnabled {
            contentDependent.append(contentsOf: GenerateRubyModString(text: story.content, notRubyString: settings.notRubyCharactorStringArray, isDisableNarouRuby: settings.isDisableNarouRuby))
        }
        return CategorizeStoryText(content: story.content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: settings.defaultSpeaker, sectionConfigList: settings.sectionConfigList, waitConfigList: settings.waitConfigList, indexedPreSortedSpeechModArray: settings.indexedPreSortedSpeechModArray, contentDependentSpeechModArray: contentDependent)
    }

    static func CategorizeStoryText(story:Story, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int) -> [CombinedSpeechBlock] {
        return CategorizeStoryText(story: story, settings: GatherStorySpeechSettings(novelID: story.novelID), withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount)
    }
    #endif

    // speechModArray の正規表現周りを計算して単なる読み替え設定にして、
    // 読み替え前の文字列長でソートされた状態にする部分だけを別関数としておきます
    /// 正規表現の読み替えを、この本文に実際に現れた形へ展開する。
    /// 正規表現でない物はそのまま通す。
    static func ExpandSpeechModArray(content:String, speechModArray:[SpeechModSetting]) -> [SpeechModSetting] {
        var speechModSettingList:[SpeechModSetting] = []
        var beforeHit:[String:Bool] = [:]
        for modSetting in speechModArray {
            if modSetting.isUseRegularExpression {
                if let regexp = try? NSRegularExpression(pattern: modSetting.before, options: []) {
                    regexp.enumerateMatches(in: content, options: [], range: NSMakeRange(0, content.count)) { (result, flags, stop) in
                        guard let result = result, let contentRange = Range(result.range, in: content) else { return }
                        let before = String(content[contentRange])
                        if beforeHit[before] == true { return }
                        let after = regexp.stringByReplacingMatches(in: before, options: [], range: NSMakeRange(0, before.count), withTemplate: modSetting.after)
                        let setting = SpeechModSetting(before: before, after: after, isUseRegularExpression: false, targetSpeechEngineTypeArray: modSetting.targetSpeechEngineTypeArray)
                        speechModSettingList.append(setting)
                        beforeHit[before] = true
                    }
                }
            }else{
                speechModSettingList.append(modSetting)
            }
        }
        return speechModSettingList
    }

    static func CategorizeStoryText(content:String, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int, defaultSpeaker:SpeakerSetting, sectionConfigList:[SpeechSectionConfig], waitConfigList:[SpeechWaitConfig], speechModArray:[SpeechModSetting]) -> [CombinedSpeechBlock] {
        let sortedSpeechModArray = UniqSpeechModArray(speechModArray: SpeechModArraySort(speechModArray: ExpandSpeechModArray(content: content, speechModArray: speechModArray)))

        return CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, sortedSpeechModArray: sortedSpeechModArray)
    }

    /// 本文に依らない分を並べ替え済みで受け取る版。
    /// 本文ごとに変わる分(正規表現の展開結果とルビ)だけを並べ替えて併合する。
    /// 結果は上の版と同一になる(StoryTextClassifierSpeechModOrderTest で確認している)。
    static func CategorizeStoryText(content:String, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int, defaultSpeaker:SpeakerSetting, sectionConfigList:[SpeechSectionConfig], waitConfigList:[SpeechWaitConfig], indexedPreSortedSpeechModArray:[Character:[SpeechModSetting]], contentDependentSpeechModArray:[SpeechModSetting]) -> [CombinedSpeechBlock] {
        let expanded = SpeechModArraySort(speechModArray: ExpandSpeechModArray(content: content, speechModArray: contentDependentSpeechModArray))
        let indexed = MergeIntoIndexedSpeechModArray(indexedPreSortedSpeechModArray, sortedContentDependentArray: expanded)

        return CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, indexedSpeechModArray: indexed)
    }
}
