//
//  ViewController.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <CoreData/CoreData.h>
#import <Social/Social.h>
#import "SpeechViewController.h"
#import "Story.h"
#import "NarouContent.h"
#import "GlobalDataSingleton.h"
#import "NarouSearchResultDetailViewController.h"
#import "EasyShare.h"
#import "EasyAlert.h"
#import "CreateSpeechModSettingViewController.h"
#import "EditUserBookViewController.h"

@interface SpeechViewController ()

@end

@implementation SpeechViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    //[[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"SpeechViewController viewDidLoad %@, reading_chapter: %d, currentReadingStory: %p", self.NarouContentDetail.title, [self.NarouContentDetail.reading_chapter intValue], self.NarouContentDetail.currentReadingStory]]; // NSLog
    
    [[GlobalDataSingleton GetInstance] AddSpeakRangeDelegate:self];
    
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
    
    // NavitationBar にボタンを配置します。
    NSString* speakText = NSLocalizedString(@"SpeechViewController_Speak", @"Speak");
    if ([[GlobalDataSingleton GetInstance] isSpeaking]) {
        speakText = NSLocalizedString(@"SpeechViewController_Stop", @"Stop");
    }
    NSMutableArray* buttonItemList = [NSMutableArray new];
    startStopButton = [[UIBarButtonItem alloc] initWithTitle:speakText style:UIBarButtonItemStylePlain target:self action:@selector(startStopButtonClick:)];
    [buttonItemList addObject:startStopButton];
    
    NSString* detailText;
    if ([self.NarouContentDetail isUserCreatedContent]) {
        detailText = NSLocalizedString(@"SpeechViewController_Edit", @"編集");
    }else{
        detailText = NSLocalizedString(@"SpeechViewController_Detail", @"詳細");
    }
    detailButton = [[UIBarButtonItem alloc] initWithTitle:detailText style:UIBarButtonItemStylePlain target:self action:@selector(detailButtonClick:)];
    [buttonItemList addObject:detailButton];
    if ([self.NarouContentDetail isUserCreatedContent] != true) {
        shareButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareButtonClicked:)];
        [buttonItemList addObject:shareButton];
    }
    self.navigationItem.rightBarButtonItems = buttonItemList;
    self.navigationItem.title = self.NarouContentDetail.title;

#if 0 // ボタンで章を移動するようにします。
    // 左右のスワイプを設定してみます。
    UISwipeGestureRecognizer* rightSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(RightSwipe:)];
    rightSwipe.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:rightSwipe];
    UISwipeGestureRecognizer* leftSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(LeftSwipe:)];
    leftSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:leftSwipe];
#endif

    [self updateChapterSlider];

    // フォントサイズを設定された値に変更します。
    [self loadAndSetFontSize];
    
    // フォントサイズ変更イベントを受け取るようにします。
    [self setNotificationReciver];

    // 読み上げ設定をloadします。
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData ReloadSpeechSetting];
    // 読み上げる文章を設定します。
    [self SetCurrentReadingPointFromSavedData:self.NarouContentDetail];
    
    // textView で選択範囲が変えられた時のイベントハンドラに自分を登録します
    self.textView.delegate = self;

    // 読み替え辞書への直接登録メニューを追加します
    UIMenuController* menuController = [UIMenuController sharedMenuController];
    UIMenuItem* speechModMenuItem = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"SpeechViewController_AddSpeechModSettings", @"読み替え辞書へ登録") action:@selector(setSpeechModSetting:)];
    [menuController setMenuItems:@[speechModMenuItem]];
    
    m_bIsSpeaking = NO;
}

