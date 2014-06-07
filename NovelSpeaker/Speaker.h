//
//  Speaker.h
//  NBackSpeaker
//
//  Created by 飯村 卓司 on 2014/02/16.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

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
}

/// 音声の読み上げを開始します。開始できた場合は TRUE を返します
- (BOOL) Speech: (NSString*) text;

/// 音声の読み上げ言語を指定します。@"ja-JP", @"en-US" などが使えます
- (void) SetVoice: (NSString*) language;

/// 音声の読み上げ速度を指定します。1.0f が通常の速度で、2.0f だと二倍速、0.5f だと半分の速度です
- (void) SetRate: (float) rate;

/// 現在の読み上げ状態を取得します
- (STSpeakingStatus) GetStatus;

@end
