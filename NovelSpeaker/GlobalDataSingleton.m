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
//@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
//@synthesize managedObjectModel = _managedObjectModel;
//@synthesize managedObjectContext = _managedObjectContext;

static GlobalDataSingleton* _singleton = nil;

- (id)init
{
    self = [super init];
    
    m_LogStringArray = [NSMutableArray new];

    m_bIsFirstPageShowed = false;
    
    m_MainQueue = dispatch_get_main_queue();
    // CoreDataアクセス用の直列queueを作ります。
    m_CoreDataAccessQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.coredataaccess", DISPATCH_QUEUE_SERIAL);

    m_DownloadQueue = [NarouDownloadQueue new];
    
    m_isNeedReloadSpeakSetting = false;
    
    m_ManagedObjectContextPerThreadDictionary = [NSMutableDictionary new];
    m_MainManagedObjectContextHolderThreadID = nil;
    
    m_CoreDataObjectHolder = [[CoreDataObjectHolder alloc] initWithModelName:@"SettingDataModel" fileName:@"SettingDataModel" folderType:DOCUMENTS_FOLDER_TYPE mergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];

    // NiftySpeaker は default config が必要ですが、これには core data の値を使いません。
    // (というか使わないでおかないとここで取得しようとした時にマイグレーションが発生してしまいます)
    SpeechConfig* speechConfig = [SpeechConfig new];
    speechConfig.pitch = 1.0f;
    speechConfig.rate = 1.0f;
    speechConfig.beforeDelay = 0.0f;
    m_NiftySpeaker = [[NiftySpeaker alloc] initWithSpeechConfig:speechConfig];

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

- (void)coreDataPerfomBlockAndWait:(void(^)())block {
    [m_CoreDataObjectHolder performBlockAndWait:block];
}

/// CoreData で保存している GlobalState object (一つしかないはず) を取得します
// 非公開インタフェースになりました。
- (GlobalState*) GetCoreDataGlobalStateThreadUnsafe
{
    NSError* err;
    // CoreData で読みだします
    NSArray* fetchResults = [m_CoreDataObjectHolder FetchAllEntity:@"GlobalState"];
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed. %@, %@", err, [err userInfo]);
        return nil;
    }
    if([fetchResults count] == 0)
    {
        // まだ登録されてなかったので新しく作ります。
        GlobalState* globalState = [m_CoreDataObjectHolder CreateNewEntity:@"GlobalState"];
        if(globalState == nil)
        {
            NSLog(@"GlobalState create failed.");
            return nil;
        }
        globalState.defaultRate = [[NSNumber alloc] initWithFloat:AVSpeechUtteranceDefaultSpeechRate];
        globalState.defaultPitch = [[NSNumber alloc] initWithFloat:1.0f];
        [m_CoreDataObjectHolder save];
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        GlobalState* state = [self GetCoreDataGlobalStateThreadUnsafe];
        stateCache = [[GlobalStateCacheData alloc] initWithCoreData:state];
    //});
    }];
    return stateCache;
}

/// GlobalState を更新します。
- (BOOL)UpdateGlobalState:(GlobalStateCacheData*)globalState
{
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        GlobalState* state = [self GetCoreDataGlobalStateThreadUnsafe];

        // pitch か rate が変わってたら読み直し指示をします。
        if ([state.defaultPitch compare:globalState.defaultPitch] != NSOrderedSame
            || [state.defaultRate compare:globalState.defaultRate] != NSOrderedSame
            || [state.speechWaitSettingUseExperimentalWait boolValue] != [globalState.speechWaitSettingUseExperimentalWait boolValue]){
            m_isNeedReloadSpeakSetting = true;
        }
        state.defaultPitch = globalState.defaultPitch;
        state.defaultRate = globalState.defaultRate;
        state.textSizeValue = globalState.textSizeValue;
        state.maxSpeechTimeInSec = globalState.maxSpeechTimeInSec;
        state.speechWaitSettingUseExperimentalWait = globalState.speechWaitSettingUseExperimentalWait;
        
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
    //});
    }];
    [m_CoreDataObjectHolder save];
    return result;
}


/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContent*) SearchCoreDataNarouContentFromNcodeThreadUnsafe:(NSString*) ncode
{
    NSError* err;
    NSArray* fetchResults = [m_CoreDataObjectHolder
                             SearchEntity:@"NarouContent"
                             predicate:[NSPredicate predicateWithFormat:@"ncode == %@", ncode]];
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
    if([fetchResults count] > 1)
    {
        NSLog(@"duplicate ncode!!! %@ delete all content...", ncode);
        for (int i = 0; i < [fetchResults count]; i++) {
            NarouContent* targetContent = [fetchResults objectAtIndex:i];
            [m_CoreDataObjectHolder DeleteEntity:targetContent];
            [m_CoreDataObjectHolder save];
        }
        return nil;
    }
    return [fetchResults objectAtIndex:0];
}

/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContentCacheData*) SearchNarouContentFromNcode:(NSString*) ncode
{
    __block NarouContentCacheData* result = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:ncode];
        if (coreDataContent != nil) {
            result = [[NarouContentCacheData alloc] initWithCoreData:coreDataContent];
        }
    //});
    }];
    /// TODO: 何故か nil が帰ってくるときは、duplicate ncode で消されてる可能性があるのでsaveしておきます。
    if (result == nil) {
        [self saveContext];
    }
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
    __block BOOL isNeedContentListChangedAnnounce = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        if (coreDataContent == nil) {
            coreDataContent = [self CreateNewNarouContentThreadUnsafe];
            isNeedContentListChangedAnnounce = true;
        }else if(coreDataContent.novelupdated_at != content.novelupdated_at){
            isNeedContentListChangedAnnounce = true;
        }
        result = [content AssignToCoreData:coreDataContent];
        [m_CoreDataObjectHolder save];
    //});
    }];
    if (isNeedContentListChangedAnnounce || true) {
        [self NarouContentListChangedAnnounce];
    }
    return result;
}


/// 新しい NarouContent を生成して返します。
- (NarouContent*) CreateNewNarouContentThreadUnsafe
{
    NarouContent* content = [m_CoreDataObjectHolder CreateNewEntity:@"NarouContent"];
    return content;
}

/// 保存されている NarouContent の数を取得します。
- (NSUInteger) GetNarouContentCount
{
    __block NSUInteger result = 0;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        result = [m_CoreDataObjectHolder CountEntity:@"NarouContent"];
    //});
    }];
    return result;
}

/// NarouContent の全てを NarouContentCacheData の NSArray で取得します
/// novelupdated_at で sort されて返されます。
- (NSMutableArray*) GetAllNarouContent
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"NarouContent" sortAttributeName:@"novelupdated_at" ascending:NO];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[NarouContentCacheData alloc] initWithCoreData:results[i]];
        }
    //});
    }];
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
        return NSLocalizedString(@"GlobalDataSingleton_CanNotGetValidNCODE", @"有効な NCODE を取得できませんでした。");
    }
    NSString* targetNcode = content.ncode;
    __block NarouContentCacheData* targetContentCacheData = [self SearchNarouContentFromNcode:targetNcode];
    if (targetContentCacheData == nil) {
        // 登録がないようなのでとりあえず NarouContent を登録します。
        __block BOOL isNarouContentCreated = false;
        [self coreDataPerfomBlockAndWait:^{
        //dispatch_sync(m_CoreDataAccessQueue, ^{
            NarouContent* targetContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:targetNcode];
            if (targetContent == nil) {
                targetContent = [self CreateNewNarouContentThreadUnsafe];
                isNarouContentCreated = true;
            }
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
            // 新しく作ったので save して main thread と sync しておきます。
            [m_CoreDataObjectHolder save];
        //});
        }];
        if (isNarouContentCreated) {
            [self NarouContentListChangedAnnounce];
        }
    }
    
    /*
    if (targetContentCacheData != nil && ([targetContentCacheData.general_all_no intValue] <= [self CountContentChapter:targetContentCacheData]) ) {
        return NSLocalizedString(@"GlobalDataSingleton_AlreadyDownloaded", @"既にダウンロード済です。");
    }
     */
    
    // download queue に追加します。
    NSLog(@"add download queue.");
    [[GlobalDataSingleton GetInstance] PushContentDownloadQueue:content];
    
    return nil;
}

