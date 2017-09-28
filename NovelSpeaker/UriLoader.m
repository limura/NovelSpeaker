//
//  UriLoader.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/08.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "UriLoader.h"
#import "SiteInfo.h"

@implementation UriLoader

- (id)init {
    self = [super init];
    if (self == nil) {
        return self;
    }
    
    m_SleepTime = 1.0f;
    m_MaxDepth = 100;
    m_SiteInfoArray = [NSMutableArray new];
    m_WebAccessQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.uriloader.webaccessqueue", DISPATCH_QUEUE_CONCURRENT);
    
    return self;
}

/// SiteInfo のJSONを解析した後の NSArray を元に内部データベースに追加します
- (BOOL)AddSiteInfoFromJsonArray:(NSArray *)siteInfoJsonArray targetSiteInfoArray:(NSMutableArray*)targetSiteInfoArray {
    if (siteInfoJsonArray == nil /*|| ![siteInfoJsonArray isMemberOfClass:[NSArray class]]*/) {
        NSLog(@"siteInfoJsonArray invalid: %@", siteInfoJsonArray);
        return false;
    }
    
    for (NSDictionary* firstObject in siteInfoJsonArray) {
        if (![firstObject isMemberOfClass:[NSDictionary class]]) {
            //continue;
        }
        NSDictionary* secondObject = [firstObject objectForKey:@"data"];
        if (secondObject == nil /*|| ![secondObject isMemberOfClass:[NSDictionary class]]*/) {
            continue;
        }
        NSString* urlPattern = [secondObject objectForKey:@"url"];
        NSString* nextLink = [secondObject objectForKey:@"nextLink"];
        NSString* pageElement = [secondObject objectForKey:@"pageElement"];
        if (urlPattern == nil || nextLink == nil || pageElement == nil) {
            continue;
        }
        SiteInfo* siteInfo = [[SiteInfo alloc] initWithParams:urlPattern nextLink:nextLink pageElement:pageElement];
        if (siteInfo == nil) {
            continue;
        }
        [targetSiteInfoArray addObject:siteInfo];
    }
    return true;
}

