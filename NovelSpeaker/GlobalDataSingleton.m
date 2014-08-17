//
//  GlobalDataSingleton.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/30.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "GlobalDataSingleton.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
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

    m_DownloadQueue = [NarouDownloadQueue new];
    
    m_isNeedReloadSpeakSetting = false;
    
    m_ManagedObjectContextPerThreadDictionary = [NSMutableDictionary new];
    m_MainManagedObjectContextHolderThreadID = nil;

    // NiftySpeaker は default config が必要ですが、これには core data の値を使いません。
    // (というか使わないでおかないとマイグレーションの時にひどいことになります)
    SpeechConfig* speechConfig = [SpeechConfig new];
    speechConfig.pitch = 1.0f;
    speechConfig.rate = 1.0f;
    speechConfig.beforeDelay = 0.0f;
    m_NiftySpeaker = [[NiftySpeaker alloc] initWithSpeechConfig:speechConfig];;

    AVAudioSession* session = [AVAudioSession sharedInstance];
    NSError* err = nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&err];
    if (err) {
        NSLog(@"AVAudioSessionCategoryPlayback set failed. %@ %@", err, err.userInfo);
    }
    [session setActive:NO error:nil];

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
// 非公開インタフェースになりました。
- (GlobalState*) GetCoreDataGlobalStateThreadUnsafe
{
    NSError* err;
    NSMutableArray* fetchResults = nil;
    // CoreData で読みだします
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:@"GlobalState" inManagedObjectContext: self.managedObjectContext];
    [fetchRequest setEntity:entity];
    err = nil;
    //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    }
    //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);

    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    if([fetchResults count] == 0)
    {
        // まだ登録されてなかったので新しく作ります。
        GlobalState* globalState = nil;
        //NSLog(@"%@ insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
        @synchronized(_persistentStoreCoordinator){
        globalState = (GlobalState*)[NSEntityDescription insertNewObjectForEntityForName:@"GlobalState" inManagedObjectContext:self.managedObjectContext];
        }
        //NSLog(@"%@ out insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
        if(globalState == nil)
        {
            NSLog(@"GlobalState create failed.");
            return nil;
        }
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

/// CoreData で保存している GlobalState object (一つしかないはず) を取得します
- (GlobalStateCacheData*) GetGlobalState
{
    __block GlobalStateCacheData* stateCache = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        GlobalState* state = [self GetCoreDataGlobalStateThreadUnsafe];
        stateCache = [[GlobalStateCacheData alloc] initWithCoreData:state];
    });
    return stateCache;
}

/// GlobalState を更新します。
- (BOOL)UpdateGlobalState:(GlobalStateCacheData*)globalState
{
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        GlobalState* state = [self GetCoreDataGlobalStateThreadUnsafe];

        // pitch か rate が変わってたら読み直し指示をします。
        if ([state.defaultPitch compare:globalState.defaultPitch] != NSOrderedSame
            || [state.defaultRate compare:globalState.defaultRate] != NSOrderedSame) {
            m_isNeedReloadSpeakSetting = true;
        }
        state.defaultPitch = globalState.defaultPitch;
        state.defaultRate = globalState.defaultRate;
        
        if (globalState.currentReadingStory == nil) {
            state.currentReadingStory = nil;
            result = true;
            return;
        }
        
        GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
        NarouContent* content = [globalData SearchCoreDataNarouContentFromNcodeThreadUnsafe:globalState.currentReadingStory.ncode];
        if (content == nil) {
            state.currentReadingStory = nil;
            result = false;
            return;
        }
        Story* story = [self SearchCoreDataStoryThreadUnsafe:globalState.currentReadingStory.ncode chapter_no:[globalState.currentReadingStory.chapter_number intValue]];
        if (story == nil) {
            state.currentReadingStory = nil;
            content.currentReadingStory = nil;
        }else{
            story.readLocation = globalState.currentReadingStory.readLocation;
            state.currentReadingStory = story;
            content.currentReadingStory = story;
        }
        result = true;
    });
    return result;
}


/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContent*) SearchCoreDataNarouContentFromNcodeThreadUnsafe:(NSString*) ncode
{
    NSError* err;
    NSMutableArray* fetchResults = nil;
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:@"NarouContent" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"ncode == %@", ncode];
    [fetchRequest setPredicate:predicate];

    err = nil;
    //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    }
    //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);

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

/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContentCacheData*) SearchNarouContentFromNcode:(NSString*) ncode
{
    __block NarouContentCacheData* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:ncode];
        if (coreDataContent != nil) {
            result = [[NarouContentCacheData alloc] initWithCoreData:coreDataContent];
        }
    });
    return result;
}


