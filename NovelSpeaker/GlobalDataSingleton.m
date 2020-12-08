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
#import <UserNotifications/UserNotifications.h>
//#import "NSDataZlibExtension.h"
//#import "NSStringExtension.h"
//#import "NiftyUtility.h"
//#import "NSDataDetectEncodingExtension.h"
//#import "UriLoader.h"

#if TARGET_OS_WATCH == 0
#import "NovelSpeaker-Swift.h"
//#import "UIViewControllerExtension.h"
//#import "UIImageExtension.h"
#else
#import "NovelSpeakerWatchApp-Bridging-Header.h"
#endif

#define APP_GROUP_USER_DEFAULTS_SUITE_NAME @"group.com.limuraproducts.novelspeaker"
#define APP_GROUP_USER_DEFAULTS_URL_DOWNLOAD_QUEUE @"URLDownloadQueue"
#define APP_GROUP_USER_DEFAULTS_ADD_TEXT_QUEUE @"AddTextQueue"
#define COOKIE_ENCRYPT_SECRET_KEY @"謎のエラーです。これを確認できた人はご一報ください"
#define USER_DEFAULTS_BACKGROUND_FETCH_FETCHED_NOVEL_COUNT @"BackgroundFetchFetchedNovelCount"
#define NOT_RUBY_STRING_ARRAY @"・、  ？?！!"

@implementation GlobalDataSingleton

// Core Data 用
//@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
//@synthesize managedObjectModel = _managedObjectModel;
//@synthesize managedObjectContext = _managedObjectContext;

static GlobalDataSingleton* _singleton = nil;
#if TARGET_OS_WATCH == 0
static DummySoundLooper* dummySoundLooper = nil;
#endif

- (id)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    m_LogStringArray = [NSMutableArray new];

    //m_bIsFirstPageShowed = false;
    m_isMaxSpeechTimeExceeded = false;
    
    m_MainQueue = dispatch_get_main_queue();
    // CoreDataアクセス用の直列queueを作ります。
    m_CoreDataAccessQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.coredataaccess", DISPATCH_QUEUE_SERIAL);
    
    m_isNeedReloadSpeakSetting = false;
    
    m_ManagedObjectContextPerThreadDictionary = [NSMutableDictionary new];
    m_MainManagedObjectContextHolderThreadID = nil;
    
    m_CoreDataObjectHolder = [[CoreDataObjectHolder alloc] initWithModelName:@"SettingDataModel" fileName:@"SettingDataModel" folderType:DOCUMENTS_FOLDER_TYPE mergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];

    return self;
}
    
