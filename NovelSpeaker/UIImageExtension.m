//
//  UIImageExtension.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/01/05.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

#import "UIImageExtension.h"

@implementation UIImage (UIImageExtension)

// 画像をリサイズします
- (UIImage*)resize:(CGSize)newSize {
    CGFloat wRatio = newSize.width / self.size.width;
    CGFloat hRatio = newSize.height / self.size.height;
    CGFloat ratio = wRatio < hRatio ? wRatio : hRatio;
    CGSize targetSize = CGSizeMake(self.size.width * ratio, self.size.height * ratio);
    UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0);
    [self drawInRect:CGRectMake(0.0, 0.0, targetSize.width, targetSize.height)];
    UIImage* newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

@end
