//
//  PickerViewDialog.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/07/30.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import "PickerViewDialog.h"

@implementation PickerViewDialog

+ (UIView*)searchRootView:(UIView*)view {
    while (view != nil) {
        if (view.superview == nil) {
            return view;
        }
        view = view.superview;
    }
    return nil;
}

// 新しく PickerViewDialog の UIView を作成します。
+ (instancetype)createNewDialog:(NSArray*)displayTextArray firstSelectedString:(NSString*)firstSelectedString parentView:(UIView*)parentView resultReceiver:(void (^)(NSString*))resultReceiver {
    // .xib から nib を作ってそれの UIView を取り出して返す
    UINib* nib = [UINib nibWithNibName:NSStringFromClass([self class]) bundle:nil];
    if (nib == nil) {
        return nil;
    }
    PickerViewDialog* view = [nib instantiateWithOwner:self options:nil][0];
    if (view == nil) {
        return nil;
    }
    [view setDisplayTextArray:displayTextArray firstSelectedString:firstSelectedString];
    [view setResultReceiver:resultReceiver];
    
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    view.bounds = CGRectMake(0, 0, screenSize.width, screenSize.height);
    view.frame = CGRectMake(0, screenSize.height, screenSize.width, screenSize.height);
    view.accessibilityViewIsModal = true;
    UIView* rootView = [PickerViewDialog searchRootView:parentView];
    if (rootView != nil) {
        parentView = rootView;
    }
    [parentView addSubview:view];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, view);

    return view;
}

+ (UIView*)getToplevelView:(UIView*)currentView {
    if (currentView == nil) {
        NSLog(@"search toplevelView failed. currentView is nil!!!!");
        return nil;
    }
    while(currentView.superview != nil) {
        currentView = currentView.superview;
    }
    return currentView;
}

- (void)setDisplayTextArray:(NSArray*)displayTextArray firstSelectedString:(NSString*)firstSelectedString {
    m_DisplayTextArray = displayTextArray;
    if (firstSelectedString != nil) {
        for (int i = 0; i < [m_DisplayTextArray count]; i++) {
            if ([m_DisplayTextArray[i] compare:firstSelectedString] == NSOrderedSame) {
                [self.PickerView selectRow:i inComponent:0 animated:false];
                return;
            }
        }
    }
    if ([m_DisplayTextArray count] > 0) {
        [self.PickerView selectRow:[m_DisplayTextArray count] / 2 inComponent:0 animated:false];
    }
}

- (void)setResultReceiver:(void (^)(NSString*))resultReceiver {
    m_ResultReceiver = resultReceiver;
}

- (void)popup:(void(^)(void))completeTime{
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    [UIView animateWithDuration:0.2f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.bounds = CGRectMake(0, 0, screenSize.width, screenSize.height);
        self.frame = CGRectMake(0, 0, screenSize.width, screenSize.height);
    }completion:^(BOOL b){
        if (completeTime != nil) {
            completeTime();
        }
    }];
}

- (void)popdown:(void(^)(void))completeTime {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    [UIView animateWithDuration:0.2f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.bounds = CGRectMake(0, 0, screenSize.width, screenSize.height);
        self.frame = CGRectMake(0, screenSize.height, screenSize.width, screenSize.height);
    }completion:^(BOOL b){
        if (completeTime != nil) {
            completeTime();
        }
    }];
}

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.PickerView.dataSource = self;
    self.PickerView.delegate = self;
}

- (NSString*)GetRowText:(NSInteger)row {
    if (m_DisplayTextArray == nil || [m_DisplayTextArray count] <= row || row < 0) {
        return @"-";
    }
    return m_DisplayTextArray[row];
}

- (NSString*)GetSelectedString {
    NSInteger selectedRow = [self.PickerView selectedRowInComponent:0];
    return [self GetRowText: selectedRow];
}

// UIPickerView の列数を返す
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView*)pickerView
{
    return 1;
}

// UIPickerView の行数を返す
- (NSInteger)pickerView:(UIPickerView*)pickerView numberOfRowsInComponent:(NSInteger)component
{
    return [m_DisplayTextArray count];
}

// UIPickerView に表示される値を返す
- (NSString*)pickerView:(UIPickerView*)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return [self GetRowText:row];
}

- (void)doneButtonClicked{
    if (m_ResultReceiver) {
        m_ResultReceiver([self GetSelectedString]);
    }
    [self popdown:^{
        [self removeFromSuperview];
    }];
}

- (IBAction)doneButtonClicked:(id)sender {
    //[self doneButtonClicked];
    [self popdown:^{
        [self removeFromSuperview];
    }];
}
- (IBAction)doneButtonBottomClicked:(id)sender {
    //[self doneButtonClicked];
    [self popdown:^{
        [self removeFromSuperview];
    }];
}
- (IBAction)okButtonClicked:(id)sender {
    [self doneButtonClicked];
}
- (IBAction)cancelButtonClicked:(id)sender {
    [self popdown:^{
        [self removeFromSuperview];
    }];
}


@end

