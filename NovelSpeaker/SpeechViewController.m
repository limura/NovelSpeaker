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
    
    // 読み上げる文章を設定します。
    if([self ChangeChapter:1] != true)
    {
        [self setSpeechText:@"読み込みに失敗しました。" range:NSMakeRange(0,0)];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)RightSwipe:(UISwipeGestureRecognizer *)sender
{
    [self ChangeChapter:m_CurrentChapter-1];
}
- (void)LeftSwipe:(UISwipeGestureRecognizer *)sender
{
    [self ChangeChapter:m_CurrentChapter+1];
}

/// 読み上げる文章の章を変更します
- (BOOL)ChangeChapter:(int)chapter
{
    if (chapter <= 0 || chapter > [self.NarouContentDetail.general_all_no intValue]) {
        NSLog(@"chapter に不正な値(%d)が指定されました。(1 から %@ の間である必要があります)", chapter, self.NarouContentDetail.general_all_no);
        return false;
    }
    
    Story* story = [[GlobalDataSingleton GetInstance] SearchStory:self.NarouContentDetail.ncode chapter_no:chapter];
    if (story == nil || story.content == nil || [story.content length] <= 0) {
        return false;
    }
    [self setSpeechText:story.content range:NSMakeRange(0, 0)];
    m_CurrentChapter = chapter;
    return true;
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

    GlobalState* globalState = [[GlobalDataSingleton GetInstance] GetGlobalState];
    [m_SpeechTextBox SetPitch:[globalState.defaultPitch floatValue]];
    [m_SpeechTextBox SetRate:[globalState.defaultRate floatValue]];
    [m_SpeechTextBox StartSpeech];
}

/// 読み上げを停止します
- (void)stopSpeech{
    [m_SpeechTextBox StopSpeech];
    startStopButton.title = @"Speak";
}

/// 読み上げ用の文字列を設定します。
/// 読み上げ中の場合は読み上げは停止されます。
/// 読み上げられるのは text で、range で指定されている点を読み上げ開始点として読み上げを開始します。
- (void)setSpeechText:(NSString*)text range:(NSRange)range {
    [self stopSpeech];
    [self.textView setText:text];
    self.textView.selectedRange = range;
    [m_SpeechTextBox SetText:text];
}

- (void)detailButtonClick:(id)sender {    
    [self performSegueWithIdentifier:@"speechToDetailSegue" sender:self];
}

- (void)startStopButtonClick:(id)sender {
    if([startStopButton.title compare:@"Speak"] == NSOrderedSame)
    {
        // 停止中だったので読み上げを開始します
        [self startSpeech];
    }
    else
    {
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


@end
