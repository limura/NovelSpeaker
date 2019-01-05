//
//  SpeechWaitSettingTableViewController.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SpeechWaitConfigCacheData.h"
@interface SpeechWaitSettingTableViewController : UITableViewController<UINavigationControllerDelegate>
{
    SpeechWaitConfigCacheData* m_SelectedWaitConfig;
}
@end
