//
//  NiftySpeaker.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/10.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NiftySpeaker.h"
#import "GlobalDataSingleton.h"
#import "SpeechBlock.h"
#import "SpeechConfig.h"

@interface BlockSeparator : NSObject
@property (nonatomic, retain) NSString* startString;
@property (nonatomic, retain) NSString* endString;
@property (nonatomic, retain) SpeechConfig* speechConfig;
@end
@implementation BlockSeparator
@end

@interface DelaySetting : NSObject
@property (nonatomic, retain) NSString* separator;
@property (nonatomic) NSTimeInterval beforeDelay;
@end
@implementation DelaySetting
@end

typedef enum {
    SPEECH_SETTING_TYPE_DELAY = 1,
    SPEECH_SETTING_TYPE_TONE_CHANGE_IN = 2,
    SPEECH_SETTING_TYPE_TONE_CHANGE_OUT = 4,
} SpeechSettingType;

@interface SpeechSetting : NSObject
@property (nonatomic) SpeechSettingType type;
@property (nonatomic, retain) SpeechConfig* config;
@end
@implementation SpeechSetting
@end

@implementation NiftySpeaker

- (id)init
{
    self = [super init];
    if (self == nil) {
        return self;
    }

    m_Speaker = [Speaker new];
    m_Speaker.speakRangeChangeDelegate = self;
    
    m_SpeechBlockArray = nil;
    m_BlockSeparatorArray = [NSMutableArray new];
    m_DelaySettingArray = [NSMutableArray new];
    m_SpeechModDictionary = [NSMutableDictionary new];

    m_DefaultSpeechConfig = [SpeechConfig new];
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    m_DefaultSpeechConfig.pitch = [globalState.defaultPitch floatValue];
    m_DefaultSpeechConfig.rate = [globalState.defaultRate floatValue];
    m_DefaultSpeechConfig.beforeDelay = 0.0f;
    
    m_bIsSpeaking = false;
    m_NowSpeechBlockIndex = 0;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    
    m_SpeakRangeDelegateArray = [NSMutableArray new];
    
    return self;
}

- (id)initWithSpeechConfig:(SpeechConfig*)speechConfig
{
    self = [super init];
    if (self == nil) {
        return self;
    }
    
    m_Speaker = [Speaker new];
    m_Speaker.speakRangeChangeDelegate = self;
    
    m_SpeechBlockArray = nil;
    m_BlockSeparatorArray = [NSMutableArray new];
    m_DelaySettingArray = [NSMutableArray new];
    m_SpeechModDictionary = [NSMutableDictionary new];
    
    m_DefaultSpeechConfig = [SpeechConfig new];
    m_DefaultSpeechConfig.pitch = speechConfig.pitch;
    m_DefaultSpeechConfig.rate = speechConfig.rate;
    m_DefaultSpeechConfig.beforeDelay = speechConfig.beforeDelay;
    
    m_bIsSpeaking = false;
    m_NowSpeechBlockIndex = 0;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    
    m_SpeakRangeDelegateArray = [NSMutableArray new];
    
    return self;
}

/// 表示用の文字列を受け取って、SpeechBlock を生成します。
- (SpeechBlock*)CreateSpeechBlockFromDisplayText:(NSString*)displayText speechModDictionary:(NSDictionary*)speechModDictionary config:(SpeechConfig*)config
{
    SpeechBlock* result = [SpeechBlock new];
    result.speechConfig = [SpeechConfig new];
    result.speechConfig.beforeDelay = config.beforeDelay;
    result.speechConfig.pitch = config.pitch;
    result.speechConfig.rate = config.rate;
    unsigned long p = 0;
    unsigned long displayTextLength = [displayText length];
    while (p < displayTextLength) {
        NSRange targetRange = NSMakeRange(p, displayTextLength - p);
        unsigned long min_p = displayTextLength;
        NSString* hitFrom = nil;
        for (NSString* from in speechModDictionary) {
            NSRange searchResult = [displayText rangeOfString:from options:0 range:targetRange];
            if (searchResult.location == NSNotFound) {
                continue;
            }
            if (min_p > searchResult.location) {
                min_p = searchResult.location;
                hitFrom  = from;
            }
        }
        if (hitFrom == nil) {
            break;
        }
        if (p < min_p) {
            NSRange beforeRange = NSMakeRange(p, min_p - p);
            NSString* beforeString = [displayText substringWithRange:beforeRange];
            [result AddDisplayText:beforeString speechText:beforeString];
        }
        NSString* toString = [speechModDictionary objectForKey:hitFrom];
        [result AddDisplayText:hitFrom speechText:toString];
        p = min_p + [hitFrom length];
    }
    if (p < displayTextLength) {
        NSRange endRange = NSMakeRange(p, displayTextLength - p);
        NSString* endString = [displayText substringWithRange:endRange];
        [result AddDisplayText:endString speechText:endString];
    }
    
    return result;
}

