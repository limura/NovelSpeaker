//
//  NiftySpeakerTests.m
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/13.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NiftySpeaker.h"
#import "SpeechBlock.h"

@interface NiftySpeakerTests : XCTestCase
{
}
@end

@implementation NiftySpeakerTests

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

/// SpeechBlock への分割を確認する
- (void)testNiftySpeakerBlockSeparate
{
    //XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
    NiftySpeaker* speaker = [NiftySpeaker new];
    
    SpeechConfig* defaultSpeechConfig = [SpeechConfig new];
    defaultSpeechConfig.pitch = 1.0f;
    defaultSpeechConfig.rate = 0.5f;
    defaultSpeechConfig.beforeDelay = 0.0f;
    [speaker SetDefaultSpeechConfig:defaultSpeechConfig];
    
    SpeechConfig* normalSpeakConfig = [SpeechConfig new];
    normalSpeakConfig.pitch = 1.5f;
    normalSpeakConfig.rate = 0.5f;
    SpeechConfig* specialSpeakConfig = [SpeechConfig new];
    specialSpeakConfig.pitch = 1.2f;
    specialSpeakConfig.rate = 0.5;
    [speaker AddBlockStartSeparator:@"「" endString:@"」" speechConfig:normalSpeakConfig];
    [speaker AddBlockStartSeparator:@"『" endString:@"』" speechConfig:specialSpeakConfig];
    [speaker AddDelayBlockSeparator:@"\r\n\r\n" delay:0.02f];
    //[speaker AddDelayBlockSeparator:@"\n\n" delay:0.1f];
    //[speaker AddDelayBlockSeparator:@"。" delay:0.1f];
    [speaker AddSpeechModText:@"異世界" to:@"イセカイ"];
    [speaker AddSpeechModText:@"術師" to:@"ジュツシ"];

    
    [speaker SetText:@""
     @"異世界\r\n"
     @"\r\n"
     @"「行頭から会話文」\r\n"
     @"「続いて会話文」\r\n"
     @"通常の文章\r\n"
     @"通常の文章の中に「会話文」\r\n"
     @"\r\n"
     @"通常の文章の中に「複数の」「会話文が」紛れる。\r\n"
     @"「会話文が『ネスト』する場合」\r\n"
     @"「会話文の中に\r\n\r\n改行が複数ある場合」\r\n"
     @"通常の文章"
     ];
    
    NSArray* blockArray = [speaker GetGeneratedSpeechBlockArray_ForTest];
    
    SpeechBlock* block = [blockArray objectAtIndex:0];
    NSString* displayText = [block GetDisplayText];
    NSString* compareText = @"異世界";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@(%lu) <-> %@(%lu)", displayText, [displayText length], compareText, [compareText length]);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:1];
    displayText = [block GetDisplayText];
    compareText = @"\r\n\r\n";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@(%lu) <-> %@(%lu)", displayText, [displayText length], compareText, [compareText length]);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay > 0.0f, @"block(%p) beforeDelay: %f", block, block.speechConfig.beforeDelay);
    
    block = [blockArray objectAtIndex:2];
    displayText = [block GetDisplayText];
    compareText = @"「行頭から会話文";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@(%lu) <-> %@(%lu)", displayText, [displayText length], compareText, [compareText length]);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);
    
    block = [blockArray objectAtIndex:3];
    displayText = [block GetDisplayText];
    compareText = @"」\r\n";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:4];
    displayText = [block GetDisplayText];
    compareText = @"「続いて会話文";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:5];
    displayText = [block GetDisplayText];
    compareText = @"」\r\n通常の文章\r\n通常の文章の中に";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);
    
    block = [blockArray objectAtIndex:6];
    displayText = [block GetDisplayText];
    compareText = @"「会話文";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:7];
    displayText = [block GetDisplayText];
    compareText = @"」";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);

    block = [blockArray objectAtIndex:8];
    displayText = [block GetDisplayText];
    compareText = @"\r\n\r\n通常の文章の中に";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@(%lu) <-> %@(%lu)", displayText, [displayText length], compareText, [compareText length]);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay > 0.0f, @"block(%p) beforeDelay: %f", block, block.speechConfig.beforeDelay);
    
    block = [blockArray objectAtIndex:9];
    displayText = [block GetDisplayText];
    compareText = @"「複数の";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);
    
    block = [blockArray objectAtIndex:10];
    displayText = [block GetDisplayText];
    compareText = @"」";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);

    block = [blockArray objectAtIndex:11];
    displayText = [block GetDisplayText];
    compareText = @"「会話文が";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);
    
    block = [blockArray objectAtIndex:12];
    displayText = [block GetDisplayText];
    compareText = @"」紛れる。\r\n";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:13];
    displayText = [block GetDisplayText];
    compareText = @"「会話文が";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);
    
    block = [blockArray objectAtIndex:14];
    displayText = [block GetDisplayText];
    compareText = @"『ネスト";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.2f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);
    
    block = [blockArray objectAtIndex:15];
    displayText = [block GetDisplayText];
    compareText = @"』する場合";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:16];
    displayText = [block GetDisplayText];
    compareText = @"」\r\n";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:17];
    displayText = [block GetDisplayText];
    compareText = @"「会話文の中に";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f);

    block = [blockArray objectAtIndex:18];
    displayText = [block GetDisplayText];
    compareText = @"\r\n\r\n改行が複数ある場合";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f);
    XCTAssertTrue(block.speechConfig.beforeDelay > 0.0f, @"block(%p) beforeDelay: %f", block, block.speechConfig.beforeDelay);

    block = [blockArray objectAtIndex:19];
    displayText = [block GetDisplayText];
    compareText = @"」\r\n通常の文章";
    XCTAssertTrue([displayText compare:compareText] == NSOrderedSame, @"not same: %@ <-> %@", displayText, compareText);
    XCTAssertTrue(block.speechConfig.pitch == 1.5f, @"not same pitch: %f <-> %f", block.speechConfig.pitch, 1.0f);
    XCTAssertTrue(block.speechConfig.beforeDelay == 0.0f, @"not same beforeDelay: %f <-> %f", block.speechConfig.beforeDelay, 0.0f);
}

@end
