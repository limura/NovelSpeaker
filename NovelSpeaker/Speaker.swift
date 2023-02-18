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

class Speaker {
    var speaker_Original:Speaker_Original? = nil
    var speaker_WithoutWillSpeakRange:Speaker_WithoutWillSpeakRange? = nil
    
    init() {
        AssignSpeaker()
    }
    
    func AssignSpeaker() {
        if NovelSpeakerUtility.GetIsDisableWillSpeakRange() {
            if speaker_Original == nil && speaker_WithoutWillSpeakRange != nil {
                return
            }
            speaker_Original = nil
            speaker_WithoutWillSpeakRange = Speaker_WithoutWillSpeakRange()
        }else{
            if speaker_Original != nil && speaker_WithoutWillSpeakRange == nil {
                return
            }
            speaker_Original = Speaker_Original()
            speaker_WithoutWillSpeakRange = nil
        }
    }
    
    func Speech(text:String) {
        speaker_Original?.Speech(text: text)
        speaker_WithoutWillSpeakRange?.Speech(text: text)
    }
    
    func Stop() {
        speaker_Original?.Stop()
        speaker_WithoutWillSpeakRange?.Stop()
    }
    
    func Pause() {
        speaker_Original?.Pause()
        speaker_WithoutWillSpeakRange?.Pause()
    }
    
    func Resume() {
        speaker_Original?.Resume()
        speaker_WithoutWillSpeakRange?.Resume()
    }
    
    var voice:AVSpeechSynthesisVoice {
        get {
            if let speaker = speaker_Original {
                return speaker.voice
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.voice
            }
            return AVSpeechSynthesisVoice()
        }
        set(value) {
            speaker_Original?.voice = value
            speaker_WithoutWillSpeakRange?.voice = value
        }
    }
    func SetVoiceWith(identifier:String, language:String) {
        speaker_Original?.SetVoiceWith(identifier: identifier, language: language)
        speaker_WithoutWillSpeakRange?.SetVoiceWith(identifier: identifier, language: language)
    }
    func SetVoiceWith(language:String) {
        speaker_Original?.SetVoiceWith(language: language)
        speaker_WithoutWillSpeakRange?.SetVoiceWith(language: language)
    }
    var pitch:Float {
        get {
            if let speaker = speaker_Original {
                return speaker.pitch
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.pitch
            }
            return 1.0
        }
        set(value) {
            speaker_Original?.pitch = value
            speaker_WithoutWillSpeakRange?.pitch = value
        }
    }
    var rate:Float {
        get {
            if let speaker = speaker_Original {
                return speaker.rate
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.rate
            }
            return 1.0
        }
        set(value) {
            speaker_Original?.rate = value
            speaker_WithoutWillSpeakRange?.rate = value
        }
    }
    var volume:Float {
        get {
            if let speaker = speaker_Original {
                return speaker.volume
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.volume
            }
            return 1.0
        }
        set(value) {
            speaker_Original?.volume = value
            speaker_WithoutWillSpeakRange?.volume = value
        }
    }
    var delay:TimeInterval {
        get {
            if let speaker = speaker_Original {
                return speaker.delay
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.delay
            }
            return 1.0
        }
        set(value) {
            speaker_Original?.delay = value
            speaker_WithoutWillSpeakRange?.delay = value
        }
    }
    var delegate:SpeakRangeDelegate? {
        get {
            if let speaker = speaker_Original {
                return speaker.delegate
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.delegate
            }
            return nil
        }
        set(value) {
            speaker_Original?.delegate = value
            speaker_WithoutWillSpeakRange?.delegate = value
        }
    }

    func isSpeaking() -> Bool {
        if let speaker = speaker_Original {
            return speaker.isSpeaking()
        }
        if let speaker = speaker_WithoutWillSpeakRange {
            return speaker.isSpeaking()
        }
        return false
    }
    
    func reloadSynthesizer() {
        speaker_Original?.reloadSynthesizer()
        speaker_WithoutWillSpeakRange?.reloadSynthesizer()
    }
    
    func ChangeSpeakerWillSpeakRangeType() {
        let prevSpeakerOriginal = speaker_Original
        let prevSpeakerWithoutWillSpeakRange = speaker_WithoutWillSpeakRange
        AssignSpeaker()
        if let speaker = speaker_Original, let prev = prevSpeakerWithoutWillSpeakRange {
            speaker.delegate = prev.delegate
            speaker.voice = prev.voice
            speaker.delay = prev.delay
            speaker.volume = prev.volume
            speaker.rate = prev.rate
            speaker.pitch = prev.pitch
        }
        if let speaker = speaker_WithoutWillSpeakRange, let prev = prevSpeakerOriginal {
            speaker.delegate = prev.delegate
            speaker.voice = prev.voice
            speaker.delay = prev.delay
            speaker.volume = prev.volume
            speaker.rate = prev.rate
            speaker.pitch = prev.pitch
        }
    }
    
    func isPaused() -> Bool {
        if let speaker = speaker_Original {
            return speaker.isPaused()
        }
        if let speaker = speaker_WithoutWillSpeakRange {
            return speaker.isPaused()
        }
        return false
    }

    var isSpeechKicked:Bool {
        get {
            if let speaker = speaker_Original {
                return speaker.isSpeechKicked
            }
            if let speaker = speaker_WithoutWillSpeakRange {
                return speaker.isSpeechKicked
            }
            return false
        }
    }
}

class Speaker_Original: NSObject, AVSpeechSynthesizerDelegate {
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
        if NiftyUtility.isTesting() {
            return
        }
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
class Speaker_WithoutWillSpeakRange: NSObject, AVSpeechSynthesizerDelegate {
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
        if NiftyUtility.isTesting() {
            return
        }
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

    /*
    #if !os(watchOS)
    @objc func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        if let delegate = self.m_Delegate {
            delegate.willSpeakRange(range: characterRange)
        }
    }
    #endif
     */
    
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
