//
//  SpeechBlockSpeaker.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

class SpeechBlockSpeaker: NSObject, SpeakRangeDelegate {
    let speaker = MultiVoiceSpeaker()
    
    var speechBlockArray:[CombinedSpeechBlock] = []
    var currentSpeechBlockIndex:Int = 0
    var delegate:SpeakRangeDelegate? = nil
    var m_IsSpeaking = false
    // 現在のblockの先頭部分が全体のDisplayStringに対してどれだけのオフセットを持っているかの値
    var currentDisplayStringOffset = 0
    // Blockの先頭からの読み上げ開始位置のズレ(読み上げを開始する時はBlockの途中から始まる可能性があり、そのズレを表す)
    var currentBlockDisplayOffset = 0
    var currentBlockSpeechOffset = 0
    // 現在の先頭からの読み上げ中の位置(willSpeakRange で知らされる location と同じ値)
    var currentSpeakingLocation = 0
    
    // StopSpeech() で実際に読み上げが止まった時のハンドラ
    let stopSpeechHandlerLockObject = NSObject()
    var stopSpeechHandler:(()->Void)? = nil
    
    override init() {
        super.init()
        speaker.delegate = self
    }
    
    var displayText:String {
        get {
            var result:String = ""
            for blockInfo in speechBlockArray {
                result += blockInfo.displayText
            }
            return result
        }
    }
    
    var speechText:String {
        get {
            var result:String = ""
            for blockInfo in speechBlockArray {
                result += blockInfo.speechText
            }
            return result
        }
    }
    var isSpeaking:Bool {
        get { return m_IsSpeaking }
    }
    var isSpeakingBySynthesizerState:Bool {
        get { return speaker.isSpeaking }
    }
    var isPausedBySynthesizerState:Bool {
        get { return speaker.isPaused }
    }

    func GetSpeechTextWith(range:NSRange) -> String {
        let startOffset = DisplayLocationToSpeechLocation(location: range.location)
        let endOffset = DisplayLocationToSpeechLocation(location: range.location + range.length)
        let speechText = self.speechText
        let speechTextCount = speechText.unicodeScalars.count
        if speechTextCount < startOffset || speechTextCount < endOffset { return "" }
        let startIndex = speechText.index(speechText.startIndex, offsetBy: startOffset)
        let endIndex = speechText.index(speechText.startIndex, offsetBy: endOffset)
        return String(speechText[startIndex..<endIndex])
    }
    
    func DisplayLocationToSpeechLocation(location:Int) -> Int {
        var displayLocation = 0
        var speechLocation = 0
        
        for blockInfo in speechBlockArray {
            let displayTextCount = blockInfo.displayText.unicodeScalars.count
            let speechTextCount = blockInfo.speechText.unicodeScalars.count
            if displayLocation + displayTextCount > location {
                let displayOffset = Float(location - displayLocation)
                let speechOffset = displayOffset * Float(speechTextCount) / Float(displayTextCount)
                speechLocation += Int(speechOffset + 0.5)
                break
            }
            displayLocation += displayTextCount
            speechLocation += speechTextCount
        }
        return speechLocation
    }
    func SpeechLocationToDisplayLocation(location:Int) -> Int {
        var displayLocation = 0
        var speechLocation = 0
        
        for blockInfo in speechBlockArray {
            let displayTextCount = blockInfo.displayText.unicodeScalars.count
            let speechTextCount = blockInfo.speechText.unicodeScalars.count
            if speechLocation + speechTextCount > location {
                let speechOffset = Float(location - speechLocation)
                let displayOffset = speechOffset * Float(displayTextCount) / Float(speechTextCount)
                displayLocation += Int(displayOffset + 0.5)
                break
            }
            displayLocation += displayTextCount
            speechLocation += speechTextCount
        }
        return displayLocation
    }
    
    func GenerateSpeechTextFrom(displayTextRange:NSRange) -> String {
        var result = ""
        var location = 0
        for block in speechBlockArray {
            let currentBlockDisplayTextLength = block.displayText.unicodeScalars.count
            if currentBlockDisplayTextLength <= 0 { continue }
            if location + currentBlockDisplayTextLength <= displayTextRange.location
                || location > (displayTextRange.location + displayTextRange.length) {
                location += currentBlockDisplayTextLength
                continue
            }
            var currentBlockStartLocation = displayTextRange.location - location
            var currentBlockEndLocation = displayTextRange.location + displayTextRange.length - location
            if currentBlockStartLocation < 0 {
                currentBlockStartLocation = 0
            }
            if currentBlockEndLocation > currentBlockDisplayTextLength {
                currentBlockEndLocation = currentBlockDisplayTextLength
            }
            result += block.GenerateSpeechTextFrom(range: NSMakeRange(currentBlockStartLocation, currentBlockEndLocation - currentBlockStartLocation))
            location += currentBlockDisplayTextLength
        }
        return result
    }
    
