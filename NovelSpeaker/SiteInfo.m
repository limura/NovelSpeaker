//
//  SiteInfo.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/08.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "SiteInfo.h"
#import "NovelSpeaker-Swift.h"

@implementation SiteInfo
- (id)initWithParams:(NSString*)urlPattern nextLink:(NSString*)nextLink pageElement:(NSString*)pageElement title:(NSString*)title author:(NSString *)author firstPageLink:(NSString *)firstPageLink tag:(NSString*)tag subtitle:(NSString*)subtitle {
    self = [super init];
    if (self == nil) {
        NSLog(@"super init return nil");
        return self;
    }
    NSError* error;
    m_UrlPattern = [NSRegularExpression regularExpressionWithPattern:urlPattern options:0 error:&error];
    if (m_UrlPattern == nil) {
        //NSLog(@"SiteInfo initWithParams: regex failed: %@", urlPattern);
        return nil;
    }
    m_PageElement = pageElement;
    m_NextLink = nextLink == nil ? @"" : nextLink;
    m_Title = title == nil ? @"//title" : title;
    m_Author = author == nil ? @"" : author;
    m_FirstPageLink = firstPageLink == nil ? @"" : firstPageLink;
    m_Tag = tag == nil ? @"" : tag;
    m_Subtitle = subtitle == nil ? @"" : subtitle;
    
    return self;
}

/// 指定された url がこの SiteInfo の示すURLであるか否かを判定します
- (BOOL)isTargetUrl:(NSURL*)url{
    @autoreleasepool {
        NSString* urlString = [url absoluteString];
        if([m_UrlPattern numberOfMatchesInString:urlString options:0 range:NSMakeRange(0, urlString.length)] > 0){
            return true;
        }
        return false;
    }
}

- (NSURL*)GetURLFromXpath:(NSString*)xpathString document:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL documentEncoding:(unsigned long)documentEncoding {
    if (xpathString == nil || [xpathString length] <= 0) {
        return nil;
    }
    xmlChar* xpath = (xmlChar*)[xpathString cStringUsingEncoding:NSUTF8StringEncoding];
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

/// NextLink に当たるものを取り出します
- (NSURL*)GetNextURL:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL documentEncoding:(unsigned long)documentEncoding {
    return [self GetURLFromXpath:m_NextLink document:document context:context currentURL:currentURL documentEncoding:documentEncoding];
}

/// firstPageLink に当たるものを取り出します
- (NSURL*)GetFirstPageURL:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL documentEncoding:(unsigned long)documentEncoding {
    return [self GetURLFromXpath:m_FirstPageLink document:document context:context currentURL:currentURL documentEncoding:documentEncoding];
}

/// タイトルを抽出します
- (NSString*)GetTitle:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    NSString* titleString = [self ExecuteXpathToString:m_Title document:document context:context documentEncoding:documentEncoding];
    if (titleString == nil) {
        return nil;
    }
    titleString = [SiteInfo RemoveHtmlTag:titleString];
    titleString = [SiteInfo RemoveHtmlCharacterRefernce:titleString];
    titleString = [titleString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return titleString;
}

/// 著者を抽出します
- (NSString*)GetAuthor:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    NSString* authorString = [self ExecuteXpathToString:m_Author document:document context:context documentEncoding:documentEncoding];
    if (authorString == nil) {
        return nil;
    }
    return [[NSString alloc] initWithFormat:@"%@", [SiteInfo RemoveHtmlTag:authorString]];
}

/// サブタイトルを抽出します
- (NSString*)GetSubtitle:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    NSString* subtitleString = [self ExecuteXpathToString:m_Subtitle document:document context:context documentEncoding:documentEncoding];
    if (subtitleString == nil) {
        return nil;
    }
    return [[NSString alloc] initWithFormat:@"%@", [SiteInfo RemoveHtmlTag:subtitleString]];
}

/// タグのリストを抽出します
/// 注意：
/// タグはリストに分かれている場合、タグ毎にNSArrayの1要素になっているはずです
/// NSArray の中身は NSString* ですが、HTMLを含む文字列なので、HtmlStringToAttributedString を呼ぶ必要があるかもしれません。
- (NSArray*)GetTagArray:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    NSArray* tagArray = [self ExecuteXpathToStringArray:m_Tag document:document context:context documentEncoding:documentEncoding];
    NSMutableArray* resultArray = [NSMutableArray new];
    for (NSString* tag in tagArray) {
        NSString* cleanTag = [[[SiteInfo HtmlStringToAttributedString:tag] string] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [resultArray addObjectsFromArray:[cleanTag componentsSeparatedByString:@" "]];
    }
    return resultArray;
}

