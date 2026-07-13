//
//  WatchWidgetInteractiveSpike.swift
//  NovelSpeakerWatchWidget
//
//  対話型コンプリケーション(v2)の調査スパイク。★調査が終わったら撤去する★
//
//  確かめたいこと(実機でボタンを押すと、結果がウィジェット自身に表示される):
//  ① 素の AppIntent: どのプロセスで実行されるか + WCSession で iPhone へ sendMessage が通るか
//  ② openAppWhenRun = true: Watch アプリが前面に起動するか(「単体モードで再生開始」ボタンの経路)
//  ③ AudioPlaybackIntent: 実行プロセイスと、そこから音(AVSpeechSynthesizer)が出せるか
//
//  このファイルは Watch アプリと Widget Extension の両方のターゲットに入れる。
//  (AudioPlaybackIntent 等は「システムがアプリ側プロセスで intent を実行する」建て付けなので、
//   intent の型が両方に存在する必要がある。Apple のサンプルも共有コードに置く構成)
//
//  対話型ウィジェット(Button(intent:))は watchOS 11+ で、Smart Stack と一部の大型
//  コンプリケーションのみ。文字盤の通常コンプリケーションはタップ=アプリ起動のまま。
//

import Foundation
import AppIntents
import WatchConnectivity
import WidgetKit
import SwiftUI
import AVFoundation

// MARK: - 結果の記録(App Group 経由でウィジェットに表示する)

enum WidgetSpikeLog {
    static let resultKey = "WidgetSpikeLastResult"

    /// 実行プロセスの識別(アプリ本体か Widget Extension かが bundle id で分かる)
    static var processName: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "?"
        if bundleID.hasSuffix("widget") || bundleID.contains("WidgetExtension") {
            return "widget拡張"
        }
        return "アプリ(\(bundleID.components(separatedBy: ".").last ?? bundleID))"
    }

    static func record(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        UserDefaults(suiteName: WatchComplicationData.appGroupID)?
            .set("\(formatter.string(from: Date())) \(text)", forKey: resultKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> String {
        return UserDefaults(suiteName: WatchComplicationData.appGroupID)?
            .string(forKey: resultKey) ?? "ボタン未実行"
    }
}

// MARK: - WCSession の一時的な有効化(widget拡張プロセスで delegate が居ない場合用)

/// intent の実行プロセスに WCSession の delegate が居なければ(= Watch アプリ本体ではない)、
/// この場しのぎの delegate を立てて activation を待つ。アプリ本体プロセスで実行された場合は
/// PhoneSessionManager が既に delegate なので何もしない
private final class SpikeSessionDelegate: NSObject, WCSessionDelegate {
    static let shared = SpikeSessionDelegate()
    private var activationContinuation: CheckedContinuation<WCSessionActivationState, Never>?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        activationContinuation?.resume(returning: activationState)
        activationContinuation = nil
    }

    func waitForActivation(timeoutSeconds: Double) async -> WCSessionActivationState {
        let session = WCSession.default
        if session.activationState == .activated { return .activated }
        return await withCheckedContinuation { continuation in
            activationContinuation = continuation
            session.delegate = self
            session.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                self?.activationContinuation?.resume(returning: WCSession.default.activationState)
                self?.activationContinuation = nil
            }
        }
    }
}

/// WCSession で iPhone へ togglePlayPause を送ってみて、結果を文字列で返す(①③共用)
private func trySendTogglePlayPause() async -> String {
    guard WCSession.isSupported() else { return "WCSession非対応" }
    let session = WCSession.default
    if session.delegate == nil {
        let state = await SpikeSessionDelegate.shared.waitForActivation(timeoutSeconds: 3.0)
        guard state == .activated else { return "activate失敗(\(state.rawValue))" }
    }
    guard session.activationState == .activated else { return "未activate" }
    let reachable = session.isReachable
    return await withCheckedContinuation { continuation in
        var finished = false
        func finish(_ text: String) {
            guard !finished else { return }
            finished = true
            continuation.resume(returning: text)
        }
        // WatchMessage.swift は widget ターゲットに入れていないので直書き
        // (cmd=togglePlayPause / 返信の ok。WatchMessage.commandKey 等と同じ値)
        session.sendMessage(["cmd": "togglePlayPause"], replyHandler: { reply in
            let ok = reply["ok"] as? Bool ?? false
            finish("送信OK reply.ok=\(ok) reachable=\(reachable)")
        }, errorHandler: { error in
            finish("送信失敗 \((error as NSError).code) reachable=\(reachable)")
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            finish("返信タイムアウト reachable=\(reachable)")
        }
    }
}

// MARK: - テスト用 intent 3種

/// ① 素の AppIntent: 実行プロセスと WCSession の可否を調べる
struct SpikePhoneToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "テスト① iPhone再生トグル"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let result = await trySendTogglePlayPause()
        WidgetSpikeLog.record("① \(WidgetSpikeLog.processName): \(result)")
        return .result()
    }
}

/// ② openAppWhenRun: Watch アプリが前面起動するか
struct SpikeOpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "テスト② アプリ起動"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetSpikeLog.record("② \(WidgetSpikeLog.processName): 実行された(前面起動したかは目視)")
        return .result()
    }
}

/// ③ AudioPlaybackIntent: 実行プロセスと発話可否
struct SpikeAudioIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "テスト③ 音声テスト"
    static var isDiscoverable: Bool = false

    /// 発話が終わる前に解放されないよう保持する
    private static let synthesizer = AVSpeechSynthesizer()

    func perform() async throws -> some IntentResult {
        var audioResult = "?"
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try await audioSession.activate()
            let utterance = AVSpeechUtterance(string: "テストです")
            utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            Self.synthesizer.speak(utterance)
            audioResult = "発話発注OK"
        } catch {
            audioResult = "audio失敗 \((error as NSError).code)"
        }
        WidgetSpikeLog.record("③ \(WidgetSpikeLog.processName): \(audioResult)")
        return .result()
    }
}

// MARK: - 実験ウィジェット(accessoryRectangular)

struct SpikeEntry: TimelineEntry {
    let date: Date
    let lastResult: String
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: Date(), lastResult: "…")
    }
    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(SpikeEntry(date: Date(), lastResult: WidgetSpikeLog.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [SpikeEntry(date: Date(), lastResult: WidgetSpikeLog.load())], policy: .never))
    }
}

struct SpikeComplicationView: View {
    let entry: SpikeEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button(intent: SpikePhoneToggleIntent()) {
                    Text("①").font(.caption)
                }
                Button(intent: SpikeOpenAppIntent()) {
                    Text("②").font(.caption)
                }
                Button(intent: SpikeAudioIntent()) {
                    Text("③").font(.caption)
                }
            }
            .buttonStyle(.bordered)
            Text(entry.lastResult)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SpikeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.spike",
                            provider: SpikeProvider()) { entry in
            SpikeComplicationView(entry: entry)
        }
        .configurationDisplayName("ことせかい 実験")
        .description("対話型ウィジェットの調査用(後で消えます)")
        .supportedFamilies([.accessoryRectangular])
    }
}
