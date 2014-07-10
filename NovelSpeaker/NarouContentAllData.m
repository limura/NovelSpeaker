//
//  NarouContentAllData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/03.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouContentAllData.h"

@implementation NarouContentAllData

/// 小説になろうの時間フォーマットからNSDateに変換します
- (NSDate*)ConvertNarouDate2NSDate: (NSString*)narouDate
{
    NSDateFormatter* formatter = [NSDateFormatter new];
    [formatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
    return [formatter dateFromString:narouDate];
}

// 文字列を受け取って NSNumber に変換します。
// nil など変換できなかった場合は 0 を返します。
- (NSNumber*)String2Number: (NSString*) str
{
    if (str == nil || [str isEqual:[NSNull null]]) {
        return [[NSNumber alloc] initWithInt:0];
    }
    return [[NSNumber alloc] initWithInt:[str intValue]];
}

/// 辞書を用いて初期化します。
- (id)initWithJsonData: (NSDictionary*)jsonContent
{
    self = [super init];

    self.title = [jsonContent objectForKey:@"title"];
    self.ncode = [jsonContent objectForKey:@"ncode"];
    self.userid = [jsonContent objectForKey:@"userid"];
    self.writer = [jsonContent objectForKey:@"writer"];
    self.story = [jsonContent objectForKey:@"story"];
    self.genre = [self String2Number:[jsonContent objectForKey:@"genre"]];
    self.keyword = [jsonContent objectForKey:@"keyword"];
    self.general_all_no = [self String2Number:[jsonContent objectForKey:@"general_all_no"]];
    self.fav_novel_cnt = [self String2Number:[jsonContent objectForKey:@"fav_novel_cnt"]];
    self.review_cnt = [self String2Number:[jsonContent objectForKey:@"review_cnt"]];
    self.all_point = [self String2Number:[jsonContent objectForKey:@"all_point"]];
    self.all_hyoka_cnt = [self String2Number:[jsonContent objectForKey:@"all_hyoka_cnt"]];
    self.end = [self String2Number:[jsonContent objectForKey:@"end"]];
    self.global_point = [self String2Number:[jsonContent objectForKey:@"global_point"]];
    // 小説の更新時間を取り出します。
    NSString* novelupdated_at_string = [jsonContent objectForKey:@"novelupdated_at"];
    self.novelupdated_at = [self ConvertNarouDate2NSDate:novelupdated_at_string];
    
    self.current_download_complete_count = 0;
    self.reading_chapter = [[NSNumber alloc] initWithInt:1];

    return self;
}

// CoreData側の値を使って初期化します。
- (id)initWithCoreData: (NarouContent*)coreDatacontent
{
    self = [super init];
    
    self.title = coreDatacontent.title;
    self.ncode = coreDatacontent.ncode;
    self.userid = coreDatacontent.userid;
    self.writer = coreDatacontent.writer;
    self.story = coreDatacontent.story;
    self.genre = coreDatacontent.genre;
    self.keyword = coreDatacontent.keyword;
    self.general_all_no = coreDatacontent.general_all_no;
    self.end = coreDatacontent.end;
    self.global_point = coreDatacontent.global_point;
    self.fav_novel_cnt = coreDatacontent.fav_novel_cnt;
    self.review_cnt = coreDatacontent.review_cnt;
    self.all_point = coreDatacontent.all_point;
    self.all_hyoka_cnt = coreDatacontent.all_hyoka_cnt;
    self.sasie_cnt = coreDatacontent.sasie_cnt;
    self.novelupdated_at = coreDatacontent.novelupdated_at;
    self.reading_chapter = coreDatacontent.reading_chapter;
    
    self.current_download_complete_count = 0;
    
    return self;
}

/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToNarouContent: (NarouContent*)content
{
    content.title = self.title;
    content.ncode = self.ncode;
    content.userid = self.userid;
    content.writer = self.writer;
    content.story = self.story;
    content.genre = self.genre;
    content.keyword = self.keyword;
    content.general_all_no = self.general_all_no;
    content.end = self.end;
    content.global_point = self.global_point;
    content.fav_novel_cnt = self.fav_novel_cnt;
    content.review_cnt = self.review_cnt;
    content.all_point = self.all_point;
    content.all_hyoka_cnt = self.all_hyoka_cnt;
    content.sasie_cnt = self.sasie_cnt;
    content.novelupdated_at = self.novelupdated_at;
    content.reading_chapter = self.reading_chapter;
    
    return true;
}

@end
