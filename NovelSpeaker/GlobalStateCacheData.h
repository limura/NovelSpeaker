//
//  GlobalStateCacheData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GlobalState.h"
#import "StoryCacheData.h"

@interface GlobalStateCacheData : NSObject

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (GlobalState*)coreDataStory;

/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (GlobalState*)coreDataStory;

@property (nonatomic) NSNumber * defaultPitch;
@property (nonatomic) NSNumber * defaultRate;
@property (nonatomic) NSNumber * maxSpeechTimeInSec;
@property (nonatomic) NSNumber * textSizeValue;
@property (nonatomic) NSNumber * speechDelayComma;
@property (nonatomic) NSNumber * speechDelayPeriod;
@property (nonatomic) NSNumber * speechDelayThreeComma;
@property (nonatomic) NSNumber * speechDelayParagraph;
@property (nonatomic) StoryCacheData *currentReadingStory;

@end
