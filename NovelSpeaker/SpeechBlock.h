//
//  SpeechBlock.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/10.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeechConfig.h"


/// 読み上げ用の文字列ブロック。
/// このブロックは一回の読み上げで読み上げられる文字列を保存します。
/// つまりは読み上げのピッチやスピードが一定で読み上げられる事を期待しています。
/// 読み上げ用の文字列と、表示用の文字列を別々に管理します。
@interface SpeechBlock : NSObject
{
    /// FakeSpeechText の配列
    NSMutableArray* m_FakeSpeechTextArray;
    /// 読み上げ中に表示位置がずれる問題への対策に使う正規表現へのキャッシュ
    NSRegularExpression* regexpForSpeechRecognizerBug;
}

/// 読み上げ時に使用するピッチやスピード
@property (nonatomic) SpeechConfig* speechConfig;

/// 表示用の文字列と読み上げ用の文字列を両方指定して追加します。
- (BOOL) AddDisplayText:(NSString*) displayText speechText:(NSString*)speechText;

/// 読み上げに使用する文字列を取得します。
- (NSString*)GetSpeechText;

/// 表示に使用する文字列を取得します。
- (NSString*)GetDisplayText;

/// 読み上げに使用する文字列を取得します。(DisplayText での位置指定を入れた版)
- (NSString*)GetSpeechTextWithStartPointAboutDisplayText:(NSRange)startPoint;

/// 読み上げ用の文字列の NSRange から表示用の文字列の NSRange に変換します
- (NSRange) ConvertSpeakRangeToDisplayRange:(NSRange)range;

/// 表示用の文字列の NSRange から読み上げ用の文字列の NSRange に変換します
- (NSRange) ConvertDisplayRangeToSpeakRange:(NSRange)range;

@end
