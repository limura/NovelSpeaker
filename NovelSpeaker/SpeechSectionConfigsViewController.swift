//
//  SpeechSectionConfigsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/14.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class SpeechSectionConfigsViewController: FormViewController {
    let speaker = Speaker()
    var testText = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
    var hideCache:[String:Bool] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("SpeechSectionConfigsViewController_Title", comment: "話者変更設定")
        createCells()
    }

    func testSpeech(text: String, speakerSetting:RealmSpeakerSetting) {
        speaker.stopSpeech()
        speaker.setPitch(speakerSetting.pitch)
        speaker.setRate(speakerSetting.rate)
        speaker.setVoiceWithIdentifier(speakerSetting.voiceIdentifier)
        speaker.speech(text)
    }
    func updateTitleCell(speechSectionConfig:RealmSpeechSectionConfig) {
        guard let row = self.form.rowBy(tag: "TitleLabelRow-\(speechSectionConfig.id)") as? LabelRow else {
            return
        }
        row.title = "\(speechSectionConfig.startText) …… \(speechSectionConfig.endText)"
        if let speaker = speechSectionConfig.speaker {
            row.value = speaker.name
        }
        row.updateCell()
    }
    
    func createSpeechSectionConfigCells(speechSectionConfig:RealmSpeechSectionConfig) -> Section {
        let id = speechSectionConfig.id
        var speakerName = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerUnknown", comment: "不明")
        if let speaker = speechSectionConfig.speaker {
            speakerName = speaker.name
        }
        let section = Section()
        section <<< LabelRow("TitleLabelRow-\(id)") {
            $0.title = "\(speechSectionConfig.startText) …… \(speechSectionConfig.endText)"
            $0.value = speakerName
        }.onCellSelection({ (_, _) in
            if let isHide = self.hideCache[id] {
                self.hideCache[id] = !isHide
            }else{
                self.hideCache[id] = false
            }
            for tag in [
                "StartTextRow-\(id)",
                "EndTextRow-\(id)",
                "SpeakerAlertRow-\(id)",
                "SpeechTestButtonRow-\(id)",
                "RemoveButtonRow-\(id)"
                ] {
                guard let row = self.form.rowBy(tag: tag) else {
                    return
                }
                row.evaluateHidden()
                row.updateCell()
            }
        })
        <<< TextRow("StartTextRow-\(id)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_BeforeTextTitle", comment: "開始文字")
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.hidden = Condition.function(["TitleLabelRow-\(id)"], { (form) -> Bool in
                return self.hideCache[id] ?? true
            })
            $0.value = speechSectionConfig.startText
            $0.add(rule: RuleRequired())
            $0.cell.textField.borderStyle = .roundedRect
        }.onChange({ (row) in
            guard let text = row.value else {
                return
            }
            if text.count <= 0 {
                return
            }
            let realm = try! RealmUtil.GetRealm()
            guard let speechSectionConfig = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: id) else {
                return
            }
            try! realm.write {
                speechSectionConfig.startText = text
            }
            self.updateTitleCell(speechSectionConfig: speechSectionConfig)
        }).cellUpdate({ (textCell, textRow) in
            if !textRow.isValid {
                textCell.titleLabel?.textColor = .red
            }
            textCell.textField.clearButtonMode = .always
        })
        <<< TextRow("EndTextRow-\(id)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_AfterTextTitle", comment: "終了文字")
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.hidden = Condition.function(["TitleLabelRow-\(id)"], { (form) -> Bool in
                return self.hideCache[id] ?? true
            })
            $0.value = speechSectionConfig.endText
            $0.add(rule: RuleRequired())
            $0.cell.textField.borderStyle = .roundedRect
        }.onChange({ (row) in
            guard let text = row.value else {
                return
            }
            if text.count <= 0 {
                return
            }
            let realm = try! RealmUtil.GetRealm()
            guard let speechSectionConfig = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: id) else {
                return
            }
            try! realm.write {
                speechSectionConfig.endText = text
            }
            self.updateTitleCell(speechSectionConfig: speechSectionConfig)
        }).cellUpdate({ (textCell, textRow) in
            if !textRow.isValid {
                textCell.titleLabel?.textColor = .red
            }
            textCell.textField.clearButtonMode = .always
        })
        <<< AlertRow<String>("SpeakerAlertRow-\(id)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerAlertRowTitle", comment: "話者")
            $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            $0.hidden = Condition.function(["TitleLabelRow-\(id)"], { (form) -> Bool in
                return self.hideCache[id] ?? true
            })
            $0.selectorTitle = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerSelectorTitle", comment: "話者を選択してください")
            let realm = try! RealmUtil.GetRealm()
            let speakerSettingArray = realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false").sorted(byKeyPath: "createdDate", ascending: true)
            $0.options = speakerSettingArray.map({$0.name})
            $0.value = speechSectionConfig.speaker?.name ?? NSLocalizedString("SpeechSectionConfigsViewController_SpeakerUnknown", comment: "不明")
        }.onChange({ (row) in
            guard let name = row.value else {
                return
            }
            let realm = try! RealmUtil.GetRealm()
            guard let sectionConfig = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: id) else {
                return
            }
            try! realm.write {
                if let speaker = realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", name).first {
                    sectionConfig.speakerID = speaker.id
                }
            }
            self.updateTitleCell(speechSectionConfig: sectionConfig)
        })
        <<< ButtonRow("SpeechTestButtonRow-\(id)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_TestSpeechButtonTitle", comment: "発音テスト")
            $0.hidden = Condition.function(["TitleLabelRow-\(id)"], { (form) -> Bool in
                return self.hideCache[id] ?? true
            })
        }.onCellSelection({ (buttonCellOf, button) in
            let realm = try! RealmUtil.GetRealm()
            guard let speaker = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: id)?.speaker else {
                return
            }
            self.testSpeech(text: self.testText, speakerSetting: speaker)
        })
        <<< ButtonRow("RemoveButtonRow-\(id)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_RemoveButtonRow", comment: "この設定を削除")
            $0.hidden = Condition.function(["TitleLabelRow-\(id)"], { (form) -> Bool in
                return self.hideCache[id] ?? true
            })
        }.onCellSelection({ (buttonCellOf, button) in
            NiftyUtilitySwift.EasyDialogTwoButton(
                viewController: self,
                title: NSLocalizedString("SpeakSettingsViewController_ConifirmRemoveTitle", comment: "この設定を削除しますか？"),
                message: nil,
                button1Title: NSLocalizedString("Cancel_button", comment: "Cancel"),
                button1Action: nil,
                button2Title: NSLocalizedString("OK_button", comment: "OK"),
                button2Action: {
                    let realm = try! RealmUtil.GetRealm()
                    guard let setting = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: id) else {
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
                    self.hideCache.removeValue(forKey: id)
            })
        })
        return section
    }
    
    func createCells() {
        let realm = try! RealmUtil.GetRealm()
        let speechSectionConfigArray = RealmSpeechSectionConfig.GetAllObjects(realm: realm)?.sorted(byKeyPath: "createdDate")
        let section = Section()
        <<< TextAreaRow() {
            $0.value = NSLocalizedString("SpeechSectionConfigsViewController_Usage", comment: "会話文などで声質や話者を変更するための設定です。\nそれぞれの設定をタップすると詳細が設定できます。開始文字と終了文字の間に挟まれた部分を読み上げる話者を選択します。必要のない設定は削除することもできます。")
            $0.textAreaMode = .readOnly
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_AddNewSettingButtonTitle", comment: "新しい話者変更設定を追加する")
        }.onCellSelection({ (_, button) in
            let newSpeechSectionConfig = RealmSpeechSectionConfig()
            let realm = try! RealmUtil.GetRealm()
            if let defaultSpeaker = RealmGlobalState.GetInstance(realm: realm)?.defaultSpeaker {
                newSpeechSectionConfig.speakerID = defaultSpeaker.name
            }
            try! realm.write {
                realm.add(newSpeechSectionConfig)
            }
            self.form.append(self.createSpeechSectionConfigCells(speechSectionConfig: newSpeechSectionConfig))
            NiftyUtilitySwift.EasyDialogOneButton(
                viewController: self,
                title: NSLocalizedString("SpeechSectionConfigsViewController_SpeakerSettingAdded", comment: "末尾に話者変更設定を追加しました。\n(恐らくはスクロールする必要があります)"),
                message: nil,
                buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                buttonAction:nil)
        })
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
        form +++ section

        if let speechSectionConfigArray = speechSectionConfigArray {
            for speechSectionConfig in speechSectionConfigArray {
                form.append(self.createSpeechSectionConfigCells(speechSectionConfig: speechSectionConfig))
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
