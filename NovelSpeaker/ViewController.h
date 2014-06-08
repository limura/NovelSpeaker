//
//  ViewController.h
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Speaker.h"

@interface ViewController : UIViewController<SpeakRangeDelegate>
{
    Speaker* m_Speaker;
    NSInteger m_SpeechStartPosition;
}
@property (weak, nonatomic) IBOutlet UITextView *textView;
@property (weak, nonatomic) IBOutlet UIButton *startStopButton;
@property (weak, nonatomic) IBOutlet UIButton *loadButton;
@end
