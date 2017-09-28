//
//  SpeakSettingEditTableViewCell.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeakSettingsTableViewController.h"

static NSString* const SpeakSettingEditTableViewCellID = @"SpeakSettingEditTableViewCell";

@interface SpeakSettingEditTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UITextField *startStringTextField;
@property (weak, nonatomic) IBOutlet UITextField *endStringTextField;
@property (weak, nonatomic) IBOutlet UISlider *pitchSlider;

@property (nonatomic, weak) id<SettingTableViewDelegate> testSpeakDelegate;

@end
