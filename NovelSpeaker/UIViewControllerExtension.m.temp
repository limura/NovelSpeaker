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
    UIViewController* view = controller;
    if (view == nil) {
        view = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    if ([controller isMemberOfClass:[UITabBarController class]]) {
        UITabBarController* tbc = (UITabBarController*)controller;
        view = [UIViewController toplevelViewController:tbc.selectedViewController];
        return view;
    }
    if ([controller isMemberOfClass:[UINavigationController class]]) {
        UINavigationController* nc = (UINavigationController*)controller;
        view = [UIViewController toplevelViewController:nc.visibleViewController];
        return view;
    }
    if (controller.presentedViewController != nil) {
        view = [UIViewController toplevelViewController:controller.presentedViewController];
        return view;
    }
    return view;
}

/// 最前面のUIViewControllerを取得します(nilが帰る可能性があります)
+ (UIViewController*)toplevelViewController{
    return [UIViewController toplevelViewController:nil];
}

@end
