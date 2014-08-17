//
//  NarouDownloadQueue.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "NarouDownloadQueue.h"
#import "GlobalDataSingleton.h"
#import "NarouLoader.h"
#import "NarouContent.h"
#import "NarouContentCacheData.h"
#import "StoryCacheData.h"

@implementation NarouDownloadQueue

/// 一度のダウンロードでダウンロードされるテキストの数
static int BULK_DOWNLOAD_COUNT = 10;
/// BULK_DOWNLOAD_COUNT回のテキストダウンロードの度に寝る時間[NSTimeInterval]
static float SLEEP_TIME_SECOND = 10.5f;

- (id)init
{
    self = [super init];
    if (self == nil) {
        return self;
    }

    // main thread の dispatch queue を取得します
    m_MainDispatchQueue = dispatch_get_main_queue();
    
    //
    m_DownloadQueueReadWriteDispatchQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.naroudownloadqueue.downloadqueuereadwrite", NULL);
    
    // コンテンツダウンロード用の直列queueを作ります。
    m_ContentsDownloadDispatchQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.naroudownloadqueue.contentsdownload", NULL);

    m_DownloadQueue = [NSMutableArray new];
    m_isNeedQuit = false;
    
    m_DownloadEventHandlerList = [NSMutableArray new];
    
    m_CurrentDownloadContentAllData = nil;
    m_DownloadCount = 0;
    
    [self StartDownloadThread];
    
    return self;
}

- (void)dealloc
{
    [self StopDownloadThread];
}

/// text を pattern で正規表現マッチさせて、マッチしたか否かを返します。
/// 毎回 NSRegularExpression object を作るので頭悪い気がします。
- (BOOL)regexMatch:(NSString*)text pattern:(NSString*)pattern
{
    NSError* err = nil;
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&err];
    NSTextCheckingResult* matchResult = [regex firstMatchInString:text options:NSMatchingReportProgress range:NSMakeRange(0, [text length])];
    if (matchResult == nil) {
        return false;
    }
    return true;
}

/// 与えられた文字列が正しく小説のテキストであるかを判定します。
/// ダウンロードが失敗したり、HTTP で wlan 認証をしたりする所に移動した場合
/// とかに変なテキストを掴まされたりした場合を判定する必要があるため、
/// かなり怪しい判定処理を行っています。
- (BOOL)isValidChapterText:(NSString*)text
{
    if (text == nil) {
        return false;
    }

    // なんか HTML っぽかったら駄目。
    // これは連続ダウンロードで失敗したときにも引っかかるはず。
    if ([self regexMatch:text pattern:@"^\\s*<"] == true) {
        return false;
    }
    
    return true;
}

/// story が正しいものかどうかを判定します。
/// ダウンロードに失敗しているなどを検出するために使います。
- (BOOL)isValidStory:(StoryCacheData*)story
{
    if (story == nil) {
        return false;
    }
    if ([self isValidChapterText:story.content] == false) {
        return false;
    }
    return true;
}

/// ダウンロード用のthreadを起動します
- (BOOL)StartDownloadThread
{
    dispatch_async(m_ContentsDownloadDispatchQueue, ^{
        [self threadMain];
    });
    
    return true;
}

/// ダウンロード用のthreadに停止を指示します。
- (void)StopDownloadThread
{
    m_isNeedQuit = true;
}

/// ダウンロード周りのイベントハンドラ用のdelegateに追加します。
- (BOOL)AddDownloadEventHandler:(id<NarouDownloadQueueDelegate>)handler
{
    [m_DownloadEventHandlerList addObject:handler];
    return true;
}
/// ダウンロード周りのイベントハンドラ用のdelegateから削除します。
- (BOOL)DelDownloadEventHandler:(id<NarouDownloadQueueDelegate>)handler
{
    [m_DownloadEventHandlerList removeObject:handler];
    return true;
}


/// DownloadEndイベントを発生させます。
- (void)KickDoenloadEnd
{
    for (id<NarouDownloadQueueDelegate> handler in m_DownloadEventHandlerList){
        [handler DownloadEnd];
    }
}
/// DownloadStatusUpdate イベントを発生させます。
- (void)KickDownloadStatusUpdate:(NarouContentCacheData*)content n:(int)n maxpos:(int)maxpos
{
    for (id<NarouDownloadQueueDelegate> handler in m_DownloadEventHandlerList){
        [handler DownloadStatusUpdate:content currentPosition:n maxPosition:maxpos];
    }
}

/// ダウンロード用threadのmain
- (void)threadMain
{
    bool isDownloadKicked = false;
    while (true) {
        if (m_isNeedQuit) {
            break;
        }
        [NSThread sleepForTimeInterval:0.1];
        
        __block NarouContentCacheData* targetContent = nil;
        dispatch_sync(m_DownloadQueueReadWriteDispatchQueue, ^{
            if ([m_DownloadQueue count] > 0) {
                targetContent = m_DownloadQueue[0];
                [m_DownloadQueue removeObjectAtIndex:0];
            }
        });
        
        if (targetContent == nil) {
            if (isDownloadKicked) {
                // ダウンロードが終わったら DownloadEnd イベントを発生させます。
                dispatch_sync(m_MainDispatchQueue, ^{
                    [self KickDoenloadEnd];
                });
            }
            isDownloadKicked = false;
            continue;
        }
        
        [self ChapterDownload:targetContent];
        isDownloadKicked = true;
    }
}

