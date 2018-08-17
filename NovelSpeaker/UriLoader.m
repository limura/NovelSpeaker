//
//  UriLoader.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/08.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "UriLoader.h"
#import "SiteInfo.h"
#import "NiftyUtility.h"
#import "GlobalDataSingleton.h"
#import "NovelSpeaker-Swift.h"

@implementation UriLoader

- (id)init {
    self = [super init];
    if (self == nil) {
        return self;
    }
    
    m_SleepTime = 1.6f;
    m_MaxDepth = 100;
    m_SiteInfoArray = [NSMutableArray new];
    m_CustomSiteInfoArray = [NSMutableArray new];
    m_WebAccessQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.uriloader.webaccessqueue", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

/// 保存されている SiteInfo を開放します
- (void)ClearSiteInfoCache{
    if (m_SiteInfoArray != nil) {
        [m_SiteInfoArray removeAllObjects];
    }
    if (m_CustomSiteInfoArray != nil) {
        [m_CustomSiteInfoArray removeAllObjects];
    }
    m_SiteInfoArray = [NSMutableArray new];
    m_CustomSiteInfoArray = [NSMutableArray new];
}

/// SiteInfo のJSONを解析した後の NSArray を元に内部データベースに追加します
- (BOOL)AddSiteInfoFromJsonArray:(NSArray *)siteInfoJsonArray targetSiteInfoArray:(NSMutableArray*)targetSiteInfoArray {
    NSMutableArray* tmpArray = [NSMutableArray new];
    if (siteInfoJsonArray == nil || ![siteInfoJsonArray isKindOfClass:[NSArray class]]) {
        NSLog(@"AddSiteInfoFromJsonArray: siteInfoJsonArray invalid: %@", siteInfoJsonArray);
        return false;
    }
    
    for (NSDictionary* firstObject in siteInfoJsonArray) {
        if (![firstObject isKindOfClass:[NSDictionary class]]) {
            NSLog(@"AddSiteInfoFromJsonArray: isKindOfClass failed.");
            continue;
        }
        NSDictionary* secondObject = [NiftyUtility validateNSDictionaryForDictionary:firstObject key:@"data"];
        if (secondObject == nil) {
            NSLog(@"AddSiteInfoFromJsonArray: data not found.");
            continue;
        }
        NSString* urlPattern = [NiftyUtility validateNSDictionaryForString:secondObject key:@"url"];
        NSString* pageElement = [NiftyUtility validateNSDictionaryForString:secondObject key:@"pageElement"];
        if (urlPattern == nil || pageElement == nil) {
            NSLog(@"AddSiteInfoFromJsonArray: urlPattern or pageElement is not found.");
            continue;
        }
        NSString* nextLink = [NiftyUtility validateNSDictionaryForString:secondObject key:@"nextLink"];
        if (nextLink == nil) {
            nextLink = @"";
        }
        NSString* title = [NiftyUtility validateNSDictionaryForString:secondObject key:@"title"];
        if (title == nil) {
            title = @"//title";
        }
        NSString* author = [NiftyUtility validateNSDictionaryForString:secondObject key:@"author"];
        if (author == nil) {
            author = @"";
        }
        NSString* firstPageLink = [NiftyUtility validateNSDictionaryForString:secondObject key:@"firstPageLink"];
        if (firstPageLink == nil) {
            firstPageLink = @"";
        }
        NSString* tag = [NiftyUtility validateNSDictionaryForString:secondObject key:@"tag"];
        if (tag == nil) {
            tag = @"";
        }
        SiteInfo* siteInfo = [[SiteInfo alloc] initWithParams:urlPattern nextLink:nextLink pageElement:pageElement title:title author:author firstPageLink:firstPageLink tag:tag];
        if (siteInfo == nil) {
            NSLog(@"AddSiteInfoFromJsonArray: siteInfo == nil");
            continue;
        }
        //NSLog(@"AddSiteInfoFromJsonArray: addObject: %@", [siteInfo GetDescription]);
        [tmpArray addObject:siteInfo];
    }
    NSArray* sortedArray = [tmpArray sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        SiteInfo* a = obj1;
        SiteInfo* b = obj2;
        NSUInteger aLength = [a GetSortHint];
        NSUInteger bLength = [b GetSortHint];
        if (aLength > bLength) {
            return NSOrderedAscending;
        }else if (aLength < bLength) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    for (SiteInfo* siteInfo in sortedArray) {
        [targetSiteInfoArray addObject:siteInfo];
    }
    return true;
}

/// SiteInfo のJSONを内部データベースに追加します。
- (BOOL)AddSiteInfoFromData:(NSData*)siteInfo{
    NSError* error = nil;
    if (siteInfo == nil) {
        return false;
    }
    NSArray* jsonArray = [NSJSONSerialization JSONObjectWithData:siteInfo options:NSJSONReadingAllowFragments error:&error];
    if (jsonArray == nil || error != nil) {
        NSLog(@"AddSiteInfoFromData jsonArray == nil or error != nil. jsonArray: %p, error: %p(%@)", jsonArray, error, error);
        return false;
    }
    return [self AddSiteInfoFromJsonArray:jsonArray targetSiteInfoArray:m_SiteInfoArray];
}

/// SiteInfo のJSON文字列を内部データベースに追加します。
- (BOOL)AddSiteInfoFromString:(NSString*)siteInfo{
    return [self AddSiteInfoFromData:[siteInfo dataUsingEncoding:NSUTF8StringEncoding]];
}

/// SiteInfo をURLから内部データベースに追加します。
- (void)AddSiteInfoFromURL:(NSURL*)url successAction:(void(^)(void))successAction failedAction:(void(^)(NSURL* url))failedAction{
    dispatch_async(m_WebAccessQueue, ^(){
        NSURLRequest* request = [NSURLRequest requestWithURL:url];
        NSError* error;
        NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:&error];
        if (data == nil) {
            if (failedAction != nil) {
                failedAction(url);
                return;
            }
        }
        if (![self AddSiteInfoFromData:data]) {
            if (failedAction != nil) {
                failedAction(url);
                return;
            }
        }
        if (successAction != nil) {
            successAction();
        }
    });
}

/// ことせかい用にカスタムされた SiteInfo (Autopagerize由来ではないSiteInfo) のJSONを内部データベースに追加します。
- (BOOL)AddCustomSiteInfoFromData:(NSData*)siteInfo{
    if (siteInfo == nil) {
        return false;
    }
    NSError* error = nil;
    NSArray* jsonArray = [NSJSONSerialization JSONObjectWithData:siteInfo options:NSJSONReadingAllowFragments error:&error];
    if (jsonArray == nil || error != nil) {
        return false;
    }
    return [self AddSiteInfoFromJsonArray:jsonArray targetSiteInfoArray:m_CustomSiteInfoArray];
}


/// 内部で保持している情報のうち、対象のURLに適用可能と思われる SiteInfo* をArrayで取得します。
/// 取得された配列は、先頭のものの方が価値が良いものとなっています。(ということにしておきます)
- (NSArray*)searchSiteInfoForURL:(NSURL*)url {
    NSMutableArray* resultArray = [NSMutableArray new];

    for (SiteInfo* siteInfo in m_CustomSiteInfoArray) {
        //NSLog(@"check: %@", [siteInfo GetDescription]);
        if ([siteInfo isTargetUrl:url]) {
            [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"ことせかい用SiteInfoの一つを採用します: %@", [siteInfo GetDescription]]];
            [resultArray addObject:siteInfo];
        }
    }

    for (SiteInfo* siteInfo in m_SiteInfoArray) {
        if ([siteInfo isTargetUrl:url]) {
            [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"Autopagerize用SiteInfoの一つを採用します: %@", [siteInfo GetDescription]]];
            [resultArray addObject:siteInfo];
        }
    }

    SiteInfo* defaultSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"(//link|//a)[contains(concat(' ', translate(normalize-space(@rel),'NEXT','next'), ' '), ' next ')]" pageElement:@"//*[contains(@class,'autopagerize_page_element')]|//*[contains(@itemprop,'articleBody')]" title:@"//title" author:@"" firstPageLink:@"" tag:@""];
    [resultArray addObject:defaultSiteInfo];
    SiteInfo* fallbackSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"" pageElement:@"//body" title:@"//title" author:@"" firstPageLink:@"" tag:@""];
    [resultArray addObject:fallbackSiteInfo];
    /*
    fallbackSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"" pageElement:@"//\*" title:@"//title" author:@""];
    [resultArray addObject:fallbackSiteInfo];
    */

    return resultArray;
}

