//
//  SpeechWaitSettingViewController.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeechWaitConfigCacheData.h"

@interface SpeechWaitSettingViewController : UIViewController

// 前のページから受け取る情報
@property SpeechWaitConfigCacheData* speechWaitConfigCacheData;
@property (weak, nonatomic) IBOutlet UITextField *inputTextField;
@property (weak, nonatomic) IBOutlet UISwitch *onOffSwitch;
@property (weak, nonatomic) IBOutlet UIButton *commitButton;
- (IBAction)commitButtonClicked:(id)sender;

@end
