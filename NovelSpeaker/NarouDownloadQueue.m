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
#import "UriLoader.h"
#import "EasyAlert.h"
#import "NovelSpeaker-Swift.h"

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
    m_DownloadQueueReadWriteDispatchQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.naroudownloadqueue.downloadqueuereadwrite", DISPATCH_QUEUE_SERIAL);
    
    // コンテンツダウンロード用の直列queueを作ります。
    m_ContentsDownloadDispatchQueue = dispatch_queue_create("com.limuraproducts.novelspeaker.naroudownloadqueue.contentsdownload", DISPATCH_QUEUE_SERIAL);

    m_DownloadQueue = [NSMutableArray new];
    m_isNeedQuit = false;
    
    m_DownloadEventHandlerList = [NSMutableArray new];
    m_DownloadEventHandlerDictionary = [NSMutableDictionary new];
    
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

/// ダウンロード周りのイベントハンドラ用のdelegateに追加します。
- (BOOL)AddDownloadEventHandlerWithNcode:(NSString*)string handler:(id<NarouDownloadQueueDelegate>)handler
{
    if(string == nil)
    {
        return false;
    }
    [m_DownloadEventHandlerDictionary setObject:handler forKey:string];
    return true;
}
/// ダウンロード周りのイベントハンドラ用のdelegateから削除します。
- (BOOL)DelDownloadEventHandlerWithNcode:(NSString*)string
{
    [m_DownloadEventHandlerDictionary removeObjectForKey:string];
    return true;
}


/// DownloadEndイベントを発生させます。
- (void)KickDoenloadEnd
{
    for (id<NarouDownloadQueueDelegate> handler in m_DownloadEventHandlerList){
        [handler DownloadEnd];
    }
    for (NSString* ncode in m_DownloadEventHandlerDictionary) {
        id<NarouDownloadQueueDelegate> ncodeHandler = [m_DownloadEventHandlerDictionary objectForKey:ncode];
        [ncodeHandler DownloadEnd];
    }
}
/// DownloadStatusUpdate イベントを発生させます。
- (void)KickDownloadStatusUpdate:(NarouContentCacheData*)content n:(int)n maxpos:(int)maxpos
{
    for (id<NarouDownloadQueueDelegate> handler in m_DownloadEventHandlerList){
        [handler DownloadStatusUpdate:content currentPosition:n maxPosition:maxpos];
    }
    id<NarouDownloadQueueDelegate> ncodeHandler = [m_DownloadEventHandlerDictionary objectForKey:content.ncode];
    if (ncodeHandler != nil) {
        [ncodeHandler DownloadStatusUpdate:content currentPosition:n maxPosition:maxpos];
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
            if ([self->m_DownloadQueue count] > 0) {
                targetContent = self->m_DownloadQueue[0];
                [self->m_DownloadQueue removeObjectAtIndex:0];
            }
        });
        
        if (targetContent == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:false];
            });
            if (isDownloadKicked) {
                // ダウンロードが終わったら DownloadEnd イベントを発生させます。
                dispatch_sync(m_MainDispatchQueue, ^{
                    [self KickDoenloadEnd];
                });
            }
            isDownloadKicked = false;
            continue;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:true];
        });
        [self ChapterDownload:targetContent];
        isDownloadKicked = true;
    }
}

/// ncode のコンテンツのダウンロードを指示します。
- (BOOL)AddDownloadQueue:(NarouContentCacheData*)content
{
    dispatch_async(m_DownloadQueueReadWriteDispatchQueue, ^{
        [self->m_DownloadQueue addObject:content];
    });
    [self announceDownloadStatus:content n:0 maxPos:[content.general_all_no intValue]];
    return true;
}

/// ダウンロード状態が変わったことのアナウンスを行います。
- (void)announceDownloadStatus:(NarouContentCacheData*)content n:(int)n maxPos:(int)maxPos
{
    //NSLog(@"%@ position update notification %d/%d", content.ncode, n, maxPos);
    NSDictionary* args = [[NSDictionary alloc] initWithObjectsAndKeys:
                          [[NSNumber alloc] initWithBool:true], @"isDownloading"
                          , [[NSNumber alloc] initWithInt:n], @"currentPosition"
                          , [[NSNumber alloc] initWithInt:maxPos], @"maxPosition"
                          , nil];
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentDownloadStatusChanged_%@", content.ncode];
    NSNotification* notification = [NSNotification notificationWithName:notificationName object:self userInfo:args];
    [notificationCenter postNotification:notification];
}

