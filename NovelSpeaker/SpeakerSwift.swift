//
//  SpeakerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

protocol SpeakRangeProtocol {
    func willSpeakRange(range:NSRange)
    func finishSpeak()
}

class SpeakerSwift: NSObject, AVSpeechSynthesizerDelegate {
    let synthesizer:AVSpeechSynthesizer = AVSpeechSynthesizer()
    var m_Voice:AVSpeechSynthesisVoice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice()
    var m_Pitch:Float = 1.0
    var m_Rate:Float = AVSpeechUtteranceDefaultSpeechRate
    var m_Delay:TimeInterval = 0.0
    var m_Delegate:SpeakRangeProtocol? = nil
    
    override init() {
        super.init()
        synthesizer.delegate = self
        SetNotificationHandler()
    }
    
    deinit {
        RemoveNotificationHandler()
        synthesizer.delegate = nil
    }
    
    func Speech(text:String) {
        let utt = AVSpeechUtterance(string: text)
        utt.voice = m_Voice
        utt.pitchMultiplier = m_Pitch
        utt.rate = m_Rate
        utt.postUtteranceDelay = m_Delay
        synthesizer.speak(utt)
    }
    
    func Stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    func Pause() {
        synthesizer.pauseSpeaking(at: .immediate)
    }
    
    func Resume() {
        synthesizer.continueSpeaking()
    }
    
    var voice:AVSpeechSynthesisVoice {
        get { return m_Voice }
        set(value) { m_Voice = value }
    }
    func SetVoiceWith(identifier:String, language:String) {
        if let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            m_Voice = voice
        }
        if let voice = AVSpeechSynthesisVoice(language: language) {
            m_Voice = voice
        }
    }
    func SetVoiceWith(language:String) {
        if let voice = AVSpeechSynthesisVoice(language: language) {
            m_Voice = voice
        }
    }
    var pitch:Float {
        get { return m_Pitch }
        set(value) { m_Pitch = value }
    }
    var rate:Float {
        get { return m_Rate }
        set(value) {
            if value > AVSpeechUtteranceMaximumSpeechRate {
                m_Rate = AVSpeechUtteranceMaximumSpeechRate
                return
            }
            if value < AVSpeechUtteranceMinimumSpeechRate {
                m_Rate = AVSpeechUtteranceMinimumSpeechRate
                return
            }
            m_Rate = value
        }
    }
    var delay:TimeInterval {
        get { return m_Delay }
        set(value) { m_Delay = value }
    }
    var delegate:SpeakRangeProtocol? {
        get { return m_Delegate }
        set(value) { m_Delegate = value }
    }
    
    func SetNotificationHandler() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionDidInterrupt(notification:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    func RemoveNotificationHandler() {
        let center = NotificationCenter.default
        center.removeObserver(self)
    }
    
    @objc func sessionDidInterrupt(notification:Notification) {
        guard let interruptType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber, let type = AVAudioSession.InterruptionType(rawValue: interruptType.uintValue) else { return }
        switch type {
        case AVAudioSession.InterruptionType.began:
            Pause()
        case AVAudioSession.InterruptionType.ended:
            Resume()
        default:
            break
        }
    }
    
    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        delegate?.finishSpeak()
    }
    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        delegate?.finishSpeak()
    }

    #if !os(watchOS)
    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if let delegate = self.m_Delegate {
            delegate.willSpeakRange(range: characterRange)
        }
    }
    #endif
}