- (void)dealloc
{
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
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

- (void)coreDataPerfomBlockAndWait:(void(^)(void))block {
    [m_CoreDataObjectHolder performBlockAndWait:block];
}


#if TARGET_OS_WATCH == 0
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
#endif

#if TARGET_OS_WATCH == 0
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
#else
- (GlobalStateCacheData*)GetGlobalState
{
    return [GlobalStateCacheData new];
}
#endif

#if TARGET_OS_WATCH == 0
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
#endif

#if TARGET_OS_WATCH == 0
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
#endif

+ (NSString*)SortTypeToSortAttributeName:(int)sortType
{
    NSString* sortAttributeName = @"novelupdated_at";
    switch (sortType) {
        case NarouContentSortTypeNovelUpdatedAt:
            sortAttributeName = @"novelupdated_at";
            break;
        case NarouContentSortTypeTitle:
            sortAttributeName = @"title";
            break;
        case NarouContentSortTypeWriter:
            sortAttributeName = @"writer";
            break;
        case NarouContentSortTypeNcode:
            sortAttributeName = @"ncode";
            break;
        default:
            sortAttributeName = @"novelupdated_at";
            break;
    }
    return sortAttributeName;
}

/// NarouContent の全てを NarouContentCacheData の NSArray で取得します
/// novelupdated_at で sort されて返されます。
- (NSArray*) GetAllNarouContent:(int)sortType
{
    __block NSError* err;
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSString* sortAttributeName = [GlobalDataSingleton SortTypeToSortAttributeName:sortType];
        NSArray* results = [self->m_CoreDataObjectHolder FetchAllEntity:@"NarouContent" sortAttributeName:sortAttributeName ascending:NO];
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

/// 指定された ncode の小説で、保存されている Story の chapter_no のみのリストを取得します(公開用method)
- (NSArray*)GetAllStoryForNcodeThreadUnsafe:(NSString*)ncode
{
    NSArray* fetchResults = [m_CoreDataObjectHolder SearchEntity:@"Story" predicate:[NSPredicate predicateWithFormat:@"ncode == %@", ncode] sortAttributeName:@"chapter_number" ascending:YES];
    
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed.");
        return @[];
    }
    NSMutableArray* resultArray = [[NSMutableArray alloc] initWithCapacity:[fetchResults count]];
    int i = 0;
    for (Story* story in fetchResults) {
        StoryCacheData* storyCacheData = [[StoryCacheData alloc] initWithCoreData:story];
        resultArray[i] = storyCacheData;
        i++;
    }
    return resultArray;
}

/// 指定された ncode の小説で、保存されている Story を全て取得します。
- (NSArray*)GeAllStoryForNcode:(NSString*)ncode
{
    __block NSArray* result = 0;
    [self coreDataPerfomBlockAndWait:^{
        result = [self GetAllStoryForNcodeThreadUnsafe:ncode];
    }];
    return result;
}

#if TARGET_OS_WATCH == 0
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
#endif

- (void)saveContext
{
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        [self->m_CoreDataObjectHolder save];
    //});
    }];
    NSLog(@"CoreData saved.");
}

/// 読み上げの会話文の音程設定を全て読み出します。
/// NSArray の中身は SpeakPitchConfigCacheData で、title でsortされた値が取得されます。
- (NSArray*)GetAllSpeakPitchConfig
{
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [self->m_CoreDataObjectHolder FetchAllEntity:@"SpeakPitchConfig" sortAttributeName:@"title" ascending:NO];
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
            [self->m_CoreDataObjectHolder save];
        }
    //});
    }];
    if (result) {
        //NSLog(@"isNeedReloadSpeakSetting = true (pitch)");
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
        NSArray* results = [self->m_CoreDataObjectHolder FetchAllEntity:@"SpeechModSetting" sortAttributeName:@"beforeString" ascending:NO];
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

/// 読み上げ時の読み替え設定をリストで受け取り、上書き更新します。
- (BOOL)UpdateSpeechModSettingMultiple:(NSArray*)modSettingArray {
    if (modSettingArray == nil) {
        return false;
    }
    __block BOOL result = true;
    [self coreDataPerfomBlockAndWait:^{
        for (SpeechModSettingCacheData* modSetting in modSettingArray) {
            SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:[modSetting GetBeforeStringForCoreDataSearch]];
            if (coreDataConfig == nil) {
                coreDataConfig = [self CreateNewSpeechModSettingThreadUnsafe:modSetting];
            }
            if (coreDataConfig != nil) {
                if (![modSetting AssignToCoreData:coreDataConfig]) {
                    result = false;
                }
            }
        }
        [self->m_CoreDataObjectHolder save];
    }];
    if (result) {
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
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
        SpeechModSetting* coreDataConfig = [self GetSpeechModSettingWithBeforeStringThreadUnsafe:[modSetting GetBeforeStringForCoreDataSearch]];
        if (coreDataConfig == nil) {
            coreDataConfig = [self CreateNewSpeechModSettingThreadUnsafe:modSetting];
        }
        if (coreDataConfig != nil) {
            result = [modSetting AssignToCoreData:coreDataConfig];
            [self->m_CoreDataObjectHolder save];
        }
    //});
    }];
    if (result) {
        //NSLog(@"isNeedReloadSpeakSetting = true (speechMod)");
        m_isNeedReloadSpeakSetting = true;
    }
    return result;
}