/// ncode のコンテンツのダウンロードを指示します。
- (BOOL)AddDownloadQueue:(NarouContentCacheData*)content
{
    dispatch_async(m_DownloadQueueReadWriteDispatchQueue, ^{
        [m_DownloadQueue addObject:content];
    });
    return true;
}

/// ncode のコンテンツのダウンロードを開始します。
- (BOOL)ChapterDownload:(NarouContentCacheData*)localContent
{
    NSString* downloadURL = [NarouLoader GetTextDownloadURL:localContent.ncode];
    if (downloadURL == nil) {
        NSLog(@"can not get download url for ncode: %@", localContent.ncode);
        return false;
    }
    // 与えられた情報が最新のものなのだろうと思い込んで、CoreData側の情報を上書きします。
    [[GlobalDataSingleton GetInstance] UpdateNarouContent:localContent];

    // 現在ダウンロード中とするデータを copy で作っておきます。
    dispatch_async(m_MainDispatchQueue, ^{
        m_CurrentDownloadContentAllData = localContent;
        m_CurrentDownloadContentAllData.current_download_complete_count = 0;
    });

    int max_content_count = [localContent.general_all_no intValue];
        
    NSLog(@"download queue for %@ started max: %d", localContent.title, max_content_count);
    for (int n = 1; n < max_content_count; n++) {
        // ダウンロード状態を更新します。
        dispatch_async(m_MainDispatchQueue, ^{
            [self KickDownloadStatusUpdate:localContent n:n maxpos:max_content_count];
            m_CurrentDownloadContentAllData.current_download_complete_count = n;
        });

        //NSLog(@"Story の query をかけます。");
        // 既に読みこんであるか否かを判定します。
        StoryCacheData* story = [[GlobalDataSingleton GetInstance] SearchStory:localContent.ncode chapter_no:n];
        //NSLog(@"Story の query が終わりました。");
        if (story != nil) {
            // 何かデータがありました。
            if ([self isValidStory:story] == false) {
                // 駄目なデータでした。削除して読み込みを行います。
                NSLog(@"すでにあるデータは 駄目なデータだったので削除して読み込みを行います。(%d)", n);
                NSLog(@"content: %p", localContent);
                [[GlobalDataSingleton GetInstance] DeleteStory:story];
                NSLog(@"content: %p", localContent);
            }else{
                // 既に読み込んであるようなので読み込まないで良いことにします。
                //NSLog(@"読み込み済みなのでスキップします。%d/%d %@", n, max_content_count, localContent.title);
                continue;
            }
        }
        if (m_DownloadCount >= BULK_DOWNLOAD_COUNT) {
            NSLog(@"download sleep.");
            // 指定回数分までダウンロードされたので、ダウンロードを開始する前に指定の秒数だけ寝ます。
            // これをしないで連続ダウンロードを行うとゴミデータを掴まされる事になります。
            NSDate* endDate = [[NSDate date] dateByAddingTimeInterval:SLEEP_TIME_SECOND];
            while ([endDate compare:[NSDate date]] != NSOrderedAscending) {
                if (m_isNeedQuit) {
                    break;
                }
                [NSThread sleepForTimeInterval:0.1];
            }
            m_DownloadCount = m_DownloadCount % BULK_DOWNLOAD_COUNT;
        }
        if (m_isNeedQuit) {
            break;
        }
        // ダウンロードします。
        //NSLog(@"download start %d %@", n, downloadURL);
        m_DownloadCount += 1;
        NSString* text = [NarouLoader TextDownload:downloadURL count:n];
        if (text == nil) {
            // 読み込みに失敗したのでここで終了します。
            NSLog(@"text download failed. ncode: %@, download in %d/%d", localContent.ncode, n, max_content_count);
            return false;
        }
        //NSLog(@"create new story: %d, %@", n, localContent.title);
        // コンテンツを生成します。
        [[GlobalDataSingleton GetInstance] UpdateStory:text chapter_number:n parentContent:localContent];
        // 保存を走らせます。(でないと main thread側 の core data に反映されません……(´・ω・`)
        [[GlobalDataSingleton GetInstance] saveContext];
   }
   // すべてのダウンロードが完了したら、nil で状態を更新します。
    dispatch_async(m_MainDispatchQueue, ^{
        [self KickDownloadStatusUpdate:nil n:0 maxpos:0];
        m_CurrentDownloadContentAllData = nil;
    });

    return true;
}

/// 現在ダウンロード待ち中の NarouContentAllData* のリストを返します。
- (NSArray*)GetCurrentWaitingList
{
    __block NSArray* result = nil;
    dispatch_sync(m_DownloadQueueReadWriteDispatchQueue, ^{
        result = [m_DownloadQueue copy];
    });
    return result;
}

/// 現在ダウンロード待ち中のものから、ncode を持つものをリストから外します。
- (BOOL)DeleteDownloadQueue:(NSString*)ncode
{
    __block BOOL bRemoved = false;
    dispatch_sync(m_DownloadQueueReadWriteDispatchQueue, ^{
        int index = -1;
        for (int i = 0; i < [m_DownloadQueue count]; i++) {
            NarouContentCacheData* content = m_DownloadQueue[i];
            if ([content.ncode isEqualToString:ncode]) {
                index = i;
                break;
            }
        }
        if (index >= 0) {
            [m_DownloadQueue removeObjectAtIndex:index];
            bRemoved = true;
        }
    });
    return bRemoved;
}

/// 現在ダウンロード中のNarouContentAllDataを取得します。
/// 何もダウンロードしていなければ nil が帰ります。
- (NarouContentCacheData*)GetCurrentDownloadingInfo
{
    return m_CurrentDownloadContentAllData;
}


@end
