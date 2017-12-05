//
//  SiteInfo.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/08.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <libxml/parser.h>
#import <libxml/HTMLparser.h>
#import <libxml/xpath.h>

@interface SiteInfo : NSObject
{
    NSRegularExpression* m_UrlPattern;
    NSString* m_NextLink;
    NSString* m_PageElement;
    NSString* m_Title;
    NSString* m_Author;
    NSString* m_FirstPageLink;
}

- (id)initWithParams:(NSString*)urlPattern nextLink:(NSString*)nextLink pageElement:(NSString*)pageElement title:(NSString*)title author:(NSString*)author firstPageLink:(NSString*)firstPageLink;

/// 指定された url がこの SiteInfo の示すURLであるか否かを判定します
- (BOOL)isTargetUrl:(NSURL*)url;

/// NextLink に当たるものを取り出します
- (NSURL*)GetNextURL:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL documentEncoding:(unsigned long)documentEncoding;
/// firstPageLink に当たるものを取り出します
- (NSURL*)GetFirstPageURL:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL documentEncoding:(unsigned long)documentEncoding;

/// タイトルを抽出します
- (NSString*)GetTitle:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding;
/// 著者を抽出します
- (NSString*)GetAuthor:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding;

/// PageElementに当たる HTML を、NSString の形式で取り出します。
/// HTML から単純な String にするには、HtmlStringToAttributedString 等のユーティリティを用いてください。
- (NSString*)GetPageElement:(xmlDocPtr)document context:(xmlXPathContextPtr)context documentEncoding:(unsigned long)documentEncoding;

/// HTML の文字列のHTMLタグをそれらしく処理して NSAttributedString に変換します
/// 実際の所は NSAttributedString にそういうことをしてくれるイニシャライザがあるのでそれを使います。
/// ただ、それは main thread からしか呼び出せないイニシャライザなので、main thread 側に処理を投げる処理が入ります。
/// そのため、この関数を呼ぶ奴は dispatch_sync(dispatch_get_main_queue(), ... をしているとブロックするかもしれないです。(´・ω・`)
+ (NSAttributedString*)HtmlStringToAttributedString:(NSString*)htmlString;

/// HTMLの <ruby> 関係のタグを排除します
+ (NSString*)RemoveRubyTag:(NSString*)html;

/// HTMLタグを全部消します
+ (NSString*)RemoveHtmlTag:(NSString*)html;

/// XHTML の <br /> のようなタグ(単品で終わるタグ) を <br> のようなタグに変更します
+ (NSString*)ReplaceXhtmlLonlyTag:(NSString*)html;

/// 概要を文字列で返します
- (NSString*)GetDescription;

@end
