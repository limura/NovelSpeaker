//
//  UIViewControllerExtension.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/10/16.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

#import "UIViewControllerExtension.h"

@implementation UIViewController (UIViewControllerExtension)

/// 最前面のUIViewControllerを取得します(nilが帰る可能性があります)
+ (UIViewController*)toplevelViewController:(UIViewController*)controller{
    if (controller == nil) {
        controller = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    if ([controller isMemberOfClass:[UITabBarController class]]) {
        UITabBarController* tbc = (UITabBarController*)controller;
        return [UIViewController toplevelViewController:tbc.selectedViewController];
    }
    if ([controller isMemberOfClass:[UINavigationController class]]) {
        UINavigationController* nc = (UINavigationController*)controller;
        return [UIViewController toplevelViewController:nc.visibleViewController];
    }
    if (controller.presentedViewController != nil) {
        return [UIViewController toplevelViewController:controller.presentedViewController];
    }
    return controller;
}

/// 最前面のUIViewControllerを取得します(nilが帰る可能性があります)
+ (UIViewController*)toplevelViewController{
    return [UIViewController toplevelViewController:nil];
}

@end
