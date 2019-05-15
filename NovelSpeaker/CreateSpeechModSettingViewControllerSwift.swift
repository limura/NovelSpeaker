//
//  CreateSpeechModSettingViewControllerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/15.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class CreateSpeechModSettingViewControllerSwift: FormViewController {
    public var targetSpeechModSettingID:String? = nil
    var currentSetting = RealmSpeechModSetting()
    var beforeTestText = ""
    var afterTestText = ""
    var beforeText = ""
    var afterText = ""
    var isUseRegexp = false
    let speaker = NiftySpeaker()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_Title", comment: "読みの修正詳細")
        
        createCells()
    }
    
    func validateBeforeString(text:String, isUseRegexp: Bool) -> Bool {
        if isUseRegexp {
            if ((try? NSRegularExpression(pattern: text, options: [])) != nil) {
                return true
            }
            return false
        }
        if text.count <= 0 {
            return false
        }
        return true
    }
    
    func validateAfterString(text:String) -> Bool {
        if text.count <= 0 {
            return false
        }
        return true
    }
    
    func createCells() {
        let realm = try! RealmUtil.GetRealm()
        if let targetID = targetSpeechModSettingID {
            if let targetSetting = realm.object(ofType: RealmSpeechModSetting.self, forPrimaryKey: targetID) {
                self.currentSetting = targetSetting
            }
        }
        self.beforeText = currentSetting.before
        self.afterText = currentSetting.after
        self.isUseRegexp = currentSetting.isUseRegularExpression
        self.form +++ Section()
        <<< TextRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_BeforeTitle", comment: "読み替え前")
            $0.value = currentSetting.before
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.cell.textField.clearButtonMode = .always
            $0.cell.textField.borderStyle = .roundedRect
        }.onChange({ (textRow) in
            guard let value = textRow.value else {
                return
            }
            if value.count < 0 || !textRow.isValid {
                return
            }
            self.beforeText = value
            if !self.isUseRegexp, let row = self.form.rowBy(tag: "BeforeTestTextRow") as? TextRow {
                row.value = value
                self.beforeTestText = value
                row.updateCell()
            }
        }).cellUpdate({ (cell, row) in
            if !row.isValid {
                cell.titleLabel?.textColor = .red
                // detailTextLabel だと書いている正規表現文字と被って表示されてしまうため、外します。
                // cell.detailTextLabel?.text = row.validationErrors.first?.msg
            }
        })
        <<< TextRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AfterTitle", comment: "読み替え後")
            $0.value = currentSetting.after
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.cell.textField.clearButtonMode = .always
            $0.cell.textField.borderStyle = .roundedRect
        }.onChange({ (textRow) in
            guard let value = textRow.value else {
                return
            }
            if value.count < 0 || !textRow.isValid {
                return
            }
            self.afterText = value
        }).cellUpdate({ (cell, row) in
            if !row.isValid {
                cell.titleLabel?.textColor = .red
            }
        })
        <<< SwitchRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_RegularExpressionTitle", comment: "正規表現マッチ")
            $0.value = currentSetting.isUseRegularExpression
        }.onChange({ (row) in
            guard let value = row.value else {
                return
            }
            self.isUseRegexp = value
        })
        <<< TextRow("BeforeTestTextRow") {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_BeforeSampleTitle", comment: "読み替え前")
            if currentSetting.isUseRegularExpression {
                $0.value = "メロスは激怒した"
            }else{
                $0.value = currentSetting.before
            }
            beforeTestText = $0.value ?? "メロスは激怒した"
            $0.cell.textField.clearButtonMode = .always
            $0.cell.textField.borderStyle = .roundedRect
        }.onChange({ (textRow) in
            guard let value = textRow.value else {
                return
            }
            if value.count < 0 {
                return
            }
            self.beforeTestText = value
        })
        <<< TextRow("AfterTestTextRow") {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AfterSampleTitle", comment: "読み替え後")
            $0.value = ""
            $0.cell.textField.isUserInteractionEnabled = false
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_TestButtonTitle", comment: "発音テスト")
        }.onCellSelection({ (_, _) in
            self.runTest()
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_ApplyButtonTitle", comment: "保存する")
        }.onCellSelection({ (_, _) in
            if !self.validateDataAndAlert(before: self.beforeText, after: self.afterText, isUseRegexp: self.isUseRegexp) {
                return
            }
            let realm = try! RealmUtil.GetRealm()
            try! realm.write {
                self.currentSetting.before = self.beforeText
                self.currentSetting.after = self.afterText
                self.currentSetting.isUseRegularExpression = self.isUseRegexp
                realm.add(self.currentSetting, update: true)
            }
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
        })
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    func validateDataAndAlert(before:String, after:String, isUseRegexp:Bool) -> Bool {
        if !validateBeforeString(text: before, isUseRegexp: isUseRegexp) {
            DispatchQueue.main.async {
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: self,
                    title: NSLocalizedString("CreateSpeechModSettingViewControllerSwift_ValidateBeforeFailedTitle", comment: "読み替え前の文字列に問題があります"),
                    message: NSLocalizedString("CreateSpeechModSettingViewControllerSwift_ValidateBeforeFieldMessage", comment: "空文字列であるか、正規表現に不備があるようです。"),
                    buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                    buttonAction: nil)
            }
            return false
        }
        if !validateAfterString(text: after) {
            DispatchQueue.main.async {
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: self,
                    title: NSLocalizedString("CreateSpeechModSettingViewControllerSwift_ValidateAfterFailedTitle", comment: "読み替え後の文字列に問題があります"),
                    message: NSLocalizedString("CreateSpeechModSettingViewControllerSwift_ValidateAfterFieldMessage", comment: "空文字列は設定できません。\n読み替え後に発話させないようにするには空白に読み替えさせる必要があります。"),
                    buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                    buttonAction: nil)
            }
            return false
        }
        return true
    }

    func runTest() {
        let before = self.beforeText
        let after = self.afterText
        let isUseRegexp = self.isUseRegexp
        let testText = self.beforeTestText
        if !validateDataAndAlert(before: before, after: after, isUseRegexp: isUseRegexp) {
            return
        }

        speaker.stopSpeech()
        speaker.clearSpeakSettings()
        if let speechConfig = try? RealmUtil.GetRealm().object(ofType: RealmGlobalState.self,   forPrimaryKey: RealmGlobalState.UniqueID)?.defaultSpeaker?.speechConfig {
            speaker.setDefaultSpeechConfig(speechConfig)
        }
        if isUseRegexp {
            if let modArray = StringSubstituter.findRegexpSpeechModConfigs(testText, pattern: before, to: after) {
                for mod in modArray {
                    if let mod = mod as? SpeechModSettingCacheData {
                        speaker.addSpeechModText(mod.beforeString, to: mod.afterString)
                    }
                }
            }
        }else{
            speaker.addSpeechModText(before, to: after)
        }
        speaker.setText(testText)
        if let displayText = speaker.getSpeechText(), let row = self.form.rowBy(tag: "AfterTestTextRow") {
            if let textRow = row as? TextRow {
                textRow.value = displayText
                textRow.updateCell()
            }
        }
        speaker.startSpeech()
    }
}
