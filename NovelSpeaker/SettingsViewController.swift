//
//  SettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/11.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import MessageUI
import Eureka

class SettingsViewController: FormViewController, MFMailComposeViewControllerDelegate {
    var m_NarouContentCacheData:NarouContentCacheData? = nil
    var m_RubySwitchToggleHitCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "SettingsViewController viewDidLoad", data: [:])
        createSettingsTable()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        addNotificationCenter()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeNotificationCenter()
    }
    
    // TODO: バックアップファイルからのデータ読み込み完了後にこの Notification を呼ぶ
    func addNotificationCenter(){
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(forName: Notification.Name.NovelSpeaker.GlobalStateChanged, object: nil, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.form.removeAll()
                self.createSettingsTable()
            }
        }
    }

    func removeNotificationCenter(){
        NotificationCenter.default.removeObserver(self)
    }
    
    func createSettingsTable(){
        form +++ Section()
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SpeakerSettingsViewController_TitleText", comment:"話者・声色設定")
            }.onCellSelection({ (_, _) in
                let nextViewController = SpeakerSettingsViewController()
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingsViewController_SpeechModSettingsButtonTitle", comment:"話者変更設定(会話文等で声質を変えたりする設定)")
            }.onCellSelection({ (_, _) in
                let nextViewController = SpeechSectionConfigsViewController()
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })

            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SettingOfTheSpeechDelay", comment:"読み上げ時の間の設定")
            }.onCellSelection({ (_, _) in
                let nextViewController = SpeechWaitSettingViewControllerSwift()
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })

            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_CorrectionOfTheReading", comment:"読みの修正")
                $0.presentationMode = .segueName(segueName: "speechModSettingSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SettingOfTheTextSize", comment:"文字サイズの設定")
                $0.presentationMode = .segueName(segueName: "textSizeSettingSegue", onDismiss: nil)
            }
            
            <<< TimeIntervalCountDownRow() {
                $0.title = NSLocalizedString("SettingTableViewController_MaxSpeechTime", comment:"最大連続再生時間")
                let duration = GlobalDataSingleton.getInstance().getGlobalState().maxSpeechTimeInSec
                //Date(timeIntervalSince1970: duration as! TimeInterval)
                //Date(timeIntervalSinceReferenceDate: duration as! TimeInterval)
                $0.minuteInterval = 5
                $0.value = duration?.doubleValue
                }.onChange({ row in
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write(block: { (realm) in
                        globalState.maxSpeechTimeInSec = Int(value)
                    })
                })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_CreateNewUserText", comment:"新規自作本の追加")
            }.onCellSelection({ (butonCellof, buttonRow) in
                self.CreateNewUserText()
            })
            
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_BackgroundFetch", comment:"小説の自動更新")
                $0.value = GlobalDataSingleton.getInstance().getBackgroundNovelFetchEnabled()
            }.onChange({ row in
                let judge = row.value
                if judge! {
                    EasyDialog.Builder(self)
                        .title(title: NSLocalizedString("SettingTableViewController_ConfirmEnableBackgroundFetch_title", comment:"確認"))
                        .label(text: NSLocalizedString("SettingtableViewController_ConfirmEnableBackgroundFetch", comment:"この設定を有効にすると、ことせかい を使用していない時等に小説の更新を確認するようになるため、ネットワーク通信が発生するようになります。よろしいですか？"))
                        .addButton(title: NSLocalizedString("Cancel_button", comment: "cancel"), callback: { dialog in
                            row.value = false
                            row.updateCell()
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: true, completion: nil)
                            }
                        })
                        .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                            NiftyUtilitySwift.RegisterUserNotification()
                            if let globalState = RealmGlobalState.GetInstance() {
                                RealmUtil.Write(block: { (realm) in
                                    globalState.isBackgroundNovelFetchEnabled = true
                                })
                                NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
                            }
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: true)
                            }
                        })
                        .build().show()
                }else{
                    if let globalState = RealmGlobalState.GetInstance() {
                        RealmUtil.Write(block: { (realm) in
                            globalState.isBackgroundNovelFetchEnabled = false
                        })
                        NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
                    }
                }
            })
            
            <<< SwitchRow("OverrideRubySwitchRow") {
                $0.title = NSLocalizedString("SettingTableViewController_OverrideRuby", comment:"ルビはルビだけ読む")
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else {
                    $0.value = false
                    return
                }
                $0.value = speechOverrideSetting.isOverrideRubyIsEnabled
            }.onChange({ row in
                self.m_RubySwitchToggleHitCount += 1
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    speechOverrideSetting.isOverrideRubyIsEnabled = value
                })
            })
            <<< TextRow("OverrideRubyTextRow") {
                $0.title = NSLocalizedString("SettingTableViewController_EditNotRubyStringTitle", comment:"非ルビ文字")
                $0.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    let row: RowOf<Bool>! = form.rowBy(tag: "OverrideRubySwitchRow")
                    return row.value ?? false == false
                })
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else {
                    $0.value = ""
                    return
                }
                $0.value = speechOverrideSetting.notRubyCharactorStringArray
            }.onChange({ textRow in
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let value = textRow.value else { return }
                RealmUtil.Write(block: { (realm) in
                    speechOverrideSetting.notRubyCharactorStringArray = value
                })
            })
            <<< SwitchRow(){
                $0.title = NSLocalizedString("SettingTableViewController_DisplayBookmarkPositionOnBookshelf", comment: "本棚に栞の現在位置ゲージを表示する")
                $0.cell.textLabel?.numberOfLines = 0
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isReadingProgressDisplayEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isReadingProgressDisplayEnabled = value
                })
            })
            <<< SwitchRow(){
                $0.title = NSLocalizedString("SettingTableViewController_OnlyDisplayAddSpeechModSettings", comment: "本文中の長押しメニューを読み替え辞書へ登録のみにする")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isMenuItemIsAddSpeechModSettingOnly
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isMenuItemIsAddSpeechModSettingOnly = value
                })
            })
            <<< SwitchRow(){
                $0.title = NSLocalizedString("SettingTableViewController_ShortSkipIsEnabled", comment: "コントロールセンターの前後の章(トラック)への移動ボタンを、少し前/少し後の文への移動にする")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isShortSkipEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isShortSkipEnabled = value
                })
            })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_PlaybackDurationIsEnabled", comment: "コントロールセンターの再生時間ゲージを有効にする(表示される時間は概算で、正確な値にはなりません)")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isPlaybackDurationEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isPlaybackDurationEnabled = value
                })
            })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_DarkThemeIsEnabled", comment: "小説を読む時に背景を暗くする")
                $0.cell.textLabel?.numberOfLines = 0
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isDarkThemeEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isDarkThemeEnabled = value
                })
            })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_PageTurningSoundIsEnabled", comment: "ページめくり時に音を鳴らす")
                $0.cell.textLabel?.numberOfLines = 0
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isPageTurningSoundEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isPageTurningSoundEnabled = value
                })
            })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_IgnoreURISpeechIsEnabled", comment: "URIを読み上げないようにする")
                $0.cell.textLabel?.numberOfLines = 0
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else { return }
                $0.value = speechOverrideSetting.isIgnoreURIStringSpeechEnabled
            }.onChange({ (row) in
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    speechOverrideSetting.isIgnoreURIStringSpeechEnabled = value
                })
            })
            <<< AlertRow<String>() { row in
                row.title = NSLocalizedString("SettingTableViewController_RepeatTypeTitle", comment:"繰り返し再生")
                row.selectorTitle = NSLocalizedString("SettingTableViewController_RepeatTypeTitle", comment:"繰り返し再生")
                let noRepeat = NSLocalizedString("SettingTableViewController_RepeatType_NoRepeat", comment: "しない")
                let rewindToFirstStory = NSLocalizedString("SettingTableViewController_RepeatType_RewindToFirstStory", comment: "最初から")
                let rewindToThisStory =  NSLocalizedString("SettingTableViewController_RepeatType_RewindToThisStory", comment: "一つの章")
                row.options = [noRepeat, rewindToFirstStory, rewindToThisStory]
                row.value = noRepeat
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else { return }
                let type = speechOverrideSetting.repeatSpeechType
                if type == .rewindToFirstStory {
                    row.value = rewindToFirstStory
                }
                if type == .rewindToThisStory {
                    row.value = rewindToThisStory
                }
            }.onChange({ (row) in
                let noRepeat = NSLocalizedString("SettingTableViewController_RepeatType_NoRepeat", comment: "しない")
                let rewindToFirstStory = NSLocalizedString("SettingTableViewController_RepeatType_RewindToFirstStory", comment: "最初から")
                let rewindToThisStory =  NSLocalizedString("SettingTableViewController_RepeatType_RewindToThisStory", comment: "一つの章")
                guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let typeString = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    if typeString == noRepeat {
                        speechOverrideSetting.repeatSpeechType = .noRepeat
                    }else if typeString == rewindToFirstStory {
                        speechOverrideSetting.repeatSpeechType = .rewindToFirstStory
                    }else if typeString == rewindToThisStory {
                        speechOverrideSetting.repeatSpeechType = .rewindToThisStory
                    }
                })
            })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_IsEscapeAboutSpeechPositionDisplayBugOniOS12Enabled", comment: "iOS 12 で読み上げ中の読み上げ位置表示がおかしくなる場合への暫定的対応を適用する")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled
            }.onChange({ (row) in
                let judge = row.value
                if judge! {
                    EasyDialog.Builder(self)
                        .title(title: NSLocalizedString("SettingTableViewController_ConfirmEnableEscapeAboutSpeechPositionDisplayBugOniOS12_title", comment:"確認"))
                        .textView(content: NSLocalizedString("SettingtableViewController_ConfirmEnableEscapeAboutSpeechPositionDisplayBugOniOS12", comment:"この設定を有効にすると、読み上げ中の読み上げ位置表示がおかしくなる原因と思われる文字(多くは空白や改行などの表示されない文字です)について、\"α\"(アルファ)に読み替えるように設定することで回避するようになります。\nこの機能を実装した時点では、\"α\"(アルファ)は読み上げられない文字ですので概ね問題ない動作になると思われますが、将来的に iOS の音声合成エンジン側の変更により「アルファ」と読み上げられるようになる可能性があります。\nまた、この機能が必要となるのは iOS 12(以降) だと思われます。\n以上の事を理解した上でこの設定を有効にしますか？"), heightMultiplier: 0.6)
                        .addButton(title: NSLocalizedString("Cancel_button", comment: "cancel"), callback: { dialog in
                            row.value = false
                            row.updateCell()
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: true, completion: nil)
                            }
                        })
                        .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: true)
                            }
                            guard let globalState = RealmGlobalState.GetInstance() else { return }
                            RealmUtil.Write(block: { (realm) in
                                globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = true
                            })
                        })
                        .build().show()
                }else{
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    RealmUtil.Write(block: { (realm) in
                        globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = false
                    })
                }
            })
            <<< SwitchRow("MixWithOthersSwitchRow") {
                $0.title = NSLocalizedString("SettingTableViewController_MixWithOthersIsEnabled", comment: "他のアプリで音楽が鳴っても止まらないように努力する(イヤホンやコントロールセンターからの操作を受け付けなくなります)")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isMixWithOthersEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isMixWithOthersEnabled = value
                })
            })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_DuckOthersIsEnabled", comment: "他のアプリの音を小さくする")
                $0.cell.textLabel?.numberOfLines = 0
                $0.hidden = .function(["MixWithOthersSwitchRow"], { form -> Bool in
                    let row: RowOf<Bool>! = form.rowBy(tag: "MixWithOthersSwitchRow")
                    return row.value ?? false == false
                })
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isDuckOthersEnabled
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isDuckOthersEnabled = value
                })
            })
            <<< SwitchRow("IsOpenRecentBookInStartTime") {
                $0.title = NSLocalizedString("SettingTableViewController_IsOpenRecentBookInStartTime", comment: "起動時に前回開いていた小説を開く")
                $0.cell.textLabel?.numberOfLines = 0
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isOpenRecentNovelInStartTime
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isOpenRecentNovelInStartTime = value
                })
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_AddDefaultCorrectionOfTheReading", comment:"標準の読みの修正を上書き追加")
            }.onCellSelection({ (butonCellof, buttonRow) in
                self.ConfirmAddDefaultSpeechModSetting()
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingsViewController_RemoveDefaultSpeechModSettings", comment:"標準の読みの修正と同じものを読み替え辞書登録から削除")
            }.onCellSelection({ (butonCellof, buttonRow) in
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogTwoButton(
                        viewController: self,
                        title: NSLocalizedString("SettingsViewController_RemoveDefaultSpeechModSettings_ConifirmTitle", comment: "確認"),
                        message: NSLocalizedString("SettingsViewController_RemoveDefaultSpeechModSettings_ConifirmMessage", comment: "読みの修正に登録されているもののうち、標準の読みの修正と同じものを削除します。よろしいですか？"),
                        button1Title: nil, // Cancel
                        button1Action: nil,
                        button2Title: nil, // OK
                        button2Action: {
                            NovelSpeakerUtility.RemoveAllDefaultSpeechModSettings()
                            DispatchQueue.main.async {
                                NiftyUtilitySwift.EasyDialogOneButton(
                                    viewController: self,
                                    title: nil,
                                    message: NSLocalizedString("SettingsViewController_RemoveDefaultSpeechModSettings_DeletedMessage", comment: "読みの修正に登録されているもののうち、標準の読みの修正と同じものを削除しました。"),
                                    buttonTitle: nil, // OK
                                    buttonAction: nil)
                            }
                    })
                }
            })

            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GetNcodeDownloadURLScheme", comment:"再ダウンロード用データの生成")
                }.onCellSelection({ (butonCellof, buttonRow) in
                    self.ShareNcodeListURLScheme()
                })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GoToSupportSite", comment: "サポートサイトを開く")
            }.onCellSelection({ (buttonCellof, buttonRow) in
                if let url = URL(string: "https://limura.github.io/NovelSpeaker/") {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SendBugReport", comment: "不都合報告をmailで開発者に送る")
                $0.presentationMode = .segueName(segueName: "BugReportViewSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GoToReleaseLog", comment:"更新履歴")
            }.onCellSelection({ (buttonCellOf, button) in
                let nextViewController = UpdateLogViewController()
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_RightNotation", comment:"権利表記")
                $0.presentationMode = .segueName(segueName: "CreditPageSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_About", comment: "ことせかい について")
            }.onCellSelection({ (buttonCellof, buttonRow) in
                EasyDialog.Builder(self)
                .label(text: NSLocalizedString("SettingTableViewController_About", comment: "ことせかい について"))
                .label(text: "Version: " + NiftyUtilitySwift.GetAppVersionString())
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                        dialog.dismiss(animated: false, completion: nil)
                    })
                .build().show()
            })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_LICENSE", comment: "LICENSE")
            }.onCellSelection({ (buttonCallof, buttonRow) in
                if let path = Bundle.main.path(forResource: "LICENSE", ofType: ".txt") {
                    do {
                        let license = try String(contentsOfFile: path)
                        DispatchQueue.main.async {
                            EasyDialog.Builder(self)
                                .textView(content: license, heightMultiplier: 0.7)
                                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                    NovelSpeakerUtility.SetLicenseReaded(isRead: true)
                                    DispatchQueue.main.async {
                                        dialog.dismiss(animated: true)
                                    }
                                })
                                .build().show()
                        }
                        return
                    }catch{
                        // nothing to do.
                    }
                }
                DispatchQueue.main.async {
                    EasyDialog.Builder(self)
                        .textView(content: NSLocalizedString("SettingTableViewController_LISENSE_file_can_not_read", comment: "LICENSE.txt を読み込めませんでした。ことせかい の GitHub 側の LICENSE.txt を参照してください。"), heightMultiplier: 0.7)
                        .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: true)
                            }
                        })
                        .build().show()
                }
            })
            <<< ButtonRow() {
            $0.title = NSLocalizedString("SettingTableViewController_PrivacyPolicy", comment: "ことせかい のプライバシーポリシーを確認する")
            $0.cell.textLabel?.numberOfLines = 0
            $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
            }.onCellSelection({ (buttonCellOf, buttonRow) in
                if let privacyPolicyUrl = NovelSpeakerUtility.privacyPolicyURL {
                    func privacyPolycyLoadFailed(){
                        DispatchQueue.main.async {
                            EasyDialog.Builder(self)
                            .textView(content: NSLocalizedString("SettingTableViewController_PrivacyPolicy_can_not_load", comment: "最新のプライバシーポリシーを読み込めませんでした。\nSafariでの表示を試みます。"), heightMultiplier: 0.6)
                            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: true)
                                    UIApplication.shared.open(privacyPolicyUrl, options: [:], completionHandler: nil)
                                }
                            })
                            .build().show()
                        }
                    }
                    NiftyUtilitySwift.cashedHTTPGet(url: privacyPolicyUrl, delay: 60*60, successAction: { (data) in
                        if let currentPrivacyPolicy = String(data: data, encoding: .utf8) {
                            DispatchQueue.main.async {
                                EasyDialog.Builder(self)
                                .textView(content: currentPrivacyPolicy, heightMultiplier: 0.7)
                                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                    DispatchQueue.main.async {
                                        dialog.dismiss(animated: true)
                                    }
                                })
                                .build().show()
                            }
                        }else{
                            privacyPolycyLoadFailed()
                        }
                    }, failedAction: { (error) in
                        privacyPolycyLoadFailed()
                    })
                }
            })

            // デバッグ用の設定は、「ルビはルビだけ読む」のON/OFFを10回位繰り返すと出て来るようにしていて、
            // それらはこの下に記述されます
            +++ Section("Debug") {
                $0.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    return self.m_RubySwitchToggleHitCount < 10
                })
            }
            
            <<< SwitchRow("OverrideForceSiteInfoReload") {
                $0.title = NSLocalizedString("SettingTableViewController_ForceSiteInfoReload", comment:"SiteInfoを毎回読み直す")
                $0.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    return self.m_RubySwitchToggleHitCount < 10
                })
                $0.value = false
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                $0.value = globalState.isForceSiteInfoReloadIsEnabled
            }.onChange({ row in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write(block: { (realm) in
                    globalState.isForceSiteInfoReloadIsEnabled = value
                })
            })
            /*
            <<< SwitchRow("IsDummySilentSoundEnabled") {
                $0.title = NSLocalizedString("SettingTableViewController_DummySilentSoundEnable", comment:"再生中に無音の音を鳴らしてバックグラウンド再生中に再生が停止しないように祈る")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                $0.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    return self.m_RubySwitchToggleHitCount < 10
                })
                $0.value = GlobalDataSingleton.getInstance()?.isDummySilentSoundEnabled()
                }.onChange({ row in
                    GlobalDataSingleton.getInstance()?.setIsDummySilentSoundEnabled(row.value!)
                })
             */
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_ShowDebugLog", comment:"デバッグログの表示")
                $0.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    return self.m_RubySwitchToggleHitCount < 10
                })
                $0.presentationMode = .segueName(segueName: "debugLogViewSegue", onDismiss: nil)
            }
    }
    
    // 新規のユーザ本を追加して、編集ページに遷移する
    func CreateNewUserText(){
        performSegue(withIdentifier: "CreateNewUserTextSegue", sender: self)
        /* MEMO: 自前でWidgetを配置することができればこういう感じで segue を使わずに画面遷移しようと思っています。
        let novel = RealmNovel()
        let nextViewController = EditBookViewController()
        nextViewController.targetNovel = novel
        self.navigationController?.pushViewController(nextViewController, animated: true)
         */
    }
    /// 標準で用意された読み上げ辞書を上書き追加します。
    func AddDefaultSpeechModSetting(){
        NovelSpeakerUtility.OverrideDefaultSpeechModSettings()
        EasyDialog.Builder(self)
            .label(text: NSLocalizedString("SettingTableViewController_AnAddressAddedAStandardParaphrasingDictionary", comment: "標準の読み替え辞書を上書き追加しました。"))
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: {dialog in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: true)
                }
            })
            .build().show()
    }
    /// 標準で用意された読み上げ辞書で上書きして良いか確認した上で、上書き追加します。
    func ConfirmAddDefaultSpeechModSetting(){
        EasyDialog.Builder(self)
            .title(title: NSLocalizedString("SettingTableViewController_ConfirmAddDefaultSpeechModSetting", comment:"確認"))
            .label(text: NSLocalizedString("SettingtableViewController_ConfirmAddDefaultSpeechModSettingMessage", comment:"用意された読み替え辞書を追加・上書きします。よろしいですか？"))
            .addButton(title: NSLocalizedString("Cancel_button", comment:"Cancel"), callback: { dialog in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: true)
                }
            })
            .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: true, completion: nil)
                }
                self.AddDefaultSpeechModSetting()
            })
            .build().show()
    }

    @discardableResult
    func sendMailWithBinary(data:Data, fileName:String, mimeType:String) -> Bool {
        if !MFMailComposeViewController.canSendMail() {
            return false;
        }
        let picker = MFMailComposeViewController()
        picker.mailComposeDelegate = self;
        picker.setSubject(NSLocalizedString("SettingTableView_SendEmailForBackupTitle", comment:"ことせかい バックアップ"))
        var messageBody = NSLocalizedString("SettingTableView_SendEmailForBackupBody", comment:"添付されたファイルを ことせかい で読み込む事で、小説のリストが再生成されます。")
        if data.count >= 1024*1024*5 { // 5MBytes以上
            messageBody += "\r\n" + String(format: NSLocalizedString("SettingTableView_SendEmailWithLargeFileWarning", comment: "なお、今回添付されているファイルは %@ ととても大きいため、メールの転送経路によってはエラーを引き起こす可能性があります。\r\niCloud DriveのMail Dropという機能を使うとかなり大きなファイル(最大5GBytesまで)のファイルを送信できるようになるので、そちらの利用を検討したほうが良いかもしれません。"), NiftyUtilitySwift.ByteSizeToVisibleString(byteSize: data.count)) 
        }
        picker.setMessageBody(messageBody, isHTML: false)
        picker.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        present(picker, animated: true, completion: nil)
        return true;
    }
    
    /// 現在の本棚にある小説のリストを再ダウンロードするためのURLを取得して、シェアします。
    func ShareNcodeListURLScheme(){
        DispatchQueue.main.async {
            EasyDialog.Builder(self)
            .text(content: NSLocalizedString("SettingsViewController_IsCreateFullBackup?", comment: "小説の本文まで含めた完全なバックアップファイルを生成しますか？\r\n登録小説数が多い場合は生成に膨大な時間と本体容量が必要となります。"))
            .addButton(title: NSLocalizedString("SettingsViewController_ChooseFullBackup", comment: "完全バックアップを生成する(時間がかかります)")) { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        self.ShareBackupData(withAllStoryContent: true)
                    })
                }
            }.addButton(title: NSLocalizedString("SettingsViewController_ChooseSmallBackup", comment: "軽量バックアップを生成する(時間はかかりません)")) { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        self.ShareBackupData(withAllStoryContent: false)
                    })
                }
            }.addButton(title: NSLocalizedString("SettingsViewController_ChooseCancel", comment: "キャンセル")) { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
            }.build().show()
        }
    }
    /// 現在の状態をファイルにして mail に添付します。
    func ShareBackupData(withAllStoryContent:Bool){
        let labelTag = 100
        let dialog = EasyDialog.Builder(self)
            .label(text: NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……"), textAlignment: NSTextAlignment.center, tag: labelTag)
            .build()
        DispatchQueue.main.async {
            dialog.show()
        }
        DispatchQueue.global(qos: .utility).async {
            guard let backupData = NovelSpeakerUtility.CreateBackupData(withAllStoryContent: withAllStoryContent, progress: { (description) in
                DispatchQueue.main.async {
                    if let label = dialog.view.viewWithTag(labelTag) as? UILabel {
                        label.text = NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……") + "\r\n"
                            + description
                    }
                }
            }) else {
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                    NiftyUtilitySwift.EasyDialogOneButton(viewController: self, title: NSLocalizedString("SettingsViewController_GenerateBackupDataFailed", comment: "バックアップデータの生成に失敗しました。"), message: nil, buttonTitle: nil, buttonAction: nil)
                }
                return
            }
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale.current
            dateFormatter.dateFormat = "yyyyMMddHHmm"
            let dateString = dateFormatter.string(from: Date())
            let fileName = String.init(format: "%@.novelspeaker-backup+zip", dateString)
            DispatchQueue.main.async {
                dialog.dismiss(animated: false, completion: nil)
                self.sendMailWithBinary(data: backupData, fileName: fileName, mimeType: "application/octet-stream")
            }
        }
    }
    
    // MFMailComposeViewController でmailアプリ終了時に呼び出されるのでこのタイミングで viewController を取り戻します
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let identifier = segue.identifier {
            switch identifier {
            case "CreateNewUserTextSegue":
                if let nextViewController:EditBookViewController = segue.destination as? EditBookViewController {
                    let novel = RealmNovel()
                    novel.type = .UserCreated
                    let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: 1)
                    RealmUtil.Write { (realm) in
                        realm.add(novel, update: true)
                        realm.add(story, update: true)
                    }
                    nextViewController.targetNovel = novel
                }
                break
            default:
                break
            }
        }
    }
}
