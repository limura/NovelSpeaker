//
//  UIViewControllerExtension.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/10/16.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UIViewController (UIViewControllerExtension)

/// 最前面のUIViewControllerを取得します。(nilが帰る可能性があります)
+ (UIViewController*)toplevelViewController;

@end