/// Ncode の指定でダウンロードqueueに追加します。
/// 追加できなかった場合はエラーメッセージを返します。
- (BOOL) AddDownloadQueueForNarouNcode:(NSString*)ncode
{
    return [m_DownloadQueue AddDownloadQueueForNcodeList:ncode];
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
    NSArray* fetchResults = [m_CoreDataObjectHolder SearchEntity:@"Story" predicate:[NSPredicate predicateWithFormat:@"ncode == %@ AND chapter_number == %d", ncode, chapter_number]];
    
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed.");
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* story = [self SearchCoreDataStoryThreadUnsafe:ncode chapter_no:chapter_number];
        if (story != nil) {
            result = [[StoryCacheData alloc] initWithCoreData:story];
        }
    //});
    }];
    return result;
}

/// Story を新しく生成します。必要な情報をすべて指定する必要があります
- (Story*) CreateNewStoryThreadUnsafe:(NarouContent*)parentContent content:(NSString*)content chapter_number:(int)chapter_number;
{
    Story* story = [m_CoreDataObjectHolder CreateNewEntity:@"Story"];

    story.parentContent = parentContent;
    [parentContent addChildStoryObject:story];
        
    story.ncode = parentContent.ncode;
    story.chapter_number = [[NSNumber alloc] initWithInt:chapter_number];
    story.content = content;
    [m_CoreDataObjectHolder save];

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
        //NSLog(@"UpdateStoryThreadUnsafe failed. parenteCoreDataContent is nil");
        result = false;
    }else{
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:parentContent.ncode chapter_no:chapter_number];
        if (coreDataStory == nil) {
            //NSLog(@"UpdateStoryThreadUnsafe: create new story for \"%@\" chapter: %d", parentContent.ncode, chapter_number);
            coreDataStory = [self CreateNewStoryThreadUnsafe:parentCoreDataContent content:content chapter_number: chapter_number];
        }
        coreDataStory.content = content;
        coreDataStory.parentContent = parentCoreDataContent;
        coreDataStory.chapter_number = [[NSNumber alloc] initWithInt:chapter_number];
        if(![m_CoreDataObjectHolder save]){
            //NSLog(@"UpdateStoryThreadUnsafe: m_CoreDataObjectHolder save failed.");
        }
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        result = [self UpdateStoryThreadUnsafe:content chapter_number:chapter_number parentContent:parentContent];
    //});
    }];
    
    return result;
}

- (void)NarouContentListChangedAnnounce
{
    //NSLog(@"NarouContentListChangedAnnounced.");
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSNotification* notification = [NSNotification notificationWithName:@"NarouContentListChanged" object:self];
    [notificationCenter postNotification:notification];
}

/// 小説を一つ削除します
- (BOOL)DeleteContent:(NarouContentCacheData*)content
{
    if (content == nil) {
        return false;
    }
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        if (coreDataContent != nil) {
            [m_CoreDataObjectHolder DeleteEntity:coreDataContent];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    //});
    }];
    if (result) {
        [self NarouContentListChangedAnnounce];
    }
    return result;
}

/// 章を一つ削除します
- (BOOL)DeleteStory:(StoryCacheData *)story
{
    if (story == nil) {
        return false;
    }
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:[story.chapter_number intValue]];
        if (coreDataStory == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataStory];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    //});
    }];
    return result;
}

/// 対象の小説でCoreDataに保存されている章の数を取得します。
- (NSUInteger)CountContentChapter:(NarouContentCacheData*)content
{
    if (content == nil || content.ncode == nil) {
        return 0;
    }
    
    __block NSUInteger result = 0;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        result = [m_CoreDataObjectHolder CountEntity:@"Story" predicate:[NSPredicate predicateWithFormat:@"ncode == %@", content.ncode]];
    //});
    }];
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
    NSUInteger location = [story.readLocation integerValue];
    if (location == [story.content length] && [story.content length] > 0) {
        location = [story.content length] - 1;
    }
    //[self AddLogString:[[NSString alloc] initWithFormat:@"読み上げ位置を保存します。(%@) 章: %d 位置: %ld/%ld", content.title, [story.chapter_number intValue], (long)location, (unsigned long)[story.content length]]]; // NSLog

    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:[story.chapter_number intValue]];
        GlobalState* globalState = [self GetCoreDataGlobalStateThreadUnsafe];
        if (coreDataContent == nil || coreDataStory == nil || globalState == nil) {
            result = false;
        }else{
            coreDataStory.readLocation = [[NSNumber alloc] initWithUnsignedInteger:location];
            coreDataContent.currentReadingStory = coreDataStory;
            globalState.currentReadingStory = coreDataStory;
            [m_CoreDataObjectHolder save];
            result = true;
        }
    //});
    }];
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* nextCoreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:target_chapter_number];
        if (nextCoreDataStory != nil) {
            //NSLog(@"chapter: %d is alive", target_chapter_number);
            result = [[StoryCacheData alloc] initWithCoreData:nextCoreDataStory];
        }else{
            NSLog(@"chapter: %d is NOT alive", target_chapter_number);
        }
    //});
    }];
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* previousCoreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:target_chapter_number];
        if (previousCoreDataStory != nil) {
            result = [[StoryCacheData alloc] initWithCoreData:previousCoreDataStory];
        }
    //});
    }];
    return result;
}

