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
    [[GlobalDataSingleton GetInstance] DeleteDownloadEventHandler:self];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

///
- (void)initWithTitleLabel:(NSString*)titleLabel ncode:(NSString*)ncode
{
    self.TitleLabel.text = titleLabel;
    self.TitleLabel.hidden = NO;
    self.NewIndicatorLabel.hidden = YES;
    self.DownloadProgressView.hidden = YES;
    self.DownloadActivityIndicatorView.hidden = YES;
    
    [[GlobalDataSingleton GetInstance] AddDownloadEventHandler:self];
    
    m_Ncode = ncode;
}

/// New! のインジケータを点けます
- (void)NewIndicatorEnable
{
    self.NewIndicatorLabel.hidden = NO;
}

/// New! のインジケータを消します
- (void)NewIndicatorDisable
{
    self.NewIndicatorLabel.hidden = YES;
}

// 個々の章のダウンロードが行われようとする度に呼び出されます。
- (void)DownloadStatusUpdate:(NarouContentCacheData*)content currentPosition:(int)currentPosition maxPosition:(int)maxPosition
{
    if (content == nil || content.ncode == nil || ![content.ncode isEqualToString:m_Ncode] || maxPosition == 0) {
        self.DownloadProgressView.hidden = YES;
        self.DownloadActivityIndicatorView.hidden = YES;
        return;
    }
    float progress = (float)currentPosition / (float)maxPosition;
    self.DownloadProgressView.progress = progress;
    self.DownloadProgressView.hidden = NO;
    self.DownloadActivityIndicatorView.hidden = NO;
}
// 全ての download queue がなくなった時に呼び出されます。
- (void)DownloadEnd
{
    self.DownloadProgressView.hidden = YES;
    self.DownloadActivityIndicatorView.hidden = YES;
}


@end