    // 読み上げ中のSpeechBlockを次の物を指すように変化させます。
    // 次の物がなければ false を返します。
    func setNextSpeechBlock() -> Bool {
        // currentBlock が取り出せない場合はエラー
        guard currentSpeechBlockIndex < speechBlockArray.count else { return false }
        let currentBlock = speechBlockArray[currentSpeechBlockIndex]
        currentSpeechBlockIndex += 1
        currentDisplayStringOffset += currentBlock.displayText.unicodeScalars.count
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeakingLocation = currentDisplayStringOffset
        // 次のblock を取り出せないなら終わったという意味で false を返す
        guard currentSpeechBlockIndex < speechBlockArray.count else { return false }
        return true
    }
    
    func enqueueSpeechBlock(){
        guard currentSpeechBlockIndex < speechBlockArray.count else {
            self.finishSpeak(isCancel: true, speechString: "")
            return
        }
        let block = speechBlockArray[currentSpeechBlockIndex]
        let location = block.ComputeDisplayLocationFrom(speechLocation: currentBlockSpeechOffset) + currentDisplayStringOffset
        self.delegate?.willSpeakRange(range: NSMakeRange(location, 1))
        let speechText = block.GenerateSpeechTextFrom(displayLocation: currentBlockDisplayOffset)
        speaker.Speech(text: speechText, voiceIdentifier: block.voiceIdentifier, locale: block.locale, pitch: block.pitch, rate: block.rate, volume: block.volume, delay: block.delay)
        //print("Speech: \(speechText)")
    }
    
    func setSpeechBlockArray(blockArray:[CombinedSpeechBlock]) {
        speechBlockArray = blockArray
        currentDisplayStringOffset = 0
        currentSpeechBlockIndex = 0
        currentSpeakingLocation = 0
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        
        resetRegisterdVoices()
    }
    func resetRegisterdVoices() {
        var voiceIdentifierDictionary:[String?:String?] = [:]
        for block in speechBlockArray {
            voiceIdentifierDictionary[block.voiceIdentifier] = block.locale
        }
        for (voiceIdentifier, locale) in voiceIdentifierDictionary {
            speaker.RegisterVoiceIdentifier(voiceIdentifier: voiceIdentifier, locale: locale)
        }
    }
    