+ (NSString*)GetContentCharSetFromHTTPResponse:(NSHTTPURLResponse*)httpResponse {
    NSDictionary* dictionary = [httpResponse allHeaderFields];
    if (dictionary == nil) {
        return nil;
    }
    NSString* contentType = [dictionary valueForKey:@"Content-Type"];
    if (contentType == nil) {
        return nil;
    }
    NSRegularExpression* regexp = [[NSRegularExpression alloc] initWithPattern:@"; *charset=([^ ]*)" options:0 error:nil];
    NSTextCheckingResult* result = [regexp firstMatchInString:contentType options:0 range:NSMakeRange(0, contentType.length)];
    if (result == nil) {
        NSLog(@"header: charset unknwon. %@", contentType);
        return nil;
    }
    if (result.numberOfRanges <= 0) {
        NSLog(@"header: charset unknown numberOfRanges <= 0: %@", contentType);
        return nil;
    }
    NSRange range = [result rangeAtIndex:1];
    NSString* encodingString = [contentType substringWithRange:range];
    return encodingString;
}

+ (NSString*)GetContentCharSet:(NSHTTPURLResponse*)httpResponse data:(NSData*)data faileoverCharset:(NSString*)faileoverCherset {
    NSDictionary* targetEncodings = @{
                                      @"utf-8": [NSNumber numberWithUnsignedLong:NSUTF8StringEncoding]
                                      , @"euc-jp": [NSNumber numberWithUnsignedLong:NSJapaneseEUCStringEncoding]
                                      , @"shift_jis": [NSNumber numberWithUnsignedLong:NSShiftJISStringEncoding]
                                      , @"iso-2022-jp": [NSNumber numberWithUnsignedLong:NSISO2022JPStringEncoding]
                                      };
    NSString* headerCharset = [UriLoader GetContentCharSetFromHTTPResponse:httpResponse];
    if (headerCharset != nil) {
        return headerCharset;
    }
    NSString* tmpString = nil;
    NSString* guessEncoding = nil;
    for (NSString* key in targetEncodings) {
        NSNumber* encoding = [targetEncodings objectForKey:key];
        tmpString = [[NSString alloc] initWithData:data encoding:[encoding unsignedLongValue]];
        if (tmpString != nil) {
            guessEncoding = key;
            break;
        }
    }
    if (tmpString == nil) {
        return @"utf-8";
    }
    //NSLog(@"tmpString: %p, %lu, %@", tmpString, (unsigned long)tmpString.length, guessEncoding);
    
    NSArray* charsetTagRegexpArray = @[
       @"content=[\"'].*?; *charset=(.*?)[\"']",
       @"meta +charset=[\"'](.*?)[\"']",
    ];
    for (NSString* pattern in charsetTagRegexpArray) {
        NSError* err = nil;
        NSRegularExpression* regexp = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&err];
        NSTextCheckingResult* match = [regexp firstMatchInString:tmpString options:0 range:NSMakeRange(0, tmpString.length)];
        if (match.numberOfRanges >= 2) {
            NSString* charset = [tmpString substringWithRange:[match rangeAtIndex:1]];
            if (charset != nil && charset.length > 0) {
                NSLog(@"charset found: %@", charset);
                return charset;
            }
        }
    }
    if (guessEncoding != nil) {
        NSLog(@"charset not found. return guess: %@", guessEncoding);
        return guessEncoding;
    }
    return faileoverCherset;
}

