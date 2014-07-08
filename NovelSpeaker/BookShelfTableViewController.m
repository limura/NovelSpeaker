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
    [[GlobalDataSingleton GetInstance] SetDownloadEventHandler:self];
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
    return [contentList count];
}

// 個々のセルの取得
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // 利用できる cell があるなら再利用します
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if(cell == nil)
    {
        // 無いようなので生成します。
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    }
    
    NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
    if(contentList == nil
       || [contentList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], indexPath.row);
        cell.textLabel.text = @"undefined";
        return cell;
    }

    NarouContent* narouContent = (NarouContent*)contentList[indexPath.row];
    cell.textLabel.text = [[NSString alloc] initWithFormat:@"%@", narouContent.title];
    return cell;
}

/// セルが選択された時
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
    if(contentList == nil
       || [contentList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], indexPath.row);
        return;
    }
    NarouContent* narouContent = (NarouContent*)contentList[indexPath.row];
    
    // 次のビューに飛ばします。
    m_NextViewDetail = [[NarouContentAllData alloc] initWithCoreData:narouContent];
    [self performSegueWithIdentifier:@"bookShelfToReaderSegue" sender:self];
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
           || [contentList count] < indexPath.row)
        {
            NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], indexPath.row);
            return;
        }
        NarouContent* content = (NarouContent*)contentList[indexPath.row];
        [[GlobalDataSingleton GetInstance] DeleteContent:content];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}

// 個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentAllData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition
{
    [self.tableView reloadData];
}
// 全ての download queue がなくなった時に呼び出されます。
- (void)DownloadEnd
{
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
