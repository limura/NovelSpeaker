//
//  NarouDownloadQueue.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NarouContentAllData.h"

@interface NarouDownloadQueue : NSObject

/// ncode のコンテンツをダウンロードをqueueに入れます。
- (BOOL)startDownload:(NSString*)ncode;

@end
