//
//  Speaker.m
//  NBackSpeaker
//
//  Created by 飯村 卓司 on 2014/02/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "Speaker.h"

@implementation Speaker

@synthesize speakRangeChangeDelegate;

- (id) init {
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    m_Synthesizer = [AVSpeechSynthesizer new];
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    m_Rate = 0.7f;
    m_Pitch = 1.0f;
    m_Interval = 0.0;
    m_CurrentStatus = STSpeakingStatusNone;
    
    m_Synthesizer.delegate = self;

    // AVAudioSessionInterruptionNotification のイベントハンドラを登録します
    [self setAVAudioSessionInterruptionNotificationHandler];
    
    return self;
}
    
- (void)dealloc
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
}

- (BOOL) Speech: (NSString*) text
{
    // memo: AVSpeechSynthesizer:speakUtterance は再生queueに追加される形式のようなので、再生中でも追加してかまわないっぽいです
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    if (m_Voice == nil) {
        m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    }
    utterance.voice = m_Voice;
    utterance.rate = m_Rate;
    utterance.pitchMultiplier = m_Pitch;
    utterance.postUtteranceDelay = m_Interval;
    
    NSLog(@"rate: %f, pitch: %f, post delay: %f text: %@", m_Rate, m_Pitch, m_Interval, text);
    [m_Synthesizer speakUtterance:utterance];
    
    return TRUE;
}

- (void) SetVoice: (NSString*) language
{
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
}

- (BOOL)SetVoiceWithIdentifier: (NSString*) voiceID
{
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_9_0) {
        return false;
    }
    if (voiceID == nil) {
        return false;
    }
    AVSpeechSynthesisVoice* voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voiceID];
    if (voice == nil) {
        NSLog(@"can not set voiceIdentifier: %@", voiceID);
        return false;
    }
    m_Voice = voice;
    return true;
}

- (void) SetRate: (float) rate
{
    if(rate < AVSpeechUtteranceMinimumSpeechRate)
    {
        rate = AVSpeechUtteranceMinimumSpeechRate;
    }else if(rate > AVSpeechUtteranceMaximumSpeechRate)
    {
        rate = AVSpeechUtteranceMaximumSpeechRate;
    }
    m_Rate = rate;
}

- (void) SetPitch: (float) pitch
{
    m_Pitch = pitch;
}

- (void) SetDelay: (NSTimeInterval) interval
{
    m_Interval = interval;
}

- (STSpeakingStatus) GetStatus
{
    return m_CurrentStatus;
}

- (BOOL) StopSpeech
{
    //if ([m_Synthesizer isSpeaking]) {
    NSLog(@"#### AVSpeech Stop Immediate####");
        [m_Synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    //}
    
    // なにやら読み上げが失敗するようになることがあるようなので、Stopのタイミングで AVSpeechSynthesizer object を作り直すようにします
    m_Synthesizer.delegate = nil; // 先に delegate は消しておきます
    m_Synthesizer = nil; // 走れ！走れ！AVSpeechSynthesizerのデストラクタよ走れ！
    m_Synthesizer = [AVSpeechSynthesizer new];
    m_Synthesizer.delegate = self;
    
    return true;
}

- (BOOL) PauseSpeech
{
    return [m_Synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

- (BOOL) ResumeSpeech
{
    return [m_Synthesizer continueSpeaking];
}

- (void)changeStatus:(STSpeakingStatus)status
{
    m_CurrentStatus = status;
    switch(status)
    {
        case STSpeakingStatusNone:
            //NSLog(@"speak status -> None");
            break;
        case STSpeakingStatusPause:
            NSLog(@"speak status -> Pause");
            break;
        case STSpeakingStatusSpeak:
            //NSLog(@"speak status -> Speak");
            break;
        case STSpeakingStatusStop:
            //NSLog(@"speak status -> Stop");
            if (self.speakRangeChangeDelegate != nil) {
                [self.speakRangeChangeDelegate finishSpeak];
            }
            break;
        default:
            NSLog(@"speak status -> Unknown");
            break;
    }
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance
{
	[self changeStatus:STSpeakingStatusSpeak];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance{
	[self changeStatus:STSpeakingStatusStop];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didPauseSpeechUtterance:(AVSpeechUtterance *)utterance{
	[self changeStatus:STSpeakingStatusPause];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didContinueSpeechUtterance:(AVSpeechUtterance *)utterance{
	[self changeStatus:STSpeakingStatusSpeak];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance{
	[self changeStatus:STSpeakingStatusStop];
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance{
    if (self.speakRangeChangeDelegate == nil) {
        return;
    }
    [self.speakRangeChangeDelegate willSpeakRange:characterRange speakText:utterance.speechString];

}

- (void)setAVAudioSessionInterruptionNotificationHandler
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(sessionDidInterrupt:) name:AVAudioSessionInterruptionNotification object:nil];
}

- (void)sessionDidInterrupt:(NSNotification*)notification
{
    if (notification == nil) {
        return;
    }
    
    switch ([notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue]) {
        case AVAudioSessionInterruptionTypeBegan:
            NSLog(@"interruption begin.");
            [self PauseSpeech];
            break;
        case AVAudioSessionInterruptionTypeEnded:
            NSLog(@"interuption end.");
            [self ResumeSpeech];
            break;
        default:
            break;
    }
}

@end
