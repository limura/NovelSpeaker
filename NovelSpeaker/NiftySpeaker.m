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
#import "NovelSpeaker-Swift.h"

#define iOS12WillSpeakRangeBugTargetRegexp @"[\\s•・*]"
#define iOS12WillSpeakRangeBugConvertToString @"α"

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
    m_StringSubstituter = [StringSubstituter new];

    m_DefaultSpeechConfig = [SpeechConfig new];
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    m_DefaultSpeechConfig.pitch = [globalState.defaultPitch floatValue];
    m_DefaultSpeechConfig.rate = [globalState.defaultRate floatValue];
    m_DefaultSpeechConfig.voiceIdentifier = [globalData GetVoiceIdentifier];
    m_DefaultSpeechConfig.beforeDelay = 0.0f;
    
    m_bIsSpeaking = false;
    m_NowSpeechBlockIndex = 0;
    m_NowQueuedBlockIndex = 0;
    m_MaxQueueBlockLength = 1;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    
    m_SpeakRangeDelegateArray = [NSMutableArray new];
    
    m_RegexpForSpeechRecognizerBug = [NSRegularExpression regularExpressionWithPattern:iOS12WillSpeakRangeBugTargetRegexp options:0 error:nil];

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
    m_StringSubstituter = [StringSubstituter new];
    
    m_DefaultSpeechConfig = [SpeechConfig new];
    m_DefaultSpeechConfig.pitch = speechConfig.pitch;
    m_DefaultSpeechConfig.rate = speechConfig.rate;
    m_DefaultSpeechConfig.beforeDelay = speechConfig.beforeDelay;
    m_DefaultSpeechConfig.voiceIdentifier = speechConfig.voiceIdentifier;
    
    m_bIsSpeaking = false;
    m_NowSpeechBlockIndex = 0;
    m_NowQueuedBlockIndex = 0;
    m_MaxQueueBlockLength = 1;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    
    m_SpeakRangeDelegateArray = [NSMutableArray new];

    m_RegexpForSpeechRecognizerBug = [NSRegularExpression regularExpressionWithPattern:iOS12WillSpeakRangeBugTargetRegexp options:0 error:nil];

    return self;
}

/// NSString* の入っている NSArray について、
/// 文字列長の長いもの ＞ 文字sort の順で sort して返す
- (NSArray*)SortSpeechModKey:(NSArray*)keys
{
    return [keys sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSString* a = obj1;
        NSString* b = obj2;
        if ([a length] > [b length]) {
            return NSOrderedAscending;
        }
        if ([a length] < [b length]) {
            return NSOrderedDescending;
        }
        return [a compare:b];
    }];
}

