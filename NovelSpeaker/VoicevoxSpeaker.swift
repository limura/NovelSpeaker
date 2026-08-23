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
    // ユーザーが明示的に Pause() した状態かどうか。
    // isPaused() を playerNode.isPlaying から推測すると、ブロックの合成中やブロック間で
    // (一時停止していないのに)再生していない状態も「一時停止中」と誤判定してしまい、
    // MultiVoiceSpeaker.isAnySynthesizerActive が誤って真になって
    // SpeechBlockSpeaker.StartSpeech() が idle 待ちに落ち、再生開始時に m_IsSpeaking が
    // 立たず「再生ボタンが▶️のまま/スキップボタンが有効化されない」という不具合の原因になっていた。
    // そのため、一時停止は推測ではなく明示フラグで管理する。
    private var m_IsPaused: Bool = false
    // 「今この発話(utterance)が進行中か」の明示フラグ。
    // isSpeaking() を playerNode.isPlaying で判定すると、AVAudioPlayerNode は再生バッファを
    // 撃ち終えても stop() するまで isPlaying=true を返し続けるため、発話が自然終了した(Stop()を
    // 経ていない)スピーカーが「再生中」を報告し続け、MultiVoiceSpeaker.isAnySynthesizerActive が
    // 真のままになって次の再生開始時に上記の「▶️のまま」不具合を引き起こす。
    // performSpeech で true、再生完了/停止で false にする。
    private var m_IsUtteranceActive: Bool = false


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

    // 音声モデルが手元に無い時に、代わりに読み上げてもらう端末の音声。
    // ここで諦めて無音のまま次のブロックへ進むと、
    // 「一部だけ読まれない」という一番分かりにくい壊れ方になる。
    private var fallbackSpeaker: Speaker?
    private var isUsingFallbackSpeaker = false

    init(styleId: UInt32) {
        self.styleId = styleId
        super.init()
        engine.attach(playerNode)
        engine.attach(timePitch)
        // ここでは接続しない(このタイミングでの適切なフォーマットが分からないため)。
        // 実際のバッファが得られた時点(playBuffer)でそのフォーマットに合わせて接続する。
        registerAudioGraphNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 再生の足元が崩れた時

    // ★AVAudioEngine は、外の都合で勝手に止まる事がある。
    //
    // 止まると、撃ってあるバッファの再生完了コールバックが**二度と来ない**。
    // このスピーカーは次のブロックへ進む合図をそれ一本に頼っているので、
    // 気づかないと「音は出ないのに再生中のつもりで固まる」という
    // 一番分かりにくい壊れ方になる(アラームで実際に踏んだ)。
    //
    // 割り込み(アラーム・電話・他アプリ)は StorySpeaker がまとめて面倒を見ている
    // (エンジンによらず同じ扱いにしたいので、あちらが持ち場)。
    // ここで見るのは、そこに乗らない「グラフだけが壊れる」2つ:
    //
    //  - 出力先が変わった(AirPods が繋がった・CarPlay・Bluetooth の切り替え等)。
    //    エンジンは自分で止まり、接続も切れる。抜けた時は StorySpeaker が
    //    止めて少し戻してくれるが、**挿さった時**は誰も何もしていなかった。
    //  - メディアサービスの再起動。音まわりが丸ごと作り直される。
    //
    // どちらも、繋ぎ直して**今のブロックを頭から鳴らし直す**。
    // 途中から再開する手段が無い(撃ったバッファのどこまで鳴ったか分からない)ため、
    // 少し戻って聞き直す形にする。ヘッドフォンが抜けた時に25文字戻すのと同じ考え方。
    private func registerAudioGraphNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioEngineConfigurationDidChange(notification:)),
                           name: .AVAudioEngineConfigurationChange, object: nil)
        center.addObserver(self, selector: #selector(mediaServicesWereReset(notification:)),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    @objc private func audioEngineConfigurationDidChange(notification: Notification) {
        // 他の話者のエンジンの分まで拾わないよう、自分の物だけを見る。
        guard (notification.object as AnyObject?) === engine else { return }
        scheduleRestartAfterAudioGraphBreak(reason: "音の出力先が変わった")
    }

    @objc private func mediaServicesWereReset(notification: Notification) {
        scheduleRestartAfterAudioGraphBreak(reason: "メディアサービスが再起動した")
    }

    /// ★すぐには鳴らし直さず、ひと呼吸おいてから判断する。
    ///
    /// 同じ出来事で StorySpeaker 側も動く事がある。
    /// 例えばヘッドフォンが抜けた時、あちらは「止めて25文字戻す」と決めていて、
    /// こちらへは同時にグラフが壊れた通知が来る。どちらが先に届くかは決まっていない。
    /// 先にこちらが鳴らし直してしまうと、止めると決めた側の判断を一瞬だけ
    /// 上書きしてしまう(抜いた直後に一声鳴る)。
    /// あちらの判断が landing してから見れば、止まっていれば
    /// 下の guard で何もしない事になり、**止めると決めた側が必ず勝つ**。
    ///
    /// 待っている間の無音は、どのみち鳴らし直すので体感は変わらない。
    private func scheduleRestartAfterAudioGraphBreak(reason: String) {
        let myGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, myGeneration == self.generation else { return }
            self.restartCurrentSpeechAfterAudioGraphBreak(reason: reason)
        }
    }

    /// 壊れたグラフを捨てて、今読んでいたブロックを頭から鳴らし直す。
    ///
    /// ★「止まっているなら何もしない」。
    /// ヘッドフォンを挿し直した時に勝手に読み始めないのは、この guard による
    /// (抜いた時点で StorySpeaker が止めているので、挿し直しでは既に止まっている)。
    /// AVSpeechSynthesizer の頃と同じで、挿し直しでは再開しない。
    private func restartCurrentSpeechAfterAudioGraphBreak(reason: String) {
        // 鳴っていなかったなら何もしない。
        // (一時停止中・停止済みも含む。停止は Stop() が世代を進めて始末してある)
        guard m_IsUtteranceActive, m_IsPaused == false, isUsingFallbackSpeaker == false else { return }
        let text = currentSpeechText
        guard text.isEmpty == false else { return }
        AppInformationLogger.AddLog(
            message: "VoicevoxSpeaker: \(reason)ので、今のブロックを鳴らし直します",
            isForDebug: true)
        // ユーザー操作ではないが、ここでの無音は「作り置きが足りない」せいではないので
        // 無音の計測からは外す(原因の切り分けが濁るため)。
        VoicevoxSilenceReporter.shared.notePlaybackInterrupted()
        stopProgressReporting()
        playerNode.stop()
        // 出力フォーマットが変わっている可能性があるので、繋ぎ直させる。
        connectedFormat = nil
        // performSpeech が世代を進めるので、古いバッファの完了通知が今さら来ても無視される。
        // 音声はキャッシュから返るのが普通なので、合成し直しにはならない。
        performSpeech(text: text)
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
        m_IsPaused = false
        m_IsUtteranceActive = true
        isUsingFallbackSpeaker = false
        currentSpeechText = text
        generation += 1
        let myGeneration = generation

        // 今まさに再生に必要な合成なので、優先度は先行合成(.utility)より高くしておく
        // (actor上での順番待ちが少しでも有利になるように。実行中のC呼び出し自体を
        // 割り込ませることはできないため、完全な保証ではない)。
        Task(priority: .userInitiated) {
            do {
                let wavData = try await VoicevoxCore.shared.synthesize(text: text, styleId: styleId)
                let buffer = try Self.pcmBuffer(fromWavData: wavData)
                await MainActor.run {
                    self.playBuffer(buffer, generation: myGeneration, text: text)
                }
            } catch {
                // ★音声モデルが無いだけなら、端末の音声で代わりに読む。
                // ここを「失敗」で終わらせると、作成済みの音声がある箇所だけ読まれて
                // 無い箇所は飛ばされる、という一番分かりにくい壊れ方になる
                // (ブロックの途中から再生を始めた時は、作ってあるはずの箇所でも
                //  本文が一致せず合成が必要になるため、これは普通に起きる)。
                if VoicevoxCore.cachedStyles.contains(where: { $0.styleId == self.styleId }) == false {
                    VoicevoxMissingModelNotice.post(styleId: self.styleId)
                    await MainActor.run {
                        self.speakWithFallbackSpeaker(text: text, generation: myGeneration)
                    }
                    return
                }
                AppInformationLogger.AddLog(message: "VoicevoxSpeaker: synthesize failed: \(error.localizedDescription)", appendix: [
                    "text": text,
                    "styleId": "\(styleId)",
                ], isForDebug: true)
                await MainActor.run {
                    guard myGeneration == self.generation else { return }
                    self.m_IsUtteranceActive = false
                    self.m_Delegate?.finishSpeak(isCancel: true, speechString: text)
                }
            }
        }
    }

    /// 音声モデルが無い箇所を、端末の音声で読み上げる。
    ///
    /// 進行状況(発話中か・一時停止中か)の問い合わせは、
    /// この間だけ端末側の話者へ委ねる。こちらのフラグで答えると
    /// 「読み上げているのに終わった事になっている」等の食い違いが起きる。
    private func speakWithFallbackSpeaker(text: String, generation myGeneration: Int) {
        guard myGeneration == generation else { return }
        let speaker = fallbackSpeaker ?? Speaker()
        fallbackSpeaker = speaker
        speaker.SetVoiceWith(identifier: RealmSpeakerSetting.GuessBestVoiceIdentifier(), language: "ja-JP")
        speaker.pitch = m_Pitch
        speaker.rate = m_Rate
        speaker.volume = m_Volume
        speaker.delay = m_Delay
        speaker.delegate = m_Delegate
        isUsingFallbackSpeaker = true
        m_IsUtteranceActive = false
        speaker.Speech(text: text)
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer, generation myGeneration: Int, text: String) {
        guard myGeneration == generation else { return }
        do {
            try startEngineIfNeeded(format: buffer.format)
        } catch {
            AppInformationLogger.AddLog(message: "VoicevoxSpeaker: AVAudioEngine start failed: \(error.localizedDescription)", appendix: [:], isForDebug: true)
            m_IsUtteranceActive = false
            m_Delegate?.finishSpeak(isCancel: true, speechString: text)
            return
        }

        timePitch.rate = Self.timePitchRate(fromUtteranceRate: m_Rate)
        // 「必要CPU率 = 再生速度倍率 × RTF」なので、実測ログに再生速度も残しておく
        // (VOICEVOX は常に1倍速で合成し、速度はこの timePitch.rate で変えている)。
        // 生成が実時間の何倍速かだけ分かっても、再生がそれより速ければ貯金は減る。
        // 両方を並べておかないと、追いつけていない原因が生成側なのか速度設定なのか決められない。
        VoicevoxCPUUsageReporter.shared.notePlaybackRate(Double(timePitch.rate))
        timePitch.pitch = Self.timePitchCents(fromPitchMultiplier: m_Pitch)
        playerNode.volume = max(0.0, min(1.0, m_Volume))

        // 直前に鳴らし終えてから、ここで実際に音が出るまでが「意図しない無音」。
        // 話者をまたいでも拾えるよう、起点は VoicevoxSilenceReporter 側で持っている。
        VoicevoxSilenceReporter.shared.notePlaybackStarting()

        startProgressReporting(text: text, buffer: buffer, generation: myGeneration)

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, myGeneration == self.generation else { return }
                // このブロックの音声を撃ち終えた。次のブロックが来れば performSpeech で
                // 再び true になる。次が無ければ(発話終了)これで false のままになる。
                self.m_IsUtteranceActive = false
                self.stopProgressReporting()
                let delaySeconds = max(0.0, self.m_Delay)
                // 次のブロックが鳴り始めるまでの間隔を測るための基準点。
                VoicevoxSilenceReporter.shared.notePlaybackEnded(intentionalDelay: delaySeconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
                    guard myGeneration == self.generation else { return }
                    self.m_Delegate?.finishSpeak(isCancel: false, speechString: text)
                }
            }
        }
        playerNode.play()
    }

    /// エンジンを鳴らせる状態にする。
    ///
    /// ★一度で諦めない。StorySpeaker.StartSpeech() は音声セッションの有効化を
    /// 別のキューへ投げてから読み上げを始めるので、合成が速いと
    /// **セッションが有効になる前に** ここへ来る事がある。
    /// その時 engine.start() は失敗し、以前はそのまま「このブロックは中止」に
    /// 落としていたため、再生ボタンを1回押しても何も始まらず、
    /// もう一度押すと始まる(その頃にはセッションが有効になっている)という
    /// 症状になっていた。アラームで中断された直後は特に踏みやすい。
    /// 失敗したらセッションを有効にしてから、もう一度だけ試す。
    private func startEngineIfNeeded(format: AVAudioFormat) throws {
        try ensureGraphConnected(format: format)
        if engine.isRunning { return }
        do {
            try engine.start()
        } catch {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        }
    }

    private func startProgressReporting(text: String, buffer: AVAudioPCMBuffer, generation myGeneration: Int) {
        stopProgressReporting()
        let cumulativeWeights = Self.cumulativeSpeechWeights(for: text)
        guard let totalWeight = cumulativeWeights.last, totalWeight > 0, buffer.format.sampleRate > 0 else { return }
        // frameLength/sampleRate は等速(1倍)での音声長。実際の再生は timePitch.rate 倍速で行われるため、
        // 実際の再生時間は (等速長 / 再生倍率) になる。ここで倍率を割らずに等速長のまま進捗を按分すると、
        // 例えば2倍速では実際は半分の時間で再生が終わるのに表示上の位置は半分までしか進まない
        // (=「ブロックの半分あたりを示した所で発話が終わる」)という位置ずれになる。
        let playbackRate = max(0.0001, Double(timePitch.rate))
        let duration = Double(buffer.frameLength) / buffer.format.sampleRate / playbackRate
        guard duration > 0 else { return }
        let startDate = Date()
        // 推定位置は必ず前進のみ(単調増加)にする。時間按分だけだと、丸めや下流側
        //(SpeechBlockSpeaker.willSpeakRange)での speech→display 位置再マッピングとの
        // 兼ね合いで、ハイライトが1〜2文字前後に細かく行ったり来たりして目まぐるしく
        // 見えてしまうため、一度進んだ位置より手前は指さないようにして安定させる。
        var lastReportedIndex = -1
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, myGeneration == self.generation else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(startDate)
            let fraction = min(1.0, max(0.0, elapsed / duration))
            let targetWeight = fraction * totalWeight
            // cumulativeWeights[i] は「文字 i まで読み終えた時点」の累積重み。
            // targetWeight を超える最初の文字を「今読んでいる位置」とみなす。
            var index = cumulativeWeights.count - 1
            for (i, weight) in cumulativeWeights.enumerated() where weight >= targetWeight {
                index = i
                break
            }
            if index <= lastReportedIndex { return } // 後退・同位置なら通知しない(ブレ防止)
            lastReportedIndex = index
            self.m_Delegate?.willSpeakRange(range: NSRange(location: index, length: 1))
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // 改行・空白・区切り記号の連続("。。。。。。"等)はVOICEVOXが実際にはほぼ音声時間を
    // 使わない(あるいはまとめて短く発話される)ため、経過時間から読み上げ位置を按分推定する際に
    // 通常の文字と同じ重みで扱うと、そうした区間が長いほど推定位置が実際より大きく先行してしまう
    // (実機で「発話箇所と全然違う場所を示す」という形で確認された)。
    // ここでは目安として、そのような文字の重みを下げてから累積させることで、推定精度の近似を改善する。
    // ※ あくまで文字種による近似であり、VOICEVOX側の実際の音素タイミングを見ているわけではない。
    private static func speechWeight(for character: Character) -> Double {
        if character.isWhitespace || character.isNewline {
            return 0.05
        }
        if character.isPunctuation || character.isSymbol {
            return 0.15
        }
        return 1.0
    }

    private static func cumulativeSpeechWeights(for text: String) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(text.count)
        var sum = 0.0
        for character in text {
            sum += speechWeight(for: character)
            result.append(sum)
        }
        return result
    }

    private func stopProgressReporting() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func Stop() {
        generation += 1
        let myGeneration = generation
        m_IsPaused = false
        m_IsUtteranceActive = false
        if isUsingFallbackSpeaker {
            // 端末の音声で読んでいる最中。停止の通知は向こうが出すので、
            // ここで重ねて出すと同じブロックを2回消費してしまう。
            isUsingFallbackSpeaker = false
            stopProgressReporting()
            fallbackSpeaker?.Stop()
            return
        }
        // ユーザー操作による停止は「意図しない無音」ではないので、計測の基準点を捨てる。
        VoicevoxSilenceReporter.shared.notePlaybackInterrupted()
        stopProgressReporting()
        playerNode.stop()
        let text = currentSpeechText
        // MultiVoiceSpeaker.Stop() は speechQueueLock を保持したままこの Stop() を呼ぶため、
        // ここで delegate?.finishSpeak(...) を同期的に呼ぶと MultiVoiceSpeaker.finishSpeak() 内の
        // 同じlockの再入でデッドロックする。そのため呼び出しは async に逃がす必要があるが、
        // その間に(wedge回復等で)新しい Speech() が同じインスタンスに対して発行されていたら、
        // この古いキャンセル通知はもう配送してはいけない(新しい発話のqueue項目を誤って
        // 消費してしまい、実際には発話していないのにブロックが進んでしまうバグになる)。
        // generation を比較して、世代が変わっていなければ(=まだ誰も上書きしていなければ)のみ配送する。
        DispatchQueue.main.async { [weak self] in
            guard let self = self, myGeneration == self.generation else { return }
            self.m_Delegate?.finishSpeak(isCancel: true, speechString: text)
        }
    }

    func Pause() {
        m_IsPaused = true
        if isUsingFallbackSpeaker {
            fallbackSpeaker?.Pause()
            return
        }
        // 一時停止中は「意図しない無音」ではないので、計測の基準点を捨てる。
        VoicevoxSilenceReporter.shared.notePlaybackInterrupted()
        stopProgressReporting()
        playerNode.pause()
    }

    func Resume() {
        if isUsingFallbackSpeaker {
            m_IsPaused = false
            fallbackSpeaker?.Resume()
            return
        }
        guard engine.isRunning else { return }
        m_IsPaused = false
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
        if isUsingFallbackSpeaker, let fallbackSpeaker = fallbackSpeaker {
            return fallbackSpeaker.isSpeaking()
        }
        // playerNode.isPlaying は再生バッファを撃ち終えても stop() まで true を返し続けるため
        // それには頼らず、明示的な「発話進行中」フラグで判定する(一時停止中は発話中ではない)。
        return m_IsUtteranceActive && !m_IsPaused
    }

    func isPaused() -> Bool {
        if isUsingFallbackSpeaker, let fallbackSpeaker = fallbackSpeaker {
            return fallbackSpeaker.isPaused()
        }
        // 「再生していない」ことから推測するのではなく、明示的に Pause() された状態のみを
        // 一時停止とみなす(ブロックの合成中やブロック間で再生していないだけの状態を
        // 一時停止と誤判定しないため)。
        return m_IsPaused
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
