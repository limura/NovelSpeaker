//
//  ViewController.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <CoreData/CoreData.h>
#import "SpeechViewController.h"
#import "Story.h"
#import "NarouContent.h"
#import "GlobalDataSingleton.h"
#import "NarouSearchResultDetailViewController.h"

@interface SpeechViewController ()

@end

@implementation SpeechViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [[GlobalDataSingleton GetInstance] AddSpeakRangeDelegate:self];
    
    // NavitationBar にボタンを配置します。
    startStopButton = [[UIBarButtonItem alloc] initWithTitle:@"Speak" style:UIBarButtonItemStyleBordered target:self action:@selector(startStopButtonClick:)];
    detailButton = [[UIBarButtonItem alloc] initWithTitle:@"詳細" style:UIBarButtonItemStyleBordered target:self action:@selector(detailButtonClick:)];
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:startStopButton, detailButton, nil];
    self.navigationItem.title = self.NarouContentDetail.title;
    
    // 左右のスワイプを設定してみます。
    UISwipeGestureRecognizer* rightSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(RightSwipe:)];
    rightSwipe.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:rightSwipe];
    UISwipeGestureRecognizer* leftSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(LeftSwipe:)];
    leftSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:leftSwipe];
    
    self.ChapterSlider.minimumValue = 1;
    self.ChapterSlider.maximumValue = [self.NarouContentDetail.general_all_no floatValue] - 0.5f;
    
    // 読み上げる文章を設定します。
    [self SetCurrentReadingPointFromSavedData:self.NarouContentDetail];
    
    m_bIsSpeaking = NO;
}

- (void)dealloc
{
    [[GlobalDataSingleton GetInstance] DeleteSpeakRangeDelegate:self];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self resignFirstResponder];
    
    [super viewWillDisappear:animated];
}

/// 読み込みに失敗した旨を表示します。
- (void)SetReadingPointFailedMessage
{
    StoryCacheData* story = [StoryCacheData new];
    story.content = @"文書の読み込みに失敗しました。";
    story.readLocation = 0;
    [self setSpeechStory:story];
}

/// 保存されている読み上げ位置を元に、現在の文書を設定します。
- (BOOL)SetCurrentReadingPointFromSavedData:(NarouContentCacheData*)content
{
    if (content == nil) {
        [self SetReadingPointFailedMessage];
        return false;
    }
    StoryCacheData* story = [[GlobalDataSingleton GetInstance] GetReadingChapter:content];
    if (story == nil) {
        // なにやら設定されていないようなので、最初の章を読み込むことにします。
        story = [[GlobalDataSingleton GetInstance] SearchStory:content.ncode chapter_no:1];
        if (story == nil) {
            [self SetReadingPointFailedMessage];
            return false;
        }
    }
    NSLog(@"set currentreading story: %@ (content: %@ %@) location: %lu", story.ncode, content.ncode, content.title, [story.readLocation unsignedLongValue]);
    [self setSpeechStory:story];
    return true;
}

/// 現在の読み込み位置を保存します。
- (void)SaveCurrentReadingPoint
{
    if (m_CurrentReadingStory == nil) {
        return;
    }
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    m_CurrentReadingStory.readLocation = [[NSNumber alloc] initWithUnsignedLong:self.textView.selectedRange.location];
    NSLog(@"update read location %lu (%@)", [m_CurrentReadingStory.readLocation unsignedLongValue], m_CurrentReadingStory.ncode);
    [globalData ReadingPointUpdate:self.NarouContentDetail story:m_CurrentReadingStory];
    [globalData saveContext];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    [self SaveCurrentReadingPoint];
}

- (BOOL)SetPreviousChapter
{
    [self stopSpeech];
    StoryCacheData* story = [[GlobalDataSingleton GetInstance] GetPreviousChapter:m_CurrentReadingStory];
    if (story == nil) {
        return false;
    }
    story.readLocation = [[NSNumber alloc] initWithInt:0];
    [self UpdateCurrentReadingStory:story];
    [self SaveCurrentReadingPoint];
    return true;
}

- (BOOL)SetNextChapter
{
    [self stopSpeech];
    StoryCacheData* story = [[GlobalDataSingleton GetInstance] GetNextChapter:m_CurrentReadingStory];
    if (story == nil) {
        return false;
    }
    story.readLocation = [[NSNumber alloc] initWithInt:0];
    [self UpdateCurrentReadingStory:story];
    [self SaveCurrentReadingPoint];
    return true;
}

- (void)RightSwipe:(UISwipeGestureRecognizer *)sender
{
    [self SetPreviousChapter];
}
- (void)LeftSwipe:(UISwipeGestureRecognizer *)sender
{
    [self SetNextChapter];
}

/// 読み上げる文章の章を変更します。
- (BOOL)UpdateCurrentReadingStory:(StoryCacheData*)story
{
    if (story == nil || story.content == nil || [story.content length] <= 0) {
        [self SetReadingPointFailedMessage];
        return false;
    }
    if ([story.content length] < [story.readLocation intValue])
    {
        NSLog(@"Story に保存されている読み込み位置(%d)が Story の長さ(%lu)を超えています。0 に上書きします。", [story.readLocation intValue], (unsigned long)[story.content length]);
        story.readLocation = [[NSNumber alloc] initWithInt:0];
    }

    [self setSpeechStory:story];
    self.ChapterSlider.value = [story.chapter_number floatValue];
    m_CurrentReadingStory = story;
    return true;
}