+ (unsigned long)charsetToNSStringEncodingValue:(NSString*)charsetString{
    NSDictionary* targetEncodings = @{
                                      @"UTF-8": [NSNumber numberWithUnsignedLong:NSUTF8StringEncoding]
                                      , @"EUC-JP": [NSNumber numberWithUnsignedLong:NSJapaneseEUCStringEncoding]
                                      , @"Shift_JIS": [NSNumber numberWithUnsignedLong:NSShiftJISStringEncoding]
                                      , @"ISO-2022-JP": [NSNumber numberWithUnsignedLong:NSISO2022JPStringEncoding]
                                      };
    if (charsetString == nil) {
        return NSUTF8StringEncoding;
    }
    for (NSString* key in targetEncodings) {
        if ([charsetString caseInsensitiveCompare:key] == NSOrderedSame) {
            NSNumber* encoding = [targetEncodings valueForKey:key];
            return [encoding unsignedLongValue];
        }
    }
    NSLog(@"charset \"%@\" is unknown name. return NSUTF8StringEncoding(%lu)", charsetString, (unsigned long)NSUTF8StringEncoding);
    return NSUTF8StringEncoding;
}

+ (void)HttpGetAsync:(NSURL*)url successAction:(void(^)(NSData* data, NSHTTPURLResponse* response, NSURL* requestURL))successAction failedAction:(void(^)(NSURL* requestURL))failedAction {
    NSURLRequest* request = [NSURLRequest requestWithURL:url];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError) {
        NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
        if (data == nil
            || httpResponse == nil
            || ((int)httpResponse.statusCode / 100 ) != 2) {
            if (failedAction != nil) {
                failedAction(url);
                return;
            }
        }
        if (successAction == nil) {
            return;
        }
        successAction(data, httpResponse, url);
    }];
}

