//
//  SpeechBlock.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/10.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeechBlock.h"

/// 表示用の文字列と、読み上げ用の文字列をそれぞれ保存します。
@interface FakeSpeechText : NSObject
/// 読み上げ用の文字列
@property (nonatomic) NSString* speechText;
/// 表示用の文字列
@property (nonatomic) NSString* displayText;
@end
@implementation FakeSpeechText
@end


@implementation SpeechBlock

- (id)init
{
    self = [super init];
    if (self == nil) {
        return self;
    }
    m_FakeSpeechTextArray = [NSMutableArray new];
    
    return self;
}

/// 表示用の文字列と読み上げ用の文字列を両方指定して追加します。
- (BOOL) AddDisplayText:(NSString*) displayText speechText:(NSString*)speechText
{
    FakeSpeechText* fakeText = [FakeSpeechText new];
    fakeText.displayText = displayText;
    fakeText.speechText = speechText;
    [m_FakeSpeechTextArray addObject:fakeText];
    
    return true;
}

/// 読み上げに使用する文字列を取得します。
- (NSString*)GetSpeechText
{
    NSMutableString* str = [NSMutableString new];
    for (FakeSpeechText* fakeText in m_FakeSpeechTextArray) {
        [str appendString:fakeText.speechText];
    }
    return str;
}

/// 表示に使用する文字列を取得します。
- (NSString*)GetDisplayText
{
    NSMutableString* str = [NSMutableString new];
    for (FakeSpeechText* fakeText in m_FakeSpeechTextArray) {
        [str appendString:fakeText.displayText];
    }
    return str;
}

/// 読み上げに使用する文字列を取得します。(DisplayText での位置指定を入れた版)
- (NSString*)GetSpeechTextWithStartPointAboutDisplayText:(NSRange)startPoint;
{
    NSRange speakRange = [self ConvertDisplayRangeToSpeakRange:startPoint];
    NSString* speakString = [self GetSpeechText];
    speakRange.length = [speakString length] - speakRange.location;
    return [speakString substringWithRange:speakRange];
}


/// 読み上げ用の文字列の NSRange から表示用の文字列の NSRange に変換します
- (NSRange) ConvertSpeakRangeToDisplayRange:(NSRange)range
{
    unsigned long displayP = 0;
    unsigned long speechP = 0;
    NSRange result;
    result.length = 0;
    result.location = NSNotFound;
    for (FakeSpeechText* fakeText in m_FakeSpeechTextArray) {
        unsigned long speechTextLength = [fakeText.speechText length];
        if ((speechP + speechTextLength) > range.location) {
            if ([fakeText.displayText compare:fakeText.speechText] == NSOrderedSame) {
                 // 同じ文字列(同じ長さ)なので、一応その長さまでずらした値を返します。
                unsigned long diffLength = range.location - speechP;
                result.location = displayP + diffLength;
                result.length = speechTextLength - diffLength;
                break;
            }
            result.length = [fakeText.displayText length];
            result.location = displayP;
            break;
        }
        speechP += speechTextLength;
        displayP += [fakeText.displayText length];
    }
    return result;
}

/// 表示用の文字列の NSRange から読み上げ用の文字列の NSRange に変換します
- (NSRange) ConvertDisplayRangeToSpeakRange:(NSRange)range
{
    unsigned long displayP = 0;
    unsigned long speechP = 0;
    NSRange result;
    result.length = 0;
    result.location = NSNotFound;
    for (FakeSpeechText* fakeText in m_FakeSpeechTextArray) {
        unsigned long displayTextLength = [fakeText.displayText length];
        if ((displayP + displayTextLength) > range.location) {
            if ([fakeText.displayText compare:fakeText.speechText] == NSOrderedSame) {
                // 同じ文字列(同じ長さ)なので、一応その長さまでずらした値を返します。
                unsigned long diffLength = range.location - displayP;
                result.location = speechP + diffLength;
                result.length = displayTextLength - diffLength;
                break;
            }
            result.length = [fakeText.speechText length];
            result.location = speechP;
            break;
        }
        displayP += displayTextLength;
        speechP += [fakeText.speechText length];
    }
    return result;
}


@end