/// 読み上げ用の文字列からSpeechBlockの配列への変換を行います。
- (NSArray*)ConvertTextToSpeechBlockArray:(NSString*)text
{
    //NSArray* BlockSeparatedTextArray = [self SplitDelayedText:m_BlockSeparatorArray text:text];
    //NSArray* DelaySeparateTextArray = [self SplitTextByDelaySettingArray:m_DelaySettingArray text:text];
    
    NSMutableDictionary* speechSettingMap = [NSMutableDictionary new];

    unsigned long textLength = [text length];
    for (DelaySetting* delaySetting in m_DelaySettingArray) {
        unsigned long p = 0;
        while (p < textLength) {
            NSRange targetRange = NSMakeRange(p, textLength - p);
            NSRange searchResult = [text rangeOfString:delaySetting.separator options:0 range:targetRange];
            if (searchResult.location == NSNotFound) {
                break;
            }
            NSNumber* targetKey = [[NSNumber alloc] initWithUnsignedLong:searchResult.location];
            SpeechSetting* currentSetting = [speechSettingMap objectForKey:targetKey];
            if (currentSetting == nil) {
                currentSetting = [SpeechSetting new];
                currentSetting.config = [SpeechConfig new];
                currentSetting.config.pitch = m_DefaultSpeechConfig.pitch;
                currentSetting.config.rate = m_DefaultSpeechConfig.pitch;
                currentSetting.config.beforeDelay = m_DefaultSpeechConfig.beforeDelay;
                currentSetting.type = 0;
            }
            currentSetting.type |= SPEECH_SETTING_TYPE_DELAY;
            currentSetting.config.beforeDelay = delaySetting.beforeDelay;
            [speechSettingMap setObject:currentSetting forKey:targetKey];
            p = searchResult.location + searchResult.length;
        }
    }

    for (BlockSeparator* blockSeparator in m_BlockSeparatorArray)
    {
        unsigned long p = 0;
        while (p < textLength) {
            NSRange targetRange = NSMakeRange(p, textLength - p);
            NSRange startSearchResult = [text rangeOfString:blockSeparator.startString options:0 range:targetRange];
            if (startSearchResult.location == NSNotFound || (startSearchResult.location + 1) >= textLength) {
                break;
            }
            NSRange endTargetRange = NSMakeRange(startSearchResult.location + 1, textLength - (startSearchResult.location+1));
            NSRange endSearchResult = [text rangeOfString:blockSeparator.endString options:0 range:endTargetRange];
            if (endSearchResult.location == NSNotFound) {
                break;
            }
            
            NSNumber* startKey = [[NSNumber alloc] initWithUnsignedLong:startSearchResult.location];
            SpeechSetting* startSetting = [speechSettingMap objectForKey:startKey];
            if (startSetting == nil) {
                startSetting = [SpeechSetting new];
                startSetting.config = [SpeechConfig new];
                startSetting.config.beforeDelay = 0.0f;
                startSetting.type = 0;
            }
            startSetting.type |= SPEECH_SETTING_TYPE_TONE_CHANGE_IN;
            startSetting.type &= ~SPEECH_SETTING_TYPE_TONE_CHANGE_OUT;
            startSetting.config.pitch = blockSeparator.speechConfig.pitch;
            startSetting.config.rate = blockSeparator.speechConfig.rate;
            [speechSettingMap setObject:startSetting forKey:startKey];
            //NSLog(@"set start: %lu -> delay: %.2f, pitch: %.2f, rate: %.2f", [startKey unsignedLongValue], startSetting.config.beforeDelay, startSetting.config.pitch, startSetting.config.rate);
            
            NSNumber* endKey = [[NSNumber alloc] initWithUnsignedLong:endSearchResult.location];
            SpeechSetting* endSetting = [speechSettingMap objectForKey:endKey];
            if (endSetting == nil) {
                endSetting = [SpeechSetting new];
                endSetting.config = [SpeechConfig new];
                endSetting.config.beforeDelay = 0.0f;
                endSetting.type = 0;
            }
            endSetting.type |= SPEECH_SETTING_TYPE_TONE_CHANGE_OUT;
            endSetting.type &= ~SPEECH_SETTING_TYPE_TONE_CHANGE_IN;
            endSetting.config.pitch = blockSeparator.speechConfig.pitch;
            endSetting.config.rate = blockSeparator.speechConfig.rate;
            [speechSettingMap setObject:endSetting forKey:endKey];
            //NSLog(@"set end: %lu -> delay: %.2f, pitch: %.2f, rate: %.2f", [endKey unsignedLongValue], endSetting.config.beforeDelay, endSetting.config.pitch, endSetting.config.rate);
            
            p = endSearchResult.location + endSearchResult.length;
        }
    }
    
    NSMutableArray* configStack = [NSMutableArray new];
    [configStack addObject:m_DefaultSpeechConfig];
    NSArray* locationArray = [speechSettingMap allKeys];
    locationArray = [locationArray sortedArrayUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b){
        return [a compare:b];
    }];

    /*
    for (NSNumber* key in locationArray) {
        unsigned long location = [key unsignedLongValue];
        SpeechSetting* setting = [speechSettingMap objectForKey:key];
        NSString* str = [text substringWithRange:NSMakeRange(location, [text length] - location)];
        NSLog(@"target: %lu, %@%@%@, pitch: %f, rate: %f, delay: %f, %@"
              , location
              , setting.type & SPEECH_SETTING_TYPE_DELAY ? @"DELAY|" : @""
              , setting.type & SPEECH_SETTING_TYPE_TONE_CHANGE_IN ? @"IN|" : @""
              , setting.type & SPEECH_SETTING_TYPE_TONE_CHANGE_OUT ? @"OUT|" : @""
              , setting.config.pitch
              , setting.config.rate
              , setting.config.beforeDelay
              , str);
    }
     */
    
    unsigned long p = 0;
    NSMutableArray* speechBlockArray = [NSMutableArray new];
    for (NSNumber* key in locationArray) {
        SpeechSetting* setting = [speechSettingMap objectForKey:key];
        if (setting == nil) {
            continue;
        }
        if (p >= [key unsignedLongValue]) {
            continue;
        }
        //NSLog(@"setting[%lu]: delay: %.2f, pitch: %.2f, rate: %.2f", [key unsignedLongValue], setting.config.beforeDelay, setting.config.pitch, setting.config.rate);
        
        SpeechConfig* currentConfig = [configStack lastObject];
        SpeechConfig* nextConfig = [SpeechConfig new];
        nextConfig.beforeDelay = 0.0f;
        nextConfig.pitch = m_DefaultSpeechConfig.pitch;
        nextConfig.rate = m_DefaultSpeechConfig.rate;
        BOOL bNeedPushNextConfig = false;
        if (setting.type & SPEECH_SETTING_TYPE_DELAY) {
            nextConfig.beforeDelay = setting.config.beforeDelay;
            bNeedPushNextConfig = true;
        }
        if (setting.type & SPEECH_SETTING_TYPE_TONE_CHANGE_IN) {
            nextConfig.pitch = setting.config.pitch;
            nextConfig.rate = setting.config.rate;
            bNeedPushNextConfig = true;
        }else if(setting.type & SPEECH_SETTING_TYPE_TONE_CHANGE_OUT){
            if ([configStack count] > 1) {
                [configStack removeLastObject];
            }
            SpeechConfig* popConfig = [configStack lastObject];
            // TONE_CHANGE_OUT の時は delay の設定は消します。
            // TODO: だいたいはこれでOKだと思いますが、多分これよくないパターンがあるはず……
            popConfig.beforeDelay = 0.0f;
        }
        if (bNeedPushNextConfig) {
            [configStack addObject:nextConfig];
        }
        NSRange textRange = NSMakeRange(p, [key unsignedLongValue] - p);
        NSString* targetString = [text substringWithRange:textRange];
        SpeechBlock* block = [self CreateSpeechBlockFromDisplayText:targetString speechModDictionary:m_SpeechModDictionary config:currentConfig];
        //NSLog(@"block(%p): delay: %.2f, pitch: %.2f, rate: %.2f %@ → %@", block, block.speechConfig.beforeDelay, block.speechConfig.pitch, block.speechConfig.rate, targetString, [block GetSpeechText]);
        [speechBlockArray addObject:block];
        p = [key unsignedIntegerValue];
    }
    if (p < [text length]) {
        SpeechConfig* config = [configStack lastObject];
        NSRange textRange = NSMakeRange(p, [text length] - p);
        NSString* targetString = [text substringWithRange:textRange];
        SpeechBlock* block = [self CreateSpeechBlockFromDisplayText:targetString speechModDictionary:m_SpeechModDictionary config:config];
        //NSLog(@"block(%p): delay: %.2f, pitch: %.2f, rate: %.2f %@ → %@", block, block.speechConfig.beforeDelay, block.speechConfig.pitch, block.speechConfig.rate, targetString, [block GetSpeechText]);
        [speechBlockArray addObject:block];
    }
    
    return speechBlockArray;
}

