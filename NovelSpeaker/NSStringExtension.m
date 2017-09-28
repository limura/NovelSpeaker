//
//  NSStringExtension.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2017/03/31.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

#import "NSStringExtension.h"

@implementation NSString (NSStringNovelSpeakerExtension)

- (NSString*)getFirstContentLine {
    NSString* trimedString = [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    __block NSString* firstLine = nil;
    [trimedString enumerateLinesUsingBlock:^(NSString* line, BOOL* stop){
        firstLine = line;
        *stop = true;
    }];
    return firstLine;
}

@end
