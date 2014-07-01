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

/// 小説になろうの時間フォーマットからNSDateに変換します
- (NSDate*)ConvertNarouDate2NSDate: (NSString*)narouDate
{
    NSDateFormatter* formatter = [NSDateFormatter new];
    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
    return [formatter dateFromString:narouDate];
}

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
        if (ncode == nil || [ncode length] <= 0) {
            // 何も入っていないようなので無視します。(たぶんallcountって奴しか入ってない部分だと思う)
            continue;
        }
        NarouContent* content = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:ncode];
        
        if (content == nil) {
            NSLog(@"ncode: %@ %@ not found. adding.", ncode, [jsonContent objectForKey:@"title"]);
            content = [[GlobalDataSingleton GetInstance] CreateNewNarouContent];
        }

        content.title = [jsonContent objectForKey:@"title"];
        content.ncode = ncode;
        content.userid = [jsonContent objectForKey:@"userid"];
        content.story = [jsonContent objectForKey:@"story"];
        content.writer = [jsonContent objectForKey:@"writer"];

        // 小説の更新時間を取り出します。
        NSString* novelupdated_at_string = [jsonContent objectForKey:@"novelupdated_at"];
        content.novelupdated_at = [self ConvertNarouDate2NSDate:novelupdated_at_string];
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