+ (BOOL)CheckContentTypeSame:(NSString*)target httpResponse:(NSHTTPURLResponse*)httpResponse {
    id contentTypeId = [[httpResponse allHeaderFields] objectForKey:@"Content-Type"];
    if ([contentTypeId isKindOfClass:[NSString class]]) {
        NSString* contentType = contentTypeId;
        return [[target lowercaseString] isEqualToString:[contentType lowercaseString]];
    }
    return false;
}

/// 指定されたURLからGETで取得したデータをUTF-8に変換してNSDataとして返します。
/// これはブロッキングします。リクエストに失敗した時など明確にエラーした場合は nil を返します。
/// ただ、encodingがわからなかった場合は何も変換せず返すので注意してください。
+ (NSData*)GetHtmlDataAboutUTF8Encorded:(NSURL*)targetUrl cookieStorage:(NSHTTPCookieStorage*)cookieStorage out_charSetString:(NSMutableString**)out_charsetString out_charsetValue:(unsigned long*)out_charsetValue out_error:(NSMutableString*)out_errorString
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:targetUrl];
    
    NSArray* cookieArray = [cookieStorage cookiesForURL:targetUrl];
    NSDictionary* header = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieArray];
    [request setAllHTTPHeaderFields:header];

    NSError* error;
    NSURLResponse* response;
    NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    NSLog(@"NSURLConnection return: data(%lu bytes), error: %@", (unsigned long)[data length], [error localizedDescription]);
    if (data == nil) {
        if (out_errorString != nil) {
            [out_errorString setString:NSLocalizedString(@"UriLoader_NSURLConnectionRequestFailed", @"Webサーバからの取得に失敗しました。(接続失敗？)")];
        }
        return nil;
    }
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    if ((int)(httpResponse.statusCode / 100) != 2) {
        NSLog(@"HTTP status code is not 2?? (%ld) url: %@", (long)httpResponse.statusCode, [targetUrl absoluteString]);
        if (out_errorString != nil) {
            [out_errorString setString:[[NSString alloc] initWithFormat:NSLocalizedString(@"UriLoader_HTTPResponseIsInvalid", @"サーバから返されたステータスコードが正常値(200 OK等)ではなく、%ld を返されました。ログインが必要なサイトである場合などに発生する場合があります。ことせかい アプリ側でできることはあまり無いかもしれませんが、ことせかい のサポートサイトに設置してあります、ご意見ご要望フォームにこの問題の起こったURLとこの症状が起こった前にやったことを添えて報告して頂けると、あるいはなんとかできるかもしれません。"), httpResponse.statusCode]];
            [BehaviorLogger AddLogWithDescription:@"GetHtmlDataAboutUTF8Encorded HTTP status code fail" data:@{
                  @"returned HTTP status code": [NSString stringWithFormat:@"%ld", (long)httpResponse.statusCode],
                  @"url": targetUrl == nil ? @"nil" : [targetUrl absoluteString],
                  @"request header": request == nil ? @"nil": [request allHTTPHeaderFields]
            }];
        }
        return nil;
    }
    
    // pdf だったら怪しく文字列化して謎HTMLに変換してその後の処理を行います。
    if ([UriLoader CheckContentTypeSame:@"application/pdf" httpResponse:httpResponse]) {
        NSString* text = [NiftyUtilitySwift BinaryPDFToStringWithData:data];
        if (text != nil) {
            NSString* fileName = [[targetUrl lastPathComponent] stringByDeletingPathExtension];
            if (fileName == nil || [fileName length] <= 0) {
                fileName = @"unknwon document";
            }
            NSString* dummyHtml = [[NSString alloc] initWithFormat:@"<html><title>%@</title><meta charset=\"UTF-8\"><body><pre>%@</pre></body></html>", fileName, text];
            data = [dummyHtml dataUsingEncoding:NSUTF8StringEncoding];
        }
    }
    
    NSString* encoding = [self GetContentCharSet:httpResponse data:data faileoverCharset:@"UTF-8"];
    //NSLog(@"final encoding: %@", encoding);
    unsigned long charsetValue = [UriLoader charsetToNSStringEncodingValue:encoding];
    
    // charset が UTF-8 でなければ強引に UTF-8 にしたものを生成してそれを使います
    NSString* decodedString = nil;
    if (charsetValue != NSUTF8StringEncoding) {
        decodedString = [[NSString alloc] initWithData:data encoding:charsetValue];
    }
    if (decodedString != nil) {
        NSData* decodedData = [decodedString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:TRUE];
        if (decodedData != nil) {
            data = decodedData;
            encoding = @"utf-8";
            charsetValue = NSUTF8StringEncoding;
            NSLog(@"data override to utf8");
        }
    }
    if (out_charsetString != nil) {
        [*out_charsetString setString:encoding];
    }
    if (out_charsetValue != nil) {
        *out_charsetValue = charsetValue;
    }
    return data;
}

