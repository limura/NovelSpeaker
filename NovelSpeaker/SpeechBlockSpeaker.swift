//
//  SpeechBlockSpeaker.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

class SpeechBlockSpeaker: NSObject, SpeakRangeDelegate {
    let speaker = MultiVoiceSpeaker()
    
    var speechBlockArray:[CombinedSpeechBlock] = []
    var currentSpeechBlockIndex:Int = 0
    var delegate:SpeakRangeDelegate? = nil
    var m_IsSpeaking = false
    // 現在のblockの先頭部分が全体のDisplayStringに対してどれだけのオフセットを持っているかの値
    var currentDisplayStringOffset = 0
    // Blockの先頭からの読み上げ開始位置のズレ(読み上げを開始する時はBlockの途中から始まる可能性があり、そのズレを表す)
    var currentBlockDisplayOffset = 0
    var currentBlockSpeechOffset = 0
    // 現在の先頭からの読み上げ中の位置(willSpeakRange で知らされる location と同じ値)
    var currentSpeakingLocation = 0
    // willSpeakRange が呼ばれた回数。synth wedge 検出で「発話が実際に進んだか」の判定に使う。
    var willSpeakRangeCallCount = 0
    // speak() ごとに増える世代番号。停止/次 speak で進行中の wedge watcher を失効させ、
    // 「停止→同じブロックで再生し直し」をまたいだ誤回復を防ぐ。
    private var speakGeneration = 0
    
    // StopSpeech() で実際に読み上げが止まった時のハンドラ
    let stopSpeechHandlerLockObject = NSObject()
    var stopSpeechHandler:(()->Void)? = nil
    
    override init() {
        super.init()
        speaker.delegate = self
    }
    
    var displayText:String {
        get {
            var result:String = ""
            for blockInfo in speechBlockArray {
                result += blockInfo.displayText
            }
            return result
        }
    }
    
    var speechText:String {
        get {
            var result:String = ""
            for blockInfo in speechBlockArray {
                result += blockInfo.speechText
            }
            return result
        }
    }
    var isSpeaking:Bool {
        get { return m_IsSpeaking }
    }
    var isSpeakingBySynthesizerState:Bool {
        get { return speaker.isSpeaking }
    }
    var isPausedBySynthesizerState:Bool {
        get { return speaker.isPaused }
    }
    var isAnySynthesizerActive:Bool {
        get { return speaker.isAnySynthesizerActive }
    }
    // 停止しきっていない synth に speak し直すのを避けるため、idle になるのを待ってから開始する予約。
    private var startWhenIdleWorkItem:DispatchWorkItem? = nil

    func GetSpeechTextWith(range:NSRange) -> String {
        let startOffset = DisplayLocationToSpeechLocation(location: range.location)
        let endOffset = DisplayLocationToSpeechLocation(location: range.location + range.length)
        let speechText = self.speechText
        let speechTextCount = speechText.unicodeScalars.count
        if speechTextCount < startOffset || speechTextCount < endOffset { return "" }
        let startIndex = speechText.index(speechText.startIndex, offsetBy: startOffset)
        let endIndex = speechText.index(speechText.startIndex, offsetBy: endOffset)
        return String(speechText[startIndex..<endIndex])
    }
    
    func DisplayLocationToSpeechLocation(location:Int) -> Int {
        var displayLocation = 0
        var speechLocation = 0
        
        for blockInfo in speechBlockArray {
            let displayTextCount = blockInfo.displayText.unicodeScalars.count
            let speechTextCount = blockInfo.speechText.unicodeScalars.count
            if displayLocation + displayTextCount > location {
                let displayOffset = Float(location - displayLocation)
                let speechOffset = displayOffset * Float(speechTextCount) / Float(displayTextCount)
                speechLocation += Int(speechOffset + 0.5)
                break
            }
            displayLocation += displayTextCount
            speechLocation += speechTextCount
        }
        return speechLocation
    }
    func SpeechLocationToDisplayLocation(location:Int) -> Int {
        var displayLocation = 0
        var speechLocation = 0
        
        for blockInfo in speechBlockArray {
            let displayTextCount = blockInfo.displayText.unicodeScalars.count
            let speechTextCount = blockInfo.speechText.unicodeScalars.count
            if speechLocation + speechTextCount > location {
                let speechOffset = Float(location - speechLocation)
                let displayOffset = speechOffset * Float(displayTextCount) / Float(speechTextCount)
                displayLocation += Int(displayOffset + 0.5)
                break
            }
            displayLocation += displayTextCount
            speechLocation += speechTextCount
        }
        return displayLocation
    }
    