#if TARGET_OS_WATCH == 0
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
#endif

#if TARGET_OS_WATCH == 0
/// 読み上げ時の「間」の設定を追加します。(内部版)
- (SpeechWaitConfig*) CreateNewSpeechWaitConfigThreadUnsafe:(SpeechWaitConfigCacheData*)data
{
    SpeechWaitConfig* config = [m_CoreDataObjectHolder CreateNewEntity:@"SpeechWaitConfig"];
    [data AssignToCoreData:config];
    [m_CoreDataObjectHolder save];
    return config;
}
#endif

/// 読み上げ時の「間」の設定を全て読み出します。
- (NSArray*)GetAllSpeechWaitConfig
{
    __block NSMutableArray* fetchResults = nil;
    [self coreDataPerfomBlockAndWait:^{
    //dispatch_sync(m_CoreDataAccessQueue, ^{
        NSArray* results = [self->m_CoreDataObjectHolder FetchAllEntity:@"SpeechWaitConfig" sortAttributeName:@"targetText" ascending:YES];
        fetchResults = [[NSMutableArray alloc] initWithCapacity:[results count]];
        for (int i = 0; i < [results count]; i++) {
            fetchResults[i] = [[SpeechWaitConfigCacheData alloc] initWithCoreData:results[i]];
        }
    //});
    }];
    return fetchResults;
}

#if TARGET_OS_WATCH == 0
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
                [self->m_CoreDataObjectHolder save];
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
#endif



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
    //NSLog(@"isAliveCoreDataSaveFile");
    return [m_CoreDataObjectHolder isAliveSaveDataFile];
}

- (BOOL)isAliveOLDSaveDataFile{
    //NSLog(@"isAliveOLDSaveDataFile");
    return [m_CoreDataObjectHolder isAliveOLDSaveDataFile];
}

- (BOOL)moveOLDSaveDataFileToNewLocation{
    //NSLog(@"moveOLDSaveDataFileToNewLocation");
    return [m_CoreDataObjectHolder moveOLDSaveDataFileToNewLocation];
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
    [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
    NSString* logString = [[NSString alloc] initWithFormat:@"%@ %@", [formatter stringFromDate:date], string];
    NSLog(@"%p, %@", m_LogStringArray, logString);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->m_LogStringArray addObject:logString];
        while ([self->m_LogStringArray count] > 1024) {
            [self->m_LogStringArray removeObjectAtIndex:0];
        }
    });
}
- (void)ClearLogString{
    m_LogStringArray = [NSMutableArray new];
}
- (NSArray*)GetLogStringArray{
    return m_LogStringArray;
}

