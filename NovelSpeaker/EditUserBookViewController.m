//
//  EditUserBookViewController.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/07/31.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import "EditUserBookViewController.h"
#import "EasyAlert.h"

@interface EditUserBookViewController ()

@end

/*
 - 編集中にページ移動すると
   - 元ページの登録が消える
   - 移動先ページの内容が元ページのものになる
 */

@implementation EditUserBookViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    m_pEasyAlert = [[EasyAlert alloc] initWithViewController:self];
    m_CurrentChapterNumber = 0;

    // 指定された小説を読み込みます。
    [self LoadContent];
    
    // フォントサイズを設定された値に変更します。
    [self loadAndSetFontSize];
    
    // フォントサイズ変更イベントを受け取るようにします。
    [self setNotificationReciver];
    
    // キーボードが開いた時に BookBodyTextBox の縦幅を減らす処理用にフックを入れます
    [self RegisterKeyboardNotifications];
    
    // キーボードを閉じるためにシングルタップのイベントを取るようにします
    self.singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTap:)];
    self.singleTap.delegate = self;
    self.singleTap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:self.singleTap];

    self.BookBodyTextBox.placeholder = NSLocalizedString(@"EditUserBookViewContoller_InputTextHeare", @"ここに本文を書き込んでください。");
}

- (void)viewWillAppear:(BOOL)animated
{
    //NSLog(@"viewWillAppear");
    
    [super viewWillAppear:animated];
    // 指定された小説を読み込みます。
    [self LoadContent];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/// 表示する章を設定します。
/// スライドバー等の状態も更新されます。
- (BOOL)SetChapter:(StoryCacheData*)chapter content:(NarouContentCacheData*)content
{
    if (content == nil || content.title == nil) {
        NSLog(@"self.NarouContentDetail == nil?");
        return false;
    }
    if (chapter == nil || chapter.content == nil) {
        self.BookBodyTextBox.text = @"";
    }else{
        self.BookBodyTextBox.text = chapter.content;
    }

    float max = [content.general_all_no floatValue];
    float current = [chapter.chapter_number floatValue];
    
    self.ChapterIndicatorLabel.text = [[NSString alloc] initWithFormat:@"%d/%d", (int)current, (int)max];
    
    self.ChapterSlidebar.minimumValue = 1.0f;
    self.ChapterSlidebar.maximumValue = max + 0.01f;
    self.ChapterSlidebar.value = current;
    m_CurrentChapterNumber = (int)current;
    
    if ((int)max == (int)current) {
        self.AddChapterButton.enabled = true;
        self.DelChapterButton.enabled = true;
    }else{
        self.AddChapterButton.enabled = false;
        self.DelChapterButton.enabled = false;
    }
    
    return true;
}

/// 末尾に章を一つ足します
- (StoryCacheData*)AddNewStory{
    if (self.NarouContentDetail == nil) {
        return nil;
    }
    NSNumber* maxNum = self.NarouContentDetail.general_all_no;
    if (maxNum == nil) {
        return nil;
    }
    int newNum = [maxNum intValue] + 1;
    if (newNum < 1) {
        newNum = 1;
    }
    
    //NSLog(@"末尾に章を増やします。%d -> %d", [self.NarouContentDetail.general_all_no intValue], newNum);
    
    self.NarouContentDetail.general_all_no = [[NSNumber alloc] initWithInt:newNum];
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData UpdateNarouContent:self.NarouContentDetail];
    [globalData UpdateStory:@"" chapter_number:newNum parentContent:self.NarouContentDetail];
    StoryCacheData* story = [globalData SearchStory:self.NarouContentDetail.ncode chapter_no:newNum];
    
    self.ChapterSlidebar.maximumValue = newNum + 0.01f;

    return story;
}

/// 最後の章を消します
- (BOOL)DelLastStory {
    if (self.NarouContentDetail == nil) {
        return false;
    }
    
    if([self.NarouContentDetail.general_all_no intValue] <= 0){
        return false;
    }
    StoryCacheData* deleteTargetStory = [StoryCacheData new];
    deleteTargetStory.ncode = self.NarouContentDetail.ncode;
    deleteTargetStory.chapter_number = self.NarouContentDetail.general_all_no;
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    if([globalData DeleteStory:deleteTargetStory] != true)
    {
        return false;
    }
    //NSLog(@"章を減らします。%d -> %d", [self.NarouContentDetail.general_all_no intValue], [self.NarouContentDetail.general_all_no intValue]-1);
    
    self.NarouContentDetail.general_all_no = [[NSNumber alloc] initWithInt:[self.NarouContentDetail.general_all_no intValue] - 1];
    [globalData UpdateNarouContent:self.NarouContentDetail];
    
    self.ChapterSlidebar.maximumValue = [self.NarouContentDetail.general_all_no floatValue] + 0.01f;
    return true;
}

