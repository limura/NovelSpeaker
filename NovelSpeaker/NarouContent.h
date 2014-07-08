//
//  NarouContent.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Story;

@interface NarouContent : NSManagedObject

@property (nonatomic, retain) NSString * ncode;
@property (nonatomic, retain) NSDate * novelupdated_at;
@property (nonatomic, retain) NSString * story;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * userid;
@property (nonatomic, retain) NSString * writer;
@property (nonatomic, retain) NSNumber * genre;
@property (nonatomic, retain) NSString * keyword;
@property (nonatomic, retain) NSNumber * general_all_no;
@property (nonatomic, retain) NSNumber * end;
@property (nonatomic, retain) NSNumber * global_point;
@property (nonatomic, retain) NSNumber * fav_novel_cnt;
@property (nonatomic, retain) NSNumber * review_cnt;
@property (nonatomic, retain) NSNumber * all_point;
@property (nonatomic, retain) NSNumber * all_hyoka_cnt;
@property (nonatomic, retain) NSNumber * sasie_cnt;
@property (nonatomic, retain) NSSet *childStory;
@property (nonatomic, retain) NSManagedObject *downloadQueueStatus;
@end

@interface NarouContent (CoreDataGeneratedAccessors)

- (void)addChildStoryObject:(Story *)value;
- (void)removeChildStoryObject:(Story *)value;
- (void)addChildStory:(NSSet *)values;
- (void)removeChildStory:(NSSet *)values;

@end