- (void)dealloc
{
    [self removeNotificationReciver];
    [self SaveCurrentReadingPoint];
    [[GlobalDataSingleton GetInstance] DeleteSpeakRangeDelegate:self];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    //[[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"SpeechViewController viewDidAppear %@", self.NarouContentDetail.title]]; // NSLog

    // なにやら登録が外れる事があるようなので、AddSpeakRangeDelegate をこのタイミングでも呼んでおきます。
    // AddSpeakRangeDelegate は複数回呼んでも大丈夫なように作ってあるはずです
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    //[self SetCurrentReadingPointFromSavedData:self.NarouContentDetail];
    [globalData AddSpeakRangeDelegate:self];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self.textView becomeFirstResponder];
    
    // 読み上げる文章を改めて設定したいです
    // が、読み上げ中である場合には現在保存されている情報は古いため、
    // 読み上げを停止→現在の読み上げ位置を保存→読み上げ文章を改めてロード
    // という手順を踏む必要があります。
    if ([globalData isSpeaking]) {
        // [self stopSpeech] を呼んでしまうと、現在表示されているもので読み上げ位置を更新してしまうため、
        // globalData 側の StopSpeech を呼び出します。この時、globalData側 で読み上げ位置を保存していますので改めて保存の必要はありません。
        [globalData StopSpeech];
    }
    // 読み上げ位置の更新がDB本体に保存されるまで待って、読み上げ位置を改めて設定します
    // (間髪入れずに読み出そうとすると保存されていない古い情報を読む可能性が少しだけあるはずです)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self SetCurrentReadingPointFromSavedData:self.NarouContentDetail];
    });
    
    // 読み上げ中かどうかが画面が表示されていない時に更新される場合があるので、表示を更新しておきます。
    if ([globalData isSpeaking]) {
        startStopButton.title = NSLocalizedString(@"SpeechViewController_Stop", @"Stop");
    }else{
        startStopButton.title = NSLocalizedString(@"SpeechViewController_Speak", @"Speak");
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    [self resignFirstResponder];
    [self SaveCurrentReadingPoint];
    
    [super viewWillDisappear:animated];
}

/// 現在選択されている文字列を取得します
- (NSString*) GetCurrentSelectedString {
    UITextRange* range = [self.textView selectedTextRange];
    if ([range isEmpty]){
        return nil;
    }
    return [self.textView textInRange:range];
}

/// 読み替え辞書への登録イベントハンドラ
- (void) setSpeechModSetting:(id)sender {
    [self performSegueWithIdentifier:@"SpeechViewToSpeechModSetingsSegue" sender:self];
}


/// UITextField でカーソルの位置が変わった時に呼び出されるはずです。
- (void) textViewDidChangeSelection: (UITextView*) textView
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    if ([globalData isSpeaking]) {
        // 話し中であればこれはバンバン呼び出されるはずだし、勝手に NiftySpeaker側 で読み上げ位置の更新をしているはずなので無視して良いです。
        return;
    }
    NSRange range = self.textView.selectedRange;
    // 何故か起動時に表示範囲外の textViewDidChangeSelection が飛んでくるのでそれは無視するようにします。
    if (range.location >= [textView.text length]) {
        return;
    }
    //[[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"長押しにより読み上げ位置を更新します。%@ %ld %ld", self.NarouContentDetail.title, (unsigned long)range.location(unsigned long), [textView.text length]]]; // NSLog
    m_CurrentReadingStory.readLocation = [[NSNumber alloc] initWithUnsignedLong:range.location];
    [self SaveCurrentReadingPoint];
}

/// 読み込みに失敗した旨を表示します。
- (void)SetReadingPointFailedMessage
{
    StoryCacheData* story = [StoryCacheData new];
    story.content = NSLocalizedString(@"SpeechViewController_ContentReadFailed", @"文書の読み込みに失敗しました。");
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        // 自分の content.currentReadingStory は昔のcacheなので現在の値を読み直します
        StoryCacheData* story = [[GlobalDataSingleton GetInstance] GetReadingChapter:content];
        if (story == nil) {
            // なにやら設定されていないようなので、最初の章を読み込むことにします。
            // TODO: XXXX: 最新情報に更新した後にここに何故か来る事があるのをなんとかする
            [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"SpeechViewController なにやら読み上げ用の章が設定されていないようなので、最初の章を読み込みます"]]; // NSLog
            story = [[GlobalDataSingleton GetInstance] SearchStory:content.ncode chapter_no:1];
            if (story == nil) {
                [self SetReadingPointFailedMessage];
                return;
            }
        }
        //NSLog(@"set currentreading story: %@ (content: %@ %@) location: %lu", story.chapter_number, content.ncode, content.title, [story.readLocation unsignedLongValue]);
        //EasyAlertActionHolder* holder = [m_EasyAlert ShowAlert:nil message:NSLocalizedString(@"SpeechViewController_loading", @"loading...")];
        [self setSpeechStory:story];
        //[holder CloseAlert:false];
    });
   
    return true;
}

