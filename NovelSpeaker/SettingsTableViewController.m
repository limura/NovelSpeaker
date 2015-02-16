//
//  SettingsTableViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SettingsTableViewController.h"
#import "GlobalDataSingleton.h"
#import "MaxSpeechTimeTableViewCell.h"

#undef USE_LOG_VIEW

static NSString* const SettingsTableViewDefaultCellID = @"SettingsTableViewCellDefault";

@interface SettingsTableViewController ()

@end

@implementation SettingsTableViewController

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

    UINib* maxSpeechTimeTableViewCellNib = [UINib nibWithNibName:MaxSpeechTimeTableViewCellID bundle:nil];
    [self.tableView registerNib:maxSpeechTimeTableViewCellNib forCellReuseIdentifier:MaxSpeechTimeTableViewCellID];

    
    // 読み上げ設定をloadします。
    [[GlobalDataSingleton GetInstance] ReloadSpeechSetting];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    return 5
#ifdef USE_LOG_VIEW
    + 1
#endif
    ;
}

- (UITableViewCell *)GetDefaultTableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SettingsTableViewDefaultCellID forIndexPath:indexPath];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:SettingsTableViewDefaultCellID];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    switch(indexPath.row)
    {
        case 0:
            cell.textLabel.text = NSLocalizedString(@"SettingsTableViewController_SettingOfTheQualityOfVoice", @"声質の設定");
            break;
        case 1:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_CorrectionOfTheReading", @"読みの修正");
            break;
        case 2:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_SettingOfTheTextSize", @"文字サイズの設定");
            break;
        case 3:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_SettingOfTheSpeechDelay", @"読み上げ時の間の設定");
            break;
#ifdef USE_LOG_VIEW
        case 5:
            cell.textLabel.text = @"debug log";
            break;
#endif
        default:
            cell.textLabel.text = @"-";
            break;
    }
    
    return cell;
}

- (UITableViewCell *)GetMaxSpeechTimeTableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MaxSpeechTimeTableViewCellID forIndexPath:indexPath];

    if (cell != nil) {
        return cell;
    }

    cell = [[MaxSpeechTimeTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:MaxSpeechTimeTableViewCellID];


    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case 0: case 1: case 2: case 3:
#ifdef USE_LOG_VIEW
        case 5:
#endif
            return [self GetDefaultTableView:tableView cellForRowAtIndexPath:indexPath];
            break;
        case 4:
            return [self GetMaxSpeechTimeTableView:tableView cellForRowAtIndexPath:indexPath];
            break;
        default:
            break;
    }
    return nil;
}

// セルが選択された時
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case 0:
            [self performSegueWithIdentifier:@"speakSettingsSegue" sender:self];
            break;
        case 1:
            [self performSegueWithIdentifier:@"speechModSettingSegue" sender:self];
            break;
        case 2:
            [self performSegueWithIdentifier:@"textSizeSettingSegue" sender:self];
            break;
        case 3:
            [self performSegueWithIdentifier:@"textDelaySettingSegue" sender:self];
            break;
#ifdef USE_LOG_VIEW
        case 5:
            [self performSegueWithIdentifier:@"debugLogViewSegue" sender:self];
            break;
#endif
        default:
            break;
    }
}

/// tableViewCell の縦の長さを返します。
/// TODO: 多分これはスクロールバーを表示させるために全部のcellに対して呼び出されるのでたくさんのcellがあった場合ひどいことになりそうな予感。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    //UITableViewCell* cell = [self tableView:tableView cellForRowAtIndexPath:indexPath];
    UITableViewCell* cell = nil;
    if (cell == nil) {
        switch (indexPath.row) {
            case 0: case 1: case 2: case 3:
#ifdef USE_LOG_VIEW
            case 5:
#endif
                return 40.0f;
                break;
            case 4:
                return 220.0f;
                break;
            default:
                break;
        }
        return 31.0f;
    }
    return cell.frame.size.height;
}



/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
