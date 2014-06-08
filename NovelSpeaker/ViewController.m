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

/// 読み上げを開始します。
/// 読み上げ開始点(選択範囲)がなければ一番最初から読み上げを開始することにします
- (void)startSpeech {
    NSRange range = self.textView.selectedRange;
    if(range.location == NSNotFound
       || range.location >= [self.textView.text length])
    {
        // 範囲指定がおかしいので読み上げ開始位置は初期状態のものとします。
        range.location = 0;
        range.length = 0;
    }
    
    // 読み上げ開始位置以降の文字列について、読み上げを開始します。
    m_SpeechStartPosition = range.location;
    NSString* speechText = [self.textView.text substringFromIndex:range.location];
    [self.startStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    self.loadButton.enabled = FALSE;
    [m_Speaker StopSpeech]; // 一旦停止させてから、読み上げさせます
    [m_Speaker Speech:speechText];
}

/// 読み上げを停止します
- (void)stopSpeech{
    [m_Speaker StopSpeech];
    [self.startStopButton setTitle:@"Start" forState:UIControlStateNormal];
    self.loadButton.enabled = TRUE;
}

/// 読み上げ用の文字列を設定します。
/// 読み上げ中の場合は読み上げは停止されます。
/// 読み上げられるのは text で、range で指定されている点を読み上げ開始点として読み上げを開始します。
- (void)setSpeechText:(NSString*)text range:(NSRange)range {
    [self stopSpeech];
    [self.textView setText:text];
    self.textView.selectedRange = range;
}

- (IBAction)loadButtonClick:(id)sender {
    //NSString* text = [self HttpGet:@"http://ncode.syosetu.com/txtdownload/dlstart/ncode/316737/?no=1&hankaku=0&code=utf-8&kaigyo=CR"];
    
    
    NSString* text = [self HttpGet:@"http://uirou.no-ip.org/syousetu/ftc.txt"];
    NSRange range;
    range.location = NSNotFound;
    [self setSpeechText:text range:range];
    [self startSpeech];
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

- (IBAction)startStopButtonClick:(id)sender {
    if([self.startStopButton.titleLabel.text compare:@"Start"] == NSOrderedSame)
    {
        // 停止中だったので読み上げを開始します
        [self startSpeech];
    }
    else
    {
        [self stopSpeech];
    }
}

/// Speaker からのイベントを受け取ります
- (void) willSpeakRange:(NSRange)range speakText:(NSString *)text
{
    NSRange currentRange;
    currentRange.location = m_SpeechStartPosition + range.location;
    currentRange.length = range.length;
    self.textView.selectedRange = currentRange;
    [self.textView scrollRangeToVisible:currentRange];
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
