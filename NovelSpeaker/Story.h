//
//  Story.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/29.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class NarouContent;

@interface Story : NSManagedObject

@property (nonatomic, retain) NSString * content;
@property (nonatomic, retain) NarouContent *parentContent;

@end
