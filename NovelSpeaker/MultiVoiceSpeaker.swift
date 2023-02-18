//
//  MultiVoiceSpeaker.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/05/24.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//
// AVSpeechSynthesizer で発話する時に、AVSpeechSynthesisVoice が違うobjectを突っ込んで発話させると
// 毎回かなり待たされてから発話が開始するのだけれど、(もしかすると iOS 13から？)
// AVSpeechSynthesizer object を複数作ってそれぞれに対して固有の AVSpeechSynthesisVoice を担当させると
// 初回以外は待たされずに発話できるっぽいみたいなのでそれをするためのclass。
// AVSpeechSynthesizer が複数あると複数が同時に発話することができるみたいなのだけれど、
// 今の所そのような用法は無いはずなので
// このclassでは一度に一個のAVSpeechSynsesizerしか発話しないような動作にする事を目的にします。

import Foundation
import AVFoundation

fileprivate class SpeechQueue {
    let text:String
    let voiceIdentifier:String?
    let locale:String?
    let pitch:Float
    let rate:Float
    let volume:Float
    let delay:TimeInterval
    let isDummy:Bool
    var queuedSpeaker:Speaker?
    init(text:String, voiceIdentifier:String? = nil, locale:String? = nil, pitch:Float = 1, rate:Float = 1, volume:Float = 1, delay:TimeInterval, isDummy:Bool = false) {
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.locale = locale
        self.pitch = pitch
        self.rate = rate
        self.volume = volume
        self.delay = delay
        self.queuedSpeaker = nil
        self.isDummy = isDummy
    }
    
    func enqueue(speaker:Speaker) {
        self.queuedSpeaker = speaker
        speaker.pitch = pitch
        speaker.rate = rate
        speaker.volume = volume
        speaker.delay = delay
        if NovelSpeakerUtility.CheckMemoryUsageIsValid() == false {
            DispatchQueue.main.async {
                StorySpeaker.shared.InterruptByiOS16_3MemoryLeak()
            }
            return
        }
        speaker.Speech(text: text)
    }
    
    func isSpeaking() -> Bool {
        guard let speaker = self.queuedSpeaker else { return false }
        return speaker.isSpeaking()
    }
    
    func isPaused() -> Bool {
        guard let speaker = self.queuedSpeaker else { return false }
        return speaker.isPaused()
    }
    
    func isSpeakEnd() -> Bool {
        guard let speaker = self.queuedSpeaker else { return false }
        if speaker.isSpeaking() { return false }
        return true
    }
    
    func Stop() {
        guard let speaker = self.queuedSpeaker else { return }
        speaker.Stop()
    }
}

class MultiVoiceSpeaker: SpeakRangeDelegate {
    var speakerCache:[String:Speaker] = [:]
    var voiceCache:[String:AVSpeechSynthesisVoice] = [:]
    var defaultVoice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice()
    var currentVoiceIdentifier:String? = nil
    var currentVoiceLocale:String? = nil
    var delegate:SpeakRangeDelegate? = nil

    let speechQueueLock = NSLock()
    fileprivate var speechQueue:[SpeechQueue] = []
    var isStopping = false
    
    // 指定された話者のidentifierに対して「似ていると思われる(要定義)」話者を生成して返します。
    // 失敗する事は有り得ます。
    // 仕組みとしては、identifier がこんな感じなので
    // com.apple.ttsbundle.siri_female_ja-JP_premium
    // これを ["com", "apple", "ttsbundle", "siri", "female", "ja", "JP", "premium"] という形に分割して、
    // 同じ文字列が何個あったか、で個数の多い奴が「近い」と判定します。
    func getNearVoice(voiceIdentifier:String, targetLocale:String?) -> AVSpeechSynthesisVoice? {
        func voiceNameToWordList(identifier:String) -> [String] {
            return identifier.components(separatedBy: CharacterSet(charactersIn: "._-"))
        }
        func calcNearWordList(from:[String], to:[String]) -> Int {
            var hit:Int = 0
            for fromString in from {
                for toString in to {
                    if fromString == toString {
                        hit += 1
                    }
                }
            }
            return hit
        }
        let targetWordList = voiceNameToWordList(identifier: voiceIdentifier)
        var voiceList = AVSpeechSynthesisVoice.speechVoices()
        if let locale = targetLocale, let country = locale.components(separatedBy: "_").first {
            voiceList = voiceList.filter({$0.language.range(of: country)?.lowerBound == $0.language.startIndex})
        }
        var currentNearNum:Int = -1
        var currentVoice:AVSpeechSynthesisVoice? = nil
        for voice in voiceList {
            let currentWordList = voiceNameToWordList(identifier: voice.identifier)
            let nearNum = calcNearWordList(from: targetWordList, to: currentWordList)
            if nearNum > currentNearNum {
                currentVoice = voice
                currentNearNum = nearNum
            }
        }
        return currentVoice
    }
    