/// 現在の読み込み位置を保存します。
- (void)SaveCurrentReadingPoint
{
    if (m_CurrentReadingStory == nil) {
        return;
    }
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    NSUInteger location = self.textView.selectedRange.location;
    //NSLog(@"self.textView.selectedRange.location: %lu", (unsigned long)location);
    if (location <= 0) {
        NSRange readingRange = [globalData GetCurrentReadingPoint];
        location = readingRange.location;
    }
    m_CurrentReadingStory.readLocation = [[NSNumber alloc] initWithUnsignedLong:location];
    [globalData UpdateReadingPoint:self.NarouContentDetail story:m_CurrentReadingStory];
    [globalData saveContext];
}

- (NSRange)LoadCurrentReadingPoint
{
    if (m_CurrentReadingStory == nil) {
        return NSMakeRange(0, 0);
    }
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    StoryCacheData* story = [globalData SearchStory:m_CurrentReadingStory.ncode chapter_no:[m_CurrentReadingStory.chapter_number intValue]];
    if (story == nil) {
        return NSMakeRange(0, 0);
    }
    return NSMakeRange([story.readLocation unsignedIntegerValue], 0);
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    //[self SaveCurrentReadingPoint];
}

- (BOOL)SetPreviousChapter
{
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
    [self stopSpeech];
    [self SetPreviousChapter];
}
- (void)LeftSwipe:(UISwipeGestureRecognizer *)sender
{
    [self stopSpeech];
    [self SetNextChapter];
}

/// 読み上げる文章の章を変更します。
- (BOOL)UpdateCurrentReadingStory:(StoryCacheData*)story
{
    if (story == nil || story.content == nil || [story.content length] <= 0) {
        [self SetReadingPointFailedMessage];
        self.PrevChapterButton.enabled = false;
        self.NextChapterButton.enabled = false;
        return false;
    }
    if ([story.content length] < [story.readLocation intValue])
    {
        [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"SpeechViewController: Story に保存されている読み込み位置(%d)が Story の長さ(%lu)を超えています。0 に上書きします。", [story.readLocation intValue], (unsigned long)[story.content length]]]; // NSLog

        //NSLog(@"Story に保存されている読み込み位置(%d)が Story の長さ(%lu)を超えています。0 に上書きします。", [story.readLocation intValue], (unsigned long)[story.content length]);
        story.readLocation = [[NSNumber alloc] initWithInt:0];
    }


    if ([story.chapter_number intValue] <= 0) {
        self.PrevChapterButton.enabled = false;
    }else{
        self.PrevChapterButton.enabled = true;
    }
    self.NextChapterButton.enabled = true;
    
    [self setSpeechStory:story];
    self.ChapterSlider.value = [story.chapter_number floatValue];
    m_CurrentReadingStory = story;
    return true;
}

