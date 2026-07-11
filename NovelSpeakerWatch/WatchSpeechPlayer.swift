//
//  WatchSpeechPlayer.swift
//  NovelSpeakerWatch
//
//  Watch 単体再生エンジン。転送済み本文(NovelStorage)を StoryTextClassifier で
//  発話ブロックに変換し、SpeechBlockSpeaker(iOS と共通の発話コア)で読み上げる。
//
//  - オーディオセッションは .playback + .longFormAudio + activate(options:)。
//    PoC(WatchSpeechPoC)で背面発話12分以上を実証した方式。Bluetooth イヤホン等への
//    出力先選択 UI は activate 時に OS が出してくれる。
//  - willSpeakRange は AVSpeechSynthesizerDelegate のメソッドとしては定義しない
//    (定義するだけで約40MBのメモリを消費するため。Speaker.swift 側で #if !os(watchOS))。
//    読み上げ位置はブロック境界(SpeechBlockSpeaker が enqueue 時に呼ぶ willSpeakRange)でだけ進む。
//  - 停止時はオーディオセッションを必ず解放する(握ったままだと背面で電池を消費する。PoCで確認済み)。
//

import Foundation
import AVFoundation
import Combine
import WatchConnectivity

final class WatchSpeechPlayer: NSObject, ObservableObject {
    static let shared = WatchSpeechPlayer()

    /// 再生画面の発話元として Watch 単体再生が選ばれているか
    @Published var isSelectedAsSource = false
    @Published var isPlaying = false
    @Published var novelID = ""
    @Published var title = ""
    @Published var chapterNumber = 0
    @Published var chapterCount = 0
    @Published var chapterSubtitle = ""
    /// 章内の読み上げ位置(0.0-1.0、表示文字ベース)。ブロック境界ごとにしか進まない
    @Published var progress: Double = 0
    /// 章内の読み上げ位置(表示文字の unicodeScalar オフセット)。本文ページのハイライトが使う
    @Published var speakingLocation = 0

    private let speaker = SpeechBlockSpeaker()
    private var stories: [Int: NovelStorage.StoredChapter] = [:]
    private var currentContentLength = 0
    private var lastPositionSaveDate = Date(timeIntervalSince1970: 0)
    // 現在のブロック列に焼き込まれているデフォルト話者の rate/volume。
    // 発話中の速度・音量変更を「新しい値 ÷ 焼き込み値」の倍率で反映するために覚えておく
    private var bakedDefaultSpeakerRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var bakedDefaultSpeakerVolume: Float = 1.0
    private var configSendWorkItem: DispatchWorkItem?

    /// iOS 側 StorySpeaker と同じブロック分割指定
    private static let withMoreSplitTargets = ["。", "、", "　", "\n"]
    private static let moreSplitMinimumLetterCount = 200
    /// スキップ量(文字数)。iPhone 側リモコンの停止中スキップと同じ量
    static let skipLength = 100

    private override init() {
        super.init()
        speaker.delegate = self
    }

    // MARK: - 小説のオープン

    /// 転送済み本文を読み込んで再生対象にする。本文が無ければ false。
    /// 再生位置は Watch ローカルの保存位置があればそこから、無ければ先頭から。
    @discardableResult
    func open(novelID: String, fallbackTitle: String = "") -> Bool {
        guard let novel = NovelStorage.loadNovel(novelID: novelID), !novel.stories.isEmpty else { return false }
        if isPlaying { stop() }
        self.novelID = novelID
        self.title = novel.title.isEmpty ? fallbackTitle : novel.title
        self.stories = novel.stories
        self.chapterCount = novel.stories.keys.max() ?? novel.stories.count
        let position = WatchReadingPositionStore.load(novelID: novelID)
        let firstChapter = novel.stories.keys.min() ?? 1
        if applyChapter(position?.chapter ?? firstChapter, location: position?.location ?? 0) == false {
            _ = applyChapter(firstChapter, location: 0)
        }
        return true
    }

