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
#import "NovelSpeaker-Swift.h"

@interface BookShelfTableViewController : UITableViewController<NarouDownloadQueueDelegate, UINavigationControllerDelegate>
{
    NarouContentCacheData* m_NextViewDetail;
    BOOL m_isNextViewNeedResumeSpeech;
    NarouContentSortType m_SortType;
    UIRefreshControl* m_UIRefreshControl;
    NSString* m_SearchString;
    UIBarButtonItem* m_SearchButton;
    FloatingButton* m_ResumeSpeechFloatingButton;
}
@end
