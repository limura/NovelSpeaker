//
//  Story.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/22.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class GlobalState, NarouContent;

@interface Story : NSManagedObject

@property (nonatomic, retain) NSNumber * chapter_number;
@property (nonatomic, retain) NSString * content;
@property (nonatomic, retain) NSString * ncode;
@property (nonatomic, retain) NSNumber * readLocation;
@property (nonatomic, retain) NarouContent *parentContent;
@property (nonatomic, retain) GlobalState *globalStateCurrentReadingInverse;
@property (nonatomic, retain) NarouContent *contentCurrentReadingInverse;

@end
