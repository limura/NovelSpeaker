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
#import "NarouContentCacheData.h"
#import "StoryCacheData.h"
#import "GlobalStateCacheData.h"
#import "SpeakPitchConfigCacheData.h"
#import "SpeechModSettingCacheData.h"
#import "CoreDataObjectHolder.h"
#import "SpeechWaitConfigCacheData.h"

/// 全体で共有するようなデータを保持させちゃいます！(ﾟ∀ﾟ)
@interface GlobalDataSingleton : NSObject
{
    // main queue
    dispatch_queue_t m_MainQueue;
    // Core Data アクセス用queue
    dispatch_queue_t m_CoreDataAccessQueue;
    // download 用 queue
    //dispatch_queue_t m_DownloadQueue;
    // コンテンツ download 用 queue
    //dispatch_queue_t m_ContentsDownloadQueue;
    // CoreData 関係の object の保持用 object
    CoreDataObjectHolder* m_CoreDataObjectHolder;
    
    // 次回読み上げ時に読み上げ設定を読み直すべきか否か
    BOOL m_isNeedReloadSpeakSetting;
    
    /// thread毎の NSManagedObjectContext
    NSMutableDictionary* m_ManagedObjectContextPerThreadDictionary;
    /// 最初に作られた thread が main の NSManagedObjectContext として登録される
    NSString* m_MainManagedObjectContextHolderThreadID;
    
    /// 読み上げの最大連続再生時間のタイマー
    NSTimer* m_MaxSpeechTimeInSecTimer;
    
    /// 実機用log のarray
    NSMutableArray* m_LogStringArray;
    
    /// 最大連続再生時間を超過したか否か
    BOOL m_isMaxSpeechTimeExceeded;
}

// 実機log用
- (NSString*)GetLogString;
- (void)AddLogString:(NSString*)string;
- (void)ClearLogString;
- (NSArray*)GetLogStringArray;

/// シングルトンを取得します。
+ (GlobalDataSingleton*)GetInstance;

/// 保持しているデータをストレージに保存します。
- (void)saveContext;

/// CoreData で保存している GlobalState object (一つしかないはず) を取得します
// 非公開インタフェースになりました。
//- (GlobalState*) GetGlobalState;
- (GlobalStateCacheData*) GetGlobalState;

#if TARGET_OS_WATCH == 0
/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContentCacheData*) SearchNarouContentFromNcode:(NSString*) ncode;
#endif

/// NarouContent の全てを NSArray で取得します
/// novelupdated_at で sort されて返されます。
- (NSArray*) GetAllNarouContent:(int)sortType;

/// 指定された ncode の小説で、保存されている Story を全て取得します。
- (NSArray*)GeAllStoryForNcode:(NSString*)ncode;

#if TARGET_OS_WATCH == 0
/// 最後に読んでいた小説を取得します
- (NarouContentCacheData*)GetCurrentReadingContent;
#endif

/// 読み上げの会話文の音程設定を全て読み出します。
/// NSArray の中身は SpeakPitchConfigCacheData で、title でsortされた値が取得されます。
- (NSArray*)GetAllSpeakPitchConfig;

/// 読み上げの会話文の音程設定をタイトル指定で読み出します。
- (SpeakPitchConfigCacheData*)GetSpeakPitchConfigWithTitle:(NSString*)title;

/// 読み上げ時の読み替え設定を全て読み出します。
/// NSArray の中身は SpeechModSettingCacheData で、beforeString で sort された値が取得されます。
- (NSArray*)GetAllSpeechModSettings;

/// 読み上げ時の「間」の設定を全て読み出します。
- (NSArray*)GetAllSpeechWaitConfig;

/// CoreData のマイグレーションが必要かどうかを確認します。
- (BOOL)isRequiredCoreDataMigration;

/// CoreData のマイグレーションを実行します。
- (void)doCoreDataMigration;

