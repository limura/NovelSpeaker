//
//  GlobalDataSingleton.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/30.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "GlobalDataSingleton.h"
#import <AVFoundation/AVFoundation.h>
#import "NarouLoader.h"
#import "NarouDownloadQueue.h"

@implementation GlobalDataSingleton

// Core Data 用
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize managedObjectModel = _managedObjectModel;
@synthesize managedObjectContext = _managedObjectContext;

static GlobalDataSingleton* _singleton = nil;

- (id)init
{
    self = [super init];

    m_MainQueue = dispatch_get_main_queue();
    // CoreDataアクセス用の直列queueを作ります。
    m_CoreDataAccessQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.coredataaccess", NULL);
    // ダウンロード用の直列queueを作ります。
    m_DownloadQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.download", NULL);
    // コンテンツダウンロード用の直列queueを作ります。
    m_ContentsDownloadQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.contentsdownload", NULL);

    m_CurrentDownloadingContent = nil;

    return self;
}

/// singleton が確保された時に一発だけ走る method
/// CoreData の初期化とかいろいろやります。
- (void) InitializeData
{
    if([self CreateCoreDataDirectory] == NO)
    {
        NSLog(@"WARNING: CreateCoreDataDirectory failed.");
    }
}

+ (GlobalDataSingleton*) GetInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _singleton = [GlobalDataSingleton new];
        [_singleton InitializeData];
    });
    return _singleton;
}


/// CoreData で保存している GlobalState object (一つしかないはず) を取得します
- (GlobalState*) GetGlobalState
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        // CoreData で読みだします
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"GlobalState" inManagedObjectContext: self.managedObjectContext];
        [fetchRequest setEntity:entity];
        err = nil;
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    });
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    if([fetchResults count] == 0)
    {
        // まだ登録されてなかったので新しく作ります。
        __block GlobalState* globalState = nil;
        dispatch_sync(m_CoreDataAccessQueue, ^{
            globalState = (GlobalState*)[NSEntityDescription insertNewObjectForEntityForName:@"GlobalState" inManagedObjectContext:self.managedObjectContext];
        });
        if(globalState == nil)
        {
            NSLog(@"GlobalState create failed.");
            return nil;
        }
        globalState.readLocation = [[NSNumber alloc] initWithInt:0];
        globalState.defaultRate = [[NSNumber alloc] initWithFloat:AVSpeechUtteranceDefaultSpeechRate];
        globalState.defaultPitch = [[NSNumber alloc] initWithFloat:1.0f];
        return globalState;
    }
    if([fetchResults count] > 1)
    {
        NSLog(@"GlobalData count is not 1: %lu", (unsigned long)[fetchResults count]);
        return nil;
    }
    return fetchResults[0];
}

/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContent*) SearchNarouContentFromNcode:(NSString*) ncode
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"NarouContent" inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
    
        NSPredicate* predicate = [NSPredicate predicateWithFormat:@"ncode == %@", ncode];
        [fetchRequest setPredicate:predicate];

        err = nil;
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    });
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    if([fetchResults count] == 0)
    {
        // 何もなかった。
        return nil;
    }
    if([fetchResults count] != 1)
    {
        NSLog(@"duplicate ncode!!! %@", ncode);
        return nil;
    }
    return fetchResults[0];
}

/// 新しい NarouContent を生成して返します。
- (NarouContent*) CreateNewNarouContent
{
    __block NarouContent* content = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        content = [NSEntityDescription insertNewObjectForEntityForName:@"NarouContent" inManagedObjectContext:self.managedObjectContext];
    });
    return content;
}

/// 保存されている NarouContent の数を取得します。
- (NSUInteger) GetNarouContentCount
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"NarouContent" inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
        // 数を数えるだけなのでidしか返却しないようにします。
        [fetchRequest setIncludesPropertyValues:NO];

        err = nil;
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    });
    if(fetchResults == nil)
    {
        return 0;
    }
    return [fetchResults count];
}

/// NarouContent のリストを更新します。
/// 怪しく検索条件を内部で勝手に作ります。
- (BOOL)UpdateContentList
{
    NarouLoader* loader = [NarouLoader new];
    return [loader UpdateContentList];
}