/// 読み上げる文章の章を変更します(chapter指定版)
- (BOOL)ChangeChapterWithLastestReadLocation:(int)chapter
{
    if (chapter <= 0 || chapter > [self.NarouContentDetail.general_all_no intValue]) {
        [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"SpeechViewController: chapter に不正な値(%d)が指定されました。(1 から %@ の間である必要があります)指定された値は無視して 1 が指定されたものとして動作します。", chapter, self.NarouContentDetail.general_all_no]]; // NSLog
        //NSLog(@"chapter に不正な値(%d)が指定されました。(1 から %@ の間である必要があります)指定された値は無視して 1 が指定されたものとして動作します。", chapter, self.NarouContentDetail.general_all_no);
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
#if 0 // 読み上げ位置を textView から取ってくると、textView が消えている事があって、selectedRange が 0,0 を返す事があるので信用しないことにします
    NSRange range = self.textView.selectedRange;
    [[GlobalDataSingleton GetInstance] SetSpeechRange:range];
    NSLog(@"SaveCurrentReadingPoint: %@", __func__);
    [self SaveCurrentReadingPoint];
#else // 今は textViewDidChangeSelection でセレクションが移動した時のイベントをとっていて、読み上げ中でなければそちらで読み上げ位置を移動したのを保存するようにしているので、GlobalData側 が読み上げ位置の管理を行っています。ということで GlobalData から読み上げ位置を読み出すことにします。
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData SetSpeechRange:[self LoadCurrentReadingPoint]];
#endif

    // 読み上げ開始位置以降の文字列について、読み上げを開始します。
    startStopButton.title = NSLocalizedString(@"SpeechViewController_Stop", @"Stop");
    
    // 読み上げを開始します
    [[GlobalDataSingleton GetInstance] StartSpeech];
}

/// 読み上げを「バックグラウンド再生としては止めずに」読み上げ部分だけ停止します
- (void)stopSpeechWithoutDiactivate{
    [[GlobalDataSingleton GetInstance] StopSpeechWithoutDiactivate];
    
    startStopButton.title = NSLocalizedString(@"SpeechViewController_Speak", @"Speak");
    [self SaveCurrentReadingPoint];
}

/// 読み上げを停止します
- (void)stopSpeech{
    [[GlobalDataSingleton GetInstance] StopSpeech];

    startStopButton.title = NSLocalizedString(@"SpeechViewController_Speak", @"Speak");
    [self SaveCurrentReadingPoint];
}

- (void)UpdateChapterIndicatorLabel:(int)current max:(int)max
{
    self.ChapterIndicatorLabel.text = [[NSString alloc] initWithFormat:@"%d/%d", current, max];
}

/// 読み上げ用の文字列を設定します。
/// 読み上げ中の場合は読み上げは停止されます。
/// 読み上げられるのは text で、range で指定されている点を読み上げ開始点として読み上げを開始します。
- (void)setSpeechStory:(StoryCacheData*)story {
    //[self stopSpeech];
    NSString* displayText = [[GlobalDataSingleton GetInstance] ConvertStoryContentToDisplayText:story];
    if (displayText == nil || [displayText length] <= 0) {
        displayText = NSLocalizedString(@"SpeechViewController_ContentReadFailed", @"文書の読み込みに失敗しました。「詳細」→「Download」を選択して再ダウンロードすることで解消するかもしれません。");
    }
    [self.textView setText:displayText];
    NSUInteger location = [story.readLocation unsignedLongValue];
    NSUInteger length = 1;
    if ((location + length) > [displayText length]) {
        location -= 1;
    }
    NSRange range = NSMakeRange(location, length);
    self.textView.selectedRange = range;
    [self.textView scrollRangeToVisible:range];
    self.ChapterSlider.value = [story.chapter_number floatValue];
    [self UpdateChapterIndicatorLabel:[story.chapter_number intValue] max:(int)self.ChapterSlider.maximumValue];
    m_CurrentReadingStory = story;
    [[GlobalDataSingleton GetInstance] SetSpeechStory:story];
    
    // TextView は使いまわされた時、selectedRange が前の値のままのようなので、このタイミングでTextView上の読み上げ位置を上書きします
    int readLocation = [story.readLocation intValue];
    if ([self.textView.text length] <= location) {
        readLocation = (int)[self.textView.text length] - 1;
        if (readLocation < 0) {
            readLocation = 0;
        }
    }
    self.textView.selectedRange = NSMakeRange(readLocation, 1);
}

- (void)detailButtonClick:(id)sender {
    if ([self.NarouContentDetail isUserCreatedContent]) {
        [self performSegueWithIdentifier:@"EditUserTextSegue" sender:self];
        return;
    }
    [self performSegueWithIdentifier:@"speechToDetailSegue" sender:self];
}

