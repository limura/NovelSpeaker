//
//  CoreDataMultithreadTests.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2015/11/03.
//  Copyright © 2015年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "GlobalDataSingleton.h"

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

- (void)testCoreDataMultithread {
    GlobalDataSingleton* globalData = [GlobalDataSingleton GetInstance];
    dispatch_queue_attr_t mainQueue = dispatch_queue_create("mainThreadQueue", NULL);
    dispatch_queue_attr_t subQueue = dispatch_queue_create("subThreadQueue", NULL);
    
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
