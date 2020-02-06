//
//  LPPerformanceChecker.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/10/26.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LPPerformanceChecker : NSObject

/// block の実行時間を測定します。logTimeInterval 以上の時間が経っていたら、comment つきの時間 Log を NSLog() で吐きます。
+ (NSTimeInterval)CheckTimeInterval:(NSString*)comment logTimeInterval:(NSTimeInterval)logTimeInterval block:(void(^)(void))block;

/// 今が startDate からみて logTimeInterval の時間が経っていたら、comment つきの時間 Log を NSLog() で吐きます。
+ (NSTimeInterval)CheckTimeInterval:(NSString*)comment startDate:(NSDate*)startDate logTimeInterval:(NSTimeInterval)logTimeInterval;

@end