#define USER_DEFAULTS_PREVIOUS_TIME_VERSION @"PreviousTimeVersion"
#define USER_DEFAULTS_PREVIOUS_TIME_BUILD   @"PreviousTimeBuild"
#define USER_DEFAULTS_DEFAULT_VOICE_IDENTIFIER @"DefaultVoiceIdentifier"
#define USER_DEFAULTS_BOOKSELF_SORT_TYPE @"BookSelfSortType"
#define USER_DEFAULTS_BACKGROUND_FETCHED_NOVEL_ID_LIST @"BackgroundFetchedNovelIDList"
#define USER_DEFAULTS_BACKGROUND_NOVEL_FETCH_MODE @"BackgroundNovelFetchMode"
#define USER_DEFAULTS_AUTOPAGERIZE_SITEINFO_CACHE_SAVED_DATE @"AutoPagerizeSiteInfoCacheSavedDate"
#define USER_DEFAULTS_CUSTOM_AUTOPAGERIZE_SITEINFO_CACHE_SAVED_DATE @"CustomAutoPagerizeSiteInfoCacheSavedDate"
#define USER_DEFAULTES_MENU_ITEM_IS_ADD_SPEECH_MOD_SETTINGS_ONLY @"MenuItemIsAddSpeechModSettingOnly"
#define USER_DEFAULTS_OVERRIDE_RUBY_IS_ENABLED @"OverrideRubyIsEnabled"
#define USER_DEFAULTS_NOT_RUBY_CHARACTOR_STRING_ARRAY @"NotRubyCharactorStringArray"
#define USER_DEFAULTS_FORCE_SITEINFO_RELOAD_IS_ENABLED @"ForceSiteInfoReloadIsEnabled"
#define USER_DEFAULTS_READING_PROGRESS_DISPLAY_IS_ENABLED @"ReadingProgressDisplayIsEnabled"
#define USER_DEFAULTS_DISPLAY_FONT_NAME @"DisplayFontName"
#define USER_DEFAULTS_SHORT_SKIP_IS_ENABLED @"ShortSkipIsEnabled"
#define USER_DEFAULTS_PLAYBACK_DURATION_IS_ENABLED @"PlaybackDurationIsEnabled"
#define USER_DEFAULTS_DARK_THEME_IS_ENABLED @"DarkThemeIsEnabled"
#define USER_DEFAULTS_PAGE_TURNING_SOUND_IS_ENABLED @"PageTurningSoundIsEnabled"
#define USER_DEFAULTS_IGNORE_URI_SPEECH_IS_ENABLED @"IgnoreURISpeechIsEnabled"
#define USER_DEFAULTS_WEB_IMPORT_BOOKMARK_ARRAY @"WebImportBookmarkArray"
#define USER_DEFAULTS_IS_LICENSE_FILE_READED @"IsLICENSEFileIsReaded"
#define USER_DEFAULTS_CURRENT_READED_PRIVACY_POLICY @"CurrentReadedPrivacyPolicy"
#define USER_DEFAULTS_REPEAT_SPEECH_TYPE @"RepeatSpeechType"
#define USER_DEFAULTS_IS_ESCAPE_ABOUT_SPEECH_POSITION_DISPLAY_BUG_ON_IOS12 @"IsEscapeAboutSpeechPositionDisplayBugOniOS12_New01"
#define USER_DEFAULTS_IS_DUMMY_SILENT_SOUND_ENABLED @"DummySilentSoundEnabled"
#define USER_DEFAULTS_IS_MIX_WITH_OTHERS_ENABLED @"MixWithOthersEnabled"
#define USER_DEFAULTS_IS_DUCK_OTHERS_ENABLED @"DuckOthersEnabled"
#define USER_DEFAULTS_IS_OPEN_RECENT_NOVEL_IN_START_TIME @"IsOpenRecentNovelInStartTime"
#define USER_DEFAULTS_IS_DISALLOW_CELLULAR_ACCESS @"IsDisallowCellarAccess"
#define USER_DEFAULTS_IS_NEED_CONFIRM_DELETE_BOOK @"IsNeedConfirmDeleteBook"
#define USER_DEFAULTS_DEFAULT_VOLUME @"DefaultVolume"
#define USER_DEFAULTS_READING_COLOR_SETTING_FOR_BACKGROUND_COLOR @"ReadingColorSettingForBackgroundColor"
#define USER_DEFAULTS_READING_COLOR_SETTING_FOR_FOREGROUND_COLOR @"ReadingColorSettingForForegroundColor"

// 設定されている読み上げに使う音声の identifier を取得します
// XXX TODO: 本来なら core data 側でなんとかすべきです
- (NSString*)GetVoiceIdentifier {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSString* voiceIdentifier = [userDefaults stringForKey:USER_DEFAULTS_DEFAULT_VOICE_IDENTIFIER];
    // 未設定であれば怪しく現在利用可能な話者の中から推奨の話者を選択しておきます
    if (voiceIdentifier == nil) {
        NSArray* recomendIdArray = @[
         @"com.apple.ttsbundle.siri_female_ja-JP_premium", // O-ren premium
         @"com.apple.ttsbundle.siri_female_ja-JP_compact", // O-ren
         @"com.apple.ttsbundle.siri_male_ja-JP_compact", // hattori
         @"com.apple.ttsbundle.Otoya-premium", // otoya premium
         ];
        NSArray* voiceList = [AVSpeechSynthesisVoice speechVoices];
        NSMutableArray* voiceArray = [NSMutableArray new];
        for (AVSpeechSynthesisVoice* voice in voiceList) {
            if ([voice.language compare:@"ja-JP"] == NSOrderedSame) {
                [voiceArray addObject:voice];
            }
        }
        if (voiceArray != nil) {
            for (NSString* recomendId in recomendIdArray) {
                for (AVSpeechSynthesisVoice* voice in voiceArray) {
                    if ([voice.identifier compare:recomendId] == NSOrderedSame) {
                        voiceIdentifier = voice.identifier;
                        //[self SetVoiceIdentifier:voiceIdentifier];
                        return voiceIdentifier;
                    }
                }
            }
        }
    }
    return voiceIdentifier;
}

