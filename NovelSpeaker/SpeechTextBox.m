//
//  SpeechTextBox.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/26.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeechTextBox.h"
#import "SpeechRegexPitchSetting.h"

@implementation SpeechTextBox

NSString* const SPEECH_TEXT_SEPARATOR = @"\r\n";

- (id) init {
    self = [super init];
    
    m_Speaker = [[Speaker alloc] init];
    m_Speaker.delegate = self;
    
    m_SpeechPosition.length = 0;
    m_SpeechPosition.location = 0;
    m_SpeechTextList = NULL;
    self.textView = NULL;
    m_SpeechTextLocationCache = 0;
    m_SpeechTextBlockStartLocation = 0;
    m_isSpeaking = false;
    m_PitchSettingList = [[NSArray alloc] init];
    
    return self;
}

/// 読み上げる文字列を初期化します
- (BOOL) SetText: (NSString*) text
{
    m_SpeechTextList = [text componentsSeparatedByString:SPEECH_TEXT_SEPARATOR];
    m_SpeechTextListIndex = 0;
    m_SpeechTextLocationCache = 0;
    m_SpeechPosition.length = 0;
    m_SpeechPosition.location = 0;
    m_SpeechTextBlockStartLocation = 0;
    return true;
}

/// 読み上げる文字列の開始位置を指定します
- (BOOL) SetSpeechStartPoint: (NSRange)range
{
    if(range.location == NSNotFound)
    {
        // 範囲指定がおかしいので初期位置とします。
        m_SpeechTextListIndex = 0;
        m_SpeechTextLocationCache = 0;
        m_SpeechTextBlockStartLocation = 0;
        m_SpeechPosition.length = 0;
        m_SpeechPosition.location = 0;
        return false;
    }
    
    m_SpeechPosition = range;
    
    // 指定されたRangeを元に、内部状態を更新しておきます
    m_SpeechTextLocationCache = 0;
    m_SpeechTextListIndex = 0;
    int index = 0;
    
    // 読み上げの開始位置まで index を進めます
    for(NSString* text in m_SpeechTextList)
    {
        if(m_SpeechTextLocationCache + [text length] > m_SpeechPosition.location)
        {
            //NSLog(@"break: %lu + %lu (%lu) > %lu", m_SpeechTextLocationCache, (unsigned long)[text length], m_SpeechTextLocationCache + [text length], m_SpeechTextLocationCache);
            break;
        }
        m_SpeechTextLocationCache += [text length];
        m_SpeechTextLocationCache += [SPEECH_TEXT_SEPARATOR length];
        index++;
    }
    if(index >= [m_SpeechTextList count])
    {
        // 範囲指定がおかしいので初期位置とします。
        m_SpeechTextListIndex = 0;
        m_SpeechTextLocationCache = 0;
        m_SpeechTextBlockStartLocation = 0;
        m_SpeechPosition.length = 0;
        m_SpeechPosition.location = 0;
        return false;
    }
    m_SpeechTextListIndex = index;
    m_SpeechTextBlockStartLocation = 0;
    
    //NSLog(@"position update: %lu, index: %d, cache: %lu", (unsigned long)m_SpeechPosition.location, m_SpeechTextListIndex, (unsigned long)m_SpeechTextLocationCache);
    
    return true;
}

/// 読み上げの停止位置(又は現在読み上げ中の位置)を取得します。
- (NSRange) GetSpeechPoint
{
    return m_SpeechPosition;
}

/// 現在の読み上げtextを m_SpeechTextList のindex個目のものにします。
- (BOOL) SetSpeechTextIndex: (int)index
{
    m_SpeechTextListIndex = index;
    
    // 読み上げの終わった分の文字列の長さを m_SpeechTextLocationCache に入れます
    m_SpeechTextLocationCache = 0;
    // index に指定されているところから読み上げを開始するので、
    // index に指定されている文字列の長さを加えては駄目です。
    for(int i = 0; i < (index-1) && i < [m_SpeechTextList count]; i++)
    {
        m_SpeechTextLocationCache += [m_SpeechTextList[i] length];
        // 多分セパレータ分をズラしておかないと駄目です。
        m_SpeechTextLocationCache += [SPEECH_TEXT_SEPARATOR length];
    }
    m_SpeechPosition.length = 0;
    m_SpeechPosition.location = m_SpeechTextLocationCache;
    m_SpeechTextBlockStartLocation = 0;
    return true;
}

