//
//  NovelSpeakerTests.m
//  NovelSpeakerTests
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GlobalDataSingleton.h"

@interface NovelSpeakerTests : XCTestCase

@end

@implementation NovelSpeakerTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample
{
    //XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

- (void)testCurrentReadingStoryClearBug_Issue22
{
    // まずはテキトーな小説をダウンロードする
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    [globalData AddDownloadQueueForNarouNcode:@""];
}

@end
