//
//  ViewController.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    m_Speaker = [[Speaker alloc] init];
    m_Speaker.delegate = self;
    
    [m_Speaker Speech:@"準備完了"];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)buttonClick:(id)sender {
    //NSString* text = [self HttpGet:@"http://ncode.syosetu.com/txtdownload/dlstart/ncode/316737/?no=1&hankaku=0&code=utf-8&kaigyo=CR"];
    NSString* text = [self HttpGet:@"http://uirou.no-ip.org/syousetu/ftc.txt"];
    [self.textView setText:text];
    [m_Speaker Speech:text];
    return;
    NSArray* lines = [self SplitSpeakText:text];
    for(NSString* str in lines)
    {
        NSLog(@"%@", str);
        NSRange searchResult = [str rangeOfString:@"「"];
        if(searchResult.location == NSNotFound)
        {
            [m_Speaker SetPitch:1.0f];
        }else{
            [m_Speaker SetPitch:0.8f];
        }
        [m_Speaker SetDelay: 0.05];
        [m_Speaker Speech:str];
        while([m_Speaker GetStatus] != STSpeakingStatusStop)
        {
            [NSThread sleepForTimeInterval:0.1];
        }
    }
}

/// Speaker からのイベントを受け取ります
- (void) willSpeakRange:(NSRange)range speakText:(NSString *)text
{
    // 全体のテキストから目的のテキストを検索します
    NSString* originalText = text;
    NSRange originalTextRange = [originalText rangeOfString:text];
    if(originalTextRange.location == NSNotFound)
    {
        NSLog(@"location NSNotFound. %lu, %lu", range.location, range.length);
        return;
    }
    
    // Speech している部分だけ色をつけた attributedString を作ります
    // とりあえず全部を入れる箱をつくります
    NSMutableAttributedString* attributedStringBuf = [[NSMutableAttributedString alloc] init];

    if((originalTextRange.location + range.location) != 0)
    {
        // Speechの範囲外の前の部分を attributedStringBuf に追加します
        NSRange prevRange;
        prevRange.length = originalTextRange.location + range.location;
        prevRange.location = 0;
        NSString* prevString = [originalText substringWithRange:prevRange];
        NSAttributedString* prevAttributedString = [[NSAttributedString alloc] initWithString:prevString];
        [attributedStringBuf appendAttributedString:prevAttributedString];
    }
    {
        // Speech している部分を attributedStringBuf に追加します
        NSString* targetText = [text substringWithRange:range];
        NSDictionary* highlightAttribute = @{NSForegroundColorAttributeName: [UIColor redColor]};
        NSAttributedString* currentAttributedString = [[NSAttributedString alloc] initWithString:targetText  attributes:highlightAttribute];
        [attributedStringBuf appendAttributedString:currentAttributedString];
        NSLog(@"speak: %@", targetText);
    }
    if([originalText length] > (originalTextRange.location + range.location + range.length)){
        // Speech の範囲外の後ろの部分を attributedStringBuf に追加します
        NSRange nextRange;
        nextRange.location = originalTextRange.location + range.location + range.length;
        nextRange.length = [originalText length] - nextRange.location;
        NSString* nextString = [originalText substringWithRange:nextRange];
        NSAttributedString* nextAttributedString = [[NSAttributedString alloc] initWithString:nextString];
        [attributedStringBuf appendAttributedString:nextAttributedString];
    }
    
    self.textView.attributedText = attributedStringBuf;
    [self.textView scrollRangeToVisible:range];
}

/// 長い文字列を読み上げ時の読み上げやすい長さに分割した NSArray に変換します。
- (NSArray*)SplitSpeakText:(NSString*)text {
    NSArray* result = [text componentsSeparatedByString:@"\r\n"];
    return result;
}

- (NSString*)HttpGet:(NSString*)url {
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse: nil error:nil];
    NSString* str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return str;
}

@end