- (void)shareButtonClicked:(id)sender {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:m_CurrentReadingStory.ncode];
    if (content == nil) {
        return;
    }
    NSString* message = [NSString stringWithFormat:NSLocalizedString(@"SpeechViewController_TweetMessage", @"%@ %@ #narou #ことせかい %@ %@"), content.title, content.writer, [[NSString alloc] initWithFormat:@"http://ncode.syosetu.com/%@/%@/", m_CurrentReadingStory.ncode, m_CurrentReadingStory.chapter_number], @"https://itunes.apple.com/jp/app/kotosekai-xiao-shuo-jianinarou/id914344185"];
    [EasyShare ShareText:message viewController:self barButton:shareButton];
}

- (void)startStopButtonClick:(id)sender {
    if([startStopButton.title compare:NSLocalizedString(@"SpeechViewController_Speak", @"Speak")] == NSOrderedSame)
    {
        // 停止中だったので読み上げを開始します
        if (UIAccessibilityIsVoiceOverRunning()) {
            // VoiceOver が Enable であったので、警告を発します
            [m_EasyAlert ShowAlertTwoButton:NSLocalizedString(@"SpeechViewController_SpeakAlertVoiceOver", @"VoiceOverが有効になっています。このまま再生しますか？")
                message:NSLocalizedString(@"SpeechViewController_SpeakAlertVoiceOverMessage", @"そのまま再生すると二重に読み上げが発声する事になります。")
                firstButtonText:NSLocalizedString(@"Cancel_button", @"Cancel")
                firstActionHandler:nil
                secondButtonText:NSLocalizedString(@"OK_button", @"OK")
                secondActionHandler:^(UIAlertAction *action) {
                    m_bIsSpeaking = YES;
                    [self startSpeech];
                }];
            return;
        }

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
    
    // 読み替え辞書登録時の値を放り込みます
    if ([[segue identifier] isEqualToString:@"SpeechViewToSpeechModSetingsSegue"]) {
        CreateSpeechModSettingViewController* nextViewController = [segue destinationViewController];
        nextViewController.targetBeforeString = [self GetCurrentSelectedString];
    }
    
    // ユーザ作成のコンテンツだった場合
    if ([[segue identifier] isEqualToString:@"EditUserTextSegue"]) {
        EditUserBookViewController* nextViewController = [segue destinationViewController];
        nextViewController.NarouContentDetail = self.NarouContentDetail;
    }

}

// スライダーが変更されたとき。
- (IBAction)ChapterSliderChanged:(UISlider *)sender {
    [self stopSpeech];
    int chapter = (self.ChapterSlider.value + 0.5f);
    if([self ChangeChapterWithLastestReadLocation:chapter] != true)
    {
        [self SetReadingPointFailedMessage];
    }
}
- (IBAction)PrevChapterButtonClicked:(id)sender {
    [self stopSpeech];
    [self SetPreviousChapter];
}
- (IBAction)NextChapterButtonClicked:(id)sender {
    [self stopSpeech];
    [self SetNextChapter];
}

// SpeachTextBox が読み終わった時
- (void)SpeakTextBoxFinishSpeak
{
    [self stopSpeechWithoutDiactivate];
    if ([self SetNextChapter] != true) {
        return;
    }
    [self startSpeech];
}

/// 読み上げ位置が更新されたとき
- (void) willSpeakRange:(NSRange)range speakText:(NSString*)text
{
    m_CurrentReadingStory.readLocation = [[NSNumber alloc] initWithUnsignedLong:range.location];
    self.textView.selectedRange = range;
    [self.textView scrollRangeToVisible:range];
}

/// 読み上げが停止したとき
- (void) finishSpeak
{
    [self stopSpeechWithoutDiactivate];
    // 次のページに移行する時に、このsleepから先に進んでいかないような挙動？を？示している？ようなので？試しにコメントアウトしてみます
    //[NSThread sleepForTimeInterval:1.0f];
    if ([self SetNextChapter]) {
        [self startSpeech];
    }else{
        [[GlobalDataSingleton GetInstance] AnnounceBySpeech:NSLocalizedString(@"SpeechViewController_SpeechStopedByEnd", @"Speak")];
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
            [self stopSpeechWithoutDiactivate];
            if ([self SetPreviousChapter]) {
                [self startSpeech];
            }
            break;
                
        case UIEventSubtypeRemoteControlNextTrack:
            NSLog(@"event: next");
            [self stopSpeechWithoutDiactivate];
            if ([self SetNextChapter]) {
                [self startSpeech];
            }
            break;
        default:
            break;
    }
}

/// 表示用のフォントサイズを変更します
- (void)ChangeFontSize:(float)fontSize
{
    UIFont* font = [UIFont systemFontOfSize:140.0];
    self.textView.font = [font fontWithSize:fontSize];
}

/// フォントサイズを設定されている値にします。
- (void)loadAndSetFontSize
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    double fontSize = [GlobalDataSingleton ConvertFontSizeValueToFontSize:[globalState.textSizeValue floatValue]];
    [self ChangeFontSize:fontSize];
}

