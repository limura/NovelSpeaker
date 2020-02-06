//
//  SpeechWaitConfig.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/01/12.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface SpeechWaitConfig : NSManagedObject

@property (nonatomic, retain) NSString * targetText;
@property (nonatomic, retain) NSNumber * delayTimeInSec;

@end
