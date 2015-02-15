//
//  SpeechWaitSettingTableViewController.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import "SpeechWaitSettingTableViewController.h"
#import "GlobalDataSingleton.h"
#import "SpeechWaitSettingViewController.h"
#import "EasyAlert.h"

static NSString* const SpeechWaitSettingTableViewDefaultCellID = @"SpeechWaitSettingTableViewCellDefault";

@interface SpeechWaitSettingTableViewController ()

@end

@implementation SpeechWaitSettingTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    // 追加ボタンとEditボタンをつけます。
    UIBarButtonItem* addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonClicked)];
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:addButton, self.editButtonItem, nil];
    
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];

    [self setNotificationReciver];
}
- (void)dealloc
{
    [self removeNotificationReciver];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)addButtonClicked
{
    m_SelectedWaitConfig = nil;
    [self performSegueWithIdentifier:@"newTextDelaySettingSegue" sender:self];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray* speechWaitConfigList = [[GlobalDataSingleton GetInstance] GetAllSpeechWaitConfig];
    if (speechWaitConfigList == nil) {
        return 2;
    }
    return [speechWaitConfigList count] + 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:SpeechWaitSettingTableViewDefaultCellID forIndexPath:indexPath];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:SpeechWaitSettingTableViewDefaultCellID];
    }
    
    if (indexPath.row == 0) {
        cell.textLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_TargetText_SpeechWaitSettingType", @"読み上げの間の仕組み");
        GlobalStateCacheData* globalStateCache = [[GlobalDataSingleton GetInstance] GetGlobalState];
        if ([globalStateCache.speechWaitSettingUseExperimentalWait boolValue]) {
            cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Experimental", @"非推奨型");
        }else{
            cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Default", @"標準型");
        }
        return cell;
    }
    if (indexPath.row == 1) {
        cell.textLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_TargetText_EnterEnter", @"<改行><改行>");
        cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_Enabled", @"有効");
        return cell;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    NSUInteger targetRow = indexPath.row - 2;
    NSArray* speechWaitConfigList = [[GlobalDataSingleton GetInstance] GetAllSpeechWaitConfig];
    if ([speechWaitConfigList count] <= targetRow) {
        cell.textLabel.text = @"-";
        return cell;
    }
    SpeechWaitConfigCacheData* speechWaitConfigCache = [speechWaitConfigList objectAtIndex:targetRow];
    cell.textLabel.text = speechWaitConfigCache.targetText;
    if ([speechWaitConfigCache.delayTimeInSec floatValue] > 0.0f) {
        cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_Enabled", @"有効");
    }else{
        cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_Disabled", @"無効");
    }
    
    return cell;
}

// 強引に(表示されている？)全ての cell について表示を更新します。
- (void)ReloadAllTableViewData
{
    [self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
    return;
    
    // CoreData 側に save されている数と表示されている数が違うと assertion failure で落ちるので封印します。
    NSArray* speechWaitConfigList = [[GlobalDataSingleton GetInstance] GetAllSpeechWaitConfig];
    for (NSUInteger i = 0; i < [speechWaitConfigList count]; i++) {
        NSIndexPath* indexPath = [NSIndexPath indexPathForRow:i+1 inSection:0];
        UITableViewCell* cell = [self.tableView dequeueReusableCellWithIdentifier:SpeechWaitSettingTableViewDefaultCellID forIndexPath:indexPath];
        if (cell == nil) {
            continue;
        }
        SpeechWaitConfigCacheData* waitConfig = speechWaitConfigList[i];
        NSLog([[NSString alloc] initWithFormat:@"%ld -> %@ %f", i, waitConfig.targetText, [waitConfig.delayTimeInSec floatValue]]);
        if (waitConfig.targetText == nil) {
            cell.textLabel.text = @"-";
        }else{
            cell.textLabel.text = waitConfig.targetText;
        }
        if (waitConfig.delayTimeInSec == nil || [waitConfig.delayTimeInSec floatValue] <= 0.0f) {
            cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_Disabled", @"無効");
        }else{
            cell.detailTextLabel.text = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_Enabled", @"有効");
        }
    }
}


// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0 || indexPath.row == 1) {
        return NO;
    }
    return YES;
}