/// NarouContent の全てを NSArray で取得します
/// novelupdated_at で sort されて返されます。
- (NSMutableArray*) GetAllNarouContent
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"NarouContent" inManagedObjectContext:    self.managedObjectContext];
        [fetchRequest setEntity:entity];

        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"novelupdated_at" ascending:NO];
        NSArray* sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
        [fetchRequest setSortDescriptors:sortDescriptors];

        err = nil;
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    });
    if(err != nil)
    {
        NSLog(@"fetch failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    return fetchResults;
}

/// 新しい DownloadQueue を生成します。
/// 生成された DownloadQueue.sort_index は、現在登録されている一番番号の大きいものよりも大きな値に設定されます。
- (DownloadQueue*)CreateNewDownloadQueue
{
    __block DownloadQueue* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        // まずは sort_index の一番数の多いものを取得します。
        NSError* err = nil;
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"DownloadQueue" inManagedObjectContext:    self.managedObjectContext];
        [fetchRequest setEntity:entity];
        
        NSExpression* expressionKeyPath = [NSExpression expressionForKeyPath:@"sort_index"];
        NSExpression* expression = [NSExpression expressionForFunction:@"max:" arguments:[NSArray arrayWithObject:expressionKeyPath]];
        
        NSExpressionDescription* description = [NSExpressionDescription new];
        [description setName:@"max_sort_index"];
        [description setExpression:expression];
        [description setExpressionResultType:NSInteger32AttributeType];
        [fetchRequest setResultType:NSDictionaryResultType];
        [fetchRequest setPropertiesToFetch:[NSArray arrayWithObject:description]];
        
        err = nil;
        NSMutableArray* fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
        
        int max_sort_index = 0;
        if (fetchResults != nil && [fetchResults count] >= 1) {
            max_sort_index = [[fetchResults[0] valueForKey:@"max_sort_index"] intValue];
        }
        
        // 最大値が得られたので、それに +1 することで最新のものの index とします。
        int new_sort_index = max_sort_index + 1;
        
        // 新しい DownloadQueue を生成します。
        result = [NSEntityDescription insertNewObjectForEntityForName:@"DownloadQueue" inManagedObjectContext:self.managedObjectContext];
        // sort_index を設定します。
        result.sort_index = [[NSNumber alloc] initWithInt:new_sort_index];
    });
    
    return result;
}

/// ダウンロードqueueに追加しようとします
/// 追加した場合は nil を返します。
/// 追加できなかった場合はエラーメッセージを返します。
- (NSString*) AddDownloadQueueForNarou:(NarouContentAllData*) content
{
    if(content == nil || content.ncode == nil || [content.ncode length] <= 0)
    {
        return @"有効な NCODE を取得できませんでした。";
    }
    NSString* targetNcode = content.ncode;
    __block NarouContent* targetContent = [self SearchNarouContentFromNcode:targetNcode];
    if (targetContent == nil) {
        // 登録がないようなのでとりあえず NarouContent を登録します。
        targetContent = [self CreateNewNarouContent];
        dispatch_sync(m_CoreDataAccessQueue, ^{
            targetContent.title = content.title;
            targetContent.ncode = content.ncode;
            targetContent.userid = content.userid;
            targetContent.writer = content.writer;
            targetContent.story = content.story;
            targetContent.genre = content.genre;
            targetContent.keyword = content.keyword;
            targetContent.general_all_no = content.general_all_no;
            targetContent.end = content.end;
            targetContent.global_point = content.global_point;
            targetContent.fav_novel_cnt = content.fav_novel_cnt;
            targetContent.review_cnt = content.review_cnt;
            targetContent.all_point = content.all_point;
            targetContent.all_hyoka_cnt = content.all_hyoka_cnt;
            targetContent.sasie_cnt = content.sasie_cnt;
            targetContent.novelupdated_at = content.novelupdated_at;
        });
    }
    
    if(targetContent.downloadQueueStatus != nil)
    {
        return @"既にダウンロードキューに入っています。";
    }
    
    // queue を新たに生成します。
    DownloadQueue* queue = [self CreateNewDownloadQueue];
    
    // リレーションシップを張ります。
    dispatch_sync(m_CoreDataAccessQueue, ^{
        targetContent.downloadQueueStatus = queue;
        queue.targetContent = targetContent;
    });
    
    // この時点で保存しておきます。
    [self saveContext];
    
    // このqueue用のダウンロードqueueを生成しておきます。
    dispatch_async(m_DownloadQueue, ^{
        NarouDownloadQueue* downloadQueue = [NarouDownloadQueue new];
        [downloadQueue startDownload:targetContent.ncode];
    });
    
    return nil;
}

