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
#import "NarouContent.h"
#import "NarouContentAllData.h"

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

/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContent*) SearchNarouContentFromNcode:(NSString*) ncode;

/// 新しい NarouContent を生成して返します。
- (NarouContent*) CreateNewNarouContent;

/// 保存されている NarouContent の数を取得します。
- (NSUInteger) GetNarouContentCount;

/// NarouContent のリストを更新します。
/// 怪しく検索条件を内部で勝手に作ります。
- (BOOL)UpdateContentList;

/// NarouContent の全てを NSArray で取得します
/// novelupdated_at で sort されて返されます。
- (NSMutableArray*) GetAllNarouContent;

/// ダウンロードqueueに追加しようとします
/// 追加した場合は nil を返します。
/// 追加できなかった場合はエラーメッセージを返します。
- (NSString*) AddDownloadQueueForNarou:(NarouContentAllData*) content;

@end
