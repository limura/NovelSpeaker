//
//  NarouLoader.h
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

/// 小説家になろう の API 個を使って小説情報を読み出すclass。
/// SettingDataModel の NarouContent に追加するなどします。
@interface NarouLoader : NSObject
/// NarouContent のリストを更新します。
/// 怪しく検索条件を内部で勝手に作ります。
- (BOOL)UpdateContentList;

/// 文字列をURIエンコードします
+ (NSString*) URIEncode:(NSString*)str;

/// 小説家になろうで検索を行います。
/// searchString: 検索文字列
/// wname: 作者名を検索対象に含むか否か
/// title: タイトルを検索対象に含むか否か
/// keyword: キーワードを検索対象に含むか否か
/// ex: あらすじを検索対象に含むか否か
+ (NSMutableArray*)Search:(NSString*) searchString wname:(BOOL)wname title:(BOOL)title keyword:(BOOL)keyword ex:(BOOL)ex;

/// HTTP Get Request を投げて、バイナリを返します
+ (NSData*)HttpGetBinary:(NSString*)url;
/// HTTP Get Request を投げて、文字列として返します。
+ (NSString*)HttpGet:(NSString*)url;

@end
