//
//  SettingsTableViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeakSettingsTableViewController.h"
#import "DefaultSpeakSettingEditTableViewCell.h"
#import "SpeakSettingEditTableViewCell.h"
#import "SpeakSettingSampleTextTableViewCell.h"
#import "GlobalDataSingleton.h"
#import "NovelSpeaker-Swift.h"

@interface SpeakSettingsTableViewController ()

@end

@implementation SpeakSettingsTableViewController

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
    [BehaviorLogger AddLogWithDescription:@"SpeakSettingsTableViewController viewDidLoad" data:@{}];

    // 追加ボタンとEditボタンをつけます。
    UIBarButtonItem* addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonClicked)];
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:addButton, self.editButtonItem, nil];

    testSpeechSampleText = NSLocalizedString(@"SpeakSettingsTableViewController_ReadTheSentenceForTest", @"ここに書いた文をテストで読み上げます。");
    m_Speaker = [Speaker new];
    [m_Speaker SetVoiceWithIdentifier:[[GlobalDataSingleton GetInstance] GetVoiceIdentifier]];
    m_EasyAlert = [[EasyAlert alloc] initWithViewController:self];
    
    UINib* defaultSpeakSettingTableViewCellNib = [UINib nibWithNibName:DefaultSpeakSettingEditTableViewCellID bundle:nil];
    [self.tableView registerNib:defaultSpeakSettingTableViewCellNib forCellReuseIdentifier:DefaultSpeakSettingEditTableViewCellID];
    UINib* speakSettingTableViewCellNib = [UINib nibWithNibName:SpeakSettingEditTableViewCellID bundle:nil];
    [self.tableView registerNib:speakSettingTableViewCellNib forCellReuseIdentifier:SpeakSettingEditTableViewCellID];
    UINib* speakSettingSampleTextTableViewCellNib = [UINib nibWithNibName:SpeakSettingSampleTextTableViewCellID bundle:nil];
    [self.tableView registerNib:speakSettingSampleTextTableViewCellNib forCellReuseIdentifier:SpeakSettingSampleTextTableViewCellID];
    
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

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self addNotificationReceiver];
}

- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self removeNotificationReciever];
}

- (void)addNotificationReceiver{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(displayUpdateNeededNotificationReciever:) name:@"ConfigReloaded_DisplayUpdateNeeded" object:nil];
}

- (void)removeNotificationReciever{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)displayUpdateNeededNotificationReciever:(NSNotification*)notification{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

// テキストフィールドでEnterが押された
- (BOOL)textFieldShouldReturn:(UITextField *)sender {
    // キーボードを閉じる
    [sender resignFirstResponder];
    
    return TRUE;
}

- (void)addButtonClicked
{
    [self performSegueWithIdentifier:@"newSpeakSettingSegue" sender:self];
}

/// pitchの設定が追加された場合に呼び出されます
- (void)NewPitchSettingAdded
{
    [self.tableView reloadData];
}

#pragma mark - Table view data source

/// セクションの数を聞かれて答える
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

/// セクション毎の項目の数を聞かれて答える
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case 0:
            return 2 + [[[GlobalDataSingleton GetInstance] GetAllSpeakPitchConfig] count];
            break;
        default:
            break;
    }
    return 0;
}

/// 発音設定用の読み上げサンプルテキストボックスの TableViewCell を返します。
- (UITableViewCell*)getSpeakSettingSampleTestTextTableViewCell:(UITableView*)tableView
{
    SpeakSettingSampleTextTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:SpeakSettingSampleTextTableViewCellID];
    if (cell == nil) {
        cell = [[SpeakSettingSampleTextTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:SpeakSettingSampleTextTableViewCellID];
    }
    cell.testSpeakDelegate = self;
    
    return cell;
}

/// default の発音設定用の TableViewCell を返します。
- (UITableViewCell*)getDefaultSpeakSettingEditTableViewCell:(UITableView*)tableView
{
    DefaultSpeakSettingEditTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:DefaultSpeakSettingEditTableViewCellID];
    if (cell == nil) {
        cell = [[DefaultSpeakSettingEditTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DefaultSpeakSettingEditTableViewCellID];
    }
    cell.testSpeakDelegate = self;
    
    return cell;
}

