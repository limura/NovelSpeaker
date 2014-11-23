//
//  EasyAlert.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/23.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "EasyAlert.h"

/// UIAlertView は iOS8 から使わないほうが良くなるらしいので、
/// とりあえずwrapperを書いておきます
@implementation EasyAlert

/// 選択肢の無い Alert を作成します。
+ (UIAlertController*)CreateAlertNoButton:(NSString*)title message:(NSString*)message
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    return alert;
}

/// 1つの選択肢を出す Alert を作成します。
+ (UIAlertController*)CreateAlertOneButton:(NSString*)title message:(NSString*)message okButtonText:(NSString*)okButtonText okActionHandler:(void(^)(UIAlertAction *))okActionHandler
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:okButtonText style:UIAlertActionStyleDefault handler:okActionHandler]];
    return alert;
}

/// 2つの選択肢を出す Alert を作成します。
+ (UIAlertController*)CreateAlertTwoButton:(NSString*)title message:(NSString*)message
    firstButtonText:(NSString*)firstButtonText firstActionHandler:(void(^)(UIAlertAction *))firstActionHandler
    secondButtonText:(NSString*)secondButtonText secondActionHandler:(void(^)(UIAlertAction *))secondActionHandler
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:firstButtonText style:UIAlertActionStyleDefault handler:firstActionHandler]];
    [alert addAction:[UIAlertAction actionWithTitle:secondButtonText style:UIAlertActionStyleDefault handler:secondActionHandler]];
    return alert;
}

///

@end