// 指定された NSHTTPCookieStorage に入っている変なkeyになっている cookie項目 を削除します
// 変なkey: 行頭に空白が入っているもの
// 補足: この 変なkey があると、同じkeyが延々と追加されていってしまいには cookie header がでかくなりすぎて 400 を返すことになる(と思う)
+ (void)RemoveInvalidKeyDataFromCookieStorage:(NSHTTPCookieStorage*)storage {
    NSMutableArray<NSHTTPCookie*>* deleteTargets = [NSMutableArray new];
    for (NSHTTPCookie* cookie in storage.cookies) {
        NSString* key = cookie.name;
        NSString* validKey = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([key compare:validKey] == NSOrderedSame) {
            continue;
        }
        [deleteTargets addObject:cookie];
    }
    for (NSHTTPCookie* cookie in deleteTargets) {
        [storage deleteCookie:cookie];
    }
}

- (NSHTTPCookieStorage*)createCookieStorage:(NSArray*)cookieArray url:(NSURL*)url{
    NSHTTPCookieStorage* cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    //NSHTTPCookieStorage* cookieStorage = [NSHTTPCookieStorage new];
    //NSLog(@"LoadURL: cookieArray: %@", cookieArray);
    NSMutableDictionary<NSString*, NSString*>* storedCookieDictionary = [NSMutableDictionary new];
    if (cookieArray != nil && [cookieArray count] > 0) {
        for (NSString* keyValue in cookieArray) {
            NSArray* keyValueArray = [[keyValue stringByRemovingPercentEncoding] componentsSeparatedByString:@"="];
            if (keyValueArray != nil && [keyValueArray count] == 2) {
                NSString* key = [keyValueArray[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString* value = [keyValueArray[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSString* host = [url host];
                if (key == nil || [key length] <= 0 || value == nil || [value length] <= 0 || host == nil) {
                    continue;
                }
                NSString* storedValue = [storedCookieDictionary objectForKey:key];
                if (storedValue != nil && [storedValue compare:value] == NSOrderedSame) {
                    continue;
                }
                
                //NSLog(@"#### add cookie: %@=%@ ####", key, value);
                NSDictionary* cookieDictionary = @{NSHTTPCookieName   : key,
                                                   NSHTTPCookieValue  : value,
                                                   NSHTTPCookiePath   : @"/",
                                                   NSHTTPCookieDomain : host,
                                                   NSHTTPCookieExpires: [[NSDate date] dateByAddingTimeInterval:3600]};
                NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:cookieDictionary];
                [cookieStorage setCookie:cookie];
                [storedCookieDictionary setObject:key forKey:value];
            }
        }
    }
    return cookieStorage;
}

- (HtmlStory*)FetchStoryForURL:(NSURL*)targetUrl cookieStorage:(NSHTTPCookieStorage*)cookieStorage out_error:(NSMutableString*)out_errorString {
    NSMutableString* charSetString = [NSMutableString new];
    unsigned long charsetValue = 0;
    NSData* data = [UriLoader GetHtmlDataAboutUTF8Encorded:targetUrl cookieStorage:cookieStorage out_charSetString:&charSetString out_charsetValue:&charsetValue out_error:out_errorString];
    if (data == nil) {
        NSLog(@"fetchURL failed: data == nil");
        [BehaviorLogger AddLogWithDescription:@"FetchStoryForURL UriLoader GetHtmlDataAboutUTF8Encorded failed." data:@{
                @"out_error": out_errorString == nil ? @"nil" : out_errorString,
                @"url": targetUrl == nil ? @"nil" : [targetUrl absoluteString]
                }];
        return nil;
    }
    /*
    if(false){
        NSString* htmlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"show\\.php\\?(id=[0-9]*)" options:NSRegularExpressionCaseInsensitive error:nil];
        [regex enumerateMatchesInString:htmlString options:0 range:NSMakeRange(0, [htmlString length]) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
            NSLog(@"html regex match: %@", [htmlString substringWithRange:[result range]]);
        }];
        NSLog(@"%@ loaded\n%@", [targetUrl absoluteString], htmlString);
    }
    */
    
    xmlDocPtr document = htmlReadMemory([data bytes], (int)[data length], [[targetUrl absoluteString] cStringUsingEncoding:NSUTF8StringEncoding], [[charSetString lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding], HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR);
    if (document == NULL) {
        NSLog(@"xmlParseMemory() failed: %@\n%@", [targetUrl absoluteString], [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        if (out_errorString != nil) {
            [out_errorString setString:NSLocalizedString(@"UriLoader_HTMLParseFailed_Parse", @"HTMLの解析に失敗しました。(parse)")];
        }
        return nil;
    }
    xmlXPathContextPtr context;
    context = xmlXPathNewContext(document);
    if (context == NULL) {
        xmlFreeDoc(document);
        NSLog(@"xmlXPathNewContext() failed: %@", [targetUrl absoluteString]);
        if (out_errorString != nil) {
            [out_errorString setString:NSLocalizedString(@"UriLoader_HTMLParseFailed_Xpath", @"HTMLの解析に失敗しました。(xpath)")];
        }
        return nil;
    }
    
    HtmlStory* story = [HtmlStory new];
    NSArray* siteInfoArray = [self searchSiteInfoForURL:targetUrl];
    NSURL* firstPageLink = nil;
    [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"URL %@ に対して SiteInfo のマッチングを開始します。", [targetUrl absoluteString]]];
    for (SiteInfo* siteInfo in siteInfoArray) {
        // firstPageLink の中身がなければ検索しておきます。
        if (firstPageLink == nil) {
            firstPageLink = [siteInfo GetFirstPageURL:document context:context currentURL:targetUrl documentEncoding:charsetValue];
            if (firstPageLink != nil) {
                [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"firstPageLink に hit しました。firstPageURL: %@, siteInfo: %@", [firstPageLink absoluteString], [siteInfo GetDescription]]];
            }
        }
        NSString* pageHtml = [siteInfo GetPageElement:document context:context documentEncoding:charsetValue];
        // pageHtml がみつからないで、かつ、firstPageLink がみつかっていない場合は次の siteInfo を検索します
        if ((pageHtml == nil || [pageHtml length] <= 0) && firstPageLink == nil) {
            [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"pageElement と firstPageLink のどちらもヒットしませんでした。siteInfo: %@", [siteInfo GetDescription]]];
            continue;
        }
        if (pageHtml == nil) {
            pageHtml = @"";
        }
        NSString* removeRubyString = [SiteInfo RemoveRubyTag:pageHtml];
        NSString* replaceLonlyTagString = [SiteInfo ReplaceXhtmlLonlyTag:removeRubyString];
        NSString* tmpString = [replaceLonlyTagString stringByReplacingOccurrencesOfString:@"&#13;" withString:@""];
        if (tmpString == nil || [tmpString length] <= 0) {
            NSLog(@"tmpString == nil || tmpString.length <= 0");
            continue;
        }
        NSAttributedString* textAttributedString = [SiteInfo HtmlStringToAttributedString:tmpString];
        story.content = textAttributedString.string;
        story.title = [siteInfo GetTitle:document context:context documentEncoding:charsetValue];
        story.author = [siteInfo GetAuthor:document context:context documentEncoding:charsetValue];
        story.nextUrl = [siteInfo GetNextURL:document context:context currentURL:targetUrl documentEncoding:charsetValue];
        story.firstPageLink = firstPageLink;
        [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"SiteInfo hit: %@ on %@", [siteInfo GetDescription], [targetUrl absoluteString]]];
        break;
    }
    xmlXPathFreeContext(context);
    xmlFreeDoc(document);
    
    if (story.content == nil || [story.content length] <= 0) {
        NSLog(@"fetchURL failed: story.content == nil or length <= 0");
        if (out_errorString != nil) {
            [out_errorString setString:NSLocalizedString(@"UriLoader_HTMLParseFailed_ContentIsNil", @"HTMLの解析に失敗しました。(content is nil)")];
        }
        return nil;
    }
    
    story.url = [targetUrl absoluteString];
    return story;
}

/// テスト用に一つのURLを取得します。
- (void)FetchOneUrl:(NSURL*)url cookieArray:(NSArray*)cookieArray successAction:(void(^)(HtmlStory* story))successAction failedAction:(void(^)(NSURL* url, NSString* errorString))failedAction {
    dispatch_async(m_WebAccessQueue, ^{
        NSHTTPCookieStorage* cookieStorage = [self createCookieStorage:cookieArray url:url];
        NSMutableString* errorMutableString = [NSMutableString new];
        HtmlStory* story = [self FetchStoryForURL:url cookieStorage:cookieStorage out_error:errorMutableString];
        if (story == nil) {
            if (failedAction) {
                failedAction(url, errorMutableString);
            }
            return;
        }
        if (successAction) {
            successAction(story);
        }
    });
}

/// URLを読み込んで、SiteInfo の情報から得た PageElement の情報を NSString に変換して取り出しつつ、
/// MaxDepth まで nextLink を辿ったものを、PageElement毎の配列として取り出します。
/// 該当する siteinfo が無い場合、a rel="next" であったり class="autopagerize_page_element" であるものを取り出そうとします。
- (void)LoadURL:(NSURL*)url cookieArray:(NSArray*)cookieArray startCount:(int)startCount successAction:(BOOL(^)(HtmlStory* story, NSURL* currentURL))successAction failedAction:(void(^)(NSURL* url))failedAction finishAction:(void(^)(NSURL* url))finishAction{
    NSLog(@"LoadURL: %@", [url absoluteString]);
    
    dispatch_async(m_WebAccessQueue, ^(){
        NSURL* targetUrl = url;
        int count = startCount;
        BOOL success = false;

        NSHTTPCookieStorage* cookieStorage = [self createCookieStorage:cookieArray url:url];

        for (int i = 0; i < self->m_MaxDepth && targetUrl != nil; i++) {
            NSMutableString* errorMutableString = [NSMutableString new];
            HtmlStory* story = [self FetchStoryForURL:targetUrl cookieStorage:cookieStorage out_error:errorMutableString];
            if (story == nil) {
                NSLog(@"FetchURL failed. %@", errorMutableString);
                break;
            }
            if (story.content == nil || [story.content length] <= 0) {
                continue;
            }

            story.count = count++;
            success = true;
            if (successAction != nil) {
                if (!successAction(story, targetUrl)){
                    break;
                }
            }
            
            if (story.nextUrl == nil) {
                break;
            }
            targetUrl = story.nextUrl;
            [NSThread sleepForTimeInterval:self->m_SleepTime];
        }
        
        if (!success && failedAction != nil) {
            failedAction(url);
        }
        if (finishAction != nil) {
            finishAction(url);
        }
    });
}

/// 最大何ページまで読み進むかを指定します
- (void)SetMaxDepth:(int)maxDepth{
    m_MaxDepth = maxDepth;
}

/// 1ページ読み込み毎に待つ時間を秒で指定します
- (void)SetSleepTimeInSecond:(float)sleepTime{
    m_SleepTime = sleepTime;
}



@end
