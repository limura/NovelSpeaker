//
//  NarouContentAllData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/03.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NarouContent.h"
#import "StoryCacheData.h"

@interface NarouContentCacheData : NSObject

/// JOSN のデータから初期化します。
- (id)initWithJsonData: (NSDictionary*)jsonContent;
/// CoreData のデータから初期化します。
- (id)initWithCoreData: (NarouContent*)coreDatacontent;
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (NarouContent*)content;

@property (nonatomic) NSString* title;
@property (nonatomic) NSString* ncode;
@property (nonatomic) NSString* userid;
@property (nonatomic) NSString* writer;
@property (nonatomic) NSString* story;
@property (nonatomic) NSNumber* genre;
@property (nonatomic) NSString* keyword;
@property (nonatomic) NSNumber* general_all_no;
@property (nonatomic) NSNumber* end;
@property (nonatomic) NSNumber* global_point;
@property (nonatomic) NSNumber* fav_novel_cnt;
@property (nonatomic) NSNumber* review_cnt;
@property (nonatomic) NSNumber* all_point;
@property (nonatomic) NSNumber* all_hyoka_cnt;
@property (nonatomic) NSNumber* sasie_cnt;
@property (nonatomic) NSDate* novelupdated_at;
@property (nonatomic) NSNumber* reading_chapter;
@property (nonatomic) NSNumber* is_new_flug;
@property (nonatomic) StoryCacheData* currentReadingStory;

// ダウンロード進捗確認用。現在ダウンロードが完了しているコンテンツの数(最大値は general_all_no のはずです)
@property (nonatomic) int current_download_complete_count;

/// ユーザによる自作コンテンツか否かを取得します
- (BOOL)isUserCreatedContent;

/// URLで指定されるコンテンツか否かを取得します
- (BOOL)isURLContent;

@end
