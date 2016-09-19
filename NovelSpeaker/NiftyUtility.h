//
//  NiftyUtility.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/19.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NiftyUtility : NSObject

/// UIButton に表示される文字列を変更します。
/// 全ての State を同じ文字列で上書きします。
+ (void)setUIButtonText:(UIButton*)button text:(NSString*)text;

@end
