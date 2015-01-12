//
//  SpeechWaitConfigCacheData.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeechWaitConfig.h"

@interface SpeechWaitConfigCacheData : NSObject

/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeechWaitConfig*)coreDataWaitConfig;
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeechWaitConfig*)waitConfig;

@property (nonatomic) NSString * targetText;
@property (nonatomic) NSNumber * delayTimeInSec;

@end
