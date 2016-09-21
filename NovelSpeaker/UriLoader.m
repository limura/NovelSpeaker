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
- (BOOL)AddSiteInfoFromJsonArray:(NSArray *)siteInfoJsonArray {
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
        [m_SiteInfoArray addObject:siteInfo];
    }
    return true;
}

/// SiteInfo のJSONを内部データベースに追加します。
- (BOOL)AddSiteInfoFromData:(NSData*)siteInfo{
    NSError* error = nil;
    NSArray* jsonArray = [NSJSONSerialization JSONObjectWithData:siteInfo options:NSJSONReadingAllowFragments error:&error];
    if (jsonArray == nil || error != nil) {
        return false;
    }
    return [self AddSiteInfoFromJsonArray:jsonArray];
}

/// SiteInfo のJSON文字列を内部データベースに追加します。
- (BOOL)AddSiteInfoFromString:(NSString*)siteInfo{
    return [self AddSiteInfoFromData:[siteInfo dataUsingEncoding:NSUTF8StringEncoding]];
}

/// SiteInfo をURLから内部データベースに追加します。
- (void)AddSiteInfoFromURL:(NSURL*)url successAction:(void(^)())successAction failedAction:(void(^)(NSURL* url))failedAction{
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

- (SiteInfo*)searchSiteInfoForURL:(NSURL*)url {
    for (SiteInfo* siteInfo in m_SiteInfoArray) {
        if ([siteInfo isTargetUrl:url]) {
            return siteInfo;
        }
    }
    return nil;
}

- (NSString*)GetContentCharSet:(NSHTTPURLResponse*)httpResponse {
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
        NSLog(@"charset unknwon: %@", contentType);
        return nil;
    }
    if (result.numberOfRanges <= 0) {
        NSLog(@"charset unknown numberOfRanges <= 0: %@", contentType);
        return nil;
    }
    NSRange range = [result rangeAtIndex:1];
    return [contentType substringWithRange:range];
}

/// URLを読み込んで、SiteInfo の情報から得た PageElement の情報を NSString に変換して取り出しつつ、
/// MaxDepth まで nextLink を辿ったものを、PageElement毎の配列として取り出します。
/// 該当する siteinfo が無い場合、a rel="next" であったり class="autopagerize_page_element" であるものを取り出そうとします。
- (void)LoadURL:(NSURL*)url successAction:(void(^)(NSArray* result))successAction failedAction:(void(^)(NSURL* url))failedAction{
    SiteInfo* defaultSiteInfo = [[SiteInfo alloc] initWithParams:@".*" nextLink:@"//a[@rel=\"next\"]" pageElement:@"//*[@class=\"autopagerize_page_element\"]"];
    
    dispatch_async(m_WebAccessQueue, ^(){
        NSURL* targetUrl = url;
        NSMutableArray* pageArray = [NSMutableArray new];
        for (int i = 0; i < m_MaxDepth; i++) {
            NSURLRequest* request = [NSURLRequest requestWithURL:targetUrl];
            NSError* error;
            NSURLResponse* response;
            NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            if (data == nil) {
                if (failedAction != nil) {
                    failedAction(url);
                    break;
                }
            }
            NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
            if ((int)(httpResponse.statusCode / 100) != 2) {
                NSLog(@"HTTP status code is not 2?? (%ld) url: %@", (long)httpResponse.statusCode, [url absoluteString]);
                break;
            }
            
            NSString* encodingString = [[self GetContentCharSet:httpResponse] lowercaseString];
            NSLog(@"encoding: %@", encodingString);
            const char* encoding = encodingString ? [encodingString cStringUsingEncoding:NSUTF8StringEncoding] : "utf-8";
            xmlDocPtr document = htmlReadMemory([data bytes], (int)[data length], "", encoding, HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR);
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
            SiteInfo* siteInfo = [self searchSiteInfoForURL:targetUrl];
            if (siteInfo == nil) {
                NSLog(@"target SiteInfo is default.");
                siteInfo = defaultSiteInfo;
            }
            
            NSString* pageString = [siteInfo GetPageElement:document context:context];
            if (pageString != nil) {
                [pageArray addObject:pageString];
            }
            
            NSURL* nextUrl = [siteInfo GetNextURL:document context:context currentURL:targetUrl];
            xmlXPathFreeContext(context);
            xmlFreeDoc(document);
            
            if (nextUrl == nil) {
                break;
            }
            NSLog(@"next url: %@", [nextUrl absoluteString]);
            targetUrl = nextUrl;
            [NSThread sleepForTimeInterval:m_SleepTime];
        }
        if (successAction != nil) {
            successAction(pageArray);
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
