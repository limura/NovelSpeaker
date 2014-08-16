//
//  CreateNewSpeakPitchSettingViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "CreateNewSpeakPitchSettingViewController.h"
#import "GlobalDataSingleton.h"

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
        UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"タイトルにする文字列を入れてください。" message:nil delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        m_isNeedBack = false;
        [alertView show];
        return;
    }
    
    SpeakPitchConfigCacheData* pitchConfig = [[GlobalDataSingleton GetInstance] GetSpeakPitchConfigWithTitle:title];
    if (pitchConfig != nil) {
        UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"既に存在する設定です。" message:nil delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        m_isNeedBack = false;
        [alertView show];
        return;
    }
    pitchConfig = [SpeakPitchConfigCacheData new];
    pitchConfig.pitch = [[NSNumber alloc] initWithFloat:1.0f];
    pitchConfig.startText = @"『";
    pitchConfig.endText = @"』";
    pitchConfig.title = title;
    if (![[GlobalDataSingleton GetInstance] UpdateSpeakPitchConfig:pitchConfig]) {
        UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"音声設定の追加に失敗しました。" message:nil delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        m_isNeedBack = true;
        [alertView show];
        return;
    }
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"音声設定を追加しました。" message:nil delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
    m_isNeedBack = true;
    [alertView show];
}

// alertView で何かがクリックされた
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (m_isNeedBack) {
        [self.createNewSpeakPitchSettingDelegate NewPitchSettingAdded];
        [self.navigationController popViewControllerAnimated:YES];
    }
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