/// 指定されたNarouContentの情報を更新します。
/// CoreData側に登録されていなければ新規に作成し、
/// 既に登録済みであれば情報を更新します。
- (BOOL)UpdateNarouContent:(NarouContentCacheData*)content
{
    if (content == nil || content.ncode == nil) {
        return false;
    }
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        if (coreDataContent == nil) {
            coreDataContent = [self CreateNewNarouContentThreadUnsafe];
        }
        result = [content AssignToCoreData:coreDataContent];
    });
    return result;
}


/// 新しい NarouContent を生成して返します。
- (NarouContent*) CreateNewNarouContentThreadUnsafe
{
    NarouContent* content = nil;
    //NSLog(@"%@ insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    content = [NSEntityDescription insertNewObjectForEntityForName:@"NarouContent" inManagedObjectContext:self.managedObjectContext];
    }
    //NSLog(@"%@ out insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
    return content;
}

/// 保存されている NarouContent の数を取得します。
- (NSUInteger) GetNarouContentCount
{
    __block NSUInteger result = 0;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"NarouContent" inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
        // 数を数えるだけなのでidしか返却しないようにします。
        [fetchRequest setIncludesPropertyValues:NO];

        NSError* err = nil;
        //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
        NSMutableArray* fetchResults;
        @synchronized(_persistentStoreCoordinator){
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
        }
        //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);

        if(fetchResults == nil)
        {
            result = 0;
        }else{
            result = [fetchResults count];
        }
    });
    return result;
}

/// NarouContent の全てを NarouContentCacheData の NSArray で取得します
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
        //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
        NSArray* results;
        @synchronized(_persistentStoreCoordinator){
        results = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
        }
        //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[NarouContentCacheData alloc] initWithCoreData:results[i]];
        }
    });
    if(err != nil)
    {
        NSLog(@"fetch failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    return fetchResults;
}

/// ダウンロードqueueに追加しようとします
/// 追加した場合は nil を返します。
/// 追加できなかった場合はエラーメッセージを返します。
- (NSString*) AddDownloadQueueForNarou:(NarouContentCacheData*) content
{
    if(content == nil || content.ncode == nil || [content.ncode length] <= 0)
    {
        return @"有効な NCODE を取得できませんでした。";
    }
    NSString* targetNcode = content.ncode;
    __block NarouContentCacheData* targetContentCacheData = [self SearchNarouContentFromNcode:targetNcode];
    if (targetContentCacheData == nil) {
        // 登録がないようなのでとりあえず NarouContent を登録します。
        dispatch_sync(m_CoreDataAccessQueue, ^{
            NarouContent* targetContent = [self CreateNewNarouContentThreadUnsafe];
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
            targetContentCacheData = [[NarouContentCacheData alloc] initWithCoreData:targetContent];
        });
    }
    
    if ([targetContentCacheData.general_all_no intValue] <= [self CountContentChapter:targetContentCacheData] ) {
        return @"既にダウンロード済です。";
    }
    
    // download queue に追加します。
    NSLog(@"add download queue.");
    [[GlobalDataSingleton GetInstance] PushContentDownloadQueue:content];
    
    return nil;
}

/// download queue の最後に対象の content を追加します。
- (void)PushContentDownloadQueue:(NarouContentCacheData*)content
{
    [m_DownloadQueue AddDownloadQueue:content];
}

/// 現在ダウンロード中のコンテンツ情報を取得します。
- (NarouContentCacheData*)GetCurrentDownloadingInfo
{
    return [m_DownloadQueue GetCurrentDownloadingInfo];
}

/// 現在ダウンロード待ち中のコンテンツ情報のリストを取得します。
- (NSArray*) GetCurrentDownloadWaitingInfo
{
    return [m_DownloadQueue GetCurrentWaitingList];
}

/// ダウンロードイベントハンドラを設定します
- (BOOL)AddDownloadEventHandler:(id<NarouDownloadQueueDelegate>)delegate
{
    [m_DownloadQueue AddDownloadEventHandler:delegate];
    return true;
}


/// ダウンロードイベントハンドラから削除します。
- (BOOL)DeleteDownloadEventHandler:(id<NarouDownloadQueueDelegate>)delegate
{
    [m_DownloadQueue DelDownloadEventHandler:delegate];
    return true;
}

/// ダウンロード周りのイベントハンドラ用のdelegateに追加します。(ncode で絞り込む版)
- (BOOL)AddDownloadEventHandlerWithNcode:(NSString*)string handler:(id<NarouDownloadQueueDelegate>)handler
{
    return [m_DownloadQueue AddDownloadEventHandlerWithNcode:string handler:handler];
}
/// ダウンロード周りのイベントハンドラ用のdelegateから削除します。(ncode で絞り込む版)
- (BOOL)DeleteDownloadEventHandlerWithNcode:(NSString*)string
{
    return [m_DownloadQueue DelDownloadEventHandlerWithNcode:string];
}


/// 現在ダウンロード待ち中のものから、ncode を持つものをリストから外します。
- (BOOL)DeleteDownloadQueue:(NSString*)ncode
{
    return [m_DownloadQueue DeleteDownloadQueue:ncode];
}

/// CoreData で保存している Story のうち、Ncode と chapter_no で検索した結果
/// 得られた Story を取得します。
/// 登録がなければ nil を返します
- (Story*) SearchCoreDataStoryThreadUnsafe:(NSString*) ncode chapter_no:(int)chapter_number
{
    NSError* err;
    NSMutableArray* fetchResults = nil;
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
        
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"ncode == %@ AND chapter_number == %d", ncode, chapter_number];
    [fetchRequest setPredicate:predicate];
        
    err = nil;
    //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    }
    //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);

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
        NSLog(@"duplicate ncode+chapter_number!!! %@/%d", ncode, chapter_number);
        return nil;
    }
    return fetchResults[0];
}

