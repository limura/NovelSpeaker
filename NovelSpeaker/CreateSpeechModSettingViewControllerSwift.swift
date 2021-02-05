//
//  CreateSpeechModSettingViewControllerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/15.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class CreateSpeechModSettingViewControllerSwift: FormViewController, MultipleNovelIDSelectorDelegate {
    @objc public var targetSpeechModSettingBeforeString:String? = nil
    public var targetNovelID = ""
    public var isUseAnyNovelID = true
    var beforeTestText = ""
    var afterTestText = ""
    var beforeText = ""
    var afterText = ""
    var isUseRegexp = false
    var targetNovelIDSet:Set<String> = Set<String>()
    let speaker = SpeechBlockSpeaker()

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_Title", comment: "読みの修正詳細")
        
        createCells()
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
        var before:String = ""
        var after:String = ""
        var isUseRegularExpression:Bool = false
        self.targetNovelIDSet.removeAll()
        if self.targetNovelID.count > 0 {
            self.targetNovelIDSet.insert(self.targetNovelID)
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            if let targetID = targetSpeechModSettingBeforeString, let targetSetting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: targetID) {
                before = targetSetting.before
                after = targetSetting.after
                isUseRegularExpression = targetSetting.isUseRegularExpression
                for novelID in targetSetting.targetNovelIDArray {
                    self.targetNovelIDSet.insert(novelID)
                }
            }else{
                before = targetSpeechModSettingBeforeString ?? ""
                after = ""
                isUseRegularExpression = false
            }
        }
        self.beforeText = before
        self.afterText = after
        self.isUseRegexp = isUseRegularExpression
        self.form +++ Section()
        <<< TextRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_BeforeTitle", comment: "読み替え前")
            $0.value = self.beforeText
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnDemand
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
            cell.textField.textAlignment = .left
            cell.textField.clearButtonMode = .always
        })
        <<< TextRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AfterTitle", comment: "読み替え後")
            $0.value = self.afterText
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnDemand
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
            cell.textField.textAlignment = .left
            cell.textField.clearButtonMode = .always
        })
        <<< SwitchRow() {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_RegularExpressionTitle", comment: "正規表現マッチ")
            $0.value = self.isUseRegexp
        }.onChange({ (row) in
            guard let value = row.value else {
                return
            }
            self.isUseRegexp = value
        })
        <<< LabelRow("TargetNovelIDLabelRow") {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_TargetNovelIDLabelTitle", comment: "適用対象")
            $0.value = self.SelectedNovelIDSetToNovelNameString(selectedNovelIDSet: self.targetNovelIDSet)
            $0.cell.accessoryType = .disclosureIndicator
            $0.cell.editingAccessoryType = .disclosureIndicator
        }.onCellSelection({ (cellOf, row) in
            let nextViewController = MultipleNovelIDSelectorViewController()
            nextViewController.delegate = self
            nextViewController.SelectedNovelIDSet = self.targetNovelIDSet
            nextViewController.IsUseAnyNovelID = self.isUseAnyNovelID
            self.navigationController?.pushViewController(nextViewController, animated: true)
        })
        <<< TextRow("BeforeTestTextRow") {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_BeforeSampleTitle", comment: "読み替え前")
            if self.isUseRegexp {
                $0.value = "メロスは激怒した"
            }else{
                $0.value = self.beforeText
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
        }).cellUpdate({ (cell, row) in
            cell.textField.textAlignment = .left
            cell.textField.clearButtonMode = .always
        })
        <<< TextRow("AfterTestTextRow") {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AfterSampleTitle", comment: "読み替え後")
            $0.value = ""
            $0.cell.textField.isUserInteractionEnabled = false
            $0.cell.textField.textAlignment = .left
            $0.cell.textField.borderStyle = .roundedRect
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
            if self.targetNovelIDSet.count <= 0 {
                NiftyUtility.EasyDialogTwoButton(
                    viewController: self,
                    title: nil,
                    message: NSLocalizedString("CreateSpeechModSettingViewControllerSwift_ConifirmDeleteSettingBecauseNoTargetNovelID", comment: "適用対象の小説が何もない状態になっています。\nこの読みの修正を削除してもよろしいですか？"),
                    button1Title: nil,
                    button1Action: nil,
                    button2Title: nil,
                    button2Action: {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            if let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: self.beforeText) {
                                RealmUtil.WriteWith(realm: realm, block: { (realm) in
                                    setting.delete(realm: realm)
                                })
                            }
                        }
                        DispatchQueue.main.async {
                            self.navigationController?.popViewController(animated: true)
                        }
                })
            }
            RealmUtil.Write { (realm) in
                let setting:RealmSpeechModSetting
                if let targetBeforeString = self.targetSpeechModSettingBeforeString, let originalSetting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: targetBeforeString) {
                    if targetBeforeString != self.beforeText {
                        originalSetting.delete(realm: realm)
                        setting = RealmSpeechModSetting()
                        setting.before = self.beforeText
                    }else{
                        setting = originalSetting
                    }
                }else{
                    setting = RealmSpeechModSetting()
                    setting.before = self.beforeText
                }
                setting.after = self.afterText
                setting.isUseRegularExpression = self.isUseRegexp
                setting.targetNovelIDArray.removeAll()
                for novelID in self.targetNovelIDSet {
                    setting.targetNovelIDArray.append(novelID)
                }
                realm.add(setting, update: .modified)
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
        form.validate()
        if !validateBeforeString(text: before, isUseRegexp: isUseRegexp) {
            DispatchQueue.main.async {
                NiftyUtility.EasyDialogOneButton(
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
                NiftyUtility.EasyDialogOneButton(
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

        speaker.StopSpeech()
        let defaultSpeaker:SpeakerSetting = RealmUtil.RealmBlock { (realm) -> SpeakerSetting in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm), let realmDefaultSpeaker = globalState.defaultSpeakerWith(realm: realm) {
                return SpeakerSetting(from: realmDefaultSpeaker)
            }
            let realmDefaultSpeaker = RealmSpeakerSetting()
            return SpeakerSetting(from: realmDefaultSpeaker)
        }
        let modSettingArray = [SpeechModSetting(before: before, after: after, isUseRegularExpression: isUseRegexp)]
        speaker.SetText(content: testText, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max, defaultSpeaker: defaultSpeaker, sectionConfigList: [], waitConfigList: [], speechModArray: modSettingArray)
        let displayText = speaker.speechText
        if let row = self.form.rowBy(tag: "AfterTestTextRow") {
            if let textRow = row as? TextRow {
                textRow.value = displayText
                textRow.updateCell()
            }
        }
        speaker.StartSpeech()
    }
    
    func SelectedNovelIDSetToNovelNameString(selectedNovelIDSet: Set<String>) -> String {
        var selectedNovelNameArray:[String] = []
        if selectedNovelIDSet.contains(MultipleNovelIDSelectorViewController.AnyTypeTag) {
            selectedNovelNameArray.append(NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AnyTargetName", comment: "全ての小説"))
        }
        for novelID in selectedNovelIDSet {
            if novelID == MultipleNovelIDSelectorViewController.AnyTypeTag { continue }
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
                selectedNovelNameArray.append(novel.title)
            }
        }
        return selectedNovelNameArray.joined(separator: ", ")
    }
    
    func MultipleNovelIDSelectorSelected(selectedNovelIDSet: Set<String>, hint: String) {
        DispatchQueue.main.async {
            self.targetNovelIDSet = selectedNovelIDSet
            guard let row = self.form.rowBy(tag: "TargetNovelIDLabelRow") as? LabelRow else { return }
            if selectedNovelIDSet.count <= 0 {
                row.value = "-"
                row.updateCell()
                return
            }
            row.value = self.SelectedNovelIDSetToNovelNameString(selectedNovelIDSet: selectedNovelIDSet)
            row.updateCell()
        }
    }
}
