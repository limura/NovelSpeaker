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
    
    m_Synthesizer = [AVSpeechSynthesizer new];
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    m_Rate = 0.7f;
    m_Pitch = 1.0f;
    m_Interval = 0.0;
    m_CurrentStatus = STSpeakingStatusNone;
    
    m_Synthesizer.delegate = self;
    
    return self;
}

- (BOOL) Speech: (NSString*) text
{
    if(m_CurrentStatus == STSpeakingStatusSpeak)
    {
        // 再生中は失敗にしていましたが、再生中に登録できないと
        // 長い文を読ませようとした時に音声を合成するまでの時間が待たされる事があるので
        // 複数登録できるようにエラーはしないようにします。
        //return FALSE;
    }

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = m_Voice;
    utterance.rate = m_Rate;
    utterance.pitchMultiplier = m_Pitch;
    utterance.postUtteranceDelay = m_Interval;
    
    //NSLog(@"rate: %f, pitch: %f, post delay: %f text: %@", m_Rate, m_Pitch, m_Interval, text);
    [m_Synthesizer speakUtterance:utterance];
    
    return TRUE;
}

- (void) SetVoice: (NSString*) language
{
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
}

- (void)SetVoiceWithIdentifier: (NSString*) voideID
{
    m_Voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voideID];
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
    BOOL result = true;
    //if ([m_Synthesizer isSpeaking]) {
        result = [m_Synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    //}
    
    // なにやら読み上げが失敗するようになることがあるようなので、Stopのタイミングで AVSpeechSynthesizer object を作り直すようにします
    m_Synthesizer.delegate = nil; // 先に delegate は消しておきます
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
            //NSLog(@"speak status -> Pause");
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

@end
