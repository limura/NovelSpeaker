//
//  SpeechWaitConfigCacheData.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import "SpeechWaitConfigCacheData.h"

@implementation SpeechWaitConfigCacheData

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeechWaitConfig*)coreDataWaitConfig
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    self.targetText = coreDataWaitConfig.targetText;
    self.delayTimeInSec = coreDataWaitConfig.delayTimeInSec;
    if (self.delayTimeInSec == nil) {
        self.delayTimeInSec = [[NSNumber alloc] initWithFloat:0.0f];
    }
    
    return self;
}

/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeechWaitConfig*)coreDataWaitConfig
{
    coreDataWaitConfig.targetText = self.targetText;
    coreDataWaitConfig.delayTimeInSec = self.delayTimeInSec;
    
    return true;
}

@end
