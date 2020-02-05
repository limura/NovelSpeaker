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
#import "NiftySpeaker.h"
#import "NiftyUtility.h"
#import "PickerViewDialog.h"

@implementation DefaultSpeakSettingEditTableViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];
    // Initialization code
    self.pitchSlider.minimumValue = 0.5f;
    self.pitchSlider.maximumValue = 2.0f;
    self.rateSlider.minimumValue = AVSpeechUtteranceMinimumSpeechRate;
    self.rateSlider.maximumValue = AVSpeechUtteranceMaximumSpeechRate;

    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    self.pitchSlider.value = [globalState.defaultPitch floatValue];
    self.rateSlider.value = [globalState.defaultRate floatValue];
    self.pitchValueLabel.text = [[NSString alloc] initWithFormat:@"%.2f", self.pitchSlider.value];
    self.rateValueLabel.text = [[NSString alloc] initWithFormat:@"%.2f", self.rateSlider.value];

    NSString* speakerNameString = [NiftySpeaker getDisplayStringForVoiceIdentifier:[globalData GetVoiceIdentifier]];
    if (speakerNameString != nil) {
        [NiftyUtility setUIButtonText:self.speakerNameButton text:speakerNameString];
    }
    self.speakerNameButton.titleLabel.adjustsFontSizeToFitWidth = YES;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (IBAction)pitchValueChanged:(id)sender {
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultPitch = [[NSNumber alloc] initWithFloat:self.pitchSlider.value];
    self.pitchValueLabel.text = [[NSString alloc] initWithFormat:@"%.2f", self.pitchSlider.value];
    [[GlobalDataSingleton GetInstance] UpdateGlobalState:globalState];
}
- (IBAction)rateValueChanged:(id)sender {
    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    globalState.defaultRate = [[NSNumber alloc] initWithFloat:self.rateSlider.value];
    self.rateValueLabel.text = [[NSString alloc] initWithFormat:@"%.2f", self.rateSlider.value];
    [[GlobalDataSingleton GetInstance] UpdateGlobalState:globalState];
}

- (IBAction)speakTestButtonClicked:(id)sender {
    [self.testSpeakDelegate testSpeakWithPitch:self.pitchSlider.value rate:self.rateSlider.value];
}

- (IBAction)speakerSelectButtonClicked:(id)sender {
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_9_0) {
        [self.testSpeakDelegate showAlert:NSLocalizedString(@"DefaultSpeakSettingEditTableViewCell_AlertCanNotUseSpeakerSelection_title", @"話者を選択できません") message:NSLocalizedString(@"DefaultSpeakSetingEditTableViewCell_AlertCanNotSelectSpeakerSelection_message", @"iOS のバージョンが古いので話者の選択はできません。OS のバージョンを最新のものに変更してください。")];
        return;
    }
    NSArray* voiceArray = [NiftySpeaker getSupportedSpeaker:@"ja-JP"];
    if ([voiceArray count] <= 1) {
        [self.testSpeakDelegate showAlert:NSLocalizedString(@"DefaultSpeakSettingEditTableViewCell_AlertCanNotSelectSpeaker_title", @"話者を選択できません") message:NSLocalizedString(@"DefaultSpeakSetingEditTableViewCell_AlertCanNotSelectSpeaker_message", @"選択できる話者データが一つ以下です。\n設定アプリ→一般→アクセシビリティ→スピーチ→声→日本語\nと手繰っていった所で音声データをダウンロードしてから、もう一度お試しください。")];
        return;
    }
    
    NSString* targetIdentifier = [[GlobalDataSingleton GetInstance] GetVoiceIdentifier];
    AVSpeechSynthesisVoice* targetVoice = nil;
    NSMutableArray* displayTextList = [NSMutableArray new];
    for (AVSpeechSynthesisVoice* voice in voiceArray) {
        //NSLog(@"voice:%@ %@", voice.name, voice.identifier);
        [displayTextList addObject:voice.name];
        if ([voice.identifier compare:targetIdentifier] == NSOrderedSame) {
            targetVoice = voice;
        }
    }

    PickerViewDialog* dialog = [PickerViewDialog createNewDialog:displayTextList firstSelectedString:targetVoice != nil ? targetVoice.name : nil parentView:self resultReceiver:^(NSString* result){
        AVSpeechSynthesisVoice* selectedVoice = voiceArray[0];
        for (int i = 0; i < [displayTextList count]; i++) {
            if ([displayTextList[i] compare:result] == NSOrderedSame && [voiceArray count] >= i) {
                selectedVoice = voiceArray[i];
                break;
            }
        }
        
        GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
        [globalData SetVoiceIdentifier:selectedVoice.identifier];
        [globalData ReloadSpeechSetting];
        
        [NiftyUtility setUIButtonText:self.speakerNameButton text:selectedVoice.name];
    }];
    [dialog popup:nil];
}
@end

