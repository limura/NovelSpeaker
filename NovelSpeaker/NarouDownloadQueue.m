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
#import "NarouContentAllData.h"

@implementation NarouDownloadQueue

// 一回のテキストダウンロードの度に寝る時間[NSTimeInterval]
static float SLEEP_TIME_SECOND = 5.0f;

/// ncode のコンテンツをダウンロードをqueueに入れます
- (BOOL)startDownload:(NSString*)ncode
{
    dispatch_queue_t contentDownloadQueue = [[GlobalDataSingleton GetInstance] GetContentsDownloadQueue];
    dispatch_async(contentDownloadQueue, ^{
        // ダウンロード用のqueue。
        NSString* downloadURL = [NarouLoader GetTextDownloadURL:ncode];
        if (downloadURL == nil) {
            NSLog(@"can not get download url for ncode: %@", ncode);
            return;
        }
        NarouContent* content = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:ncode];
        if (content == nil) {
            NSLog(@"can not get NarouContent from ncode: %@", ncode);
        }
        NarouContentAllData* localContent = [[NarouContentAllData alloc] initWithCoreData:content];

        int max_content_count = [content.general_all_no intValue];
        
        NSLog(@"download queue for %@ started max: %d", content.title, max_content_count);
        for (int n = 1; n < max_content_count; n++) {
            // ダウンロードを開始する「前に」指定の秒数だけ寝ます。
            // これをしないで連続ダウンロードを行うとゴミデータを掴まされる事になります。
            [NSThread sleepForTimeInterval:SLEEP_TIME_SECOND];
            // ダウンロードします。
            NSString* text = [NarouLoader TextDownload:downloadURL count:n];
            if (text == nil) {
                // 読み込みに失敗したのでここで終了します。
                NSLog(@"text download failed. ncode: %@, download in %d/%d", ncode, n, max_content_count);
                return;
            }
            // コンテンツを生成します。
            [[GlobalDataSingleton GetInstance] CreateNewStory:content content:text chapter_number:n];

            // ダウンロード状態を更新します。
            localContent.current_download_complete_count = n;
            [[GlobalDataSingleton GetInstance] UpdateCurrentDownloadingInfo:localContent];
        }
        // すべてのダウンロードが完了したら、nil で状態を更新します。
        [[GlobalDataSingleton GetInstance] UpdateCurrentDownloadingInfo:nil];
    });
    return true;
}


@end
