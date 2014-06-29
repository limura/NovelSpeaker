//
//  ViewController.m
//  NovelSpeaker
//
//  Created by 飯村 卓司 on 2014/05/06.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <CoreData/CoreData.h>
#import "ViewController.h"
#import "Story.h"
#import "NarouContent.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.rateSlider.minimumValue = AVSpeechUtteranceMinimumSpeechRate;
    self.rateSlider.maximumValue = AVSpeechUtteranceMaximumSpeechRate;
    self.rateSlider.value = AVSpeechUtteranceDefaultSpeechRate;
    self.pitchSlider.minimumValue = 0.5f;
    self.pitchSlider.maximumValue = 2.0f;
    self.pitchSlider.value = 1.0f;
    
    m_SpeechTextBox = [[SpeechTextBox alloc] init];
    m_SpeechTextBox.textView = self.textView;

    [m_SpeechTextBox SetDelay: 0.001];
    [m_SpeechTextBox AddPitchSetting:@"」$" pitch:1.5f];
    [m_SpeechTextBox AddPitchSetting:@"』$" pitch:1.5f];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/// 読み上げを開始します。
/// 読み上げ開始点(選択範囲)がなければ一番最初から読み上げを開始することにします
- (void)startSpeech {
    // 読み上げ位置を m_SpeechTextBox に指示します
    NSRange range = self.textView.selectedRange;
    [m_SpeechTextBox SetSpeechStartPoint:range];

    // 読み上げ開始位置以降の文字列について、読み上げを開始します。
    [self.startStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    self.loadButton.enabled = FALSE;

    [m_SpeechTextBox SetPitch:self.pitchSlider.value];
    [m_SpeechTextBox SetRate:self.rateSlider.value];
    [m_SpeechTextBox StartSpeech];
}

/// 読み上げを停止します
- (void)stopSpeech{
    [m_SpeechTextBox StopSpeech];
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
    [m_SpeechTextBox SetText:text];
}

- (IBAction)loadButtonClick:(id)sender {
    //NSString* text = [self HttpGet:@"http://ncode.syosetu.com/txtdownload/dlstart/ncode/316737/?no=1&hankaku=0&code=utf-8&kaigyo=CR"];
    
    NSString* text = [self HttpGet:@"http://uirou.no-ip.org/syousetu/ftc.txt"];
    NSRange range;
    range.location = NSNotFound;
    range.length = 0;
    [self setSpeechText:text range:range];
    
    return;
    // TODO: load save をする場合はこんな感じでやるらしい。
    // CoreData で text を保存してみます
    Story* story = (Story*)[NSEntityDescription insertNewObjectForEntityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
    story.content = text;
    NSError* err = nil;
    [self.managedObjectContext save:&err];
    if(err != nil)
    {
        NSLog(@"save error: %@, %@", err, [err userInfo]);
        return;
    }
    
    // CoreData で読みだしてみます
    NSLog(@"original story.content: %@", story.content);

    NSFetchRequest* fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription* entity = [NSEntityDescription entityForName:@"Story" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"content" ascending:NO];
    NSArray* sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
    [fetchRequest setSortDescriptors:sortDescriptors];
    sortDescriptors = nil;
    sortDescriptor = nil;
    err = nil;
    NSMutableArray* fetchResults = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&err] mutableCopy];
    if(fetchResults == nil)
    {
        NSLog(@"fetch from CoreData failed. %@, %@", err, [err userInfo]);
        return;
    }
    NSLog(@"%lu story loaded.", (unsigned long)[fetchResults count]);
    
    return;
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