/// ダウンロード状態が終わった事のアナウンスを行います。
- (void)announceDownloadStatusEnd:(NarouContentCacheData*)content
{
    //NSLog(@"%@ FINISH notification", content.ncode);
    NSDictionary* args = [[NSDictionary alloc] initWithObjectsAndKeys:
                          [[NSNumber alloc] initWithBool:false], @"isDownloading"
                          , nil];
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentDownloadStatusChanged_%@", content.ncode];
    NSNotification* notification = [NSNotification notificationWithName:notificationName object:self userInfo:args];
    [notificationCenter postNotification:notification];
}

// new! の Notification を飛ばします
- (void)announceNarouContentNewStatusUp:(NarouContentCacheData*)content
{
    //NSLog(@"%@ New status UP!", content.ncode);
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusUp_%@", content.ncode];
    NSNotification* notification = [NSNotification notificationWithName:notificationName object:self];
    [notificationCenter postNotification:notification];
}

/// URL のコンテンツをダウンロードします。
- (BOOL)URLDownload:(NarouContentCacheData*)localContent {

    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    UriLoader* loader = [UriLoader new];
    NSLog(@"URLDownload: %@ %@", localContent.title, localContent.ncode);
    
    // ことせかい用のカスタムSiteInfoデータを優先度的に上にするために先に読み込ませます
    NSData* customSiteInfoData = [globalData GetCachedCustomAutoPagerizeSiteInfoData];
    if(![loader AddCustomSiteInfoFromData:customSiteInfoData]){
        NSLog(@"AddCustomSiteInfoFromData failed: %@", [[NSString alloc] initWithData:customSiteInfoData encoding:NSUTF8StringEncoding]);
    }
    
    // AutoPagerizeの情報はその後です
    NSData* siteInfoData = [globalData GetCachedAutoPagerizeSiteInfoData];
    if(![loader AddSiteInfoFromData:siteInfoData]){
        return false;
    }
    
    NSString* urlString = localContent.ncode;
    int startCount = 1;
    // 最終ダウンロードURLがあるならターゲットをそれに更新する。
    // XXXXX TODO: .userid が最後に読み込んだ URL になってるのをなんとかしたい……(´・ω・`)
    if (localContent.userid != nil && [localContent.userid length] > 0) {
        urlString = localContent.userid;
        startCount = [localContent.general_all_no intValue];
    }
    NSURL* targetURL = [[NSURL alloc] initWithString:urlString];

    //NSLog(@"URLDownload: keyword(cookie): %@", localContent.keyword);
    NSArray* cookieArray = [localContent.keyword componentsSeparatedByString:@";"];

    __block BOOL result = false;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [loader LoadURL:targetURL cookieArray:cookieArray startCount:startCount successAction:^BOOL(HtmlStory* story, NSURL* currentURL){
        if (story == nil) {
            return false;
        }
        // ダウンロード中に本棚からNarouContentが消されている場合はダウンロードを打ち切る必要があります。
        {
            NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:localContent.ncode];
            if (content == nil) {
                NSLog(@"already deleted content!!!!!!!!");
                return false;
            }
        }
        
        if ([localContent.general_all_no intValue] < story.count) {
            localContent.general_all_no = [[NSNumber alloc] initWithInt:story.count];
        }
        // XXXXX TODO: .userid が最後に読み込んだ URL になってるのをなんとかしたい……(´・ω・`)
        localContent.userid = [currentURL absoluteString];
        if (story.count != startCount) {
            // 最初に読んだもの以外は内容を更新する。(最初に読むのは前回最後に読んだものなので、ユーザが内容を更新している可能性があるため更新しない)
            [globalData UpdateStory:story.content chapter_number:story.count parentContent:localContent];
            localContent.is_new_flug = [[NSNumber alloc] initWithBool:true];
            localContent.novelupdated_at = [[NSDate alloc] initWithTimeIntervalSinceNow:0];
        }
        [globalData UpdateNarouContent:localContent];
        result = true;
        // ダウンロードされたので、ダウンロード状態を更新します。
        dispatch_async(self->m_MainDispatchQueue, ^{
            [self KickDownloadStatusUpdate:localContent n:story.count maxpos:story.count];
            self->m_CurrentDownloadContentAllData.current_download_complete_count = story.count;
        });
        return true;
    } failedAction:^(NSURL* url){
        NSLog(@"LoadURL failed. %@", [url absoluteString]);
    } finishAction:^(NSURL* url){
        //NSLog(@"LoadURL finish. %@", [url absoluteString]);
        // すべてのダウンロードが完了したら、nil で状態を更新します。
        dispatch_async(self->m_MainDispatchQueue, ^{
            [self KickDownloadStatusUpdate:nil n:0 maxpos:0];
            self->m_CurrentDownloadContentAllData = nil;
        });
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    // 更新された内容をアナウンスする必要があります
    NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:localContent.ncode];
    if (content != nil) {
        localContent = content;
    }
    [self announceDownloadStatusEnd:localContent];

    return result;
}

