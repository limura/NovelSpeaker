//
//  StoryCacheData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/14.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "StoryCacheData.h"

@implementation StoryCacheData

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (Story*)coreDataStory
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
   
    self.chapter_number = coreDataStory.chapter_number;
    self.content = [coreDataStory.content stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\n"];
    self.ncode = coreDataStory.ncode;
    self.readLocation = coreDataStory.readLocation;
    
    return self;
}
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (Story*)coreDataStory
{
    coreDataStory.chapter_number = self.chapter_number;
    coreDataStory.content = [self.content stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\n"];
    coreDataStory.ncode = self.ncode;
    coreDataStory.readLocation = self.readLocation;
    
    return true;
}

@end
