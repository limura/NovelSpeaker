//
//  UpdateLogViewController.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/05/04.
//  Copyright (c) 2015年 IIMURA Takuji. All rights reserved.
//

#import "UpdateLogViewController.h"

@interface UpdateLogViewController ()

@end

@implementation UpdateLogViewController

- (void)AssignUpdateLog
{
    self.LogTextView.text = NSLocalizedString(@"UpdateLogViewController_UpdateLog", @"update log");
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [self AssignUpdateLog];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
