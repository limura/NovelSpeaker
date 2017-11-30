//
//  NarouContentAllData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/03.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouContentCacheData.h"
#import "GlobalDataSingleton.h"
#import "NiftyUtility.h"

@implementation NarouContentCacheData

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
    if (self == nil) {
        return nil;
    }
    
    self.title = [NiftyUtility decodeHtmlEscape:[NSString stringWithFormat:@"%@", [jsonContent objectForKey:@"title"]]];
    self.ncode = [NSString stringWithFormat:@"%@", [jsonContent objectForKey:@"ncode"]];
    self.userid = [NSString stringWithFormat:@"%@", [jsonContent objectForKey:@"userid"]];
    self.writer = [NiftyUtility decodeHtmlEscape:[NSString stringWithFormat:@"%@", [jsonContent objectForKey:@"writer"]]];
    self.story = [NiftyUtility decodeHtmlEscape:[NSString stringWithFormat:@"%@", [jsonContent objectForKey:@"story"]]];
    self.genre = [self String2Number:[jsonContent objectForKey:@"genre"]];
    self.keyword = [NiftyUtility decodeHtmlEscape:[NSString stringWithFormat:@"%@", [jsonContent objectForKey:@"keyword"]]];
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
    self.currentReadingStory = nil;
    self.is_new_flug = [[NSNumber alloc] initWithBool:false];

    return self;
}

// CoreData側の値を使って初期化します。
- (id)initWithCoreData: (NarouContent*)coreDatacontent
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
   
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
    self.is_new_flug = coreDatacontent.is_new_flug;
    
    self.current_download_complete_count = 0;
    
    if (coreDatacontent.currentReadingStory == nil) {
        self.currentReadingStory = nil;
    }else{
        self.currentReadingStory = [[StoryCacheData alloc] initWithCoreData:coreDatacontent.currentReadingStory];
    }
    
    return self;
}

/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (NarouContent*)content
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
    content.is_new_flug = self.is_new_flug;
    
    if (self.currentReadingStory == nil) {
        content.currentReadingStory = nil;
    }else{
        [[GlobalDataSingleton GetInstance] UpdateStoryThreadUnsafe:self.currentReadingStory.content chapter_number:[self.currentReadingStory.chapter_number intValue] parentContent:self];
    }
    
    return true;
}

/// ユーザによる自作コンテンツか否かを取得します
/// 今の所、単に ncode として保存されている文字列の頭が "_u" になっているか否かを判定しているだけです。
- (BOOL)isUserCreatedContent
{
    if (self.ncode == nil) {
        return false;
    }
    return [self.ncode hasPrefix:@"_u"] || [self isURLContent];
}

/// URLで指定されるコンテンツか否かを取得します
- (BOOL)isURLContent {
    if (self.ncode == nil) {
        return false;
    }
    if([self.ncode hasPrefix:@"http://"] || [self.ncode hasPrefix:@"https://"]){
        return true;
    }
    return false;
}


@end
