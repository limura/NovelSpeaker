//
//  CoreDataObjectHolder.m
//  CoreDataTest
//
//  Created by IIMURA Takuji on 2014/08/28.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "CoreDataObjectHolder.h"
#import <CoreData/CoreData.h>
#import "LPPerformanceChecker.h"

@implementation CoreDataObjectHolder

+ (NSObject*)GetSyncObject{
    static NSObject* syncObject = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        syncObject = [NSObject new];
    });
    return syncObject;
}

/// モデル名(XXXX.xcdatamodel の XXXX の部分)、ファイル名、フォルダタイプを指定して初期化します。
/// 生成されるファイルは "ファイル名.sqlite" という名前になります。
- (CoreDataObjectHolder*)initWithModelName:(NSString*)modelName fileName:(NSString*)fileName folderType:(CoreDataObjectHolderFolderType)folderType mergePolicy:(id)mergePolicy
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    m_ModelName = modelName;
    m_FileName = fileName;
    m_FolderType = folderType;
    m_MergePolicy = mergePolicy;

    m_PersistentStoreCoordinator = nil;
    m_ManagedObjectModel = nil;
    m_Thread_to_NSManagedObjectContext_Dictionary = [NSMutableDictionary new];
    //m_MergeThreadManagedObjectContext = nil;
    //m_MergeThreadDispatchQueue = dispatch_get_main_queue();
    //m_MergeThreadDispatchQueue = dispatch_queue_create("com.limuraproducts.coredataextension.mergethread", NULL);
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString*)GetCurrentThreadID
{
    return [[NSString alloc] initWithFormat:@"%@", [NSThread currentThread]];
}

/// SQLiteのファイルが存在するかどうかを取得します
- (BOOL)isAliveSaveDataFile
{
    NSURL *storeURL = [self GetSqlFileURL];
    if (storeURL == nil) {
        return false;
    }
    
    NSString* path = [storeURL path];
    if (path == nil) {
        return false;
    }
    
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

/// マイグレーションが必要かどうかを取得します。
- (BOOL)isNeedMigration
{
    NSURL *storeURL = [self GetSqlFileURL];
    NSError* error = nil;
    
    NSDictionary* sourceMetaData =
    [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                               URL:storeURL
                                                             error:&error];
    if (sourceMetaData == nil) {
        return NO;
    } else if (error) {
        NSLog(@"Checking migration was failed (%@, %@)", error, [error userInfo]);
        abort();
    }
    if (false) {
        NSLog(@"metadata:");
        for (NSString* key in sourceMetaData) {
            NSLog(@"%@", key);
        }
        NSLog(@"done.");
    }
    
    BOOL isCompatible = [[self GetManagedObjectModel] isConfiguration:nil
                                     compatibleWithStoreMetadata:sourceMetaData];
    
    return !isCompatible;
}

/// マイグレーションを行います。(マイグレーションが終了するか、失敗するまで帰りません)
- (BOOL)doMigration
{
    // PersistentStoreCoordinator を取得した時点でマイグレーションが走ります。
    if([self GetPersistentStoreCoordinator] == nil)
    {
        return false;
    }
    return true;
}

/// 保存している .sqlite ファイルを削除します。
/// 同時に保持している core data の object は開放されます。
- (void)deleteStoreFile
{
    NSURL* storeURL = [self GetSqlFileURL];
    [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];
    
    m_PersistentStoreCoordinator = nil;
    m_ManagedObjectModel = nil;
    [m_Thread_to_NSManagedObjectContext_Dictionary removeAllObjects];
    //m_MergeThreadManagedObjectContext = nil;
}

/// 今のthreadでのデータを他のthreadに向けて sync します。(ファイルへの保存(セーブ)はしません)
- (BOOL)sync
{
    return [self save];
}

/// writer queue までデータを送り、ファイルへの保存を行います。
- (BOOL)save
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    if (![context hasChanges]) {
        return true;
    }
    __block BOOL result = true;
    [context performBlockAndWait:^{
        NSError* error = nil;
        if (![context save:&error]) {
            NSLog(@"CoreData save error: %@ %@", error, error.userInfo);
            result = false;
        }
    }];
    return result;
}



- (NSManagedObjectModel*)GetManagedObjectModel
{
    if (m_ManagedObjectModel != nil) {
        return m_ManagedObjectModel;
    }
    
    NSURL* modelURL = [[NSBundle mainBundle] URLForResource:m_ModelName withExtension:@"momd"];
    
    m_ManagedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return m_ManagedObjectModel;
}

- (NSURL*)GetStoreDirectoryURL
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *directoryURL = nil;
    
    switch (m_FolderType) {
        case DOCUMENTS_FOLDER_TYPE:
            directoryURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
            break;
        case CACHE_FOLDER_TYPE:
            directoryURL = [[fileManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
            break;
        default:
            NSLog(@"ERROR: FolderType is unknown.");
            return nil;
            break;
    }
    // フォルダを追加したい場合はこのようにします。
    // [directoryURL URLByAppendingPathComponent:m_SaveFolderName];
    return directoryURL;
}

- (NSURL*)GetSqlFileURL
{
    return [[[self GetStoreDirectoryURL] URLByAppendingPathComponent:m_FileName] URLByAppendingPathExtension:@"sqlite"];
}

/// Core Data用にディレクトリを(なければ)作ります。
- (BOOL)CreateCoreDataDirectory
{
    NSURL* directory = [self GetStoreDirectoryURL];
    NSError* err = nil;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:[directory path] withIntermediateDirectories:YES attributes:nil error:&err])
    {
        NSLog(@"can not create directory %@, %@", err, [err userInfo]);
        return NO;
    }
    return YES;
}

