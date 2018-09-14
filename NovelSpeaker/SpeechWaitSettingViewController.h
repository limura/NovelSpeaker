//
//  SpeechWaitSettingViewController.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeechWaitConfigCacheData.h"
#import "EasyAlert.h"
#import "NiftySpeaker.h"

@interface SpeechWaitSettingViewController : UIViewController<UITextFieldDelegate, UIGestureRecognizerDelegate>
{
    EasyAlert* m_EasyAlert;
    NiftySpeaker* m_NiftySpeaker;
}
// シングルタップを取ってキーボードを閉じます
@property(nonatomic, strong) UITapGestureRecognizer *singleTap;
// 前のページから受け取る情報
@property SpeechWaitConfigCacheData* speechWaitConfigCacheData;
@property (weak, nonatomic) IBOutlet UITextField *inputTextField;
@property (weak, nonatomic) IBOutlet UIButton *commitButton;
- (IBAction)commitButtonClicked:(id)sender;
@property (weak, nonatomic) IBOutlet UISlider *waitTimeSlider;
- (IBAction)WaitTimeSliderLeftButtonClicked:(id)sender;
- (IBAction)WaitTimeSliderRightButtonClicked:(id)sender;
@property (weak, nonatomic) IBOutlet UITextField *SampleSpeechTextField;
- (IBAction)SampleSpeechButtonClicked:(id)sender;
- (IBAction)inputTextFieldChanged:(id)sender;
- (IBAction)textFieldDidEndOnExit:(id)sender;

@end