/// 小説を読み込みます。読み込みに失敗したら false を返します。
/// 小説が未定義の場合(self.NarouContentDetail が nilの場合)は、章を初期値で生成します。
- (BOOL)LoadContent {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    // 一時的に全てを default値 にしておきます
    self.TitleTextBox.text = @"unknown document";
    self.BookBodyTextBox.text = @"";
    self.ChapterSlidebar.minimumValue = 1;
    self.ChapterSlidebar.maximumValue = 1;
    self.ChapterSlidebar.value = 1;
    m_CurrentChapterNumber = 1;
    
    NarouContentCacheData* content = self.NarouContentDetail;
    if (content == nil || content.title == nil) {
        return false;
    }
    self.TitleTextBox.text = content.title;

    StoryCacheData* story = content.currentReadingStory;
    // どうやら content.currentReadingStory のものは古いデータを参照することがあるようなので、loadし直します。
    int targetChapter = 1;
    if (story != nil) {
        targetChapter = [story.chapter_number intValue];
    }
    story = [globalData SearchStory:content.ncode chapter_no:targetChapter];
    if (story == nil) {
        story = [globalData SearchStory:content.ncode chapter_no:1];
        if (story == nil) {
            story = [self AddNewStory];
            if (story == nil) {
                return false;
            }
        }
    }

    //NSLog(@"LoadContent: %d %@", [story.chapter_number intValue], story.content);
    
    [self SetChapter:story content:content];
    
    return true;
}


/// 現在の入力状態で content(小説情報) の登録を上書きします。失敗すると false を返します。
/// 足りないことがある場合、怪しくダイアログをだします。
- (BOOL)SaveCurrentContent{
    if (self.TitleTextBox.text == nil || [self.TitleTextBox.text length] <= 0) {
        [m_pEasyAlert ShowAlertOKButton:NSLocalizedString(@"EditUserBookViewController_PleaseInputTitle", @"タイトルを入力してください") message:nil];
        return false;
    }
    self.NarouContentDetail.title = self.TitleTextBox.text;
    [[GlobalDataSingleton GetInstance] UpdateNarouContent:self.NarouContentDetail];
    return true;
}

- (BOOL)SaveStoryTo:(int)chapterNumber
{
    if (![self SaveCurrentContent]) {
        return false;
    }
    if (self.BookBodyTextBox.text == nil || [self.BookBodyTextBox.text length] <= 0) {
        [m_pEasyAlert ShowAlertOKButton:NSLocalizedString(@"EditUserBookViewController_PleaseInputBookBody", @"本文を入力してください") message:nil];
        return false;
    }
    if([[GlobalDataSingleton GetInstance] UpdateStory:self.BookBodyTextBox.text chapter_number:chapterNumber parentContent:self.NarouContentDetail]) {
        //NSLog(@"story saved. %d/%d %@", chapterNumber, [self.NarouContentDetail.general_all_no intValue], self.BookBodyTextBox.text);
    }else{
        //NSLog(@"story save FAILED. %d/%d %@", chapterNumber, [self.NarouContentDetail.general_all_no intValue], self.BookBodyTextBox.text);
    }
    return true;

}

/// 現在の入力状態で章を上書き更新します。失敗すると false を返します。
- (BOOL)SaveCurrentStory{
    int chapter = (int)self.ChapterSlidebar.value;
    return [self SaveStoryTo:chapter];
}

