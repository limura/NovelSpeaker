//
//  StoryTextClassifier.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import RealmSwift
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
}
struct SpeechWaitConfig {
    let targetText : String
    let delayTimeInSec : Float
    init(from:RealmSpeechWaitConfig) {
        targetText = from.targetText
        delayTimeInSec = from.delayTimeInSec
    }
}
struct SpeechModSetting {
    let before : String
    let after : String
    let isUseRegularExpression : Bool
    init(from:RealmSpeechModSetting) {
        before = from.before
        after = from.after
        isUseRegularExpression = from.isUseRegularExpression
    }
    init(before:String, after:String, isUseRegularExpression:Bool) {
        self.before = before
        self.after = after
        self.isUseRegularExpression = isUseRegularExpression
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
    let delay:TimeInterval
    
    init(block:SpeechBlockInfo) {
        voiceIdentifier = block.voiceIdentifier
        locale = block.locale
        pitch = block.pitch
        rate = block.rate
        volume = block.volume
        delay = block.delay
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
        guard checkDoubleEqual(a: 0.0, b: block.delay) // delay があるなら合成してはいけません
            && checkFloatEqual(a: pitch, b: block.pitch)
            && checkFloatEqual(a: rate, b: block.rate)
            && checkFloatEqual(a: volume, b: block.volume)
            && voiceIdentifier == block.voiceIdentifier
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
    
    // 同じ話者の設定SpeechBlockInfoが連続している物を纏めた CombiledSpeechBlock へと変換します。
    // 一応、表示用の文字列長が moreSplitMinimumLetterCount よりも長い文字列になるようならそこで分割しようとします。
    // ただ、元々の文字列長が長すぎる場合はそのままの長さで残ってしまいますし、
    // 日本語として切れて良い場所かどうかは考慮に入れていないために不自然な所で区切られた文になる可能性もある
    // という事を理解しておいてください。
    static func ConcatinateSameVoiceSettingSpeechBlock(speechBlockArray:[SpeechBlockInfo], moreSplitMinimumLetterCount:Int, splitTargetLastLetters:[String]) -> [CombinedSpeechBlock] {
        var result:[CombinedSpeechBlock] = []
        var currentBlock:CombinedSpeechBlock? = nil
        var currentDisplayTextCount = 0
        for block in speechBlockArray {
            let displayText = block.displayText
            let blockDisplayTextCount = displayText.count
            var hasValidSuffix = false
            for lastLetter in splitTargetLastLetters {
                if displayText.hasSuffix(lastLetter) {
                    hasValidSuffix = true
                    break
                }
            }
            if let current = currentBlock {
                if ((currentDisplayTextCount + blockDisplayTextCount) < moreSplitMinimumLetterCount || hasValidSuffix == false)
                    && current.Add(block: block) {
                    currentDisplayTextCount += blockDisplayTextCount
                    continue
                }
                if ((currentDisplayTextCount + blockDisplayTextCount) >= moreSplitMinimumLetterCount && hasValidSuffix == true)
                    && current.Add(block: block) {
                    result.append(current)
                    currentBlock = nil
                    currentDisplayTextCount = 0
                    continue
                }
                result.append(current)
            }
            currentBlock = CombinedSpeechBlock(block: block)
            currentDisplayTextCount = 0
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
        var indexedSpeechModArray:[Character:[SpeechModSetting]] = [:]
        for modSetting in sortedSpeechModArray {
            guard let c = modSetting.before.first else { continue }
            if var list = indexedSpeechModArray[c] {
                list.append(modSetting)
                indexedSpeechModArray[c] = list
            }else{
                indexedSpeechModArray[c] = [modSetting]
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
    
    static func SpeechModArraySort(speechModArray:[SpeechModSetting]) -> [SpeechModSetting] {
        return speechModArray.sorted { (a, b) -> Bool in
            if a.before.count > b.before.count { return true }
            if a.before.count < b.before.count { return false }
            if a.before == b.before {
                if a.after.count > b.after.count { return true }
                if a.after.count < b.after.count { return false }
                return a.after < b.after
            }
            return a.before < b.before
        }
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
    
    static func IndexSpeechModArray(sortedSpeechModArray:[SpeechModSetting]) -> [Character:[SpeechModSetting]] {
        var result:[Character:[SpeechModSetting]] = [:];
        for setting in sortedSpeechModArray {
            if setting.before.count <= 0 {
                continue
            }
            let c = setting.before[setting.before.startIndex]
            if var settingArray = result[c] {
                settingArray.append(setting)
            }else{
                result[c] = [setting]
            }
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
        var waitConfing_delayTimeInSec = TimeInterval(waitConfig?.delayTimeInSec ?? 0.0)
        whileLoop: while index < text.endIndex {
            let c = text[index]
            guard let sortedSpeechModArray = indexedSpeechModArray[c] else {
                index = text.index(index, offsetBy: 1)
                continue
            }
            let targetText = text[index..<text.endIndex]
            for speechMod in sortedSpeechModArray {
                if targetText.starts(with: speechMod.before) {
                    if currentStartIndex != index {
                        let displayText = String(text[currentStartIndex..<index])
                        let speechText = displayText
                        let blockInfo = SpeechBlockInfo(speechText: speechText, displayText: displayText, voiceIdentifier: speakerSetting.voiceIdentifier, locale: speakerSetting.locale, pitch: speakerSetting.pitch, rate: speakerSetting.rate, volume: speakerSetting.volume, delay: waitConfing_delayTimeInSec, isMod: false)
                        waitConfing_delayTimeInSec = TimeInterval(0.0)
                        result.append(blockInfo)
                    }
                    let nextIndex = text.index(index, offsetBy: speechMod.before.count)
                    let displayText = String(text[index..<nextIndex])
                    let speechText = speechMod.after
                    let blockInfo = SpeechBlockInfo(speechText: speechText, displayText: displayText, voiceIdentifier: speakerSetting.voiceIdentifier, locale: speakerSetting.locale, pitch: speakerSetting.pitch, rate: speakerSetting.rate, volume: speakerSetting.volume, delay: waitConfing_delayTimeInSec, isMod: true)
                    waitConfing_delayTimeInSec = TimeInterval(0.0)
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
            let blockInfo = SpeechBlockInfo(speechText: speechText, displayText: displayText, voiceIdentifier: speakerSetting.voiceIdentifier, locale: speakerSetting.locale, pitch: speakerSetting.pitch, rate: speakerSetting.rate, volume: speakerSetting.volume, delay: waitConfing_delayTimeInSec, isMod: false)
            waitConfing_delayTimeInSec = TimeInterval(0.0)
            result.append(blockInfo)
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
    static func CategorizeStoryText(story:Story, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int) -> [CombinedSpeechBlock] {
        RealmUtil.RealmBlock { (realm) -> [CombinedSpeechBlock] in
            let defaultSpeaker:RealmSpeakerSetting
            if let novelDefaultSpeaker = RealmNovel.SearchNovelWith(realm: realm, novelID: story.novelID)?.defaultSpeakerWith(realm: realm) {
                defaultSpeaker = novelDefaultSpeaker
            }else if let globalStateDefaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) {
                defaultSpeaker = globalStateDefaultSpeaker
            }else{
                defaultSpeaker = RealmSpeakerSetting()
            }
            
            let sectionConfigList:[SpeechSectionConfig]
            if let speechSectionConfigDictValues = RealmSpeechSectionConfig.SearchSettingsFor(realm: realm, novelID: story.novelID) {
                sectionConfigList = ConvertSpeechSectionConfig(realm: realm, fromArray: Array(speechSectionConfigDictValues), defaultSpeaker: defaultSpeaker)
            }else{
                sectionConfigList = []
            }
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
            if let modSettingListFromSetting = RealmSpeechModSetting.SearchSettingsFor(realm: realm, novelID: story.novelID)?.map({ SpeechModSetting(from: $0) }) {
                speechModSettingList.append(contentsOf: modSettingListFromSetting)
            }
            
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
                    before: "[a-zA-Z][0-9a-zA-Z-+.]*:(//((%[0-9a-f][0-9a-f]|[0-9a-zA-Z-._~!$&'()*+,;=:])*@)?(\\[(::(ffff:([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])(\\.([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])){3}|(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,5})?)|([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,4})?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,3})?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){0,2})?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::(([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3}))?)?|:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})(::([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})?|(:([0-9a-fA-F]|[1-9a-fA-F][0-9a-fA-F]{1,3})){3})))))|v[0-9a-fA-F]\\.([0-9a-zA-Z-._~!$&'()*+,;=:])+)\\]|(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=])*)(:[1-9][0-9]*)?)?(/(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=:@])*)*(\\?(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=:@/?])*)?(#(%[0-9a-fA-F][0-9a-fA-F]|[0-9a-zA-Z-._~!$&'()*+,;=:@/?])*)?",
                    after: "",
                    isUseRegularExpression: true
                )
                speechModSettingList.append(modSetting)
            }
            if isOverrideRubyEnabled {
                let rubySettingArray = GenerateRubyModString(text: story.content, notRubyString: notRubyCharactorStringArray, isDisableNarouRuby: isDisableNarouRuby)
                speechModSettingList.append(contentsOf: rubySettingArray)
            }
            
            return CategorizeStoryText(content: story.content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: SpeakerSetting(from: defaultSpeaker), sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, speechModArray: speechModSettingList)
        }
    }
    
    // speechModArray の正規表現周りを計算して単なる読み替え設定にして、
    // 読み替え前の文字列長でソートされた状態にする部分だけを別関数としておきます
    static func CategorizeStoryText(content:String, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int, defaultSpeaker:SpeakerSetting, sectionConfigList:[SpeechSectionConfig], waitConfigList:[SpeechWaitConfig], speechModArray:[SpeechModSetting]) -> [CombinedSpeechBlock] {
        
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
                        let setting = SpeechModSetting(before: before, after: after, isUseRegularExpression: false)
                        speechModSettingList.append(setting)
                        beforeHit[before] = true
                    }
                }
            }else{
                speechModSettingList.append(modSetting)
            }
        }
        let sortedSpeechModArray = UniqSpeechModArray(speechModArray: SpeechModArraySort(speechModArray: speechModSettingList))

        return CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, sortedSpeechModArray: sortedSpeechModArray)
    }
}