/// 表示用の文字列を受け取って、SpeechBlock を生成します。
- (SpeechBlock*)CreateSpeechBlockFromDisplayText:(NSString*)displayText speechModDictionary:(NSDictionary*)speechModDictionary config:(SpeechConfig*)config
{
    SpeechBlock* result = [SpeechBlock new];
    result.speechConfig = [SpeechConfig new];
    result.speechConfig.beforeDelay = config.beforeDelay;
    result.speechConfig.pitch = config.pitch;
    result.speechConfig.rate = config.rate;
    result.speechConfig.voiceIdentifier = config.voiceIdentifier;
    unsigned long p = 0;
    unsigned long displayTextLength = [displayText length];
    while (p < displayTextLength) {
        NSRange targetRange = NSMakeRange(p, displayTextLength - p);
        unsigned long min_p = displayTextLength;
        NSString* hitFrom = nil;
        
        NSArray* speechModDictionaryKeys = [self SortSpeechModKey:[speechModDictionary allKeys]];
        for (NSString* from in speechModDictionaryKeys) {
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

/// 表示用の文字列を受け取って、SpeechBlock を生成します。
- (SpeechBlock*)CreateSpeechBlockFromDisplayText:(NSString*)displayText config:(SpeechConfig*)config
{
    return [m_StringSubstituter Convert:displayText speechConfig:config];
}

/// 読み上げ用の文字列からSpeechBlockの配列への変換を行います。
- (NSArray*)ConvertTextToSpeechBlockArray:(NSString*)text
{
    //NSArray* BlockSeparatedTextArray = [self SplitDelayedText:m_BlockSeparatorArray text:text];
    //NSArray* DelaySeparateTextArray = [self SplitTextByDelaySettingArray:m_DelaySettingArray text:text];

    /// 読み上げ設定の変化する位置ごとに次の変化を記録するための辞書
    NSMutableDictionary* speechSettingMap = [NSMutableDictionary new];

    // m_DelaySettingArray の設定を辞書に登録していきます。
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
                currentSetting.config.voiceIdentifier = m_DefaultSpeechConfig.voiceIdentifier;
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
                startSetting.config.voiceIdentifier = [[GlobalDataSingleton GetInstance] GetVoiceIdentifier];
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
                endSetting.config.voiceIdentifier = [[GlobalDataSingleton GetInstance] GetVoiceIdentifier];
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
    
    NSArray* locationArray = [speechSettingMap allKeys];
    locationArray = [locationArray sortedArrayUsingComparator:^NSComparisonResult(NSNumber* a, NSNumber* b){
        return [a compare:b];
    }];

#if 0
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
#endif

    NSMutableArray* configStack = [NSMutableArray new];
    [configStack addObject:m_DefaultSpeechConfig];

    unsigned long p = 0;
    NSMutableArray* speechBlockArray = [NSMutableArray new];
    NSTimeInterval delayTime = 0.0f;
    for (NSNumber* key in locationArray) {
        SpeechSetting* setting = [speechSettingMap objectForKey:key];
        if (setting == nil) {
            continue;
        }
        //NSLog(@"setting[%lu]: delay: %.2f, pitch: %.2f, rate: %.2f", [key unsignedLongValue], setting.config.beforeDelay, setting.config.pitch, setting.config.rate);
        
        SpeechConfig* currentConfig = [configStack lastObject];
        currentConfig.beforeDelay = delayTime;
        SpeechConfig* nextConfig = [SpeechConfig new];
        nextConfig.beforeDelay = 0.0f;
        nextConfig.pitch = currentConfig.pitch;
        nextConfig.rate = currentConfig.rate;
        nextConfig.voiceIdentifier = currentConfig.voiceIdentifier;
        
        delayTime = 0.0f;
        if (setting.type & SPEECH_SETTING_TYPE_DELAY) {
            delayTime = setting.config.beforeDelay;
        }
        if (setting.type & SPEECH_SETTING_TYPE_TONE_CHANGE_IN) {
            nextConfig.pitch = setting.config.pitch;
            nextConfig.rate = setting.config.rate;
            [configStack addObject:nextConfig];
        }
        if (setting.type & SPEECH_SETTING_TYPE_TONE_CHANGE_OUT) {
            if ([configStack count] > 1) {
                [configStack removeLastObject];
            }
        }
        if (p >= [key unsignedLongValue]) {
            // 同じ場所に指示があった。(いきなり頭に "「" があったとか
            // つまり読み上げるべきものは何も無いので SpeechBlock は作らなくて良い
            continue;
        }
        NSRange textRange = NSMakeRange(p, [key unsignedLongValue] - p);
        NSString* targetString = [text substringWithRange:textRange];
        if (currentConfig.beforeDelay > 0.0f) {
            SpeechConfig* tmpConfig = [SpeechConfig new];
            tmpConfig.rate = currentConfig.rate;
            tmpConfig.pitch = currentConfig.pitch;
            tmpConfig.beforeDelay = currentConfig.beforeDelay;
            tmpConfig.voiceIdentifier = currentConfig.voiceIdentifier;
            currentConfig = tmpConfig;
        }
        SpeechBlock* block = [self CreateSpeechBlockFromDisplayText:targetString config:currentConfig];
        //NSLog(@"block(%p): delay: %.2f, pitch: %.2f, rate: %.2f %@ → %@", block, block.speechConfig.beforeDelay, block.speechConfig.pitch, block.speechConfig.rate, targetString, [block GetSpeechText]);
        [speechBlockArray addObject:block];
        p = [key unsignedIntegerValue];
    }
    if (p < [text length]) {
        SpeechConfig* config = [configStack lastObject];
        if (delayTime > 0.0f) {
            SpeechConfig* tmpConfig = [SpeechConfig new];
            tmpConfig.rate = config.rate;
            tmpConfig.pitch = config.pitch;
            tmpConfig.beforeDelay = delayTime;
            tmpConfig.voiceIdentifier = config.voiceIdentifier;
            config = tmpConfig;
        }
        NSRange textRange = NSMakeRange(p, [text length] - p);
        NSString* targetString = [text substringWithRange:textRange];
        SpeechBlock* block = [self CreateSpeechBlockFromDisplayText:targetString config:config];
        //NSLog(@"block(%p): delay: %.2f, pitch: %.2f, rate: %.2f %@ → %@", block, block.speechConfig.beforeDelay, block.speechConfig.pitch, block.speechConfig.rate, targetString, [block GetSpeechText]);
        [speechBlockArray addObject:block];
    }
#if 0
    {
        NSMutableString* logText = [NSMutableString new];
        for (SpeechBlock* block in speechBlockArray) {
            [logText appendFormat:@"pitch: %f, rate: %f, delay: %f: %@\n",
             block.speechConfig.pitch,
             block.speechConfig.rate,
             block.speechConfig.beforeDelay,
             [block GetDisplayText]];
        }
        NSLog(@"%@", logText);
    }
#endif
    
    return speechBlockArray;
}

/// 読み上げ用の文字列を設定します。同時に SpeechBlock への変換が走ります。
- (BOOL)SetText:(NSString*)text
{
    [self StopSpeech];
    m_NowQueuedBlockIndex = 0;
    m_SpeechBlockArray = [self ConvertTextToSpeechBlockArray:text];
    return true;
}

/// 読み上げ用に設定されている文字列を取得します。SpeechBlockからの変換になるのでちょっと非効率的です
- (NSString*)GetText
{
    NSMutableString* result = [NSMutableString new];
    for (SpeechBlock* block in m_SpeechBlockArray) {
        [result appendString:[block GetDisplayText]];
    }
    return result;
}

/// 実際に読み上げられる文字列を取得します。SpeechBlockからの変換になるのでちょっと非効率的です
- (NSString*)GetSpeechText
{
    NSMutableString* result = [NSMutableString new];
    for (SpeechBlock* block in m_SpeechBlockArray) {
        [result appendString:[block GetSpeechText]];
    }
    return result;
}

/// 無指定の時の声色を指定します。
- (BOOL)SetDefaultSpeechConfig:(SpeechConfig*)speechConfig
{
    if (speechConfig == nil) {
        GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
        GlobalStateCacheData* globalState = [globalData GetGlobalState];
        m_DefaultSpeechConfig = [SpeechConfig new];
        m_DefaultSpeechConfig.pitch = [globalState.defaultPitch floatValue];
        m_DefaultSpeechConfig.rate = [globalState.defaultRate floatValue];
        m_DefaultSpeechConfig.beforeDelay = 0.0f;
        m_DefaultSpeechConfig.voiceIdentifier = [globalData GetVoiceIdentifier];
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

/// SpeechBlock の delay設定を削除します
- (void)DeleteDelayBlockSeparator:(NSString*)string
{
    NSMutableArray* deleteTargetList = [NSMutableArray new];
    for (DelaySetting* delaySetting in m_DelaySettingArray) {
        if ([delaySetting.separator compare:string] == NSOrderedSame) {
            [deleteTargetList addObject:delaySetting];
        }
    }
    for (DelaySetting* delaySetting in deleteTargetList) {
        [m_DelaySettingArray removeObject:delaySetting];
    }
}

/// 読み上げ時にSiriさんが読み間違えてしまう文字列の読み替え辞書を一つ消します
- (void)DeleteSpeechModString:(NSString*)string
{
    [m_SpeechModDictionary removeObjectForKey:string];
    [m_StringSubstituter DelSetting:string];
}

/// 読み上げ時に、Siriさんが読み間違えてしまう文字列を読み間違えないように別の文字列で置き換えるテーブルを追加します。
- (BOOL)AddSpeechModText:(NSString*)from to:(NSString*)to
{
    [m_SpeechModDictionary setObject:to forKey:from];
    [m_StringSubstituter AddSetting_From:from to:to];
    return true;
}

/// 読み上げを開始します。
- (BOOL)StartSpeech
{
    [BehaviorLogger AddLogWithDescription:@"NiftySpeaker StartSpeech" data:@{}];
    return [self EnqueueSpeechTextBlock];
}

/// 読み上げ文の複数ブロックを m_MaxQueueBlockLength があふれるまで 読み上げqueue に突っ込みます。
- (BOOL)EnqueueSpeechTextBlock
{
    NSUInteger maxBlockCount = [m_SpeechBlockArray count];
    while (m_NowQueuedBlockIndex - m_NowSpeechBlockIndex < m_MaxQueueBlockLength &&
           m_NowQueuedBlockIndex < maxBlockCount) {
        if([self EnqueueOneSpeechTextBlock] == false)
        {
            break;
        }
        m_NowQueuedBlockIndex++;
    }
    return true;
}

/// 読み上げ文の 1ブロック を再生queueに突っ込みます。
- (BOOL)EnqueueOneSpeechTextBlock
{
    if (m_SpeechBlockArray == nil || [m_SpeechBlockArray count] <= 0 || m_NowQueuedBlockIndex >= [m_SpeechBlockArray count]) {
        return false;
    }
    SpeechBlock* currentBlock = [m_SpeechBlockArray objectAtIndex:m_NowQueuedBlockIndex];
    NSString* speakText = [currentBlock GetSpeechText];
    NSUInteger location = m_NowSpeechBlockSpeachRange.location;
    if (m_NowQueuedBlockIndex != m_NowSpeechBlockIndex) {
        // 読み上げ中の位置ならば location は使いますが、先行入力の場合は location は 0 に固定になります。
        location = 0;
    }
    NSRange targetRange = NSMakeRange(location, [speakText length] - location);
    speakText = [speakText substringWithRange:targetRange];
    if (currentBlock.speechConfig.voiceIdentifier != nil) {
        [m_Speaker SetVoiceWithIdentifier:currentBlock.speechConfig.voiceIdentifier];
    }
    [m_Speaker SetRate:currentBlock.speechConfig.rate];
    [m_Speaker SetPitch:currentBlock.speechConfig.pitch];
    [m_Speaker SetDelay:currentBlock.speechConfig.beforeDelay];
    //[m_Speaker Speech:speakText];
    NSString* dummySpeakText = speakText;
    if ([[GlobalDataSingleton GetInstance] IsEscapeAboutSpeechPositionDisplayBugOniOS12Enabled]) {
        dummySpeakText = [m_RegexpForSpeechRecognizerBug stringByReplacingMatchesInString:speakText options:0 range:NSMakeRange(0, [speakText length]) withTemplate:iOS12WillSpeakRangeBugConvertToString];
        if (dummySpeakText == nil) {
            dummySpeakText = speakText;
        }
    }
    [m_Speaker Speech:dummySpeakText];
    
    m_bIsSpeaking = true;
    return true;
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
    //NSLog(@"range.length: %lu -> %lu", (unsigned long)m_NowSpeechBlockSpeachRange.length, (unsigned long)currentRange.length);
    currentRange.location += p + currentRange.length; // m_NowSpeechBlockSpeachRange.length には現在読み上げ中の Block の location が入っている(はず)のでその分が currentRange.length に反映されているのでその分を増やしてやる
    
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
    m_NowSpeechBlockSpeachRange.length = 0;
    m_NowSpeechBlockIndex = blockIndex;
    m_NowQueuedBlockIndex = blockIndex;
    
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
    //NSLog(@"willSpeakRange: %ld/%ld", (unsigned long)range.location, (unsigned long)range.length);
    m_NowSpeechBlockSpeachRange.length = range.location; // m_NowSpeechBlockSpeachRange.length には現在読み上げ中の Block の location を入れる
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
    if((m_NowQueuedBlockIndex + 1) >= [m_SpeechBlockArray count])
    {
        return false;
    }
    
    m_NowQueuedBlockIndex++;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    return true;
}

/// 読み上げが停止したよのイベントハンドラ
- (void) finishSpeak
{
    if (!m_bIsSpeaking) {
        // 読み上げが停止なら続けません。
        return;
    }
    m_NowSpeechBlockIndex++;
    m_NowSpeechBlockSpeachRange.location = 0;
    m_NowSpeechBlockSpeachRange.length = 0;
    if (m_NowSpeechBlockIndex >= [m_SpeechBlockArray count]) {
        // 与えられた分の読み上げが終了したので終了イベントを投げます。
        for (id<SpeakRangeDelegate> delegate in m_SpeakRangeDelegateArray) {
            [delegate finishSpeak];
        }
        return;
    }
    // queueに余裕がありそうなら読み上げqueueに突っ込みます。
    [self EnqueueSpeechTextBlock];
}

#pragma mark -
#pragma mark Interruption event handling
/*
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
 */

/// 読み上げ設定を初期化します
- (void)ClearSpeakSettings
{
    [m_BlockSeparatorArray removeAllObjects];
    [m_DelaySettingArray removeAllObjects];
    [m_SpeechModDictionary removeAllObjects];
    [m_StringSubstituter ClearSetting];
}


/// 読み上げ用に確保されたSpeechBlockの配列を取得します(テスト用)
- (NSArray*)GetGeneratedSpeechBlockArray_ForTest
{
    return m_SpeechBlockArray;
}

/// 指定された文字列を読み上げでアナウンスします。
/// ただし、読み上げを行っていない場合に限ります。
/// 読み上げを行った場合には true を返します。
- (BOOL)AnnounceBySpeech:(NSString*)speechString
{
    if (m_bIsSpeaking) {
        return false;
    }
    return [m_Speaker Speech:speechString];
}


/// countryCode の発音をサポートしている音声の AVSpeechSynthesisVoice のリストを取得します。
+ (NSArray*)getSupportedSpeaker:(NSString*)countryCode{
    NSArray* voiceList = [AVSpeechSynthesisVoice speechVoices];
    NSMutableArray* countryVoiceList = [NSMutableArray new];
    for (AVSpeechSynthesisVoice* voice in voiceList) {
        if ([voice.language compare:countryCode] == NSOrderedSame) {
            [countryVoiceList addObject:voice];
        }
    }
    return countryVoiceList;
}

/// 指定された voice identifier が利用可能なものかどうかを判定する
+ (BOOL)isValidVoiceIdentifier:(NSString*)targetIdentifier{
    AVSpeechSynthesisVoice* voice = [AVSpeechSynthesisVoice voiceWithIdentifier:targetIdentifier];
    if(voice){
        return YES;
    }
    return NO;
}

/// AVSpeechSynthesisVoice.identifier から .name を取得します。該当がなければ nil を返します。
+ (NSString*)getDisplayStringForVoiceIdentifier:(NSString*)identifier {
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_9_0) {
        return nil;
    }
    AVSpeechSynthesisVoice* voice = [AVSpeechSynthesisVoice voiceWithIdentifier:identifier];
    if (voice != nil) {
        return voice.name;
    }
    return nil;
}

/// 現在の標準のSpeechConfigを取得します
- (SpeechConfig*)GetDefaultSpeechConfig {
    return m_DefaultSpeechConfig;
}


#if 0
// AVAudioSessionDelegate で受け取れる音声停止のイベント？
- (void)inputIsAvailableChanged:(BOOL)isInputAvailable
{
    if (isInputAvailable == YES && m_bIsSpeaking) {
        [self StartSpeech];
    }
    if (isInputAvailable == NO && m_bIsSpeaking) {
        [self StopSpeech];
    }
}
#endif
@end
