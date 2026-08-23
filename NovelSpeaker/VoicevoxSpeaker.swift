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

    // メディアサービスの再起動で作り直す必要があるので let にはできない
    // (再起動すると、これらは全て無効なオブジェクトになる。reloadSynthesizer() 参照)。
    private var engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timePitch = AVAudioUnitTimePitch()

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

    // MARK: - 割り込みから戻る時に、頭まで巻き戻らないための控え
    //
    // 割り込み(アラーム等)は、ブロックの途中で音を奪っていく。
    // 途中の位置から頼み直すと「その位置から末尾まで」が別の本文になり、
    // 作り置きが当たらず合成のやり直しになる(=止めた瞬間に声が出ない)。
    // かといってブロックの頭から鳴らすと、長いブロックでは200文字ほど聞き直す事になる。
    // そこで **頼むのはブロック丸ごと(作り置きが当たる)・鳴らす時に音声を飛ばす** 形にする。
    /// 今鳴らしている音声の、等速での長さ。
    private var currentAudioSeconds: Double = 0
    /// 今鳴らしている音声を、頭から何秒ぶん飛ばして鳴らし始めたか(等速換算)。
    private var currentSkippedSeconds: Double = 0
    /// 鳴らし始めた時刻。
    private var currentPlaybackStartDate: Date?
    /// 割り込みで止まった本文(これと同じ本文を次に頼まれたら飛ばす)。
    private var interruptedResumeText: String = ""
    /// 割り込みで止まった位置(等速換算の秒)。ここから少し手前を鳴らし始める。
    private var interruptedResumeSeconds: Double = 0
    /// 止まった所より手前に戻す量。少し重ねた方が話の繋がりが取れる。
    private static let resumeOverlapSeconds: Double = 2.0
    static var resumeOverlapSecondsForTesting: Double { return resumeOverlapSeconds }
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
    // メディアサービスの再起動も StorySpeaker が持ち場(音まわりを丸ごと作り直す
    // 必要があり、話者だけでは完結しないため。reloadSynthesizer() で呼ばれる)。
    // ここで見るのは、そこに乗らない「グラフだけが壊れる」もの:
    //
    //  - 出力先が変わった(AirPods が繋がった・CarPlay・Bluetooth の切り替え等)。
    //    エンジンは自分で止まり、接続も切れる。抜けた時は StorySpeaker が
    //    止めて少し戻してくれるが、**挿さった時**は誰も何もしていなかった。
    //
    // 繋ぎ直して**今のブロックを頭から鳴らし直す**。
    // 途中から再開する手段が無い(撃ったバッファのどこまで鳴ったか分からない)ため、
    // 少し戻って聞き直す形にする。ヘッドフォンが抜けた時に25文字戻すのと同じ考え方。
    private func registerAudioGraphNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioEngineConfigurationDidChange(notification:)),
                           name: .AVAudioEngineConfigurationChange, object: nil)
    }

    @objc private func audioEngineConfigurationDidChange(notification: Notification) {
        // 他の話者のエンジンの分まで拾わないよう、自分の物だけを見る。
        guard (notification.object as AnyObject?) === engine else { return }
        DispatchQueue.main.async {
            // ★繋ぎ直しは**必ず**やる。鳴らし直すかどうかとは別。
            //
            // 出力先が変わると、エンジンが止まるだけでなく**接続そのものが切れる**。
            // 以前はここを「鳴らし直す」と一緒にしていたため、鳴らし直さない判断に
            // なった時(このブロックを撃ち終えていた等)に connectedFormat が古いままになり、
            // 次に鳴らす時 ensureGraphConnected が「同じフォーマットだから繋ぎ直し不要」と
            // 判断して切れたままの接続で start してしまう。
            // 実機では「Bluetooth を繋ぐと⏸のまま止まり、再生ボタンを押しても鳴らない」
            // (何度か押すとようやく鳴る)という形で出た。
            self.connectedFormat = nil
            if self.engine.isRunning {
                self.engine.stop()
            }
            AppInformationLogger.AddLog(
                message: "VoicevoxSpeaker: 音の出力先が変わったので、再生の経路を繋ぎ直します",
                appendix: [
                    "isUtteranceActive": "\(self.m_IsUtteranceActive)",
                    "isPaused": "\(self.m_IsPaused)",
                ], isForDebug: true)
            self.scheduleRestartAfterAudioGraphBreak(reason: "音の出力先が変わった")
        }
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
    /// ★もう一つ、待つ事に意味がある。
    ///
    /// 出力先の切り替えは瞬時ではなく、古い経路が死んでから新しい経路が
    /// 鳴り出すまでに数秒かかる(実機で Bluetooth イヤホンを繋いだ時に3〜4秒)。
    /// その間に鳴らし直しても、鳴らした先が死んでいるので本文が聞こえないまま流れる。
    /// **どのみち音は出ない時間**なので、少し待ってから鳴らし直す方が
    /// 無音の長さは変わらずに、聞き逃す本文だけが減る。
    /// ただし長く待ちすぎると、経路が生きた後の分がそのまま無音になるので、
    /// 切り替えにかかる時間の全部は待たない。
    private static let restartDelayAfterAudioGraphBreak: TimeInterval = 1.0

    private func scheduleRestartAfterAudioGraphBreak(reason: String) {
        let myGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelayAfterAudioGraphBreak) { [weak self] in
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
        // (繋ぎ直しの指示は、この呼び出しの前に済ませてある)
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

        // 割り込みから戻ってきた時は、止まった所の少し手前まで音声を飛ばす。
        // (合成はブロック丸ごとで頼んでいるので、ここまでは作り置きがそのまま当たっている)
        let totalAudioSeconds = Double(buffer.frameLength) / max(1, buffer.format.sampleRate)
        var skippedSeconds = 0.0
        var playbackBuffer = buffer
        if text == interruptedResumeText {
            let target = max(0, interruptedResumeSeconds - Self.resumeOverlapSeconds)
            // 末尾ぎりぎりまで飛ばすと一瞬で終わってしまうので、少しは残す。
            if target > 0, target < totalAudioSeconds - Self.resumeOverlapSeconds,
               let trimmed = Self.buffer(buffer, skippingSeconds: target) {
                playbackBuffer = trimmed
                skippedSeconds = target
            }
            interruptedResumeText = ""
            interruptedResumeSeconds = 0
        }
        currentAudioSeconds = totalAudioSeconds
        currentSkippedSeconds = skippedSeconds
        currentPlaybackStartDate = Date()

        // 直前に鳴らし終えてから、ここで実際に音が出るまでが「意図しない無音」。
        // 話者をまたいでも拾えるよう、起点は VoicevoxSilenceReporter 側で持っている。
        VoicevoxSilenceReporter.shared.notePlaybackStarting()

        startProgressReporting(text: text, buffer: playbackBuffer, generation: myGeneration,
                               skippedSeconds: skippedSeconds, totalAudioSeconds: totalAudioSeconds)

        playerNode.scheduleBuffer(playbackBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
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
        do {
            try ensureGraphConnected(format: format)
            if engine.isRunning { return }
            try engine.start()
        } catch {
            // ここへ来る理由は2つある。
            //  ・音声セッションがまだ有効になっていない(StartSpeech が別キューで有効化するため)
            //  ・グラフが壊れている(出力先の変更やメディアサービスの再起動)
            // どちらか分からないので、両方やってからもう一度だけ試す。
            AppInformationLogger.AddLog(
                message: "VoicevoxSpeaker: 再生の開始に失敗したので、経路を作り直して試し直します: \(error.localizedDescription)",
                isForDebug: true)
            try? AVAudioSession.sharedInstance().setActive(true)
            rebuildAudioGraph()
            try ensureGraphConnected(format: format)
            try engine.start()
        }
    }

    /// エンジンとノードを捨てて作り直す。接続は次に鳴らす時に張り直される。
    private func rebuildAudioGraph() {
        engine.stop()
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitch = AVAudioUnitTimePitch()
        engine.attach(playerNode)
        engine.attach(timePitch)
        connectedFormat = nil
    }

    /// - Parameters:
    ///   - buffer: 実際に鳴らすバッファ(飛ばした後の残り)。
    ///   - skippedSeconds: 頭から飛ばした秒数(等速換算)。
    ///   - totalAudioSeconds: 飛ばす前の全体の長さ(等速換算)。
    private func startProgressReporting(text: String, buffer: AVAudioPCMBuffer, generation myGeneration: Int,
                                        skippedSeconds: Double = 0, totalAudioSeconds: Double = 0) {
        stopProgressReporting()
        let cumulativeWeights = Self.cumulativeSpeechWeights(for: text)
        guard let totalWeight = cumulativeWeights.last, totalWeight > 0, buffer.format.sampleRate > 0 else { return }
        // 音声を飛ばした分だけ、読み上げ位置の推定も進んだ所から始める。
        // (飛ばしたのに位置が頭を指すと、ハイライトが本文とずれる)
        let skippedFraction = totalAudioSeconds > 0 ? min(1.0, max(0.0, skippedSeconds / totalAudioSeconds)) : 0
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
            let remainingFraction = min(1.0, max(0.0, elapsed / duration))
            let fraction = skippedFraction + remainingFraction * (1.0 - skippedFraction)
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

    /// ★音まわりのオブジェクトを作り直す。
    ///
    /// 普段は必要ない(VOICEVOX には AVSpeechSynthesizer のような
    /// 「同一プロセス内でエンジンが固着する」問題が無く、AVAudioEngine は使い回せる)。
    ///
    /// 要るのは**メディアサービスが再起動した時**。iOS の音を一手に扱っている
    /// mediaserverd が落ちて再起動すると、AVAudioEngine も AVAudioPlayerNode も
    /// AVAudioUnit も**全て無効なオブジェクトになる**。
    /// 繋ぎ直しても無効なノードのままなので、捨てて作り直すしかない。
    /// (呼ぶのは StorySpeaker。セッションの設定し直しと順番を合わせる必要があるため)
    func reloadSynthesizer() {
        generation += 1
        m_IsUtteranceActive = false
        m_IsPaused = false
        stopProgressReporting()
        rebuildAudioGraph()
        fallbackSpeaker?.reloadSynthesizer()
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

    /// 頭から指定秒数ぶんを落とした音声を作る。作れなければ nil。
    ///
    /// 中身をコピーするだけ。format を変えないので、そのまま同じ経路に流せる。
    /// (テストから叩けるように internal にしてある)
    static func buffer(_ source: AVAudioPCMBuffer, skippingSeconds seconds: Double) -> AVAudioPCMBuffer? {
        let sampleRate = source.format.sampleRate
        guard sampleRate > 0, seconds > 0 else { return nil }
        let skipFrames = AVAudioFrameCount(seconds * sampleRate)
        guard skipFrames > 0, skipFrames < source.frameLength else { return nil }
        let remaining = source.frameLength - skipFrames
        guard let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: remaining) else { return nil }
        result.frameLength = remaining
        let channelCount = Int(source.format.channelCount)
        if let from = source.floatChannelData, let to = result.floatChannelData {
            for channel in 0..<channelCount {
                let stride = source.stride
                for frame in 0..<Int(remaining) {
                    to[channel][frame * stride] = from[channel][(frame + Int(skipFrames)) * stride]
                }
            }
        } else if let from = source.int16ChannelData, let to = result.int16ChannelData {
            for channel in 0..<channelCount {
                let stride = source.stride
                for frame in 0..<Int(remaining) {
                    to[channel][frame * stride] = from[channel][(frame + Int(skipFrames)) * stride]
                }
            }
        } else if let from = source.int32ChannelData, let to = result.int32ChannelData {
            for channel in 0..<channelCount {
                let stride = source.stride
                for frame in 0..<Int(remaining) {
                    to[channel][frame * stride] = from[channel][(frame + Int(skipFrames)) * stride]
                }
            }
        } else {
            return nil
        }
        return result
    }

    /// ★割り込みで止められた。次に同じ本文を頼まれたら、ここまで音声を飛ばす。
    ///
    /// 飛ばす量は「経過時間から見た今の位置」で決める。
    /// VOICEVOX には再生位置を教えてくれる口が無いので、
    /// 読み上げ位置の推定と同じく鳴らし始めからの経過時間で測る(数百ミリ秒の誤差はある)。
    /// 少し手前(resumeOverlapSeconds)から鳴らすので、多少ずれても話は繋がる。
    func noteInterruptedForResume() {
        guard isUsingFallbackSpeaker == false,
              m_IsUtteranceActive,
              currentSpeechText.isEmpty == false,
              let startDate = currentPlaybackStartDate else {
            interruptedResumeText = ""
            interruptedResumeSeconds = 0
            return
        }
        let playbackRate = max(0.0001, Double(timePitch.rate))
        let playedAudioSeconds = Date().timeIntervalSince(startDate) * playbackRate
        let position = currentSkippedSeconds + playedAudioSeconds
        // 鳴り終わっているなら、次のブロックへ進むだけなので控えは要らない。
        guard position < currentAudioSeconds else {
            interruptedResumeText = ""
            interruptedResumeSeconds = 0
            return
        }
        interruptedResumeText = currentSpeechText
        interruptedResumeSeconds = max(0, position)
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
