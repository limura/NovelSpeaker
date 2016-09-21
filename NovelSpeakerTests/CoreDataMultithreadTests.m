//
//  CoreDataMultithreadTests.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/11/03.
//  Copyright © 2015年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GlobalDataSingleton.h"

#import "UriLoader.h"

@interface CoreDataMultithreadTests : XCTestCase

@end

@implementation CoreDataMultithreadTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

/*
- (void)testCoreDataMultithread {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    dispatch_queue_t mainQueue = dispatch_queue_create("mainThreadQueue", NULL);
    dispatch_queue_t subQueue = dispatch_queue_create("subThreadQueue", DISPATCH_QUEUE_CONCURRENT);
}
 */

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

- (void)testXPath {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL done = false;
    __block NSArray* dataArray = nil;
    
    UriLoader* uriLoader = [UriLoader new];
    [uriLoader SetMaxDepth:3];
    NSURL* siteInfoUrl = [[NSURL alloc] initWithString:@"http://wedata.net/databases/AutoPagerize/items.json"];
    [uriLoader AddSiteInfoFromURL:siteInfoUrl successAction:^(){
        NSLog(@"add siteinfo success.");
        NSURL* targetURL = [[NSURL alloc] initWithString:@"https://kakuyomu.jp/works/1177354054880210298/episodes/1177354054880210374"];
        [uriLoader LoadURL:targetURL successAction:^(NSArray* result){
            NSLog(@"LoadURL success:");
            dataArray = result;
            done = true;
            dispatch_semaphore_signal(semaphore);
        } failedAction:^(NSURL* url){
            NSLog(@"LoadURL failed: %@", [url absoluteString]);
            done = true;
            dispatch_semaphore_signal(semaphore);
        }];
    } failedAction:^(NSURL* url){
        NSLog(@"add siteinfo failed: %@", [url absoluteString]);
        done = true;
        dispatch_semaphore_signal(semaphore);
    }];

    while(dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW)){
        // http://stackoverflow.com/questions/13620128/block-main-thread-dispatch-get-main-queue-and-or-not-run-currentrunloop
        // で知ったのだけれど、これを呼んであげないと block してしまう……[NSThread sleep] みたいなので行けるのかと思ったら違った。(´・ω・`)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    //[NSThread sleepForTimeInterval:5];
    for (NSString* content in dataArray) {
        NSLog(@"%@", content);
    }
}

- (void)testGCD{
    dispatch_queue_t backgroundQueue1 = dispatch_queue_create("queue1", DISPATCH_QUEUE_CONCURRENT);
    //dispatch_queue_t backgroundQueue2 = dispatch_queue_create("queue2", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    
    XCTAssertTrue([NSThread isMainThread]);
    for (int i = 0; i < 10; i++) {
        dispatch_async(backgroundQueue1, ^{
            [NSThread sleepForTimeInterval:1];
            XCTAssertTrue(![NSThread isMainThread]);
            dispatch_async(mainQueue, ^{
                [NSThread sleepForTimeInterval:0.5];
                XCTAssertTrue([NSThread isMainThread]);
            });
        });
    }
    [NSThread sleepForTimeInterval:3];
}

@end
