//
//  VoicevoxSpeaker.swift
//  NovelSpeaker
//
//  VOICEVOX(voicevox_core)で合成したPCMを AVAudioEngine + AVAudioPlayerNode で再生する
//  SpeechEngineSpeaking 実装。VOICEVOX_IOS_INTEGRATION.md §6-2/6-3 の設計を踏まえる。
//
//  倍速再生は合成側でなく AVAudioUnitTimePitch(再生側)で行う。理由は同ドキュメント通り、
//  キャッシュ(合成結果)を速度に依存させないため。
//
//  VOICEVOXのC APIには単語境界コールバックが無いため、willSpeakRange は
//  再生経過時間とテキスト文字数から按分した近似位置で擬似的に呼ぶ(単語単位ではなく近似)。
//

import Foundation
import AVFoundation

class VoicevoxSpeaker: NSObject, SpeechEngineSpeaking {
    let styleId: UInt32

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private var m_Pitch: Float = 1.0
    private var m_Rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var m_Volume: Float = 1.0
    private var m_Delay: TimeInterval = 0.0
    private var m_Delegate: SpeakRangeDelegate? = nil
    private(set) var isSpeechKicked: Bool = false

    // 現在再生中(または直前に再生した)テキスト。finishSpeak の speechString に使う。
    private var currentSpeechText: String = ""
    // Stop() やエンジン破棄との競合を避けるための世代カウンタ。
    private var generation: Int = 0
    private var progressTimer: Timer?
    // playerNode→timePitch→mainMixer を現在何のフォーマットで接続しているか。
    // VOICEVOXのWAVは24kHz/monoで一定のはずだが、接続時のフォーマットと
    // scheduleBuffer するバッファのフォーマットが食い違うと
    // "_outputFormat.channelCount == buffer.format.channelCount" で落ちるため、
    // 実際に得られたバッファのフォーマットで都度(初回のみ通常)接続し直す。
    private var connectedFormat: AVAudioFormat?

    init(styleId: UInt32) {
        self.styleId = styleId
        super.init()
        engine.attach(playerNode)
        engine.attach(timePitch)
        // ここでは接続しない(このタイミングでの適切なフォーマットが分からないため)。
        // 実際のバッファが得られた時点(playBuffer)でそのフォーマットに合わせて接続する。
    }

    private func ensureGraphConnected(format: AVAudioFormat) throws {
        if let connectedFormat = connectedFormat, connectedFormat == format {
            return
        }
        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        if wasRunning {
            try engine.start()
        }
    }

    func Speech(text: String) {
        if NiftyUtility.isTesting() {
            return
        }
        performSpeech(text: text)
    }

