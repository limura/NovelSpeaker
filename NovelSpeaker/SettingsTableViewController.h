//
//  SettingsTableViewController.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EasyAlert.h"
#import "NarouContentCacheData.h"
#import <MessageUI/MessageUI.h>

@interface SettingsTableViewController : UITableViewController<MFMailComposeViewControllerDelegate>
{
    EasyAlert* m_EasyAlert;
    
    NarouContentCacheData* m_EditUserBookViewNarouContent;
}
@property (strong, nonatomic) IBOutlet UITableView *settingsTableView;
@end