/// ncode のコンテンツのダウンロードを開始します。
- (BOOL)ChapterDownload:(NarouContentCacheData*)localContent
{
    if (localContent == nil || localContent.ncode == nil) {
        return false;
    }
    [BehaviorLogger AddLogWithDescription:@"NarouDownloadQueue ChapterDownload kicked" data:@{
        @"ncode": localContent.ncode == nil ? @"nil" : localContent.ncode
    }];
    if ([localContent isURLContent]) {
        return [self URLDownload:localContent];
    }
    if ([localContent isUserCreatedContent]) {
        return false;
    }
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    
    // 与えられた content の ncode を使って最新情報を読み込んでCoreData側の情報を上書きします。
    NarouContentCacheData* currentContent = [NarouLoader GetCurrentNcodeContentData:localContent.ncode];
    if (currentContent == nil) {
        NSLog(@"ncode: %@ の最新情報の読み込みに失敗しました。", localContent.ncode);
        return false;
    }
    [globalData UpdateNarouContent:currentContent];
    localContent = currentContent;
    
    NSString* downloadURL = [NarouLoader GetTextDownloadURL:localContent.ncode];
    if (downloadURL == nil) {
        NSLog(@"can not get download url for ncode: %@", localContent.ncode);
        return false;
    }

    // 現在ダウンロード中とするデータを copy で作っておきます。
    dispatch_async(m_MainDispatchQueue, ^{
        self->m_CurrentDownloadContentAllData = localContent;
        self->m_CurrentDownloadContentAllData.current_download_complete_count = 0;
    });

    int max_content_count = [localContent.general_all_no intValue];
    Boolean isDownloaded = FALSE;
        
    //NSLog(@"download queue for %@ started max: %d", localContent.title, max_content_count);
    for (int n = 1; n <= max_content_count; n++) {

        //NSLog(@"Story の query をかけます。");
        // 既に読みこんであるか否かを判定します。
        StoryCacheData* story = [globalData SearchStory:localContent.ncode chapter_no:n];
        //NSLog(@"Story の query が終わりました。");
        if (story != nil) {
            // 何かデータがありました。
            if ([self isValidStory:story] == false) {
                // 駄目なデータでした。削除して読み込みを行います。
                NSLog(@"すでにあるデータは 駄目なデータだったので削除して読み込みを行います。(%d)", n);
                [globalData DeleteStory:story];
            }else{
                // 既に読み込んであるようなので読み込まないで良いことにします。
                //NSLog(@"読み込み済みなのでスキップします。%d/%d %@", n, max_content_count, localContent.title);
                continue;
            }
        }
        if (m_DownloadCount >= BULK_DOWNLOAD_COUNT) {
            //NSLog(@"download sleep.");
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
        // ダウンロード中に本棚からNarouContentが消されている場合はダウンロードを打ち切る必要があります。
        {
            NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:localContent.ncode];
            if (content == nil) {
                NSLog(@"already deleted content!!!!!!!!");
                return false;
            }
        }
        //NSLog(@"create new story: %d, %@", n, localContent.title);
        // コンテンツを生成します。
        [globalData UpdateStory:text chapter_number:n parentContent:localContent];
        // new flag を立てます
        localContent.is_new_flug = [[NSNumber alloc] initWithBool:true];
        [globalData UpdateNarouContent:localContent];
        // 保存を走らせます。(でないと main thread側 の core data に反映されません……(´・ω・`)
        [globalData saveContext];
        [self announceNarouContentNewStatusUp:localContent];

        // ダウンロードされたので、ダウンロード状態を更新します。
        dispatch_async(m_MainDispatchQueue, ^{
            [self KickDownloadStatusUpdate:localContent n:n maxpos:max_content_count];
            self->m_CurrentDownloadContentAllData.current_download_complete_count = n;
        });
        [self announceDownloadStatus:localContent n:n maxPos:max_content_count];
        
        isDownloaded = TRUE;
    }
   // すべてのダウンロードが完了したら、nil で状態を更新します。
    dispatch_async(m_MainDispatchQueue, ^{
        [self KickDownloadStatusUpdate:nil n:0 maxpos:0];
        self->m_CurrentDownloadContentAllData = nil;
    });
    [self announceDownloadStatusEnd:localContent];
    
    // ncode で監視している奴には ちゃんと DownloadEnd を送ってやります。
    id<NarouDownloadQueueDelegate> ncodeHandler = [m_DownloadEventHandlerDictionary objectForKey:localContent.ncode];
    if (ncodeHandler != nil) {
        [ncodeHandler DownloadEnd];
    }
    
    if (isDownloaded) {
        m_NewDownloadCount++;
    }
    
    return true;
}

