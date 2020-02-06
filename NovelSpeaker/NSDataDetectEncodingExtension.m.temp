//
//  NSDataDetectEncodingExtension.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/02/18.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

#import "NSDataDetectEncodingExtension.h"

@implementation NSData (NSDataDetectEncodingExtension)

// https://qiita.com/mosson/items/c4c329d433d99e3583ec
+(NSStringEncoding) detectEncoding:(NSData *)data
{
    NSStringEncoding encoding = NSUTF8StringEncoding;
    NSStringEncoding encodings[] = {
        NSUTF8StringEncoding,
        NSNonLossyASCIIStringEncoding,
        NSShiftJISStringEncoding,
        NSJapaneseEUCStringEncoding,
        NSMacOSRomanStringEncoding,
        NSWindowsCP1251StringEncoding,
        NSWindowsCP1252StringEncoding,
        NSWindowsCP1253StringEncoding,
        NSWindowsCP1254StringEncoding,
        NSWindowsCP1250StringEncoding,
        NSISOLatin1StringEncoding,
        NSUnicodeStringEncoding,
        0
    };
    
    int i = 0;
    NSString *try_str;
    
    if (memchr([data bytes], 0x1b, [data length]) != NULL) {
        try_str = [[NSString alloc] initWithData:data encoding:NSISO2022JPStringEncoding];
        if (try_str != nil)
            return NSISO2022JPStringEncoding;
    }
    
    while(encodings[i] != 0){
        try_str = [[NSString alloc] initWithData:data encoding:encodings[i]];
        if (try_str != nil) {
            encoding = encodings[i];
            break;
        }
        i++;
    }
    return encoding;
}

-(NSStringEncoding) detectEncoding {
    return [NSData detectEncoding:self];
}


@end
