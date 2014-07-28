//
//  ViewController.h
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "Speaker.h"
#import "SpeechTextBox.h"
#import "NarouContentCacheData.h"
#import "StoryCacheData.h"

@interface SpeechViewController : UIViewController<SpeakTextBoxDelegate>
{
    NSInteger m_SpeechStartPosition;
    SpeechTextBox* m_SpeechTextBox;
    UIBarButtonItem* startStopButton;
    UIBarButtonItem* detailButton;
    int m_CurrentChapter;
    StoryCacheData* m_CurrentReadingStory;
    BOOL m_bIsSpeaking;
}
@property (weak, nonatomic) IBOutlet UISlider *ChapterSlider;
@property (weak, nonatomic) IBOutlet UITextView *textView;

// 前のページから得られる表示するための情報
@property NarouContentCacheData* NarouContentDetail;

- (IBAction)ChapterSliderChanged:(UISlider *)sender;
@end
