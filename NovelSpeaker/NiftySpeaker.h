//
//  NiftySpeaker.h
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2014/08/10.
//  Copyright (c) 2014年 IIMURA Takuji. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpeechConfig.h"
#import "Speaker.h"

/// 「イイカンジ」の読み上げclass
/// 与えられた文字列を、読み上げの声色や区切り毎で分割した
/// SpeechBlock の配列に変換してから読み上げを行う。
@interface NiftySpeaker : NSObject<SpeakRangeDelegate, AVAudioSessionDelegate>
{
    /// 読み上げ用object
    Speaker* m_Speaker;
    
    /// 読み上げを待つ SpeechBlock の配列
    NSArray* m_SpeechBlockArray;
    
    /// 標準の声色
    SpeechConfig* m_DefaultSpeechConfig;
    
    /// delay を追加するための分割ルールのリスト
    NSMutableArray* m_DelaySettingArray;
    
    /// 声色を変えるための分割ルールのリスト
    NSMutableArray* m_BlockSeparatorArray;
    
    /// 読み上げ時の文字列を変更するためのテーブル(key が元文字列で value が読み上げ時に使われる文字列)
    NSMutableDictionary* m_SpeechModDictionary;
    
    /// 読み上げをしているか否かのbool値
    BOOL m_bIsSpeaking;
    
    /// 現在読み上げている m_SpeechBlockArray のインデックス
    unsigned int m_NowSpeechBlockIndex;
    
    /// 現在読み上げている m_SpeechBlockArray における、speakText での読み上げ位置
    NSRange m_NowSpeechBlockSpeachRange;
    
    // delegate を保存します。
    NSMutableArray* m_SpeakRangeDelegateArray;
}

/// GlobalDataSingletonを使わない初期化
- (id)initWithSpeechConfig:(SpeechConfig*)speechConfig;

/// 読み上げ用の文字列を設定します。同時に SpeechBlock への変換が走ります。
- (BOOL)SetText:(NSString*)text;

/// 無指定の時の声色を指定します。
- (BOOL)SetDefaultSpeechConfig:(SpeechConfig*)speechConfig;

/// SpeechBlock で声色を変えるための範囲を判定するための文字列設定を追加します。
- (BOOL)AddBlockStartSeparator:(NSString*)startString endString:(NSString*)endString speechConfig:(SpeechConfig*)speechConfig;

/// SpeechBlock で deleay を追加するための分割ルールを設定します。
/// 注意：この設定では声色を変更することはできません。
- (BOOL)AddDelayBlockSeparator:(NSString*)string delay:(NSTimeInterval)delay;

/// 読み上げ時に、Siriさんが読み間違えてしまう文字列を読み間違えないように別の文字列で置き換えるテーブルを追加します。
- (BOOL)AddSpeechModText:(NSString*)from to:(NSString*)to;

/// 読み上げを開始します。
- (BOOL)StartSpeech;

/// 読み上げを停止します。
- (BOOL)StopSpeech;

/// 現在の読み上げ位置を取得します
- (NSRange)GetCurrentReadingPoint;

/// 読み上げ位置を指定した座標に更新します。
- (BOOL)UpdateCurrentReadingPoint:(NSRange)point;

/// 読み上げ時のイベントハンドラを追加します。
- (BOOL)AddSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate;

/// 読み上げ時のイベントハンドラを削除します。
- (void)DeleteSpeakRangeDelegate:(id<SpeakRangeDelegate>)delegate;

/// 読み上げ中か否かを取得します
- (BOOL)isSpeaking;

@end