/// CoreData のデータファイルが存在するかどうかを取得します
- (BOOL)isAliveCoreDataSaveFile;
- (BOOL)isAliveOLDSaveDataFile;
- (BOOL)moveOLDSaveDataFileToNewLocation;

// 設定されている読み上げに使う音声の identifier を取得します
// XXX TODO: 本来なら core data 側でなんとかすべきです
- (NSString*)GetVoiceIdentifier;

/// 本棚のソートタイプを取得します
- (int)GetBookSelfSortType;

/// 新規小説の自動ダウンロード機能のON/OFF状態を取得します
- (BOOL)GetBackgroundNovelFetchEnabled;

/// 小説内部での範囲選択時に出てくるメニューを「読み替え辞書に登録」だけにする(YES)か否(NO)かの設定値を取り出します
- (BOOL)GetMenuItemIsAddSpeechModSettingOnly;

/// ルビがふられた物について、ルビの部分だけを読むか否かの設定を取得します
- (BOOL)GetOverrideRubyIsEnabled;

/// URIを読み上げないようにするか否かを取得します
- (BOOL)GetIsIgnoreURIStringSpeechEnabled;

/// 読み上げられないため、ルビとしては認識しない文字集合を取得します
- (NSString*)GetNotRubyCharactorStringArray;

/// SiteInfo デバッグ用に、毎回 SiteInfo の読み直しを行うか否かの設定を取得します
- (BOOL)GetForceSiteInfoReloadIsEnabled;

/// 読んでいるゲージを表示するか否かを取得します
- (BOOL)IsReadingProgressDisplayEnabled;

/// コントロールセンターの「前の章へ戻る/次の章へ進む」ボタンを「少し戻る/少し進む」ボタンに変更するか否かを取得します
- (BOOL)IsShortSkipEnabled;

/// コントロールセンターの再生時間ゲージを有効にするか否かを取得します
- (BOOL)IsPlaybackDurationEnabled;

/// ページめくり音を発生させるか否かを取得します
- (BOOL)IsPageTurningSoundEnabled;

/// 小説の表示に使用するフォント名を取得します
- (NSString*)GetDisplayFontName;

/// iOS 12 からの読み上げ中の読み上げ位置がずれる問題への対応で、空白文字をαに置き換える設定のEnable/Disableを取得します
- (BOOL)IsEscapeAboutSpeechPositionDisplayBugOniOS12Enabled;

/// 読み上げ時に他のアプリと共存して鳴らせるようにするか否かを取得します
- (BOOL)IsMixWithOthersEnabled;

/// 読み上げ時に他のアプリと共存して鳴らせる場合、他アプリ側の音を小さくするか否かを取得します
- (BOOL)IsDuckOthersEnabled;

/// 利用許諾を読んだか否かを取得します
- (BOOL)IsLicenseReaded;

/// リピート再生の設定を取得します
- (int)GetRepeatSpeechType;

/// 起動時に前回開いていた小説を開くか否かの設定を取得します
- (BOOL)IsOpenRecentNovelInStartTime;

/// ダウンロード時に携帯電話回線を禁じるか否かの設定を取得します
- (BOOL)IsDisallowsCellularAccess;

/// 本棚で小説を削除する時に確認するか否かを取得します
- (BOOL)IsNeedConfirmDeleteBook;

#if TARGET_OS_WATCH == 0
/// 小説を読む部分での表示色設定を読み出します(背景色分)。標準の場合は nil が返ります。
- (UIColor*)GetReadingColorSettingForBackgroundColor;

/// 小説を読む部分での表示色設定を読み出します(文字色分)。標準の場合は nil が返ります。
- (UIColor*)GetReadingColorSettingForForegroundColor;
#endif

/// 一度読んだ事のあるプライバシーポリシーを取得します(読んだことがなければ @"" が取得されます)
- (NSString*)GetReadedPrivacyPolicy;

/// Web取り込み用のBookmarkを取得します
- (NSArray*)GetWebImportBookmarks;

/// CoreData の sqlite ファイルを削除します
- (void)RemoveCoreDataDataFile;

@end
