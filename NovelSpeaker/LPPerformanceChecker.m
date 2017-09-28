//
//  LPPerformanceChecker.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/10/26.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "LPPerformanceChecker.h"

@implementation LPPerformanceChecker

/// block の実行時間を測定します。logTimeInterval 以上の時間が経っていたら、comment つきの時間 Log を NSLog() で吐きます。
+ (NSTimeInterval)CheckTimeInterval:(NSString*)comment logTimeInterval:(NSTimeInterval)logTimeInterval block:(void(^)(void))block{
    NSDate* startDate = [NSDate date];
    if (block != nil) {
        block();
    }
    return [LPPerformanceChecker CheckTimeInterval:comment startDate:startDate logTimeInterval:logTimeInterval];
}

/// 今が startDate からみて logTimeInterval の時間が経っていたら、comment つきの時間 Log を NSLog() で吐きます。
+ (NSTimeInterval)CheckTimeInterval:(NSString*)comment startDate:(NSDate*)startDate logTimeInterval:(NSTimeInterval)logTimeInterval
{
    NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:startDate];
    if (interval > logTimeInterval) {
        NSLog(@"%@ %f", comment, interval);
    }
    return interval;
}

@end