/// HTML文字列の中の表示にはいらなそうなタグの部分をまるっと削除して返します。
/// どうして必要だったのか：
/// iframe 等で別URLの読み込み元等があると NSAttributedString で NSHTMLTextDocumentType を読み込もうとしていた時に
/// その別URLの読み込みが発生し、場合によってはそれが失敗するなどで NSAttributedString 自体が サイズ 0 の残念な結果になることがあります。
/// それが起こる可能性のあるHTMLタグについて、全部まるっと削除するというものです。
+ (NSString*)RemoveHtmlNoStringTag:(NSString *)htmlString {
    NSMutableString* result = htmlString.mutableCopy;
    NSArray* targetRegexStrings = @[
        //@"<script.*?/script>",
        @"<iframe.*?>",
        @"<link.*?>",
        @"<meta.*?>",
        //@"<img[^>]*?>", // img は将来的に ALT を表示できたらいいのかもしれないなぁと思ったりもする……
    ];
    for (NSString* regexString in targetRegexStrings) {
        @autoreleasepool {
            NSError* error = nil;
            NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:regexString options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators) error:&error];
            if (regex == nil) {
                NSLog(@"regex error: %@, %@", regexString, error);
            }
            if (regex != nil) {
                [regex replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:@""];
            }
        }
    }
    return result;
}

/// HTML の文字列のHTMLタグをそれらしく処理して NSAttributedString に変換します
/// 実際の所は NSAttributedString にそういうことをしてくれるイニシャライザがあるのでそれを使います。
/// ただ、それは main thread からしか呼び出せないイニシャライザなので、main thread 側に処理を投げる処理が入ります。
/// そのため、この関数を呼ぶ奴は dispatch_sync(dispatch_get_main_queue(), ... をしているとブロックするかもしれないです。(´・ω・`)
+ (NSAttributedString* _Nonnull)HtmlStringToAttributedString:(NSString*)htmlString {
    // iframe 等の外部URLを読み込んでいるものを事前に排除します。
    // それらの中に外部URLが書いてあったりするとネットワークアクセスが発生したり、アクセスが失敗して結果サイズ0の文字列が生成されることがあるようです
    htmlString = [SiteInfo RemoveHtmlNoStringTag:htmlString];
    // NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType を使う場合は main thread でないと駄目だそうな。
    __block NSAttributedString* attributedString = nil;
    if ([NSThread isMainThread]) {
        NSError* error = nil;
        attributedString = [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUTF8StringEncoding] options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,                                                                                                                 NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)} documentAttributes:nil error:&error];
        if (error != nil) {
            NSLog(@"html to string failed(in main thread): %@", [error localizedDescription]);
        }
    }else{
        //dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        [NiftyUtilitySwift DispatchSyncMainQueueWithBlock:^{
            NSError* error = nil;
            attributedString = [[NSAttributedString alloc] initWithData:[htmlString dataUsingEncoding:NSUTF8StringEncoding] options:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,                                                                                                                 NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)} documentAttributes:nil error:&error];
            if (error != nil) {
                NSLog(@"html to string failed(in other thread): %@", [error localizedDescription]);
            }
            //dispatch_semaphore_signal(semaphore);
        }];
        //dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    
    if (attributedString == nil) {
        attributedString = [NSAttributedString new];
    }

    return attributedString;
}

/// 怪しく <ruby>xxx<rp>(</rp><rt>yyy</rt><rp>)</rt></ruby> や、<ruby>xxx<rt>yyy</rt></ruby> という文字列を
/// <ruby>|xxx<rp>(</rp><rt>yyy</rt><rp>)</rt></ruby> という文字列に変換します。
/// つまり、xxx(yyy) となるはずのものを、|xxx(yyy) となるように変換するわけです。
+ (NSString*)AddDummyRubyRpVerticalBar:(NSString*)htmlString {
    @autoreleasepool {
        NSString* convFrom = @"<ruby>(<rb>)?([^<]+)\\s*(</rb>)?\\s*(<rp>[^<]*</rp>)?\\s*(<rt>[^<]+</rt>)\\s*(<rp>[^<]*</rp>)?</ruby>";
        NSString* convTo = @"<ruby>|$1$2$3<rp>(</rp>$5<rp>)</rp></ruby>";
        NSRegularExpression* regexp = [NSRegularExpression regularExpressionWithPattern:convFrom options:NSRegularExpressionCaseInsensitive error:nil];
        
        return [regexp stringByReplacingMatchesInString:htmlString options:0 range:NSMakeRange(0, htmlString.length) withTemplate:convTo];
    }
}

/// HTMLの <ruby> 関係のタグを排除します
/// 怪しく <ruby>xxx<rp>(</rp><rt>yyy</rt><rp>)</rt></ruby> という文字列を
/// <ruby>|xxx<rp>(</rp><rt>yyy</rt><rp>)</rt></ruby> という文字列に変換してからそれら ruby 周りのHTMLタグを削除します。
/// つまり、xxx(yyy) となるはずのものを、|xxx(yyy) となるように変換してから ruby 周りのHTMLタグを削除します。
+ (NSString*)RemoveRubyTag:(NSString*)html {
    NSString* result = [SiteInfo AddDummyRubyRpVerticalBar:html];
    //<ruby><rb>黒河</rb><rp>（</rp><rt>くろかわ</rt><rp>）</rp></ruby>
    NSArray* targetArray = @[@"<ruby>", @"</ruby>", @"<rb>", @"</rb>", @"<rp>", @"</rp>", @"<rt>", @"</rt>"];
    for (NSString* target in targetArray) {
        result = [result stringByReplacingOccurrencesOfString:target withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, [result length])];
    }
    return result;
}