- (IBAction)EntryButtonClicked:(id)sender {
    if(![self SaveCurrentContent] || ![self SaveCurrentStory])
    {
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)UpdateDisplayStory:(int)chapterNumber {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    StoryCacheData* story = [globalData SearchStory:self.NarouContentDetail.ncode chapter_no:chapterNumber];
    if (story == nil) {
        return false;
    }
    if (story.content != nil) {
        self.BookBodyTextBox.text = story.content;
    }

    return true;
}

- (BOOL)LoadChapter:(int)num
{
    StoryCacheData* story = [[GlobalDataSingleton GetInstance] SearchStory:self.NarouContentDetail.ncode chapter_no:num];
    if (story == nil) {
        NSLog(@"FATAL. Storyが読み込めませんでした。");
        return false;
    }
    self.ChapterSlidebar.value = num;
    //NSLog(@"chapter %d load: %@", num, story.content);
    [self SetChapter:story content:self.NarouContentDetail];
    return true;
}

/// 前の章へボタンがおされた
- (IBAction)PrevChapterButtonClicked:(id)sender {
    if (![self SaveCurrentStory]) {
        return;
    }
    
    if (self.ChapterSlidebar.value <= 1) {
        return;
    }
    int current = (int)self.ChapterSlidebar.value;

    [self LoadChapter:current - 1];
}

/// 次の章へボタンが押された
- (IBAction)NextChapterButtonClicked:(id)sender {
    if (![self SaveCurrentStory]) {
        return;
    }

    int max = [self.NarouContentDetail.general_all_no intValue];
    int current = (int)self.ChapterSlidebar.value;

    if (current + 1 > max) {
        return;
    }
    
    [self LoadChapter:current + 1];
}

- (IBAction)ChapterSlidebarValueChanged:(id)sender {
    if (m_CurrentChapterNumber <= 0 || self.NarouContentDetail == nil || m_CurrentChapterNumber > [self.NarouContentDetail.general_all_no intValue]) {
        NSLog(@"m_CurrentChapterNumber: %d 変だ。", m_CurrentChapterNumber);
        return;
    }
    // 表示している chapter が変わっていなければ何もしません。
    int chapter = (int)(self.ChapterSlidebar.value + 0.5f);
    if (chapter == m_CurrentChapterNumber) {
        self.ChapterSlidebar.value = chapter;
        return;
    }
    
    if (![self SaveStoryTo:m_CurrentChapterNumber]) {
        return;
    }

    [self LoadChapter:chapter];
}

- (IBAction)AddChapterButtonClicked:(id)sender {
    if (![self SaveCurrentStory]) {
        return;
    }
    StoryCacheData* story = [self AddNewStory];
    if (story == nil) {
        [m_pEasyAlert ShowAlertOKButton:NSLocalizedString(@"EditUserBookViewController_AddNewStoryFailed", @"新しい章の追加に失敗しました") message:nil];
        return;
    }
    [self SetChapter:story content:self.NarouContentDetail];
}

- (IBAction)DelChapterButtonClicked:(id)sender {
    [m_pEasyAlert ShowAlertTwoButton:NSLocalizedString(@"EditUserBookViewController_ConfirmDeleteThisChapter", @"この章を削除します。よろしいですか？") message:nil firstButtonText:NSLocalizedString(@"Cancel_button", @"Cancel") firstActionHandler:nil secondButtonText:NSLocalizedString(@"OK_button", @"OK") secondActionHandler:^(UIAlertAction *alert) {
            if (![self DelLastStory]) {
                [m_pEasyAlert ShowAlertOKButton:NSLocalizedString(@"EditUserBookViewController_CanNotDeleteChapter", @"章の削除に失敗しました") message:nil];
                return;
            }
            int last = [self.NarouContentDetail.general_all_no intValue];
            StoryCacheData* story = [[GlobalDataSingleton GetInstance] SearchStory:self.NarouContentDetail.ncode chapter_no:last];
            if (story == nil) {
                [self LoadContent];
                return;
            }
            [self SetChapter:story content:self.NarouContentDetail];
        }];
}



// フォントサイズあたり

/// 表示用のフォントサイズを変更します
- (void)ChangeFontSize:(float)fontSize
{
    UIFont* font = [UIFont systemFontOfSize:140.0];
    self.BookBodyTextBox.font = [font fontWithSize:fontSize];
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
}

/// NotificationCenter の受信者の設定を解除します。
- (void)removeNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter removeObserver:self name:@"StoryDisplayFontSizeChanged" object:nil];
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

// キーボードが開いた時に BookBodyTextBox の縦幅を減らす処理用にフックを登録します
- (void)RegisterKeyboardNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillBeHidden:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

// キーボードが開く時のフック
- (void)keyboardWasShown:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
    CGRect keyboardFrame = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    int height = keyboardFrame.size.height - 42;
    if (height < 0) {
        height = 0;
    }
    self.BookBodyTextBoxBottomConstraint.constant = height;

    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}

// キーボードが閉じる時のフック
- (void)keyboardWillBeHidden:(NSNotification*)notification
{
    NSDictionary *info = [notification userInfo];
    NSTimeInterval duration = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    self.BookBodyTextBoxBottomConstraint.constant = 0;
    
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    }];
}


/// シングルタップのイベントハンドラ。
/// キーボードが出ていたら閉じます。
-(void)onSingleTap:(UITapGestureRecognizer *)recognizer {
    if (self.BookBodyTextBox.isFirstResponder) {
        [self.BookBodyTextBox resignFirstResponder];
    }
    if (self.TitleTextBox.isFirstResponder) {
        [self.TitleTextBox resignFirstResponder];
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
