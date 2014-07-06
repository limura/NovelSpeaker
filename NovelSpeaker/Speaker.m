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
    
    m_Synthesizer = [[AVSpeechSynthesizer alloc] init];
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
        // 再生中は失敗にします。
        return FALSE;
    }

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = m_Voice;
    utterance.rate = m_Rate;
    utterance.pitchMultiplier = m_Pitch;
    utterance.postUtteranceDelay = m_Interval;
    
    NSLog(@"rate: %f, pitch: %f, text: %@", m_Rate, m_Pitch, text);
    [m_Synthesizer speakUtterance:utterance];
    
    return TRUE;
}

- (void) SetVoice: (NSString*) language
{
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
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
    return [m_Synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

- (BOOL) PauseSpeech
{
    return [m_Synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

- (BOOL) ResumeSpeech
{
    return [m_Synthesizer 	continueSpeaking];
}

- (void)changeStatus:(STSpeakingStatus)status
{
    m_CurrentStatus = status;
    switch(status)
    {
        case STSpeakingStatusNone:
            NSLog(@"speak status -> None");
            break;
        case STSpeakingStatusPause:
            NSLog(@"speak status -> Pause");
            break;
        case STSpeakingStatusSpeak:
            NSLog(@"speak status -> Speak");
            break;
        case STSpeakingStatusStop:
            NSLog(@"speak status -> Stop");
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
