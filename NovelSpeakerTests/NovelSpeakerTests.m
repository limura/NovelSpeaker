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
    // http://ncode.syosetu.com/n5693dn/
    NSString* targetNcode = @"N5693DN";
    /*
    [globalData AddDownloadQueueForNarouNcode:targetNcode];
    [NSThread sleepForTimeInterval:3.0f];
    
    NarouContentCacheData* content = [globalData SearchNarouContentFromNcode:targetNcode];
    XCTAssertTrue(content != nil, @"content is nil");
    
    StoryCacheData* story1 = [globalData SearchStory:targetNcode chapter_no:2];
    [globalData UpdateReadingPoint:content story:story1];

    NarouContentCacheData* currentReadingContent = [globalData GetCurrentReadingContent];
    XCTAssertTrue([targetNcode compare:currentReadingContent.ncode] == NSOrderedSame, @"current reading content is not same ncode");
    XCTAssertTrue(currentReadingContent.currentReadingStory != nil, @"current reading story is nil take 1");
    XCTAssertTrue([currentReadingContent.currentReadingStory.chapter_number intValue] != 1, @"current reading story chapter number is not 1 take 1");
     */

    // 最後？の章を消します
    //StoryCacheData* story2 = [globalData SearchStory:targetNcode chapter_no:3];
    //[globalData DeleteStory:story2];
/*
    currentReadingContent = [globalData GetCurrentReadingContent];
    XCTAssertTrue([targetNcode compare:currentReadingContent.ncode] == NSOrderedSame, @"current reading content is not same ncode take 2");
    XCTAssertTrue(currentReadingContent.currentReadingStory != nil, @"current reading story is nil take 2");
    XCTAssertTrue([currentReadingContent.currentReadingStory.chapter_number intValue] != 1, @"current reading story chapter number is not 1 take 2");

    // 再度ダウンロードします
    [globalData AddDownloadQueueForNarouNcode:targetNcode];
    [NSThread sleepForTimeInterval:3.0f];

    currentReadingContent = [globalData GetCurrentReadingContent];
    XCTAssertTrue([targetNcode compare:currentReadingContent.ncode] == NSOrderedSame, @"current reading content is not same ncode take 3");
    XCTAssertTrue(currentReadingContent.currentReadingStory != nil, @"current reading story is nil take 3");
    XCTAssertTrue([currentReadingContent.currentReadingStory.chapter_number intValue] != 1, @"current reading story chapter number is not 1 take 3");
 */
}

- (void)testURLDownload {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    NSString* result = [globalData AddDownloadQueueForURL:[[NSURL alloc] initWithString:@"https://kakuyomu.jp/works/1177354054880210298/episodes/1177354054880210374"]];
}

@end