    func GenerateSpeechTextFrom(displayTextRange:NSRange) -> String {
        var result = ""
        var location = 0
        for block in speechBlockArray {
            let currentBlockDisplayTextLength = block.displayText.unicodeScalars.count
            if currentBlockDisplayTextLength <= 0 { continue }
            if location + currentBlockDisplayTextLength <= displayTextRange.location
                || location > (displayTextRange.location + displayTextRange.length) {
                location += currentBlockDisplayTextLength
                continue
            }
            var currentBlockStartLocation = displayTextRange.location - location
            var currentBlockEndLocation = displayTextRange.location + displayTextRange.length - location
            if currentBlockStartLocation < 0 {
                currentBlockStartLocation = 0
            }
            if currentBlockEndLocation > currentBlockDisplayTextLength {
                currentBlockEndLocation = currentBlockDisplayTextLength
            }
            result += block.GenerateSpeechTextFrom(range: NSMakeRange(currentBlockStartLocation, currentBlockEndLocation - currentBlockStartLocation))
            location += currentBlockDisplayTextLength
        }
        return result
    }
    
    // 読み上げ中のSpeechBlockを次の物を指すように変化させます。
    // 次の物がなければ false を返します。
    func setNextSpeechBlock() -> Bool {
        // currentBlock が取り出せない場合はエラー
        guard currentSpeechBlockIndex < speechBlockArray.count else { return false }
        let currentBlock = speechBlockArray[currentSpeechBlockIndex]
        currentSpeechBlockIndex += 1
        currentDisplayStringOffset += currentBlock.displayText.unicodeScalars.count
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeakingLocation = currentDisplayStringOffset
        // 次のblock を取り出せないなら終わったという意味で false を返す
        guard currentSpeechBlockIndex < speechBlockArray.count else { return false }
        return true
    }
    
