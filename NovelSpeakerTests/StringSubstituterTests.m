//
//  StringSubstituterTests.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/10/04.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "StringSubstituter.h"

@interface StringSubstituterTests : XCTestCase

@end

@implementation StringSubstituterTests

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

- (void)testAddSetting
{
    StringSubstituter* substituter = [StringSubstituter new];
    
    XCTAssertTrue([substituter AddSetting_From:@"hoge" to:@"hage"], @"add failed");
}

- (void)testDel
{
    StringSubstituter* substituter = [StringSubstituter new];
    
    XCTAssertTrue([substituter AddSetting_From:@"hoge" to:@"hage"], @"add failed");
    
    XCTAssertFalse([substituter DelSetting:nil]);
    XCTAssertTrue([substituter DelSetting:@"hoge"]);
    
}

- (void)testConvert
{
    StringSubstituter* substituter = [StringSubstituter new];
    
    XCTAssertTrue([substituter AddSetting_From:@"aaaa" to:@"b"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"a" to:@"eeee"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"aaa" to:@"cc"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"aa" to:@"ddd"], @"add failed");
    
    NSString* from = @"aaaa aaa aa a";
    NSString* answer = @"b cc ddd eeee";
    
    NSString* conved = [substituter Convert:from];
    XCTAssertEqual([answer compare:conved], NSOrderedSame, @"conv failed:\n  from:\"%@\"\nanswer:\"%@\"\n    to:\"%@\"", from, answer, conved);
}

- (void)testConvertJP
{
    StringSubstituter* substituter = [StringSubstituter new];
    
    XCTAssertTrue([substituter AddSetting_From:@"ああああ" to:@"い"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"漢" to:@"字字"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"あああ" to:@"文文"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"あ" to:@"いいい"], @"add failed");
    
    NSString* from = @"ああああ あああ 漢漢 あ";
    NSString* answer = @"い 文文 字字字字 いいい";
    
    NSString* conved = [substituter Convert:from];
    XCTAssertEqual([answer compare:conved], NSOrderedSame, @"conv failed:\n  from:\"%@\"\nanswer:\"%@\"\n    to:\"%@\"", from, answer, conved);
}

@end
