//
//  NarouLoader.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouLoader.h"
#import "NarouContent.h"
#import "GlobalDataSingleton.h"
#import "NarouContentCacheData.h"

/// 小説家になろう の API 個を使って小説情報を読み出すclass。
/// SettingDataModel の NarouContent に追加するなどします。
@implementation NarouLoader

/// なろう検索APIのURLを使って検索結果を取得します。
+ (NSMutableArray*)SearchWithURL:(NSString*)queryUrl
{
    NSLog(@"search: %@", queryUrl);
    NSData* jsonData = [self HttpGetBinary:queryUrl];
    NSMutableArray* result = [NSMutableArray new];
    if (jsonData == nil) {
        return result;
    }
    
    NSError* err = nil;
    // TODO: これ NSArray と NSDictionary のどっちが帰ってくるのが正しいのかわからない形式で呼んでる？
    NSArray* contentList = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingAllowFragments error:&err];
    for(NSDictionary* jsonContent in contentList)
    {
        NarouContentCacheData* content = [[NarouContentCacheData alloc] initWithJsonData:jsonContent];
        if (content == nil || content.ncode == nil || [content.ncode length] <= 0
            || [content.ncode compare:@"(null)"] == NSOrderedSame) {
            continue;
        }
        
        [result addObject:content];
    }
    
    return result;
    
}

/// 小説家になろうで検索を行います。
/// searchString: 検索文字列
/// wname: 作者名を検索対象に含むか否か
/// title: タイトルを検索対象に含むか否か
/// keyword: キーワードを検索対象に含むか否か
/// ex: あらすじを検索対象に含むか否か
+ (NSMutableArray*)Search:(NSString*) searchString wname:(BOOL)wname title:(BOOL)title keyword:(BOOL)keyword ex:(BOOL)ex order:(NSString*)order
{
    // 18禁のに接続したければ、ここの URL を api.syousetu.com/novelapi/... って所を
    // api.syousetu.com/novel18api/ に書き換えればOKらしいよ？ 試してないけど。
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"http://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500", nil];
    
    if (searchString != nil) {
        queryUrl = [queryUrl stringByAppendingFormat:@"&word=%@", [self URIEncode:searchString]];
    }
    if (wname)
    {
        queryUrl = [queryUrl stringByAppendingString:@"&wname=1"];
    }
    if (title)
    {
        queryUrl = [queryUrl stringByAppendingString:@"&title=1"];
    }
    if (keyword)
    {
        queryUrl = [queryUrl stringByAppendingString:@"&keyword=1"];
    }
    if (ex)
    {
        queryUrl = [queryUrl stringByAppendingString:@"&ex=1"];
    }
    if (order != nil) {
        queryUrl = [queryUrl stringByAppendingString:[[NSString alloc] initWithFormat:@"&order=%@", order]];
    }
    return [NarouLoader SearchWithURL:queryUrl];
}

/// 小説家になろうで検索を行います
/// 作者の user_id での検索です
+ (NSArray*)SearchUserID:(NSString*)userID
{
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"http://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500&userid=%@", userID];
    return [NarouLoader SearchWithURL:queryUrl];
}


/// 小説家になろうで検索を行います
/// ncode での検索です。
/// ncode は @"-" で区切ることで複数検索を同時にできます
+ (NSArray*)SearchNcode:(NSString*)ncodeList
{
    NSString* escapedString = [ncodeList stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"http://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500&ncode=%@", escapedString];
    return [NarouLoader SearchWithURL:queryUrl];
}

