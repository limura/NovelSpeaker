//
//  BookShelfTableViewCell.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/13.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NarouDownloadQueue.h"

@interface BookShelfTableViewCell : UITableViewCell<NarouDownloadQueueDelegate>
{
    NSString* m_Ncode;
}

@property (weak, nonatomic) IBOutlet UILabel *TitleLabel;
@property (weak, nonatomic) IBOutlet UILabel *NewIndicatorLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *DownloadProgressView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *DownloadActivityIndicatorView;

- (void)initWithTitleLabel:(NSString*)titleLabel ncode:(NSString*)ncode;

- (void)NewIndicatorEnable;

- (void)NewIndicatorDisable;


@end
