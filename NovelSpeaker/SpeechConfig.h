//
//  SpeechConfig.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/10.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

/// 読み上げの時の設定
@interface SpeechConfig : NSObject

@property (nonatomic) NSString* voiceIdentifier;
@property (nonatomic) float pitch;
@property (nonatomic) float rate;
@property (nonatomic) float volume;
@property (nonatomic) NSTimeInterval beforeDelay;
@property (nonatomic) NSString* voiceLocale;

@end
