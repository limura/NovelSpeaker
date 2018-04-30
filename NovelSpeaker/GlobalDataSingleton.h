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
#import "NarouDownloadQueue.h"
#import "GlobalStateCacheData.h"
#import "NiftySpeaker.h"
#import "SpeakPitchConfigCacheData.h"
#import "SpeechModSettingCacheData.h"
#import "CoreDataObjectHolder.h"
#import "SpeechWaitConfigCacheData.h"

typedef NS_ENUM(NSUInteger,NarouContentSortType) {
    NarouContentSortType_NovelUpdatedAt = 0,
    NarouContentSortType_Title,
    NarouContentSortType_Writer,
    NarouContentSortType_Ncode,
};

/// 全体で共有するようなデータを保持させちゃいます！(ﾟ∀ﾟ)
@interface GlobalDataSingleton : NSObject
{
    // 最初の表示をしたかどうかのbool値
    bool m_bIsFirstPageShowed;
    
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
    
    // ダウンロードキュー
    NarouDownloadQueue* m_DownloadQueue;
    // コンテンツダウンロードを終了するべきかどうかのbool値
    //bool m_isNeedQuit;
    
    // 読み上げを管理します。
    NiftySpeaker* m_NiftySpeaker;
    
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
}

// 実機log用
- (NSString*)GetLogString;
- (void)AddLogString:(NSString*)string;
- (void)ClearLogString;
- (NSArray*)GetLogStringArray;

/// シングルトンを取得します。
+ (GlobalDataSingleton*)GetInstance;

// Core Data 用
//@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
//@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
//@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;

/// Core Data用にディレクトリを(なければ)作ります。
//- (BOOL)CreateCoreDataDirectory;

/// 保持しているデータをストレージに保存します。
- (void)saveContext;

/// CoreDataが保存する時に使うディレクトリを取得します。
//- (NSURL *)applicationDocumentsDirectory;

/// CoreData で保存している GlobalState object (一つしかないはず) を取得します
// 非公開インタフェースになりました。
//- (GlobalState*) GetGlobalState;
- (GlobalStateCacheData*) GetGlobalState;

/// GlobalState を更新します。
- (BOOL)UpdateGlobalState:(GlobalStateCacheData*)globalState;

/// CoreData で保存している NarouContent のうち、Ncode で検索した結果
/// 得られた NovelContent を取得します。
/// 登録がなければ nil を返します
- (NarouContentCacheData*) SearchNarouContentFromNcode:(NSString*) ncode;

/// 指定されたNarouContentの情報を更新します。
/// CoreData側に登録されていなければ新規に作成し、
/// 既に登録済みであれば情報を更新します。
- (BOOL)UpdateNarouContent:(NarouContentCacheData*)content;

/// 新しい NarouContent を生成して返します。
// 非公開インタフェースになりました。
//- (NarouContent*) CreateNewNarouContent;

/// 保存されている NarouContent の数を取得します。
- (NSUInteger) GetNarouContentCount;

/// NarouContent の全てを NSArray で取得します
/// novelupdated_at で sort されて返されます。
- (NSArray*) GetAllNarouContent:(NarouContentSortType)sortType;

/// 指定された ncode に登録されている全ての Story の内容(文章)を配列にして取得します
- (NSArray*)GetAllStoryTextForNcode:(NSString*)ncode;

/// ダウンロードqueueに追加しようとします
/// 追加した場合は nil を返します。
/// 追加できなかった場合はエラーメッセージを返します。
- (NSString*) AddDownloadQueueForNarou:(NarouContentCacheData*) content;

/// Ncode の指定でダウンロードqueueに追加します。
/// 追加できなかった場合はエラーメッセージを返します。
- (BOOL) AddDownloadQueueForNarouNcode:(NSString*)ncode;

/// 現在ダウンロード中のコンテンツ情報を取得します。
- (NarouContentCacheData*)GetCurrentDownloadingInfo;

/// 現在ダウンロード待ち中のNarouContentCacheDataのリストを取得します。
- (NSArray*) GetCurrentDownloadWaitingInfo;

/// CoreData で保存している Story のうち、Ncode と chapter_number で検索した結果
/// 得られた Story を取得します。
/// 登録がなければ nil を返します
- (StoryCacheData*) SearchStory:(NSString*)ncode chapter_no:(int)chapter_number;

/// Story を新しく生成します。必要な情報をすべて伝える必要があります。
/// private method になりました。
//- (Story*) CreateNewStory:(NarouContent*)parentContent content:(NSString*)content chapter_number:(int)chapter_number;

/// 指定されたStoryの情報を更新します。(dispatch_sync で囲っていない版)
/// CoreData側に登録されていなければ新規に作成し、
/// 既に登録済みであれば情報を更新します。
- (BOOL)UpdateStoryThreadUnsafe:(NSString*)content chapter_number:(int)chapter_number parentContent:(NarouContentCacheData *)parentContent;