- (SpeakPitchConfigCacheData*)GetPitchConfigFromTableRow:(long)row
{
    long index = row - 2;
    if (row < 0) {
        return nil;
    }
    NSArray* speakConfigArray = [[GlobalDataSingleton GetInstance] GetAllSpeakPitchConfig];
    if (index >= [speakConfigArray count]) {
        return nil;
    }
    SpeakPitchConfigCacheData* config = [speakConfigArray objectAtIndex:index];
    return config;
}

/// 発音設定用の TableViewCell を返します。
- (UITableViewCell*)getSpeakSettingEditTableViewCell:(UITableView*)tableView row:(long)row
{
    SpeakPitchConfigCacheData* config = [self GetPitchConfigFromTableRow:row];
    if (config == nil) {
        return nil;
    }
    
    SpeakSettingEditTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:SpeakSettingEditTableViewCellID];
    if (cell == nil) {
        cell = [[SpeakSettingEditTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:SpeakSettingEditTableViewCellID];
    }

    cell.testSpeakDelegate = self;
    cell.titleLabel.text = config.title;
    cell.startStringTextField.text = config.startText;
    cell.endStringTextField.text = config.endText;
    cell.pitchSlider.value = [config.pitch floatValue];
    
    return cell;
}

/// tableViewCell の縦の長さを返します。
/// TODO: 多分これはスクロールバーを表示させるために全部のcellに対して呼び出されるのでたくさんのcellがあった場合ひどいことになりそうな予感。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell = [self tableView:tableView cellForRowAtIndexPath:indexPath];
    if (cell == nil) {
        switch (indexPath.row) {
            case 0:
                return 31.0f;
            case 1:
                return 146.0f;
                break;
            default:
                break;
        }
        return 130.0f;
    }
    return cell.frame.size.height;
}

/// セルを取得に来るので返す
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case 0: // 音声設定
            switch (indexPath.row) {
                case 0:
                    return [self getSpeakSettingSampleTestTextTableViewCell:tableView];
                    break;
                case 1:
                    return [self getDefaultSpeakSettingEditTableViewCell:tableView];
                    break;
                default:
                    break;
            }
            return [self getSpeakSettingEditTableViewCell:tableView row:indexPath.row];
            break;
            
        default:
            break;
    }
    return nil;
}

/// テストの読み上げボタンが押された時のイベントハンドラ
- (void) testSpeakWithPitch:(float)pitch rate:(float)rate
{
    [m_Speaker StopSpeech];
    [m_Speaker SetPitch:pitch];
    [m_Speaker SetRate:rate];
    [m_Speaker SetVoiceWithIdentifier:[[GlobalDataSingleton GetInstance] GetVoiceIdentifier]];
    [m_Speaker Speech:testSpeechSampleText];
}

/// テスト読み上げ用の文字列が書き換えられた時のイベントハンドラ
- (void) testSpeakSampleTextUpdate:(NSString*)text
{
    testSpeechSampleText = text;
}

/// TableViewCell から alert を表示したいとのお願いのイベントハンドラ
- (void) showAlert:(NSString*)title message:(NSString*)message {
    [m_EasyAlert ShowAlertOKButton:title message:message];
}


// エディットできるならYESと答える
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    if (indexPath.row < 2) {
        return NO;
    }
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

// テーブルのセルの追加や削除のイベントハンドラ
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        if (indexPath.row >= 2) {
            SpeakPitchConfigCacheData* pitchConfig = [self GetPitchConfigFromTableRow:indexPath.row];
            if (pitchConfig != nil) {
                [[GlobalDataSingleton GetInstance] DeleteSpeakPitchConfig:pitchConfig];
            }
            // Delete the row from the data source
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
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
    if ([[segue identifier] isEqualToString:@"newSpeakSettingSegue"])
    {
        CreateNewSpeakPitchSettingViewController* controller = [segue destinationViewController];
        controller.createNewSpeakPitchSettingDelegate = self;
    }
}



@end
