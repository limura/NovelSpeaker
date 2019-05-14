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

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        BehaviorLogger.AddLog(description: "SettingsViewController viewDidLoad", data: [:])
        self.title = NSLocalizedString("SpeakerSettingsViewController_TitleText", comment: "話者設定")
        createSettingsTable()
    }
    
    func testSpeech(pitch:Float, rate: Float, identifier: String, text: String) {
        speaker.stopSpeech()
        speaker.setPitch(pitch)
        speaker.setRate(rate)
        speaker.setVoiceWithIdentifier(identifier)
        speaker.speech(text)
    }
    
    func createSpeakSettingRows(currentSetting:RealmSpeakerSetting) -> Section {
        let targetID = currentSetting.id
        let realm = try! RealmUtil.GetRealm()
        var isDefaultSpeakerSetting = false
        if let globalState = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID) {
            if let defaultSpeakerSetting = globalState.defaultSpeaker {
                if defaultSpeakerSetting.id == targetID {
                    isDefaultSpeakerSetting = true
                }
            }
        }

        let section = Section()
        if isDefaultSpeakerSetting {
            section <<< LabelRow() {
                $0.title = NSLocalizedString("SpeakSettingsViewController_SpeakSettingNameTitle", comment: "名前")
                $0.value = currentSetting.name
            }
        }else{
            section
            <<< TextRow("TitleRow-\(targetID)") {
                $0.title = NSLocalizedString("SpeakSettingsViewController_SpeakSettingNameTitle", comment: "名前")
                $0.value = currentSetting.name
                $0.add(rule: RuleClosure<String>(closure: { (name) -> ValidationError? in
                    guard let name = name else {
                        return ValidationError(msg: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorNil", comment: "名前に空文字列は設定できません"))
                    }
                    let realm = try! RealmUtil.GetRealm()
                    if realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND id != %@ AND name = %@", targetID, name).first != nil {
                        return ValidationError(msg: NSLocalizedString("SpeakerSettingViewController_NameValidateErrorAlready", comment: "既に定義済みの名前です"))
                    }
                    return nil
                }))
                $0.validationOptions = .validatesOnChange
                //$0.cellStyle = .value1
                //$0.cell.textField.textAlignment = .left
                $0.cell.textField.borderStyle = .roundedRect
            }.onChange({ (row) in
                if let value = row.value {
                    if value.count <= 0 || !row.isValid {
                        return
                    }
                    let realm = try! RealmUtil.GetRealm()
                    if let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) {
                        try! realm.write {
                            setting.name = value
                        }
                    }
                }
            }).cellUpdate({ (textCell, textRow) in
                if !textRow.isValid {
                    textCell.titleLabel?.textColor = .red
                    textCell.detailTextLabel?.text = textRow.validationErrors.first?.msg
                }
            })
        }
        section
        <<< SliderRow("PitchSliderRow-\(targetID)") {
            $0.value = currentSetting.pitch
            $0.cell.slider.minimumValue = 0.5
            $0.cell.slider.maximumValue = 2.0
            $0.shouldHideValue = true
            $0.steps = 2501
            $0.title = NSLocalizedString("SpeakSettingsViewController_PitchTitle", comment: "高さ")
        }.onChange({ (row) in
            if let value = row.value {
                let realm = try! RealmUtil.GetRealm()
                if let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) {
                    try! realm.write {
                        setting.pitch = value
                    }
                }
            }
        })
        <<< SliderRow("RateSliderRow-\(targetID)") {
            $0.value = currentSetting.rate
            $0.cell.slider.minimumValue = AVSpeechUtteranceMinimumSpeechRate
            $0.cell.slider.maximumValue = AVSpeechUtteranceMaximumSpeechRate
            $0.shouldHideValue = true
            $0.steps = 1001
            $0.title = NSLocalizedString("SpeakSettingsViewController_RateTitle", comment: "速度")
        }.onChange({ (row) in
            guard let rate = row.value else{
                return
            }
            let realm = try! RealmUtil.GetRealm()
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
                    if let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) {
                        try! realm.write {
                            setting.rate = rate
                        }
                    }
                }
            }else{
                if let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) {
                    try! realm.write {
                        setting.rate = rate
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
        }.onChange({ (row) in
            guard let locale = row.value else {
                return
            }
            let realm = try! RealmUtil.GetRealm()
            guard let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) else {
                return
            }
            var voiceNames:[String] = []
            var voiceName = ""
            try! realm.write {
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
        }.onChange({ (row) in
            guard let voiceName = row.value else {
                return
            }
            guard let voice = AVSpeechSynthesisVoice.speechVoices().filter({$0.name == voiceName}).first else {
                return
            }
            let realm = try! RealmUtil.GetRealm()
            guard let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) else {
                return
            }
            try! realm.write {
                setting.voiceIdentifier = voice.identifier
            }
        })
        <<< ButtonRow("TestSpeechButtonRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_TestSpeechButtonTitle", comment: "発音テスト")
        }.onCellSelection({ (buttonCellOf, button) in
            let realm = try! RealmUtil.GetRealm()
            guard let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) else {
                return
            }
            self.testSpeech(pitch: setting.pitch, rate: setting.rate, identifier: setting.voiceIdentifier, text: self.testText)
        })
        if !isDefaultSpeakerSetting {
            section <<< ButtonRow("RemoveButtonRow-\(targetID)") {
                $0.title = NSLocalizedString("SpeakerSettingsViewController_RemoveButtonRow", comment: "この話者の設定を削除")
            }.onCellSelection({ (buttonCellOf, button) in
                var settingName = ""
                let realm = try! RealmUtil.GetRealm()
                if let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) {
                    settingName = setting.name
                }
                NiftyUtilitySwift.EasyDialogTwoButton(
                viewController: self,
                title: settingName,
                message: NSLocalizedString("SpeakSettingsViewController_ConifirmRemoveTitle", comment: "この設定を削除しますか？"),
                button1Title: NSLocalizedString("Cancel_button", comment: "Cancel"),
                button1Action: nil,
                button2Title: NSLocalizedString("OK_button", comment: "OK"),
                button2Action: {
                    guard let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) else {
                        return
                    }
                    try! realm.write {
                        RealmUtil.Delete(realm: realm, model: setting)
                    }
                    if let index = self.form.index(of: section) {
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
            let newSpeakerSetting = RealmSpeakerSetting()
            let realm = try! RealmUtil.GetRealm()
            try! realm.write {
                realm.add(newSpeakerSetting)
            }
            self.form.append(self.createSpeakSettingRows(currentSetting: newSpeakerSetting))
            NiftyUtilitySwift.EasyDialogOneButton(
                viewController: self,
                title: NSLocalizedString("SpeakSettingsViewController_SpeakerSettingAdded", comment: "末尾に話者設定を追加しました。\n(恐らくはスクロールする必要があります)"),
                message: nil,
                buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                buttonAction:nil)
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
        
        let realm = try! RealmUtil.GetRealm()
        let globalState = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID)
        if let defaultSpeaker = globalState?.defaultSpeaker {
            sections = sections +++ createSpeakSettingRows(currentSetting: defaultSpeaker)
            for speakerSetting in realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND id != %@", defaultSpeaker.id) {
                sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
            }
        }else{
            for speakerSetting in realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false") {
                sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
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
