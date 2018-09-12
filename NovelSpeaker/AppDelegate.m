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
#import "UriLoader.h"

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

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSSetUncaughtExceptionHandler(&uncaughtExceptionHandler);
    
    // Override point for customization after application launch.
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    if ([globalData isAliveCoreDataSaveFile] == false) {
        if (![globalData isAliveOLDSaveDataFile] || ![globalData moveOLDSaveDataFileToNewLocation]){
            [globalData InsertDefaultSetting];
        }
    }
    
    // background fetch activate
    if ([globalData GetBackgroundNovelFetchEnabled] == true) {
        [globalData StartBackgroundFetch];
    }
    
    UIViewController* toplevelViewController = nil;
    if ([globalData isRequiredCoreDataMigration]) {
        UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"coreDataMigration" bundle:nil];
        toplevelViewController = [storyboard instantiateInitialViewController];
    }else{
        UIStoryboard* storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        toplevelViewController = [storyboard instantiateInitialViewController];
    }
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = toplevelViewController;
    [self.window makeKeyAndVisible];
    
    // CookieStorageを健全化しておきます……(´・ω・`)
    [UriLoader RemoveInvalidKeyDataFromCookieStorage:[NSHTTPCookieStorage sharedHTTPCookieStorage]];
    
    // "************" でハングするようなので強制的に読み替え辞書に登録して安全な文字に読み変えるようにします(´・ω・`)
    [globalData ForceOverrideHungSpeakStringToSpeechModSettings];
    
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
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    NSLog(@"application will enter foreground.");
    // badge clear.
    application.applicationIconBadgeNumber = -1;
    [[GlobalDataSingleton GetInstance] UpdateBackgroundFetchedNovelCount:0];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    //NSLog(@"application did become active.");
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData HandleAppGroupQueue];
    // BackgroundFetchが有効な設定であれば起動時に有効化します。
    if ([globalData GetBackgroundNovelFetchEnabled] == true) {
        [globalData StartBackgroundFetch];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    NSLog(@"application will terminate");
    [[GlobalDataSingleton GetInstance] saveContext];
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    return [globalData ProcessURL:url];
}

// iOS9 で deprecated になったらしい。
// https://qiita.com/ShingoFukuyama/items/e85d34360f3f951ca612
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    return [globalData ProcessURL:url];
}

// for background fetch
- (void)application:(UIApplication *)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData HandleBackgroundFetch:application performFetchWithCompletionHandler:completionHandler];
}


@end
