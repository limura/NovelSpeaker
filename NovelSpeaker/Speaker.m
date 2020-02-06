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
    m_Volume = 1.0f;
    m_AudioEngine = nil;
    m_AudioPlayerNode = nil;
    m_AudioFormat_After = nil;
    m_AudioFormat_Before = nil;
    m_AudioConverter = nil;
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
    if (m_Synthesizer != nil) {
        m_Synthesizer.delegate = nil;
    }
}

- (AVSpeechUtterance*)CreateUtterance:(NSString*)text {
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:text];
    if (m_Voice == nil) {
        m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    }
    utterance.voice = m_Voice;
    utterance.rate = m_Rate;
    if (m_Volume > 0.0 && m_Volume < 1.0) {
        utterance.volume = m_Volume;
    }
    utterance.pitchMultiplier = m_Pitch;
    utterance.postUtteranceDelay = m_Interval;
    return utterance;
}

- (void)SetupAudioEngine:(AVAudioFormat*)format volume:(float)volume {
    // format を変更するための AVAudioConverter が用意されているならそのまま返します
    if (m_AudioFormat_After != nil
        && m_AudioFormat_Before != nil
        && m_AudioFormat_Before.commonFormat == format.commonFormat
        && m_AudioFormat_After.channelCount == format.channelCount
        && m_AudioFormat_After.interleaved == format.interleaved
        && fabs(m_AudioFormat_After.sampleRate - format.sampleRate) < DBL_EPSILON) {
        return;
    }
    // format を変更する必要がなくて、AudioPlayerNode が用意されているならそのまま返します
    if ((format.commonFormat == AVAudioPCMFormatFloat32
        || format.commonFormat == AVAudioPCMFormatFloat64)
        && m_AudioEngine != nil
        && m_AudioPlayerNode != nil) {
        return;
    }
    NSLog(@"create AudioEngine:\n\tchannelCount: %u -> %u\n\tinterleaved: %@ -> %@\n\tsampleRate: %f -> %f, volume: %f"
          , m_AudioFormat_After.channelCount, format.channelCount
          , m_AudioFormat_After.interleaved ? @"True" : @"False", format.interleaved ? @"True" : @"False"
          , m_AudioFormat_After.sampleRate, format.sampleRate
          , m_Volume);
    if (m_AudioEngine != nil) {
        [m_AudioEngine stop];
    }
    m_AudioEngine = [AVAudioEngine new];
    m_AudioPlayerNode = [AVAudioPlayerNode new];
    [m_AudioEngine attachNode:m_AudioPlayerNode];
    AVAudioMixerNode* mixerNode = [m_AudioEngine mainMixerNode];
    // なんでだかわからないけれど、AVAudioEngine で playerNode と mixerNode を繋ぐ時、
    // format として AVAudioPCMFormatInt16 を指定するとそこで落ちるため
    // それらであれば AVAudioPCMFormatFloat32 に変換するように converter を用意します。
    AVAudioFormat* toFormat = format;
    if (format.commonFormat == AVAudioPCMFormatInt16
        || format.commonFormat == AVAudioPCMFormatInt32) {
        AVAudioFormat* fromFormat = format;
        toFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:fromFormat.sampleRate channels:fromFormat.channelCount interleaved:fromFormat.interleaved];
        AVAudioConverter* converter = [[AVAudioConverter alloc] initFromFormat:fromFormat toFormat:toFormat];
        m_AudioFormat_After = toFormat;
        m_AudioFormat_Before = fromFormat;
        m_AudioConverter = converter;
    }else{
        m_AudioConverter = nil;
    }
    [m_AudioEngine connect:m_AudioPlayerNode to:mixerNode format:toFormat];
    [m_AudioPlayerNode setVolume:volume];
    [m_AudioEngine startAndReturnError:nil];
    [m_AudioPlayerNode play];
}

