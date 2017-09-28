//
//  NSDataZlibExtension.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/22.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "NSDataZlibExtension.h"
#import <zlib.h>

@implementation NSData (NSDataZlibExtension)

// from http://qiita.com/odaman68000/items/d33096abfa1d9e8f6aca
- (z_stream)initialized_zStream {
    z_stream zStream;
    zStream.zalloc = Z_NULL;
    zStream.zfree = Z_NULL;
    zStream.opaque = Z_NULL;
    return zStream;
}

- (id)deflate:(int)compressionLevel {
    z_stream zStream = [self initialized_zStream];
    Bytef buffer[131072];
    deflateInit(&zStream, compressionLevel);
    zStream.next_in = (Bytef *)self.bytes;
    zStream.avail_in = (uInt)self.length;
    int retval = Z_OK;
    NSMutableData *ret = [NSMutableData dataWithCapacity:0];
    do {
        zStream.next_out = buffer;
        zStream.avail_out = sizeof(buffer);
        retval = deflate(&zStream, Z_FINISH);
        //if (retval != Z_OK) {
        //    break;
        //}
        size_t length = sizeof(buffer) - zStream.avail_out;
        if (length > 0)
            [ret appendBytes:buffer length:length];
    } while (zStream.avail_out != sizeof(buffer));
    deflateEnd(&zStream);
    return ret;
}

- (id)inflate {
    z_stream zStream = [self initialized_zStream];
    Bytef buffer[131072];
    inflateInit(&zStream);
    zStream.next_in = (Bytef *)self.bytes;
    zStream.avail_in = (uInt)self.length;
    int retval = Z_OK;
    NSMutableData *ret = [NSMutableData dataWithCapacity:0];
    do {
        zStream.next_out = buffer;
        zStream.avail_out = sizeof(buffer);
        retval = inflate(&zStream, Z_FINISH);
        //if (retval != Z_OK) {
        //    return nil;
        //}
        size_t length = sizeof(buffer) - zStream.avail_out;
        if (length > 0)
            [ret appendBytes:buffer length:length];
    } while (zStream.avail_out != sizeof(buffer));
    inflateEnd(&zStream);
    return ret;
}

@end
