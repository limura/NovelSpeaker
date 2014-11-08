//
//  TextSizeSettingViewController.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/11/08.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TextSizeSettingViewController : UIViewController
{
    UIFont* font;
}
@property (weak, nonatomic) IBOutlet UISlider *textSizeSlider;
@property (weak, nonatomic) IBOutlet UITextView *sampleTextTextView;

- (IBAction)textSizeSliderMoved:(id)sender;
@end
