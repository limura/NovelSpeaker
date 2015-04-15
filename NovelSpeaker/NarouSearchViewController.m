//
//  NarouSearchViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/03.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouSearchViewController.h"
#import "NarouSearchResultTableViewController.h"
#import "NarouLoader.h"
#import "EasyAlert.h"

@interface NarouSearchViewController ()

@end

@implementation NarouSearchViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
        [self SetSearchOrderTargets];
        self.SearchOrderPickerView.delegate = self;
        self.SearchOrderPickerView.dataSource = self;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    m_SearchResult = nil;
    m_MainQueue = dispatch_get_main_queue();
    m_SearchQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.search", NULL);
    self.SearchTextBox.delegate = self;
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
    [self SetSearchOrderTargets];
    self.SearchOrderPickerView.delegate = self;
    self.SearchOrderPickerView.dataSource = self;
}

// 検索オーダーのリストを作ります
- (void)SetSearchOrderTargets
{
    m_SearchOrderTargetList = @[@"none", @"hyoka", @"hyokaasc", @"favnovelcnt", @"reviewcnt", @"impressioncnt", @"hyokacnt", @"hyokacntasc", @"weekly", @"lengthdesc", @"lengthasc", @"old"];
    m_SearchOrderTargetTextMap = @{@"none": NSLocalizedString(@"NarouSerchViewController_OrderNew", @"新着順")
                                   , @"hyoka": NSLocalizedString(@"NarouSerchViewController_OrderOver-allJudgment", @"総合評価の高い順")
                                   , @"hyokaasc": NSLocalizedString(@"NarouSerchViewController_OrderOver-allJudgmentAsc", @"総合評価の低い順")
                                   , @"favnovelcnt": NSLocalizedString(@"NarouSerchViewController_OrderNumberOfCoverBookmark", @"ブックマークの多い順")
                                   , @"reviewcnt": NSLocalizedString(@"NarouSerchViewController_NumberOfReview", @"レビュー数の多い順")
                                   , @"impressioncnt": NSLocalizedString(@"NarouSerchViewController_NumberOfImpression", @"感想の多い順")
                                   , @"hyokacnt": NSLocalizedString(@"NarouSerchViewController_NumberOfEvaluator", @"評価者数の多い順")
                                   , @"hyokacntasc": NSLocalizedString(@"NarouSerchViewController_NumberOfEvaluatorAsc", @"評価者数の少ない順")
                                   , @"weekly": NSLocalizedString(@"NarouSerchViewController_OrderNumberOfWeeklyUniqueUser", @"週間ユニークユーザ数順")
                                   , @"lengthdesc": NSLocalizedString(@"NarouSerchViewController_OrderStoryLength", @"本文の文字数順")
                                   , @"lengthasc": NSLocalizedString(@"NarouSerchViewController_OrderStoryLengthAsc", @"本文の文字数の少ない順")
                                   , @"old": NSLocalizedString(@"NarouSerchViewController_OrderOlder", @"古い順")
                                   };
}

// order の検索時に使う文字列を取得します
- (NSString*)GetSearchOrderSystemString:(NSInteger)pos
{
    if (pos < 0 || pos >= [m_SearchOrderTargetList count]) {
        return nil;
    }
    NSString* orderSystemString = m_SearchOrderTargetList[pos];
    if ([orderSystemString compare:@"none"] == NSOrderedSame) {
        return nil;
    }
    return orderSystemString;
}

// order の表示用文字列を取得します
- (NSString*)GetSearchOrderDisplayString:(NSInteger)pos
{
    if (pos < 0 || pos >= [m_SearchOrderTargetList count]) {
        return nil;
    }
    NSString* orderSystemString = m_SearchOrderTargetList[pos];
    return [m_SearchOrderTargetTextMap objectForKey:orderSystemString];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSLog(@"next view load!");
    // 次のビューをloadする前に呼び出してくれるらしいので、そこで検索結果を放り込みます。
    if ([[segue identifier] isEqualToString:@"searchResultPushSegue"]) {
        NSLog(@"set SearchResultList. count: %lu", (unsigned long)[m_SearchResult count]);
        NarouSearchResultTableViewController* nextViewController = [segue destinationViewController];
        nextViewController.SearchResultList = m_SearchResult;
    }
}

// 検索ボタンがクリックされた
- (IBAction)SearchButtonClicked:(id)sender {
    EasyAlertActionHolder* holder = [m_EasyAlert ShowAlert:NSLocalizedString(@"NarouSearchViewController_SearchTitle_Searching", @"Searching")
                   message:NSLocalizedString(@"NarouSearchViewController_SearchMessage_NowSearching", @"Now searching")];
    dispatch_async(m_SearchQueue, ^{
        NSArray* searchResult = [NarouLoader
                                 Search:self.SearchTextBox.text
                                 wname:self.WriterSwitch.on
                                 title:self.TitleSwitch.on
                                 keyword:self.KeywordSwitch.on
                                 ex:self.ExSwitch.on
                                 order:[self GetSearchOrderSystemString:
                                        [self.SearchOrderPickerView selectedRowInComponent:0]]
                                 ];
        m_SearchResult = searchResult;
        dispatch_async(m_MainQueue, ^{
            [holder CloseAlert:false];
            NSLog(@"search end. count: %lu", (unsigned long)[m_SearchResult count]);
            [self performSegueWithIdentifier:@"searchResultPushSegue" sender:self];
        });
    });
}

// テキストフィールドでEnterが押された
- (BOOL)textFieldShouldReturn:(UITextField *)sender {
    // キーボードを閉じる
    [sender resignFirstResponder];
    
    return TRUE;
}

// UIPickerView の列数を返す
-(NSInteger)numberOfComponentsInPickerView:(UIPickerView*)pickerView
{
    return 1;
}
// UIPickerView の行数を返す
-(NSInteger)pickerView:(UIPickerView*)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return [m_SearchOrderTargetList count];
}
// UIPickerView に表示される値を返す
-(NSString*)pickerView:(UIPickerView*)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return [self GetSearchOrderDisplayString:row];
}

@end