/// Story を検索します。(公開用method)
- (StoryCacheData*) SearchStory:(NSString*)ncode chapter_no:(int)chapter_number
{
    __block StoryCacheData* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* story = [self SearchCoreDataStoryThreadUnsafe:ncode chapter_no:chapter_number];
        if (story != nil) {
            result = [[StoryCacheData alloc] initWithCoreData:story];
        }
    });
    return result;
}

/// Story を新しく生成します。必要な情報をすべて指定する必要があります
- (Story*) CreateNewStoryThreadUnsafe:(NarouContent*)parentContent content:(NSString*)content chapter_number:(int)chapter_number;
{
    Story* story = nil;
    //NSLog(@"%@ insetNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    story = [NSEntityDescription insertNewObjectForEntityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
    }
    //NSLog(@"%@ out insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
    story.parentContent = parentContent;
    [parentContent addChildStoryObject:story];
        
    story.ncode = parentContent.ncode;
    story.chapter_number = [[NSNumber alloc] initWithInt:chapter_number];
    story.content = content;
    return story;
}

/// 指定されたStoryの情報を更新します。(dispatch_sync で囲っていない版)
/// CoreData側に登録されていなければ新規に作成し、
/// 既に登録済みであれば情報を更新します。
- (BOOL)UpdateStoryThreadUnsafe:(NSString*)content chapter_number:(int)chapter_number parentContent:(NarouContentCacheData *)parentContent
{
    if (parentContent == nil || content == nil) {
        return false;
    }
    
    BOOL result = false;
    NarouContent* parentCoreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:parentContent.ncode];
    if (parentCoreDataContent == nil) {
        result = false;
    }else{
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:parentContent.ncode chapter_no:chapter_number];
        if (coreDataStory == nil) {
            coreDataStory = [self CreateNewStoryThreadUnsafe:parentCoreDataContent content:content chapter_number:  chapter_number];
        }
        coreDataStory.content = content;
        coreDataStory.parentContent = parentCoreDataContent;
        coreDataStory.chapter_number = [[NSNumber alloc] initWithInt:chapter_number];
        result = true;
    }

    return result;
}

/// 指定されたStoryの情報を更新します。
/// CoreData側に登録されていなければ新規に作成し、
/// 既に登録済みであれば情報を更新します。
- (BOOL)UpdateStory:(NSString*)content chapter_number:(int)chapter_number parentContent:(NarouContentCacheData *)parentContent
{
    if (parentContent == nil || content == nil) {
        return false;
    }
    
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        result = [self UpdateStoryThreadUnsafe:content chapter_number:chapter_number parentContent:parentContent];
    });
    
    return result;
}


/// 小説を一つ削除します
- (BOOL)DeleteContent:(NarouContentCacheData*)content
{
    if (content == nil) {
        return false;
    }
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        if (coreDataContent != nil) {
            //NSLog(@"%@ deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
            @synchronized(_persistentStoreCoordinator){
            [self.managedObjectContext deleteObject:coreDataContent];
            }
            //NSLog(@"%@ out deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
            result = true;
        }
    });
    // 保存しておきます。
    [self saveContext];
    return true;
}