    func SetTextWitoutSettings(content:String) {
        let dummySpeaker = RealmSpeakerSetting()
        let blockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: [], moreSplitMinimumLetterCount: 99999, defaultSpeaker: SpeakerSetting(from: dummySpeaker), sectionConfigList: [], waitConfigList: [], sortedSpeechModArray: [])
        setSpeechBlockArray(blockArray: blockArray)
    }
    
    func SetText(content:String, withMoreSplitTargets: [String], moreSplitMinimumLetterCount: Int, defaultSpeaker: SpeakerSetting, sectionConfigList: [SpeechSectionConfig], waitConfigList: [SpeechWaitConfig], sortedSpeechModArray: [SpeechModSetting]) {
        let blockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, sortedSpeechModArray: sortedSpeechModArray)
        setSpeechBlockArray(blockArray: blockArray)
    }

    func SetText(content:String, withMoreSplitTargets: [String], moreSplitMinimumLetterCount: Int, defaultSpeaker: SpeakerSetting, sectionConfigList: [SpeechSectionConfig], waitConfigList: [SpeechWaitConfig], speechModArray: [SpeechModSetting]) {
        let blockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, speechModArray: speechModArray)
        setSpeechBlockArray(blockArray: blockArray)
    }
    
    func SetStory(story:Story, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int) {
        let blockArray = StoryTextClassifier.CategorizeStoryText(story: story, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount)
        setSpeechBlockArray(blockArray: blockArray)
    }

    func SetStory(story:Story) {
        SetStory(story: story, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max)
    }
    
    func StartSpeech() {
        if m_IsSpeaking == true { return }
        m_IsSpeaking = true
        enqueueSpeechBlock()
    }
    
    func StopSpeech(stopSpeechHandler:(()->Void)? = nil) {
        objc_sync_enter(self.stopSpeechHandlerLockObject)
        defer { objc_sync_exit(self.stopSpeechHandlerLockObject) }
        m_IsSpeaking = false
        self.stopSpeechHandler = stopSpeechHandler
        speaker.Stop()
    }

    /// 読み上げ開始位置を指定します。範囲外を指定された場合は false を返します
    @discardableResult
    func SetSpeechLocation(location:Int) -> Bool {
        var currentLocation = location
        if currentLocation < 0 { return false }
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeechBlockIndex = 0
        currentDisplayStringOffset = 0
        for speechBlock in speechBlockArray {
            let blockDisplayTextLength = speechBlock.displayText.unicodeScalars.count
            if currentLocation >= blockDisplayTextLength {
                currentSpeechBlockIndex += 1
                currentDisplayStringOffset += blockDisplayTextLength
                currentLocation -= blockDisplayTextLength
                continue
            }
            currentBlockDisplayOffset = currentLocation
            currentBlockSpeechOffset = speechBlock.ComputeSpeechLocationFrom(displayLocation: currentLocation)
            currentSpeakingLocation = location
            //print("SetSpeechLocation(\(location)) -> currentSpeechBlockIndex: \(currentSpeechBlockIndex), currentBlockSpeechOffset: \(currentBlockSpeechOffset)")
            return true
        }
        // ここで currentSpeakingLocation を更新しておかないと、読み上げ開始位置が 0 に戻ってしまう。
        currentSpeakingLocation = location
        //print("SetSpeechLocation(\(location)) -> currentSpeechBlockIndex: \(currentSpeechBlockIndex) (return false)")
        return false
    }
    
    /// 読み上げ開始位置を speechBlockArray の index で指示します
    @discardableResult
    func SetSpeechBlockIndex(index:Int) -> Bool {
        if index < 0 || speechBlockArray.count <= index { return false }
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeechBlockIndex = 0
        currentDisplayStringOffset = 0
        var index = index
        for speechBlock in speechBlockArray {
            if index < 0 {
                break
            }
            let blockDisplayTextLength = speechBlock.displayText.unicodeScalars.count
            currentDisplayStringOffset += blockDisplayTextLength
            currentSpeechBlockIndex += 1
            index -= 1
        }
        currentSpeakingLocation = currentDisplayStringOffset
        print("SetSpeechBlockIndex(\(index)) -> currentSpeechBlockIndex: \(currentSpeechBlockIndex)")
        return true
    }
    
    func willSpeakRange(range: NSRange) {
        guard let delegate = delegate, speechBlockArray.count > currentSpeechBlockIndex else { return }
        let block = speechBlockArray[currentSpeechBlockIndex]
        let location = block.ComputeDisplayLocationFrom(speechLocation: range.location + currentBlockSpeechOffset) + currentDisplayStringOffset
        currentSpeakingLocation = location
        delegate.willSpeakRange(range: NSMakeRange(location, range.length))
    }
    
    func finishSpeak(isCancel: Bool, speechString: String) {
        // 読み上げを停止させられている場合は何もしません。
        // これは、Stop() した時でも finishSpeak() が呼び出されるためです。
        if m_IsSpeaking != true {
            objc_sync_enter(self.stopSpeechHandlerLockObject)
            defer { objc_sync_exit(self.stopSpeechHandlerLockObject) }
            self.stopSpeechHandler?()
            self.stopSpeechHandler = nil
            return
        }
        /* // 一応読み上げ途中で Cancel が発生する問題は回避できた(一度にSpeak()にわたす文字列の長さを短くする事で回避できるぽい)
         // ので、この再開するあたりの処理は封印しておきます。
         // 実際、再開させるようにしても、発話が停止してから2,3拍おいた後に少し戻って発話する感じになるのであまりうれしくないです
        if isCancel == true {
            // isCancel で finishSpeak が来た場合で、かつ、読み上げ中の途中でfinishSpeakが発生している場合、
            // 怪しくその時点で発話を再開します。
            print("currentSpeakingLocation: \(currentSpeakingLocation), displayText.count: \(displayText.unicodeScalars.count)")
            if (currentSpeakingLocation + 3) < displayText.unicodeScalars.count {
                SetSpeechLocation(location: currentSpeakingLocation)
                enqueueSpeechBlock()
                return
            }
        }
        */
        if setNextSpeechBlock() != true {
            m_IsSpeaking = false
            self.delegate?.finishSpeak(isCancel: isCancel, speechString: speechString)
            return
        }
        enqueueSpeechBlock()
    }

    var currentLocation:Int {
        get { return currentSpeakingLocation }
    }
    
    var currentBlockIndex:Int {
        get { return currentSpeechBlockIndex }
    }
    
    var currentBlock:CombinedSpeechBlock? {
        get {
            guard speechBlockArray.count > currentSpeechBlockIndex else { return nil }
            return speechBlockArray[currentSpeechBlockIndex]
        }
    }
    
    func isDummySpeechAlive() -> Bool {
        return speaker.isDummySpeechAlive()
    }
    
    func reloadSynthesizer() {
        objc_sync_enter(self.stopSpeechHandlerLockObject)
        defer { objc_sync_exit(self.stopSpeechHandlerLockObject) }
        if let stopHandler = self.stopSpeechHandler {
            stopHandler()
            self.stopSpeechHandler = nil
        }
        speaker.reloadSynthesizer()
    }
    #if false // AVSpeechSynthesizer を開放するとメモリ解放できそうなので必要なくなりました
    func ChangeSpeakerWillSpeakRangeType() {
        self.speaker.ChangeSpeakerWillSpeakRangeType()
    }
    #endif
}
