//
//  NarouLoader.h
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NarouContentCacheData.h"

/// 小説家になろう の API 個を使って小説情報を読み出すclass。
/// SettingDataModel の NarouContent に追加するなどします。
@interface NarouLoader : NSObject

/// 文字列をURIエンコードします
+ (NSString*) URIEncode:(NSString*)str;

/// 小説家になろうで検索を行います。
/// searchString: 検索文字列
/// wname: 作者名を検索対象に含むか否か
/// title: タイトルを検索対象に含むか否か
/// keyword: キーワードを検索対象に含むか否か
/// ex: あらすじを検索対象に含むか否か
+ (NSArray*)Search:(NSString*) searchString wname:(BOOL)wname title:(BOOL)title keyword:(BOOL)keyword ex:(BOOL)ex order:(NSString*)order;

/// 小説家になろうで検索を行います
/// 作者の user_id での検索です
+ (NSArray*)SearchUserID:(NSString*)userID;

/// 小説家になろうで検索を行います
/// ncode での検索です。
/// ncode は @"-" で区切ることで複数検索を同時にできます
+ (NSArray*)SearchNcode:(NSString*)ncodeList;

/// 小説家になろうでtextダウンロードを行うためのURLを取得します。
/// 失敗した場合は nil を返します。
/// 解説：
/// 小説家になろうでは ncode というもので個々のコンテンツを管理しているのですが、
/// テキストのダウンロードではこの ncode ではない別の code を使っているようです。
/// この code の取得方法はその小説のページのHTMLを読み込まないとわからないため、
/// ここではその小説のページのHTMLを読み込んで、ダウンロード用の FORM GET に渡すURLを生成します。
+ (NSString*)GetTextDownloadURL:(NSString*)ncode;

/// 小説家になろうでTextダウンロードを行います。
/// ここで指定される download_url は、GetTextDownloadURL で得られたダウンロード用のURLを用います。
+ (NSString*)TextDownload:(NSString*)download_url count:(int)count;

/// 小説家になろうで ncode を指定して最新の NarouContent情報 を取得します。
+ (NarouContentCacheData*)GetCurrentNcodeContentData:(NSString*)ncode;

/// HTTP Get Request を投げて、バイナリを返します
+ (NSData*)HttpGetBinary:(NSString*)url;
/// HTTP Get Request を投げて、文字列として返します。
+ (NSString*)HttpGet:(NSString*)url;

@end
