//
//  SettingsTableViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Speaker.h"
#import "CreateNewSpeakPitchSettingViewController.h"

@protocol SettingTableViewDelegate <NSObject>

/// テスト読み上げボタンが押された時のイベントハンドラ
- (void) testSpeakWithPitch:(float)pitch rate:(float)rate;

/// テスト読み上げ用の文字列が書き換えられた時のイベントハンドラ
- (void) testSpeakSampleTextUpdate:(NSString*)text;


@end

@interface SpeakSettingsTableViewController : UITableViewController<SettingTableViewDelegate, CreateNewSpeakPitchSettingDelegate>
{
    NSString* testSpeechSampleText;
    Speaker* m_Speaker;
}

@end