- (NSPersistentStoreCoordinator*)GetPersistentStoreCoordinator
{
    if (m_PersistentStoreCoordinator != nil) {
        return m_PersistentStoreCoordinator;
    }
    
    NSManagedObjectModel* model = [self GetManagedObjectModel];
    if (model == nil) {
        NSLog(@"NSManagedObjectModel load failed.");
        return nil;
    }
    
    [self CreateCoreDataDirectory];

    NSError* error = nil;
    NSURL* fileURL = [self GetSqlFileURL];
    
    NSDictionary* migrateOptions =
        [[NSDictionary alloc] initWithObjectsAndKeys:
         [NSNumber numberWithBool:YES]
         , NSMigratePersistentStoresAutomaticallyOption
         , [NSNumber numberWithBool:YES]
         , NSInferMappingModelAutomaticallyOption
         , nil];

    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:fileURL options:migrateOptions error:&error]) {
        NSLog(@"ERROR: PersistentStoreCoordinator load failed. %@, %@", error, [error userInfo]);
        return nil;
    }
    // 成功したのでこのまま返して終了です。
    m_PersistentStoreCoordinator = coordinator;
    return coordinator;
}

/// NSManagedObjectContext:save:error が他のthreadで行われた時の Notification のレシーバ(MainThread用)
- (void)mergeChanges:(NSNotification*)notification
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    [context performBlock:^{
        [context mergeChangesFromContextDidSaveNotification:notification];
    }];
}

/// NSManagedObjectContext を取得します。
/// 呼び出された Thread毎 に object を生成して返します。
/// こちらも GetPersistentStoreCoordinator と同じように呼び出した時点で
/// マイグレーションがかかる可能性があります。
- (NSManagedObjectContext*)GetManagedObjectContextForThisThread
{
    // 最初に検索してあればそれを返します。
    NSString* threadID = [self GetCurrentThreadID];
    NSManagedObjectContext* context = [m_Thread_to_NSManagedObjectContext_Dictionary objectForKey:threadID];
    if (context != nil) {
        return context;
    }
    
    // 無いようなので作成します。
    
    // とりあえず何を作るにも NSPersistentStoreCoordinator は必要なので取得します。
    NSPersistentStoreCoordinator *coordinator = [self GetPersistentStoreCoordinator];
    if (coordinator == nil) {
        NSLog(@"ERROR: NSPersistentStoreCoordinator is null. Can not create NSManagedObjectContext.");
        return nil;
    }
    
    // その thread用 の ManagedObjectContext を生成します。
    if ([NSThread isMainThread]) {
        context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    }else{
        context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    }
    // 親は Main です。
    //[context setParentContext:m_MainManagedObjectContext];
    [context setPersistentStoreCoordinator:coordinator];
    [context setMergePolicy:m_MergePolicy];
    
    // 他のthread の context で書き換えが起きた時の Notification ハンドラを登録します。
    NSNotificationCenter *notify = [NSNotificationCenter defaultCenter];
    [notify addObserver:self
               selector:@selector(mergeChanges:)
                   name:NSManagedObjectContextDidSaveNotification
                 object:context];
    // m_Thread_to_NSManagedObjectContext_Dictionary に登録します。
    [m_Thread_to_NSManagedObjectContext_Dictionary setObject:context forKey:threadID];

    return context;
}


//------------------------------------------------------------
//   utility methods.
//------------------------------------------------------------

/// 新しい Entity を生成して返します
- (id)CreateNewEntity:(NSString*)entityName
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSDate* startDate = [NSDate date];
    id entity = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
    [LPPerformanceChecker CheckTimeInterval:@"CreateNewEntity時間かかりすぎ" startDate:startDate logTimeInterval:1.0f];
    return entity;
}

/// Entity を一つ削除します
- (void)DeleteEntity:(NSManagedObject*)entity
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSDate* startDate = [NSDate date];
    [context deleteObject:entity];
    [LPPerformanceChecker CheckTimeInterval:@"DeleteEntity時間かかりすぎ" startDate:startDate logTimeInterval:1.0f];
}

/// 全ての Entity を検索して返します
- (NSArray*)FetchAllEntity:(NSString*)entityName
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    
    NSError* err = nil;
    NSArray* results = nil;
    NSDate* startDate = [NSDate date];
    results = [context executeFetchRequest:fetchRequest error:&err];
    [LPPerformanceChecker CheckTimeInterval:[[NSString alloc] initWithFormat:@"FetchAllEntity (%@) 時間かかりすぎ", entityName] startDate:startDate logTimeInterval:1.0f];
    if (err != nil) {
        NSLog(@"CoreData fetchRequest failed. %@ %@", err, err.userInfo);
        results = nil;
    }
    return results;
}