/// 章を一つ削除します
- (BOOL)DeleteStory:(StoryCacheData *)story
{
    if (story == nil) {
        return false;
    }
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:[story.chapter_number intValue]];
        if (coreDataStory == nil) {
            result = false;
        }else{
            //NSLog(@"%@ deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
            @synchronized(_persistentStoreCoordinator){
            [self.managedObjectContext deleteObject:coreDataStory];
            }
            //NSLog(@"%@ out deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
            result = true;
        }
    });
    // 保存しておきます。
    [self saveContext];
    return result;
}

/// 対象の小説でCoreDataに保存されている章の数を取得します。
- (NSUInteger)CountContentChapter:(NarouContentCacheData*)content
{
    if (content == nil || content.ncode == nil) {
        return 0;
    }
    
    __block NSUInteger result = 0;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
        [fetchRequest setEntity:entity];
        // 数を数えるだけなのでidしか返却しないようにします。
        [fetchRequest setIncludesPropertyValues:NO];
        
        NSPredicate* predicate = [NSPredicate predicateWithFormat:@"ncode == %@", content.ncode];
        [fetchRequest setPredicate:predicate];

        NSError* err = nil;
        NSMutableArray* fetchResults;
        //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
        @synchronized(_persistentStoreCoordinator){
        fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
        }
        //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
        if(fetchResults == nil)
        {
            result = 0;
        }else{
            result = [fetchResults count];
        }
    });
    return result;
}

/// 最後に読んでいた小説を取得します
- (NarouContentCacheData*)GetCurrentReadingContent
{
    GlobalStateCacheData* globalState = [self GetGlobalState];
    if (globalState == nil) {
        return nil;
    }
    StoryCacheData* story = globalState.currentReadingStory;
    if (story == nil) {
        return nil;
    }
    return [self SearchNarouContentFromNcode:story.ncode];
}

/// 小説で読んでいた章を取得します
- (StoryCacheData*)GetReadingChapter:(NarouContentCacheData*)content
{
    if (content == nil) {
        return nil;
    }
    NarouContentCacheData* narouContent = [self SearchNarouContentFromNcode:content.ncode];
    return narouContent.currentReadingStory;
}

/// 読み込み中の場所を指定された小説と章で更新します。
- (BOOL)UpdateReadingPoint:(NarouContentCacheData*)content story:(StoryCacheData*)story
{
    if (content == nil || story == nil
        || content.ncode == nil
        || ![content.ncode isEqual:story.ncode]) {
        return false;
    }
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:[story.chapter_number intValue]];
        GlobalState* globalState = [self GetCoreDataGlobalStateThreadUnsafe];
        if (coreDataContent == nil || coreDataStory == nil || globalState == nil) {
            result = false;
        }else{
            coreDataStory.readLocation = story.readLocation;
            coreDataContent.currentReadingStory = coreDataStory;
            globalState.currentReadingStory = coreDataStory;
            result = true;
        }
    });
    return result;
}

/// 次の章を読み出します。
/// 次の章がなければ nil を返します。
- (StoryCacheData*)GetNextChapter:(StoryCacheData*)story
{
    if (story == nil) {
        return nil;
    }
    int target_chapter_number = [story.chapter_number intValue] + 1;
    __block StoryCacheData* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* nextCoreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:target_chapter_number];
        if (nextCoreDataStory != nil) {
            result = [[StoryCacheData alloc] initWithCoreData:nextCoreDataStory];
        }
    });
    return result;
}

/// 前の章を読み出します。
/// 前の章がなければ nil を返します。
- (StoryCacheData*)GetPreviousChapter:(StoryCacheData*)story
{
    if (story == nil) {
        return nil;
    }
    int target_chapter_number = [story.chapter_number intValue] - 1;
    __block StoryCacheData* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* previousCoreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:target_chapter_number];
        if (previousCoreDataStory != nil) {
            result = [[StoryCacheData alloc] initWithCoreData:previousCoreDataStory];
        }
    });
    return result;
}

- (void)UpdatePlayingInfo:(StoryCacheData*)story
{
    NSString* titleName = @"再生していません";
    NSString* artist = @"-";
    
    if (story != nil) {
        NarouContentCacheData* content = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:story.ncode];
        if (content != nil) {
            artist = content.writer;
            titleName = [[NSString alloc] initWithFormat:@"%@ (%d/%d)", content.title, [story.chapter_number intValue], [content.general_all_no intValue]];
        }
    }
    
    NSMutableDictionary* songInfo = [NSMutableDictionary new];
    [songInfo setObject:titleName forKey:MPMediaItemPropertyTitle];
    [songInfo setObject:artist forKey:MPMediaItemPropertyArtist];
    [[MPNowPlayingInfoCenter defaultCenter] setNowPlayingInfo:songInfo];
}

