//
//  DefaultSpeakSettingEditTableViewCell.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "DefaultSpeakSettingEditTableViewCell.h"
#import "GlobalDataSingleton.h"

@implementation DefaultSpeakSettingEditTableViewCell

- (void)awakeFromNib
{
    // Initialization code
    self.pitchSlider.minimumValue = 0.5f;
    self.pitchSlider.maximumValue = 2.0f;
    self.rateSlider.minimumValue = AVSpeechUtteranceMinimumSpeechRate;
    self.rateSlider.maximumValue = AVSpeechUtteranceMaximumSpeechRate;
    
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    self.pitchSlider.value = [globalState.defaultPitch floatValue];
    self.rateSlider.value = [globalState.defaultRate floatValue];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (IBAction)pitchValueChanged:(id)sender {
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultPitch = [[NSNumber alloc] initWithFloat:self.pitchSlider.value];
    [[GlobalDataSingleton GetInstance] UpdateGlobalState:globalState];
}
- (IBAction)rateValueChanged:(id)sender {
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultRate = [[NSNumber alloc] initWithFloat:self.rateSlider.value];
    [[GlobalDataSingleton GetInstance] UpdateGlobalState:globalState];
}

- (IBAction)speakTestButtonClicked:(id)sender {
    [self.testSpeakDelegate testSpeakWithPitch:self.pitchSlider.value rate:self.rateSlider.value];
}
@end
