//
//  CreateSpeechModSettingViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Speaker.h"
@protocol CreateNewSpeechModSettingDelegate <NSObject>

- (void)NewSpeechModSettingAdded;

@end

@interface CreateSpeechModSettingViewController : UIViewController
{
    Speaker* m_Speaker;
}
@property (weak, nonatomic) IBOutlet UITextField *beforeTextField;
@property (weak, nonatomic) IBOutlet UITextField *afterTextField;
@property (nonatomic) id<CreateNewSpeechModSettingDelegate> createNewSpeechModSettingDelegate;
@end
