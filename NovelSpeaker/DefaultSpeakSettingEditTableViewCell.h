//
//  DefaultSpeakSettingEditTableViewCell.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeakSettingsTableViewController.h"

static NSString* const DefaultSpeakSettingEditTableViewCellID = @"DefaultSpeakSettingEditTableViewCell";

@interface DefaultSpeakSettingEditTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UISlider *pitchSlider;
@property (weak, nonatomic) IBOutlet UISlider *rateSlider;
@property (weak, nonatomic) IBOutlet UIButton *speakerNameButton;

@property (nonatomic, weak) id<SettingTableViewDelegate> testSpeakDelegate;

@end