/// 本棚のソートタイプを取得します
- (int)GetBookSelfSortType {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_BOOKSELF_SORT_TYPE: [[NSNumber alloc] initWithInteger: NarouContentSortTypeTitle]}];
    NSInteger sortTypeInteger = [userDefaults integerForKey:USER_DEFAULTS_BOOKSELF_SORT_TYPE];
    NarouContentSortType sortType = sortTypeInteger;
    return sortType;
}

/// 新規小説の自動ダウンロード機能のON/OFF状態を取得します
- (BOOL)GetBackgroundNovelFetchEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_BACKGROUND_NOVEL_FETCH_MODE: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_BACKGROUND_NOVEL_FETCH_MODE];
}

/// 小説内部での範囲選択時に出てくるメニューを「読み替え辞書に登録」だけにする(YES)か否(NO)かの設定値を取り出します
- (BOOL)GetMenuItemIsAddSpeechModSettingOnly {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTES_MENU_ITEM_IS_ADD_SPEECH_MOD_SETTINGS_ONLY: @false}];
    return [userDefaults boolForKey:USER_DEFAULTES_MENU_ITEM_IS_ADD_SPEECH_MOD_SETTINGS_ONLY];
}

/// ことせかい 関連の AppGroup に属する UserDefaults を取得します。
- (NSUserDefaults*)getNovelSpeakerAppGroupUserDefaults
{
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:APP_GROUP_USER_DEFAULTS_SUITE_NAME];
    return defaults;
}

/// ことせかい 関連の AppGroup に属する UserDefaults の key に対して、文字列を格納した NSArray のつもりで text を追加します
- (void)addStringQueueToNovelSpeakerAppGroupUserDefaults:(NSString*)key text:(NSString*)text {
    NSUserDefaults* userDefaults = [self getNovelSpeakerAppGroupUserDefaults];
    NSArray* currentArray = [userDefaults stringArrayForKey:key];
    NSMutableArray* newArray = nil;
    if (currentArray == nil) {
        newArray = [NSMutableArray new];
    }else{
        newArray = [[NSMutableArray alloc] initWithArray:currentArray];
    }
    [newArray addObject:text];
    [userDefaults setObject:newArray forKey:key];
    [userDefaults synchronize];
}

/// ルビがふられた物について、ルビの部分だけを読むか否かの設定を取得します
- (BOOL)GetOverrideRubyIsEnabled {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    return [userDefaults boolForKey:USER_DEFAULTS_OVERRIDE_RUBY_IS_ENABLED];
}

/// 読み上げられないため、ルビとしては認識しない文字集合を取得します
- (NSString*)GetNotRubyCharactorStringArray{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_NOT_RUBY_CHARACTOR_STRING_ARRAY: NOT_RUBY_STRING_ARRAY}];
    return [userDefaults stringForKey:USER_DEFAULTS_NOT_RUBY_CHARACTOR_STRING_ARRAY];
}

/// SiteInfo デバッグ用に、毎回 SiteInfo の読み直しを行うか否かの設定を取得します
- (BOOL)GetForceSiteInfoReloadIsEnabled {
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_FORCE_SITEINFO_RELOAD_IS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_FORCE_SITEINFO_RELOAD_IS_ENABLED];
}

