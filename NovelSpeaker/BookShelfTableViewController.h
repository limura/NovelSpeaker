//
//  BookShelfTableViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NarouContentAllData.h"
#import "GlobalDataSingleton.h"

@interface BookShelfTableViewController : UITableViewController<NarouDownloadQueueDelegate>
{
    NarouContentAllData* m_NextViewDetail;
}
@end
