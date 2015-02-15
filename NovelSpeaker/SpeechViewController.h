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
#import "NarouContentCacheData.h"
#import "StoryCacheData.h"

@interface SpeechViewController : UIViewController<SpeakRangeDelegate, UITextViewDelegate>
{
    NSInteger m_SpeechStartPosition;
    UIBarButtonItem* startStopButton;
    UIBarButtonItem* detailButton;
    UIBarButtonItem* shareButton;
    int m_CurrentChapter;
    StoryCacheData* m_CurrentReadingStory;
    BOOL m_bIsSpeaking;
}
@property (weak, nonatomic) IBOutlet UISlider *ChapterSlider;
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UIButton *NextChapterButton;

@property (weak, nonatomic) IBOutlet UIButton *PrevChapterButton;

// 前のページから得られる表示するための情報
@property NarouContentCacheData* NarouContentDetail;

- (IBAction)ChapterSliderChanged:(UISlider *)sender;
@end
