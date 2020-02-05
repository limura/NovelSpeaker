//
//  EasyShere.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/02/18.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import "EasyShare.h"

@implementation EasyShare

/// 文字列をシェアします。
+ (void)ShareText:(NSString*)message viewController:(UIViewController*)viewController barButton:(UIBarButtonItem*)barButton
{
    UIActivityViewController* activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[message]
                                                     applicationActivities:nil];
    
    // iOS8 からのもの。
    float iOSVersion = [[[UIDevice currentDevice] systemVersion] floatValue];
    if (iOSVersion >= 8.0) {
        [activityViewController setCompletionWithItemsHandler:^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
            if (activityError) {
                NSLog(@"%@", activityError);
                return;
            }
        }];
        
        if (barButton != nil) {
            activityViewController.popoverPresentationController.barButtonItem = barButton;
        }else{
            CGRect frame = [[UIScreen mainScreen] bounds];
            activityViewController.popoverPresentationController.sourceView = viewController.view;
            activityViewController.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(frame)-60,frame.size.height-50, 120,50);;
        }
    }
    
    viewController.modalPresentationStyle = UIModalPresentationFullScreen;
    [viewController presentViewController:activityViewController
                       animated:YES
                     completion:nil];
}
@end