    /// 指定章の本文をブロック分割して発話対象にする(発話は開始しない)
    private func applyChapter(_ chapter: Int, location: Int) -> Bool {
        guard let story = stories[chapter] else { return false }
        chapterNumber = chapter
        chapterSubtitle = story.subtitle
        currentContentLength = story.content.unicodeScalars.count
        speaker.StopSpeech()
        speaker.setSpeechBlockArray(blockArray: Self.buildBlocks(content: story.content))
        let baked = Self.effectiveDefaultSpeakerConfig()
        bakedDefaultSpeakerRate = baked.rate
        bakedDefaultSpeakerVolume = baked.volume
        speaker.SetSpeechLocation(location: min(max(0, location), max(0, currentContentLength - 1)))
        updateProgress()
        return true
    }

    /// 本文ページのハイライト用。指定の小説・章が現在の発話対象なら、
    /// 発話ブロックの表示文字範囲(unicodeScalar オフセット)一覧を返す
    func displayBlockScalarRanges(novelID: String, chapter: Int) -> [Range<Int>]? {
        guard novelID == self.novelID, chapter == self.chapterNumber,
              !speaker.speechBlockArray.isEmpty else { return nil }
        var ranges: [Range<Int>] = []
        var offset = 0
        for block in speaker.speechBlockArray {
            let length = block.displayText.unicodeScalars.count
            ranges.append(offset..<(offset + length))
            offset += length
        }
        return ranges
    }

    /// 現在の発話設定で本文をブロック分割する(本文ページのハイライト範囲計算にも使う)
    static func buildBlocks(content: String) -> [CombinedSpeechBlock] {
        let settings = WatchSpeechSettingsStorage.current()
        // Watch 側で速度・音量を変更した分(iPhone へ書き戻し中のローカル差分)を重ねる
        var defaultSpeaker = settings.defaultSpeaker
        if let override = WatchSpeechConfigStore.localOverride() {
            defaultSpeaker.rate = override.rate
            defaultSpeaker.volume = override.volume
        }
        func toSpeakerSetting(_ speaker: WatchSpeechSettings.Speaker) -> SpeakerSetting {
            return SpeakerSetting(pitch: speaker.pitch, rate: speaker.rate, volume: speaker.volume, type: speaker.type, voiceIdentifier: speaker.voiceIdentifier, locale: speaker.locale)
        }
        var mods = settings.speechMods.map { SpeechModSetting(before: $0.before, after: $0.after, isUseRegularExpression: $0.isRegexp, targetSpeechEngineTypeArray: $0.targetEngines) }
        if settings.isIgnoreURIStringSpeechEnabled {
            mods.append(SpeechModSetting(before: StoryTextClassifier.ignoreURIStringRegexpPattern, after: "", isUseRegularExpression: true))
        }
        if settings.isOverrideRubyEnabled {
            mods.append(contentsOf: StoryTextClassifier.GenerateRubyModString(text: content, notRubyString: settings.notRubyCharactorStringArray, isDisableNarouRuby: settings.isDisableNarouRuby))
        }
        let sectionConfigs = settings.sectionConfigs.map { SpeechSectionConfig(startText: $0.startText, endText: $0.endText, speakerSetting: toSpeakerSetting($0.speaker)) }
        let waitConfigs = settings.waitConfigs.map { SpeechWaitConfig(targetText: $0.targetText, delayTimeInSec: $0.delayTimeInSec) }
        return StoryTextClassifier.CategorizeStoryText(content: content, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount, defaultSpeaker: toSpeakerSetting(defaultSpeaker), sectionConfigList: sectionConfigs, waitConfigList: waitConfigs, speechModArray: mods)
    }

    /// 現在有効なデフォルト話者の速度・音量(ローカル差分があればそちら、無ければ同期済み設定)。
    /// 速度・音量設定 UI の初期値と、発話中変更の倍率計算の基準値に使う
    static func effectiveDefaultSpeakerConfig() -> (rate: Float, volume: Float) {
        if let override = WatchSpeechConfigStore.localOverride() {
            return (override.rate, override.volume)
        }
        let speaker = WatchSpeechSettingsStorage.current().defaultSpeaker
        return (speaker.rate, speaker.volume)
    }

