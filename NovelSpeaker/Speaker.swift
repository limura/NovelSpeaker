//
//  SpeakerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import AVFoundation

protocol SpeakRangeDelegate {
    func willSpeakRange(range:NSRange)
    func finishSpeak(isCancel:Bool, speechString:String)
}

class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var synthesizer = AVSpeechSynthesizer()
    var m_Voice:AVSpeechSynthesisVoice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice()
    var m_Pitch:Float = 1.0
    var m_Rate:Float = AVSpeechUtteranceDefaultSpeechRate
    var m_Volume:Float = 1.0
    var m_Delay:TimeInterval = 0.0
    var m_Delegate:SpeakRangeDelegate? = nil
    var isSpeechKicked:Bool = false
    
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
        isSpeechKicked = true
        let utt = AVSpeechUtterance(string: text)
        utt.voice = m_Voice
        utt.pitchMultiplier = m_Pitch
        utt.rate = m_Rate
        utt.postUtteranceDelay = m_Delay
        utt.volume = max(0.0, min(1.0, m_Volume))
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
            return
        }
        if let voice = AVSpeechSynthesisVoice(language: language) {
            m_Voice = voice
            return
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
    var volume:Float {
        get { return m_Volume }
        set(value) {
            m_Volume = max(0.0, min(1.0, value))
        }
    }
    var delay:TimeInterval {
        get { return m_Delay }
        set(value) { m_Delay = value }
    }
    var delegate:SpeakRangeDelegate? {
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
        delegate?.finishSpeak(isCancel: false, speechString: utterance.speechString)
    }
    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        delegate?.finishSpeak(isCancel: true, speechString: utterance.speechString)
    }

    #if !os(watchOS)
    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if let delegate = self.m_Delegate {
            delegate.willSpeakRange(range: characterRange)
        }
    }
    #endif
    
    func isSpeaking() -> Bool {
        return self.synthesizer.isSpeaking
    }
    
    func reloadSynthesizer() {
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }
    
    func isPaused() -> Bool {
        return self.synthesizer.isPaused
    }
}
