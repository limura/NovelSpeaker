//
//  SpeakSettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/12.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class SpeakSettingsViewController: FormViewController {
    let speaker = Speaker()
    var testText = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
    

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        BehaviorLogger.AddLog(description: "SettingsViewController viewDidLoad", data: [:])
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
        let section = Section()
        <<< TextRow("TitleRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_SpeakSettingNameTitle", comment: "名前")
            $0.value = currentSetting.name
        }.onChange({ (row) in
            if let value = row.value {
                let realm = try! RealmUtil.GetRealm()
                if let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) {
                    try! realm.write {
                        setting.name = value
                    }
                }
            }
        })
        <<< SliderRow("PitchSliderRow-\(targetID)") {
            $0.value = currentSetting.pitch
            $0.cell.slider.minimumValue = 0.5
            $0.cell.slider.maximumValue = 2.0
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
            $0.title = NSLocalizedString("SpeakSettingsViewController_RateTitle", comment: "速度")
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
        <<< AlertRow<String>("LanguageAlertRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_LangageTitle", comment: "言語")
            $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            $0.selectorTitle = NSLocalizedString("SpeakSettingsViewController_LanguageDialogTitle", comment: "言語を選択してください")
            let languageCodeArray = AVSpeechSynthesisVoice.speechVoices().map({ $0.language })
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
            try! realm.write {
                if let voiceIdentifierRow = self.form.rowBy(tag: "VoiceIdentifierAlertRow-\(targetID)") as? AlertRow<String> {
                    let voices = AVSpeechSynthesisVoice.speechVoices().filter({$0.language == locale})
                    let voiceNames = voices.map({$0.name})
                    voiceIdentifierRow.options = voiceNames
                    voiceIdentifierRow.value = voiceNames.first ?? ""
                    if let newVoice = voices.filter({$0.name == voiceIdentifierRow.value}).first {
                        setting.voiceIdentifier = newVoice.identifier
                    }
                }
                setting.locale = locale
            }
        })
        <<< AlertRow<String>("VoiceIdentifierAlertRow-\(targetID)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_VoiceIdentifierTitle", comment: "話者")
            $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            $0.selectorTitle = NSLocalizedString("SpeakSettingsViewController_VoiceIdentifierDialogTitle", comment: "話者を選択してください")
            let voiceIdentifierArray = AVSpeechSynthesisVoice.speechVoices().filter({ $0.language == currentSetting.locale }).map({$0.identifier})
            $0.options = voiceIdentifierArray
            let voice = AVSpeechSynthesisVoice(identifier: currentSetting.voiceIdentifier)
            let voiceName = voice?.name ?? ""
            if voiceIdentifierArray.contains(voiceName) {
                $0.value = voiceName
            }else{
                $0.value = voiceIdentifierArray.first ?? ""
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
        let realm = try! RealmUtil.GetRealm()
        if let defaultSettingID = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID)?.defaultSpeakerID {
            if targetID != defaultSettingID {
                section <<< ButtonRow("RemoveButtonRow-\(targetID)") {
                    $0.title = NSLocalizedString("SpeakerSettingsViewController_RemoveButtonRow", comment: "この話者の設定を削除")
                }.onCellSelection({ (buttonCellOf, button) in
                    NiftyUtilitySwift.EasyDialogTwoButton(
                    viewController: self,
                    title: NSLocalizedString("SpeakSettingsViewController_ConifirmRemoveTitle", comment: "この設定を削除しますか？"),
                    message: nil,
                    button1Title: NSLocalizedString("Cancel_button", comment: "Cancel"),
                    button1Action: nil,
                    button2Title: NSLocalizedString("OK_button", comment: "OK"),
                    button2Action: {
                        guard let setting = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: targetID) else {
                            return
                        }
                        try! realm.write {
                            setting.isDeleted = true
                        }
                        if let index = self.form.index(of: section) {
                            self.form.remove(at: index)
                        }
                    })
                })
            }
        }

        return section
    }

    func createSettingsTable(){
        var sections = form +++ Section()
        <<< TextAreaRow() {
            $0.placeholder = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
            $0.value = testText
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
            self.form +++ self.createSpeakSettingRows(currentSetting: newSpeakerSetting)
        })
        
        let realm = try! RealmUtil.GetRealm()
        let globalState = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID)
        if let defaultSpeaker = globalState?.defaultSpeaker {
            sections = sections +++ createSpeakSettingRows(currentSetting: defaultSpeaker)
            for speakerSetting in realm.objects(RealmSpeakerSetting.self).filter("id != %@", defaultSpeaker.id) {
                sections = sections +++ createSpeakSettingRows(currentSetting: speakerSetting)
            }
        }else{
            for speakerSetting in realm.objects(RealmSpeakerSetting.self) {
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
