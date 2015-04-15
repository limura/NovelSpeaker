//
//  SpeechWaitSettingViewController.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import "SpeechWaitSettingViewController.h"
#import "GlobalDataSingleton.h"
#import "EasyAlert.h"

@interface SpeechWaitSettingViewController ()

@end

@implementation SpeechWaitSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
    m_NiftySpeaker = [NiftySpeaker new];
    
    // キーボードを閉じるためにシングルタップのイベントを取るようにします
    self.singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTap:)];
    self.singleTap.delegate = self;
    self.singleTap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:self.singleTap];
    
    if(self.speechWaitConfigCacheData != nil)
    {
        if ([self.speechWaitConfigCacheData.targetText compare:@"\r\n\r\n"] == NSOrderedSame)
        {
            // 改行については表示を変えて編集不可にします
            self.inputTextField.text = NSLocalizedString(@"SpeechWaitConfigTableView_TargetText_EnterEnter", @"<改行><改行>");;
            self.inputTextField.enabled = false;
        }else{
            self.inputTextField.text = self.speechWaitConfigCacheData.targetText;
            [self UpdateSpeechTestTextBox:self.speechWaitConfigCacheData.targetText];
        }
        if (self.speechWaitConfigCacheData.delayTimeInSec != nil) {
            self.waitTimeSlider.value = [self.speechWaitConfigCacheData.delayTimeInSec floatValue];
        }else{
            self.waitTimeSlider.value = 0.0f;
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/
/// シングルタップのイベントハンドラ
-(void)onSingleTap:(UITapGestureRecognizer *)recognizer {
    if (self.inputTextField.isFirstResponder) {
        [self.inputTextField resignFirstResponder];
    }
    if (self.SampleSpeechTextField.isFirstResponder) {
        [self.SampleSpeechTextField resignFirstResponder];
    }
}

/// シングルタップのイベントハンドルは、対象のテキストボックスでキーボードが表示されている時だけにします
-(BOOL) gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
    if (gestureRecognizer == self.singleTap) {
        // キーボード表示中のみ有効
        if (self.inputTextField.isFirstResponder
            || self.SampleSpeechTextField.isFirstResponder) {
            return YES;
        } else {
            return NO;
        }
    }
    return YES;
}

/// 読み上げの間の設定が変わったことのアナウンスを行います。
- (void)announceSpeechWaitConfig
{
    //NSLog(@"%@ position update notification %d/%d", content.ncode, n, maxPos);
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSString* notificationName = @"SpeechWaitSettingTableViewUpdated";
    NSNotification* notification = [NSNotification notificationWithName:notificationName object:self userInfo:nil];
    [notificationCenter postNotification:notification];
}

- (IBAction)commitButtonClicked:(id)sender {
    if ([self.inputTextField.text length] <= 0) {
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SpeechWaitConfigSettingView_PleaseInputText", @"文字列を入力してください。") message:nil];
        return;
    }
    
    SpeechWaitConfigCacheData* waitConfig = [SpeechWaitConfigCacheData new];
    if ([self.inputTextField.text compare:NSLocalizedString(@"SpeechWaitConfigTableView_TargetText_EnterEnter", @"<改行><改行>")] == NSOrderedSame)
    {
        waitConfig.targetText = @"\r\n\r\n";
    }else{
        waitConfig.targetText = self.inputTextField.text;
    }
    waitConfig.delayTimeInSec = [[NSNumber alloc] initWithFloat:self.waitTimeSlider.value];
    if([[GlobalDataSingleton GetInstance] AddSpeechWaitSetting:waitConfig] != false)
    {
        [[GlobalDataSingleton GetInstance] saveContext];
        [self announceSpeechWaitConfig];
        [m_EasyAlert ShowAlertOneButton:NSLocalizedString(@"SpeechWaitConfigSettingView_SettingUpdated", @"読み上げ時の間の設定を追加しました。")
                                message:nil okButtonText:NSLocalizedString(@"OK_button", nil)
                        okActionHandler:^(UIAlertAction* action){
                            [self.navigationController popViewControllerAnimated:YES];
                        }];
    }else{
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SpeechWaitConfigSettingView_SettingUpdateFailed", @"読み上げ時の間の設定の追加に失敗しました。") message:nil];
    }
}
- (IBAction)WaitTimeSliderLeftButtonClicked:(id)sender {
    float v = self.waitTimeSlider.value;
    v -= 0.1f;
    if (v <= 0.0f) {
        v = 0.0f;
    }
    self.waitTimeSlider.value = v;
}

- (IBAction)WaitTimeSliderRightButtonClicked:(id)sender {
    float v = self.waitTimeSlider.value;
    v += 0.1f;
    if (v > self.waitTimeSlider.maximumValue) {
        v = self.waitTimeSlider.maximumValue;
    }
    self.waitTimeSlider.value = v;
}

- (void)TestSpeech:(NSString*)speechString {
    if ([speechString length] <= 0) {
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SpeechWaitConfigSettingView_PleaseSetSpeechText", @"読み上げテスト用の文字列を設定してください") message:nil];
        return;
    }
    
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [m_NiftySpeaker StopSpeech];
    [m_NiftySpeaker ClearSpeakSettings];
    [globalData ApplyDefaultSpeechconfig:m_NiftySpeaker];
    [globalData ApplySpeakPitchConfig:m_NiftySpeaker];
    [globalData ApplySpeechModConfig:m_NiftySpeaker];
    [globalData ApplySpeechWaitConfig:m_NiftySpeaker];

    // 読み上げの間の設定を上書きします
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    if ([globalState.speechWaitSettingUseExperimentalWait boolValue]) {
        [m_NiftySpeaker DeleteSpeechModString:self.inputTextField.text];
    }else{
        [m_NiftySpeaker DeleteDelayBlockSeparator:self.inputTextField.text];
    }
    float delay = self.waitTimeSlider.value;
    if (delay > 0.0f) {
        if ([globalState.speechWaitSettingUseExperimentalWait boolValue]) {
            NSMutableString* waitString = [[NSMutableString alloc] initWithString:@"。"];
            for (float x = 0.0f; x < delay; x += 0.1f) {
                [waitString appendString:@"_。"];
            }
            [m_NiftySpeaker AddSpeechModText:self.inputTextField.text to:waitString];
        }else{
            [m_NiftySpeaker AddDelayBlockSeparator:self.inputTextField.text delay:delay];
        }
    }
    if (![globalState.speechWaitSettingUseExperimentalWait boolValue]) {
        // 何故か default の delay のものだと、最初の一発目は読み上げの delay が効かないので怪しく行頭にdelay用の文字列を追加します。
        speechString = [[NSString alloc] initWithFormat:@"%@%@", self.inputTextField.text, speechString];
    }
    
    [m_NiftySpeaker SetText:speechString];
    [m_NiftySpeaker StartSpeech];
}

- (IBAction)SampleSpeechButtonClicked:(id)sender {
    NSString* speechString = self.SampleSpeechTextField.text;
    [self TestSpeech:speechString];
}

- (void)UpdateSpeechTestTextBox:(NSString*)separateString {
    NSString* newTestString = [[NSString alloc] initWithFormat:@"%@%@%@"
                               , NSLocalizedString(@"SpeechWaitConfigSettingView_SpeechTestTextBoxLeftSide", @"ここに書かれた文を")
                               , separateString
                               , NSLocalizedString(@"SpeechWaitConfigSettingView_SpeechTestTextBoxRightSide", @"テストで読み上げます")
                                ];
    self.SampleSpeechTextField.text = newTestString;
}

- (IBAction)inputTextFieldChanged:(id)sender {
    [self UpdateSpeechTestTextBox:self.inputTextField.text];
}
@end
