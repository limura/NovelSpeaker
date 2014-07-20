//
//  StoryCacheData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/14.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Story.h"

@interface StoryCacheData : NSObject

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (Story*)coreDataStory;
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (Story*)story;

@property (nonatomic) NSNumber * chapter_number;
@property (nonatomic) NSString * content;
@property (nonatomic) NSString * ncode;
@property (nonatomic) NSNumber * readLocation;

@end
