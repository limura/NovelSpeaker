//
//  NarouLoadTableViewController.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouSearchResultTableViewController.h"
#import "GlobalDataSingleton.h"
#import "NarouContentCacheData.h"
#import "NarouSearchResultDetailViewController.h"

@implementation NarouSearchResultTableViewController

// view がロードされたとき
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // 編集ボタンを追加する場合
    //self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

// セクションの数
- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

// セクションのヘッダ
- (NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"検索結果";
}

// 個々のセクションのセルの数
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSLog(@"result count: %lu", (unsigned long)[self.SearchResultList count]);
    return self.SearchResultList ? [self.SearchResultList count] : 0;
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
    if(self.SearchResultList == nil
       || [self.SearchResultList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[self.SearchResultList count], (long)indexPath.row);
        cell.textLabel.text = @"undefined";
    }
    else
    {
        NarouContentCacheData* narouContent = (NarouContentCacheData*)self.SearchResultList[indexPath.row];
        cell.textLabel.text = [[NSString alloc] initWithFormat:@"%@"
                               , narouContent.title];
    }
    return cell;
}

/// セルが選択された時
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSLog(@"row %ld selected.", (long)indexPath.row);

    if(self.SearchResultList == nil
       || [self.SearchResultList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[self.SearchResultList count], (long)indexPath.row);
        return;
    }
    NarouContentCacheData* content = (NarouContentCacheData*)self.SearchResultList[indexPath.row];

    // 次のビューに飛ばします。
    m_NextViewDetail = content;
    [self performSegueWithIdentifier:@"searchResultDetailSegue" sender:self];
}

/// 次のセグエが呼び出される時に呼ばれるはずのもの
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"searchResultDetailSegue"]) {
        NarouSearchResultDetailViewController* nextViewController = [segue destinationViewController];
        nextViewController.NarouContentDetail = m_NextViewDetail;
    }
}
@end
