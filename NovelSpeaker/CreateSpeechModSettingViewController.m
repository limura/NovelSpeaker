//
//  CreateSpeechModSettingViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "CreateSpeechModSettingViewController.h"
#import "GlobalDataSingleton.h"
#import "NovelSpeaker-Swift.h"

@interface CreateSpeechModSettingViewController ()

@end

@implementation CreateSpeechModSettingViewController

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
    [BehaviorLogger AddLogWithDescription:@"CreateSpeechModSettingViewController viewDidLoad" data:@{}];
    
    m_Speaker = [Speaker new];
    m_LoadedSpeechModSetting = nil;
    if (self.targetBeforeString != nil) {
        self.beforeTextField.text = self.targetBeforeString;
        self.prevConvertTextField.text = self.beforeTextField.text;
    }else if(self.targetSpeechModSetting != nil) {
        self.beforeTextField.text = self.targetSpeechModSetting.beforeString;
        self.afterTextField.text = self.targetSpeechModSetting.afterString;
        self.regexpSwitch.on = self.targetSpeechModSetting.isRegexpType;
        if (!self.regexpSwitch.on) {
            self.prevConvertTextField.text = self.beforeTextField.text;
        }
        m_LoadedSpeechModSetting = self.targetSpeechModSetting;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)showAlertView:(NSString*)message
{
    [NiftyUtilitySwift EasyDialogOneButtonWithViewController:self title:message message:nil buttonTitle:NSLocalizedString(@"OK_button", @"OK") buttonAction:nil];
}

- (IBAction)testSpeechButtonClicked:(id)sender {
    [self UpdateAfterConvertTextField];
    //NSString* sampleText = [[NSString alloc] initWithFormat:NSLocalizedString(@"CreateSpeechModSettingView_ReadItForAAAinBBB", @"%@を%@に読み替えます。"), self.beforeTextField.text, self.afterTextField.text];
    NSString* sampleText = self.afterConvertTextField.text;
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    [m_Speaker SetRate:[globalState.defaultRate floatValue]];
    [m_Speaker SetPitch:[globalState.defaultPitch floatValue]];
    [m_Speaker SetVoiceWithIdentifier:[globalData GetVoiceIdentifier]];
    [m_Speaker Speech:sampleText];
}

- (IBAction)assignButtonClicked:(id)sender {
    if ([self.beforeTextField.text length] <= 0
        || [self.afterTextField.text length] <= 0) {
        [self showAlertView:NSLocalizedString(@"CreateSpeechModSettingView_ERROR_NoStringSetting", @"変換元か変換先の文字列が設定されていません。")];
        return;
    }
    
    SpeechModSettingConvertType type = SpeechModSettingConvertType_JustMatch;
    if(self.regexpSwitch.on){
        type = SpeechModSettingConvertType_Regexp;
    }
    if (m_LoadedSpeechModSetting != nil) {
        [[GlobalDataSingleton GetInstance] DeleteSpeechModSetting:m_LoadedSpeechModSetting];
    }
    SpeechModSettingCacheData* speechMod = [[SpeechModSettingCacheData alloc] initWithBeforeString:self.beforeTextField.text afterString:self.afterTextField.text type:type];
    if ([[GlobalDataSingleton GetInstance] UpdateSpeechModSetting:speechMod] == false) {
        [self showAlertView:NSLocalizedString(@"CreateSpeechModSettingView_SettingFailed", @"設定に失敗しました。")];
        return;
    }
    [self.createNewSpeechModSettingDelegate NewSpeechModSettingAdded];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)UpdateAfterConvertTextField{
    NSString* prevString = self.prevConvertTextField.text;
    
    NiftySpeaker* niftySpeaker = [NiftySpeaker new];
    if (self.regexpSwitch.on){
        NSString* pattern = self.beforeTextField.text;
        NSString* to = self.afterTextField.text;
        NSArray* modSettingArray = [StringSubstituter FindRegexpSpeechModConfigs:prevString pattern:pattern to:to];
        for(SpeechModSettingCacheData* modSetting in modSettingArray) {
            [niftySpeaker AddSpeechModText:modSetting.beforeString to:modSetting.afterString];
        }
    }else{
        NSString* from = self.beforeTextField.text;
        NSString* to = self.afterTextField.text;
        [niftySpeaker AddSpeechModText:from to:to];
    }
    [niftySpeaker SetText:prevString];
    NSString* afterString = [niftySpeaker GetSpeechText];
    self.afterConvertTextField.text = afterString;
}
    
- (IBAction)RefreshButtonClicked:(id)sender {
    [self UpdateAfterConvertTextField];
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

- (IBAction)uiTextFieldDidEndOnExit:(id)sender {
    [sender resignFirstResponder];
}
- (IBAction)viewTapEvent:(id)sender {
    NSLog(@"viewTapEvent.");
    [self.view endEditing:true];
}
- (IBAction)BeforeTextFieldEditingChanged:(id)sender {
    if (!self.regexpSwitch.on){
        self.prevConvertTextField.text = self.beforeTextField.text;
    }
}
- (IBAction)AfterTextFieldEditingChaned:(id)sender {
}
@end
