//
//  MaxSpeechTimeTableViewCell.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/12/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>

static NSString* const MaxSpeechTimeTableViewCellID = @"MaxSpeechTimeTableViewCell";

@interface MaxSpeechTimeTableViewCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIDatePicker *CountDownTimer;

/// 設定されている最大連続再生時間を取り出します
- (NSNumber*) GetMaxSpeechTimeInSec;

@end