    func enqueueSpeechBlock(){
        guard currentSpeechBlockIndex < speechBlockArray.count else {
            self.finishSpeak(isCancel: true, speechString: "")
            return
        }
        let block = speechBlockArray[currentSpeechBlockIndex]
        let location = block.ComputeDisplayLocationFrom(speechLocation: currentBlockSpeechOffset) + currentDisplayStringOffset
        self.delegate?.willSpeakRange(range: NSMakeRange(location, 1))
        let speechText = block.GenerateSpeechTextFrom(displayLocation: currentBlockDisplayOffset)
        // 発音すべき文字を含まない(改行・空白のみの)発話を AVSpeechSynthesizer に渡すと、
        // 端末によってはコールバック(didStart/willSpeakRange/didFinish)を一切返さず synth が
        // 永久固着し、以後その声(使い回しの synth オブジェクト)での発話が全て無音になる。
        // これが「改行が沢山ある部分で発話できなくなる」バグの真因。
        // そのような block は synth に渡さず、即「発話完了」扱いにして次の block へ進める。
        // (deep recursion を避けるため main queue に逃がす。block.delay があれば尊重する)
        if speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let skipDelay = max(0, block.delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + skipDelay) { [weak self] in
                guard let self = self else { return }
                self.finishSpeak(isCancel: false, speechString: speechText)
            }
            return
        }
        speakGeneration += 1
        let generation = speakGeneration
        speaker.Speech(text: speechText, voiceIdentifier: block.voiceIdentifier, locale: block.locale, pitch: block.pitch, rate: block.rate, volume: block.volume, delay: block.delay)
        //print("Speech: \(speechText)")
        scheduleWedgeWatch(blockIndex: currentSpeechBlockIndex, willSpeakRangeCountAtSpeak: willSpeakRangeCallCount, speechTextCount: speechText.unicodeScalars.count, speechText: speechText, generation: generation)
    }

    // ログ用に改行・タブ等を見えるエスケープにし、長すぎる場合は切り詰める。
    static func escapeForLog(_ text:String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        if escaped.count > 40 {
            return String(escaped.prefix(40)) + "…"
        }
        return escaped
    }

    // synth wedge 検出(保険):
    // enqueueSpeechBlock で speak を投げたのに、一定時間経っても willSpeakRange が一度も来ず、
    // ブロックも進んでおらず、下層 synth も idle(発話中でも一時停止中でもない)なら、
    // speak が無音で飲まれて固着しているとみなし、ログに残した上で自己回復を試みる。
    // (本文の固着の主因(空白のみ発話)は enqueueSpeechBlock 側で予防済みだが、
    //  別要因で固着した場合でもアプリ再起動なしに復帰できるようにするための保険)
    // wedge とみなすまでの待ち時間。
    // 短すぎると「正当だがまだ立ち上がり中(synth が idle のまま)の発話」を固着と誤検出して
    // しまうため、speak()→isSpeaking=true の立ち上がり時間の最悪値を超える必要がある。
    // 実機計測では立ち上がりは iPhone 6s Plus でも最大 ~0.5秒(音声生成自体の遅さは
    // isSpeaking=true 中なので synthActive 判定で守られ、ここでは無視できる)。
    // その約3倍のマージンとして 1.5秒 とする。
    private let wedgeDetectTimeout:TimeInterval = 1.5
    private func scheduleWedgeWatch(blockIndex:Int, willSpeakRangeCountAtSpeak:Int, speechTextCount:Int, speechText:String, generation:Int) {
        if speechTextCount <= 0 { return } // 空発話はすぐ終わるので対象外
        // premium/enhanced 音声の起動レイテンシを考慮して長めに待つ。
        DispatchQueue.main.asyncAfter(deadline: .now() + wedgeDetectTimeout) { [weak self] in
            guard let self = self else { return }
            // 停止/次の speak で世代が変わっていたら、この watcher はもう現役ではないので何もしない
            //(「停止→同じブロックで再生し直し」をまたいだ誤回復を防ぐ)。
            if self.speakGeneration != generation { return }
            let progressed = self.willSpeakRangeCallCount != willSpeakRangeCountAtSpeak
            let blockMoved = self.currentSpeechBlockIndex != blockIndex
            let synthActive = self.isAnySynthesizerActive
            if self.m_IsSpeaking == true && progressed == false && blockMoved == false && synthActive == false {
                let message = "synth wedge疑い: speakしたが\(self.wedgeDetectTimeout)秒間発話が始まらずsynthもidle blockIndex=\(blockIndex) len=\(speechTextCount) text=\"\(Self.escapeForLog(speechText))\""
                NSLog("NovelSpeaker.SynthWedge: ⚠️ \(message)")
                AppInformationLogger.AddLog(message: message, appendix: [
                    "blockIndex": "\(blockIndex)",
                    "speechTextCount": "\(speechTextCount)",
                    "willSpeakRangeCallCount": "\(self.willSpeakRangeCallCount)",
                    "isSpeakingBySynthesizerState": "\(self.isSpeakingBySynthesizerState)",
                    "isPausedBySynthesizerState": "\(self.isPausedBySynthesizerState)",
                ], isForDebug: true)
                self.recoverFromWedge(blockIndex: blockIndex)
            }
        }
    }

    // 固着の自己回復: synth を作り直し、固着した block から再生し直す。
    // 原因が何であれアプリ再起動なしで復帰させるための保険。
    // wedgeRecoveryCount は「連続して回復に失敗した回数」。回復が成功して発話が1つでも
    // 進めば finishSpeak / willSpeakRange で 0 にリセットされるので、実際の運用では
    // 「回復は実質無制限・でも同じ箇所で延々失敗する時だけ打ち切り」になる。
    // (打ち切り時も読み上げを止めず、その block を飛ばして次へ進めて全体を継続させる)
    private let maxConsecutiveWedgeRecovery = 5
    private var wedgeRecoveryCount = 0
    private func recoverFromWedge(blockIndex:Int) {
        if wedgeRecoveryCount >= maxConsecutiveWedgeRecovery {
            // 同じ箇所で連続して回復に失敗した。これ以上 reload ループ(電池/CPU浪費)を
            // 続けず、この block は飛ばして次へ進める(読み上げ全体は止めない)。
            NSLog("NovelSpeaker.SynthWedge: 連続\(wedgeRecoveryCount)回回復失敗。blockIndex=\(blockIndex) を飛ばして次へ進む")
            wedgeRecoveryCount = 0
            speaker.Stop()
            speaker.reloadSynthesizer()
            if setNextSpeechBlock() != true {
                m_IsSpeaking = false
                self.delegate?.finishSpeak(isCancel: true, speechString: "")
                return
            }
            m_IsSpeaking = true
            enqueueSpeechBlock()
            return
        }
        wedgeRecoveryCount += 1
        NSLog("NovelSpeaker.SynthWedge: 回復試行(\(wedgeRecoveryCount)): synth を作り直して blockIndex=\(blockIndex) から再生し直す")
        // 固着した MultiVoiceSpeaker のキューを片付け、AVSpeechSynthesizer を作り直す。
        speaker.Stop()
        speaker.reloadSynthesizer()
        // 同じ block から発話し直す
        m_IsSpeaking = true
        enqueueSpeechBlock()
    }
    
    func setSpeechBlockArray(blockArray:[CombinedSpeechBlock]) {
        speechBlockArray = blockArray
        currentDisplayStringOffset = 0
        currentSpeechBlockIndex = 0
        currentSpeakingLocation = 0
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        
        resetRegisterdVoices()
    }
    func resetRegisterdVoices() {
        var voiceIdentifierDictionary:[String?:String?] = [:]
        for block in speechBlockArray {
            voiceIdentifierDictionary[block.voiceIdentifier] = block.locale
        }
        for (voiceIdentifier, locale) in voiceIdentifierDictionary {
            speaker.RegisterVoiceIdentifier(voiceIdentifier: voiceIdentifier, locale: locale)
        }
    }
    
    func SetTextWitoutSettings(content:String) {
        let dummySpeaker = RealmSpeakerSetting()
        let blockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: [], moreSplitMinimumLetterCount: 99999, defaultSpeaker: SpeakerSetting(from: dummySpeaker), sectionConfigList: [], waitConfigList: [], sortedSpeechModArray: [])
        setSpeechBlockArray(blockArray: blockArray)
    }
    
    func SetText(content:String, withMoreSplitTargets: [String], moreSplitMinimumLetterCount: Int, defaultSpeaker: SpeakerSetting, sectionConfigList: [SpeechSectionConfig], waitConfigList: [SpeechWaitConfig], sortedSpeechModArray: [SpeechModSetting]) {
        let blockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, sortedSpeechModArray: sortedSpeechModArray)
        setSpeechBlockArray(blockArray: blockArray)
    }

    func SetText(content:String, withMoreSplitTargets: [String], moreSplitMinimumLetterCount: Int, defaultSpeaker: SpeakerSetting, sectionConfigList: [SpeechSectionConfig], waitConfigList: [SpeechWaitConfig], speechModArray: [SpeechModSetting]) {
        let blockArray = StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: defaultSpeaker, sectionConfigList: sectionConfigList, waitConfigList: waitConfigList, speechModArray: speechModArray)
        setSpeechBlockArray(blockArray: blockArray)
    }
    
    func SetStory(story:Story, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int) {
        let blockArray = StoryTextClassifier.CategorizeStoryText(story: story, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount)
        setSpeechBlockArray(blockArray: blockArray)
    }

    func SetStory(story:Story) {
        SetStory(story: story, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max)
    }
    
    func StartSpeech() {
        if m_IsSpeaking == true { return }
        // 直前の停止(stopSpeaking(.immediate))が下層 synth 上でまだ完了していない状態で
        // ここで enqueue すると「発話中の synth に再度 speak」になり、AVAudioBuffer が壊れて
        // (mDataByteSize 0)synth が固着する恐れがある(コントロールセンターのシーク連打で
        // 起きていた wedge と同種)。synth が完全に idle になるのを待ってから開始する。
        if isAnySynthesizerActive {
            scheduleStartAfterSynthesizerIdle(retryCount: 0)
            return
        }
        startWhenIdleWorkItem?.cancel()
        startWhenIdleWorkItem = nil
        m_IsSpeaking = true
        enqueueSpeechBlock()
    }

    // synth が idle になるまで短い間隔でポーリングし、idle になってから一度だけ開始する。
    // 最大でも 40 * 0.025 = 1.0秒 待ったら(stopSpeaking のキャンセルには十分な時間)開始を試みる。
    private func scheduleStartAfterSynthesizerIdle(retryCount:Int) {
        startWhenIdleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // 待っている間に別経路で開始済み/再度停止された場合は何もしない
            if self.m_IsSpeaking == true { return }
            if self.isAnySynthesizerActive && retryCount < 40 {
                self.scheduleStartAfterSynthesizerIdle(retryCount: retryCount + 1)
                return
            }
            self.startWhenIdleWorkItem = nil
            if retryCount >= 40 {
                NSLog("NovelSpeaker.SynthWedge: ⚠️ idle 待ちタイムアウト(約1秒)synthActive=\(self.isAnySynthesizerActive) のまま開始する")
            }
            self.m_IsSpeaking = true
            self.enqueueSpeechBlock()
        }
        startWhenIdleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: work)
    }

    func StopSpeech(stopSpeechHandler:(()->Void)? = nil) {
        objc_sync_enter(self.stopSpeechHandlerLockObject)
        defer { objc_sync_exit(self.stopSpeechHandlerLockObject) }
        // idle 待ちの開始予約が残っていれば取り消す(停止が優先)。
        startWhenIdleWorkItem?.cancel()
        startWhenIdleWorkItem = nil
        // 世代を進めて、進行中の wedge watcher を失効させる
        //(停止区間をまたいだ誤回復を防ぐ)。
        speakGeneration += 1
        m_IsSpeaking = false
        self.stopSpeechHandler = stopSpeechHandler
        speaker.Stop()
    }

    /// 読み上げ開始位置を指定します。範囲外を指定された場合は false を返します
    @discardableResult
    func SetSpeechLocation(location:Int) -> Bool {
        var currentLocation = location
        if currentLocation < 0 { return false }
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeechBlockIndex = 0
        currentDisplayStringOffset = 0
        for speechBlock in speechBlockArray {
            let blockDisplayTextLength = speechBlock.displayText.unicodeScalars.count
            if currentLocation >= blockDisplayTextLength {
                currentSpeechBlockIndex += 1
                currentDisplayStringOffset += blockDisplayTextLength
                currentLocation -= blockDisplayTextLength
                continue
            }
            currentBlockDisplayOffset = currentLocation
            currentBlockSpeechOffset = speechBlock.ComputeSpeechLocationFrom(displayLocation: currentLocation)
            currentSpeakingLocation = location
            //print("SetSpeechLocation(\(location)) -> currentSpeechBlockIndex: \(currentSpeechBlockIndex), currentBlockSpeechOffset: \(currentBlockSpeechOffset)")
            return true
        }
        // ここで currentSpeakingLocation を更新しておかないと、読み上げ開始位置が 0 に戻ってしまう。
        currentSpeakingLocation = location
        //print("SetSpeechLocation(\(location)) -> currentSpeechBlockIndex: \(currentSpeechBlockIndex) (return false)")
        return false
    }
    
    /// 読み上げ開始位置を speechBlockArray の index で指示します
    @discardableResult
    func SetSpeechBlockIndex(index:Int) -> Bool {
        if index < 0 || speechBlockArray.count <= index { return false }
        currentBlockDisplayOffset = 0
        currentBlockSpeechOffset = 0
        currentSpeechBlockIndex = 0
        currentDisplayStringOffset = 0
        var index = index
        for speechBlock in speechBlockArray {
            if index < 0 {
                break
            }
            let blockDisplayTextLength = speechBlock.displayText.unicodeScalars.count
            currentDisplayStringOffset += blockDisplayTextLength
            currentSpeechBlockIndex += 1
            index -= 1
        }
        currentSpeakingLocation = currentDisplayStringOffset
        print("SetSpeechBlockIndex(\(index)) -> currentSpeechBlockIndex: \(currentSpeechBlockIndex)")
        return true
    }
    
    func willSpeakRange(range: NSRange) {
        willSpeakRangeCallCount += 1
        // 実発話が進んだので、固着回復カウンタをリセットする。
        wedgeRecoveryCount = 0
        guard let delegate = delegate, speechBlockArray.count > currentSpeechBlockIndex else { return }
        let block = speechBlockArray[currentSpeechBlockIndex]
        let location = block.ComputeDisplayLocationFrom(speechLocation: range.location + currentBlockSpeechOffset) + currentDisplayStringOffset
        currentSpeakingLocation = location
        delegate.willSpeakRange(range: NSMakeRange(location, range.length))
    }
    
    func finishSpeak(isCancel: Bool, speechString: String) {
        // 読み上げを停止させられている場合は何もしません。
        // これは、Stop() した時でも finishSpeak() が呼び出されるためです。
        if m_IsSpeaking != true {
            objc_sync_enter(self.stopSpeechHandlerLockObject)
            defer { objc_sync_exit(self.stopSpeechHandlerLockObject) }
            self.stopSpeechHandler?()
            self.stopSpeechHandler = nil
            return
        }
        // ここに来た = synth が utterance を完了して次へ進む = 実際に発話が進んだという事。
        // 固着回復の「連続失敗」カウンタをリセットする。
        // (willSpeakRange が飛ばない極短ブロック("。"等)でも確実にリセットするため、
        //  willSpeakRange 側のリセットだけに頼らずここでもリセットする)
        wedgeRecoveryCount = 0
        /* // 一応読み上げ途中で Cancel が発生する問題は回避できた(一度にSpeak()にわたす文字列の長さを短くする事で回避できるぽい)
         // ので、この再開するあたりの処理は封印しておきます。
         // 実際、再開させるようにしても、発話が停止してから2,3拍おいた後に少し戻って発話する感じになるのであまりうれしくないです
        if isCancel == true {
            // isCancel で finishSpeak が来た場合で、かつ、読み上げ中の途中でfinishSpeakが発生している場合、
            // 怪しくその時点で発話を再開します。
            print("currentSpeakingLocation: \(currentSpeakingLocation), displayText.count: \(displayText.unicodeScalars.count)")
            if (currentSpeakingLocation + 3) < displayText.unicodeScalars.count {
                SetSpeechLocation(location: currentSpeakingLocation)
                enqueueSpeechBlock()
                return
            }
        }
        */
        if setNextSpeechBlock() != true {
            m_IsSpeaking = false
            self.delegate?.finishSpeak(isCancel: isCancel, speechString: speechString)
            return
        }
        enqueueSpeechBlock()
    }

    var currentLocation:Int {
        get { return currentSpeakingLocation }
    }
    
    var currentBlockIndex:Int {
        get { return currentSpeechBlockIndex }
    }
    
    var currentBlock:CombinedSpeechBlock? {
        get {
            guard speechBlockArray.count > currentSpeechBlockIndex else { return nil }
            return speechBlockArray[currentSpeechBlockIndex]
        }
    }
    
    func isDummySpeechAlive() -> Bool {
        return speaker.isDummySpeechAlive()
    }
    
    func reloadSynthesizer() {
        objc_sync_enter(self.stopSpeechHandlerLockObject)
        defer { objc_sync_exit(self.stopSpeechHandlerLockObject) }
        if let stopHandler = self.stopSpeechHandler {
            stopHandler()
            self.stopSpeechHandler = nil
        }
        speaker.reloadSynthesizer()
    }
    #if false // AVSpeechSynthesizer を開放するとメモリ解放できそうなので必要なくなりました
    func ChangeSpeakerWillSpeakRangeType() {
        self.speaker.ChangeSpeakerWillSpeakRangeType()
    }
    #endif
}
