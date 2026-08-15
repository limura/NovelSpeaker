//
//  VoicevoxPrefetchThrottle.swift
//  NovelSpeaker
//
//  VOICEVOX の先行合成(prefetch)を、アプリの状態と電源状態に応じて絞り込むための仕組み。
//
//  背景:
//  iOS はバックグラウンドのアプリに「60秒平均で CPU 80%」という上限を課しており、
//  これを超えるとプロセスを強制終了する(クラッシュレポートの bug_type 206 /
//  cpu_resource_fatal、"Action taken: Process killed")。
//  実機(iPhone 17 Pro Max / iOS 26.6)で、バックグラウンド再生中に
//    CPU: 48 seconds cpu time over 58 seconds (82% cpu average), exceeding limit of 80% cpu over 60 seconds
//    Power Source: 39 samples on Battery, 0 samples on AC
//  として実際に殺されたことを確認している。重いスタックは onnxruntime の推論で、
//  「再生に追いつこうとして先行合成が CPU を回し続ける」のが死因だった。
//
//  重要なのは以下の2点:
//   - この CPU 上限は **バックグラウンド**のアプリにのみ効く(前景では別勘定)。
//   - **外部電源(AC)接続中は適用されない**。実機で「Mac に繋いでいると落ちないが、
//     電源を抜くと落ちる」という挙動になっていたのはこれが理由。
//
//  よって「背面 かつ バッテリー駆動」の時だけ先行合成を最小限に絞り、
//  それ以外(前景/充電中)は従来どおりの積極的な先読みを維持する。
//
//  なお、これは「殺されないようにする」ための対策であって、
//  CPU 合成の RTF(実時間比)そのものを下げるものではない。RTF≒1.0 のままだと
//  実時間合成に必要な CPU 使用率自体が上限に近いため、根本解決には
//  ANE(Neural Engine)オフロード等で RTF を下げる必要がある。
//

import Foundation
#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 先行合成の積極性を表すパラメータ群。
struct VoicevoxPrefetchParameters: Equatable {
    /// 先読みしておきたい文字数の目安。
    let targetCharacterCount: Int
    /// 文字数目安を満たしていても、最低これだけのブロック数は先読みする。
    let minimumBlockCount: Int
    /// 1回の呼び出しで予約するブロック数のハード上限。
    let maxBlockCountToQueue: Int
    /// 先読み対象を探すために走査するブロック数の上限。
    let maxBlocksToScan: Int
    /// 「未再生の貯金」がこの秒数に達したら、それ以上は先行合成しない。
    ///
    /// これが無いと、1回の呼び出しあたりのブロック数を絞っても
    /// (nextPrefetchScanIndex が呼び出しを跨いで前進するため)総量に歯止めが掛からず、
    /// 先行合成が CPU を延々と焼き続ける。実機ではこれが
    ///  - CPU率が 100.8% に張り付いたまま下がらない(→ 背面CPU上限で強制終了)
    ///  - 再生に必要な合成が先行合成の待ち行列に並ばされ平均15秒待たされる(→ 無音率74.8%)
    /// の両方の原因になっていた。貯金が足りている間は合成を止める事で、CPUを空けて
    /// 再生側の要求を即座に処理できるようにする。
    let targetLeadSeconds: Double
}

/// アプリ状態・電源状態から先行合成パラメータを決める純粋なポリシー(UIKit非依存でテスト可能)。
enum VoicevoxPrefetchThrottlePolicy {
    /// 従来どおりの積極的な先読み(前景、または充電中の背面)。
    static let normal = VoicevoxPrefetchParameters(
        targetCharacterCount: 300,
        minimumBlockCount: 3,
        maxBlockCountToQueue: 8,
        maxBlocksToScan: 40,
        // 前景/充電中は CPU 上限が無いので、貯金は多めに持ってよい
        // (背面に移った後の余裕になる)。
        targetLeadSeconds: 300
    )

    /// 背面かつバッテリー駆動時の絞り込み設定。
    /// 「再生中のブロックの次の1つ」だけを合成しておく所まで落とし、
    /// 再生ペースを大きく追い越して CPU を焼き続けないようにする。
    static let throttled = VoicevoxPrefetchParameters(
        targetCharacterCount: 60,
        minimumBlockCount: 1,
        maxBlockCountToQueue: 1,
        maxBlocksToScan: 12,
        // 背面バッテリー時は、これだけ貯まったら合成を止めて CPU を空ける。
        targetLeadSeconds: 60
    )

