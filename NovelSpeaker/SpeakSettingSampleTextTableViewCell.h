//
//  SpeakSettingSampleTextTableViewCell.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeakSettingsTableViewController.h"

static NSString* const SpeakSettingSampleTextTableViewCellID = @"SpeakSettingSampleTextTableViewCell";

@interface SpeakSettingSampleTextTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UITextField *sampleTextTextField;

@property (nonatomic, weak) id<SettingTableViewDelegate> testSpeakDelegate;

@end
