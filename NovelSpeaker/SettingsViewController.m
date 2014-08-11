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

#import "NiftySpeaker.h"

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
    
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
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
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultRate = [[NSNumber alloc] initWithFloat:sender.value];
    [[GlobalDataSingleton GetInstance] UpdateGlobalState:globalState];
}

- (IBAction)DefaultPitchChanged:(UISlider *)sender {
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultPitch = [[NSNumber alloc] initWithFloat:sender.value];
    [[GlobalDataSingleton GetInstance] UpdateGlobalState:globalState];
}

NiftySpeaker* g_Speaker;

- (IBAction)testButtonClicked:(id)sender {
    g_Speaker = [NiftySpeaker new];
    SpeechConfig* speakConfig = [SpeechConfig new];
    speakConfig.pitch = 1.5f;
    speakConfig.rate = 0.5f;
    [g_Speaker AddBlockStartSeparator:@"「" endString:@"」" speechConfig:speakConfig];
    [g_Speaker AddBlockStartSeparator:@"『" endString:@"』" speechConfig:speakConfig];
    [g_Speaker AddDelayBlockSeparator:@"\n\n" delay:0.1f];
    [g_Speaker AddDelayBlockSeparator:@"\r\n\r\n" delay:0.1f];
    //[speaker AddDelayBlockSeparator:@"。" delay:0.1f];
    [g_Speaker AddSpeechModText:@"異世界" to:@"イセカイ"];
    [g_Speaker AddSpeechModText:@"直継" to:@"ナオツグ"];
    [g_Speaker AddSpeechModText:@"術師" to:@"ジュツシ"];
    //[g_Speaker AddSpeechModText:@"辛い" to:@"ツライ"];
    //[g_Speaker AddSpeechModText:@"辛く" to:@"ツラク"];
    
    NSString* text = @"異世界の始まり\n"
    @"「なんで直継がいるんだ？」\n"
    @"突然炎の剣が振るわれた。\n"
    @"\n"
    @"（身体は思い通りに動く。……違和感があるのは、手足のサイズが微妙に違うせいみたいだな……。大きい差じゃなくて良かったけど）\n"
    @"\n"
    @"目の前に広がっているのはアキバの街。\n"
    @"「これは辛くて辛いな」シロエは直継に言った。\n"
    ;
    
    [g_Speaker SetText:text];
    [g_Speaker StartSpeech];
}

@end
