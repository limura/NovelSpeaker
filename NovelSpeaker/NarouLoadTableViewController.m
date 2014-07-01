//
//  NarouLoadTableViewController.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouLoadTableViewController.h"
#import "GlobalDataSingleton.h"

@implementation NarouLoadTableViewController

// セクションの数
- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

// セクションのヘッダ
- (NSString*) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"なろう小説リスト";
    switch(section)
    {
        case 0:
            return @"section 1";
            break;
        case 1:
            return @"section 2";
            break;
        default:
            break;
    }
    return @"unknwon section";
}

// 個々のセクションのセルの数
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[GlobalDataSingleton GetInstance] GetNarouContentCount];
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
    NSMutableArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent];
    if(contentList == nil
       || [contentList count] < indexPath.row)
    {
        NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[contentList count], indexPath.row);
        cell.textLabel.text = @"undefined";
    }
    else
    {
        cell.textLabel.text = ((NarouContent*)contentList[indexPath.row]).title;
    }
    return cell;
}

@end