    // NiftyUtility.isTesting() のガードを経由しない実体。
    // @testable import 経由でユニットテストから直接呼び、実際の合成→再生パイプライン
    // (AVAudioEngineへのバッファ投入含む)を検証できるようにするため internal にしている。
    func performSpeech(text: String) {
        isSpeechKicked = true
        currentSpeechText = text
        generation += 1
        let myGeneration = generation

        Task {
            do {
                let wavData = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
                let buffer = try Self.pcmBuffer(fromWavData: wavData)
                await MainActor.run {
                    self.playBuffer(buffer, generation: myGeneration, text: text)
                }
            } catch {
                AppInformationLogger.AddLog(message: "VoicevoxSpeaker: synthesize failed: \(error.localizedDescription)", appendix: [:], isForDebug: true)
                await MainActor.run {
                    guard myGeneration == self.generation else { return }
                    self.m_Delegate?.finishSpeak(isCancel: true, speechString: text)
                }
            }
        }
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer, generation myGeneration: Int, text: String) {
        guard myGeneration == generation else { return }
        do {
            try ensureGraphConnected(format: buffer.format)
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxSpeaker: AVAudioEngine start failed: \(error.localizedDescription)", appendix: [:], isForDebug: true)
            m_Delegate?.finishSpeak(isCancel: true, speechString: text)
            return
        }

        timePitch.rate = Self.timePitchRate(fromUtteranceRate: m_Rate)
        timePitch.pitch = Self.timePitchCents(fromPitchMultiplier: m_Pitch)
        playerNode.volume = max(0.0, min(1.0, m_Volume))

        startProgressReporting(textLength: text.count, buffer: buffer, generation: myGeneration)

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, myGeneration == self.generation else { return }
                self.stopProgressReporting()
                let delaySeconds = max(0.0, self.m_Delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
                    guard myGeneration == self.generation else { return }
                    self.m_Delegate?.finishSpeak(isCancel: false, speechString: text)
                }
            }
        }
        playerNode.play()
    }

    private func startProgressReporting(textLength: Int, buffer: AVAudioPCMBuffer, generation myGeneration: Int) {
        stopProgressReporting()
        guard textLength > 0, buffer.format.sampleRate > 0 else { return }
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate
        guard duration > 0 else { return }
        let startDate = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, myGeneration == self.generation else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(startDate)
            let fraction = min(1.0, max(0.0, elapsed / duration))
            let index = min(textLength - 1, Int(fraction * Double(textLength)))
            self.m_Delegate?.willSpeakRange(range: NSRange(location: index, length: 1))
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopProgressReporting() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func Stop() {
        generation += 1
        stopProgressReporting()
        playerNode.stop()
        let text = currentSpeechText
        DispatchQueue.main.async { [weak self] in
            self?.m_Delegate?.finishSpeak(isCancel: true, speechString: text)
        }
    }

    func Pause() {
        stopProgressReporting()
        playerNode.pause()
    }

    func Resume() {
        guard engine.isRunning else { return }
        playerNode.play()
    }

    var pitch: Float {
        get { return m_Pitch }
        set { m_Pitch = value_ClampedPitch(newValue) }
    }
    var rate: Float {
        get { return m_Rate }
        set {
            if newValue > AVSpeechUtteranceMaximumSpeechRate {
                m_Rate = AVSpeechUtteranceMaximumSpeechRate
            } else if newValue < AVSpeechUtteranceMinimumSpeechRate {
                m_Rate = AVSpeechUtteranceMinimumSpeechRate
            } else {
                m_Rate = newValue
            }
        }
    }
    var volume: Float {
        get { return m_Volume }
        set { m_Volume = max(0.0, min(1.0, newValue)) }
    }
    var delay: TimeInterval {
        get { return m_Delay }
        set { m_Delay = newValue }
    }
    var delegate: SpeakRangeDelegate? {
        get { return m_Delegate }
        set { m_Delegate = newValue }
    }

    func isSpeaking() -> Bool {
        return playerNode.isPlaying
    }

    func isPaused() -> Bool {
        return !playerNode.isPlaying && isSpeechKicked && engine.isRunning
    }

    func reloadSynthesizer() {
        // VOICEVOXは AVSpeechSynthesizer のような「同一プロセス内でエンジンが固着する」問題が無いため
        // 何もしない(AVAudioEngineはこのインスタンスの生存期間中使い回す)。
    }

    private func value_ClampedPitch(_ value: Float) -> Float {
        return max(0.5, min(2.0, value))
    }

    // AVSpeechUtterance.rate(0.0...1.0, デフォルト0.5) を AVAudioUnitTimePitch.rate(再生速度倍率)に変換する。
    // 0.5(デフォルト)を等速(1.0倍)の基準点として比例配分する近似。
    private static func timePitchRate(fromUtteranceRate rate: Float) -> Float {
        let multiplier = rate / AVSpeechUtteranceDefaultSpeechRate
        return max(1.0 / 32.0, min(32.0, multiplier))
    }

    // AVSpeechUtterance.pitchMultiplier(0.5...2.0倍率) を AVAudioUnitTimePitch.pitch(セント単位)に変換する。
    private static func timePitchCents(fromPitchMultiplier multiplier: Float) -> Float {
        guard multiplier > 0 else { return 0 }
        let cents = 1200.0 * log2(Double(multiplier))
        return Float(max(-2400.0, min(2400.0, cents)))
    }

    private static func pcmBuffer(fromWavData data: Data) throws -> AVAudioPCMBuffer {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let file = try AVAudioFile(forReading: tempURL)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw VoicevoxCoreError.invalidWav
        }
        try file.read(into: buffer)
        return buffer
    }
}