/// HTMLタグを全部消します
+ (NSString*)RemoveHtmlTag:(NSString*)html {
    if (html == nil) {
        return nil;
    }
    NSString* htmlTags = @"<[^>]*>";
    NSRange range;
    while (html != nil && (range = [html rangeOfString:htmlTags options:NSRegularExpressionSearch]).location != NSNotFound) {
        html = [html stringByReplacingCharactersInRange:range withString:@""];
    }
    return html;
}

+ (NSString*)RemoveHtmlCharacterRefernce:(NSString*)html {
    if (html == nil) {
        return nil;
    }
    NSString* characterReference = @"&#[0-9a-fA-F]{1,2};";
    NSRange range;
    while (html != nil && (range = [html rangeOfString:characterReference options:NSRegularExpressionSearch]).location != NSNotFound) {
        html = [html stringByReplacingCharactersInRange:range withString:@""];
    }
    return html;
}

/// XHTML の <br /> のようなタグ(単品で終わるタグ) を <br> のようなタグに変更します
+ (NSString*)ReplaceXhtmlLonlyTag:(NSString*)html {
    NSString* lonlyTag = @"/>";
    NSRange range;
    while (html != nil && (range = [html rangeOfString:lonlyTag options:NSRegularExpressionSearch]).location != NSNotFound) {
        html = [html stringByReplacingCharactersInRange:range withString:@">"];
    }
    return html;
}

- (NSArray*)ExecuteXpathToStringArray:(NSString*)xpathString document:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    xmlChar* xpath = (xmlChar*)[xpathString cStringUsingEncoding:NSUTF8StringEncoding];
    xmlXPathObjectPtr result = xmlXPathEvalExpression(xpath, context);
    if (result == NULL || result->nodesetval == NULL) {
        return nil;
    }
    //NSLog(@"xmlXPathEvalExpression: result: %p->nodesetval(%p)->nodeNr(%d)", result, result->nodesetval, result->nodesetval->nodeNr);
    xmlNodeSetPtr nodeSet = result->nodesetval;
    NSMutableArray* stringArray = [NSMutableArray new];
    for (int i = 0; i < nodeSet->nodeNr; i++) {
        xmlNodePtr node = nodeSet->nodeTab[i];
        if (node == NULL) {
            continue;
        }
        xmlBufferPtr buffer = xmlBufferCreate();
        int result = xmlNodeDump(buffer, node->doc, node, 0, 1);
        //NSLog(@"  node[%d] xmlNodeDump: %d", i, result);
        if (result > 0) {
            const xmlChar* bufCharArray = xmlBufferContent(buffer);
            if (bufCharArray != NULL) {
                //NSString* docString = [NSString stringWithCString:(const char*)bufCharArray encoding:documentEncoding];
                NSString* docString = [[NSString alloc] initWithData:[[NSData alloc] initWithBytes:(char*)bufCharArray length:buffer->use] encoding:documentEncoding];
                //NSLog(@"docString: %p(%lu) length: %u", docString, documentEncoding, buffer->use);
                if (docString == nil) {
                    continue;
                }
                [stringArray addObject:docString];
            }
        }
        xmlBufferFree(buffer);
    }
    xmlXPathFreeObject(result);
    return stringArray;
}

- (NSString*)ExecuteXpathToString:(NSString*)xpathString document:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    NSArray* stringArray = [self ExecuteXpathToStringArray:xpathString document:document context:context documentEncoding:documentEncoding];
    if (stringArray == nil) {
        return nil;
    }
    NSMutableString* htmlString = [NSMutableString new];
    for (NSString* str in stringArray) {
        [htmlString appendString:str];
        [htmlString appendString:@"<br><br>"];
    }
    return htmlString;
}

/// PageElementに当たるもののリストを取り出します。
- (NSString*)GetPageElement:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding {
    return [self ExecuteXpathToString:m_PageElement document:document context:context documentEncoding:documentEncoding];
}

/// 概要を文字列で返します
- (NSString*)GetDescription {
    return [[NSString alloc] initWithFormat:@"SiteInfo\n  nextLink: %@,\n  pageElement: %@,\n  title: %@,\n  author: %@,\n  firstPageLink: %@,\n  urlPattern: %@", m_NextLink, m_PageElement, m_Title, m_Author, m_FirstPageLink, [m_UrlPattern pattern]];
}

/// SiteInfo の sort用のヒント(UrlPattern の文字数)を返します
- (NSUInteger)GetSortHint{
    return [[m_UrlPattern pattern] length];
}


@end
