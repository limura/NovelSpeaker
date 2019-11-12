//
//  SpeakSettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/12.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class SpeakerSettingsViewController: FormViewController {
    let speaker = Speaker()
    var testText = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
    var isRateSettingSync = true
    var hideCache:[String:Bool] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        BehaviorLogger.AddLog(description: "SettingsViewController viewDidLoad", data: [:])
        self.title = NSLocalizedString("SpeakerSettingsViewController_TitleText", comment: "話者設定")
        createSettingsTable()
        registNotificationCenter()
    }
    deinit {
        self.unregistNotificationCenter()
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
    
    func testSpeech(pitch:Float, rate: Float, identifier: String, text: String) {
        speaker.stopSpeech()
        speaker.setPitch(pitch)
        speaker.setRate(rate)
        speaker.setVoiceWithIdentifier(identifier)
        speaker.speech(text)
    }
    
    func createSpeakSettingRows(currentSetting:RealmSpeakerSetting) -> Section {
        let targetID = currentSetting.name
        var isDefaultSpeakerSetting = false
        autoreleasepool {
            if let globalState = RealmGlobalState.GetInstance() {
                autoreleasepool {
                    if let defaultSpeakerSetting = globalState.defaultSpeaker {
                        if defaultSpeakerSetting.name == targetID {
                            isDefaultSpeakerSetting = true
                        }
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
                self.hideCache[targetID] = false
            }
            for tag in [
                "PitchSliderRow-\(targetID)",
                "RateSliderRow-\(targetID)",
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
                return self.hideCache[targetID] ?? true
            })
        }.onChange({ (row) in
            if let value = row.value {
                autoreleasepool {
                    if let setting = RealmSpeakerSetting.SearchFrom(name: targetID) {
                        RealmUtil.Write { (realm) in
                            setting.pitch = value
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
                return self.hideCache[targetID] ?? true
            })
        }.onChange({ (row) in
            guard let rate = row.value else{
                return
            }
            if self.isRateSettingSync {
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
                    targetRow.value = rate
                    targetRow.updateCell()
                    autoreleasepool {
                        if let setting = RealmSpeakerSetting.SearchFrom(name: targetID) {
                            RealmUtil.Write { (realm) in
                                setting.rate = rate
                            }
                        }
                    }
                }
            }else{
                autoreleasepool {
                    if let setting = RealmSpeakerSetting.SearchFrom(name: targetID) {
                        RealmUtil.Write { (realm) in
                            setting.rate = rate
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
                return self.hideCache[targetID] ?? true
            })
        }.onChange({ (row) in
            autoreleasepool {
                guard let locale = row.value else {
                    return
                }
                guard let setting = RealmSpeakerSetting.SearchFrom(name: targetID) else {
                    return
                }
                var voiceNames:[String] = []
                var voiceName = ""
                RealmUtil.Write { (realm) in
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
                return self.hideCache[targetID] ?? true
            })
        }.onChange({ (row) in
            autoreleasepool {
                guard let voiceName = row.value else {
                    return
                }
                guard let voice = AVSpeechSynthesisVoice.speechVoices().filter({$0.name == voiceName}).first else {
                    return
                }
                guard  let setting = RealmSpeakerSetting.SearchFrom(name: targetID) else {
                    return
                }
                RealmUtil.Write { (realm) in
                    setting.voiceIdentifier = voice.identifier
                }
            }
        })
        <<< ButtonRow("TestSpeechButtonRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_TestSpeechButtonTitle", comment: "発音テスト")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                return self.hideCache[targetID] ?? true
            })
        }.onCellSelection({ (buttonCellOf, button) in
            autoreleasepool {
                guard  let setting = RealmSpeakerSetting.SearchFrom(name: targetID) else {
                    return
                }
                self.testSpeech(pitch: setting.pitch, rate: setting.rate, identifier: setting.voiceIdentifier, text: self.testText)
            }
        })
        if !isDefaultSpeakerSetting {
            section <<< ButtonRow("RemoveButtonRow-\(targetID)") {
                $0.title = NSLocalizedString("SpeakerSettingsViewController_RemoveButtonRow", comment: "この話者の設定を削除")
                $0.hidden = Condition.function(["TitleLabelRow-\(targetID)"], { (form) -> Bool in
                    return self.hideCache[targetID] ?? true
                })
            }.onCellSelection({ (buttonCellOf, button) in
                var settingName = ""
                autoreleasepool {
                    if let setting = RealmSpeakerSetting.SearchFrom(name: targetID) {
                        settingName = setting.name
                    }
                }
                NiftyUtilitySwift.EasyDialogTwoButton(
                viewController: self,
                title: settingName,
                message: NSLocalizedString("SpeakSettingsViewController_ConifirmRemoveTitle", comment: "この設定を削除しますか？"),
                button1Title: NSLocalizedString("Cancel_button", comment: "Cancel"),
                button1Action: nil,
                button2Title: NSLocalizedString("OK_button", comment: "OK"),
                button2Action: {
                    autoreleasepool {
                        guard let setting = RealmSpeakerSetting.SearchFrom(name: targetID) else {
                            return
                        }
                        RealmUtil.Write { (realm) in
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
                NiftyUtilitySwift.EasyDialogTextInput2Button(
                    viewController: self,
                    title: NSLocalizedString("SpeakerSettingsViewController_AddNewSpeakerTitle", comment: "追加される話者の名前を入力してください"),
                    message: nil,
                    textFieldText: "",
                    placeHolder: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorNil", comment: "名前に空文字列は設定できません"),
                    leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
                    rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
                    leftButtonAction: nil,
                    rightButtonAction: { (name) in
                        if autoreleasepool(invoking: { () -> Bool in
                            if RealmSpeakerSetting.SearchFrom(name: name) != nil {
                                DispatchQueue.main.async {
                                    NiftyUtilitySwift.EasyDialogOneButton(
                                        viewController: self,
                                        title: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorAlready", comment: "既に同じ名前の話者設定が存在します。"),
                                        message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                                return true
                            }else if name.count <= 0 {
                                DispatchQueue.main.async {
                                    NiftyUtilitySwift.EasyDialogOneButton(
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
                        autoreleasepool {
                            let newSpeakerSetting = RealmSpeakerSetting()
                            RealmUtil.Write { (realm) in
                                newSpeakerSetting.name = name
                                realm.add(newSpeakerSetting, update: .modified)
                            }
                            self.form.append(self.createSpeakSettingRows(currentSetting: newSpeakerSetting))
                        }
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogOneButton(
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
            $0.value = self.isRateSettingSync
        }.onChange({ (row) in
            guard let value = row.value else {
                return
            }
            self.isRateSettingSync = value
        })
        
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else {
                return
            }
            if let defaultSpeaker = globalState.defaultSpeaker {
                // defaultSpeaker がある場合はそれが一番上です。
                sections = sections +++ createSpeakSettingRows(currentSetting: defaultSpeaker)
                autoreleasepool {
                    if let speakerSettingArray  = RealmSpeakerSetting.GetAllObjects()?.filter("name != %@", defaultSpeaker.name) {
                        for speakerSetting in speakerSettingArray {
                            sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
                        }
                    }
                }
            }else{
                autoreleasepool {
                    if let speakerSettingArray  = RealmSpeakerSetting.GetAllObjects() {
                        for speakerSetting in speakerSettingArray {
                            sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
                        }
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
