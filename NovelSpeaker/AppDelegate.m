//
//  AppDelegate.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "AppDelegate.h"
#import "GlobalDataSingleton.h"
#import <AVFoundation/AVFoundation.h>
#import "NovelSpeaker-Swift.h"
#import "FTLinearActivityIndicator-Swift.h"

@implementation AppDelegate
    
// EXC_BAD_ACCESS とかでスタックトレースが観たい
// http://qiita.com/exilias/items/485fda81e3d237cb03c2
void uncaughtExceptionHandler(NSException *exception)
{
    NSLog(@"CRASH: %@", exception);
    NSLog(@"Stack Trace: %@", [exception callStackSymbols]);
    [BehaviorLogger AddLogWithDescription:@"UncaughtException" data:@{
       @"description": [exception description],
       @"stack trace": [[exception callStackSymbols] componentsJoinedByString:@"\n"]
       }];
}

- (void)setPreferredFontForTextStyleByAppearance{
    // from http://koze.hatenablog.jp/entry/2015/06/03/000000
    // UINavigationBar title
    [[UINavigationBar appearance] setTitleTextAttributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]}];
    // UIBarButtonItem title
    [[UIBarButtonItem appearance] setTitleTextAttributes:
     @{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody]}
     forState:UIControlStateNormal];
    [[UIBarButtonItem appearance] setTitleTextAttributes:
     @{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody]}
        forState:UIControlStateHighlighted];
    // UITabBarItem title
    [[UITabBarItem appearance] setTitleTextAttributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody]}
                                             forState:UIControlStateNormal];
    // UISegmentedControl title
    [[UISegmentedControl appearance] setTitleTextAttributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody]}
                                                   forState:UIControlStateNormal];
    // UISearchBar text and placeholder
    //[[UITextField appearanceWhenContainedInInstancesOfClasses:[UISearchBar class]] setFont:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    // Override point for customization after application launch.
    
    // TODO: RunLoop のを使わないのであれば消す
    //[RealmUtil startRealmRunLoopThread];
    [NovelSpeakerUtility StartAllLongLivedOperationIDWatcher];
    
    // realm の data file は
    // 起動時に iCloud か local の realm file しか無い状態にしておきます。
    // これは iCloud同期 を ON/OFF しようとした時に、
    // 逆側の realm file を掴んだままの realm object が存在するなどの理由で
    // その逆側の realm file を削除することができない事が原因になっています。
    // 例えば iCloud同期 を OFF から ON の状態にした直後に
    // 再度 ON から OFF にしたとします。
    // この時、OFF から ON にした時は iCloud 側の realm file は存在しなかったため
    // 正常に作成して iCloud側 のデータを保存できますが、
    // ON から OFF にした時には
    // 起動時から存在していた local側 の realm file が消せずに残っているために
    // それを作成しなおす事ができません。
    // それにも関わらず realm object は作成できてしまうようで、
    // メモリにのみ残った状態でなんとなく動作してしまうみたいなのですが、
    // メモリにのみデータが載っているので
    // アプリを再起動すると全てのデータが消えてしまう、という事になります。
    // という事で、「iCloud同期 の ON/OFF を切り替える場合、
    // 切り替え先の realm file が存在しない場合にのみそれを許す」という事にして、
    // アプリの起動時には「現在使用中の realm file ではない方の realm file は消す」
    // という運用にすることにします。
    if ([RealmUtil IsUseCloudRealm]) {
        [RealmUtil RemoveLocalRealmFile];
    }else{
        [RealmUtil RemoveCloudRealmFile];
    }
    
    UIViewController* toplevelViewController = nil;
    // 強制的に localRealm を消す場合はこうします
    //[CoreDataToRealmTool UnregisterConvertFromCoreDataFinished];
    //[RealmUtil RemoveLocalRealmFile];
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    if ([globalData isRequiredCoreDataMigration] || [CoreDataToRealmTool IsNeedMigration]) {
        UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"coreDataMigration" bundle:nil];
        toplevelViewController = [storyboard instantiateInitialViewController];
    }else{
        [NovelSpeakerUtility InsertDefaultSettingsIfNeeded];
        [NovelSpeakerUtility ForceOverrideHungSpeakStringToSpeechModSettings];
        UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        toplevelViewController = [storyboard instantiateInitialViewController];
    }
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = toplevelViewController;
    [self.window makeKeyAndVisible];
    
    // CookieStorageを健全化しておきます……(´・ω・`)
    [NovelSpeakerUtility RemoveInvalidKeyDataFromCookieStorageWithStorage:[NSHTTPCookieStorage sharedHTTPCookieStorage]];
    
    // for FTLinearActivityIndicator enable (iPhone X とかのノッチのあるタイプでの network activity indicator を上書きしてくれる奴を enable にする)
    [UIApplication configureLinearNetworkActivityIndicatorIfNeeded];

    // DynamicType 対応
    [self setPreferredFontForTextStyleByAppearance];
    
    [[NovelDownloadQueue shared] StartBackgroundFetchIfNeeded];
    [[NovelDownloadQueue shared] ClearDownloadCountBadge];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    NSLog(@"application did enter background.");
    [[GlobalDataSingleton GetInstance] saveContext];
    [RealmUtil SetCheckCloudDataIsValidInterruptWithIsInterrupt:true];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    NSLog(@"application did become active.");
    // badge clear.
    [[NovelDownloadQueue shared] ClearDownloadCountBadge];
    // BackgroundFetchが有効な設定であれば有効化します。
    [[NovelDownloadQueue shared] StartBackgroundFetchIfNeeded];
    if ([RealmUtil IsUseCloudRealm]) {
        [RealmUtil CloudPull];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    NSLog(@"application will terminate");
    [[GlobalDataSingleton GetInstance] saveContext];
    [NovelDownloadQueue DownloadFlush];
    if ([RealmUtil IsUseCloudRealm]) {
        [RealmUtil CloudPull];
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options{
    return [NovelSpeakerUtility ProcessURLWithUrl:url];
    //GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    //return [globalData ProcessURL:url];
}

// iOS9 で deprecated になったらしい。
// https://qiita.com/ShingoFukuyama/items/e85d34360f3f951ca612
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
{
    return [NovelSpeakerUtility ProcessURLWithUrl:url];
    //GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    //return [globalData ProcessURL:url];
}

// for background fetch
- (void)application:(UIApplication *)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler{
    [[NovelDownloadQueue shared] HandleBackgroundFetchWithApplication:application performFetchWithCompletionHandler:completionHandler];
}


@end
