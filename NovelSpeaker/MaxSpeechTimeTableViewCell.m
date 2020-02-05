//
//  MaxSpeechTimeTableViewCell.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/12/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "MaxSpeechTimeTableViewCell.h"
#import "GlobalDataSingleton.h"

@implementation MaxSpeechTimeTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [self.CountDownTimer setCountDownDuration:[[globalData GetGlobalState].maxSpeechTimeInSec intValue]];
    
    [self.CountDownTimer addTarget:self action:@selector(MaxSpeechTimeInSecPickerDidChange:) forControlEvents:UIControlEventValueChanged];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

/// GlobalStateの最大連続再生時間の値を更新します。
- (void)UpdateGlobalState
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalDataCache = [globalData GetGlobalState];
    globalDataCache.maxSpeechTimeInSec = [self GetMaxSpeechTimeInSec];
    [globalData UpdateGlobalState:globalDataCache];
}

/// 設定されている最大連続再生時間を取り出します
- (NSNumber*) GetMaxSpeechTimeInSec
{
    return [[NSNumber alloc] initWithInt:[self.CountDownTimer countDownDuration]];
}

/// CountDownTimer(UIDatePicker) の値が変わった時のイベントハンドラ
- (void)MaxSpeechTimeInSecPickerDidChange:(UIDatePicker*)picker
{
    [self UpdateGlobalState];
}

@end
