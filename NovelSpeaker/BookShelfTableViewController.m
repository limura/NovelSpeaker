//
//  BookShelfTableViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "BookShelfTableViewController.h"
#import "NarouContent.h"
#import "GlobalDataSingleton.h"
#import "SpeechViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "BookShelfTableViewCell.h"

@interface BookShelfTableViewController ()

@end

@implementation BookShelfTableViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    //[self.navigationController setNavigationBarHidden:FALSE animated:TRUE];
    
    // 編集ボタンをつけます。
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    UIBarButtonItem* refreshButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshButtonClick:)];

    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:self.editButtonItem, refreshButton, nil];

    // カスタマイズしたセルをテーブルビューにセット
    UINib *nib = [UINib nibWithNibName:BookShelfTableViewCellID bundle:nil];
    [self.tableView registerNib:nib forCellReuseIdentifier:BookShelfTableViewCellID];
    //[self.searchDisplayController.searchResultsTableView registerNib:nib forCellReuseIdentifier:BookShelfTableViewCellID];

    [self setNotificationReciver];
    //[[GlobalDataSingleton GetInstance] AddDownloadEventHandler:self];
    
    if(![[GlobalDataSingleton GetInstance] IsFirstPageShowed])
    {
        NarouContentCacheData* currentContent = [[GlobalDataSingleton GetInstance] GetCurrentReadingContent];
        if (currentContent != nil) {
            [self PushNextView:currentContent];
        }
    }
}

- (void)dealloc
{
    [self removeNotificationReciver];
    [[GlobalDataSingleton GetInstance] DeleteDownloadEventHandler:self];
}

/// NotificationCenter の受信者の設定をします。
- (void)setNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter addObserver:self selector:@selector(NarouContentListChanged:) name:@"NarouContentListChanged" object:nil];
}

/// NotificationCenter の受信者の設定を解除します。
- (void)removeNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    [notificationCenter removeObserver:self name:@"NarouContentListChanged" object:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)refreshButtonClick:(id)sender
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    NSMutableArray* contentList = [globalData GetAllNarouContent];
    if (contentList == nil) {
        return;
    }
    for (NarouContent* content in contentList) {
        NarouContentCacheData* contentAllData = [[NarouContentCacheData alloc] initWithCoreData:content];
        [globalData AddDownloadQueueForNarou:contentAllData];
    }
}

#pragma mark - Table view data source

// セクションの数
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

// セクション内部のセルの数
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
    if (contentList == nil) {
        return 0;
    }
    //NSLog(@"numberOfRowsInSection called return %lu", (unsigned long)[contentList count]);
    return [contentList count];
}

// 個々のセルの取得
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // 利用できる cell があるなら再利用します
    BookShelfTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:BookShelfTableViewCellID];
    if(cell == nil)
    {
        // 無いようなので生成します。
        cell = [[BookShelfTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:BookShelfTableViewCellID];
    }
    
    NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
    if(contentList == nil
       || [contentList count] <= indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu <= %ld", (unsigned long)[contentList count], (long)indexPath.row);
        [cell setTitleLabel:@"unknown error" ncode:nil];
        return cell;
    }

    NarouContent* narouContent = (NarouContent*)contentList[indexPath.row];
    [cell setTitleLabel:narouContent.title ncode:narouContent.ncode];
    return cell;
}

// 次のビューに飛ばします。
- (void)PushNextView:(NarouContentCacheData*)narouContent
{
    m_NextViewDetail = narouContent;
    //NSLog(@"next view: %@ %@", narouContent.ncode, narouContent.title);
    [self performSegueWithIdentifier:@"bookShelfToReaderSegue" sender:self];
}

/// セルが選択された時
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
    if(contentList == nil
       || [contentList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], (long)indexPath.row);
        return;
    }
    NarouContentCacheData* narouContent = (NarouContentCacheData*)contentList[indexPath.row];
    
    // 次のビューに飛ばします。
    [self PushNextView:narouContent];
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
        NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
        if(contentList == nil
           || [contentList count] <= indexPath.row)
        {
            NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], (long)indexPath.row);
            return;
        }
        NarouContentCacheData* content = contentList[indexPath.row];
        NSLog(@"tableView row deleting. before content.length: %lu", (unsigned long)[contentList count]);
        // Contentを消すことによって Notification が飛んで変なことになるので一旦切ります。
        [self removeNotificationReciver];
        if([[GlobalDataSingleton GetInstance] DeleteContent:content] != true)
        {
            NSLog(@"delete content failed ncode: %@ title: %@", content.ncode, content.title);
        }
        // NotificationReciver を復活させます
        [self setNotificationReciver];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        NSLog(@"tableView row delete.    after content.length: %lu", (unsigned long)[contentList count]);
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}

// 個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentCacheData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition
{
    [self.tableView reloadData];
}
// 全ての download queue がなくなった時に呼び出されます。
- (void)DownloadEnd
{
    [self.tableView reloadData];
}

/// NotificationCenter越しに呼び出されるイベントのイベントハンドラ
- (void)NarouContentListChanged:(NSNotification*)notification
{
    //NSLog(@"NarouContentListChanged notification got.");
    [self.tableView reloadData];
}

/*
// Override to support rearranging the table view.
// 移動されたときに呼び出される。
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// 移動できるかどうかのYES/NOを返す。
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/// NavigationController で戻ってきた時とかに呼び出される
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
	[viewController viewWillAppear:animated];
    
    // 更新フラグとかを更新するために全部リロードしちゃいます
    NSLog(@"didShowViewController: reloadData");
    [self.tableView reloadData];
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
	[viewController viewWillAppear:animated];

    // 更新フラグとかを更新するために全部リロードしちゃいます
    NSLog(@"didShowViewController: reloadData");
    [self.tableView reloadData];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"bookShelfToReaderSegue"]) {
        SpeechViewController* nextViewController = [segue destinationViewController];
        nextViewController.NarouContentDetail = m_NextViewDetail;
    }
}


@end
