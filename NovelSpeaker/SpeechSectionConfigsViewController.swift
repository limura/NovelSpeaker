//
//  SpeechSectionConfigsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/14.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class SpeechSectionConfigsViewController: FormViewController, MultipleNovelIDSelectorDelegate, RealmObserverResetDelegate {
    let speaker = SpeechBlockSpeaker()
    var testText = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
    var hideCache:[String:Bool] = [:]
    public var targetNovelID = RealmSpeechSectionConfig.anyTarget
    var targetNovelIDSetMap:[String:Set<String>] = [String:Set<String>]()
    var sectionConfigObserverToken : NotificationToken? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        if self.targetNovelID == RealmSpeechSectionConfig.anyTarget {
            self.title = NSLocalizedString("SpeechSectionConfigsViewController_Title", comment: "話者変更設定")
        }else{
            self.title = NSLocalizedString("SpeechSectionConfigsViewController_TitleOnlyThisNovel", comment: "話者変更設定(小説専用設定)")
        }
        createCells()
        observeSectionConfig()
        registNotificationCenter()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }

    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    func StopObservers() {
        sectionConfigObserverToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeSectionConfig()
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

    func observeSectionConfig() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let sectionConfigList = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) else { return }
            self.sectionConfigObserverToken = sectionConfigList.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .initial(_):
                    break
                case .update(_, _, _, _):
                    DispatchQueue.main.async {
                        self.form.removeAll()
                        self.createCells()
                    }
                case .error(_):
                    break
                }
            })
        }
    }

    func testSpeech(text: String, speakerSetting:RealmSpeakerSetting) {
        speaker.StopSpeech()
        let defaultSpeaker = SpeakerSetting(from: speakerSetting)
        speaker.SetText(content: text, withMoreSplitTargets: [], moreSplitMinimumLetterCount: Int.max, defaultSpeaker: defaultSpeaker, sectionConfigList: [], waitConfigList: [], sortedSpeechModArray: [])
        speaker.StartSpeech()
    }
    func updateTitleCell(realm:Realm, speechSectionConfig:RealmSpeechSectionConfig) {
        let name = speechSectionConfig.name
        let startText = speechSectionConfig.startText
        let endText = speechSectionConfig.endText
        let speakerName = speechSectionConfig.speakerWith(realm: realm)?.name
        DispatchQueue.main.async {
            guard let row = self.form.rowBy(tag: "TitleLabelRow-\(name)") as? LabelRow else {
                return
            }
            row.title = "\(name): \(startText) …… \(endText)"
            if let speakerName = speakerName {
                row.value = speakerName
            }
            row.updateCell()
        }
    }
    
    func createSpeechSectionConfigCells(realm: Realm, speechSectionConfig:RealmSpeechSectionConfig) -> Section {
        let name = speechSectionConfig.name
        var speakerName = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerUnknown", comment: "不明")
        if let speaker = speechSectionConfig.speakerWith(realm: realm) {
            speakerName = speaker.name
        }
        self.targetNovelIDSetMap[name] = Set<String>()
        for novelID in speechSectionConfig.targetNovelIDArray {
            self.targetNovelIDSetMap[name]?.insert(novelID)
        }

        let section = Section()
        section.tag = name
        section <<< LabelRow("TitleLabelRow-\(name)") {
            $0.title = "\(name): \(speechSectionConfig.startText) …… \(speechSectionConfig.endText)"
            $0.value = speakerName
        }.onCellSelection({ (_, _) in
            if let isHide = self.hideCache[name] {
                self.hideCache[name] = !isHide
            }else{
                self.hideCache[name] = false
            }
            for tag in [
                "StartTextRow-\(name)",
                "EndTextRow-\(name)",
                "SpeakerAlertRow-\(name)",
                "TargetNovelIDLabelRow-\(name)",
                "SpeechTestButtonRow-\(name)",
                "RemoveButtonRow-\(name)"
                ] {
                guard let row = self.form.rowBy(tag: tag) else {
                    return
                }
                row.evaluateHidden()
                row.updateCell()
            }
        })
        <<< TextRow("StartTextRow-\(name)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_BeforeTextTitle", comment: "開始文字")
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.hidden = Condition.function(["TitleLabelRow-\(name)"], { (form) -> Bool in
                return self.hideCache[name] ?? true
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
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let speechSectionConfig = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name) else {
                    return
                }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken]) { (realm) in
                    speechSectionConfig.startText = text
                }
                self.updateTitleCell(realm: realm, speechSectionConfig: speechSectionConfig)
            }
        }).cellUpdate({ (textCell, textRow) in
            if !textRow.isValid {
                textCell.titleLabel?.textColor = .red
            }
            textCell.textField.clearButtonMode = .always
        })
        <<< TextRow("EndTextRow-\(name)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_AfterTextTitle", comment: "終了文字")
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.hidden = Condition.function(["TitleLabelRow-\(name)"], { (form) -> Bool in
                return self.hideCache[name] ?? true
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
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let speechSectionConfig = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name) else {
                    return
                }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken]) { (realm) in
                    speechSectionConfig.endText = text
                }
                self.updateTitleCell(realm: realm, speechSectionConfig: speechSectionConfig)
            }
        }).cellUpdate({ (textCell, textRow) in
            if !textRow.isValid {
                textCell.titleLabel?.textColor = .red
            }
            textCell.textField.clearButtonMode = .always
        })
        <<< AlertRow<String>("SpeakerAlertRow-\(name)") { (row) -> Void in
            row.title = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerAlertRowTitle", comment: "話者")
            row.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            row.hidden = Condition.function(["TitleLabelRow-\(name)"], { (form) -> Bool in
                return self.hideCache[name] ?? true
            })
            row.selectorTitle = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerSelectorTitle", comment: "話者を選択してください")
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let speakerSettingArray = RealmSpeakerSetting.GetAllObjectsWith(realm: realm)?.sorted(byKeyPath: "createdDate", ascending: true) else { return }
                row.options = speakerSettingArray.map({$0.name})
            }
            row.value = speechSectionConfig.speakerWith(realm: realm)?.name ?? NSLocalizedString("SpeechSectionConfigsViewController_SpeakerUnknown", comment: "不明")
        }.onChange({ (row) in
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let targetName = row.value, let sectionConfig = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name), let speaker = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetName) else {
                    return
                }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken]) { (realm) in
                    sectionConfig.speakerID = speaker.name
                }
                self.updateTitleCell(realm: realm, speechSectionConfig: sectionConfig)
            }
        })
        <<< LabelRow("TargetNovelIDLabelRow-\(name)") {
            $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_TargetNovelIDLabelTitle", comment: "適用対象")
            if let idSet = self.targetNovelIDSetMap[name] {
                $0.value = self.SelectedNovelIDSetToNovelNameString(selectedNovelIDSet: idSet)
            }else{
                $0.value = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerUnknown", comment: "不明")
            }
            $0.cell.accessoryType = .disclosureIndicator
            $0.cell.editingAccessoryType = .disclosureIndicator
            $0.hidden = Condition.function(["TitleLabelRow-\(name)"], { (form) -> Bool in
                return self.hideCache[name] ?? true
            })
        }.onCellSelection({ (cellOf, row) in
            guard let idSet = self.targetNovelIDSetMap[name] else { return }
            let nextViewController = MultipleNovelIDSelectorViewController()
            nextViewController.delegate = self
            nextViewController.SelectedNovelIDSet = idSet
            nextViewController.Hint = name
            nextViewController.IsUseAnyNovelID = true // self.targetNovelID == RealmSpeechSectionConfig.anyTarget
            self.navigationController?.pushViewController(nextViewController, animated: true)
        })
        <<< ButtonRow("SpeechTestButtonRow-\(name)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_TestSpeechButtonTitle", comment: "発音テスト")
            $0.hidden = Condition.function(["TitleLabelRow-\(name)"], { (form) -> Bool in
                return self.hideCache[name] ?? true
            })
        }.onCellSelection({ (buttonCellOf, button) in
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let speaker = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name)?.speakerWith(realm: realm) else {
                    return
                }
                self.testSpeech(text: self.testText, speakerSetting: speaker)
            }
        })
        <<< ButtonRow("RemoveButtonRow-\(name)") {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_RemoveButtonRow", comment: "この設定を削除")
            $0.hidden = Condition.function(["TitleLabelRow-\(name)"], { (form) -> Bool in
                return self.hideCache[name] ?? true
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
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let setting = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name) else {
                            return
                        }
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken]) { (realm) in
                            setting.delete(realm: realm)
                        }
                    }
                    if let index = self.form.firstIndex(of: section) {
                        print("remove section index: \(index)")
                        self.form.remove(at: index)
                    }else{
                        print("can not remove section because index is nil")
                    }
                    self.hideCache.removeValue(forKey: name)
            })
        })
        return section
    }
    
    func createCells() {
        let section = Section()
        <<< TextAreaRow() {
            $0.value = NSLocalizedString("SpeechSectionConfigsViewController_Usage", comment: "会話文などで声質や話者を変更するための設定です。\nそれぞれの設定をタップすると詳細が設定できます。開始文字と終了文字の間に挟まれた部分を読み上げる話者を選択します。必要のない設定は削除することもできます。")
            $0.textAreaMode = .readOnly
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SpeechSectionConfigsViewController_AddNewSettingButtonTitle", comment: "新しい話者変更設定を追加する")
        }.onCellSelection({ (_, button) in
            DispatchQueue.main.async {
                NiftyUtilitySwift.EasyDialogTextInput2Button(
                    viewController: self,
                    title: NSLocalizedString("SpeechSectionConfigsViewController_AddNewSettingDialogTitle", comment: "話者設定の名前を指定してください"),
                    message: nil,
                    textFieldText: "",
                    placeHolder: NSLocalizedString("SpeechSectionConfigsViewController_AddNewSettingDialogPlaceHolder", comment: "空文字列は指定できません"),
                    leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
                    rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
                    leftButtonAction: nil,
                    rightButtonAction: { (name) in
                        if name.count <= 0 {
                            DispatchQueue.main.async {
                                NiftyUtilitySwift.EasyDialogOneButton(
                                    viewController: self,
                                    title: NSLocalizedString("SpeechSectionConfigsViewController_AddNewSettingDialogPlaceHolder", comment: "空文字列は指定できません"),
                                    message: nil,
                                    buttonTitle: nil,
                                    buttonAction: nil)
                            }
                            return
                        }
                        RealmUtil.RealmBlock { (realm) -> Void in
                            let newSpeechSectionConfig:RealmSpeechSectionConfig
                            if let config = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name) {
                                newSpeechSectionConfig = config
                            }else{
                                newSpeechSectionConfig = RealmSpeechSectionConfig()
                                newSpeechSectionConfig.name = name
                                if let defaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) {
                                    newSpeechSectionConfig.speakerID = defaultSpeaker.name
                                }
                            }
                            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken]) { (realm) in
                                realm.add(newSpeechSectionConfig, update: .modified)
                            }
                            newSpeechSectionConfig.AddTargetNovelIDWith(realm: realm, novelID: self.targetNovelID)
                            self.form.append(self.createSpeechSectionConfigCells(realm: realm, speechSectionConfig: newSpeechSectionConfig))
                        }
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogOneButton(
                                viewController: self,
                                title: NSLocalizedString("SpeechSectionConfigsViewController_SpeakerSettingAdded", comment: "末尾に話者変更設定を追加しました。\n(恐らくはスクロールする必要があります)"),
                                message: nil,
                                buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                                buttonAction:nil)
                        }
                    },
                    shouldReturnIsRightButtonClicked: true)
            }
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

        RealmUtil.RealmBlock { (realm) -> Void in
            if let speechSectionConfigArray = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm)?.sorted(byKeyPath: "createdDate").filter({ (setting) -> Bool in
                if self.targetNovelID == RealmSpeechSectionConfig.anyTarget { return true }
                return setting.targetNovelIDArray.contains(self.targetNovelID)
            }) {
                for speechSectionConfig in speechSectionConfigArray {
                    form.append(self.createSpeechSectionConfigCells(realm: realm, speechSectionConfig: speechSectionConfig))
                }
            }
        }
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
        let name = hint
        DispatchQueue.main.async {
            guard let row = self.form.rowBy(tag: "TargetNovelIDLabelRow-\(name)") as? LabelRow else { return }
            if selectedNovelIDSet.count <= 0 {
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogTwoButton(
                        viewController: self,
                        title: nil,
                        message: NSLocalizedString("SpeechSectionConfigsViewController_ConifirmDeleteSettingBecauseNoTargetNovelID", comment: "適用対象の小説が何もない状態になっています。\nこの話者変更設定を削除してもよろしいですか？"),
                        button1Title: nil,
                        button1Action: nil,
                        button2Title: nil,
                        button2Action: {
                            RealmUtil.RealmBlock { (realm) -> Void in
                                guard let setting = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name) else {
                                    return
                                }
                                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken]) { (realm) in
                                    setting.delete(realm: realm)
                                }
                            }
                            if let section = self.form.sectionBy(tag: name), let index = self.form.firstIndex(of: section) {
                                print("remove section index: \(index)")
                                self.form.remove(at: index)
                            }else{
                                print("can not remove section because index is nil")
                            }
                            self.hideCache.removeValue(forKey: name)
                    })
                }
                return
            }
            self.targetNovelIDSetMap[name] = selectedNovelIDSet
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let sectionConfig = RealmSpeechSectionConfig.SearchFromWith(realm: realm, name: name) else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.sectionConfigObserverToken], block: { (realm) in
                    sectionConfig.targetNovelIDArray.removeAll()
                    for novelID in selectedNovelIDSet {
                        sectionConfig.targetNovelIDArray.append(novelID)
                    }
                })
            }
            row.value = self.SelectedNovelIDSetToNovelNameString(selectedNovelIDSet: selectedNovelIDSet)
            row.updateCell()
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
