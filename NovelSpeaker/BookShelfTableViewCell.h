//
//  BookShelfTableViewCell.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/13.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NarouDownloadQueue.h"

static NSString* const BookShelfTableViewCellID = @"BookShelfTableViewCell";

@interface BookShelfTableViewCell : UITableViewCell<NarouDownloadQueueDelegate>
{
    dispatch_queue_t m_MainDispatchQueue;
    NSString* m_Ncode;
}

@property (weak, nonatomic) IBOutlet UILabel *TitleLabel;
@property (weak, nonatomic) IBOutlet UIImageView *NewImaveView;
@property (weak, nonatomic) IBOutlet UIProgressView *DownloadProgressView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *ActivityIndicator;

- (void)setTitleLabel:(NSString*)titleLabel ncode:(NSString*)ncode;


@end
