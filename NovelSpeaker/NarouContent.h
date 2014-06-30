//
//  NarouContent.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/30.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Story;

@interface NarouContent : NSManagedObject

@property (nonatomic, retain) NSString * ncode;
@property (nonatomic, retain) NSString * story;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * userid;
@property (nonatomic, retain) NSString * writer;
@property (nonatomic, retain) NSDate * novelupdated_at;
@property (nonatomic, retain) NSDate * updated_at;
@property (nonatomic, retain) NSSet *childStory;
@end

@interface NarouContent (CoreDataGeneratedAccessors)

- (void)addChildStoryObject:(Story *)value;
- (void)removeChildStoryObject:(Story *)value;
- (void)addChildStory:(NSSet *)values;
- (void)removeChildStory:(NSSet *)values;

@end