    /// - Parameters:
    ///   - isBackground: アプリがバックグラウンドにあるか。
    ///   - isOnExternalPower: 外部電源(AC/USB)に接続されているか。
    ///   - isLowPowerModeEnabled: 低電力モードか。
    static func parameters(isBackground: Bool, isOnExternalPower: Bool, isLowPowerModeEnabled: Bool) -> VoicevoxPrefetchParameters {
        // 前景では、このバックグラウンド CPU 上限の対象にならないので従来どおり。
        guard isBackground else { return normal }
        // 低電力モードでは CPU クロックが落ちて合成が更に間に合わなくなるため、
        // 充電中であっても絞る(発熱・電池消費の面でも望ましい)。
        if isLowPowerModeEnabled { return throttled }
        // 外部電源接続中はバックグラウンド CPU 上限が適用されないので絞らなくてよい。
        if isOnExternalPower { return normal }
        return throttled
    }
}

/// アプリ状態・電源状態を監視して、現在の先行合成パラメータを提供する。
///
/// `refillVoicevoxPrefetchIfNeeded()` は発話進行に伴って任意のスレッドから呼ばれ得るが、
/// `UIApplication.shared.applicationState` はメインスレッド専用のため、
/// 通知でメインキューに受けた結果をロック付きでキャッシュして参照する形にしている。
final class VoicevoxPrefetchThrottleMonitor {
    static let shared = VoicevoxPrefetchThrottleMonitor()

    private let lock = NSLock()
    private var isBackgroundCache = false
    private var isStarted = false

    private init() {}

    /// 通知監視を開始する(何度呼んでもよい)。
    func start() {
        lock.lock()
        if isStarted {
            lock.unlock()
            return
        }
        isStarted = true
        lock.unlock()

        #if os(watchOS)
        // watchOS では VOICEVOX による合成は行わない想定だが、
        // 仮に動かす場合でも背面では絞る方が安全なので、前景通知のみ拾って判定する。
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(forName: WKApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setIsBackground(false)
        }
        notificationCenter.addObserver(forName: WKApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setIsBackground(true)
        }
        #elseif canImport(UIKit)
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setIsBackground(true)
        }
        notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setIsBackground(false)
        }
        notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setIsBackground(false)
        }
        // 電源状態(充電中かどうか)を見るためにバッテリー監視を有効にする。
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
            self.setIsBackground(UIApplication.shared.applicationState == .background)
        }
        #endif
    }

    private func setIsBackground(_ newValue: Bool) {
        lock.lock()
        let changed = isBackgroundCache != newValue
        isBackgroundCache = newValue
        lock.unlock()
        if changed {
            NSLog("NovelSpeaker.VoicevoxPrefetchThrottle: [\(VoicevoxCore.logTimestamp())] isBackground=\(newValue) parameters=\(currentParameters)")
            if newValue {
                // 前景では上限が緩いため、背面に入る時点で大量の先行合成が積まれている事がある。
                // 積まれたタスクは背面に入っても走り続けて CPU を焼き、背面CPU上限による
                // 強制終了の原因になるので、未実行分はここで破棄する
                // (完了済みのキャッシュ=貯金はそのまま残る)。
                VoicevoxCore.shared.scheduleCancelPendingPrefetch()
            }
        }
    }

    var isBackground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isBackgroundCache
    }

    /// 外部電源(AC/USB)に接続されているか。
    var isOnExternalPower: Bool {
        #if os(watchOS)
        // WatchKit のバッテリー監視はアプリ側の明示的な有効化が必要で、
        // 背面では取得できない事もあるため、安全側(=絞る方)に倒して false を返す。
        return false
        #elseif canImport(UIKit)
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
        #else
        return false
        #endif
    }

    /// 現在の状況に応じた先行合成パラメータ。
    var currentParameters: VoicevoxPrefetchParameters {
        return VoicevoxPrefetchThrottlePolicy.parameters(
            isBackground: isBackground,
            isOnExternalPower: isOnExternalPower,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}