/// 読み上げ用の文字列を設定します。同時に SpeechBlock への変換が走ります。
- (BOOL)SetText:(NSString*)text
{
    m_SpeechBlockArray = [self ConvertTextToSpeechBlockArray:text];
    return true;
}

/// 無指定の時の声色を指定します。
- (BOOL)SetDefaultSpeechConfig:(SpeechConfig*)speechConfig
{
    if (speechConfig == nil) {
        GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
        m_DefaultSpeechConfig = [SpeechConfig new];
        m_DefaultSpeechConfig.pitch = [globalState.defaultPitch floatValue];
        m_DefaultSpeechConfig.rate = [globalState.defaultRate floatValue];
        m_DefaultSpeechConfig.beforeDelay = 0.0f;
        return true;
    }
    m_DefaultSpeechConfig = speechConfig;
    return true;
}

/// SpeechBlock で声色を変えるための範囲を判定するための文字列設定を追加します。
- (BOOL)AddBlockStartSeparator:(NSString*)startString endString:(NSString*)endString speechConfig:(SpeechConfig*)speechConfig
{
    BlockSeparator* separator = [BlockSeparator new];
    separator.startString = startString;
    separator.endString = endString;
    separator.speechConfig = speechConfig;
    
    [m_BlockSeparatorArray addObject:separator];
    
    return true;
}