/// 小説家になろうで ncode を指定して最新の NarouContent情報 を取得します。
+ (NarouContentCacheData*)GetCurrentNcodeContentData:(NSString*)ncode
{
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"http://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500&ncode=%@", ncode];

    NSData* jsonData = [self HttpGetBinary:queryUrl];
    if (jsonData == nil) {
        return nil;
    }
    
    NSError* err = nil;
    // TODO: これ NSArray と NSDictionary のどっちが帰ってくるのが正しいのかわからない形式で呼んでる？
    NSArray* contentList = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingAllowFragments error:&err];
    // 複数あるので探します。
    for(NSDictionary* jsonContent in contentList)
    {
        NarouContentCacheData* content = [[NarouContentCacheData alloc] initWithJsonData:jsonContent];
        if (content.ncode == nil || [content.ncode length] <= 0) {
            continue;
        }
        if ([ncode compare:content.ncode] == NSOrderedSame) {
            NarouContentCacheData* previousContent = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:ncode];
            if (previousContent != nil) {
                content.reading_chapter = previousContent.reading_chapter;
                content.currentReadingStory = previousContent.currentReadingStory;
                content.is_new_flug  = previousContent.is_new_flug;
            }
            return content;
        }
    }
    NSLog(@"ncode: %@ で検索しましたが、結果がありませんでした。", ncode);
    return nil;
}


/// 文字列をURIエンコードします。
+ (NSString*) URIEncode:(NSString*)str
{
    NSString *encodedText = (__bridge_transfer NSString *)
    CFURLCreateStringByAddingPercentEscapes(NULL,
                                            (__bridge CFStringRef)str, //元の文字列
                                            NULL,
                                            CFSTR("!*'();:@&=+$,/?%#[]"),
                                            CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
    return encodedText;
}

/// 小説家になろうでtextダウンロードを行うためのURLを取得します。
/// 失敗した場合は nil を返します。
/// 解説：
/// 小説家になろうでは ncode というもので個々のコンテンツを管理しているのですが、
/// テキストのダウンロードではこの ncode ではない別の code を使っているようです。
/// この code の取得方法はその小説のページのHTMLを読み込まないとわからないため、
/// ここではその小説のページのHTMLを読み込んで、ダウンロード用の FORM GET に渡すURLを生成します。
+ (NSString*)GetTextDownloadURL:(NSString*)ncode
{
    // まずは通常のHTMLを取得します。
    NSString* htmlURL = [[NSString alloc] initWithFormat:@"http://ncode.syosetu.com/%@/", ncode];
    NSString* html = [self HttpGet:htmlURL];
    if (html == nil) {
        return nil;
    }
    // この html から、正規表現を使って
    // onclick="javascript:window.open('http://ncode.syosetu.com/txtdownload/top/ncode/562600/'
    // といった文字列の、562600 の部分を取得します。
    NSString* matchPattern = @"onclick=\"javascript:window.open\\('https?://ncode.syosetu.com/txtdownload/top/ncode/([^/]*)/'";
    NSError* err = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:matchPattern options:NSRegularExpressionCaseInsensitive error:&err];
    if (err != nil) {
        NSLog(@"Regex create failed: %@, %@", err, [err userInfo]);
        return nil;
    }
    
    NSTextCheckingResult* checkResult = [regex firstMatchInString:html options:NSMatchingReportProgress range:NSMakeRange(0, [html length])];
    if (checkResult == nil) {
        NSLog(@"FATAL: textdownload regex not match.");
        return nil;
    }
    NSString* result = [html substringWithRange:[checkResult rangeAtIndex:1]];
    return [[NSString alloc] initWithFormat:@"http://ncode.syosetu.com/txtdownload/dlstart/ncode/%@/", result];
}

/// 小説家になろうでTextダウンロードを行います。
+ (NSString*)TextDownload:(NSString*)download_url count:(int)count
{
    NSString* url = [[NSString alloc] initWithFormat:@"%@?hankaku=0&code=utf-8&kaigyo=CRLF&no=%d", download_url, count];
    return [self HttpGet:url];
}

/// HTTP GET request for binary
+ (NSData*)HttpGetBinary:(NSString*)url {
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    return [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
}
/// HTTP GET request
+ (NSString*)HttpGet:(NSString*)url {
    NSData* data = [self HttpGetBinary:url];
    if (data == nil) {
        return nil;
    }
    NSString* str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str;
}

@end
