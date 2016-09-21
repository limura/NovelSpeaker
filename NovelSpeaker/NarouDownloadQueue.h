//
//  NarouDownloadQueue.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NarouContentCacheData.h"

@protocol NarouDownloadQueueDelegate <NSObject>

// 個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentCacheData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition;
// 全ての download queue がなくなった時に呼び出されます。
- (void)DownloadEnd;

@end

@interface NarouDownloadQueue : NSObject
{
    // main thread の dispatch queue
    dispatch_queue_t m_MainDispatchQueue;
    
    // download queue 書き込み/読み出し用 dispatch queue
    dispatch_queue_t m_DownloadQueueReadWriteDispatchQueue;

    // コンテンツ download thread 用 dispatch queue
    dispatch_queue_t m_ContentsDownloadDispatchQueue;

    /// download queue
    NSMutableArray* m_DownloadQueue;

    /// コンテンツダウンロード用のthreadが終了するべきか否か
    bool m_isNeedQuit;
    
    /// download event handler list
    NSMutableArray* m_DownloadEventHandlerList;
    
    /// ncode match での download event handler list
    NSMutableDictionary* m_DownloadEventHandlerDictionary;
    
    /// 現在ダウンロード中のものの情報
    NarouContentCacheData* m_CurrentDownloadContentAllData;
    
    /// 小説家になろうからダウンロードした回数(連続ダウンロード抑止用)
    int m_DownloadCount;
    
    /// 小説家になろうから新たにダウンロードした小説の数(バッヂ用)
    int m_NewDownloadCount;
}

/// ダウンロード周りのイベントハンドラ用のdelegateに追加します。
- (BOOL)AddDownloadEventHandler:(id<NarouDownloadQueueDelegate>)handler;
/// ダウンロード周りのイベントハンドラ用のdelegateから削除します。
- (BOOL)DelDownloadEventHandler:(id<NarouDownloadQueueDelegate>)handler;

/// ダウンロード周りのイベントハンドラ用のdelegateに追加します。(ncode で絞り込む版)
- (BOOL)AddDownloadEventHandlerWithNcode:(NSString*)string handler:(id<NarouDownloadQueueDelegate>)handler;
/// ダウンロード周りのイベントハンドラ用のdelegateから削除します。(ncode で絞り込む版)
- (BOOL)DelDownloadEventHandlerWithNcode:(NSString*)string;

/// ダウンロード用のthreadを起動します
- (BOOL)StartDownloadThread;

/// ダウンロード用のthreadに停止を指示します。
- (void)StopDownloadThread;

/// ncode のコンテンツをダウンロードをqueueに入れます。
- (BOOL)AddDownloadQueue:(NarouContentCacheData*)content;

/// 現在ダウンロード待ち中の NarouContentCacheData* のリストを返します。
- (NSArray*)GetCurrentWaitingList;

/// 現在ダウンロード待ち中のものから、ncode を持つものをリストから外します。
- (BOOL)DeleteDownloadQueue:(NSString*)ncode;

/// 現在ダウンロード中のNarouContentCacheDataを取得します。
/// 何もダウンロードしていなければ nil が帰ります。
- (NarouContentCacheData*)GetCurrentDownloadingInfo;

/// ncodeのリスト(@"ncode-ncode-ncode..." という形式)の文字列を受け取って、ダウンロードキューに入れます
- (BOOL)AddDownloadQueueForNcodeList:(NSString*)ncodeList;

/// 現在の新規ダウンロード数カウントをクリアします
- (void)ClearNewDownloadCount;

/// 現在の新規ダウンロード数カウントを取得します
- (int)GetNewDownloadCount;

@end
