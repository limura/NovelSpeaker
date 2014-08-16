//
//  CreateNewSpeakPitchSettingViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol CreateNewSpeakPitchSettingDelegate <NSObject>

- (void)NewPitchSettingAdded;

@end

@interface CreateNewSpeakPitchSettingViewController : UIViewController<UIAlertViewDelegate>
{
    BOOL m_isNeedBack;
}

@property (weak, nonatomic) IBOutlet UITextField *titleTextField;
@property (nonatomic) id<CreateNewSpeakPitchSettingDelegate> createNewSpeakPitchSettingDelegate;

@end
