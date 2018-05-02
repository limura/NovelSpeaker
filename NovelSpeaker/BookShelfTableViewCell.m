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
    [super awakeFromNib];
    // Initialization code
    m_Ncode = nil;
}

- (void)dealloc
{
    [self removeNotificationReciver];
    [[GlobalDataSingleton GetInstance] DeleteDownloadEventHandlerWithNcode:m_Ncode];
}

/// NotificationCenter の受信者の設定をします。
- (void)setNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];

    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentDownloadStatusChanged_%@", m_Ncode];
    [notificationCenter addObserver:self selector:@selector(NarouContentDowonloadStatusChanged:) name:notificationName object:nil];

    notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusUp_%@", m_Ncode];
    [notificationCenter addObserver:self selector:@selector(NarouContentNewStatusUp:) name:notificationName object:nil];

    notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusDown_%@", m_Ncode];
    [notificationCenter addObserver:self selector:@selector(NarouContentNewStatusDown:) name:notificationName object:nil];
    
    notificationName = [[NSString alloc] initWithFormat:@"NarouContentReadingPointChanged_%@", m_Ncode];
    [notificationCenter addObserver:self selector:@selector(NarouContentReadingPointUpdated:) name:notificationName object:nil];
    notificationName = @"NarouContentReadingPointChanged";
    [notificationCenter addObserver:self selector:@selector(NarouContentReadingPointUpdated:) name:notificationName object:nil];
}

/// NotificationCenter の受信者の設定を解除します。
- (void)removeNotificationReciver
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];

    NSString* notificationName = [[NSString alloc] initWithFormat:@"NarouContentDownloadStatusChanged_%@", m_Ncode];
    [notificationCenter removeObserver:self name:notificationName object:nil];

    notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusUp_%@", m_Ncode];
    [notificationCenter removeObserver:self name:notificationName object:nil];
    
    notificationName = [[NSString alloc] initWithFormat:@"NarouContentNewStatusDown_%@", m_Ncode];
    [notificationCenter removeObserver:self name:notificationName object:nil];

    notificationName = [[NSString alloc] initWithFormat:@"NarouContentReadingPointChanged_%@", m_Ncode];
    [notificationCenter removeObserver:self name:notificationName object:nil];
    notificationName = @"NarouContentReadingPointChanged";
    [notificationCenter removeObserver:self name:notificationName object:nil];
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
            if (content != nil && content.ncode != nil && m_Ncode != nil && [content.ncode compare:m_Ncode] == NSOrderedSame) {
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

- (void)UpdateNewLabel
{
    NarouContentCacheData* content = [[GlobalDataSingleton GetInstance] SearchNarouContentFromNcode:m_Ncode];
    if ([content.is_new_flug boolValue]) {
        self.NewImaveView.hidden = NO;
        //NSLog(@"is new: %@", m_Ncode);
    }else{
        self.NewImaveView.hidden = YES;
    }
}

///
- (void)setTitleLabel:(NSString*)titleLabel ncode:(NSString*)ncode
{
    if([m_Ncode length] > 0)
    {
        [self removeNotificationReciver];
    }
    m_Ncode = ncode;
    m_MainDispatchQueue = dispatch_get_main_queue();

    self.TitleLabel.text = titleLabel;
    self.NewImaveView.hidden = YES;
    
    [self UpdateActivityIndicator];
    [self UpdateNewLabel];
    [self UpdateReadingProgressView:m_Ncode];
    
    NarouContentCacheData* content = [[GlobalDataSingleton GetInstance] GetCurrentDownloadingInfo];
    if (content == nil || [content.ncode compare:ncode] != NSOrderedSame) {
        self.DownloadProgressView.hidden = YES;
    }else{
        self.DownloadProgressView.hidden = NO;
    }
    
    [self setNotificationReciver];
    //[[GlobalDataSingleton GetInstance] AddDownloadEventHandlerWithNcode:ncode handler:self];
}

// 読んでいるゲージを更新します
- (void)UpdateReadingProgressView:(NSString*)ncode {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    if (![globalData IsReadingProgressDisplayEnabled]) {
        self.ReadProgressView.hidden = true;
        return;
    }
    NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:ncode];
    if (content == nil) {
        self.ReadProgressView.hidden = true;
        return;
    }
    StoryCacheData* story = content.currentReadingStory;
    if (story == nil) {
        self.ReadProgressView.hidden = true;
        return;
    }
    float allNumber = [content.general_all_no floatValue];
    if (allNumber <= 0.0f) {
        allNumber = 1.0f;
    }
    float chapterNumber = [story.chapter_number floatValue];
    float pageLength = (float)[story.content length];
    if (pageLength <= 0.0f) {
        pageLength = 1.0f;
    }
    float readingPoint = [story.readLocation floatValue];
    float readingProgress = ((chapterNumber - 1.0f) + readingPoint / pageLength) / allNumber;
    self.ReadProgressView.progress = readingProgress;
    self.ReadProgressView.hidden = false;
    
    if (([content.general_all_no compare:story.chapter_number] == NSOrderedSame || [content.general_all_no intValue] == 0)
        && ([story.readLocation unsignedIntValue] + 10) >= [story.content length]) {
        self.ReadProgressView.tintColor = [[UIColor alloc] initWithRed:0.0 green:0.9 blue:0.0 alpha:1];
    }else{
        self.ReadProgressView.tintColor = [[UIColor alloc] initWithRed:255/256.0 green:188/256.0 blue:2/256.0 alpha:1.0];
    }
}

