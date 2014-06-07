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
}
@property (weak, nonatomic) IBOutlet UITextView *textView;
@end
