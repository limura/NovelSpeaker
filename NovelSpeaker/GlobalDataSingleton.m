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
    m_CoreDataAccessQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.coredataaccess", NULL);

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
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:ncode];
        if (coreDataContent != nil) {
            result = [[NarouContentCacheData alloc] initWithCoreData:coreDataContent];
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        if (coreDataContent == nil) {
            coreDataContent = [self CreateNewNarouContentThreadUnsafe];
            isNeedContentListChangedAnnounce = true;
        }else if(coreDataContent.novelupdated_at != content.novelupdated_at){
            isNeedContentListChangedAnnounce = true;
        }
        result = [content AssignToCoreData:coreDataContent];
        [m_CoreDataObjectHolder save];
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        result = [m_CoreDataObjectHolder CountEntity:@"NarouContent"];
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
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"NarouContent" sortAttributeName:@"novelupdated_at" ascending:NO];
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
        return NSLocalizedString(@"GlobalDataSingleton_CanNotGetValidNCODE", @"有効な NCODE を取得できませんでした。");
    }
    NSString* targetNcode = content.ncode;
    __block NarouContentCacheData* targetContentCacheData = [self SearchNarouContentFromNcode:targetNcode];
    if (targetContentCacheData == nil) {
        // 登録がないようなのでとりあえず NarouContent を登録します。
        __block BOOL isNarouContentCreated = false;
        dispatch_sync(m_CoreDataAccessQueue, ^{
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
        });
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
        result = false;
    }else{
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:parentContent.ncode chapter_no:chapter_number];
        if (coreDataStory == nil) {
            coreDataStory = [self CreateNewStoryThreadUnsafe:parentCoreDataContent content:content chapter_number: chapter_number];
        }
        coreDataStory.content = content;
        coreDataStory.parentContent = parentCoreDataContent;
        coreDataStory.chapter_number = [[NSNumber alloc] initWithInt:chapter_number];
        [m_CoreDataObjectHolder save];
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* coreDataContent = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:content.ncode];
        if (coreDataContent != nil) {
            [m_CoreDataObjectHolder DeleteEntity:coreDataContent];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        Story* coreDataStory = [self SearchCoreDataStoryThreadUnsafe:story.ncode chapter_no:[story.chapter_number intValue]];
        if (coreDataStory == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataStory];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    });
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
        result = [m_CoreDataObjectHolder CountEntity:@"Story" predicate:[NSPredicate predicateWithFormat:@"ncode == %@", content.ncode]];
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
    NSUInteger location = [story.readLocation integerValue];
    if (location == [story.content length] && [story.content length] > 0) {
        location = [story.content length] - 1;
    }
    [self AddLogString:[[NSString alloc] initWithFormat:@"読み上げ位置を保存します。(%@) 章: %d 位置: %ld/%ld", content.title, [story.chapter_number intValue], (long)location, (unsigned long)[story.content length]]]; // NSLog

    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
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
            //NSLog(@"chapter: %d is alive", target_chapter_number);
            result = [[StoryCacheData alloc] initWithCoreData:nextCoreDataStory];
        }else{
            NSLog(@"chapter: %d is NOT alive", target_chapter_number);
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

/// 標準の読み替え辞書を上書き追加します。
- (void)InsertDefaultSpeechModConfig
{
        NSArray* dataArray = [[NSArray alloc] initWithObjects:
                              @"異世界", @"イセカイ"
                              , @"術者", @"ジュツシャ"
                              , @"術師", @"ジュツシ"
                              , @"術式", @"ジュツシキ"
                              , @"美味い", @"うまい"
                              , @"不味い", @"まずい"
                              , @"俺達", @"おれたち"
                              //, @"俺たち", @"おれたち"
                              , @"照ら", @"てら"
                              , @"身体", @"からだ"
                              , @"真っ暗", @"まっくら"
                              , @"真っ二つ", @"まっぷたつ"
                              , @"小柄", @"こがら"
                              , @"召喚獣", @"ショウカンジュウ"
                              , @"召喚術", @"ショウカンジュツ"
                              , @"お米", @"おこめ"
                              , @"三々五々", @"さんさんごご"
                              , @"漏ら", @"もら"
                              , @"魔人", @"まじん"
                              , @"魔導", @"まどう"
                              , @"魔石", @"ませき"
                              , @"魔獣", @"まじゅう"
                              , @"異次元", @"いじげん"
                              , @"異能", @"イノウ"
                              , @"異界", @"イカイ"
                              , @"異種族", @"いしゅぞく"
                              , @"異獣", @"いじゅう"
                              , @"爆炎", @"ばくえん"
                              , @"大賢者", @"だいけんじゃ"
                              , @"分身", @"ぶんしん"
                              , @"シュミレー", @"シミュレー"
                              , @"願わくば", @"ねがわくば"
                              , @"静寂", @"せいじゃく"
                              , @"霊子", @"れいし"
                              , @"霊体", @"れいたい"
                              , @"身体能力", @"しんたい能力"
                              , @"荷馬車", @"ニバシャ"
                              , @"脳筋", @"ノウキン"
                              , @"聖騎士", @"セイキシ"
                              , @"真っ暗", @"まっくら"
                              , @"気弾", @"キダン"
                              , @"殺人鬼", @"サツジンキ"
                              , @"極悪人", @"ゴクアクニン"
                              , @"支配下", @"シハイカ"
                              , @"念話", @"ネンワ"
                              , @"姫君", @"ヒメギミ"
                              , @"大泣き", @"オオナキ"
                              , @"大慌て", @"おおあわて"
                              , @"可笑し", @"おかし"
                              , @"初見", @"しょけん"
                              , @"の宴", @"のうたげ"
                              , @"いつの間に", @"いつのまに"
                              , @"幻獣", @"ゲンジュウ"
                              , @"神獣", @"シンジュウ"
                              , @"妖艶", @"ようえん"
                              , @"妖獣", @"ヨウジュウ"
                              , @"妖人", @"ようじん"
                              , @"空賊", @"クウゾク"
                              , @"厨二", @"チュウニ"
                              , @"剣聖", @"ケンセイ"
                              , @"兎に角", @"とにかく"
                              , @"姉ぇ", @"ネエ"
                              , @"行ってらっしゃい", @"いってらっしゃい"
                              , @"行ってきます", @"いってきます"
                              , @"漢探知", @"男探知"
                              , @"最上階", @"さいじょうかい"
                              , @"悪趣味", @"あくしゅみ"
                              , @"忌み子", @"イミコ"
                              , @"引きこもり", @"ひきこもり"
                              , @"巨乳", @"きょにゅう"
                              , @"貧乳", @"ひんにゅう"
                              , @"微乳", @"びにゅう"
                              , @"美乳", @"びにゅう"
                              , @"千切れ", @"ちぎれ"
                              , @"力場", @"りきば"
                              , @"兎に角", @"とにかく"
                              , @"体当たり", @"たいあたり"
                              , @"上方修正", @"じょうほう修正"
                              , @"お兄様", @"おにいさま"
                              , @"お兄さま", @"おにいさま"
                              , @"お付き", @"おつき"
                              , @"VRMMORPG", @"VR MMORPG"
                              , @"薬室", @"やくしつ"
                              , @"薬師", @"くすし"
                              , @"海兵隊", @"かいへいたい"
                              , @"擲弾", @"てきだん"
                              , @"弾倉", @"だんそう"
                              , @"対戦車", @"たいせんしゃ"
                              , @"ボクっ娘", @"ボクっ子"
                              , @"ドジっ娘", @"ドジっ子"
                              , @"獣人", @"じゅうじん"
                              , @"祖父ちゃん", @"じいちゃん"
                              , @"艶かし", @"なまめかし"
                              , @"淹れ", @"いれ"
                              , @"煎れ", @"いれ"
                              , @"奴ら", @"ヤツら"
                              , @"掌打", @"しょうだ"
                              
                              , @"〜", @"ー"
                              
                              , @"上の上", @"ジョウのジョウ"
                              , @"上の中", @"ジョウのチュウ"
                              , @"上の下", @"ジョウのゲ"
                              , @"中の上", @"チュウのジョウ"
                              , @"中の中", @"チュウのチュウ"
                              , @"中の下", @"チュウのゲ"
                              , @"下の上", @"ゲのジョウ"
                              , @"下の中", @"ゲのチュウ"
                              , @"下の下", @"ゲのゲ"
                              
                              , @"α", @"アルファ"
                              , @"Α", @"アルファ"
                              , @"β", @"ベータ"
                              , @"Β", @"ベータ"
                              , @"γ", @"ガンマ"
                              , @"Γ", @"ガンマ"
                              , @"δ", @"デルタ"
                              , @"Δ", @"デルタ"
                              , @"ε", @"イプシロン"
                              , @"Ε", @"イプシロン"
                              , @"ζ", @"ゼータ"
                              , @"Ζ", @"ゼータ"
                              , @"η", @"エータ"
                              , @"θ", @"シータ"
                              , @"Θ", @"シータ"
                              , @"ι", @"イオタ"
                              , @"κ", @"カッパ"
                              , @"λ", @"ラムダ"
                              , @"μ", @"ミュー"
                              , @"ν", @"ニュー"
                              , @"ο", @"オミクロン"
                              , @"π", @"パイ"
                              , @"Π", @"パイ"
                              , @"ρ", @"ロー"
                              , @"σ", @"シグマ"
                              , @"Σ", @"シグマ"
                              , @"τ", @"タウ"
                              , @"υ", @"ユプシロン"
                              , @"φ", @"ファイ"
                              , @"Φ", @"ファイ"
                              , @"χ", @"カイ"
                              , @"ψ", @"プサイ"
                              , @"ω", @"オメガ"
                              , @"Ω", @"オメガ"
                              
                              , @"Ⅰ", @"1"
                              , @"Ⅱ", @"2"
                              , @"Ⅲ", @"3"
                              , @"Ⅳ", @"4"
                              , @"Ⅴ", @"5"
                              , @"Ⅵ", @"6"
                              , @"Ⅶ", @"7"
                              , @"Ⅷ", @"8"
                              , @"Ⅸ", @"9"
                              , @"Ⅹ", @"10"
                              , @"ⅰ", @"1"
                              , @"ⅱ", @"2"
                              , @"ⅲ", @"3"
                              , @"ⅳ", @"4"
                              , @"ⅴ", @"5"
                              , @"ⅵ", @"6"
                              , @"ⅶ", @"7"
                              , @"ⅷ", @"8"
                              , @"ⅸ", @"9"
                              , @"ⅹ", @"10"

                              , @"※", @" "

                              , @"直継", @"ナオツグ"
                              , @"にゃん太", @"ニャンタ"
                              , @"カズ彦", @"カズヒコ"
                              , @"大地人", @"だいちじん"
                              , @"地底人", @"ちていじん"
                              //, @"Plant hwyaden", @"プラント・フロウデン"
                              //, @"Ｐｌａｎｔ　ｈｗｙａｄｅｎ", @"プラント・フロウデン"
                              
                              , nil];
        SpeechModSettingCacheData* speechModSetting = [SpeechModSettingCacheData new];
        for (int i = 0; i < [dataArray count]; i += 2) {
            speechModSetting.beforeString = [dataArray objectAtIndex:i];
            speechModSetting.afterString = [dataArray objectAtIndex:i+1];
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
    if (speechConfigArray != nil) {
        for (SpeakPitchConfigCacheData* pitchConfig in speechConfigArray) {
            SpeechConfig* speechConfig = [SpeechConfig new];
            speechConfig.pitch = [pitchConfig.pitch floatValue];
            speechConfig.rate = [globalState.defaultRate floatValue];
            speechConfig.beforeDelay = 0.0f;
            [m_NiftySpeaker AddBlockStartSeparator:pitchConfig.startText endString:pitchConfig.endText speechConfig:speechConfig];
        }
    }

    // delay については \r\n\r\n 以外を読み込むことにします
    //[m_NiftySpeaker AddDelayBlockSeparator:@"\r\n\r\n" delay:0.02];
    {
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
                        [m_NiftySpeaker AddSpeechModText:speechWaitConfigCache.targetText to:waitString];
                    }else{
                        [m_NiftySpeaker AddDelayBlockSeparator:speechWaitConfigCache.targetText delay:delay];
                    }
                }
            }
        }
    }
    
    NSArray* speechModConfigArray = [self GetAllSpeechModSettings];
    if (speechModConfigArray != nil) {
        for (SpeechModSettingCacheData* speechModSetting in speechModConfigArray) {
            [m_NiftySpeaker AddSpeechModText:speechModSetting.beforeString to:speechModSetting.afterString];
        }
    }
    
    return true;
}

