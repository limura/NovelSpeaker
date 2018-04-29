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
    void(^firstAction)(UIAlertAction*_Nullable);
    void(^secondAction)(UIAlertAction*_Nullable);
    UIAlertView* alertView;
    UIAlertController* alertController;
}

- (id _Nullable)initWithData:(void(^_Nullable)(UIAlertAction*_Nullable))FirstAction SecondAction:(void(^_Nullable)(UIAlertAction*_Nullable))SecondAction AlertView:(UIAlertView*_Nullable)AlertView AlertController:(UIAlertController*_Nullable)AlertController;

- (BOOL)isEqualAlertView:(UIAlertView*_Nullable)AlertView;
- (BOOL)isEqualAlertController:(UIAlertController*_Nullable)AlertController;
- (void)runFirstAction:(UIAlertAction*_Nullable)action;
- (void)runSecondAction:(UIAlertAction*_Nullable)action;
- (void)CloseAlert:(bool)animate completion:(void (^ __nullable)(void))completion;

@end

@interface EasyAlert : NSObject<UIAlertViewDelegate>
{
    UIViewController* m_ParentViewController;
    NSMutableArray* m_AlertList;
}

- (id _Nullable)initWithViewController:(UIViewController*_Nonnull)viewController;

/// 選択肢の無い Alert を作成します。
+ (UIAlertController*_Nullable)CreateAlertNoButton:(NSString*_Nullable)title message:(NSString*_Nullable)message;

/// 1つの選択肢を出す Alert を作成します。
+ (UIAlertController*_Nullable)CreateAlertOneButton:(NSString*_Nullable)title message:(NSString*_Nullable)message okButtonText:(NSString*_Nullable)okButtonText okActionHandler:(void(^_Nullable)(UIAlertAction *_Nullable))okActionHandler;

/// 2つの選択肢を出す Alert を作成します。
+ (UIAlertController*_Nullable)CreateAlertTwoButton:(NSString*_Nullable)title message:(NSString*_Nullable)message
                           firstButtonText:(NSString*_Nullable)firstButtonText firstActionHandler:(void(^_Nullable)(UIAlertAction *_Nullable))firstActionHandler
                          secondButtonText:(NSString*_Nullable)secondButtonText secondActionHandler:(void(^_Nullable)(UIAlertAction *_Nullable))secondActionHandler;

/// 何も押せないメッセージを表示します。ハンドラはありません。
/// 返り値として返す EasyAlertActionHolder の CloseAlert method で閉じてください。
- (EasyAlertActionHolder*_Nullable)ShowAlert:(NSString*_Nullable)title message:(NSString*_Nullable)message;

/// 何も押せないメッセージを表示して、このメッセージは指定された時間後に勝手に消えます
- (BOOL)ShowAlertAutoFade:(NSString*_Nullable)title message:(NSString*_Nullable)message delayInSeconds:(double)delayInSeconds;

/// 一つの選択肢を出す alert を表示します。ハンドラを一つ受け取ります
- (BOOL)ShowAlertOneButton:(NSString*_Nullable)title message:(NSString*_Nullable)message okButtonText:(NSString*_Nullable)okButtonText okActionHandler:(void(^_Nullable)(UIAlertAction*_Nullable))okActionHandler;

/// OK が押せるだけのダイアログを表示します。ハンドラはありません。
- (BOOL)ShowAlertOKButton:(NSString*_Nullable)title message:(NSString*_Nullable)message;

/// 2つの選択肢を出す alert を表示します。ハンドラを2つ受け取ります
- (BOOL)ShowAlertTwoButton:(NSString*_Nullable)title message:(NSString*_Nullable)message firstButtonText:(NSString*_Nullable)firstButtonText firstActionHandler:(void(^_Nullable)(UIAlertAction*_Nullable))firstActionHandler secondButtonText:(NSString*_Nullable)secondButtonText secondActionHandler:(void(^_Nullable)(UIAlertAction*_Nullable))secondActionHandler;

@end
