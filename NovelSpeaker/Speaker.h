//
//  Speaker.h
//  NBackSpeaker
//
//  Created by 飯村 卓司 on 2014/02/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol SpeakRangeDelegate <NSObject>

/// これから読み上げる文字列をお知らせします
/// range は現在読み上げ中の文字列中のどの部分が読み上げられるかの範囲
/// text は現在読み上げ中の文字列です
/// 実際に読み上げられる文字を取り出すには
///    [text substringWithRange:range]
/// とします。
- (void) willSpeakRange:(NSRange)range speakText:(NSString*)text;

/// 読み上げが停止したことを知らせます
- (void) finishSpeak;
@end

/// 音声の読み上げ状態
typedef enum {
    /// 読み上げ中
    STSpeakingStatusSpeak,
    /// 終了している
	STSpeakingStatusStop,
    /// 一時停止中
	STSpeakingStatusPause,
    /// 初期状態 or 何もしていない
	STSpeakingStatusNone
} STSpeakingStatus;

/// 文字列から Siri を使って音声読み上げを行います。
@interface Speaker : NSObject<AVSpeechSynthesizerDelegate>
{
    AVSpeechSynthesizer* m_Synthesizer;
    AVSpeechSynthesisVoice* m_Voice;
    STSpeakingStatus m_CurrentStatus;
    float m_Rate;
    float m_Pitch;
    NSTimeInterval m_Interval;
    float m_Volume;
    AVAudioEngine* m_AudioEngine;
    AVAudioPlayerNode* m_AudioPlayerNode;
    AVAudioFormat* m_AudioFormat;
    AVAudioConverter* m_AudioConverter;
}

/// delegate プロパティ
@property (nonatomic, weak) id<SpeakRangeDelegate> speakRangeChangeDelegate;

/// 音声の読み上げを開始します。開始できた場合は TRUE を返します
- (BOOL) Speech: (NSString*) text;

/// 音声の読み上げ言語を指定します。@"ja-JP", @"en-US" などが使えます
- (void) SetVoice: (NSString*) language;

/// 音声の読み上げ話者を指定します。@"Alex", AVSpeechSynthesisVoiceIdentifierAlex などが使えます
- (BOOL)SetVoiceWithIdentifier:(NSString*) voiceID voiceLocale:(NSString*)voiceLocale;

/// 音声の読み上げ速度を指定します。1.0f が通常の速度で、2.0f だと二倍速、0.5f だと半分の速度です。
/// この設定は次回以降の読み上げから有効になります
/// 最小値は AVSpeechUtteranceMinimumSpeechRate
/// 最大値は AVSpeechUtteranceMaximumSpeechRate
/// 標準値は AVSpeechUtteranceDefaultSpeechRate です。
- (void) SetRate: (float) rate;

/// 音声のピッチを指定します。小さい値は男性っぽく、大きい値は女性っぽくなります
/// この設定は次回以降の読み上げから有効になります
/// 値は 0.5f から 2.0f までで、標準値は 1.0f です。
- (void) SetPitch: (float) pitch;

/// 音声を読み上げるときの前から開ける時間を指定します
/// この設定は次回以降の読み上げから有効になります
- (void) SetDelay: (NSTimeInterval) interval;

/// 現在の読み上げ状態を取得します
- (STSpeakingStatus) GetStatus;

/// 読み上げを終了します
- (BOOL) StopSpeech;

/// 読み上げを一時中断します。
/// 再開する場合は ResumeSpeech を使用します
- (BOOL) PauseSpeech;

/// 読み上げを再開します
- (BOOL) ResumeSpeech;

@end
