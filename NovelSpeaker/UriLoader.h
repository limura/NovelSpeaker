//
//  UriLoader.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/08.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

/// URI からコンテンツ文字列を抽出します。
@interface UriLoader : NSObject
{
    dispatch_queue_t m_WebAccessQueue;
    int m_MaxDepth;
    float m_SleepTime;
    NSMutableArray* m_SiteInfoArray;
}

/// SiteInfo のJSON文字列を内部データベースに追加します。
- (BOOL)AddSiteInfoFromString:(NSString*)siteInfo;

/// SiteInfo をURLから内部データベースに追加します。
- (void)AddSiteInfoFromURL:(NSURL*)url successAction:(void(^)())successAction failedAction:(void(^)(NSURL* url))failedAction;

/// URLを読み込んで、SiteInfo の情報から得た PageElement の情報を NSString に変換して取り出しつつ、
/// MaxDepth まで nextLink を辿ったものを、PageElement毎の配列として取り出します。
/// 該当する siteinfo が無い場合、a rel="next" であったり class="autopagerize_page_element" であるものを取り出そうとします。
- (void)LoadURL:(NSURL*)url successAction:(void(^)(NSArray* result))successAction failedAction:(void(^)(NSURL* url))failedAction;

/// 最大何ページまで読み進むかを指定します
- (void)SetMaxDepth:(int)maxDepth;

/// 1ページ読み込み毎に待つ時間を秒で指定します
- (void)SetSleepTimeInSecond:(float)sleepTime;

@end
