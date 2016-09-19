//
//  BookShelfTableViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/07/05.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NarouContentCacheData.h"
#import "GlobalDataSingleton.h"

@interface BookShelfTableViewController : UITableViewController<NarouDownloadQueueDelegate, UINavigationControllerDelegate>
{
    NarouContentCacheData* m_NextViewDetail;
    NarouContentSortType m_SortType;
}
@end