    // MARK: - 速度・音量の変更

    /// デフォルト話者の速度・音量を変更する(速度・音量設定 UI から呼ばれる)。
    /// - 単体再生中なら次のブロックから反映される
    /// - iPhone に繋がっていれば iPhone の標準話者設定にも保存される(繋がっていなければ後で送る)
    func setSpeechConfig(rate: Float, volume: Float) {
        let clampedRate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        let clampedVolume = min(max(volume, 0.0), 1.0)
        WatchSpeechConfigStore.set(rate: clampedRate, volume: clampedVolume)
        if !novelID.isEmpty {
            speaker.rateMultiplier = clampedRate / max(0.01, bakedDefaultSpeakerRate)
            speaker.volumeMultiplier = clampedVolume / max(0.01, bakedDefaultSpeakerVolume)
        }
        // スライダー操作の途中で毎回送らないよう、少し待ってまとめて送る
        configSendWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.sendPendingSpeechConfigIfPossible()
        }
        configSendWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// 未送信の速度・音量変更を iPhone へ送る(reachable になった時などにも呼ばれる)
    func sendPendingSpeechConfigIfPossible() {
        guard WatchSpeechConfigStore.isPendingSend,
              let override = WatchSpeechConfigStore.localOverride() else { return }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        PhoneSessionManager.shared.send(.setDefaultSpeakerConfig, args: [
            WatchMessage.Arg.rate: Double(override.rate),
            WatchMessage.Arg.volume: Double(override.volume),
        ], quiet: true) { ok in
            if ok { WatchSpeechConfigStore.markSent() }
        }
    }

    /// 発話設定ファイルを受信した時に PhoneSessionManager から呼ばれる。
    /// ローカル差分が iPhone 側へ反映済みなら差分を解消する
    func reconcileSpeechConfigAfterSettingsReceived() {
        WatchSpeechConfigStore.reconcileAfterSettingsReceived()
    }

    // MARK: - 再生操作

    func play() {
        guard !novelID.isEmpty else {
            reportError(NSLocalizedString("Watch_Player_NoNovelSelected_ChooseFromBookshelf", comment: "小説が選ばれていません。本棚から小説を選んでください。"))
            return
        }
        // 発話直前に iPhone との発話設定の同期を試みる。時間を食ってまごつかないよう、
        // 最大2秒で諦めてそのまま(手元の設定で)発話を開始する
        syncSettingsBeforePlay { [weak self] settingsUpdated in
            DispatchQueue.main.async {
                guard let self = self, !self.isPlaying else { return }
                if settingsUpdated {
                    // 新しい設定が届いたので現在の章を組み直してから開始する(位置は維持)
                    _ = self.applyChapter(self.chapterNumber, location: self.speaker.currentLocation)
                }
                self.startPlayback()
            }
        }
    }