/// 読んでいるゲージを表示するか否かを取得します
- (BOOL)IsReadingProgressDisplayEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_READING_PROGRESS_DISPLAY_IS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_READING_PROGRESS_DISPLAY_IS_ENABLED];
}

/// コントロールセンターの「前の章へ戻る/次の章へ進む」ボタンを「少し戻る/少し進む」ボタンに変更するか否かを取得します
- (BOOL)IsShortSkipEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_SHORT_SKIP_IS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_SHORT_SKIP_IS_ENABLED];
}

/// コントロールセンターの再生時間ゲージを有効にするか否かを取得します
- (BOOL)IsPlaybackDurationEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_PLAYBACK_DURATION_IS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_PLAYBACK_DURATION_IS_ENABLED];
}

/// ページめくり音を発生させるか否かを取得します
- (BOOL)IsPageTurningSoundEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_PAGE_TURNING_SOUND_IS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_PAGE_TURNING_SOUND_IS_ENABLED];
}

/// URIを読み上げないようにするか否かを取得します
- (BOOL)GetIsIgnoreURIStringSpeechEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IGNORE_URI_SPEECH_IS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_IGNORE_URI_SPEECH_IS_ENABLED];
}


/// 小説の表示に使用するフォント名を取得します
- (NSString*)GetDisplayFontName{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_DISPLAY_FONT_NAME: @""}];
    NSString* fontName = [userDefaults stringForKey:USER_DEFAULTS_DISPLAY_FONT_NAME];
    if ([fontName compare:@""] == NSOrderedSame) {
        return nil;
    }
    return fontName;
}
    
    
/// iOS 12 からの読み上げ中の読み上げ位置がずれる問題への対応で、空白文字をαに置き換える設定のEnable/Disableを取得します
- (BOOL)IsEscapeAboutSpeechPositionDisplayBugOniOS12Enabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_ESCAPE_ABOUT_SPEECH_POSITION_DISPLAY_BUG_ON_IOS12: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_ESCAPE_ABOUT_SPEECH_POSITION_DISPLAY_BUG_ON_IOS12];
}

/// 読み上げ時に他のアプリと共存して鳴らせるようにするか否かを取得します
- (BOOL)IsMixWithOthersEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_MIX_WITH_OTHERS_ENABLED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_MIX_WITH_OTHERS_ENABLED];
}

/// 読み上げ時に他のアプリと共存して鳴らせる場合、他アプリ側の音を小さくするか否かを取得します
- (BOOL)IsDuckOthersEnabled{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_DUCK_OTHERS_ENABLED: @true}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_DUCK_OTHERS_ENABLED];
}

/// 利用許諾を読んだか否かを取得します
- (BOOL)IsLicenseReaded{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_LICENSE_FILE_READED: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_LICENSE_FILE_READED];
}

/// リピート再生の設定を取得します
- (int)GetRepeatSpeechType{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_REPEAT_SPEECH_TYPE: [[NSNumber alloc] initWithInt:RepeatSpeechTypeNoRepeat]}];
    NSInteger type = [userDefaults integerForKey:USER_DEFAULTS_REPEAT_SPEECH_TYPE];
    if (type != RepeatSpeechTypeNoRepeat
        && type != RepeatSpeechTypeRewindToFirstStory
        && type != RepeatSpeechTypeRewindToThisStory) {
        type = RepeatSpeechTypeNoRepeat;
    }
    return (int)type;
}

/// 起動時に前回開いていた小説を開くか否かの設定を取得します
- (BOOL)IsOpenRecentNovelInStartTime{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_OPEN_RECENT_NOVEL_IN_START_TIME: @true}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_OPEN_RECENT_NOVEL_IN_START_TIME];
}

/// ダウンロード時に携帯電話回線を禁じるか否かの設定を取得します
- (BOOL)IsDisallowsCellularAccess{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_DISALLOW_CELLULAR_ACCESS: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_DISALLOW_CELLULAR_ACCESS];
}

