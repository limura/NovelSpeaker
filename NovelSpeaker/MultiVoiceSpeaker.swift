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
    let delay:TimeInterval
    let isDummy:Bool
    var queuedSpeaker:Speaker?
    init(text:String, voiceIdentifier:String? = nil, locale:String? = nil, pitch:Float = 1, rate:Float = 1, delay:TimeInterval, isDummy:Bool = false) {
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.locale = locale
        self.pitch = pitch
        self.rate = rate
        self.delay = delay
        self.queuedSpeaker = nil
        self.isDummy = isDummy
    }
    
    func enqueue(speaker:Speaker) {
        self.queuedSpeaker = speaker
        speaker.pitch = pitch
        speaker.rate = rate
        speaker.delay = delay
        speaker.Speech(text: text)
    }
    
    func isSpeaking() -> Bool {
        guard let speaker = self.queuedSpeaker else { return false }
        return speaker.isSpeaking()
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
    
    func getVoice(voiceIdentifier:String?, fallbackLocale:String?) -> AVSpeechSynthesisVoice {
        if let voiceIdentifierNotNil = voiceIdentifier, let voice = voiceCache[voiceIdentifierNotNil] { return voice }
        if let voiceIdentifierNotNil = voiceIdentifier ,let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifierNotNil) {
            voiceCache[voiceIdentifierNotNil] = voice
            return voice
        }
        if let locale = fallbackLocale, let voice = AVSpeechSynthesisVoice(language: locale) {
            voiceCache[voice.identifier] = voice
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
        return speaker
    }
    
    fileprivate func startSpeech(queue:SpeechQueue) {
        let speaker = getSpeaker(voiceIdentifier: queue.voiceIdentifier, locale: queue.locale)
        isStopping = false
        queue.enqueue(speaker: speaker)
    }
    
    func enqueue(text:String, voiceIdentifier:String?, locale:String?, pitch:Float = 1, rate:Float = 1, delay:TimeInterval = 0, isDummy:Bool = false) {
        //print("MultiVoiceSpeaker speech request got: \(text)")
        let queue = SpeechQueue(text: text, voiceIdentifier: voiceIdentifier, locale: locale, pitch: pitch, rate: rate, delay: delay, isDummy: isDummy)

        self.speechQueueLock.lock()
        defer { self.speechQueueLock.unlock() }
        let firstQueue = speechQueue.first
        speechQueue.append(queue)
        if firstQueue != nil {
            return
        }
        startSpeech(queue: queue)
    }
    
    func Speech(text:String, voiceIdentifier:String?, locale:String?, pitch:Float = 1, rate:Float = 1, delay:TimeInterval = 0) {
        enqueue(text: text, voiceIdentifier: voiceIdentifier, locale: locale, pitch: pitch, rate: rate, delay: delay)
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
    func finishSpeak() {
        var finishDelegate:SpeakRangeDelegate? = nil
        self.speechQueueLock.lock()
        defer {
            self.speechQueueLock.unlock()
            finishDelegate?.finishSpeak()
        }
        if speechQueue.count > 0 {
            let queue = speechQueue.removeFirst()
            if queue.isDummy == false {
                finishDelegate = delegate
            }
        }
        if isStopping {
            speechQueue.removeAll()
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
        enqueue(text: " ", voiceIdentifier: voiceIdentifier, locale: locale, pitch: 1, rate: 1, delay: 0, isDummy: true)
    }
}