/// SpeechBlock で deleay を追加するための分割ルールを設定します。
/// この設定では声色を変更することはできません。
- (BOOL)AddDelayBlockSeparator:(NSString*)string delay:(NSTimeInterval)delay
{
    DelaySetting* setting = [DelaySetting new];
    setting.separator = string;
    setting.beforeDelay = delay;
    [m_DelaySettingArray addObject:setting];
    
    return true;
}


/// 読み上げ時に、Siriさんが読み間違えてしまう文字列を読み間違えないように別の文字列で置き換えるテーブルを追加します。
- (BOOL)AddSpeechModText:(NSString*)from to:(NSString*)to
{
    [m_SpeechModDictionary setObject:to forKey:from];
    return true;
}

/// 読み上げを開始します。
- (BOOL)StartSpeech
{
    if (m_SpeechBlockArray == nil || [m_SpeechBlockArray count] <= 0 || m_NowSpeechBlockIndex >= [m_SpeechBlockArray count]) {
        return false;
    }
    SpeechBlock* currentBlock = [m_SpeechBlockArray objectAtIndex:m_NowSpeechBlockIndex];
    NSString* speakText = [currentBlock GetSpeechText];
    NSRange targetRange = NSMakeRange(m_NowSpeechBlockSpeachRange.location, [speakText length] - m_NowSpeechBlockSpeachRange.location);
    speakText = [speakText substringWithRange:targetRange];
    [m_Speaker SetRate:currentBlock.speechConfig.rate];
    [m_Speaker SetPitch:currentBlock.speechConfig.pitch];
    [m_Speaker SetDelay:currentBlock.speechConfig.beforeDelay];
    NSLog(@"speech: delay: %.2f, pitch: %.2f, rate: %.2f, %@"
          , currentBlock.speechConfig.beforeDelay
          , currentBlock.speechConfig.pitch
          , currentBlock.speechConfig.rate
          , speakText);
    [m_Speaker Speech:speakText];
    
    m_bIsSpeaking = true;
    return false;
}

/// 読み上げを停止します。
- (BOOL)StopSpeech
{
    m_bIsSpeaking = false;
    [m_Speaker StopSpeech];
    return true;
}

/// 現在の読み上げ位置を取得します
- (NSRange)GetCurrentReadingPoint
{
    if (m_NowSpeechBlockIndex >= [m_SpeechBlockArray count]) {
        return NSMakeRange(0, 0);
    }
    
    unsigned long p = 0;
    for (int i = 0; i < [m_SpeechBlockArray count] && i < m_NowSpeechBlockIndex; i++) {
        SpeechBlock* block = [m_SpeechBlockArray objectAtIndex:i];
        NSString* displayString = [block GetDisplayText];
        p += [displayString length];
    }
    SpeechBlock* currentBlock = [m_SpeechBlockArray objectAtIndex:m_NowSpeechBlockIndex];
    NSRange currentRange = [currentBlock ConvertSpeakRangeToDisplayRange:m_NowSpeechBlockSpeachRange];
    currentRange.location += p;
    
    return currentRange;
}