- (void)UpdatePlayingInfo:(StoryCacheData*)story
{
    NSString* titleName = NSLocalizedString(@"GlobalDataSingleton_NoPlaing", @"再生していません");
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

- (void)InsertDefaultSpeakPitchConfig
{
    NSArray* speechConfigArray = [self GetAllSpeakPitchConfig];
    if (speechConfigArray == nil || [speechConfigArray count] <= 0) {
        // 設定が無いようなので勝手に作ります。
        SpeakPitchConfigCacheData* speakConfig = [SpeakPitchConfigCacheData new];
        speakConfig.title = NSLocalizedString(@"GlobalDataSingleton_Conversation1", @"会話文");
        speakConfig.pitch = [[NSNumber alloc] initWithFloat:1.5f];
        speakConfig.startText = @"「";
        speakConfig.endText = @"」";
        [self UpdateSpeakPitchConfig:speakConfig];
        speakConfig.title = NSLocalizedString(@"GlobalDataSingleton_Conversation2", @"会話文 2");
        speakConfig.pitch = [[NSNumber alloc] initWithFloat:1.2f];
        speakConfig.startText = @"『";
        speakConfig.endText = @"』";
        [self UpdateSpeakPitchConfig:speakConfig];
    }
}

/// 標準の読み上げ辞書のリストを取得します
- (NSDictionary*)GetDefaultSpeechModConfig {
    NSDictionary* dataDictionary = @{
        @"黒剣": @"コッケン"
        , @"黒尽くめ": @"黒づくめ"
        , @"黒剣": @"コッケン"
        , @"鶏ガラ": @"トリガラ"
        , @"魚醤": @"ギョショウ"
        , @"魔石": @"ませき"
        , @"魔獣": @"まじゅう"
        , @"魔導": @"まどう"
        , @"魔人": @"まじん"
        , @"駄弁る": @"だべる"
        , @"食い千切": @"くいちぎ"
        , @"飛翔体": @"ヒショウタイ"
        , @"飛来物": @"ヒライブツ"
        , @"願わくば": @"ねがわくば"
        , @"頑な": @"かたくな"
        , @"静寂": @"せいじゃく"
        , @"霊子": @"れいし"
        , @"霊体": @"れいたい"
        , @"集音": @"シュウオン"
        , @"闘術": @"闘じゅつ"
        , @"間髪": @"カンパツ"
        , @"金属片": @"金属ヘン"
        , @"金属板": @"キンゾクバン"
        , @"重装備": @"ジュウソウビ"
        , @"重火器": @"ジュウカキ"
        , @"重武装": @"ジュウブソウ"
        , @"重機関銃": @"ジュウキカンジュウ"
        , @"重低音": @"ジュウテイオン"
        , @"遮蔽物": @"シャヘイブツ"
        , @"遠まわし": @"とおまわし"
        , @"過去形": @"カコケイ"
        , @"火器": @"ジュウカキ"
        , @"造作もな": @"ゾウサもな"
        , @"通信手": @"ツウシンシュ"
        , @"轟炎": @"ゴウエン"
        , @"車列": @"シャレツ"
        , @"身分証": @"ミブンショウ"
        , @"身体能力": @"しんたい能力"
        , @"身体": @"からだ"
        , @"身を粉に": @"身をコに"
        , @"蹴散ら": @"ケチら"
        , @"踵を返": @"きびすを返"
        , @"貴船": @"キセン"
        , @"貧乳": @"ひんにゅう"
        , @"謁見の間": @"謁見のま"
        , @"解毒薬": @"ゲドクヤク"
        , @"規格外": @"キカクガイ"
        , @"要確認": @"ヨウ確認"
        , @"要救助者": @"ヨウ救助者"
        , @"複数人": @"複数ニン"
        , @"装甲板": @"装甲バン"
        , @"術者": @"ジュツシャ"
        , @"術式": @"ジュツシキ"
        , @"術師": @"ジュツシ"
        , @"行ってらっしゃい": @"いってらっしゃい"
        , @"行ってきます": @"いってきます"
        , @"行ったり来たり": @"いったりきたり"
        , @"血肉": @"チニク"
        , @"虫唾が走": @"ムシズが走"
        , @"薬師": @"くすし"
        , @"薬室": @"やくしつ"
        , @"薄明り": @"うすあかり"
        , @"薄ら": @"ウスラ"
        , @"荷馬車": @"ニバシャ"
        , @"艶めかし": @"なまめかし"
        , @"艶かし": @"なまめかし"
        , @"艦首": @"カンシュ"
        , @"艦影": @"カンエイ"
        , @"船外": @"センガイ"
        , @"脳筋": @"ノウキン"
        , @"聖骸布": @"セーガイフ"
        , @"聖骸": @"セーガイ"
        , @"聖騎士": @"セイキシ"
        , @"義体": @"ギタイ"
        , @"美男子": @"ビナンシ"
        , @"美味さ": @"ウマさ"
        , @"美味い": @"うまい"
        , @"美乳": @"びにゅう"
        , @"縞々": @"シマシマ"
        , @"緊急時": @"キンキュウジ"
        , @"絢十": @"あやと"
        , @"経験値": @"経験チ"
        , @"素体": @"そたい"
        , @"純心": @"ジュンシン"
        , @"精神波": @"セイシンハ"
        , @"米粒": @"コメツブ"
        , @"等間隔": @"トウカンカク"
        , @"笑い者": @"ワライモノ"
        , @"竜人": @"リュウジン"
        , @"空賊": @"クウゾク"
        , @"私掠船": @"シリャクセン"
        , @"神獣": @"シンジュウ"
        , @"祖父ちゃん": @"じいちゃん"
        , @"知性体": @"知性たい"
        , @"瞬殺": @"シュンサツ"
        , @"着艦": @"チャッカン"
        , @"真っ暗": @"まっくら"
        , @"真っ只中": @"マッタダナカ"
        , @"真っ二つ": @"まっぷたつ"
        , @"相も変わ": @"アイも変わ"
        , @"直継": @"ナオツグ"
        , @"発艦": @"ハッカン"
        , @"発射管": @"ハッシャカン"
        , @"発射口": @"ハッシャコウ"
        , @"異能": @"イノウ"
        , @"異空間": @"イクウカン"
        , @"異種族": @"いしゅぞく"
        , @"異界": @"イカイ"
        , @"異獣": @"いじゅう"
        , @"異次元": @"いじげん"
        , @"異世界": @"イセカイ"
        , @"男性器": @"ダンセイキ"
        , @"甜麺醤": @"テンメンジャン"
        , @"甘っちょろ": @"アマっちょろ"
        , @"環境下": @"環境か"
        , @"理想形": @"リソウケイ"
        , @"獣道": @"けものみち"
        , @"獣人": @"じゅうじん"
        , @"牛すじ": @"ギュウスジ"
        , @"爆発物": @"バクハツブツ"
        , @"爆炎": @"ばくえん"
        , @"熱波": @"ネッパ"
        , @"照ら": @"てら"
        , @"煎れ": @"いれ"
        , @"火星": @"カセイ"
        , @"火器": @"カキ"
        , @"漢探知": @"男探知"
        , @"漏ら": @"もら"
        , @"満タン": @"まんたん"
        , @"淹れ": @"いれ"
        , @"海賊船": @"海賊セン"
        , @"海兵隊": @"かいへいたい"
        , @"浮遊物": @"フユウブツ"
        , @"汝ら": @"なんじら"
        , @"氷のう": @"ヒョウノウ"
        , @"水場": @"水ば"
        , @"気弾": @"キダン"
        , @"気に食": @"きにく"
        , @"民間船": @"ミンカンセン"
        , @"殺人鬼": @"サツジンキ"
        , @"死に体": @"シニタイ"
        , @"機雷原": @"キライゲン"
        , @"構造物": @"コウゾウブツ"
        , @"極悪人": @"ゴクアクニン"
        , @"極々": @"ゴクゴク"
        , @"来いよ": @"こいよ"
        , @"木製": @"モクセイ"
        , @"望み薄": @"ノゾミウス"
        , @"月光神": @"ゲッコウシン"
        , @"最上階": @"さいじょうかい"
        , @"星間物質": @"セイカンブッシツ"
        , @"星系": @"セイケイ"
        , @"星域": @"セイイキ"
        , @"敵船": @"テキセン"
        , @"敵性体": @"敵性たい"
        , @"敵わない": @"かなわない"
        , @"数週間": @"スウシュウカン"
        , @"支配下": @"シハイカ"
        , @"擲弾": @"てきだん"
        , @"操船中": @"ソウセンチュウ"
        , @"操船": @"そうせん"
        , @"接敵": @"セッテキ"
        , @"排泄物": @"ハイセツブツ"
        , @"掌砲長": @"ショウホウチョウ"
        , @"掌砲手": @"ショウホウシュ"
        , @"掌打": @"しょうだ"
        , @"掌帆長": @"ショウハンチョウ"
        , @"指揮車": @"シキシャ"
        , @"拙い": @"マズイ"
        , @"技術者": @"ギジュツシャ"
        , @"手練れ": @"テダレ"
        , @"所狭し": @"トコロセマシ"
        , @"成程": @"なるほど"
        , @"慌ただし": @"あわただし"
        , @"愛国心": @"アイコクシン"
        , @"愛おし": @"いとおし"
        , @"悪趣味": @"あくしゅみ"
        , @"悪戯": @"いたずら"
        , @"急ごしらえ": @"キュウゴシラエ"
        , @"念話": @"ネンワ"
        , @"忠誠心": @"忠誠シン"
        , @"忌み子": @"イミコ"
        , @"心配性": @"シンパイショウ"
        , @"心拍": @"シンパク"
        , @"徹甲弾": @"テッコウダン"
        , @"微乳": @"びにゅう"
        , @"後がない": @"アトがない"
        , @"彷徨う": @"さまよう"
        , @"影響下": @"エイキョウカ"
        , @"弾着": @"ダンチャク"
        , @"弾倉": @"だんそう"
        , @"強張る": @"こわばる"
        , @"引きこもり": @"ひきこもり"
        , @"幻獣": @"ゲンジュウ"
        , @"幸か不幸": @"コウかフコウ"
        , @"年単位": @"ネンタンイ"
        , @"平常心": @"ヘイジョウシン"
        , @"席替え": @"セキガエ"
        , @"巨乳": @"きょにゅう"
        , @"小柄": @"こがら"
        , @"小型船": @"コガタセン"
        , @"小一時間": @"コ1時間"
        , @"対戦車": @"たいせんしゃ"
        , @"寝顔": @"ネガオ"
        , @"害獣": @"ガイジュウ"
        , @"安酒": @"ヤスザケ"
        , @"宇宙船乗り": @"ウチュウセンノリ"
        , @"宇宙暦": @"ウチュウレキ"
        , @"宇宙人": @"ウチュウジン"
        , @"孫子": @"ソンシ"
        , @"姫君": @"ヒメギミ"
        , @"姉上": @"アネウエ"
        , @"姉ぇ": @"ネエ"
        , @"妖艶": @"ようえん"
        , @"妖獣": @"ヨウジュウ"
        , @"妖人": @"ようじん"
        , @"奴ら": @"ヤツら"
        , @"女性器": @"ジョセイキ"
        , @"女子力": @"女子りょく"
        , @"太陽神": @"タイヨウシン"
        , @"太もも": @"フトモモ"
        , @"天晴れ": @"アッパレ"
        , @"大馬鹿": @"オオバカ"
        , @"大賢者": @"だいけんじゃ"
        , @"大津波": @"オオツナミ"
        , @"大泣き": @"オオナキ"
        , @"大所帯": @"オオジョタイ"
        , @"大慌て": @"おおあわて"
        , @"大怪我": @"オオ怪我"
        , @"大地人": @"だいちじん"
        , @"大嘘": @"オオウソ"
        , @"大人": @"おとな"
        , @"大っぴら": @"おおっぴら"
        , @"外殻": @"ガイカク"
        , @"外惑星": @"ガイワクセイ"
        , @"壊れ難": @"壊れにく"
        , @"墓所": @"ボショ"
        , @"地球外": @"チキュウガイ"
        , @"地底人": @"ちていじん"
        , @"回頭": @"カイトウ"
        , @"喰う": @"くう"
        , @"喜声": @"キセイ"
        , @"問題外": @"モンダイガイ"
        , @"問題児": @"問題じ"
        , @"商根たくまし": @"ショウコンたくまし"
        , @"呻り声": @"唸り声"
        , @"同じ様": @"同じヨウ"
        , @"可笑し": @"おかし"
        , @"召喚術": @"ショウカンジュツ"
        , @"召喚獣": @"ショウカンジュウ"
        , @"友軍艦": @"ユウグンカン"
        , @"去り際": @"サリギワ"
        , @"厨二": @"チュウニ"
        , @"厄介者": @"ヤッカイモノ"
        , @"南部": @"なんぶ"
        , @"千載一遇": @"センザイイチグウ"
        , @"千切れ": @"ちぎれ"
        , @"勝負所": @"勝負ドコロ"
        , @"力場": @"りきば"
        , @"創造神": @"ソウゾウシン"
        , @"剣鬼": @"ケンキ"
        , @"剣聖": @"ケンセイ"
        , @"剣神": @"ケンシン"
        , @"初見": @"しょけん"
        , @"初弾": @"ショダン"
        , @"分身": @"ぶんしん"
        , @"分は悪": @"ブは悪"
        , @"分が悪": @"ブが悪"
        , @"再戦": @"サイセン"
        , @"円筒形": @"円筒ケイ"
        , @"内容物": @"ナイヨウブツ"
        , @"入出口": @"ニュウシュツコウ"
        , @"兎に角": @"とにかく"
        , @"光秒": @"コウビョウ"
        , @"光時": @"コウジ"
        , @"光分": @"コウフン"
        , @"兄ちゃん": @"ニイチャン"
        , @"兄ぃ": @"にい"
        , @"健康体": @"健康タイ"
        , @"偏光": @"ヘンコウ"
        , @"俺達": @"おれたち"
        , @"何時の間": @"いつのま"
        , @"何？": @"なに？"
        , @"体育祭": @"タイイクサイ"
        , @"体当たり": @"たいあたり"
        , @"以ての外": @"モッテノホカ"
        , @"他ならぬ": @"ほかならぬ"
        , @"仔牛": @"コウシ"
        , @"今作戦": @"コン作戦"
        , @"人肉": @"じんにく"
        , @"人的資源": @"ジンテキシゲン"
        , @"人狼": @"じんろう"
        , @"人数分": @"ニンズウブン"
        , @"人工物": @"ジンコウブツ"
        , @"予定表": @"ヨテイヒョウ"
        , @"乱高下": @"ランコオゲ"
        , @"主機": @"シュキ"
        , @"主兵装": @"シュヘイソウ"
        , @"中破": @"チュウハ"
        , @"中年": @"ちゅうねん"
        , @"中の中": @"チュウのチュウ"
        , @"中の下": @"チュウのゲ"
        , @"中の上": @"チュウのジョウ"
        , @"世界樹": @"せかいじゅ"
        , @"不届き者": @"不届きモノ"
        , @"不味い": @"まずい"
        , @"下ネタ": @"シモネタ"
        , @"下の中": @"ゲのチュウ"
        , @"下の下": @"ゲのゲ"
        , @"下の上": @"ゲのジョウ"
        , @"上腕二頭筋": @"ジョウワンニトウキン"
        , @"上方修正": @"じょうほう修正"
        , @"上の中": @"ジョウのチュウ"
        , @"上の下": @"ジョウのゲ"
        , @"上の上": @"ジョウのジョウ"
        , @"三日三晩": @"ミッカミバン"
        , @"三国": @"サンゴク"
        , @"三々五々": @"さんさんごご"
        , @"万人": @"マンニン"
        , @"一級品": @"イッキュウヒン"
        , @"一目置": @"イチモク置"
        , @"一目惚れ": @"ヒトメボレ"
        , @"一派": @"イッパ"
        , @"一日の長": @"イチジツノチョウ"
        , @"一品物": @"イッピンモノ"
        , @"一分の隙": @"いちぶの隙"
        , @"ボクっ娘": @"ボクっ子"
        , @"ペルセウス腕": @"ペルセウスワン"
        , @"ペイント弾": @"ペイントダン"
        , @"ドジっ娘": @"ドジっ子"
        , @"シュミレー": @"シミュレー"
        , @"カレー粉": @"カレーコ"
        , @"カズ彦": @"カズヒコ"
        , @"よそ者": @"ヨソモノ"
        , @"ひと言": @"ヒトコト"
        , @"の宴": @"のうたげ"
        , @"にゃん太": @"ニャンタ"
        , @"そこら中": @"ソコラジュウ"
        , @"この上ない": @"このうえない"
        , @"お米": @"おこめ"
        , @"お祖父": @"おじい"
        , @"お姉": @"オネエ"
        , @"お兄様": @"おにいさま"
        , @"お兄さま": @"おにいさま"
        , @"お付き": @"おつき"
        , @"いつの間に": @"いつのまに"
        , @"ある種": @"あるしゅ"
        , @"あっという間": @"あっというま"
        
        // 2016/07/29 added.
        , @"～": @"ー"
        , @"麻婆豆腐": @"マーボードーフ"
        , @"麻婆": @"マーボー"
        , @"豆板醤": @"トーバンジャン"
        , @"言葉少な": @"言葉すくな"
        , @"聖印": @"セイイン"
        , @"籠城": @"ロウジョウ"
        , @"禁術": @"キンジュツ"
        , @"神兵": @"シンペイ"
        , @"着ぐるみ": @"キグルミ"
        , @"白狼": @"ハクロウ"
        , @"町人": @"チョウニン"
        , @"恐怖心": @"キョウフシン"
        , @"幼生体": @"幼生タイ"
        , @"天神": @"テンジン"
        , @"大皿": @"オオザラ"
        , @"大喧嘩": @"オオゲンカ"
        , @"味方": @"ミカタ"
        , @"吐瀉物": @"トシャブツ"
        , @"古井戸": @"フル井戸"
        , @"兄様": @"ニイサマ"
        , @"使用人": @"シヨウニン"
        , @"体術": @"タイジュツ"
        , @"住人": @"ジュウニン"
        , @"亜人": @"アジン"
        , @"二つ名": @"ふたつナ"
        , @"三角コーナー": @"サンカクコーナー"
        , @"メイド頭": @"メイドガシラ"
        , @"トン汁": @"トンジル"
        , @"カツ丼": @"カツドン"
        , @"お祖母": @"おばあ"
        
        , @"〜": @"ー"
        
        , @"α": @"アルファ"
        , @"Α": @"アルファ"
        , @"β": @"ベータ"
        , @"Β": @"ベータ"
        , @"γ": @"ガンマ"
        , @"Γ": @"ガンマ"
        , @"δ": @"デルタ"
        , @"Δ": @"デルタ"
        , @"ε": @"イプシロン"
        , @"Ε": @"イプシロン"
        , @"ζ": @"ゼータ"
        , @"Ζ": @"ゼータ"
        , @"η": @"エータ"
        , @"θ": @"シータ"
        , @"Θ": @"シータ"
        , @"ι": @"イオタ"
        , @"κ": @"カッパ"
        , @"λ": @"ラムダ"
        , @"μ": @"ミュー"
        , @"ν": @"ニュー"
        , @"ο": @"オミクロン"
        , @"π": @"パイ"
        , @"Π": @"パイ"
        , @"ρ": @"ロー"
        , @"σ": @"シグマ"
        , @"Σ": @"シグマ"
        , @"τ": @"タウ"
        , @"υ": @"ユプシロン"
        , @"φ": @"ファイ"
        , @"Φ": @"ファイ"
        , @"χ": @"カイ"
        , @"ψ": @"プサイ"
        , @"ω": @"オメガ"
        , @"Ω": @"オメガ"
        
        , @"Ⅰ": @"1"
        , @"Ⅱ": @"2"
        , @"Ⅲ": @"3"
        , @"Ⅳ": @"4"
        , @"Ⅴ": @"5"
        , @"Ⅵ": @"6"
        , @"Ⅶ": @"7"
        , @"Ⅷ": @"8"
        , @"Ⅸ": @"9"
        , @"Ⅹ": @"10"
        , @"ⅰ": @"1"
        , @"ⅱ": @"2"
        , @"ⅲ": @"3"
        , @"ⅳ": @"4"
        , @"ⅴ": @"5"
        , @"ⅵ": @"6"
        , @"ⅶ": @"7"
        , @"ⅷ": @"8"
        , @"ⅸ": @"9"
        , @"ⅹ": @"10"
        
        , @"※": @" "
        
        , @"Plant hwyaden": @"プラント・フロウデン"
        , @"Ｐｌａｎｔ　ｈｗｙａｄｅｎ": @"プラント・フロウデン"
        , @"VRMMORPG": @"VR MMORPG"
        , @"ＢＩＳＨＯＰ": @"ビショップ"
        , @"ＡＩ": @"エエアイ"
        };
    return dataDictionary;
}

/// 標準の読み替え辞書を上書き追加します。
- (void)InsertDefaultSpeechModConfig
{
    NSDictionary* dataDictionary = [self GetDefaultSpeechModConfig];
    SpeechModSettingCacheData* speechModSetting = [SpeechModSettingCacheData new];
    for (NSString* key in [dataDictionary keyEnumerator]) {
        speechModSetting.beforeString = key;
        speechModSetting.afterString = [dataDictionary objectForKey:key];
        [self UpdateSpeechModSetting:speechModSetting];
    }
}

- (void)InsertDefaultSpeechWaitConfig
{
    NSArray* currentSpeechWaitSettingList = [self GetAllSpeechWaitConfig];
    if (currentSpeechWaitSettingList != nil && [currentSpeechWaitSettingList count] > 0) {
        // 何かあるなら追加しません。
        return;
    }
    {
        // 改行2つは 0.5秒待たせます
        SpeechWaitConfigCacheData* waitConfig = [SpeechWaitConfigCacheData new];
        waitConfig.targetText = @"\r\n\r\n";
        waitConfig.delayTimeInSec = [[NSNumber alloc] initWithFloat:0.5f];
        [[GlobalDataSingleton GetInstance] AddSpeechWaitSetting:waitConfig];
    }
    NSArray* defaultSpeechWaitTargets = [[NSArray alloc] initWithObjects:
                                         @"……"
                                         , @"、"
                                         , @"。"
                                         , @"・"
                                         , nil];
    
    for (NSString* targetString in defaultSpeechWaitTargets) {
        SpeechWaitConfigCacheData* waitConfig = [SpeechWaitConfigCacheData new];
        waitConfig.targetText = targetString;
        waitConfig.delayTimeInSec = [[NSNumber alloc] initWithFloat:0.0f];
        [[GlobalDataSingleton GetInstance] AddSpeechWaitSetting:waitConfig];
    }
}

/// 何も設定されていなければ標準のデータを追加します。
- (void)InsertDefaultSetting
{
    [self InsertDefaultSpeakPitchConfig];
    NSArray* speechModConfigArray = [self GetAllSpeechModSettings];
    if (speechModConfigArray == nil || [speechModConfigArray count] <= 0) {
        // これも無いようなので勝手に作ります。
        [self InsertDefaultSpeechModConfig];
    }
    [self InsertDefaultSpeechWaitConfig];
}

/// NiftySpeaker に現在の標準設定を登録します
- (void)ApplyDefaultSpeechconfig:(NiftySpeaker*)niftySpeaker
{
    GlobalStateCacheData* globalState = [self GetGlobalState];
    SpeechConfig* defaultSetting = [SpeechConfig new];
    defaultSetting.pitch = [globalState.defaultPitch floatValue];
    defaultSetting.rate = [globalState.defaultRate floatValue];
    defaultSetting.beforeDelay = 0.0f;
    [niftySpeaker SetDefaultSpeechConfig:defaultSetting];
}

/// NiftySpeakerに現在の読み上げの声質の設定を登録します
- (void)ApplySpeakPitchConfig:(NiftySpeaker*) niftySpeaker
{
    GlobalStateCacheData* globalState = [self GetGlobalState];
    
    NSArray* speechConfigArray = [self GetAllSpeakPitchConfig];
    if (speechConfigArray != nil) {
        for (SpeakPitchConfigCacheData* pitchConfig in speechConfigArray) {
            SpeechConfig* speechConfig = [SpeechConfig new];
            speechConfig.pitch = [pitchConfig.pitch floatValue];
            speechConfig.rate = [globalState.defaultRate floatValue];
            speechConfig.beforeDelay = 0.0f;
            [niftySpeaker AddBlockStartSeparator:pitchConfig.startText endString:pitchConfig.endText speechConfig:speechConfig];
        }
    }
}

/// NiftySpeakerに現在の読みの「間」の設定を登録します
- (void)ApplySpeechWaitConfig:(NiftySpeaker*) niftySpeaker
{
    GlobalStateCacheData* globalState = [self GetGlobalState];
    
    NSArray* speechWaitConfigList = [self GetAllSpeechWaitConfig];
    if (speechWaitConfigList != nil) {
        for (SpeechWaitConfigCacheData* speechWaitConfigCache in speechWaitConfigList) {
            float delay = [speechWaitConfigCache.delayTimeInSec floatValue];
            if (delay > 0.0f) {
                if ([globalState.speechWaitSettingUseExperimentalWait boolValue]) {
                    NSMutableString* waitString = [[NSMutableString alloc] initWithString:@"。"];
                    for (float x = 0.0f; x < delay; x += 0.1f) {
                        [waitString appendString:@"_。"];
                    }
                    [niftySpeaker AddSpeechModText:speechWaitConfigCache.targetText to:waitString];
                }else{
                    [niftySpeaker AddDelayBlockSeparator:speechWaitConfigCache.targetText delay:delay];
                }
            }
        }
    }
}

/// NiftySpeakerに現在の読み替え設定を登録します
- (void)ApplySpeechModConfig:(NiftySpeaker*)niftySpeaker
{
    NSArray* speechModConfigArray = [self GetAllSpeechModSettings];
    if (speechModConfigArray != nil) {
        for (SpeechModSettingCacheData* speechModSetting in speechModConfigArray) {
            [niftySpeaker AddSpeechModText:speechModSetting.beforeString to:speechModSetting.afterString];
        }
    }
}

/// 読み上げ設定を読み直します。
- (BOOL)ReloadSpeechSetting
{
    [m_NiftySpeaker ClearSpeakSettings];
    [self ApplyDefaultSpeechconfig:m_NiftySpeaker];
    [self ApplySpeakPitchConfig:m_NiftySpeaker];
    [self ApplySpeechWaitConfig:m_NiftySpeaker];
    [self ApplySpeechModConfig:m_NiftySpeaker];
    return true;
}

/// ncode の new flag を落とします。
- (void)DropNewFlag:(NSString*)ncode
{
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* content = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:ncode];
        if ([content.is_new_flug boolValue] == true) {
            NSLog(@"new flag drop: %@", ncode);
            content.is_new_flug = [[NSNumber alloc] initWithBool:false];
            [m_CoreDataObjectHolder save];
        
        }
    //});
    }];
    // drop の Notification を飛ばします
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusDown_%@", ncode];
    NSNotification* notification = [NSNotification notificationWithName:notificationName object:self];
    [notificationCenter postNotification:notification];
}

