//
//  CreateNewSpeakPitchSettingViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "CreateNewSpeakPitchSettingViewController.h"
#import "GlobalDataSingleton.h"
#import "EasyAlert.h"

@interface CreateNewSpeakPitchSettingViewController ()

@end

@implementation CreateNewSpeakPitchSettingViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        m_isNeedBack = false;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    m_isNeedBack = false;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)createButtonClicked:(id)sender {
    NSString* title = self.titleTextField.text;
    if ([title length] <= 0) {
        UIAlertController* alert = [EasyAlert CreateAlertOneButton: NSLocalizedString(@"SpeakPitchSettingView_NoTitleStringAlert", @"タイトルにする文字列を入れてください。")
                                                           message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:nil];
        [self presentViewController:alert animated:true completion:nil];
        return;
    }
    
    SpeakPitchConfigCacheData* pitchConfig = [[GlobalDataSingleton GetInstance] GetSpeakPitchConfigWithTitle:title];
    if (pitchConfig != nil) {
        UIAlertController* alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"SpeakPitchSettingView_AlreadyExistingSetting", @"既に存在する設定です。")
                                                           message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:nil];
        [self presentViewController:alert animated:true completion:nil];
        return;
    }
    pitchConfig = [SpeakPitchConfigCacheData new];
    pitchConfig.pitch = [[NSNumber alloc] initWithFloat:1.0f];
    pitchConfig.startText = @"『";
    pitchConfig.endText = @"』";
    pitchConfig.title = title;
    if (![[GlobalDataSingleton GetInstance] UpdateSpeakPitchConfig:pitchConfig]) {
        UIAlertController* alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"SpeakPitchSettingView_AppendFailed.", @"音声設定の追加に失敗しました。")
                                                           message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:^(UIAlertAction* action){
                                                               [self.createNewSpeakPitchSettingDelegate NewPitchSettingAdded];
                                                               [self.navigationController popViewControllerAnimated:YES];
                                                           }];
        [self presentViewController:alert animated:true completion:nil];
        return;
    }
    UIAlertController* alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"SpeakPitchSettingView_AppendSuccess", @"音声設定を追加しました。")
                                                       message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:^(UIAlertAction* action){
                                                           [self.createNewSpeakPitchSettingDelegate NewPitchSettingAdded];
                                                           [self.navigationController popViewControllerAnimated:YES];
                                                       }];
    [self presentViewController:alert animated:true completion:nil];
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

@end