/// 指定されたStoryの情報を更新します。
/// CoreData側に登録されていなければ新規に作成し、
/// 既に登録済みであれば情報を更新します。
- (BOOL)UpdateStory:(NSString*)content chapter_number:(int)chapter_number parentContent:(NarouContentCacheData*)parentContent;

/// 小説を一つ削除します
- (BOOL)DeleteContent:(NarouContentCacheData*)content;

/// 章を一つ削除します
- (BOOL)DeleteStory:(StoryCacheData*)story;

/// 対象の小説でCoreDataに保存されている章の数を取得します。
- (NSUInteger)CountContentChapter:(NarouContentCacheData*)content;

/// ダウンロードイベントハンドラを設定します。
- (BOOL)AddDownloadEventHandler:(id<NarouDownloadQueueDelegate>)delegate;

/// ダウンロードイベントハンドラから削除します。
- (BOOL)DeleteDownloadEventHandler:(id<NarouDownloadQueueDelegate>)delegate;

/// ダウンロード周りのイベントハンドラ用のdelegateに追加します。(ncode で絞り込む版)
- (BOOL)AddDownloadEventHandlerWithNcode:(NSString*)string handler:(id<NarouDownloadQueueDelegate>)handler;

/// ダウンロード周りのイベントハンドラ用のdelegateから削除します。(ncode で絞り込む版)
- (BOOL)DeleteDownloadEventHandlerWithNcode:(NSString*)string;


/// 現在ダウンロード待ち中のものから、ncode を持つものをリストから外します。
- (BOOL)DeleteDownloadQueue:(NSString*)ncode;

/// 最後に読んでいた小説を取得します
- (NarouContentCacheData*)GetCurrentReadingContent;

/// 小説で読んでいた章を取得します
- (StoryCacheData*)GetReadingChapter:(NarouContentCacheData*)content;

/// 読み込み中の場所を指定された小説と章で更新します。
- (BOOL)UpdateReadingPoint:(NarouContentCacheData*)content story:(StoryCacheData*)story;

/// 次の章を読み出します。
/// 次の章がなければ nil を返します。
- (StoryCacheData*)GetNextChapter:(StoryCacheData*)story;

/// 前の章を読み出します。
/// 前の章がなければ nil を返します。
- (StoryCacheData*)GetPreviousChapter:(StoryCacheData*)story;

/// 何も設定されていなければ標準のデータを追加します。
- (void)InsertDefaultSetting;

/// 読み上げ設定を読み直します。
- (BOOL)ReloadSpeechSetting;

/// story の文章を表示用の文字列に変換します。
- (NSString*)ConvertStoryContentToDisplayText:(StoryCacheData*)story;

/// 読み上げる章を設定します。
- (BOOL)SetSpeechStory:(StoryCacheData*)story;

/// 読み上げ位置を設定します。
- (BOOL)SetSpeechRange:(NSRange)range;

/// 現在の読み上げ位置を取り出します
- (NSRange)GetCurrentReadingPoint;

/// 読み上げを開始します。
- (BOOL)StartSpeech;

/// 読み上げを「バックグラウンド再生としては止めずに」読み上げ部分だけ停止します
- (BOOL)StopSpeechWithoutDiactivate;

/// 読み上げを停止します。
- (BOOL)StopSpeech;

/// 読み上げ時のイベントハンドラを追加します。
- (BOOL)AddSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate;

/// 読み上げ時のイベントハンドラを削除します。
- (void)DeleteSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate;

/// 読み上げ中か否かを取得します
- (BOOL)isSpeaking;

/// 読み上げの会話文の音程設定を全て読み出します。
/// NSArray の中身は SpeakPitchConfigCacheData で、title でsortされた値が取得されます。
- (NSArray*)GetAllSpeakPitchConfig;

/// 読み上げの会話文の音程設定をタイトル指定で読み出します。
- (SpeakPitchConfigCacheData*)GetSpeakPitchConfigWithTitle:(NSString*)title;

/// 読み上げの会話文の音程設定を更新します。
- (BOOL)UpdateSpeakPitchConfig:(SpeakPitchConfigCacheData*)config;

/// 読み上げの会話文の音声設定を削除します。
- (BOOL)DeleteSpeakPitchConfig:(SpeakPitchConfigCacheData*)config;

/// 読み上げ時の読み替え設定を全て読み出します。
/// NSArray の中身は SpeechModSettingCacheData で、beforeString で sort された値が取得されます。
- (NSArray*)GetAllSpeechModSettings;

/// 読み上げ時の読み替え設定を beforeString指定 で読み出します
- (SpeechModSettingCacheData*)GetSpeechModSettingWithBeforeString:(NSString*)beforeString;