/// &amp; を & とかに変換します
- (NSString*)UnescapeHTMLEntities:(NSString*)str
{
    NSString *returnStr = nil;
    
    if(str == nil)
    {
        return nil;
    }
    returnStr = [str stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&#x27;" withString:@"'"];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&#x39;" withString:@"'"];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&#x92;" withString:@"'"];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&#x96;" withString:@"'"];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"&amp;" withString: @"&"];

    // 小説家になろうのタグ
    // http://syosetu.com/man/tag/
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"<PBR>" withString: @"\r\n"]; // PCでの改行
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"<KBR>" withString: @""]; // 携帯での改行
    returnStr = [returnStr stringByReplacingOccurrencesOfString:@"【改ページ】" withString: @""]; // 携帯での改ページ
    returnStr = [[NSString alloc] initWithString:returnStr];

    return returnStr;
}

/// story の文章を表示用の文字列に変換します。
- (NSString*)ConvertStoryContentToDisplayText:(StoryCacheData*)story
{
    if (story == nil) {
        return nil;
    }
    return [self UnescapeHTMLEntities:story.content];
}

/// 読み上げる文書を設定します。
- (BOOL)SetSpeechStory:(StoryCacheData *)story
{
    if(![m_NiftySpeaker SetText:[self ConvertStoryContentToDisplayText:story]])
    {
        return false;
    }
    [self UpdatePlayingInfo:story];
    [self DropNewFlag:story.ncode];
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

/// 読み上げ停止のタイマーを開始します
- (void)StartMaxSpeechTimeInSecTimer
{
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    NSNumber* maxSpeechTimeInSec = [globalData GetGlobalState].maxSpeechTimeInSec;
    if (maxSpeechTimeInSec == nil) {
        return;
    }
    [self StopMaxSpeechTimeInSecTimer];

    m_MaxSpeechTimeInSecTimer = [NSTimer scheduledTimerWithTimeInterval:[maxSpeechTimeInSec intValue] target:self selector:@selector(MaxSpeechTimeInSecEventHandler:) userInfo:nil repeats:NO];
    //[m_MaxSpeechTimeInSecTimer fire]; // fire すると時間経過に関係なくすぐにイベントが発生するっぽいです。単にタイマーを作った時点でもう時間計測は開始している模様
}

/// 読み上げ停止のタイマーを停止します
- (void)StopMaxSpeechTimeInSecTimer
{
    if (m_MaxSpeechTimeInSecTimer != nil && [m_MaxSpeechTimeInSecTimer isValid]) {
        [m_MaxSpeechTimeInSecTimer invalidate];
    }
    m_MaxSpeechTimeInSecTimer = nil;
}

/// 読み上げ停止のタイマー呼び出しのイベントハンドラ
- (void)MaxSpeechTimeInSecEventHandler:(NSTimer*)timer
{
    if (m_MaxSpeechTimeInSecTimer != nil) {
        if (m_MaxSpeechTimeInSecTimer != timer) {
            [[GlobalDataSingleton GetInstance] AddLogString:[[NSString alloc] initWithFormat:@"MaxSpeechTimeInSecEventHandler が呼び出されたけれど、Timer のポインタが違ったので読み上げは停止しません。(timer: %p, m_MaxSpeechTimeInSecTimer: %p", timer, m_MaxSpeechTimeInSecTimer]]; // NSLog
        }else{
            [[GlobalDataSingleton GetInstance] AddLogString:@"MaxSpeechTimeInSecEventHandler が呼び出されたので読み上げを止めます。"]; // NSLog
            [self StopSpeech];
        }
    }else{
        [[GlobalDataSingleton GetInstance] AddLogString:@"MaxSpeechTimeInSecEventHandler が呼び出されたけれど、m_MaxSpeechTimeInSecTimer が nil でした。"]; // NSLog
    }
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
    //NSLog(@"setActive YES.");
    [session setActive:YES error:&err];
    if (err != nil) {
        NSLog(@"setActive error: %@ %@", err, err.userInfo);
    }
    [self StartMaxSpeechTimeInSecTimer];
    return [m_NiftySpeaker StartSpeech];
}

/// 読み上げを「バックグラウンド再生としては止めずに」読み上げ部分だけ停止します
- (BOOL)StopSpeechWithoutDiactivate
{
    [self StopMaxSpeechTimeInSecTimer];
    if([m_NiftySpeaker StopSpeech] == false)
    {
        return false;
    }
    return true;
}

/// 読み上げを停止します。
- (BOOL)StopSpeech
{
    AVAudioSession* session = [AVAudioSession sharedInstance];
    bool result = [self StopSpeechWithoutDiactivate];
    //NSLog(@"setActive NO.");
    [session setActive:NO error:nil];
    return result;
}

/// 読み上げ時のイベントハンドラを追加します。
- (BOOL)AddSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate
{
    //NSLog(@"AddSpeakRangeDelegate");
    return [m_NiftySpeaker AddSpeakRangeDelegate:delegate];
}

/// 読み上げ時のイベントハンドラを削除します。
- (void)DeleteSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate
{
    //NSLog(@"delete speak range delegate.");
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

- (void)saveContext
{
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        [m_CoreDataObjectHolder save];
    //});
    }];
    //NSLog(@"CoreData saved.");
}

