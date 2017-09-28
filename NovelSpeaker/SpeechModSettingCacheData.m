//
//  SpeechModSettingCacheData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeechModSettingCacheData.h"

@implementation SpeechModSettingCacheData

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeechModSetting*)coreDatacontent
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
   
    self.beforeString = coreDatacontent.beforeString;
    self.afterString = coreDatacontent.afterString;
    
    return self;
}
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeechModSetting*)content
{
    content.beforeString = self.beforeString;
    content.afterString = self.afterString;
    
    return true;
}

/// 値付き初期化
- (id)initWithBeforeString:(NSString*)beforeString afterString:(NSString*)afterString
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    self.beforeString = beforeString;
    self.afterString = afterString;
    return self;
}

@end
