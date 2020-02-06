//
//  StringSubstituterTests.m
//  novelspeaker
//
//  Created by 飯村卓司 on 2014/10/04.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "StringSubstituter.h"
#import "SpeechModSettingCacheData.h"

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
    NSString* text = @"に|勤《いそ》しんだ。《セリフ〜》\r\n"
        @"時間の|歪(ゆがー)みすら覚えながら"
        @"大半を|力場装甲(フォースフィールドアーマー)に割り当てている";
    
    NSDictionary* matchPatterns = @{
                                    @"|勤《いそ》": @"いそ",
                                    @"勤《いそ》": @"いそ",
                                    @"|歪(ゆがー)": @"ゆがー",
                                    @"歪(ゆがー)": @"ゆがー",
                                    @"|力場装甲(フォースフィールドアーマー)": @"フォースフィールドアーマー",
                                    @"力場装甲(フォースフィールドアーマー)": @"フォースフィールドアーマー",
                                    };
    NSDictionary* resultDictionary = [StringSubstituter FindNarouRubyNotation:text notRubyString:@"・"];
    
    NSLog(@"%@", resultDictionary);
    for (NSString* resultKey in [resultDictionary keyEnumerator]) {
        NSLog(@"%@ -> %@", resultKey, [resultDictionary objectForKey:resultKey]);
    }
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
- (void)testRegexpSpeechModConfigs_Escape
{
    NSString* targetText = @"あいうえお";
    NSString* pattern = @"(あ)(い)(う)(え)";
    NSString* to = @"\\$1\\$2\\$3\\\\$1\\\\$2\\\\$3"; // "\$1\$2\$3\\$1\\$2\\$3" になる
    NSArray* result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 1);
    SpeechModSettingCacheData* modSetting = result[0];
    XCTAssertEqual([modSetting.beforeString compare:@"あいうえ"], NSOrderedSame, @"「あいうえ」が発見されていない");
    NSLog(@"%@ -> %@", modSetting.beforeString, modSetting.afterString);
    XCTAssertEqual([modSetting.afterString compare:@"$1$2$3\\あ\\い\\う"], NSOrderedSame, @"「あいうえ」が「$1$2$3\\あ\\い\\う」に書き換えようとされていない");
}
    
- (void)testRegexpSpeechModConfigs
{
    NSString* targetText = @"　メロスは激怒した。必ず、かの邪智暴虐じゃちぼうぎゃくの王を除かなければならぬと決意した。メロスには政治がわからぬ。メロスは、村の牧人である。笛を吹き、羊と遊んで暮して来た。けれども邪悪に対しては、人一倍に敏感であった。きょう未明メロスは村を出発し、野を越え山越え、十里はなれた此このシラクスの市にやって来た。メロスには父も、母も無い。女房も無い。十六の、内気な妹と二人暮しだ。この妹は、村の或る律気な一牧人を、近々、花婿はなむことして迎える事になっていた。結婚式も間近かなのである。メロスは、それゆえ、花嫁の衣裳やら祝宴の御馳走やらを買いに、はるばる市にやって来たのだ。先ず、その品々を買い集め、それから都の大路をぶらぶら歩いた。メロスには竹馬の友があった。セリヌンティウスである。今は此のシラクスの市で、石工をしている。その友を、これから訪ねてみるつもりなのだ。久しく逢わなかったのだから、訪ねて行くのが楽しみである。歩いているうちにメロスは、まちの様子を怪しく思った。ひっそりしている。もう既に日も落ちて、まちの暗いのは当りまえだが、けれども、なんだか、夜のせいばかりでは無く、市全体が、やけに寂しい。";
    
    // 不正な入力: 空文字列
    NSString* pattern = @"";
    NSString* to = @"";
    NSArray* result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 0);

    // 不正な入力: nil
    pattern = nil;
    to = nil;
    result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 0);

    // 不正な入力: 正規表現として壊れている
    pattern = @"(abc"; // ')' が無い
    to = @"abc";
    result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 0);

    pattern = @"メロス(\\p{Hiragana}+)";
    to = @"太郎$1";
    result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 2);
    SpeechModSettingCacheData* modSetting = result[0];
    XCTAssertEqual([modSetting.beforeString compare:@"メロスは"], NSOrderedSame, @"「メロスは」が発見されていない");
    XCTAssertEqual([modSetting.afterString compare:@"太郎は"], NSOrderedSame, @"「メロスは」が「太郎は」に書き換えようとされていない");
    modSetting = result[1];
    XCTAssertEqual([modSetting.beforeString compare:@"メロスには"], NSOrderedSame, @"「メロスには」が発見されていない");
    XCTAssertEqual([modSetting.afterString compare:@"太郎には"], NSOrderedSame, @"「メロスには」が「太郎には」に書き換えようとされていない");

    targetText = @"時は西暦199X年、世界は核の炎に包まれた。そして200x年、人類は……";
    pattern = @"([0-9xX]+)年";
    to = @"$1ネン";
    result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 2);
    modSetting = result[0];
    XCTAssertEqual([modSetting.beforeString compare:@"199X年"], NSOrderedSame, @"「199X年」が発見されていない");
    XCTAssertEqual([modSetting.afterString compare:@"199Xネン"], NSOrderedSame, @"「199X年」が「199xネン」に書き換えようとされていない");
    modSetting = result[1];
    XCTAssertEqual([modSetting.beforeString compare:@"200x年"], NSOrderedSame, @"「200x年」が発見されていない");
    XCTAssertEqual([modSetting.afterString compare:@"200xネン"], NSOrderedSame, @"「200x年」が「200xネン」に書き換えようとされていない");

    targetText = @"abcdefghijklmnopqrstu";
    pattern = @"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)(k)(l)(m)(n)(o)(p)(q)(r)";
    to = @"$18$17$16$15$14$13$12$11$10$9$8$7$6$5$4$3$2$1";
    result = [StringSubstituter FindRegexpSpeechModConfigs:targetText pattern:pattern to:to];
    XCTAssertEqual([result count], 1);
    modSetting = result[0];
    XCTAssertEqual([modSetting.beforeString compare:@"abcdefghijklmnopqr"], NSOrderedSame, @"「abcdefghijklmnopqr」が発見されていない");
    XCTAssertEqual([modSetting.afterString compare:@"rqponmlkjihgfedcba"], NSOrderedSame, @"「abcdefghijklmnopqr」が「rqponmlkjihgfedcba」に書き換えようとされていない");
}

@end
