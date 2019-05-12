//
//  CoreDataMigrationViewController.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/17.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//
// core data のマイグレーションが必要なときに呼び出される画面。
//

#import "CoreDataMigrationViewController.h"
#import "GlobalDataSingleton.h"
#import "NovelSpeaker-Swift.h"

@interface CoreDataMigrationViewController ()

@end

@implementation CoreDataMigrationViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)goToMainStoryboard {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 通常の main storyboard に移行します。
        UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        UIViewController* firstViewController = [storyboard instantiateInitialViewController];
        [self presentViewController:firstViewController animated:YES completion:NULL];
    });
}

- (void)doRealmMigration {
    dispatch_queue_t queue =
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatch_async(queue, ^{
        if ([CoreDataToRealmTool CheckIsLocalRealmCreated] == false) {
            [CoreDataToRealmTool ClearLocalRealmDataAndConvertFromCoreaDataAndReturnError:nil];
        }
        [self goToMainStoryboard];
    });
}

- (void)doCoreDataMigration
{
    dispatch_queue_t queue =
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatch_async(queue, ^{
        GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
        [globalData doCoreDataMigration];
        [globalData InsertDefaultSetting];
        if ([CoreDataToRealmTool CheckIsLocalRealmCreated] == false) {
            [CoreDataToRealmTool ClearLocalRealmDataAndConvertFromCoreaDataAndReturnError:nil];
        }
        [self goToMainStoryboard];
    });
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [BehaviorLogger AddLogWithDescription:@"CoreDataMigrationViewController viewDidLoad" data:@{}];
    // 戻るボタンを消す
    [self.navigationItem setHidesBackButton:YES];
    
    // core data のマイグレーションを行う
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    if ([globalData isRequiredCoreDataMigration]) {
        [self doCoreDataMigration];
    }else if ([CoreDataToRealmTool CheckIsLocalRealmCreated] == false){
        [self doRealmMigration];
    }else{
        [self goToMainStoryboard];
    }
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

@end
