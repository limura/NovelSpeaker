//
//  SpeechWaitSettingViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/14.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class SpeechWaitSettingViewControllerSwift: FormViewController {
    final let TestTextAreaTag = "TestTextAreaTag"
    var testText:String = NSLocalizedString("SpeakSettingsTableViewController_ReadTheSentenceForTest", comment: "ここに書いた文をテストで読み上げます。")
    let speaker = NiftySpeaker()
    var hideCache:[String:Bool] = [:]

    func testSpeech(text: String, delaySetting:RealmSpeechWaitConfig) {
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else {
                print("can not get globalState")
                return
            }
            guard let speakerSetting = globalState.defaultSpeaker else {
                print("can not get defaultSpeakerSetting")
                return
            }
            
            speaker.stopSpeech()
            speaker.clearSpeakSettings()
            speaker.setDefaultSpeechConfig(speakerSetting.speechConfig)
            delaySetting.ApplyDelaySettingTo(niftySpeaker: speaker)
            speaker.setText(text)
            speaker.updateCurrentReadingPoint(NSRange(location: 0, length: 0))
            speaker.startSpeech()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("SettingTableViewController_SettingOfTheSpeechDelay", comment:"読み上げ時の間の設定")
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
    
    func updateTestText(targetString:String) {
        let newTargetText = targetString.replacingOccurrences(of: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"), with: "\n")
        guard let testTextAreaRow = self.form.rowBy(tag: self.TestTextAreaTag) else {
            return
        }
        guard let testTextArea = testTextAreaRow as? TextAreaRow else {
            return
        }
        testTextArea.value = "\(NSLocalizedString("SpeechWaitSettingViewController_TestText1", comment: "ここに書いた文を"))\(newTargetText)\(NSLocalizedString("SpeechWaitSettingViewController_TestText2", comment:"テストで読み上げます"))"
        testTextArea.updateCell()
    }

    func updateTitleCell(speechWaitConfig:RealmSpeechWaitConfig) {
        guard let row = self.form.rowBy(tag: "TitleLabelRow-\(speechWaitConfig.targetText)") as? LabelRow else {
            return
        }
        row.title = speechWaitConfig.targetText.replacingOccurrences(of: "\n", with: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"))
        row.value = "\(speechWaitConfig.delayTimeInSec)"
        row.updateCell()
    }
    
    func createSpeechWaitCells(speechWaitSetting:RealmSpeechWaitConfig) -> Section {
        let targetText = speechWaitSetting.targetText
        let section = Section()
        return section
        <<< LabelRow("TitleLabelRow-\(targetText)") {
            $0.title = speechWaitSetting.targetText.replacingOccurrences(of: "\n", with: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"))
            $0.value = "\(speechWaitSetting.delayTimeInSec)"
        }.onCellSelection({ (_, _) in
            if let isHide = self.hideCache[targetText] {
                self.hideCache[targetText] = !isHide
            }else{
                self.hideCache[targetText] = false
            }
            if self.hideCache[targetText] == false {
                autoreleasepool {
                    if let setting = RealmSpeechWaitConfig.SearchFrom(targetText: targetText) {
                        self.updateTestText(targetString: setting.targetText)
                    }
                }
            }
            for tag in [
                //"SpeechWaitSettingTextRow-\(targetText)",
                "DelayTimeSliderRow-\(targetText)",
                "SpeechTestButtonRow-\(targetText)",
                "RemoveButtonRow-\(targetText)"
                ] {
                guard let row = self.form.rowBy(tag: tag) else {
                    return
                }
                row.evaluateHidden()
                row.updateCell()
            }
        })
            /* primary key になったので作成後には書き換えをできなくします。
        <<< TextRow("SpeechWaitSettingTextRow-\(targetText)") {
            $0.title = NSLocalizedString("SpeechWaitSettingViewController_TargetStringTitle", comment: "対象文字列")
            $0.value = speechWaitSetting.targetText.replacingOccurrences(of: "\n", with: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"))
            $0.add(rule: RuleRequired())
            $0.validationOptions = .validatesOnChange
            $0.cell.textField.borderStyle = .roundedRect
            $0.hidden = Condition.function(["TitleLabelRow-\(targetText)"], { (form) -> Bool in
                return self.hideCache[targetText] ?? true
            })
        }.onChange({ (row) in
            guard let text = row.value, let waitSetting = RealmSpeechWaitConfig.SearchFrom(targetText: targetText) else {
                return
            }
            let newTargetText = text.replacingOccurrences(of: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"), with: "\n")
            RealmUtil.Write { (realm) in
                waitSetting.targetText = newTargetText
            }
            self.updateTestText(targetString: newTargetText)
            self.updateTitleCell(speechWaitConfig: waitSetting)
        }).onCellSelection({ (_, row) in
            guard let text = row.value else {
                return
            }
             self.updateTestText(targetString: text)
        }).cellUpdate({ (textCell, textRow) in
            if !textRow.isValid {
                textCell.titleLabel?.textColor = .red
            }
            textCell.textField.clearButtonMode = .always
        })
            */
        <<< StepperRow("DelayTimeSliderRow-\(targetText)") {
            $0.value = Double(speechWaitSetting.delayTimeInSec)
            $0.cell.stepper.minimumValue = 0.0
            $0.cell.stepper.maximumValue = 5.0
            $0.cell.stepper.stepValue = 0.1
            $0.title = NSLocalizedString("SpeechWaitSettingViewController_DelayTimeTitle", comment: "間の時間")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetText)"], { (form) -> Bool in
                return self.hideCache[targetText] ?? true
            })
        }.onChange({ (row) in
            autoreleasepool {
                guard let value = row.value, let setting = RealmSpeechWaitConfig.SearchFrom(targetText: targetText) else {
                    return
                }
                RealmUtil.Write { (realm) in
                    setting.delayTimeInSec = Float(value)
                }
                self.updateTestText(targetString: setting.targetText)
                self.updateTitleCell(speechWaitConfig: setting)
            }
        })
        <<< ButtonRow("SpeechTestButtonRow-\(targetText)") {
            $0.title = NSLocalizedString("SpeakSettingsViewController_TestSpeechButtonTitle", comment: "発音テスト")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetText)"], { (form) -> Bool in
                return self.hideCache[targetText] ?? true
            })
        }.onCellSelection({ (buttonCellOf, button) in
            autoreleasepool {
                guard let setting = RealmSpeechWaitConfig.SearchFrom(targetText: targetText) else {
                    return
                }
                self.testSpeech(text: self.testText, delaySetting: setting)
            }
        })
        <<< ButtonRow("RemoveButtonRow-\(targetText)") {
            $0.title = NSLocalizedString("SpeechWaitSettingViewController_RemoveButtonRow", comment: "この間の設定を削除")
            $0.hidden = Condition.function(["TitleLabelRow-\(targetText)"], { (form) -> Bool in
                return self.hideCache[targetText] ?? true
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
                    autoreleasepool {
                        guard let setting = RealmSpeechWaitConfig.SearchFrom(targetText: targetText) else {
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
    
    func createCells() {
        var isSpeechWaitSettingUseExperimentalWait = false
        autoreleasepool {
            if let globalData = RealmGlobalState.GetInstance() {
                isSpeechWaitSettingUseExperimentalWait = globalData.isSpeechWaitSettingUseExperimentalWait
            }
        }
        form +++ Section()
        <<< TextAreaRow() {
            $0.value = NSLocalizedString("SpeechWaitSettingViewController_Usage", comment: "句読点や空白行を読み上げる時の間を設定します。\n「読み上げ時の間の仕組み」を非推奨型にするとより短い間の設定もできるようになりますが、将来的に動かなくなる可能性があります。改行については「<改行>」という文字列があるとそれを改行として認識するようになっています。")
            $0.textAreaMode = .readOnly
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SpeechWaitSettingViewController_AddNewSettingButtonTitle", comment: "新しく間の設定を追加する")
        }.onCellSelection({ (_, button) in
            DispatchQueue.main.async {
                NiftyUtilitySwift.EasyDialogTextInput2Button(
                    viewController: self,
                    title: NSLocalizedString("SpeechWaitSettingViewController_CreateNewSettingTitle", comment: "間の設定対象となる文字列を指定してください"),
                    message: nil,
                    textFieldText: "",
                    placeHolder: NSLocalizedString("SpeechWaitSettingViewController_CreateNewSettingPlaceholder", comment: "改行を含めたい場合は「<改行>」と入力してください。"),
                    leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
                    rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
                    leftButtonAction: nil,
                    rightButtonAction: { (text) in
                        if autoreleasepool(invoking: { () -> Bool in
                            if RealmSpeechWaitConfig.SearchFrom(targetText: text) != nil {
                                DispatchQueue.main.async {
                                    NiftyUtilitySwift.EasyDialogOneButton(viewController: self, title: NSLocalizedString("SpeechWaitSettingViewController_IsAlreadyDefined", comment: "既に定義されている文字列が指定されました。"), message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                                return true
                            }
                            return false
                        }) {
                            return
                        }
                        autoreleasepool {
                            let newSpeechWaitConfig = RealmSpeechWaitConfig()
                            newSpeechWaitConfig.targetText = text
                            RealmUtil.Write { (realm) in
                                realm.add(newSpeechWaitConfig, update: .modified)
                            }
                            self.form.append(self.createSpeechWaitCells(speechWaitSetting: newSpeechWaitConfig))
                        }
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogOneButton(
                                viewController: self,
                                title: NSLocalizedString("SpeechWaitSettingViewController_SpeakerSettingAdded", comment: "末尾に間の設定を追加しました。\n(恐らくはスクロールする必要があります)"),
                                message: nil,
                                buttonTitle: nil,
                                buttonAction:nil)
                        }
                    },
                    shouldReturnIsRightButtonClicked: true)
            }
        })
        <<< AlertRow<String>("SpeechWaitTypeAlertRow") {
            $0.title = NSLocalizedString("SpeechWaitSettingViewController_SpeechWaitType", comment: "読み上げ時の間の仕組み")
            $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
            $0.selectorTitle = NSLocalizedString("SpeechWaitSettingViewController_SpeechWaitTypeSelectorTitle", comment: "読み上げ時の間の仕組みを選択してください。\n\n非推奨型にするとより細かい時間単位での制御ができるようになりますが、iOSのアップデート等で利用できなくなる可能性があるため、非推奨となります。")
            $0.value = isSpeechWaitSettingUseExperimentalWait ? NSLocalizedString("SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Experimental", comment: "非推奨型") : NSLocalizedString("SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Default", comment: "標準型")
            $0.options = [NSLocalizedString("SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Default", comment: "標準型"), NSLocalizedString("SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Experimental", comment: "非推奨型")]
        }.onChange({ (row) in
            autoreleasepool {
                guard let value = row.value, let globalData = RealmGlobalState.GetInstance() else { return }
                RealmUtil.Write { (realm) in
                    globalData.isSpeechWaitSettingUseExperimentalWait = value == NSLocalizedString("SpeechWaitConfigTableView_DelayTimeInSec_SpeechWaitSettingType_Experimental", comment: "非推奨型")
                }
            }
        })
        <<< TextAreaRow(TestTextAreaTag) {
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
        
        autoreleasepool {
            if let configArray = RealmSpeechWaitConfig.GetAllObjects() {
                for config in configArray {
                    form.append(createSpeechWaitCells(speechWaitSetting: config))
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
