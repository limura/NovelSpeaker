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
}

- (id)initWithParams:(NSString*)urlPattern nextLink:(NSString*)nextLink pageElement:(NSString*)pageElement;

/// 指定された url がこの SiteInfo の示すURLであるか否かを判定します
- (BOOL)isTargetUrl:(NSURL*)url;

/// NextLink に当たるものを取り出します
- (NSURL*)GetNextURL:(xmlDocPtr)document context:(xmlXPathContextPtr)context currentURL:(NSURL*)currentURL;

/// PageElementに当たるものを NSString に変換した物を取り出します。
- (NSString*)GetPageElement:(xmlDocPtr)document context:(xmlXPathContextPtr)context;

@end
