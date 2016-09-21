//
//  NSDataZlibExtension.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/22.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (NSDataZlibExtension)

// from http://qiita.com/odaman68000/items/d33096abfa1d9e8f6aca
- (id)deflate:(int)compressionLevel;
- (id)inflate;

@end
