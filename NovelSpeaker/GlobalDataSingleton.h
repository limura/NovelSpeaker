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
}

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
- (NSMutableArray*) GetAllNarouContent;

/// ダウンロードqueueに追加しようとします
/// 追加した場合は nil を返します。
/// 追加できなかった場合はエラーメッセージを返します。
- (NSString*) AddDownloadQueueForNarou:(NarouContentCacheData*) content;

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

/// 読み上げ時の読み替え設定を更新します。無ければ新しく登録されます。
- (BOOL)UpdateSpeechModSetting:(SpeechModSettingCacheData*)modSetting;

/// 読み上げ時の読み替え設定を削除します。
- (BOOL)DeleteSpeechModSetting:(SpeechModSettingCacheData*)modSetting;

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

@end
