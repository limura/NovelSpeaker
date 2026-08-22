//
//  SpeakSettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/12.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import AVFoundation
import RealmSwift

class SpeakerSettingsViewController: FormViewController, RealmObserverResetDelegate {
    let speaker = SpeechBlockSpeaker()
    var testText = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
    static var isRateSettingSync = true
    var rateSyncValue:Float? = nil
    static var isVolumeSettingSync = true
    var volumeSyncValue:Float? = nil
    var hideCache:[String:Bool] = [:]
    var sliderMoveDate:Date = Date(timeIntervalSince1970: 0)
    
    var speakerSettingNotificationToken:NotificationToken? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        BehaviorLogger.AddLog(description: "SettingsViewController viewDidLoad", data: [:])
        self.title = NSLocalizedString("SpeakerSettingsViewController_TitleText", comment: "話者設定")
        createSettingsTable()
        registNotificationCenter()
        registNotificationToken()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        if VoicevoxCore.isAvailableOnThisOS {
            Task {
                await VoicevoxCore.setUpFromBundleIfNeeded()
                await MainActor.run {
                    self.refreshAllVoicevoxStyleRows()
                }
            }
        }
    }

    /// 今この端末で使えるスタイルの styleId 一覧。
    static func availableVoicevoxStyleIds() -> Set<UInt32> {
        return Set(VoicevoxCore.cachedStyles.map { $0.styleId })
    }

    /// 今この話者設定が指している styleId。取得済みでなくても返す。
    static func currentVoicevoxStyleId(targetID: String) -> UInt32? {
        return RealmUtil.RealmBlock { (realm) -> UInt32? in
            guard let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID),
                  setting.type == "VOICEVOX" else { return nil }
            return UInt32(setting.voiceIdentifier)
        }
    }

    /// 未取得のスタイルの名前。手元に無いので、カタログから引く。
    /// これが無いと「(未取得) スタイル番号 37」としか出せず、
    /// 誰を選んでいたのか利用者に分からない。
    static func catalogStyleLabel(for styleId: UInt32) -> String? {
        guard let catalog = VoicevoxVoiceModelCatalogLoader.preferredCatalog(),
              let entry = catalog.entry(forStyleId: styleId) else { return nil }
        return entry.displayName
    }

    /// VOICEVOX話者設定の voiceIdentifier を見て、スタイル選択行に表示すべきラベルを返す。
    ///
    /// **未取得なだけの設定は書き換えない。** 音声モデルを消しただけで
    /// 全ての小説の話者設定が別人に書き換わり、取り直しても戻らない、という
    /// 取り返しのつかない壊れ方をするため(詳細は VoicevoxStyleSelection.swift)。
    ///
    /// 書き換えるのは「styleId ですらない」場合だけ。これは読み上げエンジンを
    /// AVSpeechSynthesizer から VOICEVOX に切り替えた時、従来 setting.type しか
    /// 書いていなかったために voiceIdentifier が AVSpeech の音声ID
    /// (例: com.apple.ttsbundle.siri_O-ren_ja-JP_premium)のまま残る、という残骸で、
    /// 放っておくと再生側が styleId=0 にフォールバックして意図しない話者で読み上げ、
    /// 先行合成との間でキーが食い違って地の文が常に無音になる原因にもなる。
    @discardableResult
    private func resolveVoicevoxStyleLabel(targetID: String) -> String? {
        let availableStyleIds = SpeakerSettingsViewController.availableVoicevoxStyleIds()
        var resultLabel: String? = nil
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else { return }
            let selection = VoicevoxStyleSelectionResolver.resolve(
                voiceIdentifier: setting.voiceIdentifier, availableStyleIds: availableStyleIds)
            switch selection {
            case .available(let styleId):
                resultLabel = SpeakerSettingsViewController.voicevoxStyleLabel(for: styleId)
            case .notDownloaded(let styleId):
                // 保存値には触らない。音声モデルを取り直せば、そのまま元の話者に戻る。
                resultLabel = VoicevoxStyleSelectionResolver.notDownloadedLabel(
                    styleId: styleId,
                    knownName: SpeakerSettingsViewController.voicevoxStyleLabel(for: styleId)
                        ?? SpeakerSettingsViewController.catalogStyleLabel(for: styleId))
            case .notAStyleId:
                // ★VOICEVOX を使う話者設定でない限り、絶対に書き換えない。
                // AVSpeechSynthesizer の話者設定の voiceIdentifier は音声IDそのものなので、
                // ここで styleId を書き込むと、選んであった音声が失われる。
                guard setting.type == "VOICEVOX" else { return }
                guard let fallbackLabel = SpeakerSettingsViewController.voicevoxStyleOptionLabels().first,
                      let fallbackStyleId = SpeakerSettingsViewController.voicevoxStyleId(forLabel: fallbackLabel) else {
                    // 音声モデルを1つも持っていない時は直しようが無いので、何もしない。
                    // (下手に既定値を書くより、未設定のままにしておく方が害が無い)
                    return
                }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                    setting.voiceIdentifier = String(fallbackStyleId)
                }
                resultLabel = fallbackLabel
            }
        }
        return resultLabel
    }

    // 画面上の全VOICEVOXスタイル選択行の表示を最新化する。
    // (音声モデルを取得すると「(未取得) …」だった行が本来の名前に変わる)
    func refreshAllVoicevoxStyleRows() {
        for row in self.form.rows.compactMap({ $0 as? LabelRow }) where row.tag?.hasPrefix("VoicevoxStyleRow-") == true {
            let targetID = String(row.tag?.dropFirst("VoicevoxStyleRow-".count) ?? "")
            row.value = self.resolveVoicevoxStyleLabel(targetID: targetID) ?? row.value
            row.updateCell()
        }
    }

    static func voicevoxStyleOptionLabels() -> [String] {
        return VoicevoxCore.cachedStyles.map { style in
            "\(style.speakerName) - \(style.name)"
        }
    }
    static func voicevoxStyleLabel(for styleId: UInt32) -> String? {
        guard let style = VoicevoxCore.cachedStyles.first(where: { $0.styleId == styleId }) else { return nil }
        return "\(style.speakerName) - \(style.name)"
    }
    static func voicevoxStyleId(forLabel label: String) -> UInt32? {
        return VoicevoxCore.cachedStyles.first(where: { "\($0.speakerName) - \($0.name)" == label })?.styleId
    }
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    func StopObservers() {
        speakerSettingNotificationToken = nil
    }
    func RestartObservers() {
        registNotificationToken()
    }
    
    func registNotificationToken() {
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let speakerSettings = RealmSpeakerSetting.GetAllObjectsWith(realm: realm) else { return }
                self.speakerSettingNotificationToken = speakerSettings.observe({ (change) in
                    switch change {
                    case .update(_, deletions: _, insertions: _, modifications: _):
                        if self.sliderMoveDate > Date(timeIntervalSinceNow: -1) { return }
                        DispatchQueue.main.async {
                            self.form.removeAll()
                            self.createSettingsTable()
                        }
                    case .initial(_):
                        break
                    default:
                        break
                    }
                })
            }
        }
    }
    
    func registNotificationCenter() {
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.RealmSettingChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }
    
    func testSpeech(pitch:Float, rate: Float, volume: Float, identifier: String, locale: String, type: String, text: String) {
        let speakerSetting = RealmSpeakerSetting()
        speakerSetting.pitch = pitch
        speakerSetting.rate = rate
        speakerSetting.volume = volume
        speakerSetting.voiceIdentifier = identifier
        speakerSetting.locale = locale
        speakerSetting.type = type
        let defaultSpeaker = SpeakerSetting(from: speakerSetting)
        speaker.StopSpeech()
        speaker.SetText(content: text, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max, defaultSpeaker: defaultSpeaker, sectionConfigList: [], waitConfigList: [], sortedSpeechModArray: [])
        speaker.StartSpeech()
    }
    
    func currentEngineType(targetID: String) -> String {
        #if targetEnvironment(macCatalyst)
        if let row = self.form.rowBy(tag: "EngineTypeAlertRow-\(targetID)") as? PushRow<String> {
            return row.value ?? "AVSpeechSynthesizer"
        }
        #else
        if let row = self.form.rowBy(tag: "EngineTypeAlertRow-\(targetID)") as? AlertRow<String> {
            return row.value ?? "AVSpeechSynthesizer"
        }
        #endif
        return "AVSpeechSynthesizer"
    }

    func createSpeakSettingRows(currentSetting:RealmSpeakerSetting) -> Section {
        let targetID = currentSetting.name
        var isDefaultSpeakerSetting = false
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if let defaultSpeakerSetting = globalState.defaultSpeakerWith(realm: realm) {
                    if defaultSpeakerSetting.name == targetID {
                        isDefaultSpeakerSetting = true
                    }
                }
            }
        }

        let section = Section()
        section <<< LabelRow("TitleLabelRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_SpeakSettingNameTitle", comment: "名前")
            $0.value = currentSetting.name
        }.onCellSelection({ (_, _) in
            if let isHide = self.hideCache[targetID] {
                self.hideCache[targetID] = !isHide
            }else{
                self.hideCache[targetID] = true
            }
            for tag in [
                "PitchSliderRow-\(targetID)",
                "RateSliderRow-\(targetID)",
                "VolumeSliderRow-\(targetID)",
                "EngineTypeAlertRow-\(targetID)",
                "LanguageAlertRow-\(targetID)",
                "VoiceIdentifierAlertRow-\(targetID)",
                "VoicevoxStyleRow-\(targetID)",
                "TestSpeechButtonRow-\(targetID)",
                "RemoveButtonRow-\(targetID)"
                ] {
                if let row = self.form.rowBy(tag: tag) {
                    row.evaluateHidden()
                    row.updateCell()
                }
            }
        })
        section
        <<< SliderRow("PitchSliderRow-\(targetID)") {
            $0.value = currentSetting.pitch
            $0.cell.slider.minimumValue = 0.5
            $0.cell.slider.maximumValue = 2.0
            $0.shouldHideValue = false
            $0.displayValueFor = { (value:Float?) -> String? in
                guard let value = value else { return "" }
                return String(format: "%.2f", value)
            }
            $0.steps = 2501
            $0.title = NSLocalizedString("SpeakSettingsViewController_PitchTitle", comment: "高さ")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? false
            })
        }.onChange({ (row) in
            self.sliderMoveDate = Date()
            if let value = row.value {
                DispatchQueue.main.async {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        if let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) {
                            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                                setting.pitch = value
                            }
                        }
                    }
                }
            }
        })
        <<< SliderRow("RateSliderRow-\(targetID)") {
            $0.value = currentSetting.rate
            $0.cell.slider.minimumValue = AVSpeechUtteranceMinimumSpeechRate
            $0.cell.slider.maximumValue = AVSpeechUtteranceMaximumSpeechRate
            $0.shouldHideValue = false
            $0.displayValueFor = { (value:Float?) -> String? in
                guard let value = value else { return "" }
                return String(format: "%.2f", value)
            }
            $0.steps = 1001
            $0.title = NSLocalizedString("SpeakSettingsViewController_RateTitle", comment: "速度")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? false
            })
        }.onChange({ (row) in
            self.sliderMoveDate = Date()
            guard let rate = row.value else{
                return
            }
            let currentRowTag = row.tag
            if SpeakerSettingsViewController.isRateSettingSync {
                if let syncValue = self.rateSyncValue, syncValue == rate { return }
                self.rateSyncValue = rate
                for row in self.form.rows.filter({ (row) -> Bool in
                    guard let row = row as? SliderRow else {
                        return false
                    }
                    guard let tag = row.tag else {
                        return false
                    }
                    return tag.hasPrefix("RateSliderRow-")
                }) {
                    guard let targetRow = row as? SliderRow else {
                        continue
                    }
                    guard let targetTag = targetRow.tag else {
                        continue
                    }
                    let targetID = String(targetTag.suffix(targetTag.count - 14))
                    DispatchQueue.main.async {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            if let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) {
                                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                                    setting.rate = rate
                                }
                            }
                        }
                    }
                    if let thisRowTag = row.tag, let currentRowTag = currentRowTag, thisRowTag == currentRowTag { continue }
                    targetRow.value = rate
                    targetRow.updateCell()
                }
            }else{
                DispatchQueue.main.async {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        if let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) {
                            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                                setting.rate = rate
                            }
                        }
                    }
                }
            }
        })
        section
        <<< SliderRow("VolumeSliderRow-\(targetID)") {
            $0.value = currentSetting.volume
            $0.cell.slider.minimumValue = 0.0
            $0.cell.slider.maximumValue = 1.0
            $0.shouldHideValue = false
            $0.displayValueFor = { (value:Float?) -> String? in
                guard let value = value else { return "" }
                return String(format: "%.2f", value)
            }
            $0.steps = 1000
            $0.title = NSLocalizedString("SpeakSettingsViewController_VolumeTitle", comment: "大きさ")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? false
            })
        }.onChange({ (row) in
            self.sliderMoveDate = Date()
            guard let volume = row.value else{
                return
            }
            let currentRowTag = row.tag
            if SpeakerSettingsViewController.isVolumeSettingSync {
                if let volumeValue = self.volumeSyncValue, volumeValue == volume { return }
                self.volumeSyncValue = volume
                for row in self.form.rows.filter({ (row) -> Bool in
                    guard let row = row as? SliderRow else {
                        return false
                    }
                    guard let tag = row.tag else {
                        return false
                    }
                    return tag.hasPrefix("VolumeSliderRow-")
                }) {
                    guard let targetRow = row as? SliderRow else {
                        continue
                    }
                    guard let targetTag = targetRow.tag else {
                        continue
                    }
                    let targetID = String(targetTag.suffix(targetTag.count - 16))
                    DispatchQueue.main.async {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            if let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) {
                                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                                    setting.volume = volume
                                }
                            }
                        }
                    }
                    if let thisRowTag = row.tag, let currentRowTag = currentRowTag, thisRowTag == currentRowTag { continue }
                    targetRow.value = volume
                    targetRow.updateCell()
                }
            }else{
                DispatchQueue.main.async {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        if let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) {
                            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                                setting.volume = volume
                            }
                        }
                    }
                }
            }
        })
        #if targetEnvironment(macCatalyst)
        let engineTypeRow = PushRow<String>("EngineTypeAlertRow-\(targetID)")
        ConfigureCatalystSingleSelectionPushRow(engineTypeRow)
        #else
        let engineTypeRow = AlertRow<String>("EngineTypeAlertRow-\(targetID)")
        engineTypeRow.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
        #endif
        engineTypeRow.title = NSLocalizedString("SpeakSettingsViewController_EngineTypeTitle", comment: "読み上げエンジン")
        engineTypeRow.selectorTitle = NSLocalizedString("SpeakSettingsViewController_EngineTypeDialogTitle", comment: "読み上げエンジンを選択してください")
        var engineTypeOptions = ["AVSpeechSynthesizer"]
        if VoicevoxCore.isAvailableOnThisOS {
            engineTypeOptions.append("VOICEVOX")
        }
        engineTypeRow.options = engineTypeOptions
        engineTypeRow.value = engineTypeOptions.contains(currentSetting.type) ? currentSetting.type : "AVSpeechSynthesizer"
        engineTypeRow.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
            return self.hideCache[targetID] ?? false
        })
        engineTypeRow.onChange({ (row) in
            guard let type = row.value else { return }
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                    setting.type = type
                }
            }
            if type == "VOICEVOX" {
                // 従来はここで type しか書いていなかったため、voiceIdentifier が
                // AVSpeech の音声IDのまま残り、再生時に styleId=0 へフォールバックしていた。
                // 有効な styleId を確定させ、スタイル選択行の表示とも一致させる。
                if let label = self.resolveVoicevoxStyleLabel(targetID: targetID),
                   let styleRow = self.form.rowBy(tag: "VoicevoxStyleRow-\(targetID)") as? LabelRow {
                    styleRow.value = label
                }
            }
            for tag in ["LanguageAlertRow-\(targetID)", "VoiceIdentifierAlertRow-\(targetID)", "VoicevoxStyleRow-\(targetID)"] {
                if let row = self.form.rowBy(tag: tag) {
                    row.evaluateHidden()
                    row.updateCell()
                }
            }
        })
        section <<< engineTypeRow

        #if targetEnvironment(macCatalyst)
        let languageRow = PushRow<String>("LanguageAlertRow-\(targetID)")
        ConfigureCatalystSingleSelectionPushRow(languageRow)
        #else
        let languageRow = AlertRow<String>("LanguageAlertRow-\(targetID)")
        languageRow.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
        #endif
        languageRow.title = NSLocalizedString("SpeakSettingsViewController_LangageTitle", comment: "言語")
        languageRow.selectorTitle = NSLocalizedString("SpeakSettingsViewController_LanguageDialogTitle", comment: "言語を選択してください")
        let languageCodeArray = Array(Set(AVSpeechSynthesisVoice.speechVoices().map({ $0.language }))).sorted()
        languageRow.options = languageCodeArray
        if languageCodeArray.contains(currentSetting.locale) {
            languageRow.value = currentSetting.locale
        }else if languageCodeArray.contains("ja-JP") {
            languageRow.value = "ja-JP"
        }else{
            languageRow.value = languageCodeArray.first ?? ""
        }
        languageRow.hidden = Condition.function(["TitleLabelRow-\(targetID)", "EngineTypeAlertRow-\(targetID)"], { (form) -> Bool in
            if self.hideCache[targetID] ?? false { return true }
            return self.currentEngineType(targetID: targetID) == "VOICEVOX"
        })
        languageRow.onChange({ (row) in
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let locale = row.value else {
                    return
                }
                guard let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else {
                    return
                }
                var voiceNames:[String] = []
                var voiceName = ""
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                    let voices = AVSpeechSynthesisVoice.speechVoices().filter({$0.language == locale})
                    voiceNames = voices.map({$0.name})
                    voiceName = voiceNames.first ?? ""
                    if let newVoice = voices.filter({$0.name == voiceName}).first {
                        setting.voiceIdentifier = newVoice.identifier
                    }
                    setting.locale = locale
                }
                #if targetEnvironment(macCatalyst)
                let voiceIdentifierRow = self.form.rowBy(tag: "VoiceIdentifierAlertRow-\(targetID)") as? PushRow<String>
                #else
                let voiceIdentifierRow = self.form.rowBy(tag: "VoiceIdentifierAlertRow-\(targetID)") as? AlertRow<String>
                #endif
                if let voiceIdentifierRow = voiceIdentifierRow {
                    voiceIdentifierRow.options = voiceNames
                    voiceIdentifierRow.value = voiceName
                    voiceIdentifierRow.updateCell()
                }
            }
        })
        section <<< languageRow
        #if targetEnvironment(macCatalyst)
        let voiceIdentifierRow = PushRow<String>("VoiceIdentifierAlertRow-\(targetID)")
        ConfigureCatalystSingleSelectionPushRow(voiceIdentifierRow)
        #else
        let voiceIdentifierRow = AlertRow<String>("VoiceIdentifierAlertRow-\(targetID)")
        voiceIdentifierRow.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
        #endif
        voiceIdentifierRow.title = NSLocalizedString("SpeakSettingsViewController_VoiceIdentifierTitle", comment: "話者")
        voiceIdentifierRow.selectorTitle = NSLocalizedString("SpeakSettingsViewController_VoiceIdentifierDialogTitle", comment: "話者を選択してください")
        let voiceNameArray = AVSpeechSynthesisVoice.speechVoices().filter({ $0.language == currentSetting.locale }).map({$0.name}).sorted()
        voiceIdentifierRow.options = voiceNameArray
        let voice = AVSpeechSynthesisVoice(identifier: currentSetting.voiceIdentifier)
        let voiceName = voice?.name ?? ""
        if voiceNameArray.contains(voiceName) {
            voiceIdentifierRow.value = voiceName
        }else{
            voiceIdentifierRow.value = voiceNameArray.first ?? ""
        }
        voiceIdentifierRow.hidden = Condition.function(["TitleLabelRow-\(targetID)", "EngineTypeAlertRow-\(targetID)"], { (form) -> Bool in
            if self.hideCache[targetID] ?? false { return true }
            return self.currentEngineType(targetID: targetID) == "VOICEVOX"
        })
        voiceIdentifierRow.onChange({ (row) in
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let voiceName = row.value else {
                    return
                }
                guard let voice = AVSpeechSynthesisVoice.speechVoices().filter({$0.language == currentSetting.locale && $0.name == voiceName}).first else {
                    return
                }
                guard  let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else {
                    return
                }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                    setting.voiceIdentifier = voice.identifier
                }
            }
        })
        section <<< voiceIdentifierRow

        // スタイルは127個あり、その大半は手元に無い。選択肢を並べるのではなく、
        // 絞り込みと取得ができる専用の画面へ送る(VoicevoxStyleSelectViewController)。
        let voicevoxStyleRow = LabelRow("VoicevoxStyleRow-\(targetID)")
        voicevoxStyleRow.title = NSLocalizedString("SpeakSettingsViewController_VoicevoxStyleTitle", comment: "VOICEVOX話者")
        // 表示だけフォールバックして保存しないと画面と保存値が食い違うが、
        // かといって何でも書き換えると未取得のスタイルを指す設定を壊す。
        // その区別は resolveVoicevoxStyleLabel に閉じ込めてある。
        voicevoxStyleRow.value = self.resolveVoicevoxStyleLabel(targetID: targetID) ?? ""
        voicevoxStyleRow.hidden = Condition.function(["TitleLabelRow-\(targetID)", "EngineTypeAlertRow-\(targetID)"], { (form) -> Bool in
            if self.hideCache[targetID] ?? false { return true }
            return self.currentEngineType(targetID: targetID) != "VOICEVOX"
        })
        voicevoxStyleRow.cellUpdate({ (cell, _) in
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
        })
        voicevoxStyleRow.onCellSelection({ [weak self] (_, row) in
            guard let self = self else { return }
            let nextViewController = VoicevoxStyleSelectViewController.instantiate(
                currentStyleId: SpeakerSettingsViewController.currentVoicevoxStyleId(targetID: targetID),
                onSelected: { styleId in
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else { return }
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                            setting.voiceIdentifier = String(styleId)
                        }
                    }
                    row.value = self.resolveVoicevoxStyleLabel(targetID: targetID) ?? ""
                    row.updateCell()
                })
            self.navigationController?.pushViewController(nextViewController, animated: true)
        })
        section <<< voicevoxStyleRow
        <<< ButtonRow("TestSpeechButtonRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_TestSpeechButtonTitle", comment: "発音テスト")
            $0.cell.textLabel?.numberOfLines = 0
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? false
            })
        }.onCellSelection({ (buttonCellOf, button) in
            RealmUtil.RealmBlock { (realm) -> Void in
                guard  let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else {
                    return
                }
                print("testSpeech: volume: \(setting.volume), name: \(setting.name)")
                // 未取得のVOICEVOX話者では合成できない。黙って失敗すると
                // 「押しても無反応」にしか見えないので、取得へ繋ぐ。
                if setting.type == "VOICEVOX", let styleId = UInt32(setting.voiceIdentifier),
                   VoicevoxVoiceModelConsentDialog.presentIfNotDownloaded(
                        on: self, styleId: styleId,
                        onStarted: { [weak self] in self?.refreshAllVoicevoxStyleRows() }) {
                    return
                }
                self.testSpeech(pitch: setting.pitch, rate: setting.rate, volume: setting.volume, identifier: setting.voiceIdentifier, locale: setting.locale, type: setting.type, text: self.testText)
            }
        })
        if !isDefaultSpeakerSetting {
            section <<< ButtonRow("RemoveButtonRow-\(targetID)") {
                $0.title = NSLocalizedString("SpeakerSettingsViewController_RemoveButtonRow", comment: "この話者の設定を削除")
                $0.cell.textLabel?.numberOfLines = 0
                $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                    return self.hideCache[targetID] ?? false
                })
            }.onCellSelection({ (buttonCellOf, button) in
                var settingName = ""
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) {
                        settingName = setting.name
                    }
                }
                NiftyUtility.EasyDialogTwoButton(
                viewController: self,
                title: settingName,
                message: NSLocalizedString("SpeakSettingsViewController_ConifirmRemoveTitle", comment: "この設定を削除しますか？"),
                button1Title: NSLocalizedString("Cancel_button", comment: "Cancel"),
                button1Action: nil,
                button2Title: NSLocalizedString("OK_button", comment: "OK"),
                button2Action: {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let setting = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetID) else {
                            return
                        }
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                            setting.delete(realm: realm)
                        }
                    }
                    if let index = self.form.firstIndex(of: section) {
                        print("remove section index: \(index)")
                        self.form.remove(at: index)
                    }else{
                        print("can not remove section because index is nil")
                    }
                })
            })
        }

        return section
    }

    func createSettingsTable(){
        var sections = form +++ Section()
        <<< TextAreaRow() {
            $0.placeholder = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
            $0.value = testText
            $0.cell.textView.layer.borderWidth = 0.2
            $0.cell.textView.layer.cornerRadius = 10.0
            $0.cell.textView.layer.masksToBounds = true
        }.onChange({ (row) in
            if let value = row.value {
                self.testText = value
            }
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SpeakSettingsViewController_AddNewSettingButtonTitle", comment: "新しく話者設定を追加する")
        }.onCellSelection({ (_, button) in
            DispatchQueue.main.async {
                NiftyUtility.EasyDialogTextInput2Button(
                    viewController: self,
                    title: NSLocalizedString("SpeakerSettingsViewController_AddNewSpeakerTitle", comment: "追加される話者の名前を入力してください"),
                    message: nil,
                    textFieldText: "",
                    placeHolder: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorNil", comment: "名前に空文字列は設定できません"),
                    leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
                    rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
                    leftButtonAction: nil,
                    rightButtonAction: { (name) in
                        if RealmUtil.RealmBlock(block: { (realm) -> Bool in
                            if RealmSpeakerSetting.SearchFromWith(realm: realm, name: name) != nil {
                                DispatchQueue.main.async {
                                    NiftyUtility.EasyDialogOneButton(
                                        viewController: self,
                                        title: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorAlready", comment: "既に同じ名前の話者設定が存在します。"),
                                        message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                                return true
                            }else if name.count <= 0 {
                                DispatchQueue.main.async {
                                    NiftyUtility.EasyDialogOneButton(
                                        viewController: self,
                                        title: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorNil", comment: "名前に空文字列は設定できません"),
                                        message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                                return true
                            }
                            return false
                        }) {
                            return
                        }
                        RealmUtil.RealmBlock { (realm) -> Void in
                            let newSpeakerSetting = RealmSpeakerSetting()
                            newSpeakerSetting.name = name
                            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingNotificationToken]) { (realm) in
                                realm.add(newSpeakerSetting, update: .modified)
                            }
                            self.form.append(self.createSpeakSettingRows(currentSetting: newSpeakerSetting))
                        }
                        DispatchQueue.main.async {
                            NiftyUtility.EasyDialogOneButton(
                                viewController: self,
                                title: NSLocalizedString("SpeakSettingsViewController_SpeakerSettingAdded", comment: "末尾に話者設定を追加しました。\n(恐らくはスクロールする必要があります)"),
                                message: nil,
                                buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                                buttonAction:nil)
                        }
                    },
                    shouldReturnIsRightButtonClicked: true)
            }
        })
        <<< SwitchRow() {
            $0.title = NSLocalizedString("SpeakSettingsViewController_SyncRateSetting", comment: "速度設定を同期する")
            $0.value = SpeakerSettingsViewController.isRateSettingSync
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ (row) in
            guard let value = row.value else {
                return
            }
            SpeakerSettingsViewController.isRateSettingSync = value
        })
        <<< SwitchRow() {
            $0.title = NSLocalizedString("SpeakSettingsViewController_SyncVolumeSetting", comment: "大きさ設定を同期する")
            $0.value = SpeakerSettingsViewController.isVolumeSettingSync
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ (row) in
            guard let value = row.value else {
                return
            }
            SpeakerSettingsViewController.isVolumeSettingSync = value
        })

        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                return
            }
            if let defaultSpeaker = globalState.defaultSpeakerWith(realm: realm) {
                // defaultSpeaker がある場合はそれが一番上です。
                sections = sections +++ createSpeakSettingRows(currentSetting: defaultSpeaker)
                if let speakerSettingArray  = RealmSpeakerSetting.GetAllObjectsWith(realm: realm)?.filter("name != %@", defaultSpeaker.name) {
                    for speakerSetting in speakerSettingArray {
                        sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
                    }
                }
            }else{
                if let speakerSettingArray  = RealmSpeakerSetting.GetAllObjectsWith(realm: realm) {
                    for speakerSetting in speakerSettingArray {
                        sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
                    }
                }
            }
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
