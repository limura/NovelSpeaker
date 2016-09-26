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
#import "EasyShare.h"
#import "EditUserBookViewController.h"

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
        m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
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
    
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
    
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
    return 11
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
        case 5:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_CreateNewUserText", @"新規自作本の追加");
            break;
        case 6:
            cell.textLabel.text = [[GlobalDataSingleton GetInstance] GetBackgroundNovelFetchEnabled] ?
                NSLocalizedString(@"SettingTableViewController_BackgroundFetch_Enabled", @"新規小説の自動ダウンロード: 有効")
                : NSLocalizedString(@"SettingTableViewController_BackgroundFetch_Disabled", @"新規小説のダウンロード: 無効");
            ;
            break;
        case 7:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_AddDefaultCorrectionOfTheReading", @"標準の読みの修正を上書き追加");
            break;
        case 8:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_GetNcodeDownloadURLScheme", @"再ダウンロード用URLスキームの取得");
            break;
        case 9:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_GoToReleaseLog", @"更新履歴");
            break;
        case 10:
            cell.textLabel.text = NSLocalizedString(@"SettingTableViewController_RightNotation", @"権利表記");
            break;
#ifdef USE_LOG_VIEW
        case 10:
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
        case 0: case 1: case 2: case 3: case 5: case 6: case 7: case 8: case 9: case 10:
#ifdef USE_LOG_VIEW
        case 11:
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

/// 標準で用意された読み上げ辞書を上書き追加します。
- (void)AddDefaultSpeechModSetting
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData InsertDefaultSpeechModConfig];
    
    [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SettingTableViewController_AnAddressAddedAStandardParaphrasingDictionary", @"標準の読み替え辞書を上書き追加しました。") message:nil];
}

/// 標準で用意された読み上げ辞書で上書きして良いか確認した上で、上書き追加します。
- (void)ConfirmAddDefaultSpeechModSetting
{
    [m_EasyAlert ShowAlertTwoButton:NSLocalizedString(@"SettingTableViewController_ConfirmAddDefaultSpeechModSetting", @"確認") message:NSLocalizedString(@"SettingtableViewController_ConfirmAddDefaultSpeechModSettingMessage", @"用意された読み替え辞書を追加・上書きします。よろしいですか？") firstButtonText:NSLocalizedString(@"Cancel_button", @"Cancel") firstActionHandler:nil secondButtonText:NSLocalizedString(@"OK_button", @"OK") secondActionHandler:^(UIAlertAction *alert) {
        [self AddDefaultSpeechModSetting];
    }];
}

/// BackgroundFetch で小説の更新分を取得するか否かの設定をトグルします。
- (void)BackgroundNovelFetchSettingToggle
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    BOOL isEnabled = [globalData GetBackgroundNovelFetchEnabled];
    UIApplication* application = [UIApplication sharedApplication];
    if (isEnabled) {
        [globalData UpdateBackgroundNovelFetchMode:false];
        
        [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalNever];
    }else{
        [m_EasyAlert ShowAlertTwoButton:NSLocalizedString(@"SettingTableViewController_ConfirmEnableBackgroundFetch_title", @"確認") message:NSLocalizedString(@"SettingtableViewController_ConfirmEnableBackgroundFetch", @"この設定を有効にすると、ことせかい を使用していない時等に小説の更新を確認するようになるため、ネットワーク通信が発生するようになります。よろしいですか？") firstButtonText:NSLocalizedString(@"Cancel_button", @"Cancel") firstActionHandler:nil secondButtonText:NSLocalizedString(@"OK_button", @"OK") secondActionHandler:^(UIAlertAction *alert) {
            [globalData UpdateBackgroundNovelFetchMode:true];

            // この時点で Notification を有効化します。
            if (NSFoundationVersionNumber < NSFoundationVersionNumber_iOS_8_0) {
                [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(
                                                                                       UIRemoteNotificationTypeBadge
                                                                                       | UIRemoteNotificationTypeAlert)];
            }else{
                UIUserNotificationSettings* notificationSettings = [UIUserNotificationSettings settingsForTypes:
                                                                    (UIUserNotificationTypeAlert | UIUserNotificationTypeBadge)
                                                                                                     categories:nil];
                [[UIApplication sharedApplication] registerUserNotificationSettings:notificationSettings];
            }
            
            [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
            [self.settingsTableView reloadData];
        }];
    }
    [self.settingsTableView reloadData];
}

/// 現在の本棚にある小説のリストを再ダウンロードするためのURLを取得して、シェアします。
- (void)ShareNcodeListURLScheme
{
    //GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    //[globalData AddDownloadQueueForURL:[[NSURL alloc] initWithString:@"https://kakuyomu.jp/works/1177354054880928816/episodes/1177354054880929986"]];
    NSArray* contentList = [[GlobalDataSingleton GetInstance] GetAllNarouContent:NarouContentSortType_Ncode];
    if (contentList == nil || [contentList count] <= 0) {
        [m_EasyAlert ShowAlertOKButton:NSLocalizedString(@"SettingTableViewController_NoContentHave", @"本棚に本がありません") message:nil];
        return;
    }
    
    NSMutableString* shareText = [[NSMutableString alloc] initWithString:@"novelspeaker://downloadncode/"];
    
    for (NarouContentCacheData* content in contentList) {
        if ([content isUserCreatedContent]) {
            continue;
        }
        [shareText appendString:[[NSString alloc] initWithFormat:@"%@-", content.ncode]];
    }
    NSString* shareURL = [shareText substringToIndex:[shareText length] - 1];

    [m_EasyAlert ShowAlertOneButton:NSLocalizedString(@"SettingTableViewController_ShareNcodeListURLScheme", @"本棚に登録されている小説の再ダウンロードURLスキームを生成します")
                            message:NSLocalizedString(@"SettingTableViewController_ShareNcodeListURLSchemeMessage", @"現在 本棚に登録されている全ての「小説家になろう」の小説を再ダウンロードさせるためのURLを生成しました。\r\nことせかい をアンインストールしてしまっても、このURLを開けばもう一度小説をダウンロードさせることができます。バックアップ用途などに使用してください。(自分宛てに mail するなどが良いかもしれません)")
                       okButtonText:NSLocalizedString(@"OK_button", @"OK") okActionHandler:^(UIAlertAction *action){
                           [EasyShare ShareText:shareURL viewController:self barButton:nil];
                       }];
}

// 新規のユーザ本を追加して、編集ページに遷移する
- (void)CreateNewUserText{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    
    m_EditUserBookViewNarouContent = [globalData CreateNewUserBook];
    [self performSegueWithIdentifier:@"CreateNewUserTextSegue" sender:self];
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
        case 5:
            [self CreateNewUserText];
            break;
        case 6:
            [self BackgroundNovelFetchSettingToggle];
            break;
        case 7:
            [self ConfirmAddDefaultSpeechModSetting];
            break;
        case 8:
            [self ShareNcodeListURLScheme];
            break;
        case 9:
            [self performSegueWithIdentifier:@"updateLogSegue" sender:self];
            break;
        case 10:
            [self performSegueWithIdentifier:@"CreditPageSegue" sender:self];
            break;
#ifdef USE_LOG_VIEW
        case 10:
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
            case 0: case 1: case 2: case 3: case 5: case 6: case 7: case 8: case 9: case 10:
#ifdef USE_LOG_VIEW
            case 11:
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

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    if ([[segue identifier] isEqualToString:@"CreateNewUserTextSegue"]) {
        EditUserBookViewController* nextViewController = [segue destinationViewController];
        nextViewController.NarouContentDetail = m_EditUserBookViewNarouContent;
    }
}


@end