/// 現在ダウンロード待ち中の NarouContentAllData* のリストを返します。
- (NSArray*)GetCurrentWaitingList
{
    __block NSArray* result = nil;
    dispatch_sync(m_DownloadQueueReadWriteDispatchQueue, ^{
        if (self != nil && self->m_DownloadQueue != nil) {
            result = [self->m_DownloadQueue copy];
        }else{
            result = @[];
        }
    });
    return result;
}

/// 現在ダウンロード待ち中のものから、ncode を持つものをリストから外します。
- (BOOL)DeleteDownloadQueue:(NSString*)ncode
{
    __block BOOL bRemoved = false;
    dispatch_sync(m_DownloadQueueReadWriteDispatchQueue, ^{
        int index = -1;
        for (int i = 0; i < [self->m_DownloadQueue count]; i++) {
            NarouContentCacheData* content = self->m_DownloadQueue[i];
            if ([content.ncode isEqualToString:ncode]) {
                index = i;
                break;
            }
        }
        if (index >= 0) {
            [self->m_DownloadQueue removeObjectAtIndex:index];
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


/// ncodeのリスト(@"ncode-ncode-ncode..." という形式)の文字列を受け取って、ダウンロードキューに入れます
- (BOOL)AddDownloadQueueForNcodeList:(NSString*)ncodeList
{
    // 一応入力文字列をvalidateします
    // 先頭は 'n' か 'N' である必要があります
    if (!([ncodeList hasPrefix:@"n"] || [ncodeList hasPrefix:@"N"])) {
        return false;
    }
    // 文字列は [A-Za-z0-9-] だけである必要があります
    {
        NSRegularExpression* regexp = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9-]" options:NSRegularExpressionIgnoreMetacharacters error:nil];
        NSTextCheckingResult* matchResult = [regexp firstMatchInString:ncodeList options:0 range:NSMakeRange(0, ncodeList.length)];
        if (matchResult.numberOfRanges > 0) {
            return false;
        }
    }
    dispatch_async(m_DownloadQueueReadWriteDispatchQueue, ^{
        NSArray* searchResult = [NarouLoader SearchNcode:ncodeList];
        for (NarouContentCacheData* content in searchResult) {
            [self AddDownloadQueue:content];
        }
    });
    return true;
}

/// 現在の新規ダウンロード数をクリアします
- (void)ClearNewDownloadCount{
    m_NewDownloadCount = 0;
}

/// 現在の新規ダウンロード数を取得します
- (int)GetNewDownloadCount {
    return m_NewDownloadCount;
}


@end
