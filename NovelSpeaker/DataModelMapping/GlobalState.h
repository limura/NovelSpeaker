//
//  GlobalState.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/12.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class Story;

@interface GlobalState : NSManagedObject

@property (nonatomic, retain) NSNumber * defaultPitch;
@property (nonatomic, retain) NSNumber * defaultRate;
@property (nonatomic, retain) Story *currentReadingStory;

@end
