//
//  HtmlStory.h
//  novelspeaker
//
//  Created by 飯村卓司 on 2016/09/29.
//  Copyright © 2016年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface HtmlStory : NSData

@property (nonatomic) NSString* url;
@property (nonatomic) NSString* content;
@property (nonatomic) NSString* title;
@property (nonatomic) int count;

@end
