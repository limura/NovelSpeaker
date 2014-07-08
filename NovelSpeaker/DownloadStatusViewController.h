//
//  DownloadStatusViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "GlobalDataSingleton.h"

@interface DownloadStatusViewController : UIViewController<NarouDownloadQueueDelegate, UITableViewDataSource, UITableViewDelegate>

@property (weak, nonatomic) IBOutlet UILabel *DownloadingTitleLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *DownloadingProgressView;
@property (weak, nonatomic) IBOutlet UILabel *DownloadingProgressLabel;
@property (weak, nonatomic) IBOutlet UILabel *ErrorLabel;
@property (weak, nonatomic) IBOutlet UITableView *WaitDownloadQueueTableView;
@property (weak, nonatomic) IBOutlet UITableView *DownloadWaitingQueueTableView;

@end
