//
//  SpeechModSettingCacheData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeechModSetting.h"

@interface SpeechModSettingCacheData : NSObject

@property (nonatomic) NSString* beforeString;
@property (nonatomic) NSString* afterString;

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeechModSetting*)coreDatacontent;
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeechModSetting*)content;

/// 値付き初期化
- (id)initWithBeforeString:(NSString*)beforeString afterString:(NSString*)afterString;

@end
