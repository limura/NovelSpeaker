//
//  SpeechModSettingsTableViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeechModSettingsTableViewController.h"
#import "GlobalDataSingleton.h"
#import "CreateSpeechModSettingViewController.h"

@interface SpeechModSettingsTableViewController ()

@end

static NSString* const speechModSettingsTableViewDefaultCellID = @"speechModSettingsTableViewDefaultCell";

@implementation SpeechModSettingsTableViewController

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
    
    m_Speaker = [Speaker new];
    [m_Speaker SetVoiceWithIdentifier:[[GlobalDataSingleton GetInstance] GetVoiceIdentifier]];
    
    // 追加ボタンとEditボタンをつけます。
    UIBarButtonItem* addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonClicked)];
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:addButton, self.editButtonItem, nil];

    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)addButtonClicked
{
    [self performSegueWithIdentifier:@"newSpeechSettingSegue" sender:self];
}

- (SpeechModSettingCacheData*)GetSpeechModSettingFromRow:(long)row
{
    NSArray* speechModSettingArray = [[GlobalDataSingleton GetInstance] GetAllSpeechModSettings];
    if (speechModSettingArray == nil || [speechModSettingArray count] <= row) {
        return nil;
    }
    
    return [speechModSettingArray objectAtIndex:row];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray* speechModSettingArray = [[GlobalDataSingleton GetInstance] GetAllSpeechModSettings];
    if (speechModSettingArray == nil) {
        return 0;
    }
    return [speechModSettingArray count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:speechModSettingsTableViewDefaultCellID forIndexPath:indexPath];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:speechModSettingsTableViewDefaultCellID];
    }
    
    SpeechModSettingCacheData* modSetting = [self GetSpeechModSettingFromRow:indexPath.row];
    if (modSetting == nil) {
        cell.textLabel.text = @"-";
    }else{
        cell.textLabel.text = [[NSString alloc] initWithFormat:NSLocalizedString(@"SpeechModSettingsTableViewController_DisplayPattern", @"\"%@\" を \"%@\" に"), modSetting.beforeString, modSetting.afterString];
    }
    return cell;
}

- (void)NewSpeechModSettingAdded
{
    [self.tableView reloadData];
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}

// スワイプでは削除させない
// from http://codingcafe.jp/uitableview%E3%81%A7%E3%82%B9%E3%83%AF%E3%82%A4%E3%83%97%E5%89%8A%E9%99%A4%E3%82%92%E7%84%A1%E5%8A%B9%E3%81%AB/
- (UITableViewCellEditingStyle)tableView:(UITableView *)aTableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Detemine if it's in editing mode
    if (self.editing) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        SpeechModSettingCacheData* modSetting = [self GetSpeechModSettingFromRow:indexPath.row];
        if (modSetting != nil) {
            [[GlobalDataSingleton GetInstance] DeleteSpeechModSetting:modSetting];
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}

// セルが選択された時
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SpeechModSettingCacheData* modSetting = [self GetSpeechModSettingFromRow:indexPath.row];
    if (modSetting == nil) {
        return;
    }
    NSString* sampleText = [[NSString alloc] initWithFormat:NSLocalizedString(@"SpeechModSettingsTableViewController_SpeakTestPattern", @"%@を%@に"), modSetting.beforeString, modSetting.afterString];
    [m_Speaker Speech:sampleText];
}
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

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    if ([[segue identifier] isEqualToString:@"newSpeechSettingSegue"])
    {
        CreateSpeechModSettingViewController* controller = [segue destinationViewController];
        controller.createNewSpeechModSettingDelegate = self;
    }
}

@end
