//
//  SpeechModSettingCacheData.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeechModSettingCacheData.h"

@interface SpeechModSettingCacheData ()
    @property (nonatomic, readwrite) NSString* beforeString;
    @property (nonatomic, readwrite) NSString* afterString;
    @property (nonatomic, readwrite) SpeechModSettingConvertType convertType;
@end

#define REGEXP_MAGIC_KEY @"\x07"

@implementation SpeechModSettingCacheData

/// beforeString と afterString を設定します
- (BOOL)setBeforeString:(NSString*)beforeString afterString:(NSString*)afterString type:(SpeechModSettingConvertType)type {
    if(beforeString == nil){
        self.beforeString = @"";
        self.afterString = @"";
        self.convertType = SpeechModSettingConvertType_JustMatch;
        return false;
    }
    if(afterString == nil){
        afterString = @"";
    }
    // TODO: CoreData内の beforeString の頭が REGEXP_MAGIC_KEY("\x07") で終わっていたら正規表現という極悪仕様をいつか直す('A`)
    // 末尾の \x0b を許してはなりません
    while([beforeString length] >= 1 && [beforeString hasSuffix:REGEXP_MAGIC_KEY]){
        beforeString = [beforeString substringToIndex:[beforeString length] - 1];
    }
    self.convertType = type;
    self.beforeString = beforeString;
    self.afterString = afterString;
    return true;
}
    
/// 値付き初期化
- (id)initWithBeforeString:(NSString*)beforeString afterString:(NSString*)afterString type:(SpeechModSettingConvertType)type
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    [self setBeforeString:beforeString afterString:afterString type:type];
    return self;
}

/// CoreData のデータから初期化します。
- (id)initWithCoreData:(SpeechModSetting*)coreDatacontent
{
    NSString* beforeString = coreDatacontent.beforeString;
    NSString* afterString = coreDatacontent.afterString;
    SpeechModSettingConvertType type = SpeechModSettingConvertType_JustMatch;
    // TODO: CoreData内の beforeString の末尾が REGEXP_MAGIC_KEY("\x07") で終わっていたら正規表現という極悪仕様をいつか直す('A`)
    while([beforeString length] >= 1 && [beforeString hasSuffix:REGEXP_MAGIC_KEY]){
        beforeString = [beforeString substringToIndex:[beforeString length] - 1];
        type = SpeechModSettingConvertType_Regexp;
    }
    return [self initWithBeforeString:beforeString afterString:afterString type:type];
}
/// 自分の持つ情報を CoreData側 に書き込みます。
- (BOOL)AssignToCoreData: (SpeechModSetting*)content
{
    NSString* beforeString = self.beforeString;
    NSString* afterString = self.afterString;
    // TODO: CoreData内の beforeString の末尾が REGEXP_MAGIC_KEY("\x07") で終わっていたら正規表現という極悪仕様をいつか直す('A`)
    if(self.convertType == SpeechModSettingConvertType_Regexp){
        beforeString = [beforeString stringByAppendingString:REGEXP_MAGIC_KEY];
    }
    content.beforeString = beforeString;
    content.afterString = afterString;
    
    return true;
}

/// 単純マッチでの置換か否かを取得します
- (BOOL)isJustMatchType{
    return self.convertType == SpeechModSettingConvertType_JustMatch;
}
/// 正規表現での置換か否かを取得します
- (BOOL)isRegexpType{
    return self.convertType == SpeechModSettingConvertType_Regexp;
}

/// CoreData で検索するための beforeString を取得します
- (NSString*)GetBeforeStringForCoreDataSearch{
    // TODO: CoreData内の beforeString の末尾が REGEXP_MAGIC_KEY("\x07") で終わっていたら正規表現という極悪仕様をいつか直す('A`)
    if(self.convertType == SpeechModSettingConvertType_Regexp){
        return [self.beforeString stringByAppendingString:REGEXP_MAGIC_KEY];
    }
    return self.beforeString;
}


@end
