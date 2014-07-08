//
//  DownloadStatusViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "DownloadStatusViewController.h"
#import "NarouContentAllData.h"

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
    self.DownloadWaitingQueueTableView.delegate = self;
    
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData SetDownloadEventHandler:self];

    NarouContentAllData* content = [[GlobalDataSingleton GetInstance] GetCurrentDownloadingInfo];
    if (content == nil) {
        self.DownloadingTitleLabel.text = @"ダウンロード中のものはありません";
        self.DownloadingProgressView.progress = 0.0f;
        self.DownloadingProgressLabel.text = @"0/0";
        self.ErrorLabel.text = @"";
        return;
    }
    self.DownloadingTitleLabel.text = content.title;
    float n = content.current_download_complete_count;
    float max = [content.general_all_no floatValue];
    self.DownloadingProgressView.progress = n / max;
    self.DownloadingProgressLabel.text = [[NSString alloc] initWithFormat:@"%d/%d", (int)n, (int)max];
    self.ErrorLabel.text = @"";
    //self.WaitDownloadQueueTableView;
}

- (void)dealloc
{
    [[GlobalDataSingleton GetInstance] UnsetDownloadEventHandler:self];
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
- (void)DownloadStatusUpdate:(NarouContentAllData *)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition
{
    if (content == nil) {
        self.DownloadingTitleLabel.text = @"ダウンロード中のものはありません";
        self.DownloadingProgressView.progress = 0.0f;
        self.DownloadingProgressLabel.text = @"0/0";
        self.ErrorLabel.text = @"";
        return;
    }
    self.DownloadingTitleLabel.text = content.title;
    float n = currentPosition;
    float max = maxPosition;
    self.DownloadingProgressView.progress = n / max;
    self.DownloadingProgressLabel.text = [[NSString alloc] initWithFormat:@"%d/%d", currentPosition, maxPosition];
    self.ErrorLabel.text = @"";
}

- (void)DownloadEnd
{
    self.DownloadingTitleLabel.text = @"ダウンロード中のものはありません";
    self.DownloadingProgressView.progress = 0.0f;
    self.DownloadingProgressLabel.text = @"0/0";
    self.ErrorLabel.text = @"";
    return;
}

// ダウンロード待ちの TableView用

// セクションの数
- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

// セクションのヘッダ
- (NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"ダウンロード待ち";
}

// 個々のセクションのセルの数
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray* currentWaitingList = [[GlobalDataSingleton GetInstance] GetCurrentDownloadWaitingInfo];
    if (currentWaitingList == nil) {
        return 0;
    }
    return [currentWaitingList count];
}

// セルの中身
- (UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // 利用できる cell があるなら再利用します
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(cell == nil)
    {
        // 無いようなので生成します。
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    }
    
    // ラベルを設定します。
    NSArray* currentWaitingList = [[GlobalDataSingleton GetInstance] GetCurrentDownloadWaitingInfo];
    if(currentWaitingList == nil
       || [currentWaitingList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[currentWaitingList count], indexPath.row);
        cell.textLabel.text = @"undefined";
    }
    else
    {
        NarouContentAllData* narouContent = (NarouContentAllData*)currentWaitingList[indexPath.row];
        cell.textLabel.text = [[NSString alloc] initWithFormat:@"%@"
                               , narouContent.title];
    }
    return cell;
}

// 編集できるか否かのYES/NOを返す。
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

// 編集されるときに呼び出される。
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSArray* contentList = [[GlobalDataSingleton GetInstance] GetCurrentDownloadWaitingInfo];
        if(contentList == nil
           || [contentList count] < indexPath.row)
        {
            NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], indexPath.row);
            return;
        }
        NarouContentAllData* content = contentList[indexPath.row];
        if([[GlobalDataSingleton GetInstance] DeleteDownloadQueue:content.ncode] != true)
        {
            return;
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }
}

@end