/// 読み上げの会話文の音程設定を全て読み出します。
/// NSArray の中身は SpeakPitchConfigCacheData で、title でsortされた値が取得されます。
- (NSArray*)GetAllSpeakPitchConfig
{
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"SpeakPitchConfig" sortAttributeName:@"title" ascending:NO];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeakPitchConfigCacheData alloc] initWithCoreData:results[i]];
        }
    //});
    }];
    return fetchResults;
}

/// 読み上げの会話文の音程設定をタイトル指定で読み出します。(内部版)
- (SpeakPitchConfig*)GetSpeakPitchConfigWithTitleThreadUnsafe:(NSString*)title
{
    NSArray* fetchResults = [m_CoreDataObjectHolder SearchEntity:@"SpeakPitchConfig" predicate:[NSPredicate predicateWithFormat:@"title == %@", title]];
    
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed.");
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:title];
        if (coreDataConfig != nil) {
            result = [[SpeakPitchConfigCacheData alloc] initWithCoreData:coreDataConfig];
        }
    //});
    }];
    return result;
}

/// 読み上げの会話文の音程設定を追加します。
- (SpeakPitchConfig*) CreateNewSpeakPitchConfigThreadUnsafe:(SpeakPitchConfigCacheData*)data
{
    SpeakPitchConfig* config = [m_CoreDataObjectHolder CreateNewEntity:@"SpeakPitchConfig"];
    if (config == nil) {
        return nil;
    }
    [data AssignToCoreData:config];
    [m_CoreDataObjectHolder save];
    return config;
}

