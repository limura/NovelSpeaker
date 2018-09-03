//
//  CreateSpeechModSettingViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Speaker.h"
#import "EasyAlert.h"
@protocol CreateNewSpeechModSettingDelegate <NSObject>

- (void)NewSpeechModSettingAdded;

@end

@interface CreateSpeechModSettingViewController : UIViewController
{
    Speaker* m_Speaker;
    EasyAlert* m_EasyAlert;
}
@property (weak, nonatomic) IBOutlet UITextField *beforeTextField;
@property (weak, nonatomic) IBOutlet UITextField *afterTextField;
@property (nonatomic, weak) id<CreateNewSpeechModSettingDelegate> createNewSpeechModSettingDelegate;
@property NSString *targetBeforeString;
@property (weak, nonatomic) IBOutlet UISwitch *regexpSwitch;
@property (weak, nonatomic) IBOutlet UITextField *prevConvertTextField;
@property (weak, nonatomic) IBOutlet UITextField *afterConvertTextField;
@end
