//
//  DownloadStatusViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "DownloadStatusViewController.h"

@interface DownloadStatusViewController ()

@end

@implementation DownloadStatusViewController

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
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    globalData.NarouDownloadStatusUpdate = self;
    
    self.DownloadingTitleLabel.text = @"ダウンロード中のものはありません";
    self.DownloadingProgressView.progress = 0.0f;
    self.DownloadingProgressLabel.text = @"0/0";
    self.ErrorLabel.text = @"";
    //self.WaitDownloadQueueTableView;
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

/// ダウンロード状態が更新されたときに呼び出されます。
- (void)NarouDownloadStatusUpdate:(NarouContentAllData*)currentDownloadingContent
{
    if (currentDownloadingContent == nil) {
        self.DownloadingTitleLabel.text = @"ダウンロード中のものはありません";
        self.DownloadingProgressView.progress = 0.0f;
        self.DownloadingProgressLabel.text = @"0/0";
        self.ErrorLabel.text = @"";
        return;
    }
    self.DownloadingTitleLabel.text = currentDownloadingContent.title;
    float n = currentDownloadingContent.current_download_complete_count;
    float max = [currentDownloadingContent.general_all_no floatValue];
    self.DownloadingProgressView.progress = n / max;
    self.DownloadingProgressLabel.text = [[NSString alloc] initWithFormat:@"%d/%d", (int)n, (int)max];
    self.ErrorLabel.text = @"";
}


@end