/// 読み上げの会話文の音程設定を更新します。
- (BOOL)UpdateSpeakPitchConfig:(SpeakPitchConfigCacheData*)config
{
    if (config == nil) {
        return false;
    }
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:config.title];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeakPitchConfigThreadUnsafe:config];
        }
        if (coreDataConfig != nil) {
            result = [config AssignToCoreData:coreDataConfig];
            [m_CoreDataObjectHolder save];
        }
    //});
    }];
    if (result) {
        //NSLog(@"isNeedReloadSpeakSetting = true (pitch)");
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}

/// 読み上げの会話文の音声設定を削除します。
- (BOOL)DeleteSpeakPitchConfig:(SpeakPitchConfigCacheData*)config
{
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:config.title];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataConfig];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    //});
    }];
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}


/// 読み上げ時の読み替え設定を全て読み出します。
/// NSArray の中身は SpeechModSettingCacheData で、beforeString で sort された値が取得されます。
- (NSArray*)GetAllSpeechModSettings
{
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"SpeechModSetting" sortAttributeName:@"beforeString" ascending:NO];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeechModSettingCacheData alloc] initWithCoreData:results[i]];
        }
    //});
    }];
    return fetchResults;
}

/// 読み上げ時の読み替え設定を beforeString指定 で読み出します(内部版)
- (SpeechModSetting*)GetSpeechModSettingWithBeforeStringThreadUnsafe:(NSString*)beforeString
{
    NSArray* fetchResults = [m_CoreDataObjectHolder SearchEntity:@"SpeechModSetting" predicate:[NSPredicate predicateWithFormat:@"beforeString == %@", beforeString]];
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed.");
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
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataSetting = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:beforeString];
        if (coreDataSetting != nil) {
            result = [[SpeechModSettingCacheData alloc] initWithCoreData:coreDataSetting];
        }
    //});
    }];
    return result;
}