/// 本棚で小説を削除する時に確認するか否かを取得します
- (BOOL)IsNeedConfirmDeleteBook{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_IS_NEED_CONFIRM_DELETE_BOOK: @false}];
    return [userDefaults boolForKey:USER_DEFAULTS_IS_NEED_CONFIRM_DELETE_BOOK];
}

#if TARGET_OS_WATCH == 0
/// 小説を読む部分での表示色設定を読み出します(背景色分)。標準設定の場合は nil が返ります。
- (UIColor*)GetReadingColorSettingForBackgroundColor{
    // 標準では JSON を入れておかずに JSON からの変換に失敗させます。
    NSString* defaultColorSettingJson = @"ERROR STRING";
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_READING_COLOR_SETTING_FOR_BACKGROUND_COLOR: defaultColorSettingJson}];
    NSString* colorSettingJson = [userDefaults stringForKey:USER_DEFAULTS_READING_COLOR_SETTING_FOR_BACKGROUND_COLOR];
    NSError* error = nil;
    NSDictionary* settingDictionary = [NSJSONSerialization JSONObjectWithData:[colorSettingJson dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (settingDictionary == nil || error != nil) {
        return nil;
    }
    CGFloat red, green, blue, alpha;
    red = green = blue = alpha = -1.0;
    typedef float (^GetColorFunc)(NSDictionary* dic, NSString* name);
    GetColorFunc getColorFunc = ^(NSDictionary* dic, NSString* name) {
        float colorValue = -1.0;
        id colorObj = [dic valueForKey:name];
        if ([colorObj isKindOfClass:[NSNumber class]]) {
            NSNumber* color = colorObj;
            return [color floatValue];
        }
        return colorValue;
    };
    red = getColorFunc(settingDictionary, @"red");
    green = getColorFunc(settingDictionary, @"green");
    blue = getColorFunc(settingDictionary, @"blue");
    alpha = getColorFunc(settingDictionary, @"alpha");
    if (red < 0.0 || green < 0.0 || blue < 0.0 || alpha < 0.0
        || red > 1.0 || green > 1.0 || blue > 1.0 || alpha > 1.0) {
        return nil;
    }
    return [[UIColor alloc] initWithRed:red green:green blue:blue alpha:alpha];
}
/// 小説を読む部分での表示色設定を読み出します(文字色分)。標準設定の場合は nil が返ります。
- (UIColor*)GetReadingColorSettingForForegroundColor{
    // 標準では JSON を入れておかずに JSON からの変換に失敗させます。
    NSString* defaultColorSettingJson = @"ERROR STRING";
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_READING_COLOR_SETTING_FOR_FOREGROUND_COLOR: defaultColorSettingJson}];
    NSString* colorSettingJson = [userDefaults stringForKey:USER_DEFAULTS_READING_COLOR_SETTING_FOR_FOREGROUND_COLOR];
    NSError* error = nil;
    NSDictionary* settingDictionary = [NSJSONSerialization JSONObjectWithData:[colorSettingJson dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
    if (settingDictionary == nil || error != nil) {
        return nil;
    }
    CGFloat red, green, blue, alpha;
    red = green = blue = alpha = -1.0;
    typedef float (^GetColorFunc)(NSDictionary* dic, NSString* name);
    GetColorFunc getColorFunc = ^(NSDictionary* dic, NSString* name) {
        float colorValue = -1.0;
        id colorObj = [dic valueForKey:name];
        if ([colorObj isKindOfClass:[NSNumber class]]) {
            NSNumber* color = colorObj;
            return [color floatValue];
        }
        return colorValue;
    };
    red = getColorFunc(settingDictionary, @"red");
    green = getColorFunc(settingDictionary, @"green");
    blue = getColorFunc(settingDictionary, @"blue");
    alpha = getColorFunc(settingDictionary, @"alpha");
    if (red < 0.0 || green < 0.0 || blue < 0.0 || alpha < 0.0
        || red > 1.0 || green > 1.0 || blue > 1.0 || alpha > 1.0) {
        return nil;
    }
    return [[UIColor alloc] initWithRed:red green:green blue:blue alpha:alpha];
}
#endif // TARGET_OS_WATCH == 0
/// 一度読んだ事のあるプライバシーポリシーを取得します(読んだことがなければ @"" が取得されます)
- (NSString*)GetReadedPrivacyPolicy{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:@{USER_DEFAULTS_CURRENT_READED_PRIVACY_POLICY: @""}];
    return [userDefaults stringForKey:USER_DEFAULTS_CURRENT_READED_PRIVACY_POLICY];
}