    /// 発話設定が最新かを iPhone に問い合わせ、古ければファイル到着を少しだけ待つ。
    /// completion(true) = 新しい設定ファイルを受信した / completion(false) = 手元の設定のままでよい
    private func syncSettingsBeforePlay(completion: @escaping (Bool) -> Void) {
        guard WCSession.default.isReachable else {
            completion(false)
            return
        }
        var finished = false
        var observer: NSObjectProtocol? = nil
        func finishOnce(_ updated: Bool) {
            DispatchQueue.main.async {
                if finished { return }
                finished = true
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                completion(updated)
            }
        }
        // 設定ファイルの到着を監視(iPhone 側が「古い」と判断した場合に飛んでくる)
        observer = NotificationCenter.default.addObserver(forName: WatchSpeechSettingsStorage.didUpdateNotification, object: nil, queue: .main) { _ in
            finishOnce(true)
        }
        PhoneSessionManager.shared.sendForReply(.syncSpeechSettings, args: [WatchMessage.Arg.fingerprint: WatchSpeechSettingsStorage.storedFingerprint()]) { reply in
            guard let reply = reply, reply[WatchMessage.Reply.ok] as? Bool == true else {
                finishOnce(false) // 通信失敗。手元の設定で開始する
                return
            }
            if reply[WatchMessage.Reply.speechSettingsUpToDate] as? Bool == true {
                finishOnce(false) // 手元の設定が既に最新
            }
            // 最新でない場合はファイル到着(上の通知)か、下のタイムアウトを待つ
        }
        // 実測: 設定が変わっていた場合の生成+転送は2秒前後かかる(初回synth起動の方が長いので許容)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            finishOnce(false)
        }
    }

    private func startPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        } catch {
            reportError(String(format: NSLocalizedString("Watch_SpeechPlayer_AudioSetupFailed", comment: "オーディオ設定に失敗しました: %@"), error.localizedDescription))
            return
        }
        // Bluetooth イヤホン等への出力先選択 UI がここで出る(必要な時だけ)
        session.activate(options: []) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard success else {
                    self.reportError(String(format: NSLocalizedString("Watch_SpeechPlayer_AudioRouteFailed", comment: "オーディオ出力先に接続できませんでした。%@"), error?.localizedDescription ?? ""))
                    return
                }
                self.isPlaying = true
                self.speaker.StartSpeech()
                PhoneSessionManager.shared.recordLastPlayed(novelID: self.novelID)
            }
        }
    }

    func stop() {
        let wasSpeaking = speaker.isSpeaking
        isPlaying = false
        savePosition(pushContext: true)
        if wasSpeaking {
            speaker.StopSpeech { [weak self] in
                DispatchQueue.main.async { self?.deactivateAudioSession() }
            }
        } else {
            speaker.StopSpeech()
            deactivateAudioSession()
        }
    }

    func togglePlayPause() {
        if isPlaying { stop() } else { play() }
    }

    /// 読み上げ位置を前後に動かす(章内でクランプ、iPhone 側の停止中スキップと同じ挙動)
    func skip(by offset: Int) {
        seek(toLocation: speaker.currentLocation + offset)
    }

    /// 読み上げ位置を章内の指定位置(表示文字の unicodeScalar オフセット)へ動かす。
    /// 再生中ならその位置から発話し直す(本文ページのタップ/長押しでの位置指定が使う)
    func seek(toLocation location: Int) {
        guard !novelID.isEmpty else { return }
        let target = min(max(0, location), max(0, currentContentLength - 1))
        if isPlaying && speaker.isSpeaking {
            speaker.StopSpeech { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.isPlaying else { return }
                    self.speaker.SetSpeechLocation(location: target)
                    self.speaker.StartSpeech()
                    self.updateProgress()
                }
            }
        } else {
            speaker.SetSpeechLocation(location: target)
            updateProgress()
            savePosition()
        }
    }

    /// 章を移動する。再生中なら移動先の章の先頭から再生を続ける
    @discardableResult
    func moveChapter(offset: Int) -> Bool {
        let target = chapterNumber + offset
        guard stories[target] != nil else { return false }
        if isPlaying && speaker.isSpeaking {
            speaker.StopSpeech { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    _ = self.applyChapter(target, location: 0)
                    if self.isPlaying {
                        self.speaker.StartSpeech()
                    }
                    self.savePosition()
                }
            }
        } else {
            _ = applyChapter(target, location: 0)
            savePosition()
        }
        return true
    }

    // MARK: - 内部処理

    private func deactivateAudioSession() {
        // アクティブなまま放置すると背面で電池を消費する(PoC で確認)ため、停止時は必ず解放する
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateProgress() {
        speakingLocation = speaker.currentLocation
        if currentContentLength > 0 {
            progress = min(1.0, Double(speaker.currentLocation) / Double(currentContentLength))
        } else {
            progress = 0
        }
        pushComplication()
    }

    /// Watch 単体再生が発話元の時、コンプリケーションの「今読んでいる小説」を更新する
    private func pushComplication() {
        guard isSelectedAsSource, !novelID.isEmpty else { return }
        WatchComplicationUpdater.update(
            novelID: novelID, title: title, chapterSubtitle: chapterSubtitle,
            chapterNumber: chapterNumber, chapterCount: chapterCount,
            progressInChapter: progress)
    }

    /// 発話元に選ばれた直後など、即時にコンプリケーションへ現在の小説を反映する
    func refreshComplication() {
        pushComplication()
    }

    private func savePosition(pushContext: Bool = false) {
        guard !novelID.isEmpty else { return }
        WatchReadingPositionStore.save(novelID: novelID, chapter: chapterNumber, location: speaker.currentLocation)
        // 読み上げ位置を iPhone へも知らせる(iPhone 側はこれで栞を更新する)。
        // 再生中は60秒に1回まで、停止時などの節目は即時
        if pushContext {
            lastContextPushDate = Date()
            PhoneSessionManager.shared.pushWatchContext()
        } else if Date().timeIntervalSince(lastContextPushDate) >= 60.0 {
            lastContextPushDate = Date()
            PhoneSessionManager.shared.pushWatchContext()
        }
    }

    private var lastContextPushDate = Date(timeIntervalSince1970: 0)

    private func savePositionThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastPositionSaveDate) >= 5.0 else { return }
        lastPositionSaveDate = now
        savePosition()
    }

    /// 発話設定を受信した時に PhoneSessionManager から呼ばれる。
    /// 停止中なら現在の章を新しい設定で組み直して即反映する(再生中は次の章から自然に反映される)
    func applyReceivedSettingsIfIdle() {
        DispatchQueue.main.async {
            guard !self.novelID.isEmpty, !self.isPlaying else { return }
            _ = self.applyChapter(self.chapterNumber, location: self.speaker.currentLocation)
        }
    }

    private func reportError(_ message: String) {
        DispatchQueue.main.async {
            // エラー表示はルート(WatchRootView)のアラートに集約しているのでそちらへ流す
            PhoneSessionManager.shared.lastErrorMessage = message
        }
    }
}

