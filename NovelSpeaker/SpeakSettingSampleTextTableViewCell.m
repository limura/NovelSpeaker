//
//  SpeakSettingSampleTextTableViewCell.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/15.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "SpeakSettingSampleTextTableViewCell.h"

@implementation SpeakSettingSampleTextTableViewCell

- (void)awakeFromNib
{
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}
- (IBAction)sampleTextTextFieldDidEndOnExit:(id)sender {
    // キーボードを閉じる
    [sender resignFirstResponder];
    
    [self.testSpeakDelegate testSpeakSampleTextUpdate:self.sampleTextTextField.text];
}

@end
