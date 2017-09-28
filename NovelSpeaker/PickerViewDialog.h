//
//  PickerViewDialog.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/30.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PickerViewDialog : UIView<UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource>
{
    NSArray* m_DisplayTextArray;
    void (^m_ResultReceiver)(NSString*);
}
@property (weak, nonatomic) IBOutlet UIPickerView *PickerView;
@property (weak, nonatomic) IBOutlet UIButton *doneButton;
@property (weak, nonatomic) IBOutlet UIButton *doneButtonBottom;

/// 新しく PickerViewDialog の UIView を作成します
+ (instancetype)createNewDialog:(NSArray*)displayTextArray firstSelectedString:(NSString*)firstSelectedString parentView:(UIView*)parentView resultReceiver:(void (^)(NSString*))resultReceiver;

/// 下からにゅるっと表示させます
- (void)popup:(void(^)(void))completeTime;
/// 表示しているなら、画面外に消えます
- (void)popdown:(void(^)(void))completeTime;


@end
