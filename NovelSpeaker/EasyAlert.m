//
//  EasyAlert.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/23.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "EasyAlert.h"

@implementation EasyAlertActionHolder
- (id)initWithData:(void(^)(UIAlertAction*))FirstAction SecondAction:(void(^)(UIAlertAction*))SecondAction AlertView:(UIAlertView*)AlertView AlertController:(UIAlertController*)AlertController
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    firstAction = FirstAction;
    secondAction = SecondAction;
    alertView = AlertView;
    alertController = AlertController;
    
    return self;
}

- (BOOL)isEqualAlertView:(UIAlertView*)AlertView
{
    return AlertView == alertView;
}
- (BOOL)isEqualAlertController:(UIAlertController *)AlertController
{
    return AlertController == alertController;
}
- (void)runFirstAction:(UIAlertAction*)action
{
    if (firstAction == nil) {
        return;
    }
    firstAction(action);
}
- (void)runSecondAction:(UIAlertAction*)action
{
    if (secondAction == nil) {
        return;
    }
    secondAction(action);
}

- (void)CloseAlert:(bool)animate completion:(void (^ __nullable)(void))completion
{
    if (alertView != nil) {
        [alertView dismissWithClickedButtonIndex:0 animated:animate];
        completion();
        return;
    }
    if (alertController != nil) {
        [alertController dismissViewControllerAnimated:animate completion:completion];
    }
}


@end

/// UIAlertView は iOS8 から使わないほうが良くなるらしいので、
/// とりあえずwrapperを書いておきます
// ただ、iOS7 には UIAlertController が無いようなので、駄目そうな時には UIAlertView を使うような形にします。
@implementation EasyAlert

- (id)initWithViewController:(UIViewController*)viewController
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    m_ParentViewController = viewController;
    m_AlertList = [NSMutableArray new];
    
    return self;
}

/// alertView がクリックされた時のイベントハンドラ
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    for (EasyAlertActionHolder* holder in m_AlertList) {
        if ([holder isEqualAlertView:alertView]){
            switch (buttonIndex) {
                case 0:
                    [holder runFirstAction:nil];
                    break;
                case 1:
                    [holder runSecondAction:nil];
                    break;
                default:
                    break;
            }
            [m_AlertList removeObject:holder];
            return;
        }
    }
}

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

/// EasyAlertActionHolder を追加します
- (void)AddEasyAlertActionHolder:(EasyAlertActionHolder*)holder
{
    [m_AlertList addObject:holder];
}

/// 何も押せないメッセージを表示します。ハンドラはありません。
/// 返り値として返す EasyAlertActionHolder の CloseAlert method で閉じてください。
- (EasyAlertActionHolder*)ShowAlert:(NSString*)title message:(NSString*)message
{
    UIAlertController* alertController = [EasyAlert CreateAlertNoButton:title message:message];
    if (alertController != nil) {
        [m_ParentViewController presentViewController:alertController animated:false completion:nil];
        return [[EasyAlertActionHolder alloc] initWithData:nil SecondAction:nil AlertView:nil AlertController:alertController];
    }
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:nil otherButtonTitles:nil];
    if (alertView != nil) {
        [alertView show];
        return [[EasyAlertActionHolder alloc] initWithData:nil SecondAction:nil AlertView:alertView AlertController:nil];
    }
    return nil;
}

/// 何も押せないメッセージを表示して、このメッセージは指定された時間後に勝手に消えます
- (BOOL)ShowAlertAutoFade:(NSString*)title message:(NSString*)message delayInSeconds:(double)delayInSeconds
{
    EasyAlertActionHolder* holder = [self ShowAlert:title message:message];
    if (holder == nil) {
        return false;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [holder CloseAlert:false completion:nil];
    });
    return true;
}

/// 一つの選択肢を出す alert を表示します。ハンドラを一つ受け取ります
- (BOOL)ShowAlertOneButton:(NSString*)title message:(NSString*)message okButtonText:(NSString*)okButtonText okActionHandler:(void(^)(UIAlertAction*))okActionHandler
{
    UIAlertController* alertController = [EasyAlert CreateAlertOneButton:title message:message okButtonText:okButtonText okActionHandler:okActionHandler];
    if (alertController != nil) {
        [m_ParentViewController presentViewController:alertController animated:false completion:nil];
        return true;
    }
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:nil otherButtonTitles:okButtonText, nil];
    if (alertView != nil) {
        EasyAlertActionHolder* holder = [[EasyAlertActionHolder alloc] initWithData:okActionHandler SecondAction:nil AlertView:alertView AlertController:nil];
        [self AddEasyAlertActionHolder:holder];
        [alertView show];
        return true;
    }
    return false;
}

/// OK が押せるだけのダイアログを表示します。ハンドラはありません。
- (BOOL)ShowAlertOKButton:(NSString*)title message:(NSString*)message
{
    return [self ShowAlertOneButton:title message:message okButtonText:NSLocalizedString(@"OK_button", @"OK") okActionHandler:nil];
}

/// 2つの選択肢を出す alert を表示します。ハンドラを2つ受け取ります
- (BOOL)ShowAlertTwoButton:(NSString*)title message:(NSString*)message firstButtonText:(NSString*)firstButtonText firstActionHandler:(void(^)(UIAlertAction*))firstActionHandler secondButtonText:(NSString*)secondButtonText secondActionHandler:(void(^)(UIAlertAction*))secondActionHandler
{
    UIAlertController* alertController = [EasyAlert CreateAlertTwoButton:title message:message firstButtonText:firstButtonText firstActionHandler:firstActionHandler secondButtonText:secondButtonText secondActionHandler:secondActionHandler];
    if (alertController != nil) {
        [m_ParentViewController presentViewController:alertController animated:false completion:nil];
        return true;
    }
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:nil otherButtonTitles:firstButtonText, secondButtonText, nil];
    if (alertView != nil) {
        EasyAlertActionHolder* holder = [[EasyAlertActionHolder alloc] initWithData:firstActionHandler SecondAction:secondActionHandler AlertView:alertView AlertController:nil];
        [self AddEasyAlertActionHolder:holder];
        [alertView show];
        return true;
    }
    return false;
}

@end
