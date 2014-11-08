//
//  TextSizeSettingViewController.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/08.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "TextSizeSettingViewController.h"
#import "GlobalDataSingleton.h"

@interface TextSizeSettingViewController ()

@end

@implementation TextSizeSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    if (font == nil) {
        //font = [UIFont systemFontOfSize:[UIFont systemFontSize]];
        font = [UIFont systemFontOfSize:140.0];
    }
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    float fontSizeValue = [globalState.textSizeValue floatValue];
    if (fontSizeValue < 1.0f) {
        fontSizeValue = 50.0f;
    }else if(fontSizeValue > 100.0f){
        fontSizeValue = 100.0f;
    }
    [self SetFontSizeByFontSizeValue:fontSizeValue];
    self.textSizeSlider.value = fontSizeValue;
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

/// 表示しているフォントを指定された値から計算されるフォントサイズに変更します。(value そのものがフォントサイズではない所に注意)
- (void)SetFontSizeByFontSizeValue:(float)value
{
    double fontSize = [GlobalDataSingleton ConvertFontSizeValueToFontSize:value];
    
    self.sampleTextTextView.font = [font fontWithSize:fontSize];
}

/// 小説の表示用フォントサイズが変わったことをアナウンスします。
- (void)StoryDisplayFontSizeChangedAnnounce:(float)fontSize
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSDictionary* userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[[NSNumber alloc] initWithFloat:fontSize], @"fontSizeValue", nil];
    NSNotification* notification = [NSNotification notificationWithName:@"StoryDisplayFontSizeChanged" object:self userInfo:userInfo];
    [notificationCenter postNotification:notification];
}

- (IBAction)textSizeSliderMoved:(id)sender {
    float currentValue = self.textSizeSlider.value;
    [self SetFontSizeByFontSizeValue:currentValue];
    
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    globalState.textSizeValue = [[NSNumber alloc] initWithFloat:currentValue];
    [globalData UpdateGlobalState:globalState];
    [self StoryDisplayFontSizeChangedAnnounce:currentValue];
}
@end
