//
//  TextSizeSettingViewController.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/08.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "TextSizeSettingViewController.h"
#import "GlobalDataSingleton.h"
#import "NovelSpeaker-Swift.h"
#import "PickerViewDialog.h"

@interface TextSizeSettingViewController ()

@end

@implementation TextSizeSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [BehaviorLogger AddLogWithDescription:@"TextSizeSettingViewController viewDidLoad" data:@{}];
    // Do any additional setup after loading the view.
    if (font == nil) {
        //font = [UIFont systemFontOfSize:[UIFont systemFontSize]];
        font = [UIFont systemFontOfSize:140.0];
    }
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    [self setFontFromGlobalState:globalState];

    NSMutableArray* buttonItemList = [NSMutableArray new];
    UIBarButtonItem* fontButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"TextSizeSettingViewController_FontSettingTitle", @"字体設定") style:UIBarButtonItemStylePlain target:self action:@selector(fontButtonClick:)];
    [buttonItemList addObject:fontButton];
    UIBarButtonItem* colorButton = [[UIBarButtonItem alloc]
    initWithTitle:NSLocalizedString(@"TextSizeSettinvViewController_ColorSettingTitle", @"色設定") style:UIBarButtonItemStylePlain target:self action:@selector(colorButtonClick:)
        ];
    [buttonItemList addObject:colorButton];
    self.navigationItem.rightBarButtonItems = buttonItemList;
    
    [self setNotificationReciver];
    [self applyColorSetting];
}

- (void)setFontFromGlobalState:(GlobalStateCacheData*)globalState {
    float fontSizeValue = [globalState.textSizeValue floatValue];
    if (fontSizeValue < 1.0f) {
        fontSizeValue = 50.0f;
    }else if(fontSizeValue > 100.0f){
        fontSizeValue = 100.0f;
    }
    [self SetFontSizeByFontSizeValue:fontSizeValue];
    self.textSizeSlider.value = fontSizeValue;
}

- (void)dealloc
{
    [self removeNotificationReciver];
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

- (void)ReloadFont:(NSString*)fontName fontSize:(CGFloat)fontSize {
    if (fontName == nil) {
        font = [UIFont systemFontOfSize:fontSize];
    }else{
        font = [UIFont fontWithName:fontName size:fontSize];
    }
    if (font != nil) {
        self.sampleTextTextView.font = font;
    }
}

/// 表示しているフォントを指定された値から計算されるフォントサイズに変更します。(value そのものがフォントサイズではない所に注意)
- (void)SetFontSizeByFontSizeValue:(float)value
{
    double fontSize = [GlobalDataSingleton ConvertFontSizeValueToFontSize:value];
    [self ReloadFont:[[GlobalDataSingleton GetInstance] GetDisplayFontName] fontSize:fontSize];
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

- (void)fontButtonClick:(id)sender {
    [self performSegueWithIdentifier:@"FontSelectSegue" sender:self];
}

- (void)applyColorSetting{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    UIColor* backgroundColor = [globalData GetReadingColorSettingForBackgroundColor];
    UIColor* foregroundColor = [globalData GetReadingColorSettingForForegroundColor];
    if (backgroundColor == nil || foregroundColor == nil) {
        if (@available(iOS 13.0, *)) {
            self.sampleTextTextView.backgroundColor = UIColor.systemBackgroundColor;
            self.sampleTextTextView.textColor = UIColor.labelColor;
        } else {
            self.sampleTextTextView.backgroundColor = UIColor.whiteColor;
            self.sampleTextTextView.textColor = UIColor.blackColor;
        }
        return;
    }
    self.sampleTextTextView.backgroundColor = backgroundColor;
    self.sampleTextTextView.textColor = foregroundColor;
}

- (void)colorButtonClick:(id)sender {
    NSArray* colorSettingTitleList = @[
        NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Default", @"標準色(ダークモードやライトモード指定に従う)"),
        NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_White", @"白地に黒で固定"),
        NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Cream", @"クリーム色地に黒で固定"),
        NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Gray", @"濃いめの灰色地に白で固定"),
        NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Black", @"黒地に白で固定"),
        NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_UserSetting", @"ユーザ指定色で固定"),
    ];
    PickerViewDialog* picker = [PickerViewDialog
        createNewDialog:colorSettingTitleList
        firstSelectedString:colorSettingTitleList[0]
        parentView:self.view
        resultReceiver:^(NSString *targetString) {
        GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
        if ([targetString compare:NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Default", @"標準色(ダークモードやライトモード指定に従う)")] == NSOrderedSame) {
            [globalData SetReadingColorSettingForBackgroundColor:nil];
            [globalData SetReadingColorSettingForForegroundColor:nil];
        }else if ([targetString compare:NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_White", @"白地に黒で固定")] == NSOrderedSame) {
            [globalData SetReadingColorSettingForBackgroundColor:UIColor.whiteColor];
            [globalData SetReadingColorSettingForForegroundColor:UIColor.blackColor];
        }else if ([targetString compare:NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Cream", @"クリーム色地に黒で固定")] == NSOrderedSame) {
            [globalData SetReadingColorSettingForBackgroundColor:[[UIColor alloc] initWithRed:1.0 green:1.0 blue:0.878 alpha:1.0]];
            [globalData SetReadingColorSettingForForegroundColor:UIColor.blackColor];
        }else if ([targetString compare:NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Gray", @"暗めの灰色地に白で固定")] == NSOrderedSame) {
            [globalData SetReadingColorSettingForBackgroundColor:[[UIColor alloc] initWithRed:0.2 green:0.2 blue:0.2 alpha:1.0]];
            [globalData SetReadingColorSettingForForegroundColor:UIColor.whiteColor];
        }else if ([targetString compare:NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_Black", @"黒地に白で固定")] == NSOrderedSame) {
            [globalData SetReadingColorSettingForBackgroundColor:UIColor.blackColor];
            [globalData SetReadingColorSettingForForegroundColor:UIColor.whiteColor];
        }else if ([targetString compare:NSLocalizedString(@"TextSizeSettingViewController_ColorSettingTitle_UserSetting", @"ユーザ指定色で固定")] == NSOrderedSame) {
            [globalData SetReadingColorSettingForBackgroundColor:nil];
            [globalData SetReadingColorSettingForForegroundColor:nil];
        }else{
            [globalData SetReadingColorSettingForBackgroundColor:nil];
            [globalData SetReadingColorSettingForForegroundColor:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyColorSetting];
        });
    }];
    [picker popup:nil];
}

/// NotificationCenter の受信者の設定をします。
- (void)setNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(FontNameChanged:) name:@"FontNameChanged" object:nil];
    [notificationCenter addObserver:self selector:@selector(displayUpdateNeededNotificationReciever:) name:@"ConfigReloaded_DisplayUpdateNeeded" object:nil];
}

/// NotificationCenter の受信者の設定を解除します。
- (void)removeNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:@"FontNameChanged" object:nil];
    [notificationCenter removeObserver:self name:@"ConfigReloaded_DisplayUpdateNeeded" object:nil];
}

/// フォント変更イベントの受信
- (void)FontNameChanged:(NSNotification*)notification
{
    float currentValue = self.textSizeSlider.value;
    [self SetFontSizeByFontSizeValue:currentValue];
}

- (void)displayUpdateNeededNotificationReciever:(NSNotification*)notification{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setFontFromGlobalState:[[GlobalDataSingleton GetInstance] GetGlobalState]];
    });
}

@end
