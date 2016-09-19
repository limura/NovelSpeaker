//
//  NiftyUtility.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/19.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "NiftyUtility.h"

@implementation NiftyUtility

/// UIButton に表示される文字列を変更します
+ (void)setUIButtonText:(UIButton*)button text:(NSString*)text {
    [button setTitle:text forState:UIControlStateNormal];
    [button setTitle:text forState:UIControlStateFocused];
    [button setTitle:text forState:UIControlStateDisabled];
    [button setTitle:text forState:UIControlStateReserved];
    [button setTitle:text forState:UIControlStateSelected];
    [button setTitle:text forState:UIControlStateApplication];
    [button setTitle:text forState:UIControlStateHighlighted];
}

@end
