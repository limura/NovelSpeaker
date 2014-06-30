//
//  SettingsViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SettingsViewController : UIViewController
@property (weak, nonatomic) IBOutlet UISlider *defaultRateSetting;
@property (weak, nonatomic) IBOutlet UISlider *defaultPitchSetting;

- (IBAction)DefaultRateChanged:(UISlider *)sender;

- (IBAction)DefaultPitchChanged:(UISlider *)sender;

@end
