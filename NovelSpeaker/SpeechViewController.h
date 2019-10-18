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
#import "NarouDownloadQueue.h"
#import "NovelSpeaker-Swift.h"

@interface SpeechViewController : UIViewController<SpeakRangeDelegate, UITextViewDelegate, NarouDownloadQueueDelegate>
{
    NSInteger m_SpeechStartPosition;
    UIBarButtonItem* startStopButton;
    UIBarButtonItem* detailButton;
    UIBarButtonItem* shareButton;
    int m_CurrentChapter;
    StoryCacheData* m_CurrentReadingStory;
    BOOL m_bIsSpeaking;
    BOOL m_bIsSeeking;
    NSTimer* m_SeekTimer;
    DuplicateSoundPlayer* m_PageTurningSoundPlayer;
}
@property (weak, nonatomic) IBOutlet UISlider *ChapterSlider;
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UIButton *NextChapterButton;

@property (weak, nonatomic) IBOutlet UIButton *PrevChapterButton;
@property (weak, nonatomic) IBOutlet UILabel *ChapterIndicatorLabel;

// 前のページから得られる表示するための情報
@property NarouContentCacheData* NarouContentDetail;
// 開いた時に読み上げを再開するか否か
@property BOOL NeedResumeSpeech;

- (IBAction)ChapterSliderChanged:(UISlider *)sender;

- (UIStatusBarStyle)preferredStatusBarStyle;
@end
