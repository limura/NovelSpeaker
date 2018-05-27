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
    
    SpeechConfig* conf = [SpeechConfig new];
    SpeechBlock* block = [substituter Convert:from speechConfig:conf];
    NSString* conved = [block GetSpeechText];
    XCTAssertEqual([answer compare:conved], NSOrderedSame, @"conv failed:\n  from:\"%@\"\nanswer:\"%@\"\n    to:\"%@\"", from, answer, conved);
}

- (void)testConvertEnter
{
    StringSubstituter* substituter = [StringSubstituter new];
    
    XCTAssertTrue([substituter AddSetting_From:@"\r\n" to:@"x"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"\r" to:@"y"], @"add failed");
    XCTAssertTrue([substituter AddSetting_From:@"\n" to:@"z"], @"add failed");
    
    NSString* from = @"a\r\n\r\n\r\r\n\n";
    NSString* answer = @"axxyxz";
    
    SpeechConfig* conf = [SpeechConfig new];
    SpeechBlock* block = [substituter Convert:from speechConfig:conf];
    NSString* conved = [block GetSpeechText];
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
    
    SpeechConfig* conf = [SpeechConfig new];
    SpeechBlock* block = [substituter Convert:from speechConfig:conf];
    NSString* conved = [block GetSpeechText];
    XCTAssertEqual([answer compare:conved], NSOrderedSame, @"conv failed:\n  from:\"%@\"\nanswer:\"%@\"\n    to:\"%@\"", from, answer, conved);
}

- (void)testNarouRuby
{
    NSString* text = @"012aiuあいう漢字(かんじ)ルビをふる、"
        @"分断（ブンダン）、|変速ルビ《へんそくルビ》、|強調している《・・・・・・》、"
        @"漢字(簡易表記のルビ部分に漢字を入れると)認識されないはず"
        @"複数（ふくすう）連続（れんぞく)目標(もくひょう)問題（もんだい）発見（はっけん）"
        @"end"
    ;
    NSDictionary* matchPatterns = @{
        @"漢字(かんじ)": @"かんじ",
        @"分断（ブンダン）": @"ブンダン",
        @"|変速ルビ《へんそくルビ》": @"へんそくルビ",
        @"複数（ふくすう）": @"ふくすう",
        @"連続（れんぞく)": @"れんぞく",
        //@"目標(もくひょう)": @"もくひょう",
        @"問題（もんだい）": @"もんだい",
        @"発見（はっけん）": @"はっけん",
        // @"|強調している《・・・・・・》": @"・・・・・・",
    };
    NSDictionary* resultDictionary = [StringSubstituter FindNarouRubyNotation:text notRubyString:@"・！＠もくひょう"];
    
    NSLog(@"%@", resultDictionary);
    for (NSString* fromAnswer in [matchPatterns keyEnumerator]) {
        NSString* toAnswer = matchPatterns[fromAnswer];
        NSString* to = [resultDictionary objectForKey:fromAnswer];
        NSString* errString = [NSString stringWithFormat:@"key \"%@\" not found", fromAnswer];
        if (to == nil) {
            NSLog(@"%@", errString);
        }
        XCTAssertNotNil(to);

        errString = [NSString stringWithFormat:@"to \"%@\" is not same \"%@\"", to, toAnswer];
        if ([to compare:toAnswer] != NSOrderedSame) {
            NSLog(@"%@", errString);
        }
        XCTAssertTrue([to compare:toAnswer] == NSOrderedSame);
    }
}

- (void)testNarouRubyBug
{
    NSString* text = @"に|勤《いそ》しんだ。\r\n《セリフ〜》\r\n";
    
    NSDictionary* matchPatterns = @{
                                    @"|勤《いそ》": @"いそ",
                                    @"勤《いそ》": @"いそ",
                                    };
    NSDictionary* resultDictionary = [StringSubstituter FindNarouRubyNotation:text notRubyString:@"・"];
    
    NSLog(@"%@", resultDictionary);
    for (NSString* fromAnswer in [matchPatterns keyEnumerator]) {
        NSString* toAnswer = matchPatterns[fromAnswer];
        NSString* to = [resultDictionary objectForKey:fromAnswer];
        NSString* errString = [NSString stringWithFormat:@"key \"%@\" not found", fromAnswer];
        if (to == nil) {
            NSLog(@"%@", errString);
        }
        XCTAssertNotNil(to);
        
        errString = [NSString stringWithFormat:@"to \"%@\" is not same \"%@\"", to, toAnswer];
        if ([to compare:toAnswer] != NSOrderedSame) {
            NSLog(@"%@", errString);
        }
        XCTAssertTrue([to compare:toAnswer] == NSOrderedSame);
    }
}

@end