/// ncode の new flag を落とします。
- (void)DropNewFlag:(NSString*)ncode
{
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NarouContent* content = [self SearchCoreDataNarouContentFromNcodeThreadUnsafe:ncode];
        if ([content.is_new_flug boolValue] == true) {
            NSLog(@"new flag drop: %@", ncode);
            content.is_new_flug = [[NSNumber alloc] initWithBool:false];
            [m_CoreDataObjectHolder save];
        
        }
    });
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
    return;
    if (m_MaxSpeechTimeInSecTimer != nil && [m_MaxSpeechTimeInSecTimer isValid]) {
        [m_MaxSpeechTimeInSecTimer invalidate];
    }
    m_MaxSpeechTimeInSecTimer = nil;
}

/// 読み上げ停止のタイマー呼び出しのイベントハンドラ
- (void)MaxSpeechTimeInSecEventHandler:(NSTimer*)timer
{
    [self StopSpeech];
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        [m_CoreDataObjectHolder save];
    });
    //NSLog(@"CoreData saved.");
}

/// 読み上げの会話文の音程設定を全て読み出します。
/// NSArray の中身は SpeakPitchConfigCacheData で、title でsortされた値が取得されます。
- (NSArray*)GetAllSpeakPitchConfig
{
    __block NSMutableArray* fetchResults = nil;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"SpeakPitchConfig" sortAttributeName:@"title" ascending:NO];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeakPitchConfigCacheData alloc] initWithCoreData:results[i]];
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:config.title];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeakPitchConfigThreadUnsafe:config];
        }
        if (coreDataConfig != nil) {
            result = [config AssignToCoreData:coreDataConfig];
            [m_CoreDataObjectHolder save];
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeakPitchConfig* coreDataConfig = [self GetSpeakPitchConfigWithTitleThreadUnsafe:config.title];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataConfig];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"SpeechModSetting" sortAttributeName:@"beforeString" ascending:NO];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeechModSettingCacheData alloc] initWithCoreData:results[i]];
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:modSetting.beforeString];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeechModSettingThreadUnsafe:modSetting];
        }
        if (coreDataConfig != nil) {
            result = [modSetting AssignToCoreData:coreDataConfig];
            [m_CoreDataObjectHolder save];
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:modSetting.beforeString];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataConfig];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    });
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
    dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [m_CoreDataObjectHolder FetchAllEntity:@"SpeechWaitConfig" sortAttributeName:@"targetText" ascending:YES];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeechWaitConfigCacheData alloc] initWithCoreData:results[i]];
        }
    });
    return fetchResults;
}

/// 読み上げ時の「間」の設定を追加します。
/// 既に同じ key (targetText) のものがあれば上書きになります。
- (BOOL)AddSpeechWaitSetting:(SpeechWaitConfigCacheData*)waitConfigCacheData
{
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
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
    });
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
    
}

/// 読み上げ時の「間」の設定を削除します。
- (BOOL)DeleteSpeechWaitSetting:(NSString*)targetString
{
    __block BOOL result = false;
    dispatch_sync(m_CoreDataAccessQueue, ^{
        SpeechWaitConfig* coreDataConfig = [self GetSpeechWaitSettingWithTargetTextThreadUnsafe:targetString];
        if (coreDataConfig == nil) {
            result = false;
        }else{
            [m_CoreDataObjectHolder DeleteEntity:coreDataConfig];
            [m_CoreDataObjectHolder save];
            result = true;
        }
    });
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

@end
