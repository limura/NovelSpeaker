//
//  DownloadQueue.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class NarouContent;

@interface DownloadQueue : NSManagedObject

@property (nonatomic, retain) NSNumber * sort_index;
@property (nonatomic, retain) NarouContent *targetContent;

@end
