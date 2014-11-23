//
//  EasyAlert.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/23.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EasyAlert : NSObject

/// 選択肢の無い Alert を作成します。
+ (UIAlertController*)CreateAlertNoButton:(NSString*)title message:(NSString*)message;

/// 1つの選択肢を出す Alert を作成します。
+ (UIAlertController*)CreateAlertOneButton:(NSString*)title message:(NSString*)message okButtonText:(NSString*)okButtonText okActionHandler:(void(^)(UIAlertAction *))okActionHandler;

/// 2つの選択肢を出す Alert を作成します。
+ (UIAlertController*)CreateAlertTwoButton:(NSString*)title message:(NSString*)message
                           firstButtonText:(NSString*)firstButtonText firstActionHandler:(void(^)(UIAlertAction *))firstActionHandler
                          secondButtonText:(NSString*)secondButtonText secondActionHandler:(void(^)(UIAlertAction *))secondActionHandler;

@end
