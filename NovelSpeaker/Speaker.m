//
//  Speaker.m
//  NBackSpeaker
//
//  Created by 飯村 卓司 on 2014/02/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "Speaker.h"

@implementation Speaker

- (id) init {
    self = [super init];
    
    m_Synthesizer = [[AVSpeechSynthesizer alloc] init];
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    m_Rate = 0.5f;
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

    AVSpeechUtterance* utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    utterance.voice = m_Voice;
    utterance.rate = m_Rate;
    [m_Synthesizer speakUtterance:utterance];
    return TRUE;
}

- (void) SetVoice: (NSString*) language
{
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
}

- (void) SetRate: (float) rate
{
    m_Rate = rate;
}

- (STSpeakingStatus) GetStatus
{
    return m_CurrentStatus;
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
    
	//NSLog(@"willSpeakRangeOfSpeechString with %lu %lu",(unsigned long)characterRange.location,characterRange.length);
    
	NSString* strTarget = [utterance.speechString substringWithRange:characterRange];
    
	//NSLog(@" target is %@",strTarget);
	//self.readingWord.text = strTarget;
    
}

@end
