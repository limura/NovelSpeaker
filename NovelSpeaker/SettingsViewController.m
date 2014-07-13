//
//  SettingsViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "GlobalDataSingleton.h"

@interface SettingsViewController ()

@end

@implementation SettingsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.defaultRateSetting.minimumValue = AVSpeechUtteranceMinimumSpeechRate;
    self.defaultRateSetting.maximumValue = AVSpeechUtteranceMaximumSpeechRate;
    self.defaultPitchSetting.minimumValue = 0.5f;
    self.defaultPitchSetting.maximumValue = 2.0f;
    
    GlobalState* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    if (globalState != nil) {
        self.defaultRateSetting.value = [globalState.defaultRate floatValue];
        self.defaultPitchSetting.value = [globalState.defaultPitch floatValue];
    }else{
        self.defaultRateSetting.value = AVSpeechUtteranceDefaultSpeechRate;
        self.defaultPitchSetting.value = 1.0f;
    }
    NSLog(@"default setting loaded: rate: %f, pitch: %f", self.defaultRateSetting.value, self.defaultPitchSetting.value);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

- (IBAction)DefaultRateChanged:(UISlider *)sender {
    GlobalState* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultRate = [[NSNumber alloc] initWithFloat:sender.value];
}

- (IBAction)DefaultPitchChanged:(UISlider *)sender {
    GlobalState* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultPitch = [[NSNumber alloc] initWithFloat:sender.value];
}

@end
