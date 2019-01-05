//
//  UIImageExtension.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/01/05.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (UIImageExtension)

// 画像をリサイズします
- (UIImage*)resize:(CGSize)newSize;

@end

NS_ASSUME_NONNULL_END
