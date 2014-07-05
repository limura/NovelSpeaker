//
//  NarouContentAllData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/03.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NarouContentAllData : NSObject

- (id)initWithJsonData: (NSDictionary*)jsonContent;

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

@end