/// 読み上げ設定を読み直します。
- (BOOL)ReloadSpeechSetting
{
    [m_NiftySpeaker ClearSpeakSettings];

    GlobalStateCacheData* globalState = [self GetGlobalState];
    SpeechConfig* defaultSetting = [SpeechConfig new];
    defaultSetting.pitch = [globalState.defaultPitch floatValue];
    defaultSetting.rate = [globalState.defaultRate floatValue];
    defaultSetting.beforeDelay = 0.0f;
    [m_NiftySpeaker SetDefaultSpeechConfig:defaultSetting];
    
    NSArray* speechConfigArray = [self GetAllSpeakPitchConfig];
    if (speechConfigArray == nil || [speechConfigArray count] <= 0) {
        // 設定が無いようなので勝手に作ります。
        SpeakPitchConfigCacheData* speakConfig = [SpeakPitchConfigCacheData new];
        speakConfig.title = @"会話文";
        speakConfig.pitch = [[NSNumber alloc] initWithFloat:1.5f];
        speakConfig.startText = @"「";
        speakConfig.endText = @"」";
        [self UpdateSpeakPitchConfig:speakConfig];
        speakConfig.title = @"会話文 2";
        speakConfig.pitch = [[NSNumber alloc] initWithFloat:1.2f];
        speakConfig.startText = @"『";
        speakConfig.endText = @"』";
        [self UpdateSpeakPitchConfig:speakConfig];

        // 読み直します。
        speechConfigArray = [self GetAllSpeakPitchConfig];
    }
    if (speechConfigArray != nil) {
        for (SpeakPitchConfigCacheData* pitchConfig in speechConfigArray) {
            SpeechConfig* speechConfig = [SpeechConfig new];
            speechConfig.pitch = [pitchConfig.pitch floatValue];
            speechConfig.rate = [globalState.defaultRate floatValue];
            speechConfig.beforeDelay = 0.0f;
            [m_NiftySpeaker AddBlockStartSeparator:pitchConfig.startText endString:pitchConfig.endText speechConfig:speechConfig];
        }
    }

    // delay については設定ページを作っていないので固定値になります。
    [m_NiftySpeaker AddDelayBlockSeparator:@"\r\n\r\n" delay:0.02f];
    
    NSArray* speechModConfigArray = [self GetAllSpeechModSettings];
    if (speechModConfigArray == nil || [speechModConfigArray count] <= 0) {
        // これも無いようなので勝手に作ります。
        NSArray* dataArray = [[NSArray alloc] initWithObjects:
                              @"異世界", @"イセカイ"
                              , @"術者", @"ジュツシャ"
                              , @"術師", @"ジュツシ"
                              , @"美味い", @"うまい"
                              , @"不味い", @"まずい"
                              , @"俺達", @"おれたち"
                              , @"照ら", @"てら"
                              , @"身体", @"からだ"
                              , @"真っ暗", @"まっくら"
                              , @"行って", @"いって"
                              , @"行く", @"いく"
                              , @"行った", @"いった"
                              , @"小柄", @"こがら"
                              , @"召喚獣", @"ショウカンジュウ"
                              , @"お米", @"おこめ"
                              , @"三々五々", @"さんさんごご"
                              , @"漏ら", @"もら"

                              , @"直継", @"ナオツグ"
                              , @"にゃん太", @"ニャンタ"
                              , @"大地人", @"だいちじん"
                              , @"地底人", @"ちていじん"
                              
                              , nil];
        SpeechModSettingCacheData* speechModSetting = [SpeechModSettingCacheData new];
        for (int i = 0; i < [dataArray count]; i += 2) {
            speechModSetting.beforeString = [dataArray objectAtIndex:i];
            speechModSetting.afterString = [dataArray objectAtIndex:i+1];
            [self UpdateSpeechModSetting:speechModSetting];
        }

        speechModConfigArray = [self GetAllSpeechModSettings];
    }
    if (speechModConfigArray != nil) {
        for (SpeechModSettingCacheData* speechModSetting in speechModConfigArray) {
            [m_NiftySpeaker AddSpeechModText:speechModSetting.beforeString to:speechModSetting.afterString];
        }
    }
    
    return true;
}