- (BOOL) SpeechToBuffer:(NSString*)text {
    AVSpeechUtterance* utterance = [self CreateUtterance:text];
    
    if (@available(iOS 13.0, *)) {
        [m_Synthesizer writeUtterance:utterance toBufferCallback:^(AVAudioBuffer * _Nonnull buffer) {
            if (![buffer isKindOfClass:[AVAudioPCMBuffer class]]) {
                return;
            }
            AVAudioPCMBuffer* _Nonnull pcmBuffer = (AVAudioPCMBuffer* _Nonnull)buffer;
            if (pcmBuffer.frameLength <= 0) {
                return;
            }
            AVAudioFormat* format = [pcmBuffer format];
            [self SetupAudioEngine:format volume:m_Volume];
            @autoreleasepool {
                AVAudioPCMBuffer* buffer = pcmBuffer;
                if (m_AudioConverter != nil
                    && format.commonFormat == m_AudioFormat_Before.commonFormat) {
                    AVAudioPCMBuffer* newBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:m_AudioFormat_After frameCapacity:pcmBuffer.frameLength];
                    NSError* err;
                    [m_AudioConverter convertToBuffer:newBuffer fromBuffer:pcmBuffer error:&err];
                    buffer = newBuffer;
                }
                [m_AudioPlayerNode scheduleBuffer:buffer completionHandler:nil];
            }
        }];
    } else {
        return [self Speech:text];
    }
    return TRUE;
}

- (BOOL) Speech: (NSString*) text
{
    if (@available(iOS 13.0, *)) {
        if (m_Volume > 1.0) {
            return [self SpeechToBuffer:text];
        }
    }
    // memo: AVSpeechSynthesizer:speakUtterance は再生queueに追加される形式のようなので、再生中でも追加してかまわないっぽいです
    AVSpeechUtterance* utterance = [self CreateUtterance:text];

    //NSLog(@"rate: %f, pitch: %f, post delay: %f text: %@", m_Rate, m_Pitch, m_Interval, text);
    [m_Synthesizer speakUtterance:utterance];
    
    return TRUE;
}

- (void) SetVoice: (NSString*) language
{
    m_Voice = [AVSpeechSynthesisVoice voiceWithLanguage:language];
}

- (BOOL)SetVoiceWithIdentifier:(NSString*) voiceID voiceLocale:(NSString*)voiceLocale
{
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_9_0) {
        return false;
    }
    if (voiceID == nil) {
        return false;
    }
    AVSpeechSynthesisVoice* voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voiceID];
    if (voice == nil) {
        NSLog(@"can not set voiceIdentifier: %@. try fallback to locale: %@", voiceID, voiceLocale);
        voice = [AVSpeechSynthesisVoice voiceWithLanguage:voiceLocale];
        if (voice == nil) {
            NSLog(@"can not set voiceIdentifier on locale: %@.", voiceLocale);
        }
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

/// 音声を読み上げる時の音量を指定します。
/// 1.0以上の値を指定すると、iOS13以降又はwatchOS 6以降の機能を利用するため、
/// それ以前のOSで1.0以上の値を指定しても無視され、1.0として扱われます。
/// また、負の値を指定すると無視されます。
- (void) SetVolume: (float) volume{
    m_Volume = volume;
}


- (STSpeakingStatus) GetStatus
{
    return m_CurrentStatus;
}

- (BOOL) StopSpeech
{
    //if ([m_Synthesizer isSpeaking]) {
    //NSLog(@"#### AVSpeech Stop Immediate####");
        [m_Synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    //}

    /*
    // なにやら読み上げが失敗するようになることがあるようなので、Stopのタイミングで AVSpeechSynthesizer object を作り直すようにします
    m_Synthesizer.delegate = nil; // 先に delegate は消しておきます
    m_Synthesizer = nil; // 走れ！走れ！AVSpeechSynthesizerのデストラクタよ走れ！
    m_Synthesizer = [AVSpeechSynthesizer new];
    m_Synthesizer.delegate = self;
     */
    
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

// watchOS でこれを見えるようにした状態で AVSpeechSynthesizer に delegate を登録すると、読み上げ時にメモリを 30MBytes から 40MBytes 位持っていかれて、しかも開放してくれなくなるので封印します。(´・ω・`)
#if TARGET_OS_IOS
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance{
    if (self.speakRangeChangeDelegate == nil) {
        return;
    }
    [self.speakRangeChangeDelegate willSpeakRange:characterRange speakText:utterance.speechString];
}
#endif

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