/// 読み上げる文章の章を変更します(chapter指定版)
- (BOOL)ChangeChapterWithLastestReadLocation:(int)chapter
{
    if (chapter <= 0 || chapter > [self.NarouContentDetail.general_all_no intValue]) {
        NSLog(@"chapter に不正な値(%d)が指定されました。(1 から %@ の間である必要があります)指定された値は無視して 1 が指定されたものとして動作します。", chapter, self.NarouContentDetail.general_all_no);
        chapter = 1;
    }
    
    StoryCacheData* story = [[GlobalDataSingleton GetInstance] SearchStory:self.NarouContentDetail.ncode chapter_no:chapter];
    return [self UpdateCurrentReadingStory:story];
}

/// 読み上げを開始します。
/// 読み上げ開始点(選択範囲)がなければ一番最初から読み上げを開始することにします
- (void)startSpeech {
    // 選択範囲を表示するようにします。
    [self.textView becomeFirstResponder];
    
    // 読み上げ位置を設定します
    NSRange range = self.textView.selectedRange;
    [[GlobalDataSingleton GetInstance] SetSpeechRange:range];
    [self SaveCurrentReadingPoint];

    // 読み上げ開始位置以降の文字列について、読み上げを開始します。
    startStopButton.title = @"Stop";
    
    // 読み上げを開始します
    [[GlobalDataSingleton GetInstance] StartSpeech];
}

/// 読み上げを停止します
- (void)stopSpeech{
    [[GlobalDataSingleton GetInstance] StopSpeech];

    startStopButton.title = @"Speak";
    [self SaveCurrentReadingPoint];
}

/// 読み上げ用の文字列を設定します。
/// 読み上げ中の場合は読み上げは停止されます。
/// 読み上げられるのは text で、range で指定されている点を読み上げ開始点として読み上げを開始します。
- (void)setSpeechStory:(StoryCacheData*)story {
    [self stopSpeech];
    [self.textView setText:story.content];
    NSRange range = NSMakeRange([story.readLocation unsignedLongValue], 0);
    self.textView.selectedRange = range;
    [self.textView scrollRangeToVisible:range];
    self.ChapterSlider.value = [story.chapter_number floatValue];
    m_CurrentReadingStory = story;
    [[GlobalDataSingleton GetInstance] SetSpeechStory:story];
}

- (void)detailButtonClick:(id)sender {    
    [self performSegueWithIdentifier:@"speechToDetailSegue" sender:self];
}

- (void)startStopButtonClick:(id)sender {
    if([startStopButton.title compare:@"Speak"] == NSOrderedSame)
    {
        // 停止中だったので読み上げを開始します
        m_bIsSpeaking = YES;
        [self startSpeech];
    }
    else
    {
        m_bIsSpeaking = NO;
        [self stopSpeech];
    }
}

#pragma mark - Navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // 次のビューをloadする前に呼び出してくれるらしいので、そこで検索結果を放り込みます。
    if ([[segue identifier] isEqualToString:@"speechToDetailSegue"]) {
        NarouSearchResultDetailViewController* nextViewController = [segue destinationViewController];
        nextViewController.NarouContentDetail = self.NarouContentDetail;
    }
}

// スライダーが変更されたとき。
- (IBAction)ChapterSliderChanged:(UISlider *)sender {
    [self stopSpeech];
    int chapter = self.ChapterSlider.value;
    if([self ChangeChapterWithLastestReadLocation:chapter] != true)
    {
        [self SetReadingPointFailedMessage];
    }
}

// SpeachTextBox が読み終わった時
- (void)SpeakTextBoxFinishSpeak
{
    if ([self SetNextChapter] != true) {
        return;
    }
    [self startSpeech];
}

/// 読み上げ位置が更新されたとき
- (void) willSpeakRange:(NSRange)range speakText:(NSString*)text
{
    self.textView.selectedRange = range;
    [self.textView scrollRangeToVisible:range];
}

/// 読み上げが停止したとき
- (void) finishSpeak
{
    if ([self SetNextChapter]) {
        [self startSpeech];
    }
}

/// リモートコントロールされたとき
- (void) remoteControlReceivedWithEvent: (UIEvent*)receivedEvent
{
    NSLog(@"event got.");
    if (receivedEvent.type != UIEventTypeRemoteControl)
    {
        return;
    }
    
    switch (receivedEvent.subtype) {
        case UIEventSubtypeRemoteControlPlay:
            //NSLog(@"event: play");
            //[self startSpeech];
            //break;
        case UIEventSubtypeRemoteControlPause:
            //NSLog(@"event: pause");
            //[self stopSpeech];
            //break;
        case UIEventSubtypeRemoteControlTogglePlayPause:
            NSLog(@"event: toggle");
            if ([[GlobalDataSingleton GetInstance] isSpeaking]) {
                [self stopSpeech];
            }else{
                [self startSpeech];
            }
            break;
                
        case UIEventSubtypeRemoteControlPreviousTrack:
            NSLog(@"event: prev");
            [self stopSpeech];
            if ([self SetPreviousChapter]) {
                [self startSpeech];
            }
            break;
                
        case UIEventSubtypeRemoteControlNextTrack:
            NSLog(@"event: next");
            [self stopSpeech];
            if ([self SetNextChapter]) {
                [self startSpeech];
            }
            break;
        default:
            break;
    }
}
@end
