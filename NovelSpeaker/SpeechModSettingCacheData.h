//
//  SpeechModSettingCacheData.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeechModSetting.h"

typedef NS_ENUM(NSUInteger, SpeechModSettingConvertType) {
    SpeechModSettingConvertType_JustMatch = 0,
    SpeechModSettingConvertType_Regexp = 1,
};

@interface SpeechModSettingCacheData : NSObject

@property (nonatomic, readonly) NSString* beforeString;
@property (nonatomic, readonly) NSString* afterString;
@property (nonatomic, readonly) SpeechModSettingConvertType convertType;


/// CoreData のデータから初期化します。
- (id)initWithCoreData: (SpeechModSetting*)coreDatacontent;
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeechModSetting*)content;

/// 値付き初期化
- (id)initWithBeforeString:(NSString*)beforeString afterString:(NSString*)afterString type:(SpeechModSettingConvertType)type;

/// 単純マッチでの置換か否かを取得します
- (BOOL)isJustMatchType;
/// 正規表現での置換か否かを取得します
- (BOOL)isRegexpType;
    
/// CoreData で検索するための beforeString を取得します
- (NSString*)GetBeforeStringForCoreDataSearch;

@end
