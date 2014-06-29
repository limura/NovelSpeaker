//
//  NarouContent.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/29.
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
@property (nonatomic, retain) Story *childStory;

@end
