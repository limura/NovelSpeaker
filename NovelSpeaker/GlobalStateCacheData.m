//
//  GlobalStateCacheData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "GlobalStateCacheData.h"
#import "GlobalDataSingleton.h"

@implementation GlobalStateCacheData

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (GlobalState*)coreDataState
{
    self = [super init];
    
    self.defaultPitch = coreDataState.defaultPitch;
    self.defaultRate = coreDataState.defaultRate;
    self.maxSpeechTimeInSec = coreDataState.maxSpeechTimeInSec;
    self.textSizeValue = coreDataState.textSizeValue;
    self.currentReadingStory = nil;
    if (coreDataState.currentReadingStory != nil) {
        self.currentReadingStory = [[StoryCacheData alloc] initWithCoreData:coreDataState.currentReadingStory];
    }
    // 5分未満(多分初期値)であれば23時間55分にします。
    if (self.maxSpeechTimeInSec == nil || [self.maxSpeechTimeInSec intValue] < 5 * 60) {
        self.maxSpeechTimeInSec = [[NSNumber alloc] initWithInt:((23*60)+55)*60];
    }
    
    return self;
}

/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (GlobalState*)coreDataState
{
    coreDataState.defaultPitch = self.defaultPitch;
    coreDataState.defaultRate = self.defaultRate;
    coreDataState.maxSpeechTimeInSec = self.maxSpeechTimeInSec;
    coreDataState.textSizeValue = self.textSizeValue;

    if (self.currentReadingStory == nil) {
        coreDataState.currentReadingStory = nil;
        return true;
    }
    // TODO: これは内部で dispatch_sync() を呼ぶので上で dispatch_sync() が呼ばれてるとデッドロックになります。
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:self.currentReadingStory.ncode];
    if (content == nil) {
        return false;
    }
    return [globalData UpdateReadingPoint:content story:self.currentReadingStory];
}

@end