/// 読み上げ時の読み替え設定をリストで受け取り、上書き更新します。
- (BOOL)UpdateSpeechModSettingMultiple:(NSArray*)modSettingArray;

/// 読み上げ時の読み替え設定を更新します。無ければ新しく登録されます。
- (BOOL)UpdateSpeechModSetting:(SpeechModSettingCacheData*)modSetting;

/// 読み上げ時の読み替え設定を削除します。
- (BOOL)DeleteSpeechModSetting:(SpeechModSettingCacheData*)modSetting;

/// 読み上げ時の「間」の設定を全て読み出します。
- (NSArray*)GetAllSpeechWaitConfig;

/// 読み上げ時の「間」の設定を追加します。
/// 既に同じ key (targetText) のものがあれば上書きになります。
- (BOOL)AddSpeechWaitSetting:(SpeechWaitConfigCacheData*)waitConfigCacheData;

/// 読み上げ時の「間」の設定を削除します。
- (BOOL)DeleteSpeechWaitSetting:(NSString*)targetString;

/// CoreData のマイグレーションが必要かどうかを確認します。
- (BOOL)isRequiredCoreDataMigration;

/// CoreData のマイグレーションを実行します。
- (void)doCoreDataMigration;

/// CoreData のデータファイルが存在するかどうかを取得します
- (BOOL)isAliveCoreDataSaveFile;

/// フォントサイズ値を実際のフォントのサイズに変換します。
+ (double)ConvertFontSizeValueToFontSize:(float)fontSizeValue;

/// 指定された文字列を読み上げでアナウンスします。
/// ただし、読み上げを行っていない場合に限ります。
/// 読み上げを行った場合には true を返します。
- (BOOL)AnnounceBySpeech:(NSString*)speechString;

/// 最初のページを表示したかどうかのbool値を取得します。
- (BOOL)IsFirstPageShowed;

/// 最初のページを表示した事を設定します。
- (void)SetFirstPageShowed;

/// URLで呼び出された時の反応をします。
- (BOOL)ProcessURL:(NSURL*)url;

/// URLスキームで呼び出された時の反応をします。
- (BOOL)ProcessURLSceme:(NSURL*)url;

/// カスタムUTI(ファイル拡張子？)で呼び出された時の反応をします。
- (BOOL)ProcessCustomFileUTI:(NSURL*)url;

/// 標準の読み替え辞書を上書き追加します。
- (void)InsertDefaultSpeechModConfig;

/// NiftySpeaker に現在の標準設定を登録します
- (void)ApplyDefaultSpeechconfig:(NiftySpeaker*)niftySpeaker;
/// NiftySpeakerに現在の読み上げの声質の設定を登録します
- (void)ApplySpeakPitchConfig:(NiftySpeaker*) niftySpeaker;
/// NiftySpeakerに現在の読みの「間」の設定を登録します
- (void)ApplySpeechWaitConfig:(NiftySpeaker*) niftySpeaker;
/// NiftySpeakerに現在の読み替え設定を登録します
- (void)ApplySpeechModConfig:(NiftySpeaker*)niftySpeaker;

/// 前回実行時とくらべてビルド番号が変わっているか否かを取得します
- (BOOL)IsVersionUped;

/// 今回起動した時のバージョン番号を保存します。
- (void)UpdateCurrentVersionSaveData;

/// 新しくユーザ定義の本を追加します。必須項目以外は未設定のものが生成されます。
- (NarouContentCacheData*)CreateNewUserBook;

/// 標準の読み上げ辞書のリストを取得します
- (NSDictionary*)GetDefaultSpeechModConfig;

/// 全てのコンテンツを再度ダウンロードしようとします。
- (void)ReDownladAllContents;

/// 現在の Download queue を全て削除します
- (void)ClearDownloadQueue;

/// 現在の新規ダウンロード数をクリアします
- (void)ClearNewDownloadCount;

/// 現在の新規ダウンロード数を取得します
- (int)GetNewDownloadCount;

// Background fetch イベントを処理します
- (void)HandleBackgroundFetch:(UIApplication *)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;

// 設定されていpod 'SZTextView'る読み上げに使う音声の identifier を取得します
// XXX TODO: 本来なら core data 側でなんとかすべきです
- (NSString*)GetVoiceIdentifier;

// 読み上げに使う音声の identifier を保存します。
// XXX TODO: 本来なら core data 側でなんとかすべきです
- (void)SetVoiceIdentifier:(NSString*)identifier;

- (void)DeleteVoiceIdentifier;

/// 本棚のソートタイプを取得します
- (NarouContentSortType)GetBookSelfSortType;
/// 本棚のソートタイプを保存します
- (void)SetBookSelfSortType:(NarouContentSortType)sortType;

