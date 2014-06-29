//
//  SpeechTextBox.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/06/26.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Speaker.h"

/**
 指定された文字列を読み上げます。
 ただ、小説を読むための怪しい拡張をこのclassである程度吸収させます。
 ということで、かなり怪しげな事をやるための状態管理を行います。
 
 - UITextBox を制御して、読み上げ中の部分を選択範囲として表示します
 - 読み上げ時に段落やセリフなどの前後に一白おかせる事などをするために
   単純にすべての文字列を一度に AVSpeechSynthesizer に渡すわけではなく、
   文字列を細切れにして渡します。
 */
@interface SpeechTextBox : NSObject<SpeakRangeDelegate>
{
    /// 実際の読み上げを行う object
    Speaker* m_Speaker;
    /// 現在の読み上げ開始位置
    NSRange m_SpeechPosition;
    /// 読み上げている文字列の配列
    NSArray* m_SpeechTextList;
    /// 現在読み上げ中の文字列の m_SpeechTextList の index
    int m_SpeechTextListIndex;
    /// m_SpeechTextListIndex から計算した現在の読み上げ位置
    NSUInteger m_SpeechTextLocationCache;
    /// 今 Speaker に読み上げさせている文字列が、
    /// m_SpeechTextList[ｍ＿SpeechTextListIndex]から何文字目まで切り飛ばしたものかを示す文字数
    NSUInteger m_SpeechTextBlockStartLocation;
    /// 現在読み上げを指示されている(true)か否(false)かの真偽値。
    /// 読み上げ終了イベントは自分で読み上げを終わらせた時も、
    /// 自動で終わった時もどちらも呼び出されるので、どちらの条件で発生したかを判定するために使います。
    BOOL m_isSpeaking;
    
    /// 細切れ文字列毎に正規表現にマッチしたら設定されるピッチのlist
    NSArray* m_PitchSettingList;
    
    /// 読み上げに使われる標準のrate
    float m_DefaultRate;
    /// 読み上げに使われる標準のpitch
    float m_DefaultPitch;
}

/// textView へのlink
@property (weak, nonatomic) UITextView *textView;

/// 読み上げる文字列を初期化します
- (BOOL) SetText: (NSString*) text;

/// 読み上げる文字列の開始位置を指定します
- (BOOL) SetSpeechStartPoint: (NSRange)range;

/// 読み上げの停止位置(又は現在読み上げ中の位置)を取得します。
- (NSRange) GetSpeechPoint;

/// SetSpeechStartPointで設定されている位置から、読み上げを開始します
- (BOOL) StartSpeech;

/// 読み上げを終了します
- (BOOL) StopSpeech;

/// 読み上げを一時中断します。
/// 再開する場合は ResumeSpeech を使用します
- (BOOL) PauseSpeech;

/// PauseSpeechで止めた読み上げを再開します
- (BOOL) ResumeSpeech;

/// 音声の読み上げ速度を指定します。1.0f が通常の速度で、2.0f だと二倍速、0.5f だと半分の速度です。
/// この設定は次回以降の読み上げから有効になります
/// 最小値は AVSpeechUtteranceMinimumSpeechRate
/// 最大値は AVSpeechUtteranceMaximumSpeechRate
/// 標準値は AVSpeechUtteranceDefaultSpeechRate です。
- (void) SetRate: (float) rate;

/// 標準の音声のピッチを指定します。小さい値は男性っぽく、大きい値は女性っぽくなります
/// この設定は次回以降の読み上げから有効になります
/// 値は 0.5f から 2.0f までで、標準値は 1.0f です。
- (void) SetPitch: (float) pitch;

/// これから読み上げる文字列について、regexPatternで正規表現マッチを行い、
/// マッチするものであれば指定されたpitchのピッチで読み上げを行うようにします。
/// マッチは登録された順に行われ、一番最初にマッチしたものが採用されます。
/// 何にもマッチしない場合には、SetPitch で指定された標準の音声ピッチが採用されます。
- (BOOL) AddPitchSetting: (NSString*)regexPattern pitch:(float)pitch;

/// 音声を読み上げるときの前から開ける時間を指定します
/// この設定は次回以降の読み上げから有効になります
- (void) SetDelay: (NSTimeInterval) interval;
@end