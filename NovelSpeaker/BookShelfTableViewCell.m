//
//  BookShelfTableViewCell.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/13.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "BookShelfTableViewCell.h"
#import "NarouDownloadQueue.h"
#import "GlobalDataSingleton.h"

@implementation BookShelfTableViewCell

- (void)awakeFromNib
{
    // Initialization code
    m_Ncode = nil;
}

- (void)dealloc
{
    [[GlobalDataSingleton GetInstance] DeleteDownloadEventHandlerWithNcode:m_Ncode];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)UpdateActivityIndicator
{
    BOOL hit = false;

    NarouContentCacheData* content = [[GlobalDataSingleton GetInstance] GetCurrentDownloadingInfo];
    if (content == nil || [content.ncode compare:m_Ncode] != NSOrderedSame) {
        hit = false;
    }else{
        hit = true;
    }

    if (hit == false) {
        NSArray* downloadList = [[GlobalDataSingleton GetInstance] GetCurrentDownloadWaitingInfo];
        for (NarouContentCacheData* content in downloadList) {
            if ([content.ncode compare:m_Ncode] == NSOrderedSame) {
                hit = true;
                break;
            }
        }
    }

    if (hit) {
        self.ActivityIndicator.hidden = NO;
        if (![self.ActivityIndicator isAnimating]) {
            [self.ActivityIndicator startAnimating];
        }
    }else{
        self.ActivityIndicator.hidden = YES;
    }
}

///
- (void)setTitleLabel:(NSString*)titleLabel ncode:(NSString*)ncode
{
    m_Ncode = ncode;
    m_MainDispatchQueue = dispatch_get_main_queue();

    self.TitleLabel.text = titleLabel;
    self.NewImaveView.hidden = YES;
    
    [self UpdateActivityIndicator];
    
    NarouContentCacheData* content = [[GlobalDataSingleton GetInstance] GetCurrentDownloadingInfo];
    if (content == nil || [content.ncode compare:ncode] != NSOrderedSame) {
        self.DownloadProgressView.hidden = YES;
    }else{
        self.DownloadProgressView.hidden = NO;
    }
    
    [[GlobalDataSingleton GetInstance] AddDownloadEventHandlerWithNcode:ncode handler:self];
}

/// New! のインジケータを点けます
- (void)NewIndicatorEnable
{
    dispatch_async(m_MainDispatchQueue, ^{
        self.NewImaveView.hidden = NO;
    });
}

/// New! のインジケータを消します
- (void)NewIndicatorDisable
{
    dispatch_async(m_MainDispatchQueue, ^{
        self.NewImaveView.hidden = YES;
    });
}

// 個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentCacheData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition
{
    dispatch_async(m_MainDispatchQueue, ^{
        [self UpdateActivityIndicator];
        if (content == nil || content.ncode == nil || ![content.ncode isEqualToString:m_Ncode] || maxPosition == 0) {
            self.DownloadProgressView.hidden = YES;
            return;
        }
        float progress = (float)currentPosition / (float)maxPosition;
        self.DownloadProgressView.progress = progress;
        self.DownloadProgressView.hidden = NO;
    });
}
// 全ての download queue がなくなった時に呼び出されます。
- (void)DownloadEnd
{
    dispatch_async(m_MainDispatchQueue, ^{
        self.DownloadProgressView.hidden = YES;
        self.ActivityIndicator.hidden = YES;
    });
}


@end