/// 読み上げる文書を設定します。
- (BOOL)SetSpeechStory:(StoryCacheData *)story
{
    if(![m_NiftySpeaker SetText:story.content])
    {
        return false;
    }
    [self UpdatePlayingInfo:story];
    NSRange range = NSMakeRange([story.readLocation unsignedLongValue], 0);
    return [m_NiftySpeaker UpdateCurrentReadingPoint:range];
}

/// 読み上げ位置を設定します。
- (BOOL)SetSpeechRange:(NSRange)range
{
    return [m_NiftySpeaker UpdateCurrentReadingPoint:range];
}

/// 現在の読み上げ位置を取り出します
- (NSRange)GetCurrentReadingPoint
{
    return [m_NiftySpeaker GetCurrentReadingPoint];
}

/// 読み上げを開始します。
- (BOOL)StartSpeech
{
    if (m_isNeedReloadSpeakSetting) {
        NSLog(@"読み上げ設定を読み直します。");
        [self ReloadSpeechSetting];
        // 読み直された読み上げ設定で発音情報を再定義させます。
        StoryCacheData* story = [self GetReadingChapter:[self GetCurrentReadingContent]];
        if (story != nil) {
            NSLog(@"発音情報を更新します。");
            [self SetSpeechStory:story];
        }
        m_isNeedReloadSpeakSetting = false;
    }

    AVAudioSession* session = [AVAudioSession sharedInstance];
    NSError* err;
    NSLog(@"setActive YES.");
    [session setActive:YES error:&err];
    if (err != nil) {
        NSLog(@"setActive error: %@ %@", err, err.userInfo);
    }
    return [m_NiftySpeaker StartSpeech];
}

/// 読み上げを停止します。
- (BOOL)StopSpeech
{
    AVAudioSession* session = [AVAudioSession sharedInstance];
    NSLog(@"setActive NO.");
    [session setActive:NO error:nil];
    if([m_NiftySpeaker StopSpeech] == false)
    {
        return false;
    }
    return true;
}

/// 読み上げ時のイベントハンドラを追加します。
- (BOOL)AddSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate
{
    return [m_NiftySpeaker AddSpeakRangeDelegate:delegate];
}

/// 読み上げ時のイベントハンドラを削除します。
- (void)DeleteSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate
{
    return [m_NiftySpeaker DeleteSpeakRangeDelegate:delegate];
}

/// 読み上げ中か否かを取得します
- (BOOL)isSpeaking
{
    return [m_NiftySpeaker isSpeaking];
}


/// 保存されているコンテンツの再読み込みを開始します。
- (BOOL)ReloadBookShelfContents
{
    return true;
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSError *error = nil;
        NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
        if (managedObjectContext != nil) {
            //NSLog(@"%@ saveContext %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
            @synchronized(_persistentStoreCoordinator){
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(backgroundContextDidSave:)
                                                             name:NSManagedObjectContextDidSaveNotification
                                                           object:managedObjectContext];
            if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
                NSLog(@"Unresolved error. save failed. %@, %@", error, [error userInfo]);
                abort();
            }
            }
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:NSManagedObjectContextDidSaveNotification
                                                          object:managedObjectContext];
            //NSLog(@"%@ out saveContext %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 5, __FUNCTION__);
        }
    });
    NSLog(@"CoreData saved.");
}

/// 読み上げの会話文の音程設定を全て読み出します。
/// NSArray の中身は SpeakPitchConfigCacheData で、title でsortされた値が取得されます。
- (NSArray*)GetAllSpeakPitchConfig
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"SpeakPitchConfig" inManagedObjectContext: self.managedObjectContext];
        [fetchRequest setEntity:entity];
        
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"title" ascending:NO];
        NSArray* sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
        [fetchRequest setSortDescriptors:sortDescriptors];
        
        err = nil;
        NSArray* results;
        //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
        @synchronized(_persistentStoreCoordinator){
        results = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
        }
        //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeakPitchConfigCacheData alloc] initWithCoreData:results[i]];
        }
    });
    if(err != nil)
    {
        NSLog(@"fetch failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    return fetchResults;
}

/// 読み上げの会話文の音程設定をタイトル指定で読み出します。(内部版)
- (SpeakPitchConfig*)GetSpeakPitchConfigWithTitleThreadUnsafe:(NSString*)title
{
    NSError* err;
    NSMutableArray* fetchResults = nil;
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:@"SpeakPitchConfig" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"title == %@", title];
    [fetchRequest setPredicate:predicate];
    
    err = nil;
    //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    }
    //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
    
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
        NSLog(@"duplicate title!!! %@", title);
        return nil;
    }
    return fetchResults[0];
}

