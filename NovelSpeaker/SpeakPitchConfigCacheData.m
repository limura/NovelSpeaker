//
//  SpeakPitchConfigCacheData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeakPitchConfigCacheData.h"

@implementation SpeakPitchConfigCacheData

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeakPitchConfig*)coreDatacontent
{
    self = [super init];
    
    self.pitch = coreDatacontent.pitch;
    self.title = coreDatacontent.title;
    self.startText = coreDatacontent.startText;
    self.endText = coreDatacontent.endText;
    
    return self;
}
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeakPitchConfig*)content
{
    content.pitch = self.pitch;
    content.title = self.title;
    content.startText = self.startText;
    content.endText = self.endText;
    
    return true;
}


@end