// MARK: - SpeakRangeDelegate

extension WatchSpeechPlayer: SpeakRangeDelegate {
    /// willSpeakRange 本体(AVSpeechSynthesizer の逐次コールバック)は watch では受けないので、
    /// これはブロック境界(SpeechBlockSpeaker.enqueueSpeechBlock)でだけ呼ばれる
    func willSpeakRange(range: NSRange) {
        DispatchQueue.main.async {
            self.updateProgress()
            self.savePositionThrottled()
        }
    }

    func finishSpeak(isCancel: Bool, speechString: String) {
        DispatchQueue.main.async {
            // 停止操作による cancel はここに来ない(StopSpeech ハンドラ側で処理)ので、
            // isPlaying が立っていれば「章を読み終えた」という意味になる
            guard self.isPlaying else { return }
            if self.applyChapter(self.chapterNumber + 1, location: 0) {
                self.speaker.StartSpeech()
                self.savePosition()
            } else {
                // 最終章まで読み終えた
                self.isPlaying = false
                self.savePosition(pushContext: true)
                self.deactivateAudioSession()
            }
        }
    }
}

// MARK: - 読み上げ位置の保存(Watch ローカル)

enum WatchReadingPositionStore {
    struct Position: Codable {
        var chapter: Int
        var location: Int
        var updatedAt: Date
    }

    private static let key = "WatchReadingPositions"