// 個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentCacheData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition
{
    dispatch_async(m_MainDispatchQueue, ^{
        [self UpdateActivityIndicator];
        [self UpdateNewLabel];
        if (content == nil || content.ncode == nil || ![content.ncode isEqualToString:self->m_Ncode] || maxPosition == 0) {
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
        [self UpdateNewLabel];
    });
}

- (void)NarouContentDowonloadStatusChanged:(NSNotification*)notification
{
    NSDictionary* args = [notification userInfo];
    NSNumber* isDownloading = [args objectForKey:@"isDownloading"];
    if (![isDownloading boolValue]) {
        //NSLog(@"NarouContentDownloadStatusChanged notification got. it is FINISH");
        dispatch_async(m_MainDispatchQueue, ^{
            self.DownloadProgressView.hidden = YES;
            self.ActivityIndicator.hidden = YES;
            [self sendSubviewToBack:self.DownloadProgressView];
        });
    }else{
        NSNumber* currentPosition = [args objectForKey:@"currentPosition"];
        NSNumber* maxPosition = [args objectForKey:@"maxPosition"];
        float progress = (float)[currentPosition intValue] / (float)[maxPosition intValue];
        dispatch_async(m_MainDispatchQueue, ^{
            self.DownloadProgressView.progress = progress;
            self.DownloadProgressView.hidden = NO;
            self.ActivityIndicator.hidden = NO;
            [self bringSubviewToFront:self.DownloadProgressView];
            if (![self.ActivityIndicator isAnimating]) {
                [self.ActivityIndicator startAnimating];
            }
            //NSLog(@"NarouContentDownloadStatusChanged notification got. it is position update. %d/%d", [currentPosition intValue], [maxPosition intValue]);
        });
        //[self UpdateActivityIndicator];
    }
}

- (void)NarouContentNewStatusUp:(NSNotification*)notification
{
    //NSLog(@"NarouContentNewStatus Up!");
    dispatch_async(m_MainDispatchQueue, ^{
        self.NewImaveView.hidden = NO;
    });
}
- (void)NarouContentNewStatusDown:(NSNotification*)notification
{
    //NSLog(@"NarouContentNewStatus Down!");
    dispatch_async(m_MainDispatchQueue, ^{
        self.NewImaveView.hidden = YES;
    });
}

- (void)NarouContentReadingPointUpdated:(NSNotification*)notification
{
    //NSLog(@"NarouContentReadingPointUpdated Up!");
    dispatch_async(m_MainDispatchQueue, ^{
        [self UpdateReadingProgressView:m_Ncode];
    });
}

@end
