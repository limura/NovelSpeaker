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

/// 小説家になろう の API 個を使って小説情報を読み出すclass。
/// SettingDataModel の NarouContent に追加するなどします。
@implementation NarouLoader

/// NarouContent のリストを更新します。
/// 怪しく検索条件を内部で勝手に作ります。
- (BOOL)UpdateContentList
{
    NSString* queryUrl = [[NSString alloc] initWithFormat:@"http://api.syosetu.com/novelapi/api/?out=json&of=t-n-u-w-s-k-e-ga-gp-f-r-a-ah-sa-nu&lim=10", nil];
    NSData* jsonData = [self HttpGetBinary:queryUrl];
    NSError* err = nil;
    
    // TODO: これ NSArray と NSDictionary のどっちが帰ってくるのが正しいのだろ。
    NSArray* contentList = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingAllowFragments error:&err];
    for(NSDictionary* jsonContent in contentList)
    {
        NSString* ncode = [jsonContent objectForKey:@"ncode"];
        NarouContent* content = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:ncode];
        
        if (content == nil) {
            content = [[GlobalDataSingleton GetInstance] CreateNewNarouContent];
        }

        content.title = [jsonContent objectForKey:@"title"];
        content.ncode = ncode;
        content.userid = [jsonContent objectForKey:@"userid"];
        content.story = [jsonContent objectForKey:@"story"];
        content.writer = [jsonContent objectForKey:@"writer"];
        //NSString* novelupdated_at_string = [jsonContent objectForKey:@"novelupdated_at"];
    }
    return true;
}

/// HTTP GET request for binary
- (NSData*)HttpGetBinary:(NSString*)url {
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    return [NSURLConnection sendSynchronousRequest:request returningResponse: nil error:nil];
}
/// HTTP GET request
- (NSString*)HttpGet:(NSString*)url {
    NSData* data = [self HttpGetBinary:url];
    NSString* str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str;
}

@end
