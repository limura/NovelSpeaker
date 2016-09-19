//
//  SpeakSettingEditTableViewCell.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeakSettingEditTableViewCell.h"
#import "GlobalDataSingleton.h"
#import "SpeakPitchConfigCacheData.h"

@implementation SpeakSettingEditTableViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];
    // Initialization code
    self.pitchSlider.minimumValue = 0.5f;
    self.pitchSlider.maximumValue = 2.0f;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

/// 高さのスライドバーの値が変わった
- (IBAction)pitchValueChanged:(id)sender {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    SpeakPitchConfigCacheData* pitchConfig = [globalData GetSpeakPitchConfigWithTitle:self.titleLabel.text];
    if (pitchConfig == nil) {
        return;
    }
    pitchConfig.pitch = [[NSNumber alloc] initWithFloat:self.pitchSlider.value];
    [globalData UpdateSpeakPitchConfig:pitchConfig];
}

/// 発声テストボタンが押された
- (IBAction)speakTestButtonClicked:(id)sender {
    float rate = [[[GlobalDataSingleton GetInstance] GetGlobalState].defaultRate floatValue];
    [self.testSpeakDelegate testSpeakWithPitch:self.pitchSlider.value rate:rate];
}

/// 開始点のテキストボックスでEnterが押された
- (IBAction)startTextBoxDidEndOnExit:(id)sender {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    SpeakPitchConfigCacheData* pitchConfig = [globalData GetSpeakPitchConfigWithTitle:self.titleLabel.text];
    if (pitchConfig == nil) {
        return;
    }
    pitchConfig.startText = self.startStringTextField.text;
    [globalData UpdateSpeakPitchConfig:pitchConfig];

    // キーボードを閉じる
    [sender resignFirstResponder];
}
/// 開始点のテキストボックスでEnterが押された
- (IBAction)endTextBoxDidEndOnExit:(id)sender {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    SpeakPitchConfigCacheData* pitchConfig = [globalData GetSpeakPitchConfigWithTitle:self.titleLabel.text];
    if (pitchConfig == nil) {
        return;
    }
    pitchConfig.endText = self.endStringTextField.text;
    [globalData UpdateSpeakPitchConfig:pitchConfig];
    // キーボードを閉じる
    [sender resignFirstResponder];
}
@end