/// 読み上げの会話文の音程設定をタイトル指定で読み出します。
- (SpeakPitchConfigCacheData*)GetSpeakPitchConfigWithTitle:(NSString*)title
{
    __block SpeakPitchConfigCacheData* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:title];
        if (coreDataConfig != nil) {
            result = [[SpeakPitchConfigCacheData alloc] initWithCoreData:coreDataConfig];
        }
    });
    return result;
}

/// 読み上げの会話文の音程設定を追加します。
- (SpeakPitchConfig*) CreateNewSpeakPitchConfigThreadUnsafe:(SpeakPitchConfigCacheData*)data
{
    SpeakPitchConfig* config = nil;
    //NSLog(@"%@ insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    config = [NSEntityDescription insertNewObjectForEntityForName:@"SpeakPitchConfig" inManagedObjectContext:self.managedObjectContext];
    }
    //NSLog(@"%@ out insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
    [data AssignToCoreData:config];
    return config;
}

/// 読み上げの会話文の音程設定を更新します。
- (BOOL)UpdateSpeakPitchConfig:(SpeakPitchConfigCacheData*)config
{
    if (config == nil) {
        return false;
    }
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:config.title];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeakPitchConfigThreadUnsafe:config];
        }
        if (coreDataConfig != nil) {
            result = [config AssignToCoreData:coreDataConfig];
        }
    });
    if (result) {
        NSLog(@"isNeedReloadSpeakSetting = true (pitch)");
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}

/// 読み上げの会話文の音声設定を削除します。
- (BOOL)DeleteSpeakPitchConfig:(SpeakPitchConfigCacheData*)config
{
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:config.title];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            //NSLog(@"%@ deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
            @synchronized(_persistentStoreCoordinator){
            [self.managedObjectContext deleteObject:coreDataConfig];
            }
            //NSLog(@"%@ out deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
            result = true;
        }
    });
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    // 保存しておきます。
    [self saveContext];
    return result;
}


/// 読み上げ時の読み替え設定を全て読み出します。
/// NSArray の中身は SpeechModSettingCacheData で、beforeString で sort された値が取得されます。
- (NSArray*)GetAllSpeechModSettings
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
        NSEntityDescription* entity = [NSEntityDescription entityForName:@"SpeechModSetting" inManagedObjectContext: self.managedObjectContext];
        [fetchRequest setEntity:entity];
        
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"beforeString" ascending:NO];
        NSArray* sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
        [fetchRequest setSortDescriptors:sortDescriptors];
        
        err = nil;
        NSArray* results;
        //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
        @synchronized(_persistentStoreCoordinator){
        results = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
        }
        //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeechModSettingCacheData alloc] initWithCoreData:results[i]];
        }
    });
    if(err != nil)
    {
        NSLog(@"fetch failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    return fetchResults;
}

/// 読み上げ時の読み替え設定を beforeString指定 で読み出します(内部版)
- (SpeechModSetting*)GetSpeechModSettingWithBeforeStringThreadUnsafe:(NSString*)beforeString
{
    NSError* err;
    NSMutableArray* fetchResults = nil;
    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:@"SpeechModSetting" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"beforeString == %@", beforeString];
    [fetchRequest setPredicate:predicate];
    
    err = nil;
    //NSLog(@"%@ executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    }
    //NSLog(@"%@ out executeFetchRequest %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
    
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
        NSLog(@"duplicate beforeString!!! %@", beforeString);
        return nil;
    }
    return fetchResults[0];
}

/// 読み上げ時の読み替え設定を beforeString指定 で読み出します
- (SpeechModSettingCacheData*)GetSpeechModSettingWithBeforeString:(NSString*)beforeString
{
    __block SpeechModSettingCacheData* result = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataSetting = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:beforeString];
        if (coreDataSetting != nil) {
            result = [[SpeechModSettingCacheData alloc] initWithCoreData:coreDataSetting];
        }
    });
    return result;
}

/// 読み上げ時の読み替え設定を追加します。
- (SpeechModSetting*) CreateNewSpeechModSettingThreadUnsafe:(SpeechModSettingCacheData*)data
{
    SpeechModSetting* setting = nil;
    //NSLog(@"%@ insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
    @synchronized(_persistentStoreCoordinator){
    setting = [NSEntityDescription insertNewObjectForEntityForName:@"SpeechModSetting" inManagedObjectContext:self.managedObjectContext];
    }
    //NSLog(@"%@ out insertNewObjectForEntityForName %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
    [data AssignToCoreData:setting];
    return setting;
}

