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
    
    if(self.speechWaitConfigCacheData != nil)
    {
        self.inputTextField.text = self.speechWaitConfigCacheData.targetText;
        if (self.speechWaitConfigCacheData.delayTimeInSec != nil
            && [self.speechWaitConfigCacheData.delayTimeInSec floatValue] > 0.0f) {
            self.onOffSwitch.on = YES;
        }else{
            self.onOffSwitch.on = NO;
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
#if true
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SpeechWaitConfigSettingView_PleaseInputText", @"文字列を入力してください。") message:nil];
#else
        UIAlertController* errorDialog = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"SpeechWaitConfigSettingView_PleaseInputText", @"文字列を入力してください。") message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:nil];
        [self presentViewController:errorDialog animated:true completion:nil];
#endif
        return;
    }
    
    SpeechWaitConfigCacheData* waitConfig = [SpeechWaitConfigCacheData new];
    waitConfig.targetText = self.inputTextField.text;
    if (self.onOffSwitch.on) {
        waitConfig.delayTimeInSec = [[NSNumber alloc] initWithFloat:0.5f];
    }else{
        waitConfig.delayTimeInSec = [[NSNumber alloc] initWithFloat:0.0f];
    }
    if([[GlobalDataSingleton GetInstance] AddSpeechWaitSetting:waitConfig] != false)
    {
        [[GlobalDataSingleton GetInstance] saveContext];
        [self announceSpeechWaitConfig];
#if true
        [m_EasyAlert ShowAlertOneButton:NSLocalizedString(@"SpeechWaitConfigSettingView_SettingUpdated", @"読み上げ時の間の設定を追加しました。")
                                message:nil okButtonText:NSLocalizedString(@"OK_button", nil)
                        okActionHandler:^(UIAlertAction* action){
                            [self.navigationController popViewControllerAnimated:YES];
                        }];
#else
        UIAlertController* alert = nil;
        alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"SpeechWaitConfigSettingView_SettingUpdated", @"読み上げ時の間の設定を追加しました。")
                                message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:^(UIAlertAction* action){
                                    [self.navigationController popViewControllerAnimated:YES];
                                }];
        [self presentViewController:alert animated:true completion:nil];
#endif
    }else{
#if true
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SpeechWaitConfigSettingView_SettingUpdateFailed", @"読み上げ時の間の設定の追加に失敗しました。") message:nil];
#else
        UIAlertController* alert = nil;
        alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"SpeechWaitConfigSettingView_SettingUpdateFailed", @"読み上げ時の間の設定の追加に失敗しました。")
                                message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:nil];
        [self presentViewController:alert animated:true completion:nil];
#endif
    }
}
@end
