//
//  EasyAlert.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/23.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EasyAlertActionHolder : NSObject
{
    void(^firstAction)(UIAlertAction*);
    void(^secondAction)(UIAlertAction*);
    UIAlertView* alertView;
    UIAlertController* alertController;
}

- (id)initWithData:(void(^)(UIAlertAction*))FirstAction SecondAction:(void(^)(UIAlertAction*))SecondAction AlertView:(UIAlertView*)AlertView AlertController:(UIAlertController*)AlertController;

- (BOOL)isEqualAlertView:(UIAlertView*)AlertView;
- (BOOL)isEqualAlertController:(UIAlertController*)AlertController;
- (void)runFirstAction:(UIAlertAction*)action;
- (void)runSecondAction:(UIAlertAction*)action;
- (void)CloseAlert:(bool)animate;
@end

@interface EasyAlert : NSObject<UIAlertViewDelegate>
{
    UIViewController* m_ParentViewController;
    NSMutableArray* m_AlertList;
}

- (id)initWithViewController:(UIViewController*)viewController;

/// 選択肢の無い Alert を作成します。
+ (UIAlertController*)CreateAlertNoButton:(NSString*)title message:(NSString*)message;

/// 1つの選択肢を出す Alert を作成します。
+ (UIAlertController*)CreateAlertOneButton:(NSString*)title message:(NSString*)message okButtonText:(NSString*)okButtonText okActionHandler:(void(^)(UIAlertAction *))okActionHandler;

/// 2つの選択肢を出す Alert を作成します。
+ (UIAlertController*)CreateAlertTwoButton:(NSString*)title message:(NSString*)message
                           firstButtonText:(NSString*)firstButtonText firstActionHandler:(void(^)(UIAlertAction *))firstActionHandler
                          secondButtonText:(NSString*)secondButtonText secondActionHandler:(void(^)(UIAlertAction *))secondActionHandler;

/// 何も押せないメッセージを表示します。ハンドラはありません。
/// 返り値として返す EasyAlertActionHolder の CloseAlert method で閉じてください。
- (EasyAlertActionHolder*)ShowAlert:(NSString*)title message:(NSString*)message;

/// 一つの選択肢を出す alert を表示します。ハンドラを一つ受け取ります
- (BOOL)ShowAlertOneButton:(NSString*)title message:(NSString*)message okButtonText:(NSString*)okButtonText okActionHandler:(void(^)(UIAlertAction*))okActionHandler;

/// OK が押せるだけのダイアログを表示します。ハンドラはありません。
- (BOOL)ShowAlertOKButton:(NSString*)title message:(NSString*)message;

/// 2つの選択肢を出す alert を表示します。ハンドラを2つ受け取ります
- (BOOL)ShowAlertTwoButton:(NSString*)title message:(NSString*)message firstButtonText:(NSString*)firstButtonText firstActionHandler:(void(^)(UIAlertAction*))firstActionHandler secondButtonText:(NSString*)secondButtonText secondActionHandler:(void(^)(UIAlertAction*))secondActionHandler;

@end
