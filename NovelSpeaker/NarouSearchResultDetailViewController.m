//
//  NarouSearchResultDetailViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouSearchResultDetailViewController.h"
#import "GlobalDataSingleton.h"
#import <math.h>
#import "EasyAlert.h"
#import "NarouLoader.h"
#import "NarouSearchResultTableViewController.h"

@interface NarouSearchResultDetailViewController ()

@end

@implementation NarouSearchResultDetailViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
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
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];

    // ダウンロードボタンを右上に配置します
    UIBarButtonItem* buttonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"DownloadButton", @"download") style:UIBarButtonItemStylePlain target:self action:@selector(downloadButtonClicked)];
    self.navigationItem.rightBarButtonItem = buttonItem;
    
    // 内容をラベル等に反映します
    if (self.NarouContentDetail == nil) {
        NSLog(@"self.NarouContentDetail == nil!!!");
        return;
    }
    self.TitleLabel.text = self.NarouContentDetail.title;
    [self.WriterButton setTitle:self.NarouContentDetail.writer forState:UIControlStateNormal];
    self.KeywordLabel.text = self.NarouContentDetail.keyword;
    self.FavNovelCntLabel.text = [self.NarouContentDetail.fav_novel_cnt stringValue];
    self.GeneralAllNoLabel.text = [self.NarouContentDetail.general_all_no stringValue];
    self.GlobalPointLabel.text = [self.NarouContentDetail.global_point stringValue];
    self.KeywordLabel.text = self.NarouContentDetail.keyword;
    self.StoryTextLabel.text = self.NarouContentDetail.story;
    
    float averagePoint = [self.NarouContentDetail.all_point floatValue] / [self.NarouContentDetail.all_hyoka_cnt floatValue];
    if (isnan(averagePoint) ) {
        averagePoint = 0.0f;
    }
    self.PointLabel.text = [[NSString alloc] initWithFormat:@"%f/%d", averagePoint
                            , [self.NarouContentDetail.all_hyoka_cnt intValue]];

    NSDateFormatter* dateFormatter = [NSDateFormatter new];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    //[dateFormatter setDateFormat:NSLocalizedString(@"DisplayDateFormat", @"YYYY-MM-dd HH:mm:ss")];
    self.NovelupdatedAtLabel.text = [dateFormatter stringFromDate:self.NarouContentDetail.novelupdated_at];
    
    //NSLog(@"ScrollView size: %f,%f", self.PageScrollView.bounds.size.width, self.PageScrollView.bounds.size.height);
    //NSLog(@"ScrollView content size: %f,%f", self.PageScrollView.contentSize.width, self.PageScrollView.contentSize.height);
}

/*
- (void)viewDidLayoutSubviews
{
    CGSize size;
    size.width = self.PageScrollView.bounds.size.width;
    size.height = 0
    + 10 + self.TitleLabel.bounds.size.height
    +  8 + self.WriterLabel.bounds.size.height
    +  8 + self.KeywordLabel.bounds.size.height
    +  8 + self.FavNovelCntLabel.bounds.size.height
    +  8 + self.GeneralAllNoLabel.bounds.size.height
    +  8 + self.GlobalPointLabel.bounds.size.height
    +  8 + self.KeywordLabel.bounds.size.height
    +  8 + self.StoryInfoLabel.bounds.size.height
    +  8 + self.StoryTextLabel.bounds.size.height
    +  8;
    NSLog(@"size: w/h: %f/%f", size.width, size.height);
    [self.PageScrollView setContentSize:size];

    [super viewDidLayoutSubviews];
    [self.view layoutSubviews];
    NSLog(@"A layout SubViews ScrollView size: %f,%f", self.PageScrollView.bounds.size.width, self.PageScrollView.bounds.size.height);
    NSLog(@"A layout SubViews ScrollView content size: %f,%f", self.PageScrollView.contentSize.width, self.PageScrollView.contentSize.height);

    size.width = self.PageScrollView.bounds.size.width;
    size.height = 0
    + 10 + self.TitleLabel.bounds.size.height
    +  8 + self.WriterLabel.bounds.size.height
    +  8 + self.KeywordLabel.bounds.size.height
    +  8 + self.FavNovelCntLabel.bounds.size.height
    +  8 + self.GeneralAllNoLabel.bounds.size.height
    +  8 + self.GlobalPointLabel.bounds.size.height
    +  8 + self.KeywordLabel.bounds.size.height
    +  8 + self.StoryInfoLabel.bounds.size.height
    +  8 + self.StoryTextLabel.bounds.size.height
    +  8;
    NSLog(@"size: w/h: %f/%f", size.width, size.height);
    [self.PageScrollView setContentSize:size];
    
    [super viewDidLayoutSubviews];
    [self.view layoutSubviews];
    NSLog(@"B layout SubViews ScrollView size: %f,%f", self.PageScrollView.bounds.size.width, self.PageScrollView.bounds.size.height);
    NSLog(@"B layout SubViews ScrollView content size: %f,%f", self.PageScrollView.contentSize.width, self.PageScrollView.contentSize.height);

}
 */

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

