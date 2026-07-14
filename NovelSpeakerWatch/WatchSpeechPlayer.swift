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
import WidgetKit

final class WatchSpeechPlayer: NSObject, ObservableObject {
    static let shared = WatchSpeechPlayer()

    /// 再生画面の発話元として Watch 単体再生が選ばれているか。
    /// App Group に永続化して、次回起動時の復元(ウィジェットの再生トグルが単体再生に効くように)と
    /// ウィジェット側の現在の発話元表示に使う
    @Published var isSelectedAsSource = false {
        didSet {
            guard oldValue != isSelectedAsSource else { return }
            UserDefaults(suiteName: WatchComplicationData.appGroupID)?
                .set(isSelectedAsSource, forKey: Self.isSelectedAsSourceKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// isSelectedAsSource の App Group 永続化キー
    private static let isSelectedAsSourceKey = "WatchIsSelectedAsSource"
    /// 起動後に単体モードの復元を試みたか(多重復元の防止)
    private var didRestoreStandaloneSelection = false
    @Published var isPlaying = false
    /// 再生開始処理中(タップから発話準備が整うまで)。初回は設定同期+オーディオ確立で
    /// 数秒〜数十秒かかることがあるので、再生ボタンをスピナーにして再タップも無視する
    @Published var isStartingPlayback = false
    @Published var novelID = ""
    @Published var title = ""
    @Published var chapterNumber = 0
    @Published var chapterCount = 0
    @Published var chapterSubtitle = ""
    /// 章内の読み上げ位置(0.0-1.0、表示文字ベース)。ブロック境界ごとにしか進まない
    @Published var progress: Double = 0
    /// 章内の読み上げ位置(表示文字の unicodeScalar オフセット)。本文ページのハイライトが使う
    @Published var speakingLocation = 0
    /// 「指定フォルダの小説を再生」で対象フォルダの選択が必要な時、候補のフォルダ名が入る。
    /// UI(WatchRootView)がこれを監視してダイアログを出し、選択されたら
    /// selectFolderForRepeatAndPlay() で再生が再開される。キャンセルなら nil に戻すだけでよい
    @Published var folderSelectionRequest: [String]?
    /// Bluetooth 未接続の注意を表示したい(WatchRootView がアラートを出す)。
    /// ソース選択ダイアログと同じビューに付けるとダイアログが閉じた直後の表示が失敗するため、
    /// エラーアラートと同じくルートに置く
    @Published var isNoBluetoothWarningPresented = false

    /// 「Bluetooth未接続の注意を今後表示しない」の UserDefaults キー
    static let suppressNoBluetoothWarningKey = "SuppressNoBluetoothWarning"

    private let speaker = SpeechBlockSpeaker()
    private var currentContentLength = 0
    /// 保持中の章の本文ハッシュ。転送で内容が変わったかの判定に使う(変わっていなければ組み直さない)
    private var currentContentHash = 0
    /// 発話中に保持中の章の内容更新が届いた印。発話中の差し替えは音が途切れるので、停止時まで保留する
    private var needsChapterReloadAfterSpeech = false
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
        // 保持している小説のバルク/manifest が届いたら、章の内容を読み直す
        // (iPhone 側の内容だけの更新で、表示と発話が食い違ったまま残らないように)
        NotificationCenter.default.addObserver(forName: NovelStorage.didUpdateNotification, object: nil, queue: .main) { [weak self] notification in
            self?.handleStoredNovelUpdate(notification)
        }
        // 前回「Watch単体モード」を選んだまま終了していたら、その小説を開き直して復元する。
        // 初期化フェーズを避けるため次のランループで(起動をブロックしない)
        DispatchQueue.main.async { [weak self] in
            self?.restoreStandaloneSelectionIfNeeded()
        }
    }

    // MARK: - ウィジェット(コンプリケーション)からの操作

    /// ウィジェットの「再生・一時停止」トグルから(アプリ起動後に)呼ばれる。
    /// 単体モードなら Watch 単体再生をトグル、そうでなければ iPhone へトグルコマンドを送る。
    /// 起動直後で復元が済んでいない場合に備え、ここでも復元を試みる(冪等)
    func toggleForWidgetLaunch() {
        restoreStandaloneSelectionIfNeeded()
        if isSelectedAsSource {
            togglePlayPause()
        } else {
            PhoneSessionManager.shared.send(.togglePlayPause)
        }
    }

    /// ウィジェット「この小説を再生」から(アプリ起動後に)呼ばれる。指定小説を現在の発話元で再生する。
    /// - Watch 単体モード: その小説を開いて単体再生を開始(未転送ならエラー)
    /// - iPhone: iPhone へ「その小説を開いて再生」コマンドを送る(現在の発話元に従う)
    func playNovelFromWidget(novelID: String) {
        restoreStandaloneSelectionIfNeeded()
        if isSelectedAsSource {
            guard open(novelID: novelID) else {
                reportError(NSLocalizedString("Watch_Player_BodyNotTransferred", comment: "この小説の本文がWatchに転送されていません。本棚の小説をタップして転送してから、もう一度お試しください。"))
                return
            }
            play()
        } else {
            PhoneSessionManager.shared.send(.playNovel, args: [WatchMessage.Arg.novelID: novelID])
        }
    }

    /// 永続化された発話元が Watch 単体だったら、最後に単体再生した小説を開き直して復元する。
    /// 復元対象が無ければ(小説が削除された等)単体モード自体を解除する。起動時と、
    /// ウィジェット起動時のトグル直前に呼ばれる(多重実行は didRestore フラグで防ぐ)
    private func restoreStandaloneSelectionIfNeeded() {
        guard !didRestoreStandaloneSelection else { return }
        didRestoreStandaloneSelection = true
        guard UserDefaults(suiteName: WatchComplicationData.appGroupID)?
                .bool(forKey: Self.isSelectedAsSourceKey) == true else { return }
        if let latest = WatchReadingPositionStore.latest(), open(novelID: latest.novelID) {
            isSelectedAsSource = true
        } else {
            isSelectedAsSource = false
        }
    }

    /// 保持中の小説の本文が転送されてきた時の読み直し。
    /// 発話中は停止時まで保留する(発話ブロックの差し替えは音が途切れる+位置の対応も揺れるため)
    private func handleStoredNovelUpdate(_ notification: Notification) {
        guard !novelID.isEmpty,
              notification.userInfo?["novelID"] as? String == novelID else { return }
        // 章数(転送済み範囲)は常に追従させる
        chapterCount = NovelStorage.storedChapterCount(novelID: novelID)
        // 保持中の章を含まないバルクの到着なら本文の読み直しは不要
        if let bulkChapter = notification.userInfo?["bulkChapter"] as? Int,
           bulkChapter != NovelStorage.bulkChapter(for: chapterNumber) {
            return
        }
        if isPlaying {
            needsChapterReloadAfterSpeech = true
            return
        }
        reloadCurrentChapterIfContentChanged()
    }

    /// 保持中の章を読み直す(内容が実際に変わっている時だけ。位置は保存済みの読み上げ位置を保つ)
    private func reloadCurrentChapterIfContentChanged() {
        needsChapterReloadAfterSpeech = false
        guard !novelID.isEmpty, chapterNumber > 0,
              let story = NovelStorage.chapter(novelID: novelID, chapter: chapterNumber),
              story.content.hashValue != currentContentHash else { return }
        // StopSpeech 後の speaker.currentLocation は当てにしない(停止処理で動きうる)ので、
        // 直前に保存された読み上げ位置を優先する
        let stored = WatchReadingPositionStore.load(novelID: novelID)
        let location = (stored?.chapter == chapterNumber ? stored?.location : nil) ?? speaker.currentLocation
        _ = applyChapter(chapterNumber, location: location)
    }

    // MARK: - 小説のオープン

    /// 転送済み本文を読み込んで再生対象にする。本文が無ければ false。
    /// 再生位置は「Watch ローカルの保存位置」と「iPhone の栞(playState に相乗り)」の
    /// 新しい方から。どちらも無ければ先頭から。
    @discardableResult
    func open(novelID: String, fallbackTitle: String = "") -> Bool {
        if isPlaying { stop() }
        guard switchNovel(novelID: novelID, fromBeginning: false) else { return false }
        if title.isEmpty { title = fallbackTitle }
        return true
    }

    /// 再生対象の小説を差し替える(オーディオセッションには触れないので連続再生の途中でも使える)。
    /// fromBeginning=false なら「Watch ローカルの保存位置 vs iPhone の栞」の新しい方から。
    /// 本文は全章をメモリに載せず、章を開くたびに必要なバルクだけ NovelStorage が展開する
    private func switchNovel(novelID: String, fromBeginning: Bool) -> Bool {
        guard let manifest = NovelStorage.manifest(novelID: novelID) else { return false }
        let storedCount = NovelStorage.storedChapterCount(novelID: novelID)
        guard storedCount > 0 else { return false }
        self.novelID = novelID
        self.title = manifest.title
        self.chapterCount = storedCount
        // firstStoredChapter は先頭バルクの展開を伴うので、栞から開ける時は呼ばずに済ませる
        func firstChapter() -> Int { return NovelStorage.firstStoredChapter(novelID: novelID) ?? 1 }
        if fromBeginning {
            return applyChapter(firstChapter(), location: 0)
        }
        let position = WatchReadingPositionStore.load(novelID: novelID)
        // iPhone 側の栞の方が新しければそちらから開く(新しい方優先)。
        // 採用したら iPhone 側のタイムスタンプごとローカルに控える
        // (次のオフライン起動でも同じ位置から開けるように。時刻を進めないので
        //  逆方向へ送り返しても iPhone 側の「厳密に新しい時だけ反映」で無視される)
        if let phone = phoneBookmarkIfNewer(novelID: novelID, than: position?.updatedAt),
           applyChapter(phone.chapter, location: phone.location) {
            WatchReadingPositionStore.save(novelID: novelID, chapter: chapterNumber,
                                           location: speaker.currentLocation, updatedAt: phone.updatedAt)
            return true
        }
        if let position = position, applyChapter(position.chapter, location: position.location) {
            return true
        }
        return applyChapter(firstChapter(), location: 0)
    }

    /// iPhone の栞(playState に相乗りしてくる位置)が指定時刻より新しければ返す
    private func phoneBookmarkIfNewer(novelID: String, than date: Date?) -> (chapter: Int, location: Int, updatedAt: Date)? {
        guard let state = PhoneSessionManager.shared.playState,
              state.novelID == novelID,
              state.bookmarkUpdatedAt > (date ?? Date(timeIntervalSince1970: 0)) else { return nil }
        return (state.chapterNumber, state.readingLocation, state.bookmarkUpdatedAt)
    }

    /// iPhone の再生状態を受信した時に PhoneSessionManager から呼ばれる。
    /// 開いている小説の栞が iPhone 側の方が新しければ、停止中に限りそちらへ追従する
    /// (再生中は Watch 側の位置が正。停止時の savePosition が iPhone へ送られてそちらが追従する)
    func adoptPhoneBookmarkIfNewer(_ state: WatchPlayState) {
        guard !novelID.isEmpty, state.novelID == novelID, !isPlaying else { return }
        let local = WatchReadingPositionStore.load(novelID: novelID)
        guard state.bookmarkUpdatedAt > (local?.updatedAt ?? Date(timeIntervalSince1970: 0)) else { return }
        guard applyChapter(state.chapterNumber, location: state.readingLocation) else { return }
        WatchReadingPositionStore.save(novelID: novelID, chapter: chapterNumber,
                                       location: speaker.currentLocation, updatedAt: state.bookmarkUpdatedAt)
    }

    /// 指定章の本文をブロック分割して発話対象にする(発話は開始しない)
    private func applyChapter(_ chapter: Int, location: Int) -> Bool {
        guard let story = NovelStorage.chapter(novelID: novelID, chapter: chapter) else { return false }
        needsChapterReloadAfterSpeech = false  // 新しく読み込むので保留中の読み直しは不要になる
        chapterNumber = chapter
        chapterSubtitle = story.subtitle
        currentContentHash = story.content.hashValue
        currentContentLength = story.content.unicodeScalars.count
        speaker.StopSpeech()
        let blocks = Self.buildBlocks(content: story.content)
        speaker.setSpeechBlockArray(blockArray: blocks)
        let baked = Self.effectiveDefaultSpeakerConfig()
        bakedDefaultSpeakerRate = baked.rate
        bakedDefaultSpeakerVolume = baked.volume
        speaker.SetSpeechLocation(location: min(max(0, location), max(0, currentContentLength - 1)))
        updateProgress()
        // 次章が別バルクなら先に展開しておく(章をまたぐ時に待たせない)
        NovelStorage.prefetchNextBulkIfNeeded(novelID: novelID, currentChapter: chapter)
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

    /// 「再生が末尾に達した時の動作」の実効値
    struct EffectiveRepeatConfig {
        let repeatType: WatchRepeatSpeechType
        let isLoopNoCheckReadingPoint: Bool
    }

    /// 現在有効な「再生が末尾に達した時の動作」(ローカル差分があればそちら、無ければ同期済み設定)。
    /// 連続再生設定 UI の初期値と、末尾到達時の分岐に使う
    static func effectiveRepeatConfig() -> EffectiveRepeatConfig {
        if let override = WatchRepeatConfigStore.localOverride() {
            return EffectiveRepeatConfig(
                repeatType: WatchRepeatSpeechType(rawValue: override.repeatTypeRawValue) ?? .noRepeat,
                isLoopNoCheckReadingPoint: override.isLoopNoCheck)
        }
        let settings = WatchSpeechSettingsStorage.current()
        return EffectiveRepeatConfig(
            repeatType: WatchRepeatSpeechType(rawValue: settings.repeatSpeechTypeRawValue ?? 0) ?? .noRepeat,
            isLoopNoCheckReadingPoint: settings.isRepeatSpeechLoopNoCheckReadingPoint == true)
    }

    // MARK: - 連続再生モードの変更

    /// 「再生が末尾に達した時の動作」を変更する(連続再生設定 UI から呼ばれる)。
    /// iPhone の設定(RealmGlobalState)へ書き戻される。繋がっていなければローカル差分として
    /// 保持して Watch の発話には即時効かせ、繋がった時に送る(速度・音量と同じ仕組み)
    func setRepeatConfig(repeatType: WatchRepeatSpeechType, isLoopNoCheckReadingPoint: Bool) {
        WatchRepeatConfigStore.set(repeatTypeRawValue: repeatType.rawValue, isLoopNoCheck: isLoopNoCheckReadingPoint)
        // スライダーと違い連打はしにくいが、選択方式と種別を続けて変える操作をまとめて送る
        repeatConfigSendWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.sendPendingRepeatConfigIfPossible()
        }
        repeatConfigSendWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// 未送信の連続再生モード変更を iPhone へ送る(reachable になった時などにも呼ばれる)
    func sendPendingRepeatConfigIfPossible() {
        guard WatchRepeatConfigStore.isPendingSend,
              let override = WatchRepeatConfigStore.localOverride() else { return }
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        PhoneSessionManager.shared.send(.setRepeatSpeechConfig, args: [
            WatchMessage.Arg.repeatType: override.repeatTypeRawValue,
            WatchMessage.Arg.loopNoCheckReadingPoint: override.isLoopNoCheck,
        ], quiet: true) { ok in
            if ok { WatchRepeatConfigStore.markSent() }
        }
    }

    /// 発話設定ファイルを受信した時に PhoneSessionManager から呼ばれる。
    /// ローカル差分が iPhone 側へ反映済みなら差分を解消する
    func reconcileRepeatConfigAfterSettingsReceived() {
        WatchRepeatConfigStore.reconcileAfterSettingsReceived()
    }

    private var repeatConfigSendWorkItem: DispatchWorkItem?

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
        startPlayFlow(askFolderSelection: true)
    }

    private func startPlayFlow(askFolderSelection: Bool) {
        guard !isStartingPlayback else { return }  // 開始処理中の再タップは無視(誤爆防止)
        guard !novelID.isEmpty else {
            reportError(NSLocalizedString("Watch_Player_NoNovelSelected_ChooseFromBookshelf", comment: "小説が選ばれていません。本棚から小説を選んでください。"))
            return
        }
        // 「指定フォルダの小説を再生」で複数フォルダに属する小説なら、iPhone 側と同じく
        // 再生開始のたびにユーザへ選んでもらう(フォルダを選び直せるように)。
        // ダイアログでの選択直後の再開(askFolderSelection=false)だけはスキップする
        if askFolderSelection, let candidates = folderSelectionCandidatesIfNeeded() {
            DispatchQueue.main.async { self.folderSelectionRequest = candidates }
            return
        }
        isStartingPlayback = true
        // 発話直前に iPhone との発話設定の同期を試みる。時間を食ってまごつかないよう、
        // 最大2秒で諦めてそのまま(手元の設定で)発話を開始する
        syncSettingsBeforePlay { [weak self] settingsUpdated in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard !self.isPlaying else {
                    self.isStartingPlayback = false
                    return
                }
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
        // 「指定フォルダの小説を再生」の対象フォルダは再生開始時に決める(連続再生中は維持)
        updateSelectedFolderForRepeat()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        } catch {
            isStartingPlayback = false
            reportError(String(format: NSLocalizedString("Watch_SpeechPlayer_AudioSetupFailed", comment: "オーディオ設定に失敗しました: %@"), error.localizedDescription))
            return
        }
        // Bluetooth イヤホン等への出力先選択 UI がここで出る(必要な時だけ)
        session.activate(options: []) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isStartingPlayback = false
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
        isStartingPlayback = false
        announcer?.cancel()
        savePosition(pushContext: true)
        if wasSpeaking {
            speaker.StopSpeech { [weak self] in
                DispatchQueue.main.async { self?.deactivateAudioSession() }
            }
        } else {
            speaker.StopSpeech()
            deactivateAudioSession()
        }
        // 発話中に届いていた内容更新があれば、止まったこのタイミングで読み直す
        if needsChapterReloadAfterSpeech {
            reloadCurrentChapterIfContentChanged()
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
        guard NovelStorage.hasChapter(novelID: novelID, chapter: target) else { return false }
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

    // MARK: - 再生が末尾に達した時の動作

    /// 最終章まで読み終えた時の分岐。「再生が末尾に達した時の動作」(iPhone から同期)に従う
    private func handleReachedEnd(repeatConfig: EffectiveRepeatConfig, settings: WatchSpeechSettings) {
        savePosition()  // 読み終えた位置(章末)を控えておく
        switch repeatConfig.repeatType {
        case .rewindToFirstStory:
            guard let firstChapter = NovelStorage.firstStoredChapter(novelID: novelID) else { break }
            announceIfEnabled(settings: settings,
                              text: NSLocalizedString("Watch_SpeechPlayer_RewindFirstStory", comment: "読み上げが最後に達したため、最初の章に戻って再生を繰り返します。")) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                guard self.applyChapter(firstChapter, location: 0) else {
                    self.finishPlaybackAtEnd()
                    return
                }
                self.speaker.StartSpeech()
                self.savePosition()
            }
            return
        case .goToNextLikeNovel, .goToNextSameFolderdNovel, .goToNextSelectedFolderdNovel,
             .goToNextSameWriterNovel, .goToNextSameWebsiteNovel:
            guard let next = nextNovelTarget(repeatConfig: repeatConfig, settings: settings) else { break }
            announceIfEnabled(settings: settings,
                              text: String(format: NSLocalizedString("Watch_SpeechPlayer_SpeechNextNovelFormat", comment: "読み上げが最後に達したため、次に %@ を再生します。"), next.title)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                guard self.switchNovel(novelID: next.novelID, fromBeginning: next.fromBeginning) else {
                    self.finishPlaybackAtEnd()
                    return
                }
                self.speaker.StartSpeech()
                self.savePosition(pushContext: true)
                PhoneSessionManager.shared.recordLastPlayed(novelID: self.novelID)
            }
            return
        default:
            break
        }
        finishPlaybackAtEnd()
    }

    /// 継続再生はせず終了する(iPhone 側と同じく末尾到達を発話で知らせてからオーディオを解放)
    private func finishPlaybackAtEnd() {
        isPlaying = false
        savePosition(pushContext: true)
        announceSpeaker().speak(text: NSLocalizedString("Watch_SpeechPlayer_SpeechStoppedByEnd", comment: "読み上げが最後に達しました。")) { [weak self] in
            guard let self = self, !self.isPlaying else { return }
            self.deactivateAudioSession()
        }
        // 発話中に届いていた内容更新があれば、止まったこのタイミングで読み直す
        if needsChapterReloadAfterSpeech {
            reloadCurrentChapterIfContentChanged()
        }
    }

    /// 「別の小説に切り替えて再生する」系(お気に入り/同じフォルダ/指定フォルダ/同じ作者/
    /// 同じWebサイト)の次の対象を、Watch に転送済みの小説の中から選ぶ。
    /// - 通常ループ: 候補順で最初の「自分以外・転送済み・未読あり」の小説(栞の続きから)
    /// - 栞の位置を確認しないループ: 現在の小説の次から順番に、転送済みのものを先頭章から
    private func nextNovelTarget(repeatConfig: EffectiveRepeatConfig, settings: WatchSpeechSettings) -> (novelID: String, title: String, fromBeginning: Bool)? {
        let stored = PhoneSessionManager.shared.storedNovelIDs
        func title(of novelID: String) -> String {
            if let title = PhoneSessionManager.shared.storedTitles[novelID], !title.isEmpty { return title }
            return PhoneSessionManager.shared.novels.first(where: { $0.novelID == novelID })?.title ?? novelID
        }
        /// 候補リスト(order)から次の1冊を選ぶ
        func pick(order: [String]) -> (novelID: String, title: String, fromBeginning: Bool)? {
            if repeatConfig.isLoopNoCheckReadingPoint {
                // iPhone 側と同じく「現在の小説が候補リストに居る」ことが前提(居なければ停止)
                guard let currentIndex = order.firstIndex(of: novelID) else { return nil }
                for offset in 1...order.count {
                    let candidate = order[(currentIndex + offset) % order.count]
                    guard stored.contains(candidate) else { continue }
                    return (candidate, title(of: candidate), true)
                }
                return nil
            }
            for candidate in order where candidate != novelID && stored.contains(candidate) && hasUnreadContent(novelID: candidate) {
                return (candidate, title(of: candidate), false)
            }
            return nil
        }
        /// 条件に合う小説をタイトル順で(iPhone 側の作者・Webサイト系の並びと同じ)
        func titleSortedNovelIDs(where predicate: (WatchNovelSummary) -> Bool) -> [String] {
            return PhoneSessionManager.shared.novels.filter(predicate)
                .sorted { $0.title < $1.title }
                .map { $0.novelID }
        }
        switch repeatConfig.repeatType {
        case .goToNextLikeNovel:
            guard let order = settings.novelLikeOrder, !order.isEmpty else { return nil }
            return pick(order: order)
        case .goToNextSameFolderdNovel:
            // 現在の小説が属するフォルダを順に試す(iPhone 側と同じ)
            for folder in settings.novelFolders ?? [] where folder.novelIDs.contains(novelID) {
                if let next = pick(order: folder.novelIDs) { return next }
            }
            return nil
        case .goToNextSelectedFolderdNovel:
            guard let folderName = selectedFolderNameForRepeat,
                  let folder = (settings.novelFolders ?? []).first(where: { $0.name == folderName }) else { return nil }
            return pick(order: folder.novelIDs)
        case .goToNextSameWriterNovel:
            guard let currentWriter = PhoneSessionManager.shared.novels.first(where: { $0.novelID == novelID })?.writer else { return nil }
            return pick(order: titleSortedNovelIDs(where: { $0.writer == currentWriter }))
        case .goToNextSameWebsiteNovel:
            guard let currentWebsite = Self.websiteIdentifier(novelID: novelID) else { return nil }
            return pick(order: titleSortedNovelIDs(where: { Self.websiteIdentifier(novelID: $0.novelID) == currentWebsite }))
        default:
            return nil
        }
    }

    /// iPhone 側の「同じWebサイト」判定と同じ: ユーザ作成小説は "" 扱い、それ以外は URL のホスト名
    private static func websiteIdentifier(novelID: String) -> String? {
        if novelID.hasPrefix(WatchSpeechSettings.userCreatedContentPrefix) { return "" }
        return URL(string: novelID)?.host
    }

    /// 「指定フォルダの小説を再生」の対象フォルダ。再生開始時に決めて連続再生中は維持する
    private var selectedFolderNameForRepeat: String?

    /// 再生開始時に対象フォルダを確定する。iPhone 側と同じく、所属フォルダが1つなら自動選択。
    /// 複数の場合はユーザの選択(folderSelectionRequest 経由)が既に済んでいればそれを維持する
    private func updateSelectedFolderForRepeat() {
        let settings = WatchSpeechSettingsStorage.current()
        guard WatchSpeechPlayer.effectiveRepeatConfig().repeatType == .goToNextSelectedFolderdNovel else {
            selectedFolderNameForRepeat = nil
            return
        }
        let containing = (settings.novelFolders ?? []).filter { $0.novelIDs.contains(novelID) }
        // 選択済みのフォルダに現在の小説が居るならそれを維持(ダイアログでの選択を尊重)
        if let name = selectedFolderNameForRepeat, containing.contains(where: { $0.name == name }) { return }
        selectedFolderNameForRepeat = containing.count == 1 ? containing.first?.name : nil
    }

    /// 「指定フォルダの小説を再生」で対象フォルダの選択が必要なら候補のフォルダ名を返す。
    /// 選択が不要(設定が違う・所属フォルダが1つ以下)なら nil。
    /// 複数フォルダ所属なら選択済みでも毎回聞く(iPhone 側と同じ。フォルダを選び直せるように)
    private func folderSelectionCandidatesIfNeeded() -> [String]? {
        let settings = WatchSpeechSettingsStorage.current()
        guard WatchSpeechPlayer.effectiveRepeatConfig().repeatType == .goToNextSelectedFolderdNovel else { return nil }
        let containing = (settings.novelFolders ?? []).filter { $0.novelIDs.contains(novelID) }
        guard containing.count > 1 else { return nil }
        return containing.map { $0.name }
    }

    /// フォルダ選択ダイアログでフォルダが選ばれた。選択を覚えて再生を再開する
    func selectFolderForRepeatAndPlay(name: String) {
        folderSelectionRequest = nil
        selectedFolderNameForRepeat = name
        startPlayFlow(askFolderSelection: false)
    }

    /// 転送済みの小説に未読部分が残っているか。
    /// iPhone 側の未読判定に合わせて章末5文字の遊びを持つ。位置情報が無ければ未読とみなす。
    /// 栞が最終章にある時だけ最終バルクを展開する(候補走査で全小説を展開しないように)
    private func hasUnreadContent(novelID: String) -> Bool {
        let lastChapter = NovelStorage.storedChapterCount(novelID: novelID)
        guard lastChapter > 0 else { return false }
        let chapter: Int
        let location: Int
        if let position = WatchReadingPositionStore.load(novelID: novelID) {
            chapter = position.chapter
            location = position.location
        } else if let summary = PhoneSessionManager.shared.novels.first(where: { $0.novelID == novelID }),
                  summary.readingChapterNumber > 0 {
            // iPhone の栞は章単位でしか分からないので章の頭からとみなす
            chapter = summary.readingChapterNumber
            location = 0
        } else {
            return true
        }
        if chapter < lastChapter { return true }
        guard let story = NovelStorage.chapter(novelID: novelID, chapter: chapter) else { return true }
        return location + 5 < story.content.unicodeScalars.count
    }

    /// isAnnounceAtRepatSpeechTime(既定 true)が有効ならアナウンスしてから、無効なら直ちに continuation を呼ぶ
    private func announceIfEnabled(settings: WatchSpeechSettings, text: String, continuation: @escaping () -> Void) {
        guard settings.isAnnounceAtRepatSpeechTime ?? true else {
            continuation()
            return
        }
        announceSpeaker().speak(text: text, completion: continuation)
    }

    private var announcer: WatchAnnounceSpeaker?

    private func announceSpeaker() -> WatchAnnounceSpeaker {
        if let announcer = announcer { return announcer }
        let created = WatchAnnounceSpeaker()
        announcer = created
        return created
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
            let settings = WatchSpeechSettingsStorage.current()
            let repeatConfig = WatchSpeechPlayer.effectiveRepeatConfig()
            // 「現在の章を再生し直す」は次の章があっても同じ章をループする(iPhone 側と同じ)
            if repeatConfig.repeatType == .rewindToThisStory, self.applyChapter(self.chapterNumber, location: 0) {
                self.speaker.StartSpeech()
                self.savePosition()
                return
            }
            if self.applyChapter(self.chapterNumber + 1, location: 0) {
                self.speaker.StartSpeech()
                self.savePosition()
                return
            }
            // 最終章まで読み終えた。「再生が末尾に達した時の動作」に従う
            self.handleReachedEnd(repeatConfig: repeatConfig, settings: settings)
        }
    }
}

// MARK: - 切替アナウンス用の軽量スピーカー

/// 「次に◯◯を再生します」等のアナウンス用。本文用の SpeechBlockSpeaker とは独立させて、
/// finishSpeak のイベントが本文の再生フローに混ざらないようにする。
/// willSpeakRange は実装しない(定義するだけで約40MBのメモリを消費するため。ファイル冒頭の注意書き参照)
private final class WatchAnnounceSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// デフォルト話者の声・速度・音量でアナウンスを発話する。終わったら completion(main queue)
    func speak(text: String, completion: @escaping () -> Void) {
        // 前回の completion が残っていたら「呼ばずに」破棄する(古い継続処理を今呼ぶと発話が被る)
        self.completion = completion
        let speaker = WatchSpeechSettingsStorage.current().defaultSpeaker
        let config = WatchSpeechPlayer.effectiveDefaultSpeakerConfig()
        let utterance = AVSpeechUtterance(string: text)
        if !speaker.voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: speaker.voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: speaker.locale)
        }
        utterance.pitchMultiplier = speaker.pitch
        utterance.rate = config.rate
        utterance.volume = config.volume
        synthesizer.speak(utterance)
    }

    func cancel() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resolve()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resolve()
    }

    private func resolve() {
        // delegate コールバックは main queue とは限らないので、completion の取り出しごと main に寄せる
        DispatchQueue.main.async {
            guard let completion = self.completion else { return }
            self.completion = nil
            completion()
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

    /// 最近更新された読み上げ位置(新しい順、最大 limit 件)。
    /// 連続再生で複数の小説を読み終えた場合の iPhone への同期漏れを防ぐため、複数件返す
    static func recent(limit: Int) -> [(novelID: String, position: Position)] {
        return loadAll().sorted { $0.value.updatedAt > $1.value.updatedAt }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }

    /// updatedAt は通常は現在時刻。iPhone の栞を取り込む時だけ iPhone 側のタイムスタンプを
    /// そのまま渡す(時刻を進めると「新しい方優先」の比較が壊れるため)
    static func save(novelID: String, chapter: Int, location: Int, updatedAt: Date = Date()) {
        var positions = loadAll()
        positions[novelID] = Position(chapter: chapter, location: location, updatedAt: updatedAt)
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

// MARK: - 「再生が末尾に達した時の動作」の Watch 側ローカル差分

/// Watch で変更した「再生が末尾に達した時の動作」。仕組み・意味論は WatchSpeechConfigStore
/// (速度・音量のローカル差分)と同じ: 正本は iPhone の RealmGlobalState で、ここは
/// 書き戻すまでの間も Watch の連続再生に効かせるための差分。書き戻しが済んで
/// 新しい設定ファイルが届いたら reconcile で解消される
enum WatchRepeatConfigStore {
    private struct Stored: Codable {
        var repeatTypeRawValue: Int
        var isLoopNoCheck: Bool
        var updatedAt: Date
        var pendingSend: Bool
    }

    private static let key = "WatchRepeatConfigOverride"

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

    static func localOverride() -> (repeatTypeRawValue: Int, isLoopNoCheck: Bool)? {
        guard let stored = loadStored() else { return nil }
        return (stored.repeatTypeRawValue, stored.isLoopNoCheck)
    }

    static var isPendingSend: Bool {
        return loadStored()?.pendingSend == true
    }

    static func set(repeatTypeRawValue: Int, isLoopNoCheck: Bool) {
        save(Stored(repeatTypeRawValue: repeatTypeRawValue, isLoopNoCheck: isLoopNoCheck,
                    updatedAt: Date(), pendingSend: true))
    }

    static func markSent() {
        guard var stored = loadStored() else { return }
        stored.pendingSend = false
        save(stored)
    }

    static func clear() {
        save(nil)
    }

    static func reconcileAfterSettingsReceived() {
        guard let stored = loadStored(), stored.pendingSend == false else { return }
        let settings = WatchSpeechSettingsStorage.current()
        let matches = (settings.repeatSpeechTypeRawValue ?? 0) == stored.repeatTypeRawValue
            && (settings.isRepeatSpeechLoopNoCheckReadingPoint == true) == stored.isLoopNoCheck
        if matches || settings.updatedAt > stored.updatedAt {
            clear()
        }
    }
}
