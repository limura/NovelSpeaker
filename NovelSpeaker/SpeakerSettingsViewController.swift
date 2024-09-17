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
    
    func testSpeech(pitch:Float, rate: Float, volume: Float, identifier: String, locale: String, text: String) {
        let speakerSetting = RealmSpeakerSetting()
        speakerSetting.pitch = pitch
        speakerSetting.rate = rate
        speakerSetting.volume = volume
        speakerSetting.voiceIdentifier = identifier
        speakerSetting.locale = locale
        let defaultSpeaker = SpeakerSetting(from: speakerSetting)
        speaker.StopSpeech()
        speaker.SetText(content: text, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max, defaultSpeaker: defaultSpeaker, sectionConfigList: [], waitConfigList: [], sortedSpeechModArray: [])
        speaker.StartSpeech()
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
                "LanguageAlertRow-\(targetID)",
                "VoiceIdentifierAlertRow-\(targetID)",
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
        <<< AlertRow<String>("LanguageAlertRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_LangageTitle", comment: "言語")
            $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            $0.selectorTitle = NSLocalizedString("SpeakSettingsViewController_LanguageDialogTitle", comment: "言語を選択してください")
            let languageCodeArray = Array(Set(AVSpeechSynthesisVoice.speechVoices().map({ $0.language }))).sorted()
            $0.options = languageCodeArray
            if languageCodeArray.contains(currentSetting.locale) {
                $0.value = currentSetting.locale
            }else if languageCodeArray.contains("ja-JP") {
                $0.value = "ja-JP"
            }else{
                $0.value = languageCodeArray.first ?? ""
            }
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? false
            })
        }.onChange({ (row) in
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
                if let voiceIdentifierRow = self.form.rowBy(tag: "VoiceIdentifierAlertRow-\(targetID)") as? AlertRow<String> {
                    voiceIdentifierRow.options = voiceNames
                    voiceIdentifierRow.value = voiceName
                    voiceIdentifierRow.updateCell()
                }
            }
        })
        <<< AlertRow<String>("VoiceIdentifierAlertRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_VoiceIdentifierTitle", comment: "話者")
            $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            $0.selectorTitle = NSLocalizedString("SpeakSettingsViewController_VoiceIdentifierDialogTitle", comment: "話者を選択してください")
            let voiceNameArray = AVSpeechSynthesisVoice.speechVoices().filter({ $0.language == currentSetting.locale }).map({$0.name}).sorted()
            $0.options = voiceNameArray
            let voice = AVSpeechSynthesisVoice(identifier: currentSetting.voiceIdentifier)
            let voiceName = voice?.name ?? ""
            if voiceNameArray.contains(voiceName) {
                $0.value = voiceName
            }else{
                $0.value = voiceNameArray.first ?? ""
            }
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? false
            })
        }.onChange({ (row) in
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
                self.testSpeech(pitch: setting.pitch, rate: setting.rate, volume: setting.volume, identifier: setting.voiceIdentifier, locale: setting.locale, text: self.testText)
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
