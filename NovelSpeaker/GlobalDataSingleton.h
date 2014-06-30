//
//  GlobalDataSingleton.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/30.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "GlobalState.h"

/// 全体で共有するようなデータを保持させちゃいます！(ﾟ∀ﾟ)
@interface GlobalDataSingleton : NSObject

/// シングルトンを取得します。
+ (GlobalDataSingleton*)GetInstance;

// Core Data 用
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

/// Core Data用にディレクトリを(なければ)作ります。
- (BOOL)CreateCoreDataDirectory;

/// 保持しているデータをストレージに保存します。
- (void)saveContext;

/// CoreDataが保存する時に使うディレクトリを取得します。
- (NSURL *)applicationDocumentsDirectory;

/// CoreData で保存している GlobalState object (一つしかないはず) を取得します
- (GlobalState*) GetGlobalState;

@end
