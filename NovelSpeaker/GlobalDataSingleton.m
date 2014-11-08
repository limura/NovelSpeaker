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
            || [state.defaultRate compare:globalState.defaultRate] != NSOrderedSame) {
            m_isNeedReloadSpeakSetting = true;
        }
        state.defaultPitch = globalState.defaultPitch;
        state.defaultRate = globalState.defaultRate;
        state.textSizeValue = globalState.textSizeValue;
        
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
            NSLog(@"chapter: %d is alive", target_chapter_number);
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

- (void)InsertDefaultSpeechModConfig
{
    NSArray* speechModConfigArray = [self GetAllSpeechModSettings];
    if (speechModConfigArray == nil || [speechModConfigArray count] <= 0) {
        // これも無いようなので勝手に作ります。
        NSArray* dataArray = [[NSArray alloc] initWithObjects:
                              @"異世界", @"イセカイ"
                              , @"術者", @"ジュツシャ"
                              , @"術師", @"ジュツシ"
                              , @"術式", @"ジュツシキ"
                              , @"美味い", @"うまい"
                              , @"不味い", @"まずい"
                              , @"俺達", @"おれたち"
                              , @"照ら", @"てら"
                              , @"身体", @"からだ"
                              , @"真っ暗", @"まっくら"
                              , @"小柄", @"こがら"
                              , @"召喚獣", @"ショウカンジュウ"
                              , @"召喚術", @"ショウカンジュツ"
                              , @"お米", @"おこめ"
                              , @"三々五々", @"さんさんごご"
                              , @"漏ら", @"もら"
                              , @"魔人", @"まじん"
                              , @"魔導", @"まどう"
                              , @"異次元", @"いじげん"
                              , @"異能", @"イノウ"
                              , @"異界", @"イカイ"
                              , @"爆炎", @"ばくえん"
                              , @"大賢者", @"だいけんじゃ"
                              , @"分身", @"ぶんしん"
                              , @"シュミレー", @"シミュレー"
                              , @"お米", @"おこめ"
                              , @"願わくば", @"ねがわくば"
                              , @"静寂", @"せいじゃく"
                              , @"霊子", @"れいし"
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
                              , @"俺達", @"おれたち"
                              , @"の宴", @"のうたげ"
                              , @"いつの間に", @"いつのまに"
                              , @"幻獣", @"ゲンジュウ"
                              , @"神獣", @"シンジュウ"
                              , @"妖獣", @"ヨウジュウ"
                              

                              , @"α", @"アルファ"
                              , @"β", @"ベータ"
                              , @"γ", @"ガンマ"
                              , @"ω", @"オメガ"
                              , @"θ", @"シータ"
                              , @"Ω", @"オメガ"

                              , @"※", @" "

                              , @"直継", @"ナオツグ"
                              , @"にゃん太", @"ニャンタ"
                              , @"カズ彦", @"カズヒコ"
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
}

/// 何も設定されていなければ標準のデータを追加します。
- (void)InsertDefaultSetting
{
    [self InsertDefaultSpeakPitchConfig];
    [self InsertDefaultSpeechModConfig];
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

    // delay については設定ページを作っていないので固定値になります。
    [m_NiftySpeaker AddDelayBlockSeparator:@"\r\n\r\n" delay:0.02f];
    
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
    return [m_NiftySpeaker StartSpeech];
}

/// 読み上げを「バックグラウンド再生としては止めずに」読み上げ部分だけ停止します
- (BOOL)StopSpeechWithoutDiactivate
{
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
    //NSLog(@"setActive NO.");
    [session setActive:NO error:nil];
    return [self StopSpeechWithoutDiactivate];
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

#if 0
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
        if (coordinator == nil) {
            NSLog(@"unresolved error. persistentStoreCordinator is null.");
            abort();
        }
        context = [[NSManagedObjectContext alloc] init];
        [context setPersistentStoreCoordinator:coordinator];
        // マージはメモリ側(store側は消される)
        [context setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        
        // 全部のthreadで同じselfを渡してNotificationを登録するならここ。
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(backgroundContextDidSave:)
                                                     name:NSManagedObjectContextDidSaveNotification
                                                   object:context];
        [m_ManagedObjectContextPerThreadDictionary setObject:context forKey:threadID];
        if (m_MainManagedObjectContextHolderThreadID == nil) {
            m_MainManagedObjectContextHolderThreadID = threadID;
            // ここで backgroundContextDidSave をNotificationCenterに登録します。
            // これで多分登録部分は一つに絞れると思うんだけれど、そもそも複数thredで同じselfを使ってる場合はどう対応させるといいんだろ？
            /*
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                    selector:@selector(backgroundContextDidSave:)
                                                        name:NSManagedObjectContextDidSaveNotification
                                                       object:context];
*/
            // TODO:
            //[[NSNotificationCenter defaultCenter] removeObserver:self
            //                                      name:NSManagedObjectContextDidSaveNotification
            //                                      object:managedObjectContext];
            // ということを多分 dealloc あたりでやらないと駄目そうなのだけれどやってない。
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
#endif // #if 0

@end
