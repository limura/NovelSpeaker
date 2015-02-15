//
//  CreateNewSpeakPitchSettingViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EasyAlert.h"

@protocol CreateNewSpeakPitchSettingDelegate <NSObject>

- (void)NewPitchSettingAdded;

@end

@interface CreateNewSpeakPitchSettingViewController : UIViewController
{
    BOOL m_isNeedBack;
    EasyAlert* m_EasyAlert;
}

@property (weak, nonatomic) IBOutlet UITextField *titleTextField;
@property (nonatomic) id<CreateNewSpeakPitchSettingDelegate> createNewSpeakPitchSettingDelegate;

@end
