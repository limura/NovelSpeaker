//
//  CoreDataObjectHolder.h
//  CoreDataTest
//
//  Created by IIMURA Takuji on 2014/08/28.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

/// CoreDataObjectHolder のデータが保存されるフォルダのタイプ指定
typedef enum {
    /// iCloud でバックアップされるフォルダタイプ
    /// 保存先が <Application_Home>/Documents になります。
    /// ユーザが生成するデータ（セーブデータなど）のみを置くのが基本らしいです。
    DOCUMENTS_FOLDER_TYPE,
    /// iCloud でバックアップされないフォルダタイプ
    /// 保存先が <Application_Home>/Library/Caches になります。
    /// 再ダウンロード可能なデータはここに置くのが原則らしいです。
    CACHE_FOLDER_TYPE,
} CoreDataObjectHolderFolderType;

/// Core Data の object を保持します。
/// NSManagedObjectContext については ThreadID毎 に作成して保持します。
/// が、このclass自体は thread safe ではないので注意してください。
@interface CoreDataObjectHolder : NSObject
{
    /// 初期化時に指定されたモデル名
    NSString* m_ModelName;
    /// 初期化時に指定されたファイル名
    NSString* m_FileName;
    /// 初期化時に指定されたフォルダタイプ
    CoreDataObjectHolderFolderType m_FolderType;
    /// マージポリシー
    id m_MergePolicy;
    
    NSPersistentStoreCoordinator* m_PersistentStoreCoordinator;
    NSManagedObjectModel* m_ManagedObjectModel;
    NSMutableDictionary* m_Thread_to_NSManagedObjectContext_Dictionary;
}

/// モデル名(XXXX.xcdatamodel の XXXX の部分)、ファイル名、フォルダタイプを指定して初期化します。
/// 生成されるファイルは "ファイル名.sqlite" という名前になります。
/// mergePolicy は、NSErrorMergePolicy(default) や NSMergeByPropertyObjectTrumpMergePolicy 等を与えます。
- (CoreDataObjectHolder*)initWithModelName:(NSString*)modelName fileName:(NSString*)fileName folderType:(CoreDataObjectHolderFolderType)folderType mergePolicy:(id)mergePolicy;

/// SQLiteのファイルが存在するかどうかを取得します
- (BOOL)isAliveSaveDataFile;

/// 古いディレクトリにSQLiteのファイルが存在するかどうかを取得します
- (BOOL)isAliveOLDSaveDataFile;

/// 古いディレクトリにあるSQLiteのファイルを新しいディレクトリに移動します
- (BOOL)moveOLDSaveDataFileToNewLocation;

/// マイグレーションが必要かどうかを取得します。
- (BOOL)isNeedMigration;

/// マイグレーションを行います。(マイグレーションが終了するか、失敗するまで帰りません)
- (BOOL)doMigration;

/// 保存している .sqlite ファイルを削除します。
- (void)deleteStoreFile;

/// 今のthreadでのデータを sync した後、ファイルへの保存を行います。
- (BOOL)save;

/// NSManagedObjectModel を取得します。
/// これを呼び出した時点ではマイグレーションはかかりません。
- (NSManagedObjectModel*)GetManagedObjectModel;

/// NSPersistentStoreCoordinator を取得します。
/// これを呼び出した時点でマイグレーションの必要があればマイグレーションが走ります。
/// つまりマイグレーションが終わるまで帰ってきませんので、
/// 先に isNeedMigration でマイグレーションの要不要を判定してから呼び出すようにしてください。
- (NSPersistentStoreCoordinator*)GetPersistentStoreCoordinator;

/// NSManagedObjectContext を取得します。
/// 呼び出された Thread毎 に object を生成して返します。
/// こちらも GetPersistentStoreCoordinator と同じように呼び出した時点で
/// マイグレーションがかかる可能性があります。
- (NSManagedObjectContext*)GetManagedObjectContextForThisThread;


// 以下 utility method

/// 新しい Entity を生成して返します
- (id)CreateNewEntity:(NSString*)entityName;

/// Entity を一つ削除します
- (void)DeleteEntity:(NSManagedObject*)entity;

/// 全ての Entity を検索して返します
- (NSArray*)FetchAllEntity:(NSString*)entityName;

/// 登録されている Entity の個数を取得します
- (NSUInteger)CountEntity:(NSString*)entityName;

/// 全ての Entity を検索して返します(sort用のattribute指定版)
- (NSArray*)FetchAllEntity:(NSString*)entityName sortAttributeName:(NSString*)sortAttributeName ascending:(BOOL)ascending;

/// Entity を検索して返します(検索用の NSPredicate 指定版)
/// NSPredicate は [NSPredicate predicateWithFormat:@"ncode == %@", ncode] とかそんな感じで作ります。
- (NSArray*)SearchEntity:(NSString*)entityName predicate:(NSPredicate*)predicate;

/// Entity を検索して返します(検索用の NSPredicate と sort用のattribute指定版)
- (NSArray*)SearchEntity:(NSString*)entityName predicate:(NSPredicate*)predicate sortAttributeName:(NSString*)sortAttributeName ascending:(BOOL)ascending;

/// 登録されている Entity の個数を取得します(検索用の NSPredicate 指定版)
- (NSUInteger)CountEntity:(NSString*)entityName predicate:(NSPredicate*)predicate;

/// 現在のthreadでの NSManagedObjectContext で、performBlockAndWait を実行します。
- (void)performBlockAndWait:(void(^)(void))block;

@end