// 読み上げの間の設定をどのように実行するかを切り替えます
- (BOOL)switchSpeechWaitSettingType
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    GlobalStateCacheData* globalState = [globalData GetGlobalState];
    NSString* newSetting = nil;
    if ([globalState.speechWaitSettingUseExperimentalWait boolValue]) {
        globalState.speechWaitSettingUseExperimentalWait = [[NSNumber alloc] initWithBool:false];
        newSetting = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Default", @"推奨型");
    }else{
        globalState.speechWaitSettingUseExperimentalWait = [[NSNumber alloc] initWithBool:true];
        newSetting = NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Experimental", @"非推奨型");
    }
    bool settingResult = [globalData UpdateGlobalState:globalState];
    if(settingResult != false)
    {
        NSString* title = [[NSString alloc] initWithFormat: NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingUpdated", @"読み上げ設定を%@に更新しました。"), newSetting];
        [m_EasyAlert ShowAlertOneButton:title message:nil okButtonText:NSLocalizedString(@"OK_button", nil) okActionHandler:^(UIAlertAction* action){
            [self.navigationController popViewControllerAnimated:YES];
        }];
    }else{
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingUpdateFailed", @"読み上げ設定の変更に失敗しました。") message:nil];
    }
    return settingResult;
}

// セルが選択された時
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case 0:
            [self switchSpeechWaitSettingType];
            break;
        case 1:
            break;
        default:
        {
            unsigned int i = indexPath.row - 2;
            NSArray* speechWaitConfigList = [[GlobalDataSingleton GetInstance] GetAllSpeechWaitConfig];
            if (speechWaitConfigList == nil || [speechWaitConfigList count] <= i) {
                return;
            }
            m_SelectedWaitConfig = speechWaitConfigList[i];
            [self performSegueWithIdentifier:@"newTextDelaySettingSegue" sender:self];
            break;
        }
    }
}

// 編集されるときに呼び出される。
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSUInteger i = indexPath.row - 2;
        NSArray* speechWaitConfigList = [[GlobalDataSingleton GetInstance] GetAllSpeechWaitConfig];
        if(speechWaitConfigList == nil
           || [speechWaitConfigList count] <= i)
        {
            NSLog(@"indexPath.row is out of range %lu < %ld", (unsigned long)[speechWaitConfigList count], i);
            return;
        }
        SpeechWaitConfigCacheData* waitConfig = speechWaitConfigList[i];
        
        if([[GlobalDataSingleton GetInstance] DeleteSpeechWaitSetting:waitConfig.targetText] != true)
        {
            NSLog(@"delete waitConfig failed targetText: %@", waitConfig.targetText);
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }
}

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    if ([[segue identifier] isEqualToString:@"newTextDelaySettingSegue"]) {
        SpeechWaitSettingViewController* nextViewController = [segue destinationViewController];
        nextViewController.speechWaitConfigCacheData = m_SelectedWaitConfig;
    }
}


- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self ReloadAllTableViewData];
    [viewController viewWillAppear:animated];
}

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self ReloadAllTableViewData];
    [viewController viewDidAppear:animated];
}

/// NotificationCenter の受信者の設定をします。
- (void)setNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    NSString* notificationName = @"SpeechWaitSettingTableViewUpdated";
    [notificationCenter addObserver:self selector:@selector(SpeechWaitSettingUpdated:) name:notificationName object:nil];
}

/// NotificationCenter の受信者の設定を解除します。
- (void)removeNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    
    NSString* notificationName = @"SpeechWaitSettingTableViewUpdated";
    [notificationCenter removeObserver:self name:notificationName object:nil];
}

- (void)SpeechWaitSettingUpdated:(NSNotification*)notification
{
    [self ReloadAllTableViewData];
}

@end
