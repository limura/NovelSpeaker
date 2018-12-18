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

static NSURLSession* session = nil;

+ (NSURLSession*)GetSession {
    if (session != nil) {
        return session;
    }
    session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
    return session;
}

/// なろう検索APIのURLを使って検索結果を取得します。
+ (NSArray*)SearchWithURL:(NSString*)queryUrl
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
+ (NSArray*)Search:(NSString*) searchString wname:(BOOL)wname title:(BOOL)title keyword:(BOOL)keyword ex:(BOOL)ex order:(NSString*)order
{
    // 18禁のに接続したければ、ここの URL を api.syousetu.com/novelapi/... って所を
    // api.syousetu.com/novel18api/ に書き換えればOKらしいよ？ 試してないけど。
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"https://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500", nil];
    
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
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"https://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500&userid=%@", userID];
    return [NarouLoader SearchWithURL:queryUrl];
}


/// 小説家になろうで検索を行います
/// ncode での検索です。
/// ncode は @"-" で区切ることで複数検索を同時にできます
+ (NSArray*)SearchNcode:(NSString*)ncodeList
{
    NSString* escapedString = [ncodeList stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"https://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500&ncode=%@", escapedString];
    return [NarouLoader SearchWithURL:queryUrl];
}

/// 小説家になろうで ncode を指定して最新の NarouContent情報 を取得します。
+ (NarouContentCacheData*)GetCurrentNcodeContentData:(NSString*)ncode
{
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"https://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=500&ncode=%@", ncode];

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
    NSString* lcaseNcode = [ncode lowercaseString];
    NSString* htmlURL = [[NSString alloc] initWithFormat:@"https://ncode.syosetu.com/%@/", lcaseNcode];
    NSString* html = [self HttpGet:htmlURL];
    if (html == nil) {
        return nil;
    }
    // この html から、正規表現を使って
    // onclick="javascript:window.open('http://ncode.syosetu.com/txtdownload/top/ncode/562600/'
    // といった文字列の、562600 の部分を取得します。
    // 2018/12/18: textdownload の link が消えてるので他の所から取り出します
    // trackback:ping="https://trackback.syosetu.com/send/novel/ncode/1052106/
    NSString* matchPattern = @"trackback:ping=\\\"https://trackback.syosetu.com/send/novel/ncode/([^/]*)/\\\"";
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
    return [[NSString alloc] initWithFormat:@"https://ncode.syosetu.com/txtdownload/dlstart/ncode/%@/", result];
}

/// 小説家になろうの小説の、指定されたページのURLを取得します
+ (NSURL*)GetStoryURLForContent:(NarouContentCacheData*)content no:(int)no {
    if (content == nil || content.ncode == nil) {
        return nil;
    }
    NSString* lcaseNcode = [content.ncode lowercaseString];
    // 短編小説の場合は最後の /1/ はいらない
    if ([content.general_all_no intValue] == 1 && [content.end boolValue] == false) {
        return [[NSURL alloc] initWithString:[[NSString alloc] initWithFormat:@"https://ncode.syosetu.com/%@/", lcaseNcode]];
    }
    return [[NSURL alloc] initWithString:[[NSString alloc] initWithFormat:@"https://ncode.syosetu.com/%@/%d/", lcaseNcode, no]];
}

/// 小説家になろうでTextダウンロードを行います。
+ (NSString*)TextDownload:(NSString*)download_url count:(int)count
{
    NSString* url = [[NSString alloc] initWithFormat:@"%@?hankaku=0&code=utf-8&kaigyo=crlf&no=%d", download_url, count];
    return [self HttpGet:url];
}

/// HTTP GET request for binary
+ (NSData*)HttpGetBinary:(NSString*)url {
    NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"GET"];
    NSURLSession* session = [NarouLoader GetSession];
    __block NSData* result = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSURLSessionDataTask* dataTask = [session dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
            if (httpResponse.statusCode != 200) {
                dispatch_semaphore_signal(semaphore);
                return;
            }
            NSArray* cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:[httpResponse allHeaderFields] forURL:[httpResponse URL]];
            [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies:cookies forURL:[httpResponse URL] mainDocumentURL:nil];
            NSLog(@"Cookies for %@", [[httpResponse URL] absoluteString]);
            for (NSHTTPCookie* cookie in cookies) {
                NSLog(@"%@", [cookie description]);
            }
            NSLog(@"end Cookies\n\n");
            result = data;
            dispatch_semaphore_signal(semaphore);
        }
    }];
    [dataTask resume];
    while(dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW)){
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return result;
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
