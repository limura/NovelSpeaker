//
//  StringSubstituter.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/09/21.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeechBlock.h"
#import "SpeechConfig.h"

/// 文字列置換のリストを登録して、一気に変換させるもの
@interface StringSubstituter : NSObject
{
    NSMutableDictionary* m_1stKeyMap;
}

/// 変換設定を追加します。
/// from が同じものを登録された場合、設定が上書きされます。
- (BOOL) AddSetting_From:(NSString*)from to:(NSString*)to;

/// 変換設定を削除します。
- (BOOL) DelSetting:(NSString*)from;

/// 変換設定を全て削除します。
- (void) ClearSetting;

/// 変換を行います。
- (SpeechBlock*) Convert:(NSString*)text speechConfig:(SpeechConfig*)speechConfig;

/// 与えられた文章の文字列から、小説家になろうにおけるルビ表記を発見して、自身の読み替え辞書に登録するための辞書を取り出します
/// 例として、『|北の鬼(ノースオーガ)』という文字列を発見した場合には
/// key → value
/// "|北の鬼(ノースオーガ)" → "ノースオーガ"
/// "北の鬼" → "ノースオーガ"
/// の二種類を出力します。
+ (NSDictionary*)FindNarouRubyNotation:(NSString*)text;

@end

