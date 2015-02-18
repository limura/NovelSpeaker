//
//  EasyShere.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/02/18.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EasyShare : NSObject

/// 文字列をシェアします。
+ (void)ShareText:(NSString*)message viewController:(UIViewController*)viewController barButton:(UIBarButtonItem*)barButton;

@end