/// コンテンツダウンロード用のqueueを返します
- (dispatch_queue_t)GetContentsDownloadQueue
{
    return m_ContentsDownloadQueue;
}

/// 現在ダウンロード中のコンテンツ情報を更新します。
- (void)UpdateCurrentDownloadingInfo:(NarouContentAllData*)currentContent
{
    m_CurrentDownloadingContent = currentContent;
    // delegate にも通達します。通達するときは main thread にしておきます。
    dispatch_async(m_MainQueue, ^{
        [self.NarouDownloadStatusUpdate NarouDownloadStatusUpdate:currentContent];
    });
}

/// 現在ダウンロード中のコンテンツ情報を取得します。
- (NarouContentAllData*)GetCurrentDownloadingInfo
{
    return m_CurrentDownloadingContent;
}

/// CoreData で保存している Story のうち、Ncode と chapter_no で検索した結果
/// 得られた Story を取得します。
/// 登録がなければ nil を返します
- (Story*) SearchStory:(NSString*) ncode chapter_no:(int)chapter_number
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
        
        NSPredicate* predicate = [NSPredicate predicateWithFormat:@"ncode == %@ AND chapter_number == %d", ncode, chapter_number];
        [fetchRequest setPredicate:predicate];
        
        err = nil;
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    });
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    if([fetchResults count] == 0)
    {
        // 何もなかった。
        return nil;
    }
    if([fetchResults count] != 1)
    {
        NSLog(@"duplicate ncode!!! %@", ncode);
        return nil;
    }
    return fetchResults[0];
    
}

/// Story を新しく生成します。必要な情報をすべて指定する必要があります
- (Story*) CreateNewStory:(NarouContent*)parentContent content:(NSString*)content chapter_number:(int)chapter_number;
{
    __block Story* story = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        story = [NSEntityDescription insertNewObjectForEntityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
        story.parentContent = parentContent;
        [parentContent addChildStoryObject:story];
        
        story.ncode = parentContent.ncode;
        story.chapter_number = [[NSNumber alloc] initWithInt:chapter_number];
        story.content = content;
    });
    return story;
}


/// Core Data用にディレクトリを(なければ)作ります。
- (BOOL)CreateCoreDataDirectory
{
    NSURL* directory = [self applicationDocumentsDirectory];
    NSError* err = nil;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:[directory path] withIntermediateDirectories:YES attributes:nil error:&err])
    {
        NSLog(@"can not create directory %@, %@", err, [err userInfo]);
        return NO;
    }
    return YES;
}

- (void)saveContext
{
    NSLog(@"saveContext called.");
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSError *error = nil;
        NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
        if (managedObjectContext != nil) {
            if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
                NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
                abort();
            }
        }
    });
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (_managedObjectContext != nil) {
        return _managedObjectContext;
    }
    
    NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
    if (coordinator != nil) {
        _managedObjectContext = [[NSManagedObjectContext alloc] init];
        [_managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return _managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (_managedObjectModel != nil) {
        return _managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"SettingDataModel" withExtension:@"momd"];
    _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return _managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (_persistentStoreCoordinator != nil) {
        return _persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"SettingDataModel.sqlite"];
    
    NSError *error = nil;
    _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
         @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        // TODO: 一旦ファイルを消してみて、もう一回やってみます。
        // ただ、これはなにかデータが壊れてるか、CoreDataの設定を書き換えたからなので、リリースした後ではこの対応だとひどいです。
        // つかデータ消してるってことはユーザの履歴とか全部吹き飛んでるわけで。('A`)
        [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];
        if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error])
        {
            NSLog(@"store cordinator add error 2th. %@, %@", error, [error userInfo]);
            abort();
        }
    }
    
    return _persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

@end