/// Web取り込み用のBookmarkを取得します
- (NSArray*)GetWebImportBookmarks{
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    // 怪しく「名前」と「URL」を"\n"で区切って保存します。(´・ω・`)
    [userDefaults registerDefaults:@{USER_DEFAULTS_WEB_IMPORT_BOOKMARK_ARRAY: @[
        //@"Google\nhttps://www.google.co.jp",
        @"小説家になろう\nhttps://syosetu.com/",
        @"青空文庫\nhttps://www.aozora.gr.jp/",
        //@"コンプリート・シャーロック・ホームズ\nhttp://www.221b.jp/", // 1秒おきに見に行かせると 403 になるっぽい？
        @"ハーメルン\nhttps://syosetu.org/",
        @"暁\nhttps://www.akatsuki-novels.com/",
        @"カクヨム\nhttps://kakuyomu.jp/",
        //@"アルファポリス\nhttps://www.alphapolis.co.jp/novel/",
        //@"pixiv/ノベル\nhttps://www.pixiv.net/novel/",
        @"星空文庫\nhttps://slib.net/",
        //@"FC2小説\nhttps://novel.fc2.com/",
        //@"novelist.jp\nhttp://novelist.jp/",
        //@"eエブリスタ\nhttps://estar.jp/",
        //@"魔法のiランドノベル\nhttps://novel.maho.jp/",
        //@"ベリーズ・カフェ\nhttps://www.berrys-cafe.jp/",
        //@"星の砂\nhttp://hoshi-suna.jp/",
        //@"小説カキコ\nhttp://www.kakiko.cc/",
        //@"のべぷろ\nhttp://www.novepro.jp/",
        //@"野いちご\nhttps://www.no-ichigo.jp/",
        //@"小説&まんが投稿屋\nhttp://works.bookstudio.com/",
        //@"シルフェニア\nhttp://www.silufenia.com/main.php",
        //@"ぱろしょ\nhttp://paro.guttari.info/",
        //@"おりおん\nhttp://de-view.net/",
        //@"ドリームライブ\nhttp://www.dreamtribe.jp/",
        //@"短編\nhttp://tanpen.jp/",
        //@"ライトノベル作法研究所\nhttp://www.raitonoveru.jp/",
        ]}];
    // 2018/10/20 アルファポリスがJavaScriptによる遅延読み込みになったため、
    // 標準ブックマークとして保存されいていたアルファポリスについては非対応という表示を追加することにした
    NSArray* bookmarkArray = [userDefaults arrayForKey:USER_DEFAULTS_WEB_IMPORT_BOOKMARK_ARRAY];
    NSMutableArray* modifiedArray = [NSMutableArray new];
    for (NSString* str in bookmarkArray) {
        if ([str compare:@"アルファポリス\nhttps://www.alphapolis.co.jp/novel/"] == NSOrderedSame) {
            [modifiedArray addObject:@"アルファポリス(Web取込 非対応サイトになりました。詳細はサポートサイト下部にありますQ&Aを御覧ください)\nhttps://www.alphapolis.co.jp/novel/"];
        }else{
            [modifiedArray addObject:str];
        }
    }
    return modifiedArray;
}

/// CoreData の sqlite ファイルを削除します
- (void)RemoveCoreDataDataFile {
    [m_CoreDataObjectHolder removeCoreDataDataFile];
}

@end