/// 読み上げ位置を指定した座標に更新します。
- (BOOL)UpdateCurrentReadingPoint:(NSRange)point
{
    if (m_bIsSpeaking) {
        return false;
    }
    
    unsigned long p = 0;
    unsigned int blockIndex = 0;
    SpeechBlock* foundBlock = nil;
    for (SpeechBlock* block in m_SpeechBlockArray) {
        NSString* displayText = [block GetDisplayText];
        unsigned long displayTextLength = [displayText length];
        if (p + displayTextLength > point.location) {
            foundBlock = block;
            break;
        }
        p += displayTextLength;
        blockIndex++;
    }
    if (foundBlock == nil) {
        return false;
    }
    
    NSRange currentRange = NSMakeRange(point.location - p, 0);
    NSRange speakRange = [foundBlock ConvertDisplayRangeToSpeakRange:currentRange];
    m_NowSpeechBlockSpeachRange = speakRange;
    m_NowSpeechBlockIndex = blockIndex;
    
    return true;
}

/// 読み上げ時のイベントハンドラを追加します。
- (BOOL)AddSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate
{
    if (delegate == nil) {
        return false;
    }
    if ([m_SpeakRangeDelegateArray containsObject:delegate]) {
        return true;
    }
    [m_SpeakRangeDelegateArray addObject:delegate];
    return true;
}

/// 読み上げ時のイベントハンドラを削除します。
- (void)DeleteSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate
{
    [m_SpeakRangeDelegateArray removeObject:delegate];
}

/// 読み上げ中か否かを取得します
- (BOOL)isSpeaking
{
    return m_bIsSpeaking;
}


/// 読み上げの位置が変わりますよのイベントハンドラ
/// 自分の delegate に向けて投げなおす。
- (void) willSpeakRange:(NSRange)range speakText:(NSString*)text
{
    if (m_NowSpeechBlockIndex >= [m_SpeechBlockArray count]) {
        return;
    }
    SpeechBlock* currentBlock = [m_SpeechBlockArray objectAtIndex:m_NowSpeechBlockIndex];
    
    NSRange adjustedRange = range;
    adjustedRange.location += m_NowSpeechBlockSpeachRange.location;
    NSRange displayRange = [currentBlock ConvertSpeakRangeToDisplayRange:adjustedRange];
    // ここまでで、displayRange に現在読み上げているブロックの location が入っているはず。
    // ということで、これより前のブロックの長さを加える。
    for (int i = 0; i < m_NowSpeechBlockIndex; i++) {
        SpeechBlock* block = [m_SpeechBlockArray objectAtIndex:i];
        NSString* text = [block GetDisplayText];
        displayRange.location += [text length];
    }
    NSString* displayText = [currentBlock GetDisplayText];
    for (id<SpeakRangeDelegate> delegate in m_SpeakRangeDelegateArray) {
        [delegate willSpeakRange:displayRange speakText:displayText];
    }
}

/// 次の SpeechBlock を読み上げ用に設定します。
- (BOOL) SetNextSpeechBlock
{
    if((m_NowSpeechBlockIndex + 1) >= [m_SpeechBlockArray count])
    {
        return false;
    }
    
    m_NowSpeechBlockIndex++;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    return true;
}

/// 読み上げが停止したよのイベントハンドラ
- (void) finishSpeak
{
    //TODO: まだ書いてない
    if (!m_bIsSpeaking) {
        // 読み上げが停止なら続けません。
        return;
    }
    if (![self SetNextSpeechBlock]) {
        // 与えられた分の読み上げが終了したので終了イベントを投げます。
        for (id<SpeakRangeDelegate> delegate in m_SpeakRangeDelegateArray) {
            [delegate finishSpeak];
        }
        return;
    }
    // 次のblockの読み上げを開始します。
    [self StartSpeech];
}

#pragma mark -
#pragma mark Interruption event handling
// 電話がかかってきたなどで再生中止したときの処理(再生は既に中止されている)
- (void)beginInterruption
{
    // 一応止める。(m_bIsSpeaking はいじらない)
    //[m_Speaker StopSpeech];
}

// 電話がかかってきたなどでの再生再開時の処理
- (void)endInterruptionWithFlags:(NSUInteger)flags
{
    if (!m_bIsSpeaking) {
        return;
    }
    [self StartSpeech];
}

/// 読み上げ用に確保されたSpeechBlockの配列を取得します(テスト用)
- (NSArray*)GetGeneratedSpeechBlockArray_ForTest
{
    return m_SpeechBlockArray;
}

@end