/// 読み上げindexを更新します。
/// これ以上読み上げできない場合は false を返します
- (BOOL) UpdateSpeechTextIndex
{
    if(m_SpeechTextList == NULL || [m_SpeechTextList count] < m_SpeechTextListIndex)
    {
        return false;
    }
    // 読み上げ位置を更新します。
    m_SpeechTextBlockStartLocation = 0;
    do {
        NSUInteger current_text_length = [m_SpeechTextList[m_SpeechTextListIndex] length];
        current_text_length += [SPEECH_TEXT_SEPARATOR length];
        m_SpeechTextListIndex++;
        if([m_SpeechTextList count] < m_SpeechTextListIndex)
        {
            return false;
        }
        m_SpeechTextLocationCache += current_text_length;
        m_SpeechPosition.location += current_text_length;
        // 長さが0の文字列の場合は更新させます。
    }while([m_SpeechTextList[m_SpeechTextListIndex] length] <= 0);

    m_SpeechPosition.length = 0;
    m_SpeechPosition.location = m_SpeechTextLocationCache;

    return true;
}

///
- (BOOL) _AssignSpeechSetting: (NSString*)text
{
    for(SpeechRegexPitchSetting* setting in m_PitchSettingList)
    {
        NSTextCheckingResult* result = [setting.regex firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
        if(result.numberOfRanges <= 0)
        {
            continue;
        }
        [m_Speaker SetPitch:setting.pitch];
        //NSLog(@"hit. use pitch: %f in %@", setting.pitch, text);
        return true;
    }
    // どれにもhitしなかったので、default値を設定します。
    //NSLog(@"not hit. use default pitch: %f in %@", m_DefaultPitch, text);
    [m_Speaker SetPitch:m_DefaultPitch];
    return true;
}

/// 現在の読み上げ位置から読み上げを開始します
- (BOOL) _StartSpeech
{
    if([m_SpeechTextList count] < m_SpeechTextListIndex)
    {
        return false;
    }
    if(m_Speaker == NULL)
    {
        return false;
    }
    
    NSString* target_text = m_SpeechTextList[m_SpeechTextListIndex];

    // 文字列のピッチの設定は、読み上げ開始点ではなく細切れにしたテキストに対して適用するので、
    // このタイミングでピッチの設定を行います。
    [self _AssignSpeechSetting:target_text];
    
    m_SpeechTextBlockStartLocation = 0;
    if(m_SpeechPosition.location > m_SpeechTextLocationCache)
    {
        // m_SpeechPosition で指示されている場所が一行の中にあったので、それより前の文字をなかったことにします。
        if([target_text length] <= m_SpeechPosition.location - m_SpeechTextLocationCache)
        {
            // 何故か読み上げ位置が現在指定されている文字の範囲を超えているので再計算させます
            // TODO: ここに陥るということはなにかおかしいです。計算が間違えているか、
            // 読み上げのStopイベントが意図しないタイミングで飛んできているかどちらか？
            // (一つの細切れtextの途中でStopイベントが飛ぶと m_SpeechTextListIndex が +1 されておかしな事になるはず)
            [self SetSpeechStartPoint:m_SpeechPosition];
        }
        m_SpeechTextBlockStartLocation = m_SpeechPosition.location - m_SpeechTextLocationCache;
        //NSLog(@"pos.location: %lu, cache: %lu -> %lu <- TextLength: %lu, text: %@", (unsigned long)m_SpeechPosition.location, (unsigned long)m_SpeechTextLocationCache, (unsigned long)m_SpeechTextBlockStartLocation, (unsigned long)[target_text length], target_text);
        target_text = [target_text substringFromIndex:m_SpeechTextBlockStartLocation];
    }

    m_isSpeaking = true;
    return [m_Speaker Speech:target_text];
}

/// SetSpeechStartPointで設定されている位置から、読み上げを開始します
- (BOOL) StartSpeech
{
    if(m_SpeechTextList == NULL || m_Speaker == NULL)
    {
        return false;
    }
    
    // 現在読み上げを行っているのであれば、停止します。
    [self StopSpeech];
    // 読み上げを開始します。
    return [self _StartSpeech];
}

/// 読み上げを終了します
- (BOOL) StopSpeech
{
    if(m_Speaker == NULL)
    {
        return false;
    }
    m_isSpeaking = false;
    return [m_Speaker StopSpeech];
}

/// 読み上げを一時中断します。
/// 再開する場合は ResumeSpeech を使用します
- (BOOL) PauseSpeech
{
    if(m_Speaker == NULL)
    {
        return false;
    }
    return [m_Speaker PauseSpeech];
}

/// 読み上げを再開します
- (BOOL) ResumeSpeech
{
    if(m_Speaker == NULL)
    {
        return false;
    }
    return [m_Speaker ResumeSpeech];
}

/// Speaker からの読み上げ位置イベントを受け取ります
- (void) willSpeakRange:(NSRange)range speakText:(NSString *)text
{
    NSRange currentRange;
    currentRange.location = m_SpeechTextLocationCache + range.location + m_SpeechTextBlockStartLocation;
    currentRange.length = range.length;
    
    if(self.textView == NULL)
    {
        return;
    }
    self.textView.selectedRange = currentRange;
    [self.textView scrollRangeToVisible:currentRange];
}

/// Speaker からの読み上げ終了イベントを受け取ります
- (void) finishSpeak
{
    if(m_isSpeaking == false)
    {
        // 読み上げを止められている場合は特に何もしません。
        return;
    }
    if([self UpdateSpeechTextIndex] == false)
    {
        return;
    }
    // 次があるなら読み上げを開始します。
    [self _StartSpeech];
}

/// 音声の読み上げ速度を指定します。1.0f が通常の速度で、2.0f だと二倍速、0.5f だと半分の速度です。
/// この設定は次回以降の読み上げから有効になります
/// 最小値は AVSpeechUtteranceMinimumSpeechRate
/// 最大値は AVSpeechUtteranceMaximumSpeechRate
/// 標準値は AVSpeechUtteranceDefaultSpeechRate です。
- (void) SetRate: (float) rate
{
    m_DefaultRate = rate;
    [m_Speaker SetRate:rate];
}

/// 音声のピッチを指定します。小さい値は男性っぽく、大きい値は女性っぽくなります
/// この設定は次回以降の読み上げから有効になります
/// 値は 0.5f から 2.0f までで、標準値は 1.0f です。
- (void) SetPitch: (float) pitch
{
    m_DefaultPitch = pitch;
    [m_Speaker SetPitch:pitch];
}

/// 正規表現マッチでのピッチ指定を追加します。
- (BOOL) AddPitchSetting: (NSString*)regexPattern pitch:(float)pitch
{
    SpeechRegexPitchSetting* setting = [[SpeechRegexPitchSetting alloc] init];
    setting.pitch = pitch;
    NSError* error = nil;
    setting.regex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:NSRegularExpressionDotMatchesLineSeparators error:&error];
    if(error != nil)
    {
        NSLog(@"NSRegularExpression create failed. maybe invalid pattern in string: '%@'", regexPattern);
        return false;
    }
    
    m_PitchSettingList = [m_PitchSettingList arrayByAddingObject:setting];
    return true;
}

/// 音声を読み上げるときの前から開ける時間を指定します
/// この設定は次回以降の読み上げから有効になります
- (void) SetDelay: (NSTimeInterval) interval
{
    [m_Speaker SetDelay:interval];
}
@end
