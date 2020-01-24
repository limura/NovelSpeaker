//
//  SpeechBlockSpeaker.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

class SpeechBlockSpeaker: NSObject, SpeakRangeProtocol {
    let speaker = SpeakerSwift()
    
    var speechBlockArray:[CombinedSpeechBlock] = []
    var currentSpeechBlockIndex:Int = 0
    var delegate:SpeakRangeProtocol? = nil
    var m_IsSpeaking = false
    // 現在のblockの先頭部分が全体のDisplayStringに対してどれだけのオフセットを持っているかの値
    var currentDisplayStringOffset = 0
    // Blockの先頭からの読み上げ開始位置のズレ(読み上げを開始する時はBlockの途中から始まる可能性があり、そのズレを表す)
    var currentBlockDisplayOffset = 0
    var currentBlockSpeechOffset = 0
    // 現在の先頭からの読み上げ中の位置(willSpeakRange で知らされる location と同じ値)
    var currentSpeakingLocation = 0
    
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
    
    func GetSpeechTextWith(range:NSRange) -> String {
        let startOffset = DisplayLocationToSpeechLocation(location: range.location)
        let endOffset = DisplayLocationToSpeechLocation(location: range.location + range.length)
        let speechText = self.speechText
        if speechText.count < startOffset || speechText.count < endOffset { return "" }
        let startIndex = speechText.index(speechText.startIndex, offsetBy: startOffset)
        let endIndex = speechText.index(speechText.startIndex, offsetBy: endOffset)
        return String(speechText[startIndex..<endIndex])
    }
    
    func DisplayLocationToSpeechLocation(location:Int) -> Int {
        var displayLocation = 0
        var speechLocation = 0
        
        for blockInfo in speechBlockArray {
            let displayTextCount = blockInfo.displayText.count
            let speechTextCount = blockInfo.speechText.count
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
            let displayTextCount = blockInfo.displayText.count
            let speechTextCount = blockInfo.speechText.count
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
    
    // 読み上げ中のSpeechBlockを次の物を指すように変化させます。
    // 次の物がなければ false を返します。
    func setNextSpeechBlock() -> Bool {
        // currentBlock が取り出せない場合はエラー
        guard currentSpeechBlockIndex < speechBlockArray.count else { return false }
        let currentBlock = speechBlockArray[currentSpeechBlockIndex]
        currentSpeechBlockIndex += 1
        currentDisplayStringOffset += currentBlock.displayText.count
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeakingLocation = currentDisplayStringOffset
        self.delegate?.willSpeakRange(range: NSMakeRange(currentDisplayStringOffset, 1))
        // 次のblock を取り出せないなら終わったという意味で false を返す
        guard currentSpeechBlockIndex < speechBlockArray.count else { return false }
        return true
    }
    
    func enqueueSpeechBlock(){
        guard currentSpeechBlockIndex < speechBlockArray.count else { return }
        let block = speechBlockArray[currentSpeechBlockIndex]
        if let voice = block.voice {
            speaker.voice = voice
        }
        speaker.pitch = block.pitch
        speaker.rate = block.rate
        speaker.delay = block.delay
        let speechText = block.GenerateSpeechTextFrom(displayLocation: currentBlockDisplayOffset)
        speaker.Speech(text: speechText)
        //print("Speech: \(speechText)")
    }
    
    func SetTextWitoutSettings(content:String) {
        let dummySpeaker = RealmSpeakerSetting()
        speechBlockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: [], moreSplitMinimumLetterCount: 99999, defaultSpeaker: SpeakerSetting(from: dummySpeaker), sectionConfigList: [], waitConfigList: [], sortedSpeechModArray: [])
        currentDisplayStringOffset = 0
        currentSpeechBlockIndex = 0
        currentSpeakingLocation = 0
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
    }
    
    func SetText(content:String, withMoreSplitTargets: [String], moreSplitMinimumLetterCount: Int, defaultSpeaker: SpeakerSetting, sectionConfigList: [SpeechSectionConfig], waitConfigList: [SpeechWaitConfig], sortedSpeechModArray: [SpeechModSetting]) {
        speechBlockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, sortedSpeechModArray: sortedSpeechModArray)
        currentDisplayStringOffset = 0
        currentSpeechBlockIndex = 0
        currentSpeakingLocation = 0
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
    }
    
    func SetStory(story:Story) {
        #if os(watchOS)
        let withMoreSplitTargets:[String] = ["。", "、", ".", ",", ":", "\n\n"]
        let moreSplitMinimumLetterCount:Int = 20
        #else
        // これらは [] で INT_MAX でも良いはずなのだけれど、
        // 。を _。 に変換されたりするような長さが変わる文字がいっぱいあると表示上の位置ズレが大きくなるため、
        // block をある程度分割しておく事にします。
        //let withMoreSplitTargets:[String] = ["。", "、", "\n\n"]
        //let moreSplitMinimumLetterCount:Int = 20
        let withMoreSplitTargets:[String] = []
        let moreSplitMinimumLetterCount:Int = Int(INT_MAX)
        #endif
        speechBlockArray = StoryTextClassifier.CategorizeStoryText(story: story, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount)
        currentDisplayStringOffset = 0
        currentSpeechBlockIndex = 0
        currentSpeakingLocation = 0
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
    }
    
    func StartSpeech() {
        m_IsSpeaking = true
        enqueueSpeechBlock()
    }
    
    func StopSpeech() {
        m_IsSpeaking = false
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
            let blockDisplayTextLength = speechBlock.displayText.count
            if currentLocation >= blockDisplayTextLength {
                currentSpeechBlockIndex += 1
                currentDisplayStringOffset += blockDisplayTextLength
                currentLocation -= blockDisplayTextLength
                continue
            }
            currentBlockDisplayOffset = currentLocation
            currentBlockSpeechOffset = speechBlock.ComputeSpeechLocationFrom(displayLocation: currentLocation)
            currentSpeakingLocation = location
            return true
        }
        return false
    }
    
    func willSpeakRange(range: NSRange) {
        guard let delegate = delegate else { return }
        let block = speechBlockArray[currentSpeechBlockIndex]
        let location = block.ComputeDisplayLocationFrom(speechLocation: range.location + currentBlockSpeechOffset) + currentDisplayStringOffset
        currentSpeakingLocation = location
        delegate.willSpeakRange(range: NSMakeRange(location, range.length))
    }
    
    func finishSpeak() {
        // 読み上げを停止させられている場合は何もしません。
        // これは、Stop() した時でも finishSpeak() が呼び出されるためです。
        if m_IsSpeaking != true {
            return
        }
        if setNextSpeechBlock() != true {
            m_IsSpeaking = false
            self.delegate?.finishSpeak()
            return
        }
        enqueueSpeechBlock()
    }

    func AnnounceText(text:String) {
        if m_IsSpeaking {
            return
        }
        speaker.Speech(text: text)
    }
    
    var currentLocation:Int {
        get { return currentSpeakingLocation }
    }
}
