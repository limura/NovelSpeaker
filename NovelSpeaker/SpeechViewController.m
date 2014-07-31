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
    
    
    m_SpeechTextBox = [[SpeechTextBox alloc] init];
    m_SpeechTextBox.textView = self.textView;

    [m_SpeechTextBox SetDelay: 0.001];
    [m_SpeechTextBox AddPitchSetting:@"」$" pitch:1.5f];
    [m_SpeechTextBox AddPitchSetting:@"』$" pitch:1.5f];
    [m_SpeechTextBox AddPitchSetting:@"^「" pitch:1.5f];
    [m_SpeechTextBox AddPitchSetting:@"^『" pitch:1.5f];
    [m_SpeechTextBox AddDelegate:self];
    
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

/// 読み込みに失敗した旨を表示します。
- (void)SetReadingPointFailedMessage
{
    [self setSpeechText:@"読み込みに失敗しました。" range:NSMakeRange(0,0)];
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
        [self SetReadingPointFailedMessage];
        return false;
    }
    NSLog(@"set currentreading story: %@ (content: %@ %@)", story.ncode, content.ncode, content.title);
    m_CurrentReadingStory = story;
    return [self UpdateCurrentReadingStory:m_CurrentReadingStory];
}

/// 現在の読み込み位置を保存します。
- (void)SaveCurrentReadingPoint
{
    if (m_CurrentReadingStory == nil) {
        return;
    }
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    m_CurrentReadingStory.readLocation = [[NSNumber alloc] initWithUnsignedLong:self.textView.selectedRange.location];
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

    [self setSpeechText:story.content range:NSMakeRange([story.readLocation intValue], 0)];
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
    
    // 読み上げ位置を m_SpeechTextBox に指示します
    NSRange range = self.textView.selectedRange;
    [m_SpeechTextBox SetSpeechStartPoint:range];

    // 読み上げ開始位置以降の文字列について、読み上げを開始します。
    startStopButton.title = @"Stop";

    GlobalStateCacheData* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    [m_SpeechTextBox SetPitch:[globalState.defaultPitch floatValue]];
    [m_SpeechTextBox SetRate:[globalState.defaultRate floatValue]];
    [m_SpeechTextBox StartSpeech];
    [self SaveCurrentReadingPoint];
    
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setActive:true error:nil];
}

/// 読み上げを停止します
- (void)stopSpeech{
    if (m_bIsSpeaking == NO) {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        [session setActive:false error:nil];
    }

    [m_SpeechTextBox StopSpeech];
    startStopButton.title = @"Speak";
    [self SaveCurrentReadingPoint];
}

/// 読み上げ用の文字列を設定します。
/// 読み上げ中の場合は読み上げは停止されます。
/// 読み上げられるのは text で、range で指定されている点を読み上げ開始点として読み上げを開始します。
- (void)setSpeechText:(NSString*)text range:(NSRange)range {
    [self stopSpeech];
    [self.textView setText:text];
    self.textView.selectedRange = range;
    [m_SpeechTextBox SetText:text];
    [m_SpeechTextBox SetSpeechStartPoint:range];
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

/// 長い文字列を読み上げ時の読み上げやすい長さに分割した NSArray に変換します。
- (NSArray*)SplitSpeakText:(NSString*)text {
    NSArray* result = [text componentsSeparatedByString:@"\r\n"];
    return result;
}

#pragma mark - Navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSLog(@"next view load!");
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
        [self setSpeechText:@"読み込みに失敗しました。" range:NSMakeRange(0,0)];
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
@end
