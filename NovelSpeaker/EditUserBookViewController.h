//
//  EditUserBookViewController.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/07/31.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GlobalDataSingleton.h"
#import "EasyAlert.h"
#import "SZTextView.h"

@interface EditUserBookViewController : UIViewController<UIGestureRecognizerDelegate, UITextFieldDelegate>
{
    EasyAlert* m_pEasyAlert;
    int m_CurrentChapterNumber;
}
// シングルタップを取ってキーボードを閉じます
@property(nonatomic, strong) UITapGestureRecognizer *singleTap;

@property (weak, nonatomic) IBOutlet UITextField *TitleTextBox;
@property (weak, nonatomic) IBOutlet SZTextView *BookBodyTextBox;
@property (weak, nonatomic) IBOutlet UISlider *ChapterSlidebar;
@property (weak, nonatomic) IBOutlet UILabel *ChapterIndicatorLabel;
@property (weak, nonatomic) IBOutlet UIButton *AddChapterButton;
@property (weak, nonatomic) IBOutlet UIButton *DelChapterButton;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *BookBodyTextBoxBottomConstraint;

// 前のページから得られる表示するための情報
@property NarouContentCacheData* NarouContentDetail;

- (IBAction)EntryButtonClicked:(id)sender;
- (IBAction)PrevChapterButtonClicked:(id)sender;
- (IBAction)NextChapterButtonClicked:(id)sender;
- (IBAction)ChapterSlidebarValueChanged:(id)sender;
- (IBAction)AddChapterButtonClicked:(id)sender;
- (IBAction)DelChapterButtonClicked:(id)sender;
- (IBAction)uiTextFieldDidEndOnExit:(id)sender;
@end
