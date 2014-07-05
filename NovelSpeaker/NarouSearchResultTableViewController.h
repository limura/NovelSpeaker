//
//  NarouLoadTableViewController.h
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/07/01.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "NarouContentAllData.h"

@interface NarouSearchResultTableViewController : UITableViewController
{
    NarouContentAllData* m_NextViewDetail;
}
@property NSArray* SearchResultList;

@end
