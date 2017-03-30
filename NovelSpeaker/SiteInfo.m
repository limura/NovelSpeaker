//
//  SiteInfo.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/08.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "SiteInfo.h"




@implementation SiteInfo
- (id)initWithParams:(NSString*)urlPattern nextLink:(NSString*)nextLink pageElement:(NSString*)pageElement {
    self = [super init];
    if (self == nil) {
        return self;
    }
    NSError* error;
    m_UrlPattern = [NSRegularExpression regularExpressionWithPattern:urlPattern options:0 error:&error];
    if (m_UrlPattern == nil) {
        return nil;
    }
    m_NextLink = nextLink;
    m_PageElement = pageElement;
    
    return self;
}

/// 指定された url がこの SiteInfo の示すURLであるか否かを判定します
- (BOOL)isTargetUrl:(NSURL*)url{
    NSString* urlString = [url absoluteString];
    if([m_UrlPattern numberOfMatchesInString:urlString options:0 range:NSMakeRange(0, urlString.length)] > 0){
        return true;
    }
    return false;
}

/// NextLink に当たるものを取り出します
- (NSURL*)GetNextURL:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL documentEncoding:(unsigned long)documentEncoding {
    xmlChar* xpath = (xmlChar*)[m_NextLink cStringUsingEncoding:NSUTF8StringEncoding];
    xmlXPathObjectPtr result = xmlXPathEvalExpression(xpath, context);
    if (result == NULL || result->nodesetval == NULL) {
        return nil;
    }
    xmlNodeSetPtr nodeSet = result->nodesetval;
    for (int i = 0; i < nodeSet->nodeNr; i++) {
        xmlNodePtr node = nodeSet->nodeTab[i];
        if (node == NULL) {
            continue;
        }
        xmlChar* href = xmlGetProp(node, (const xmlChar*)"href");
        if (href == NULL) {
            continue;
        }
        NSString* hrefString = [NSString stringWithCString:(const char*)href encoding:documentEncoding];
        xmlFree(href);
        return [NSURL URLWithString:hrefString relativeToURL:currentURL];
    }
    return nil;
}

/// HTML の文字列のHTMLタグをそれらしく処理して NSAttributedString に変換します
/// 実際の所は NSAttributedString にそういうことをしてくれるイニシャライザがあるのでそれを使います。
/// ただ、それは main thread からしか呼び出せないイニシャライザなので、main thread 側に処理を投げる処理が入ります。
/// そのため、この関数を呼ぶ奴は dispatch_sync(dispatch_get_main_queue(), ... をしているとブロックするかもしれないです。(´・ω・`)
+ (NSAttributedString* _Nonnull)HtmlStringToAttributedString:(NSString*)htmlString {
    // NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType を使う場合は main thread でないと駄目だそうな。
    __block NSAttributedString* attributedString = nil;
    if ([NSThread isMainThread]) {
        attributedString = [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUTF8StringEncoding] options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,                                                                                                                 NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)} documentAttributes:nil error:nil];
    }else{
        //dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        dispatch_queue_t queue = dispatch_get_main_queue();
        dispatch_sync(queue, ^(){
            attributedString = [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUTF8StringEncoding] options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,                                                                                                                 NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)} documentAttributes:nil error:nil];
            //dispatch_semaphore_signal(semaphore);
        });
        //dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    
    if (attributedString == nil) {
        attributedString = [NSAttributedString new];
    }

    return attributedString;
}

/// HTMLの <ruby> 関係のタグを排除します
+ (NSString*)RemoveRubyTag:(NSString*)html {
    NSString* result = html;
    //<ruby><rb>黒河</rb><rp>（</rp><rt>くろかわ</rt><rp>）</rp></ruby>
    NSArray* targetArray = @[@"<ruby>", @"</ruby>", @"<rb>", @"</rb>", @"<rp>", @"</rp>", @"<rt>", @"</rt>"];
    for (NSString* target in targetArray) {
        result = [result stringByReplacingOccurrencesOfString:target withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
    }
    return result;
}

/// HTMLタグを全部消します
+ (NSString*)RemoveHtmlTag:(NSString*)html {
    NSString* htmlTags = @"<[^>]*>";
    NSRange range;
    while ((range = [html rangeOfString:htmlTags options:NSRegularExpressionSearch]).location != NSNotFound) {
        html = [html stringByReplacingCharactersInRange:range withString:@""];
    }
    return html;
}

/// XHTML の <br /> のようなタグ(単品で終わるタグ) を <br> のようなタグに変更します
+ (NSString*)ReplaceXhtmlLonlyTag:(NSString*)html {
    NSString* lonlyTag = @"/>";
    NSRange range;
    while ((range = [html rangeOfString:lonlyTag options:NSRegularExpressionSearch]).location != NSNotFound) {
        html = [html stringByReplacingCharactersInRange:range withString:@">"];
    }
    return html;
}

/// PageElementに当たるもののリストを取り出します。
- (NSString*)GetPageElement:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    xmlChar* xpath = (xmlChar*)[m_PageElement cStringUsingEncoding:NSUTF8StringEncoding];
    xmlXPathObjectPtr result = xmlXPathEvalExpression(xpath, context);
    if (result == NULL || result->nodesetval == NULL) {
        return nil;
    }
    NSLog(@"xmlXPathEvalExpression: result: %p->nodesetval(%p)->nodeNr(%d)", result, result->nodesetval, result->nodesetval->nodeNr);
    xmlNodeSetPtr nodeSet = result->nodesetval;
    NSMutableString* htmlString = [NSMutableString new];
    for (int i = 0; i < nodeSet->nodeNr; i++) {
        xmlNodePtr node = nodeSet->nodeTab[i];
        if (node == NULL) {
            continue;
        }
        xmlBufferPtr buffer = xmlBufferCreate();
        int result = xmlNodeDump(buffer, node->doc, node, 0, 1);
        NSLog(@"  node[%d] xmlNodeDump: %d", i, result);
        if (result > 0) {
            const xmlChar* bufCharArray = xmlBufferContent(buffer);
            if (bufCharArray != NULL) {
                //NSString* docString = [NSString stringWithCString:(const char*)bufCharArray encoding:documentEncoding];
                NSString* docString = [[NSString alloc] initWithData:[[NSData alloc] initWithBytes:(char*)bufCharArray length:buffer->use] encoding:documentEncoding];
                NSLog(@"docString: %p(%lu) length: %u", docString, documentEncoding, buffer->use);
                if (docString == nil) {
                    continue;
                }
                [htmlString appendString:docString];
                [htmlString appendString:@"<br><br>"];
            }
        }
        xmlBufferFree(buffer);
    }
    xmlXPathFreeObject(result);
    return htmlString;
}

/// 概要を文字列で返します
- (NSString*)GetDescription {
    return [[NSString alloc] initWithFormat:@"nextLink: %@, pageElement: %@", m_NextLink, m_PageElement];
}




@end