    private static func loadAll() -> [String: Position] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let positions = try? JSONDecoder().decode([String: Position].self, from: data) else { return [:] }
        return positions
    }

    static func load(novelID: String) -> Position? {
        return loadAll()[novelID]
    }

    /// 一番最近更新された読み上げ位置(iPhone への同期用)
    static func latest() -> (novelID: String, position: Position)? {
        guard let entry = loadAll().max(by: { $0.value.updatedAt < $1.value.updatedAt }) else { return nil }
        return (entry.key, entry.value)
    }

    static func save(novelID: String, chapter: Int, location: Int) {
        var positions = loadAll()
        positions[novelID] = Position(chapter: chapter, location: location, updatedAt: Date())
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func remove(novelID: String) {
        var positions = loadAll()
        guard positions.removeValue(forKey: novelID) != nil else { return }
        if let data = try? JSONEncoder().encode(positions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 発話設定の保存(iPhone から transferFile で届く)

enum WatchSpeechSettingsStorage {
    /// 発話設定ファイルを受信・保存した時に飛ぶ通知(発話直前の同期待ちが使う)
    static let didUpdateNotification = Notification.Name("WatchSpeechSettingsStorage.didUpdate")
    private static let fingerprintKey = "WatchSpeechSettingsFingerprint"

    static var fileURL: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeechSettings.json")
    }

    private static var cache: WatchSpeechSettings?

    static func store(receivedFileURL: URL, fingerprint: String?) throws {
        let destination = fileURL
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: receivedFileURL, to: destination)
        cache = nil
        UserDefaults.standard.set(fingerprint ?? "", forKey: fingerprintKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: didUpdateNotification, object: nil)
        }
    }

    /// 保存済み設定ファイルの指紋(iPhone 側が metadata に載せてきた SHA256 hex)。未受信なら空
    static func storedFingerprint() -> String {
        return UserDefaults.standard.string(forKey: fingerprintKey) ?? ""
    }

    /// 保存済みの発話設定。まだ届いていなければ既定値(標準話者・読み替え無し)
    static func current() -> WatchSpeechSettings {
        if let cache = cache { return cache }
        if let data = try? Data(contentsOf: fileURL),
           let settings = try? JSONDecoder().decode(WatchSpeechSettings.self, from: data) {
            cache = settings
            return settings
        }
        let fallback = WatchSpeechSettings()
        cache = fallback
        return fallback
    }
}

// MARK: - 速度・音量の Watch 側ローカル差分

/// Watch で変更したデフォルト話者の速度・音量。
/// 正本は iPhone の RealmSpeakerSetting で、ここは「iPhone へ書き戻すまでの間(オフライン中など)も
/// Watch の発話に効かせるためのローカル差分」。同期済み設定ファイル(と指紋)には手を付けないので、
/// 発話直前の設定同期(指紋比較)と衝突しない。
/// 書き戻しが済んで新しい設定ファイルが届いたら reconcile で解消される。
enum WatchSpeechConfigStore {
    private struct Stored: Codable {
        var rate: Float
        var volume: Float
        var updatedAt: Date
        var pendingSend: Bool
    }

    private static let key = "WatchSpeechConfigOverride"

    private static func loadStored() -> Stored? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        return stored
    }

    private static func save(_ stored: Stored?) {
        if let stored = stored, let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func localOverride() -> (rate: Float, volume: Float)? {
        guard let stored = loadStored() else { return nil }
        return (stored.rate, stored.volume)
    }

    static var isPendingSend: Bool {
        return loadStored()?.pendingSend == true
    }

    static func set(rate: Float, volume: Float) {
        save(Stored(rate: rate, volume: volume, updatedAt: Date(), pendingSend: true))
    }

    /// iPhone への送信が成功した(iPhone 側の Realm に保存された)。
    /// 差分自体は新しい設定ファイルが届く(reconcile)まで発話用に残しておく
    static func markSent() {
        guard var stored = loadStored() else { return }
        stored.pendingSend = false
        save(stored)
    }

    static func clear() {
        save(nil)
    }

    /// 発話設定ファイルの受信後に呼ぶ。ローカル差分が iPhone 側に反映済み
    /// (届いた設定が差分と一致)か、iPhone 側でより新しい変更があった場合は差分を解消する。
    /// まだ送れていない(pendingSend)差分は保持し、次に繋がった時に送る
    static func reconcileAfterSettingsReceived() {
        guard let stored = loadStored(), stored.pendingSend == false else { return }
        let settings = WatchSpeechSettingsStorage.current()
        let matches = abs(settings.defaultSpeaker.rate - stored.rate) < 0.001
            && abs(settings.defaultSpeaker.volume - stored.volume) < 0.001
        if matches || settings.updatedAt > stored.updatedAt {
            clear()
        }
        // どちらでもない場合は「書き戻しより前に作られた古い設定ファイル」が届いただけなので、
        // 差分は保持したまま次のファイル(書き戻し後の内容)を待つ
    }
}