- (void)downloadButtonClicked
{
    NSString* errString = [[GlobalDataSingleton GetInstance] AddDownloadQueueForNarou:self.NarouContentDetail];
    if (errString != nil) {
        NSString* msg = [[NSString alloc] initWithString:errString];
#if true
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"NarouSearchResultDetailViewController_FailedInAdditionToDownloadQueue", @"ダウンロードキューへの追加に失敗") message:msg];
#else
        UIAlertController* alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"NarouSearchResultDetailViewController_FailedInAdditionToDownloadQueue", @"ダウンロードキューへの追加に失敗") message:msg okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:nil];
        [self presentViewController:alert animated:true completion:nil];
#endif
        return;
    }
    
    NSString* msg = [[NSString alloc] initWithFormat:NSLocalizedString(@"NarouSearchResultDetailViewController_AddSuccess_Title", @"作品名: %@"), self.NarouContentDetail.title];
#if true
    [m_EasyAlert ShowAlertOneButton:NSLocalizedString(@"NarouSearchResultDetailViewController_AddSuccess_ItWasAddedToDownloadQueue", @"ダウンロードキューに追加されました") message:msg okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:^(UIAlertAction* action){
        [self.navigationController popViewControllerAnimated:YES];
    }];
#else
    UIAlertController* alert = [EasyAlert CreateAlertOneButton:NSLocalizedString(@"NarouSearchResultDetailViewController_AddSuccess_ItWasAddedToDownloadQueue", @"ダウンロードキューに追加されました")
                                                       message:msg okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:^(UIAlertAction* action){
                                                           [self.navigationController popViewControllerAnimated:YES];
                                                       }];
    [self presentViewController:alert animated:true completion:nil];
#endif
}

- (IBAction)WriterButtonClicked:(id)sender {
#if true
    EasyAlertActionHolder* holder = [m_EasyAlert ShowAlert:NSLocalizedString(@"NarouSearchViewController_SearchTitle_Searching", @"Searching") message:NSLocalizedString(@"NarouSearchViewController_SearchMessage_NowSearching", @"Now searching")];
#else
    UIAlertController* alertView = [EasyAlert CreateAlertNoButton:NSLocalizedString(@"NarouSearchViewController_SearchTitle_Searching", @"Searching") message:NSLocalizedString(@"NarouSearchViewController_SearchMessage_NowSearching", @"Now searching")];
    // ここで animated を TRUE にしてしまうと、アニメーションしている間に dissmissViewControllerAnimated を発行してしまうと効かないので
    // 検索がすげー時間かからないと駄目になっちゃうので FALSE にします。
    [self presentViewController:alertView animated:FALSE completion:nil];
#endif
    dispatch_async(m_SearchQueue, ^{
        NSArray* searchResult = [NarouLoader SearchUserID: self.NarouContentDetail.userid];
        m_SearchResult = searchResult;
        dispatch_async(m_MainQueue, ^{
#if true
            [holder CloseAlert:false];
#else
            [alertView dismissViewControllerAnimated:FALSE completion:nil];
#endif
            NSLog(@"search end. count: %lu", (unsigned long)[m_SearchResult count]);
            [self performSegueWithIdentifier:@"searchUserIDResultPushSegue" sender:self];
        });
    });
}

// 次のページに移行する時に呼ばれる
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSLog(@"next view load!");
    // 次のビューをloadする前に呼び出してくれるらしいので、そこで検索結果を放り込みます。
    if ([[segue identifier] isEqualToString:@"searchUserIDResultPushSegue"]) {
        NSLog(@"set SearchResultList. count: %lu", (unsigned long)[m_SearchResult count]);
        NarouSearchResultTableViewController* nextViewController = [segue destinationViewController];
        nextViewController.SearchResultList = m_SearchResult;
    }
}
@end
