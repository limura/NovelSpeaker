//
//  SpeakPitchConfigCacheData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeakPitchConfig.h"

@interface SpeakPitchConfigCacheData : NSObject

@property (nonatomic) NSString* title;
@property (nonatomic) NSString* startText;
@property (nonatomic) NSString* endText;
@property (nonatomic) NSNumber* pitch;

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeakPitchConfig*)coreDatacontent;
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeakPitchConfig*)content;

@end
