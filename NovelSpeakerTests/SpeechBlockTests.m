//
//  SpeechBlockTests.m
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2018/10/09.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SpeechBlock.h"

@interface SpeechBlockTests : XCTestCase

@end

@implementation SpeechBlockTests

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}
/*
- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}
 */

- (void)testConvertSpeakRangeToDisplayRange {
    SpeechBlock* block = [SpeechBlock new];
    [block AddDisplayText:@"あいうえお" speechText:@"あいうえおかきくけこ"];
    NSRange range;
    
    for (int j = 0; j < 5; j++) {
        for (int i = 0; i < 10 - j; i++) {
            range = [block ConvertSpeakRangeToDisplayRange:NSMakeRange(j, i)];
            NSLog(@"speak->display %d,%d: %lu, %lu", j, i, (unsigned long)range.location, (unsigned long)range.length);
        }
        for (int i = 0; i < 5 - j; i++) {
            range = [block ConvertDisplayRangeToSpeakRange:NSMakeRange(j, i)];
            NSLog(@"display->speak %d,%d: %lu, %lu", j, i, (unsigned long)range.location, (unsigned long)range.length);
        }
        
        block = [SpeechBlock new];
        [block AddDisplayText:@"あいうえお" speechText:@"あいう"];
        for (int i = 0; i < 3 - j; i++) {
            range = [block ConvertSpeakRangeToDisplayRange:NSMakeRange(j, i)];
            NSLog(@"speak->display %d,%d: %lu, %lu", j, i, (unsigned long)range.location, (unsigned long)range.length);
        }
        for (int i = 0; i < 5 - j; i++) {
            range = [block ConvertDisplayRangeToSpeakRange:NSMakeRange(j, i)];
            NSLog(@"display->speak %d,%d: %lu, %lu", j, i, (unsigned long)range.location, (unsigned long)range.length);
        }
    }
}

@end