/// 読み上げ時の読み替え設定を追加します。
- (SpeechModSetting*) CreateNewSpeechModSettingThreadUnsafe:(SpeechModSettingCacheData*)data
{
    SpeechModSetting* setting = [m_CoreDataObjectHolder CreateNewEntity:@"SpeechModSetting"];
    [data AssignToCoreData:setting];
    [m_CoreDataObjectHolder save];
    return setting;
}

/// 読み上げ時の読み替え設定を更新します。無ければ新しく登録されます。
- (BOOL)UpdateSpeechModSetting:(SpeechModSettingCacheData*)modSetting
{
    if (modSetting == nil) {
        return false;
    }
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:modSetting.beforeString];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeechModSettingThreadUnsafe:modSetting];
        }
        if (coreDataConfig != nil) {
            result = [modSetting AssignToCoreData:coreDataConfig];
            [m_CoreDataObjectHolder save];
        }
    //});
    }];
    if (result) {
        //NSLog(@"isNeedReloadSpeakSetting = true (speechMod)");
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}

/// 読み上げ時の読み替え設定を削除します。
- (BOOL)DeleteSpeechModSetting:(SpeechModSettingCacheData*)modSetting
{
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:modSetting.beforeString];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataConfig];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    //});
    }];
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}

/// 読み上げ時の「間」の設定を targetText指定 で読み出します(内部版)
- (SpeechWaitConfig*)GetSpeechWaitSettingWithTargetTextThreadUnsafe:(NSString*)targetText
{
    NSArray* fetchResults = [m_CoreDataObjectHolder SearchEntity:@"SpeechWaitConfig" predicate:[NSPredicate predicateWithFormat:@"targetText == %@", targetText]];
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed.");
        return nil;
    }
    if([fetchResults count] == 0)
    {
        // 何もなかった。
        return nil;
    }
    if([fetchResults count] != 1)
    {
        NSLog(@"duplicate SpeechWaitConfig.targetText!!! %@", targetText);
        return nil;
    }
    return fetchResults[0];
}

/// 読み上げ時の「間」の設定を追加します。(内部版)
- (SpeechWaitConfig*) CreateNewSpeechWaitConfigThreadUnsafe:(SpeechWaitConfigCacheData*)data
{
    SpeechWaitConfig* config = [m_CoreDataObjectHolder CreateNewEntity:@"SpeechWaitConfig"];
    [data AssignToCoreData:config];
    [m_CoreDataObjectHolder save];
    return config;
}

/// 読み上げ時の「間」の設定を全て読み出します。
- (NSArray*)GetAllSpeechWaitConfig
{
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"SpeechWaitConfig" sortAttributeName:@"targetText" ascending:YES];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeechWaitConfigCacheData alloc] initWithCoreData:results[i]];
        }
    //});
    }];
    return fetchResults;
}

/// 読み上げ時の「間」の設定を追加します。
/// 既に同じ key (targetText) のものがあれば上書きになります。
- (BOOL)AddSpeechWaitSetting:(SpeechWaitConfigCacheData*)waitConfigCacheData
{
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechWaitConfig* coreDataConfig = [self GetSpeechWaitSettingWithTargetTextThreadUnsafe:waitConfigCacheData.targetText];
        if (coreDataConfig == nil) {
            [self CreateNewSpeechWaitConfigThreadUnsafe:waitConfigCacheData];
            result = true;
        }else{
            // float で == の比較がどれだけ意味があるのかわからんけれど、多分 0.0f には効くんじゃないかなぁ……
            if (coreDataConfig.delayTimeInSec != waitConfigCacheData.delayTimeInSec) {
                coreDataConfig.delayTimeInSec = waitConfigCacheData.delayTimeInSec;
                [m_CoreDataObjectHolder save];
                result = true;
            }
        }
    //});
    }];
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
    
}