/// 読み上げ時の読み替え設定を更新します。無ければ新しく登録されます。
- (BOOL)UpdateSpeechModSetting:(SpeechModSettingCacheData*)modSetting
{
    if (modSetting == nil) {
        return false;
    }
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:modSetting.beforeString];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeechModSettingThreadUnsafe:modSetting];
        }
        if (coreDataConfig != nil) {
            result = [modSetting AssignToCoreData:coreDataConfig];
        }
    });
    if (result) {
        NSLog(@"isNeedReloadSpeakSetting = true (speechMod)");
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}

/// 読み上げ時の読み替え設定を削除します。
- (BOOL)DeleteSpeechModSetting:(SpeechModSettingCacheData*)modSetting
{
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:modSetting.beforeString];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            //NSLog(@"%@ deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__, __FUNCTION__);
            @synchronized(_persistentStoreCoordinator){
            [self.managedObjectContext deleteObject:coreDataConfig];
            }
            //NSLog(@"%@ out deleteObject %s %d %s", [NSThread currentThread], __FILE__, __LINE__ - 2, __FUNCTION__);
            result = true;
        }
    });
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    // 保存しておきます。
    [self saveContext];
    return result;
}

/// CoreData のマイグレーションが必要かどうかを確認します。
- (BOOL)isRequiredCoreDataMigration
{
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"SettingDataModel.sqlite"];
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
    
    BOOL isCompatible = [self.managedObjectModel isConfiguration:nil
                                        compatibleWithStoreMetadata:sourceMetaData]; 
    
    return !isCompatible;
}

/// CoreData のマイグレーションを実行します。
- (void)doCoreDataMigration
{
    // core data のデータを使えば勝手にマイグレーションが走ります。
    [self GetGlobalState];
}


#pragma mark - Core Data stack

// from http://stackoverflow.com/questions/4264540/grand-central-dispatch-gcd-with-coredata
/* Save notification handler for the background context */
- (void)backgroundContextDidSave:(NSNotification *)notification {
    /* Make sure we're on the main thread when updating the main context */
    NSString* threadID = [[NSString alloc] initWithFormat:@"%@", [NSThread currentThread]];
    if ([threadID compare:m_MainManagedObjectContextHolderThreadID] != NSOrderedSame) {
        [self performSelectorOnMainThread:@selector(backgroundContextDidSave:)
                               withObject:notification
                            waitUntilDone:NO];
        return;
    }
    
    /* merge in the changes to the main context */
    [self.managedObjectContext mergeChangesFromContextDidSaveNotification:notification];
}

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    // thread毎 に NSManagedObjectContext を作るようにします。

    // TODO: ThreadID を得る方法が思いつかないのでこれで……
    NSString* threadID = [[NSString alloc] initWithFormat:@"%@", [NSThread currentThread]];
    NSManagedObjectContext* context = [m_ManagedObjectContextPerThreadDictionary objectForKey:threadID];
    if (context == nil) {
        NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
        if (coordinator != nil) {
            context = [[NSManagedObjectContext alloc] init];
            [context setPersistentStoreCoordinator:coordinator];
        }
        [m_ManagedObjectContextPerThreadDictionary setObject:context forKey:threadID];
        if (m_MainManagedObjectContextHolderThreadID == nil) {
            m_MainManagedObjectContextHolderThreadID = threadID;
        }
    }
    
    return context;
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
    
        NSDictionary* options = [[NSDictionary alloc] initWithObjectsAndKeys:
                                 [NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
    
        NSError *error = nil;
        _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
        if (![_persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
            /*
             Replace this implementation with code to handle the error appropriately.
         
             abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
         
             Typical reasons for an error here include:
             * The persistent store is not accessible;
             * The schema for the persistent store is incompatible with current managed object model.
             Check the error message to determine what the actual problem was.
             
             
             If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
             If you encounter schema incompatibility errors during development, you can reduce their frequency  by:
             * Simply deleting the existing store:
             [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
             * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
             @{NSMigratePersistentStoresAutomaticallyOption:@YES, NSInferMappingModelAutomaticallyOption:@YES}
         
             Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
             */
            // TODO: 一旦ファイルを消してみて、もう一回やってみます。
            // ただ、これはなにかデータが壊れてるか、CoreDataの設定を書き換えたからなので、
            // リリースした後ではこの対応だとひどいです。
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
