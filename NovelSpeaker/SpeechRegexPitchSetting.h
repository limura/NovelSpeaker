//
//  SpeechRegexPitchSetting.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/29.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SpeechRegexPitchSetting : NSObject

@property (retain) NSRegularExpression* regex;
@property float pitch;

@end
