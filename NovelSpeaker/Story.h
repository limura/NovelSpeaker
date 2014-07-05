//
//  Story.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class NarouContent;

@interface Story : NSManagedObject

@property (nonatomic, retain) NSString * content;
@property (nonatomic, retain) NSNumber * chapter_number;
@property (nonatomic, retain) NSString * ncode;
@property (nonatomic, retain) NarouContent *parentContent;

@end