/// 新規小説の自動ダウンロード機能のON/OFF状態を取得します
- (BOOL)GetBackgroundNovelFetchEnabled;

/// 新規小説の自動ダウンロード機能のON/OFFを切り替えます
- (void)UpdateBackgroundNovelFetchMode:(BOOL)isEnabled;

/// 内部に保存してある AutoPagerize の SiteInfo を取り出します
- (NSData*)GetCachedAutoPagerizeSiteInfoData;
/// AutoPagerize の SiteInfo を内部に保存します
- (void)SaveAutoPagerizeSiteInfoData:(NSData*)data;

/// 内部に保存してある AutoPagerize の カスタムSiteInfo を取り出します
- (NSData*)GetCachedCustomAutoPagerizeSiteInfoData;

/// ダウンロードqueueに追加しようとします
/// 追加した場合は nil を返します。
/// 追加できなかった場合はエラーメッセージを返します。
- (NSString*) AddDownloadQueueForURL:(NSString*)urlString cookieParameter:(NSString*)cookieParameter;

/// 始めの章の内容やタイトルが確定しているURLについて、新規登録をしてダウンロードqueueに追加しようとします
- (void)AddNewContentForURL:(NSURL*)url nextUrl:(NSURL*)nextUrl cookieParameter:(NSString*)cookieParameter title:(NSString*)title author:(NSString*)author firstContent:(NSString*)firstContent viewController:(UIViewController*)viewController;

/// 小説内部での範囲選択時に出てくるメニューを「読み替え辞書に登録」だけにする(YES)か否(NO)かの設定値を取り出します
- (BOOL)GetMenuItemIsAddSpeechModSettingOnly;

/// 小説内部での範囲選択時に出てくるメニューを「読み替え辞書に登録」だけにする(YES)か否(NO)かの設定値を保存します
- (void)SetMenuItemIsAddSpeechModSettingOnly:(BOOL)yesNo;

/// AppGroup で指示されたqueueを処理します
- (void)HandleAppGroupQueue;

/// 通知をONにしようとします
- (void)RegisterUserNotification;

/// BackgroundFetch を有効化します
- (void)StartBackgroundFetch;

/// ルビがふられた物について、ルビの部分だけを読むか否かの設定を取得します
- (BOOL)GetOverrideRubyIsEnabled;
/// ルビがふられた物について、ルビの部分だけを読むか否かの設定を保存します
- (void)SetOverrideRubyIsEnabled:(BOOL)yesNo;

/// 読み上げられないため、ルビとしては認識しない文字集合を取得します
- (NSString*)GetNotRubyCharactorStringArray;
/// 読み上げられないため、ルビとしては認識しない文字集合を設定します
- (void)SetNotRubyCharactorStringArray:(NSString*)data;

/// SiteInfo デバッグ用に、毎回 SiteInfo の読み直しを行うか否かの設定を取得します
- (BOOL)GetForceSiteInfoReloadIsEnabled;
/// SiteInfo デバッグ用に、毎回 SiteInfo の読み直しを行うか否かの設定を保存します
- (void)SetForceSiteInfoReloadIsEnabled:(BOOL)yesNo;

/// 読んでいるゲージを表示するか否かを取得します
- (BOOL)IsReadingProgressDisplayEnabled;
/// 読んでいるゲージを表示する(true)か否(false)かを設定します
- (void)SetReadingProgressDisplayEnabled:(BOOL)isDisplay;

/// Web取り込み用のBookmarkを取得します
- (NSArray*)GetWebImportBookmarks;
/// Web取り込み用のBookmarkに追加します。
- (void)AddWebImportBookmarkForName:(NSString*)name url:(NSURL*)url;
/// Web取り込み用のBookmarkから削除します
- (void)DelURLFromWebImportBookmark:(NSURL*)url;
/// Web取り込み用のBookmarkを全て消し去ります
- (void)ClearWebImportBookmarks;

// バックアップ用のデータを JSON に encode したものを生成して取得します
- (NSData*)CreateBackupJSONData;

/// 起動されるまでの間に新規にダウンロードされた小説の数を取得します
- (NSInteger)GetBackgroundFetchedNovelCount;
/// 起動されるまでの間に新規にダウンロードされた小説の数を更新します
- (void)UpdateBackgroundFetchedNovelCount:(NSInteger)count;

/// download queue の最後に対象の content を追加します。(与えられるNarouContentは既にCoreDataに登録されている物である必要があります)
- (void)PushContentDownloadQueue:(NarouContentCacheData*)content;

/// 読み上げ時にハングするような文字を読み上げ時にハングしない文字に変換するようにする読み替え辞書を強制的に登録します
- (void)ForceOverrideHungSpeakStringToSpeechModSettings;

@end