/// SiteInfo のJSONを内部データベースに追加します。
- (BOOL)AddSiteInfoFromData:(NSData*)siteInfo{
    NSLog(@"siteInfo: %p", siteInfo);
    NSError* error = nil;
    NSArray* jsonArray = [NSJSONSerialization JSONObjectWithData:siteInfo options:NSJSONReadingAllowFragments error:&error];
    if (jsonArray == nil || error != nil) {
        NSLog(@"jsonArray: %p, error: %p(%@)", jsonArray, error, error);
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

    /// XXXX ことせかい でのカスタムSiteInfoをとりあえずここに書きます。
    /// TODO: 将来的には外部からの読み込みをできるようにしておいたほうが良いです。
    NSArray* novelSpeakerCustomSiteInfoArray = @[
        // Arcadia
        //[[SiteInfo alloc] initWithParams:@"^http://(www\\.)?mai-net\\.(net|ath\\.cx)/bbs/sst/sst.php" nextLink:@"//table//td[@align=\"right\"]/a" pageElement:@"//blockquote/div"]
                                                 ];

    SiteInfo* defaultSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"//a[@rel=\"next\"]" pageElement:@"//*[@class=\"autopagerize_page_element\"]"];
    SiteInfo* fallbackSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"" pageElement:@"//body"];
    
    for (SiteInfo* siteInfo in m_SiteInfoArray) {
        if ([siteInfo isTargetUrl:url]) {
            [resultArray addObject:siteInfo];
        }
    }
    for (SiteInfo* siteInfo in novelSpeakerCustomSiteInfoArray) {
        if ([siteInfo isTargetUrl:url]) {
            [resultArray addObject:siteInfo];
        }
    }
    
    [resultArray addObject:defaultSiteInfo];
    [resultArray addObject:fallbackSiteInfo];
    
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
    NSLog(@"tmpString: %p, %lu, %@", tmpString, (unsigned long)tmpString.length, guessEncoding);
    NSError* err = nil;
    NSRegularExpression* regexp = [NSRegularExpression regularExpressionWithPattern:@"content=[\"'].*?; *charset=(.*?)[\"']" options:NSRegularExpressionCaseInsensitive error:&err];
    NSTextCheckingResult* match = [regexp firstMatchInString:tmpString options:0 range:NSMakeRange(0, tmpString.length)];
    if (match.numberOfRanges >= 2) {
        NSString* charset = [tmpString substringWithRange:[match rangeAtIndex:1]];
        if (charset != nil && charset.length > 0) {
            NSLog(@"charset found: %@", charset);
            return charset;
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
        if ([charsetString compare:key] == NSOrderedSame) {
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

// HTML から、<title>...</title> の ... の部分を取り出します。
+ (NSString*)GetHtmlTitle:(xmlDocPtr)document context:(xmlXPathContextPtr)context  documentEncoding:(unsigned long)documentEncoding {
    if (document == NULL || context == NULL) {
        return nil;
    }
    
    SiteInfo* titleSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"" pageElement:@"//title"];
    NSString* pageString = [titleSiteInfo GetPageElement:document context:context documentEncoding:documentEncoding];
    return [[NSString alloc] initWithFormat:@"%@", [SiteInfo RemoveHtmlTag:pageString]];
}

/// 指定されたURLからGETで取得したデータをUTF-8に変換してNSDataとして返します。
/// これはブロッキングします。リクエストに失敗した時など明確にエラーした場合は nil を返します。
/// ただ、encodingがわからなかった場合は何も変換せず返すので注意してください。
+ (NSData*)GetHtmlDataAboutUTF8Encorded:(NSURL*)targetUrl cookieStorage:(NSHTTPCookieStorage*)cookieStorage out_charSetString:(NSMutableString**)out_charsetString out_charsetValue:(unsigned long*)out_charsetValue
{
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:targetUrl];
    
    NSArray* cookieArray = [cookieStorage cookiesForURL:targetUrl];
    NSDictionary* header = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieArray];
    [request setAllHTTPHeaderFields:header];
    
    NSError* error;
    NSURLResponse* response;
    NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    if (data == nil) {
        return nil;
    }
    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
    if ((int)(httpResponse.statusCode / 100) != 2) {
        NSLog(@"HTTP status code is not 2?? (%ld) url: %@", (long)httpResponse.statusCode, [targetUrl absoluteString]);
        return nil;
    }
    
    NSString* encoding = [self GetContentCharSet:httpResponse data:data faileoverCharset:@"UTF-8"];
    NSLog(@"final encoding: %@", encoding);
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

/// URLを読み込んで、SiteInfo の情報から得た PageElement の情報を NSString に変換して取り出しつつ、
/// MaxDepth まで nextLink を辿ったものを、PageElement毎の配列として取り出します。
/// 該当する siteinfo が無い場合、a rel="next" であったり class="autopagerize_page_element" であるものを取り出そうとします。
- (void)LoadURL:(NSURL*)url cookieArray:(NSArray*)cookieArray startCount:(int)startCount successAction:(void(^)(HtmlStory* story, NSURL* currentURL))successAction failedAction:(void(^)(NSURL* url))failedAction finishAction:(void(^)(NSURL* url))finishAction{
    NSLog(@"LoadURL: %@", [url absoluteString]);
    
    dispatch_async(m_WebAccessQueue, ^(){
        NSURL* targetUrl = url;
        int count = startCount;
        BOOL success = false;

        NSHTTPCookieStorage* cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        NSLog(@"LoadURL: cookieArray: %@", cookieArray);
        if (cookieArray != nil && [cookieArray count] > 0) {
            for (NSString* keyValue in cookieArray) {
                NSArray* keyValueArray = [[keyValue stringByRemovingPercentEncoding] componentsSeparatedByString:@"="];
                if (keyValueArray != nil && [keyValueArray count] == 2) {
                    NSString* key = keyValueArray[0];
                    NSString* value = keyValueArray[1];
                    NSString* host = [url host];
                    if (key == nil || value == nil || host == nil) {
                        continue;
                    }
                    NSLog(@"#### add cookie: %@=%@ ####", key, value);
                    NSDictionary* cookieDictionary = @{NSHTTPCookieName   : key,
                                                       NSHTTPCookieValue  : value,
                                                       NSHTTPCookiePath   : @"/",
                                                       NSHTTPCookieDomain : host,
                                                       NSHTTPCookieExpires: [[NSDate date] dateByAddingTimeInterval:3600]};
                    NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:cookieDictionary];
                    [cookieStorage setCookie:cookie];
                }
            }
        }

        for (int i = 0; i < m_MaxDepth && targetUrl != nil; i++) {
            NSMutableString* charSetString = [NSMutableString new];
            unsigned long charsetValue = 0;
            NSData* data = [UriLoader GetHtmlDataAboutUTF8Encorded:targetUrl cookieStorage:cookieStorage out_charSetString:&charSetString out_charsetValue:&charsetValue];
            if (data == nil) {
                break;
            }
            
            xmlDocPtr document = htmlReadMemory([data bytes], (int)[data length], [[targetUrl absoluteString] cStringUsingEncoding:NSUTF8StringEncoding], [[charSetString lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding], HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR);
            if (document == NULL) {
                NSLog(@"xmlParseMemory() failed: %@\n%@", [targetUrl absoluteString], [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
                break;
            }
            xmlXPathContextPtr context;
            context = xmlXPathNewContext(document);
            if (context == NULL) {
                xmlFreeDoc(document);
                NSLog(@"xmlXPathNewContext() failed: %@", [targetUrl absoluteString]);
                break;
            }

            NSURL* nextUrl = nil;
            HtmlStory* story = [HtmlStory new];
            NSArray* siteInfoArray = [self searchSiteInfoForURL:targetUrl];
            for (SiteInfo* siteInfo in siteInfoArray) {
                NSString* pageHtml = [siteInfo GetPageElement:document context:context documentEncoding:charsetValue];
                if (pageHtml == nil || [pageHtml length] <= 0) {
                    continue;
                }
                NSString* removeRubyString = [SiteInfo RemoveRubyTag:pageHtml];
                NSString* replaceLonlyTagString = [SiteInfo ReplaceXhtmlLonlyTag:removeRubyString];
                NSString* tmpString = [replaceLonlyTagString stringByReplacingOccurrencesOfString:@"&#13;" withString:@""];
                if (tmpString == nil || [tmpString length] <= 0) {
                    continue;
                }
                NSAttributedString* textAttributedString = [SiteInfo HtmlStringToAttributedString:tmpString];
                story.content = textAttributedString.string;
                nextUrl = [siteInfo GetNextURL:document context:context currentURL:targetUrl documentEncoding:charsetValue];
                
                NSLog(@"decode success: next: %@, siteInfo: %@", [nextUrl absoluteString], [siteInfo GetDescription]);
                break;
            }
            story.title = [UriLoader GetHtmlTitle:document context:context documentEncoding:charsetValue];
            xmlXPathFreeContext(context);
            xmlFreeDoc(document);

            if (story.content == nil || [story.content length] <= 0) {
                continue;
            }

            story.count = count++;
            story.url = [targetUrl absoluteString];
            success = true;
            if (successAction != nil) {
                successAction(story, targetUrl);
            }
            
            if (nextUrl == nil) {
                break;
            }
            NSLog(@"next url: %@", [nextUrl absoluteString]);
            targetUrl = nextUrl;
            [NSThread sleepForTimeInterval:m_SleepTime];
        }
        
        if (!success && failedAction != nil) {
            failedAction(url);
        }else{
            if (finishAction != nil) {
                finishAction(url);
            }
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