/// NotificationCenter の受信者の設定をします。
- (void)setNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter addObserver:self selector:@selector(FontSizeChanged:) name:@"StoryDisplayFontSizeChanged" object:nil];
    
    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentDownloadStatusChanged_%@", self.NarouContentDetail.ncode];
    [notificationCenter addObserver:self selector:@selector(NarouContentUpdated:) name:notificationName object:nil];
    
    notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusUp_%@", self.NarouContentDetail.ncode];
    [notificationCenter addObserver:self selector:@selector(NarouContentUpdated:) name:notificationName object:nil];
    
    [[GlobalDataSingleton GetInstance] AddDownloadEventHandler:self];
}

/// NotificationCenter の受信者の設定を解除します。
- (void)removeNotificationReciver
{
    [[GlobalDataSingleton GetInstance] DeleteDownloadEventHandler:self];
    
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter removeObserver:self name:@"StoryDisplayFontSizeChanged" object:nil];
    
    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentDownloadStatusChanged_%@", self.NarouContentDetail.ncode];
    [notificationCenter removeObserver:self name:notificationName object:nil];

    notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusUp_%@", self.NarouContentDetail.ncode];
    [notificationCenter removeObserver:self name:notificationName object:nil];
}

/// フォントサイズ変更イベントの受信
/// NotificationCenter越しに呼び出されるイベントのイベントハンドラ
- (void)FontSizeChanged:(NSNotification*)notification
{
    NSDictionary* userInfo = notification.userInfo;
    if(userInfo == nil){
        return;
    }
    NSNumber* fontSizeValue = [userInfo objectForKey:@"fontSizeValue"];
    if (fontSizeValue == nil) {
        return;
    }
    float floatFontSizeValue = [fontSizeValue floatValue];
    [self ChangeFontSize:[GlobalDataSingleton ConvertFontSizeValueToFontSize:floatFontSizeValue]];
}

/// ダウンロード状態更新イベントの受信
- (void)NarouContentUpdated:(NSNotification*)notification
{
    self.NarouContentDetail = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:self.NarouContentDetail.ncode];
    [self updateChapterSlider];
}

/// 章のスライダを更新します
- (void)updateChapterSlider{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.ChapterSlider.minimumValue = 1;
        self.ChapterSlider.maximumValue = [self.NarouContentDetail.general_all_no floatValue] + 0.01f;
        [self UpdateChapterIndicatorLabel:[m_CurrentReadingStory.chapter_number intValue] max:(int)self.ChapterSlider.maximumValue];
    });
}

// NarouDownloadQueueDelegate ハンドラ：個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentCacheData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition {
    if ([self.NarouContentDetail.ncode compare:content.ncode] != NSOrderedSame) {
        return;
    }
    if (maxPosition > 0) {
        self.NarouContentDetail.general_all_no = [[NSNumber alloc] initWithInt:maxPosition];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            [self updateChapterSlider];
        });
    }
}
// NarouDownloadQueueDelegate ハンドラ：全ての download queue がなくなった時に呼び出されます。
- (void)DownloadEnd {
    // この時点で情報を更新しても古い情報が手に入るっぽい(更新してない？)ので特に何もしません。
}

@end
