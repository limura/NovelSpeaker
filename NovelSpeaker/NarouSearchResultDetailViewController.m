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

@interface NarouSearchResultDetailViewController ()

@end

@implementation NarouSearchResultDetailViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    // ダウンロードボタンを右上に配置します
    UIBarButtonItem* buttonItem = [[UIBarButtonItem alloc] initWithTitle:@"download" style:UIBarButtonItemStylePlain target:self action:@selector(downloadButtonClicked)];
    self.navigationItem.rightBarButtonItem = buttonItem;
    
    // 内容をラベル等に反映します
    if (self.NarouContentDetail == nil) {
        NSLog(@"self.NarouContentDetail == nil!!!");
        return;
    }
    self.TitleLabel.text = self.NarouContentDetail.title;
    self.WriterLabel.text = self.NarouContentDetail.writer;
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
    [dateFormatter setDateFormat:@"YYYY-MM-dd HH:mm:ss"];
    self.NovelupdatedAtLabel.text = [dateFormatter stringFromDate:self.NarouContentDetail.novelupdated_at];
    
    NSLog(@"ScrollView size: %f,%f", self.PageScrollView.bounds.size.width, self.PageScrollView.bounds.size.height);
    NSLog(@"ScrollView content size: %f,%f", self.PageScrollView.contentSize.width, self.PageScrollView.contentSize.height);
}


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
        UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"ダウンロードキューへの追加に失敗" message:msg delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        m_bNeedBack = false;
        [alertView show];
        return;
    }
    
    NSString* msg = [[NSString alloc] initWithFormat:@"作品名: %@", self.NarouContentDetail.title];
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:@"ダウンロードキューに追加されました" message:msg delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
    m_bNeedBack = true;
    [alertView show];
}

// alertView で何かがクリックされた
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (m_bNeedBack) {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

@end
