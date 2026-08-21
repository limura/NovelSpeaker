//
//  VoicevoxThreadPolicy.swift
//  NovelSpeaker
//
//  VOICEVOX の合成に使う CPU スレッド数を、アプリの状態と電源状態から決めるポリシー。
//
//  背景:
//  スレッド数には「どちらが得か」が状況で逆転する、という厄介な性質がある。
//   - スレッド数1 … CPU秒/文字(RTF)が最良(実測 iPhone 17 Pro Max で RTF≒0.85)。
//                   ただし1コア分しか使えないので、実時間に対しては 1.2倍速程度が限界。
//   - 自動(全コア)… RTF は悪化する(同 1.43。同じ仕事に1.7倍のCPU秒を使う)が、
//                   CPU を 292% 使えるので実時間では 2倍速相当まで出る。
//
//  背面かつバッテリー駆動の時は iOS の「60秒平均でCPU80%(=1コア相当)」の上限が効くので、
//  使えるのは実質1コア分しかない。ここでは「CPU秒あたりどれだけ音声を作れるか」が全てなので
//  スレッド数1が最良になる(全コアにしても上限で殺されるだけ)。
//  逆に前景や充電中はその上限が適用されないため、CPU秒を多めに払ってでも実時間で
//  速く作れる全コアの方が良い(1.45倍速の再生に追いつけるかどうかがここで決まる)。
//
//  よって固定値ではなく、状況に応じて切り替える。
//

import Foundation

/// UIKit に依存しない純粋なポリシー(テスト可能)。
enum VoicevoxThreadPolicy {

    /// CPU 上限が効く状況で使うスレッド数。
    static let limitedThreadCount: UInt16 = 1
    /// CPU 上限が効かない状況で使うスレッド数(0 = ONNX の自動 = 全コア)。
    static let unlimitedThreadCount: UInt16 = 0

    /// スレッド数を「増やす」方向の変更を行う最短間隔(秒)。
    ///
    /// synthesizer の作り直しには音声モデルの再ロードが伴うので、電源の抜き差しなどで
    /// 頻繁に往復されると、その度に合成が止まってしまう。減らす方向は安全のために
    /// 即座に行うが、増やす方向は急がないのでこの間隔を空ける。
    static let minimumSecondsBetweenIncrease: Double = 20

    /// 「多さ」の比較用。0 は自動(全コア)なので最大として扱う。
    static func weight(of threadCount: UInt16) -> Int {
        return threadCount == 0 ? Int.max : Int(threadCount)
    }

    /// 状況から決まるスレッド数。
    ///
    /// **外部電源に繋がっているかは見ない。** 以前は「充電中は背面CPU上限が
    /// 適用されない」として全コアに戻していたが、これは誤りだった
    /// (詳細は VoicevoxPrefetchThrottle.swift の isCPULimitApplied)。
    ///
    /// - Parameters:
    ///   - isBackground: アプリがバックグラウンドにあるか。
    ///   - isLowPowerModeEnabled: 低電力モードか。
    static func desiredThreadCount(isBackground: Bool, isLowPowerModeEnabled: Bool) -> UInt16 {
        // 低電力モードは「電池を使うな」という利用者の明示的な意思表示なので、
        // 前景であっても CPU秒あたりの効率が最良になるスレッド数1にする。
        if isLowPowerModeEnabled { return limitedThreadCount }
        // 背面では CPU 上限(60秒平均80%)が効くので、スレッド数を絞る。
        if isBackground { return limitedThreadCount }
        return unlimitedThreadCount
    }

    /// synthesizer を作り直すべきか。
    /// - Parameters:
    ///   - current: 今の synthesizer を作った時のスレッド数。
    ///   - desired: 今の状況で使いたいスレッド数。
    ///   - secondsSinceLastChange: 最後に切り替えてからの経過秒数。
    static func shouldReconfigure(current: UInt16, desired: UInt16, secondsSinceLastChange: Double) -> Bool {
        if current == desired { return false }
        // 減らす方向は「これ以上CPUを使うと殺される」側なので、間隔を空けずに即座に行う。
        if weight(of: desired) < weight(of: current) { return true }
        return secondsSinceLastChange >= minimumSecondsBetweenIncrease
    }
}