/// 読み上げ時の「間」の設定を削除します。
- (BOOL)DeleteSpeechWaitSetting:(NSString*)targetString
{
    __block BOOL result = false;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechWaitConfig* coreDataConfig = [self GetSpeechWaitSettingWithTargetTextThreadUnsafe:targetString];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataConfig];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    //});
    }];
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}


/// CoreData のマイグレーションが必要かどうかを確認します。
- (BOOL)isRequiredCoreDataMigration
{
    return [m_CoreDataObjectHolder isNeedMigration];
}

/// CoreData のマイグレーションを実行します。
- (void)doCoreDataMigration
{
    [m_CoreDataObjectHolder doMigration];
}

/// CoreData のデータファイルが存在するかどうかを取得します
- (BOOL)isAliveCoreDataSaveFile
{
    return [m_CoreDataObjectHolder isAliveSaveDataFile];
}


/// フォントサイズ値を実際のフォントのサイズに変換します。
/// 1 〜 100 までの float で、50 だと 14(default値)、1 だと 1、100 だと200 位になるような曲線でフォントサイズを計算します。
+ (double)ConvertFontSizeValueToFontSize:(float)value
{
    if (value < 1.0f) {
        value = 50.0f;
    }else if(value > 100.0f){
        value = 100.0f;
    }
    double num = pow(1.05, value);
    num += 1.0f;
    return num;
}

/// 指定された文字列を読み上げでアナウンスします。
/// ただし、読み上げを行っていない場合に限ります。
/// 読み上げを行った場合には true を返します。
- (BOOL)AnnounceBySpeech:(NSString*)speechString
{
    return [m_NiftySpeaker AnnounceBySpeech:speechString];
}

/// 最初のページを表示したかどうかのbool値を取得します。
- (BOOL)IsFirstPageShowed
{
    return m_bIsFirstPageShowed;
}

/// 最初のページを表示した事を設定します。
- (void)SetFirstPageShowed
{
    m_bIsFirstPageShowed = true;
}


/// URLスキームで呼び出された時の downloadncode について対応します。
/// 受け取る引数は @"ncode-ncode-ncode..." という文字列です
- (BOOL)ProcessURLScemeDownloadNcode:(NSString*)targetListString
{
    if (targetListString == nil) {
        return false;
    }
    return [m_DownloadQueue AddDownloadQueueForNcodeList:targetListString];
}

/// URLスキームで呼び出された時の反応をします。
/// 反応する URL は、
/// novelspeaker://downloadncode/ncode-ncode-ncode...
/// です。
- (BOOL)ProcessURLSceme:(NSURL*)url
{
    if (url == nil) {
        return false;
    }
    NSString* scheme = [url scheme];
    if (![scheme isEqualToString:@"novelspeaker"]
        && ![scheme isEqualToString:@"limuraproducts.novelspeaker"]) {
        return false;
    }
    NSString* controller = [url host];
    if ([controller isEqualToString:@"downloadncode"]) {
        NSString* ncodeListString = [url lastPathComponent];
        return [self ProcessURLScemeDownloadNcode:ncodeListString];
    }
    return false;
}

// log用
- (NSString*)GetLogString
{
    NSMutableString* string = [[NSMutableString alloc] init];
    for (NSString* str in m_LogStringArray) {
        [string appendFormat:@"%@\r\n", str];
    }
    return string;
}
- (void)AddLogString:(NSString*)string
{
    NSDate* date = [NSDate date];
    NSDateFormatter* formatter = [NSDateFormatter new];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString* logString = [[NSString alloc] initWithFormat:@"%@ %@", [formatter stringFromDate:date], string];
    [m_LogStringArray addObject:logString];
    NSLog(@"%@", logString);
    while ([m_LogStringArray count] > 1024) {
        [m_LogStringArray removeObjectAtIndex:0];
    }
}

#define USER_DEFAULTS_PREVIOUS_TIME_VERSION @"PreviousTimeVersion"
#define USER_DEFAULTS_PREVIOUS_TIME_BUILD   @"PreviousTimeBuild"

/// 前回実行時とくらべてビルド番号が変わっているか否かを取得します
- (BOOL)IsVersionUped
{
    // NSUserDefaults を使います
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSString* version = [userDefaults stringForKey:USER_DEFAULTS_PREVIOUS_TIME_VERSION];
    NSString* build = [userDefaults stringForKey:USER_DEFAULTS_PREVIOUS_TIME_BUILD];
    NSString* versionBuild = @"unknown";
    if (version != nil && build != nil) {
        versionBuild = [[NSString alloc] initWithFormat:@"%@-%@", version, build];
    }
    NSDictionary* infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString* currentVersionBuild = [[NSString alloc]
                                     initWithFormat:@"%@-%@"
                                     , [infoDictionary objectForKey:@"CFBundleShortVersionString"]
                                     , [infoDictionary objectForKey:@"CFBundleVersion"]
                                     ];
    if ([versionBuild isEqualToString:currentVersionBuild]) {
        return NO;
    }
    return YES;
}

/// 今回起動した時のバージョン番号を保存します。
- (void)UpdateCurrentVersionSaveData
{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary* infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString* version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
    NSString* build = [infoDictionary objectForKey:@"CFBundleVersion"];
    [userDefaults setObject:version forKey:USER_DEFAULTS_PREVIOUS_TIME_VERSION];
    [userDefaults setObject:build forKey:USER_DEFAULTS_PREVIOUS_TIME_BUILD];
    [userDefaults synchronize];
}

/// 新しくユーザ定義の本を追加します。ncode に "_n" で始まるユーザ定義用の code が使われ、
/// それ以外の項目は未設定のものが生成されます。
/// 生成に失敗すると nil を返します。
/// 生成しただけでまだDBには登録されていないので、内容を更新した上で UpdateNarouContent で登録してください。
- (NarouContentCacheData*)CreateNewUserBook
{
    NSString* tmpNcode = nil;
    NarouContentCacheData* content = nil;
    int n = arc4random_uniform(0x7fffffff);
    for (int i = 0; i < 1000; i++) {
        tmpNcode = [[NSString alloc] initWithFormat:@"_u%08x", n + i];
        content = [self SearchNarouContentFromNcode:tmpNcode];
        if (content == nil) {
            break;
        }
    }
    if (tmpNcode == nil || content != nil) {
        return nil;
    }
    content = [NarouContentCacheData new];
    content.title = NSLocalizedString(@"GlobalDataSingleton_NewUserBookTitle", @"新規ユーザ小説");
    content.ncode = tmpNcode;
    content.userid = @"";
    content.writer = @"";
    content.story = @"";
    content.genre = [[NSNumber alloc] initWithInt:0];
    content.keyword = @"";
    content.general_all_no = [[NSNumber alloc] initWithInt:0];
    content.end = [[NSNumber alloc] initWithBool:false];
    content.global_point = [[NSNumber alloc] initWithInt:0];
    content.fav_novel_cnt = [[NSNumber alloc] initWithInt:0];
    content.review_cnt = [[NSNumber alloc] initWithInt:0];
    content.all_point = [[NSNumber alloc] initWithInt:0];
    content.all_hyoka_cnt = [[NSNumber alloc] initWithInt:0];
    content.sasie_cnt = [[NSNumber alloc] initWithInt:0];
    content.novelupdated_at = [NSDate date];
    content.reading_chapter = [[NSNumber alloc] initWithInt:1];
    content.is_new_flug = [[NSNumber alloc] initWithBool:false];
    
    content.currentReadingStory = nil;

    return content;
}
@end
