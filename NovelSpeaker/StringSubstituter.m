//
//  StringSubstituter.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/09/21.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "StringSubstituter.h"

/*
 変換用の設定 (変換元(from)と変換先(to))を、ConvertSeting (このファイル内だけの inetrface) に入れて保存して、
 変換元(from) の 1文字目 が同じものを NSMutableArray に 変換元(from) の文字列長の長いものの順に入れます。
 その NSMutableArray　を
 変換元(from) の 1文字目 を key とした m_1stKeyMap(NSMutableDictionary) に入れて保管します。
 
 文字列の変換時は、文字列を1文字づつ読み込んで、m_1stKeyMap と見比べながら
 変換された文字列を作ります。

 これで、今までのような全ての変換文字列毎に全体を置換した文字列を生成する、
 といったほぼ全ての文字列のメモリコピーが変換対象回だけ発声していたのを
 だいたい1回位で済むようにしようとしてみます。
 ただ、1文字毎にチェックが入るので n の数が少ないと逆に重くなるはずです。
 */

@interface ConvertSetting : NSObject
@property (nonatomic) NSString* from;
@property (nonatomic) NSString* to;
@end
@implementation ConvertSetting
@end

@implementation StringSubstituter

- (id)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    m_1stKeyMap = [NSMutableDictionary new];
    
    return self;
}

/// 変換設定を追加します。
/// from が同じものを登録された場合、設定が上書きされます。
- (BOOL) AddSetting_From:(NSString*)from to:(NSString*)to
{
    if (from == nil || to == nil
        || [from length] <= 0) {
        return false;
    }
    
    // 1文字目で m_1stKeyMap から設定を読み出します。
    unichar c = [from characterAtIndex:0];
    NSString* key = [NSString stringWithFormat:@"%C", c];
    NSMutableArray* convArray = [m_1stKeyMap objectForKey:key];
    if (convArray == nil) {
        convArray = [NSMutableArray new];
    }

    // 同じ from が既にあったのなら、to を書き換えておしまいです。
    for (ConvertSetting* convSettingInArray in convArray) {
        if ([convSettingInArray.from compare:from] == NSOrderedSame) {
            convSettingInArray.to = to;
            return true;
        }
    }

    ConvertSetting* convSetting = [ConvertSetting new];
    convSetting.from = from;
    convSetting.to = to;
    
    // とりあえず追加して from の長さで sort しておきます。
    [convArray addObject:convSetting];
    convArray = [[convArray sortedArrayUsingComparator:^NSComparisonResult(ConvertSetting* a, ConvertSetting* b){
        if (a == nil){
            return NSOrderedAscending;
        }
        if (b == nil){
            return NSOrderedDescending;
        }
        NSUInteger aLength = [a.from length];
        NSUInteger bLength = [b.from length];
        if (aLength == bLength){
            return [a.from compare:NSOrderedSame];
        }
        if (aLength > bLength) {
            return NSOrderedAscending;
        }
        return NSOrderedDescending;
    }] mutableCopy];
    
    // 設定を上書きして終了です
    [m_1stKeyMap setObject:convArray forKey:key];
    
    return true;
}

/// 変換設定を削除します。
- (BOOL) DelSetting:(NSString*)from
{
    if (from == nil || [from length] <= 0) {
        return false;
    }
    
    // 1文字目で m_1stKeyMap から設定を読み出します。
    unichar c = [from characterAtIndex:0];
    NSString* key = [NSString stringWithFormat:@"%C", c];
    NSMutableArray* convArray = [m_1stKeyMap objectForKey:key];
    if (convArray == nil) {
        convArray = [NSMutableArray new];
    }
    
    // 同じ from の設定を検索します。
    NSUInteger length = [convArray count];
    for (NSUInteger i = 0; i < length; i++) {
        ConvertSetting* convSetting = convArray[i];
        if ([convSetting.from compare:from] == NSOrderedSame) {
            // 発見したので削除します
            [convArray removeObject:convSetting];
            break;
        }
    }
    // この1文字目の設定が消えたなら削除はしておきます。
    if ([convArray count] <= 0) {
        [m_1stKeyMap removeObjectForKey:key];
    }
    return true;
}

/// 変換設定を全て削除します。
- (void) ClearSetting
{
    [m_1stKeyMap removeAllObjects];
}

/// 変換を行います。
- (SpeechBlock*) Convert:(NSString*)text speechConfig:(SpeechConfig*)config;
{
    SpeechBlock* result = [SpeechBlock new];
    result.speechConfig = [SpeechConfig new];
    result.speechConfig.beforeDelay = config.beforeDelay;
    result.speechConfig.pitch = config.pitch;
    result.speechConfig.rate = config.rate;
    
    // 今まで読んできた中で書き換えの必要のない部分文字列
    NSMutableString* noConvString = [NSMutableString new];

    NSUInteger textLength = [text length];
    NSUInteger n = 0;
    while (n < textLength) {
        NSString* targetChar = [NSString stringWithFormat:@"%C", [text characterAtIndex:n]];
        NSMutableArray* convArray = [m_1stKeyMap objectForKey:targetChar];
        if (convArray == nil) {
            // 設定に無い文字なのであればそれを追加して次へ
            [noConvString appendString:targetChar];
            n++;
            continue;
        }
        BOOL hit = false;
        for (ConvertSetting* convSetting in convArray) {
            NSUInteger fromLength = [convSetting.from length];
            if (n + fromLength > textLength) {
                // 対象のfrom文字列が長すぎるので次へ
                continue;
            }
            if([text compare:convSetting.from options:NSLiteralSearch range:NSMakeRange(n, fromLength)] == NSOrderedSame)
            {
                // そこから続くのは目的の文字列であった。
                if ([noConvString length] > 0) {
                    [result AddDisplayText:noConvString speechText:noConvString];
                    noConvString = [NSMutableString new];
                }
                [result AddDisplayText:convSetting.from speechText:convSetting.to];
                n += fromLength;
                hit = true;
                break;
            }
        }
        if (hit != true) {
            // 検索したけれどマッチする from はなかった
            [noConvString appendString:targetChar];
            n++;
            continue;
        }
    }
    if ([noConvString length] > 0) {
        [result AddDisplayText:noConvString speechText:noConvString];
        noConvString = [NSMutableString new];
    }
    
    return result;
}


@end