/// 登録されている Entity の個数を取得します
- (NSUInteger)CountEntity:(NSString*)entityName
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSUInteger count = 0;
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    
    // 数を数えるだけなのでidしか返却しないようにします。
    [fetchRequest setIncludesPropertyValues:NO];
    
    NSError* err = nil;
    NSArray* results;
    NSDate* startDate = [NSDate date];
    results = [context executeFetchRequest:fetchRequest error:&err];
    [LPPerformanceChecker CheckTimeInterval:[[NSString alloc] initWithFormat:@"CountEntity (%@) 時間かかりすぎ", entityName] startDate:startDate logTimeInterval:1.0f];
  
    if (err != nil) {
        NSLog(@"CoreData fetchRequest failed. %@ %@", err, err.userInfo);
        count = 0;
    }else{
        count = [results count];
    }
    return count;
}


/// 全ての Entity を検索して返します(sort用のattribute指定版)
- (NSArray*)FetchAllEntity:(NSString*)entityName sortAttributeName:(NSString*)sortAttributeName ascending:(BOOL)ascending
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSArray* results = nil;
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:sortAttributeName ascending:ascending];
    NSArray* sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    NSError* err = nil;
    NSDate* startDate = [NSDate date];
    results = [context executeFetchRequest:fetchRequest error:&err];
    [LPPerformanceChecker CheckTimeInterval:[[NSString alloc] initWithFormat:@"FetchAllEntity %@ sortAttributeName: %@ 時間かかりすぎ", entityName, sortAttributeName] startDate:startDate logTimeInterval:1.0f];
    if (err != nil) {
        NSLog(@"CoreData fetchRequest failed. %@ %@", err, err.userInfo);
        results = nil;
    }

    return results;
}

/// Entity を検索して返します(検索用の NSPredicate 指定版)
- (NSArray*)SearchEntity:(NSString*)entityName predicate:(NSPredicate*)predicate
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    
    [fetchRequest setPredicate:predicate];
    
    NSError* err = nil;
    NSArray* results;
    NSDate* startDate = [NSDate date];
    results = [context executeFetchRequest:fetchRequest error:&err];
    [LPPerformanceChecker CheckTimeInterval:[[NSString alloc] initWithFormat:@"SearchEntity %@ predicate: %@ 時間かかりすぎ", entityName, predicate] startDate:startDate logTimeInterval:1.0f];
    if (err != nil) {
        NSLog(@"CoreData fetchRequest failed. %@ %@", err, err.userInfo);
        return nil;
    }

    return results;
}

/// Entity を検索して返します(検索用の NSPredicate と sort用のattribute指定版)
- (NSArray*)SearchEntity:(NSString*)entityName predicate:(NSPredicate*)predicate sortAttributeName:(NSString*)sortAttributeName ascending:(BOOL)ascending
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    
    [fetchRequest setPredicate:predicate];

    NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:sortAttributeName ascending:ascending];
    NSArray* sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
    [fetchRequest setSortDescriptors:sortDescriptors];

    NSError* err = nil;
    NSArray* results;
    NSDate* startDate = [NSDate date];
    results = [context executeFetchRequest:fetchRequest error:&err];
    [LPPerformanceChecker CheckTimeInterval:[[NSString alloc] initWithFormat:@"SearchEntity %@ predicate: %@ sortAttributeName: %@ 時間かかりすぎ", entityName, predicate, sortAttributeName] startDate:startDate logTimeInterval:1.0f];
    if (err != nil) {
        NSLog(@"CoreData fetchRequest failed. %@ %@", err, err.userInfo);
        return nil;
    }
    
    return results;
}


/// 登録されている Entity の個数を取得します(検索用の NSPredicate 指定版)
- (NSUInteger)CountEntity:(NSString*)entityName predicate:(NSPredicate*)predicate
{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
    [fetchRequest setEntity:entity];
    
    [fetchRequest setPredicate:predicate];

    // 数を数えるだけなのでidしか返却しないようにします。
    [fetchRequest setIncludesPropertyValues:NO];

    NSError* err = nil;
    NSArray* results;
    NSDate* startDate = [NSDate date];
    results = [context executeFetchRequest:fetchRequest error:&err];
    [LPPerformanceChecker CheckTimeInterval:[[NSString alloc] initWithFormat:@"CountEntity %@ predicate: %@ 時間かかりすぎ", entityName, predicate] startDate:startDate logTimeInterval:1.0f];
    if (err != nil) {
        NSLog(@"CoreData fetchRequest failed. %@ %@", err, err.userInfo);
        return 0;
    }

    return [results count];
}

/// 現在のthreadでの NSManagedObjectContext で、performBlockAndWait を実行します。
- (void)performBlockAndWait:(void(^)(void))block{
    NSManagedObjectContext* context = [self GetManagedObjectContextForThisThread];
    @synchronized([CoreDataObjectHolder GetSyncObject]){
        [context performBlockAndWait:^{
            block();
        }];
    }
}


@end