    func getVoice(voiceIdentifier:String?, fallbackLocale:String?) -> AVSpeechSynthesisVoice {
        if let voiceIdentifierNotNil = voiceIdentifier, let voice = voiceCache[voiceIdentifierNotNil] { return voice }
        if let voiceIdentifierNotNil = voiceIdentifier ,let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifierNotNil) {
            voiceCache[voiceIdentifierNotNil] = voice
            return voice
        }

        let changeTable = NovelSpeakerUtility.GetVoiceIdentifierChangeTable()
        if let voiceIdentifierNotNil = voiceIdentifier , let changeToArray = changeTable.filter({ $0.contains(voiceIdentifierNotNil) }).first {
            for changeTo in changeToArray {
                if changeTo == voiceIdentifierNotNil { continue }
                if let voice = AVSpeechSynthesisVoice(identifier: changeTo) {
                    for voiceId in changeToArray {
                        self.voiceCache[voiceId] = voice
                    }
                    AppInformationLogger.AddLog(message: NSLocalizedString("MultiVoiceSpeaker_getVoice_useVoiceIdentityChangeTable_Warning", comment: "指定された話者がこの端末では利用できない物であったので、代わりの話者を利用する事にします。(他のOS/OSバージョン向けのIdentity文字列を確認したので近い話者を選択しました)"), appendix: [
                        "from": voiceIdentifierNotNil,
                        "to": voice.identifier
                    ], isForDebug: true)
                    return voice
                }
            }
        }
        if let voiceIdentifierNotNil = voiceIdentifier, let voice = getNearVoice(voiceIdentifier: voiceIdentifierNotNil, targetLocale: fallbackLocale) {
            AppInformationLogger.AddLog(message: NSLocalizedString("MultiVoiceSpeaker_getVoice_useGetNearVoice_Warning", comment: "指定された話者がこの端末では利用できない物であったので、代わりの話者を利用する事にします"), appendix: ["from": voiceIdentifierNotNil, "to": "\(voice.identifier): \(voice.name)"], isForDebug: false)
            voiceCache[voice.identifier] = voice
            voiceCache[voiceIdentifierNotNil] = voice
            return voice
        }
        if let locale = fallbackLocale, let voice = AVSpeechSynthesisVoice(language: locale) {
            voiceCache[voice.identifier] = voice
            if let voiceIdentifierNotNil = voiceIdentifier, voiceIdentifierNotNil.count > 0 {
                voiceCache[voiceIdentifierNotNil] = voice
            }
            return voice
        }
        return defaultVoice
    }
    
    func getSpeaker(voiceIdentifier:String?, locale:String?) -> Speaker {
        if let voiceIdentifierNotNil = voiceIdentifier, let speaker = speakerCache[voiceIdentifierNotNil] { return speaker }
        let speaker = Speaker()
        let voice = getVoice(voiceIdentifier: voiceIdentifier, fallbackLocale: locale)
        speaker.voice = voice
        speaker.delegate = self
        speakerCache[voice.identifier] = speaker
        if let voiceIdentifierNotNil = voiceIdentifier, voiceIdentifierNotNil != voice.identifier {
            speakerCache[voiceIdentifierNotNil] = speaker
        }
        return speaker
    }
    
    fileprivate func startSpeech(queue:SpeechQueue) {
        let speaker = getSpeaker(voiceIdentifier: queue.voiceIdentifier, locale: queue.locale)
        isStopping = false
        queue.enqueue(speaker: speaker)
    }
    
    func enqueue(text:String, voiceIdentifier:String?, locale:String?, pitch:Float = 1, rate:Float = 1, volume:Float = 1, delay:TimeInterval = 0, isDummy:Bool = false) {
        //print("MultiVoiceSpeaker speech request got: \(text)")
        let queue = SpeechQueue(text: text, voiceIdentifier: voiceIdentifier, locale: locale, pitch: pitch, rate: rate, volume: volume, delay: delay, isDummy: isDummy)

        self.speechQueueLock.lock()
        defer { self.speechQueueLock.unlock() }
        let firstQueue = speechQueue.first
        speechQueue.append(queue)
        if firstQueue != nil {
            return
        }
        startSpeech(queue: queue)
    }
    
    func Speech(text:String, voiceIdentifier:String?, locale:String?, pitch:Float = 1, rate:Float = 1, volume:Float = 1, delay:TimeInterval = 0) {
        enqueue(text: text, voiceIdentifier: voiceIdentifier, locale: locale, pitch: pitch, rate: rate, volume: volume, delay: delay)
    }
    
    func Stop() {
        self.speechQueueLock.lock()
        defer { self.speechQueueLock.unlock() }
        isStopping = true
        if let queue = speechQueue.first {
            queue.Stop()
        }
        speechQueue.removeAll()
    }
    
    func willSpeakRange(range:NSRange) {
        var willSpeakDelegate:SpeakRangeDelegate? = nil
        self.speechQueueLock.lock()
        defer {
            self.speechQueueLock.unlock()
            willSpeakDelegate?.willSpeakRange(range: range)
        }
        if let queue = speechQueue.first, queue.isDummy == false {
            willSpeakDelegate = delegate
        }
    }
    func finishSpeak(isCancel: Bool, speechString: String) {
        var finishDelegate:SpeakRangeDelegate? = nil
        self.speechQueueLock.lock()
        defer {
            self.speechQueueLock.unlock()
            finishDelegate?.finishSpeak(isCancel: isCancel, speechString: speechString)
        }
        if speechQueue.count > 0 {
            let queue = speechQueue.removeFirst()
            if queue.isDummy == false {
                finishDelegate = delegate
            }
        }
        if isStopping {
            speechQueue.removeAll()
            finishDelegate = delegate
            return
        }
        if let queue = speechQueue.first {
            startSpeech(queue: queue)
        }
    }

    // 特定の voiceidentifier の speaker について、事前に speech しておく事で初回の speech に時間がかかる問題を回避するためのmethod
    func RegisterVoiceIdentifier(voiceIdentifier:String?, locale:String?) {
        let speaker = getSpeaker(voiceIdentifier: voiceIdentifier, locale: locale)
        if speaker.isSpeechKicked { return }
        print("register: \(voiceIdentifier ?? "nil"), \(locale ?? "nil")")
        enqueue(text: " ", voiceIdentifier: voiceIdentifier, locale: locale, pitch: 1, rate: 1, volume: 0, delay: 0, isDummy: true)
    }
    
    func isDummySpeechAlive() -> Bool {
        self.speechQueueLock.lock()
        defer {
            self.speechQueueLock.unlock()
        }
        for queue in self.speechQueue {
            if queue.isDummy { return true }
        }
        return false
    }
    
    func reloadSynthesizer() {
        for (_, speaker) in self.speakerCache {
            speaker.reloadSynthesizer()
        }
    }
    
    #if false // AVSpeechSynthesizer を開放するとメモリ解放できそうなので必要なくなりました
    func ChangeSpeakerWillSpeakRangeType() {
        for (_, speaker) in self.speakerCache {
            speaker.ChangeSpeakerWillSpeakRangeType()
        }
    }
    #endif // AVSpeechSynthesizer を開放するとメモリ解放できそうなので必要なくなりました

    var isSpeaking:Bool {
        get {
            self.speechQueueLock.lock()
            defer { self.speechQueueLock.unlock() }
            for speaker in speechQueue {
                if speaker.isSpeaking() { return true }
            }
            return false
        }
    }
    
    var isPaused:Bool {
        get {
            self.speechQueueLock.lock()
            defer { self.speechQueueLock.unlock() }
            for speaker in speechQueue {
                if speaker.isPaused() { return true }
            }
            return false
        }
    }
}
