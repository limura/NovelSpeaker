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
    var notificationTokens:[NSObjectProtocol] = []
    
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
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.GlobalStateChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.form.removeAll()
                self.createSettingsTable()
            }
        }
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.RealmSettingChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.form.removeAll()
                self.createSettingsTable()
            }
        }
    }

    func removeNotificationCenter(){
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }
    
    func createSettingsTable(){
        form +++ Section()
            <<< LabelRow() { (row) in
                row.tag = "SettingsTableViewController_Information_TAG"
                row.title = NSLocalizedString("SettingsTableViewController_Information", comment: "お知らせ")
                NiftyUtilitySwift.CheckNewImportantImformation(hasNewInformationAlive: { (text) in
                    if text.count > 0 {
                        row.value = "❗"
                    }else{
                        row.value = ""
                    }
                }, hasNoNewInformation: {
                    row.value = ""
                })
                row.cell.accessoryType = .disclosureIndicator
            }.onCellSelection({ (butonCellof, buttonRow) in
                NiftyUtilitySwift.FetchNewImportantImformation(fetched: { (text, holeText) in
                    var informationText = NSLocalizedString("SettingsTableViewController_Information_NoImportantInformationAlived", comment: "今現在、重要なお知らせはありません。")
                    if text.count > 0 {
                        informationText = text
                    }
                    DispatchQueue.main.async {
                        NiftyUtilitySwift.SaveCheckedImportantInformation(text: text)
                        self.tabBarController?.tabBar.items?[3].badgeValue = nil
                        if let row = self.form.rowBy(tag: "SettingsTableViewController_Information_TAG") as? LabelRow {
                            row.value = ""
                            row.updateCell()
                        }
                    }
                    NiftyUtilitySwift.EasyDialogBuilder(self)
                    .title(title: NSLocalizedString("SettingsTableViewController_Information", comment: "お知らせ"))
                    .textView(content: informationText, heightMultiplier: 0.6)
                        .addButton(title: NSLocalizedString("SettingsTableViewController_Information_ShowOutdatedInformation", comment: "過去のお知らせを確認する"), callback: { (dialog) in
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false, completion: {
                                    NiftyUtilitySwift.EasyDialogMessageDialog(viewController: self, title: NSLocalizedString("SettingsTableViewController_Information_PastInformationTitle", comment: "過去のお知らせ"), message: holeText.replacingOccurrences(of: "#", with: "\n"), completion: nil)
                                })
                            }
                        })
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"),
                               callback: { (dialog) in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                    }).build().show()
                }, err: {
                    NiftyUtilitySwift.EasyDialogOneButton(
                        viewController: self,
                        title: NSLocalizedString("SettingsTableViewController_Information", comment: "お知らせ"),
                        message: NSLocalizedString("SettingsTableViewController_Information_CanNotGetInformation", comment: "お知らせの読み込みに失敗しました。"),
                        buttonTitle: nil, buttonAction: nil)
                })
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SpeakerSettingsViewController_TitleText", comment:"話者・声色設定")
                $0.cell.textLabel?.numberOfLines = 0
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
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (_, _) in
                let nextViewController = SpeechSectionConfigsViewController()
                nextViewController.targetNovelID = RealmSpeechSectionConfig.anyTarget
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })

            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SettingOfTheSpeechDelay", comment:"読み上げ時の間の設定")
                $0.cell.textLabel?.numberOfLines = 0
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
                $0.cell.textLabel?.numberOfLines = 0
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SettingOfTheTextSize", comment:"文字サイズの設定")
                $0.presentationMode = .segueName(segueName: "textSizeSettingSegue", onDismiss: nil)
                $0.cell.textLabel?.numberOfLines = 0
            }
            
            <<< TimeIntervalCountDownRow() { (row) in
                row.title = NSLocalizedString("SettingTableViewController_MaxSpeechTime", comment:"最大連続再生時間")
                row.minuteInterval = 5
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    if let globalState = RealmGlobalState.GetInstance() {
                        row.value = Double(globalState.maxSpeechTimeInSec)
                    }else{
                        row.value = 60*60*24-60
                    }
                }
            }.onChange({ row in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.maxSpeechTimeInSec = Int(value)
                    }
                }
            })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_CreateNewUserText", comment:"新規自作本の追加")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (butonCellof, buttonRow) in
                self.CreateNewUserText()
            })
            
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_BackgroundFetch", comment:"小説の自動更新")
                $0.value = RealmGlobalState.GetInstance()?.isBackgroundNovelFetchEnabled ?? false
                $0.cell.textLabel?.numberOfLines = 0
            }.onChange({ row in
                guard let judge = row.value else { return }
                if judge {
                    NiftyUtilitySwift.EasyDialogBuilder(self)
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
                            autoreleasepool {
                                if let globalState = RealmGlobalState.GetInstance() {
                                    RealmUtil.Write { (realm) in
                                        globalState.isBackgroundNovelFetchEnabled = true
                                    }
                                    NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
                                }
                            }
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: true)
                            }
                        })
                        .build().show()
                }else{
                    autoreleasepool {
                        if let globalState = RealmGlobalState.GetInstance() {
                            RealmUtil.Write { (realm) in
                                globalState.isBackgroundNovelFetchEnabled = false
                            }
                            NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
                        }
                    }
                }
            })
            
            <<< SwitchRow("OverrideRubySwitchRow") { (row) in
                row.title = NSLocalizedString("SettingTableViewController_OverrideRuby", comment:"ルビはルビだけ読む")
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else {
                        row.value = false
                        return
                    }
                    row.value = speechOverrideSetting.isOverrideRubyIsEnabled
                }
            }.onChange({ row in
                self.m_RubySwitchToggleHitCount += 1
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        speechOverrideSetting.isOverrideRubyIsEnabled = value
                    }
                }
            })
            <<< TextRow("OverrideRubyTextRow") { (row) in
                row.title = NSLocalizedString("SettingTableViewController_EditNotRubyStringTitle", comment:"非ルビ文字")
                row.cell.textLabel?.numberOfLines = 0
                row.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    let row: RowOf<Bool>! = form.rowBy(tag: "OverrideRubySwitchRow")
                    return row.value ?? false == false
                })
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else {
                        row.value = ""
                        return
                    }
                    row.value = speechOverrideSetting.notRubyCharactorStringArray
                }
            }.onChange({ textRow in
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let value = textRow.value else { return }
                    RealmUtil.Write { (realm) in
                        speechOverrideSetting.notRubyCharactorStringArray = value
                    }
                }
            })
            <<< SwitchRow(){ row in
                row.title = NSLocalizedString("SettingTableViewController_DisplayBookmarkPositionOnBookshelf", comment: "本棚に栞の現在位置ゲージを表示する")
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isReadingProgressDisplayEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isReadingProgressDisplayEnabled = value
                    }
                }
            })
            <<< SwitchRow(){ row in
                row.title = NSLocalizedString("SettingTableViewController_OnlyDisplayAddSpeechModSettings", comment: "本文中の長押しメニューを読み替え辞書へ登録のみにする")
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isMenuItemIsAddNovelSpeakerItemsOnly
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isMenuItemIsAddNovelSpeakerItemsOnly = value
                    }
                }
            })
            <<< SwitchRow(){ row in
                row.title = NSLocalizedString("SettingTableViewController_ShortSkipIsEnabled", comment: "コントロールセンターの前後の章(トラック)への移動ボタンを、少し前/少し後の文への移動にする")
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isShortSkipEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isShortSkipEnabled = value
                    }
                }
            })
            <<< SwitchRow() { row in
                row.title = NSLocalizedString("SettingTableViewController_PlaybackDurationIsEnabled", comment: "コントロールセンターの再生時間ゲージを有効にする(表示される時間は概算で、正確な値にはなりません)")
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isPlaybackDurationEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isPlaybackDurationEnabled = value
                    }
                }
            })
            <<< SwitchRow() { row in
                row.title = NSLocalizedString("SettingTableViewController_PageTurningSoundIsEnabled", comment: "ページめくり時に音を鳴らす")
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isPageTurningSoundEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isPageTurningSoundEnabled = value
                    }
                }
            })
            <<< SwitchRow() { row in
                row.title = NSLocalizedString("SettingTableViewController_IgnoreURISpeechIsEnabled", comment: "URIを読み上げないようにする")
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else { return }
                    row.value = speechOverrideSetting.isIgnoreURIStringSpeechEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        speechOverrideSetting.isIgnoreURIStringSpeechEnabled = value
                    }
                }
            })
            <<< AlertRow<String>() { row in
                row.title = NSLocalizedString("SettingTableViewController_RepeatTypeTitle", comment:"繰り返し再生")
                row.selectorTitle = NSLocalizedString("SettingTableViewController_RepeatTypeTitle", comment:"繰り返し再生")
                let noRepeat = NSLocalizedString("SettingTableViewController_RepeatType_NoRepeat", comment: "しない")
                let rewindToFirstStory = NSLocalizedString("SettingTableViewController_RepeatType_RewindToFirstStory", comment: "最初から")
                let rewindToThisStory =  NSLocalizedString("SettingTableViewController_RepeatType_RewindToThisStory", comment: "一つの章")
                row.options = [noRepeat, rewindToFirstStory, rewindToThisStory]
                row.value = noRepeat
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting else { return }
                    let type = speechOverrideSetting.repeatSpeechType
                    if type == .rewindToFirstStory {
                        row.value = rewindToFirstStory
                    }
                    if type == .rewindToThisStory {
                        row.value = rewindToThisStory
                    }
                }
            }.onChange({ (row) in
                let noRepeat = NSLocalizedString("SettingTableViewController_RepeatType_NoRepeat", comment: "しない")
                let rewindToFirstStory = NSLocalizedString("SettingTableViewController_RepeatType_RewindToFirstStory", comment: "最初から")
                let rewindToThisStory =  NSLocalizedString("SettingTableViewController_RepeatType_RewindToThisStory", comment: "一つの章")
                autoreleasepool {
                    guard let speechOverrideSetting = RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting, let typeString = row.value else { return }
                    RealmUtil.Write { (realm) in
                        if typeString == noRepeat {
                            speechOverrideSetting.repeatSpeechType = .noRepeat
                        }else if typeString == rewindToFirstStory {
                            speechOverrideSetting.repeatSpeechType = .rewindToFirstStory
                        }else if typeString == rewindToThisStory {
                            speechOverrideSetting.repeatSpeechType = .rewindToThisStory
                        }
                    }
                }
            })
            <<< SwitchRow() { row in
                row.title = NSLocalizedString("SettingTableViewController_IsEscapeAboutSpeechPositionDisplayBugOniOS12Enabled", comment: "iOS 12 で読み上げ中の読み上げ位置表示がおかしくなる場合への暫定的対応を適用する")
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled
                }
            }.onChange({ (row) in
                let judge = row.value
                if judge! {
                    NiftyUtilitySwift.EasyDialogBuilder(self)
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
                            autoreleasepool {
                                guard let globalState = RealmGlobalState.GetInstance() else { return }
                                RealmUtil.Write { (realm) in
                                    globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = true
                                }
                            }
                        })
                        .build().show()
                }else{
                    autoreleasepool {
                        guard let globalState = RealmGlobalState.GetInstance() else { return }
                        RealmUtil.Write { (realm) in
                            globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = false
                        }
                    }
                }
            })
            <<< SwitchRow("MixWithOthersSwitchRow") { row in
                row.title = NSLocalizedString("SettingTableViewController_MixWithOthersIsEnabled", comment: "他のアプリで音楽が鳴っても止まらないように努力する(イヤホンやコントロールセンターからの操作を受け付けなくなります)")
                row.cell.textLabel?.numberOfLines = 0
                row.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isMixWithOthersEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isMixWithOthersEnabled = value
                    }
                }
            })
            <<< SwitchRow() { row in
                row.title = NSLocalizedString("SettingTableViewController_DuckOthersIsEnabled", comment: "他のアプリの音を小さくする")
                row.cell.textLabel?.numberOfLines = 0
                row.hidden = .function(["MixWithOthersSwitchRow"], { form -> Bool in
                    let row: RowOf<Bool>! = form.rowBy(tag: "MixWithOthersSwitchRow")
                    return row.value ?? false == false
                })
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isDuckOthersEnabled
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isDuckOthersEnabled = value
                    }
                }
            })
            <<< SwitchRow("IsOpenRecentBookInStartTime") { row in
                row.title = NSLocalizedString("SettingTableViewController_IsOpenRecentBookInStartTime", comment: "起動時に前回開いていた小説を開く")
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isOpenRecentNovelInStartTime
                }
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isOpenRecentNovelInStartTime = value
                    }
                }
            })
            <<< SwitchRow("isDisallowsCellularAccess") { row in
                row.title = NSLocalizedString("SettingTableViewController_IsDisallowsCellularAccess", comment: "携帯電話網ではダウンロードしないようにする")
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.IsDisallowsCellularAccess
                }
                row.cell.textLabel?.numberOfLines = 0
            }.onChange({ (row) in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.IsDisallowsCellularAccess = value
                    }
                }
            })
            <<< SwitchRow("isNeedConfirmDeleteBook") { row in
                row.title = NSLocalizedString("SettingTableViewController_IsNeedConfirmDeleteBook", comment: "小説を削除する時に確認する")
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.IsNeedConfirmDeleteBook
                }
                row.cell.textLabel?.numberOfLines = 0
            }.onChange({ (row) in
                guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                RealmUtil.Write { (realm) in
                    globalState.IsNeedConfirmDeleteBook = value
                }
            })
            <<< SwitchRow("IsUseiCloud") {
                $0.title = NSLocalizedString("SettingsViewController_IsUseiCloud_Title", comment: "iCloud 同期を使用する")
                $0.value = RealmUtil.IsUseCloudRealm()
                $0.cell.textLabel?.numberOfLines = 0
            }.onChange({ (row) in
                guard let value = row.value else { return }
                if value == true {
                    if !RealmUtil.IsUseCloudRealm() {
                        self.ConifirmiCloudEnable()
                    }
                }else{
                    if RealmUtil.IsUseCloudRealm() {
                        self.ConifirmiCloudDisable()
                    }
                }
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_AddDefaultCorrectionOfTheReading", comment:"標準の読みの修正を上書き追加")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (butonCellof, buttonRow) in
                self.ConfirmAddDefaultSpeechModSetting()
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingsViewController_RemoveDefaultSpeechModSettings", comment:"標準の読みの修正と同じものを読み替え辞書登録から削除")
                $0.cell.textLabel?.numberOfLines = 0
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
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (butonCellof, buttonRow) in
                self.ShareNcodeListURLScheme()
            })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GoToSupportSite", comment: "サポートサイトを開く")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (buttonCellof, buttonRow) in
                if let url = URL(string: "https://limura.github.io/NovelSpeaker/") {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SendBugReport", comment: "不都合報告をmailで開発者に送る")
                $0.cell.textLabel?.numberOfLines = 0
                $0.presentationMode = .segueName(segueName: "BugReportViewSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GoToReleaseLog", comment:"更新履歴")
                $0.cell.textLabel?.numberOfLines = 0
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
                $0.cell.textLabel?.numberOfLines = 0
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_About", comment: "ことせかい について")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (buttonCellof, buttonRow) in
                NiftyUtilitySwift.EasyDialogBuilder(self)
                .label(text: NSLocalizedString("SettingTableViewController_About", comment: "ことせかい について"))
                .label(text: "Version: " + NiftyUtilitySwift.GetAppVersionString())
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                        dialog.dismiss(animated: false, completion: nil)
                    })
                .build().show()
            })
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_LICENSE", comment: "LICENSE")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (buttonCallof, buttonRow) in
                if let path = Bundle.main.path(forResource: "LICENSE", ofType: ".txt") {
                    do {
                        let license = try String(contentsOfFile: path)
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogBuilder(self)
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
                    NiftyUtilitySwift.EasyDialogBuilder(self)
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
                            NiftyUtilitySwift.EasyDialogBuilder(self)
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
                                NiftyUtilitySwift.EasyDialogBuilder(self)
                                .textView(content: currentPrivacyPolicy, heightMultiplier: 0.6)
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
                    return self.m_RubySwitchToggleHitCount < -10
                })
            }
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingsViewController_ClearSiteInfoCache", comment: "SiteInfoキャッシュを削除する")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                NovelDownloadQueue.shared.clearSiteInfoCache()
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogOneButton(
                        viewController: self,
                        title: nil,
                        message: NSLocalizedString("SettingsViewController_ClearSiteInfoCache_done", comment: "保存されている SiteInfo 情報を削除しました。"),
                        buttonTitle: nil,
                        buttonAction: nil)
                }
            })
            <<< SwitchRow("OverrideForceSiteInfoReload") { row in
                row.title = NSLocalizedString("SettingTableViewController_ForceSiteInfoReload", comment:"SiteInfoを毎回読み直す")
                row.value = false
                row.cell.textLabel?.numberOfLines = 0
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    row.value = globalState.isForceSiteInfoReloadIsEnabled
                }
            }.onChange({ row in
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance(), let value = row.value else { return }
                    RealmUtil.Write { (realm) in
                        globalState.isForceSiteInfoReloadIsEnabled = value
                    }
                }
            })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_ShowDebugLog", comment:"デバッグログの表示")
                $0.presentationMode = .segueName(segueName: "debugLogViewSegue", onDismiss: nil)
                $0.cell.textLabel?.numberOfLines = 0
            }
            
            <<< ButtonRow() {
                $0.title = "iCloud pull (with remove server change token)"
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogNoButton(viewController: self, title: nil, message: NSLocalizedString("SettingsViewController_CloudPullProcessingDialog", comment: "iCloud からデータを読み込み中です。"), completion: { (dialog) in
                        RealmUtil.stopSyncEngine()
                        RealmUtil.ForceRemoveIceCreamDatabaseSyncTokens()
                        try! RealmUtil.EnableSyncEngine()
                        RealmUtil.WaitAllLongLivedOperationIDCleared(completion: {
                            RealmUtil.CheckCloudDataIsValid { (result) in
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: nil)
                                }
                            }
                        })
                    })
                }
            })
            <<< ButtonRow() {
                $0.title = "iCloud pull (normal pull)"
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogNoButton(viewController: self, title: nil, message: NSLocalizedString("SettingsViewController_CloudPullProcessingDialog", comment: "iCloud からデータを読み込み中です。"), completion: { (dialog) in
                        DispatchQueue.main.async {
                            try! RealmUtil.EnableSyncEngine()
                            RealmUtil.CloudPull()
                            dialog.dismiss(animated: false, completion: nil)
                        }
                    })
                }
            })
            <<< ButtonRow() {
                $0.title = "iCloud push"
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogNoButton(viewController: self, title: nil, message: NSLocalizedString("SettingsViewController_CloudPushProcessingDialog", comment: "iCloud 側へデータを書き込み中です。"), completion: { (dialog) in
                        DispatchQueue.main.async {
                            try! RealmUtil.EnableSyncEngine()
                            RealmUtil.CloudPush()
                            dialog.dismiss(animated: false, completion: nil)
                        }
                    })
                }
            })
            <<< ButtonRow() {
                $0.title = "次回起動時に CoreData(旧データベース) の情報に書き戻す"
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                CoreDataToRealmTool.UnregisterConvertFromCoreDataFinished()
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogOneButton(viewController: self, title: nil, message: "次回起動時に CoreData(旧データベース) の情報に書き戻すように設定しました。", buttonTitle: nil, buttonAction: nil)
                }
            })
        <<< ButtonRow() {
            $0.title = "テスト用検索タブ"
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (_, _) in
            let nextViewController = NovelSearchViewController()
            self.navigationController?.pushViewController(nextViewController, animated: true)
        }).cellUpdate({ (cell, button) in
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
            cell.textLabel?.textColor = nil
        })
        
    }

    func AssignMessageTo(tag:Int, text:String, dialog:EasyDialog) {
        DispatchQueue.main.async {
            if let label = dialog.view.viewWithTag(tag) as? UILabel {
                label.text = text
            }
        }
    }
    
    func overrideiCloudToLocal() {
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogNoButton(
                viewController: self, title: NSLocalizedString("SettingsViewController_CopyingCloudToLocal", comment: "iCloud側のデータを端末側のデータへ変換中"), message: "-", completion: { (dialog) in
                    DispatchQueue.global(qos: .utility).async {
                        autoreleasepool {
                            guard let cloudRealm = try? RealmUtil.GetCloudRealm(), let localRealm = try? RealmUtil.GetLocalRealm() else {
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: {
                                        DispatchQueue.main.async {
                                            NiftyUtilitySwift.EasyDialogOneButton(
                                                viewController: self,
                                                title: nil,
                                                message: NSLocalizedString("SettingsViewController_CopyCloudToLocalFailed", comment: "iCloudのデータの取得に失敗しました。") + "(1)",
                                                buttonTitle: nil,
                                                buttonAction: nil)
                                            guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                                            row.value = true
                                            row.updateCell()
                                        }
                                    })
                                }
                                return
                            }
                            do {
                                try RealmToRealmCopyTool.DoCopy(from: cloudRealm, to: localRealm, progress: { (text) in
                                    self.AssignMessageTo(tag: 100, text: text, dialog: dialog)
                                })
                            }catch {
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: {
                                        NiftyUtilitySwift.EasyDialogOneButton(
                                            viewController: self,
                                            title: nil,
                                            message: NSLocalizedString("SettingsViewController_CopyCloudToLocalFailed", comment: "iCloudのデータの取得に失敗しました。") + "(2)",
                                            buttonTitle: nil, buttonAction: nil)
                                        guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                                        row.value = true
                                        row.updateCell()
                                    })
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false) {
                                    RealmUtil.SetIsUseCloudRealm(isUse: false)
                                    RealmUtil.stopSyncEngine()
                                    RealmUtil.RemoveCloudRealmFile()
                                    NiftyUtilitySwift.EasyDialogOneButton(
                                        viewController: self,
                                        title: nil,
                                        message: NSLocalizedString("SettingsViewController_iCloudDisable_done", comment: "iCloud同期を停止しました"),
                                        buttonTitle: nil,
                                        buttonAction: nil)
                                }
                            }
                        }
                    }

            })
        }
    }
    
    func overrideLocalToiCloud() {
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogNoButton(
                viewController: self, title: NSLocalizedString("SettingsViewController_CopyingLocalToCloud", comment: "現在のデータをiCloud側に登録中"), message: "-", completion: { (dialog) in
                    DispatchQueue.global(qos: .utility).async {
                        autoreleasepool {
                            RealmUtil.ForceRemoveIceCreamDatabaseSyncTokens()
                            RealmUtil.CloudPull()
                            guard let cloudRealm = try? RealmUtil.GetCloudRealm(), let localRealm = try? RealmUtil.GetLocalRealm() else {
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: {
                                        DispatchQueue.main.async {
                                            NiftyUtilitySwift.EasyDialogOneButton(
                                                viewController: self,
                                                title: nil,
                                                message: NSLocalizedString("SettingsViewController_CopyLocalToCloudFailed", comment: "現在のデータのiCloud側への登録に失敗しました。") + "(1)",
                                                buttonTitle: nil, buttonAction: nil)
                                            guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                                            row.value = false
                                            row.updateCell()
                                        }
                                    })
                                }
                                return
                            }
                            do {
                                try RealmToRealmCopyTool.DoCopy(from: localRealm, to: cloudRealm, progress: { (text) in
                                    self.AssignMessageTo(tag: 100, text: text, dialog: dialog)
                                })
                            }catch {
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: {
                                        NiftyUtilitySwift.EasyDialogOneButton(
                                            viewController: self,
                                            title: nil,
                                            message: NSLocalizedString("SettingsViewController_CopyLocalToCloudFailed", comment: "現在のデータのiCloud側への登録に失敗しました。") + "(2)",
                                            buttonTitle: nil, buttonAction: nil)
                                        guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                                        row.value = false
                                        row.updateCell()
                                    })
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false) {
                                    RealmUtil.SetIsUseCloudRealm(isUse: true)
                                    // TODO: local realm file をここで消してしまうと、iCloud側への転送が終わっていない records が転送できなくなってしまう……気がします。(要調査)
                                    RealmUtil.RemoveLocalRealmFile()
                                    NiftyUtilitySwift.EasyDialogLongMessageDialog(
                                        viewController: self,
                                        message: NSLocalizedString("SettingsViewController_iCloudEnable_done", comment: "iCloud同期を開始しました。\n同期は開始されましたが、端末側に保存されているデータをiCloud側へ登録する作業は続いています。\n端末側に保存されているデータが多い場合には、iCloud側への転送が終わるまでかなりの時間がかかる可能性があります。\nなお、残念ながらiCloud側への転送が終わったかどうかを知るすべが(開発者の知る限りでは)ありません。Appleの解説によると24時間の間はアプリを再度立ち上げれば転送を継続してくれるそうですが、機内モードにすると全てを諦められてしまうなどといった問題があるという話をWeb上でみかけたりしましたので、あまり安心はできないかもしれません。\n一応未送信や未受信のデータがある場合には通信中のインジケータを回すように努力はしますが、このインジケータが消えた事で送信が終了したというわけではないかもしれない、という事を理解しておいてください。"))
                                }
                            }
                        }
                    }

            })
        }
    }
    
    func ChooseUseiCloudDataOrOverrideLocalData() {
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogBuilder(self)
            .label(text: NSLocalizedString("SettingsViewController_IsUseiCloud_ChooseiCloudDataOrLocalData", comment: "iCloud側に利用可能なデータが存在するようです。iCloud側のデータをそのまま利用するか、現在のデータでiCloud上のデータを上書きするかを選択してください。"))
            .addButton(title: NSLocalizedString("SettingsViewController_IsUseiCloud_ChooseiCloudDataOrLocalData_ChooseiCloud", comment: "iCloudのデータをそのまま利用する"), callback: { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false) {
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogTwoButton(
                                viewController: self,
                                title: nil,
                                message: NSLocalizedString("SettingsViewController_IsUseiCloud_ConifirmRemoveLocalData", comment: "iCloud上のデータを利用する事にします。現在のデータは破棄されます。この操作は元に戻せません。よろしいですか？"),
                                button1Title: nil, // cancel
                                button1Action: {
                                    DispatchQueue.main.async {
                                        guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                                        row.value = false
                                        row.updateCell()
                                    }
                                },
                                button2Title: nil, // OK
                                button2Action: {
                                    DispatchQueue.main.async {
                                        RealmUtil.SetIsUseCloudRealm(isUse: true)
                                        // local realm は消して良いと言われたので消します。
                                        RealmUtil.RemoveLocalRealmFile()
                                        NiftyUtilitySwift.EasyDialogLongMessageDialog(
                                            viewController: self,
                                            message: NSLocalizedString("SettingsViewController_iCloudEnable_done", comment: "iCloud同期を開始しました"))
                                    }
                                }
                            )
                        }
                    }
                }
            })
            .addButton(title: NSLocalizedString("SettingsViewController_IsUseiCloud_ChooseiCloudDataOrLocalData_ChooseLocal", comment: "現在のデータでiCloud上のデータを上書きする"), callback: { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        self.overrideLocalToiCloud()
                    })
                }
            })
            .addButton(title: NSLocalizedString("SettingsViewController_IsUseiCloud_ChooseiCloudDataOrLocalData_Cancel", comment: "iCloud同期をやめる(キャンセル)"), callback: { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                    guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                    row.value = false
                    row.updateCell()
                }
            })
            .build().show()
        }
    }
    
    func CheckiCloudDataForiCloudEnable() {
        DispatchQueue.main.async {
            // 全てのダウンロードを止めてから作業を行います。
            NovelDownloadQueue.shared.ClearAllDownloadQueue()
            NiftyUtilitySwift.EasyDialogNoButton(
                viewController: self,
                title: nil,
                message: NSLocalizedString("SettingsViewController_IsUseiCloud_CheckiCloudData_pulling", comment: "iCloud側のデータを確認しています"),
                completion: { (dialog) in
                    // SyncEngine 周りを綺麗さっぱり消しておきます
                    RealmUtil.stopSyncEngine()
                    RealmUtil.ForceRemoveIceCreamDatabaseSyncTokens()
                    RealmUtil.RemoveCloudRealmFile()
                    do {
                        try RealmUtil.EnableSyncEngine()
                    }catch{
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: {
                                NiftyUtilitySwift.EasyDialogOneButton(
                                    viewController: self,
                                    title: nil,
                                    message: NSLocalizedString("SettingsViewController_IsUseiCloud_FailedSyncEngineStart", comment: "iCloud への接続に失敗しました。"),
                                    buttonTitle: nil,
                                    buttonAction: nil)
                                guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                                row.value = false
                                row.updateCell()
                            })
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        RealmUtil.CheckCloudDataIsValid { (result) in
                            if result {
                                // iCloud側に使えそうなデータがあった
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false) {
                                        self.ChooseUseiCloudDataOrOverrideLocalData()
                                    }
                                }
                                return
                            }
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false) {
                                    self.overrideLocalToiCloud()
                                }
                            }
                        }
                    }
            })
        }
    }
    
    func ConifirmiCloudEnable() {
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogTwoButton(
                viewController: self,
                title: NSLocalizedString("SettingsViewController_IsUseiCloud_ConifirmTitle", comment: "iCloud 同期を有効にしますか？"),
                message: NSLocalizedString("SettingsViewController_IsUseiCloud_ConifirmMessage", comment: "iCloud 同期を有効にすると、ことせかい 内のデータを書き換えるたびに iCloud による通信が試みるようになります。例えば小説を開いたり、読み上げを行ったりしただけでもデータが書き換わりますので、頻繁に通信が発生する事になります。"),
                button1Title: nil,
                button1Action: {
                    DispatchQueue.main.async {
                        guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                        row.value = false
                        row.updateCell()
                    }
                },
                button2Title: nil,
                button2Action: {
                    self.CheckiCloudDataForiCloudEnable()
                })
        }
    }
    
    func CheckiCloudAccountStatusIsValid(okHandler:(() -> Void)?, ngHandler:((String)->Void)?) {
        RealmUtil.GetCloudAccountStatus { (accountStatus, error) in
            if let error = error {
                ngHandler?(error.localizedDescription)
                return
            }
            switch accountStatus {
            case .available:
                okHandler?()
            case .restricted:
                ngHandler?(NSLocalizedString("SettingsViewController_iCloudAccountInvalid_restricted", comment: "iCloud アカウントが制限付きの状態でしたので利用できません。"))
            case .noAccount:
                ngHandler?(NSLocalizedString("SettingsViewController_iCloudAccountInvalid_noAccount", comment: "iCloud アカウントが設定されていません。"))
            case .couldNotDetermine:
                fallthrough
            @unknown default:
                ngHandler?(NSLocalizedString("SettingsViewController_iCloudAccountInvalid_cloudNotDetermine", comment: "iCloud アカウントの状態を取得できませんでした。"))
            }
        }
    }
    
    func ConifirmiCloudDisable() {
        CheckiCloudAccountStatusIsValid(okHandler: {
            DispatchQueue.main.async {
                NiftyUtilitySwift.EasyDialogTwoButton(
                    viewController: self,
                    title: NSLocalizedString("SettingsViewController_IsUseiCloud_ConifirmTitle_disable", comment: "iCloud 同期を無効にしますか？"),
                    message: nil,
                    button1Title: nil,
                    button1Action: {
                        DispatchQueue.main.async {
                            guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                            row.value = true
                            row.updateCell()
                        }
                    },
                    button2Title: nil,
                    button2Action: {
                        self.overrideiCloudToLocal()
                })
            }
        }) { (errorDescription) in
            DispatchQueue.main.async {
                guard let row = self.form.rowBy(tag: "IsUseiCloud") as? SwitchRow else { return }
                row.value = true
                row.updateCell()
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: self,
                    title: NSLocalizedString("SettingsViewController_InvalidiCloudStatus", comment: "iCloud の状態に問題がありました。"),
                    message: errorDescription,
                    buttonTitle: nil,
                    buttonAction: nil)
            }
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
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogBuilder(self)
                .label(text: NSLocalizedString("SettingTableViewController_AnAddressAddedAStandardParaphrasingDictionary", comment: "標準の読み替え辞書を上書き追加しました。"))
                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: {dialog in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false)
                    }
                })
                .build().show()
        }
    }
    /// 標準で用意された読み上げ辞書で上書きして良いか確認した上で、上書き追加します。
    func ConfirmAddDefaultSpeechModSetting(){
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogBuilder(self)
                .title(title: NSLocalizedString("SettingTableViewController_ConfirmAddDefaultSpeechModSetting", comment:"確認"))
                .label(text: NSLocalizedString("SettingtableViewController_ConfirmAddDefaultSpeechModSettingMessage", comment:"用意された読み替え辞書を追加・上書きします。よろしいですか？"))
                .addButton(title: NSLocalizedString("Cancel_button", comment:"Cancel"), callback: { dialog in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: true)
                    }
                })
                .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                    self.AddDefaultSpeechModSetting()
                })
                .build().show()
        }
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
            NiftyUtilitySwift.EasyDialogBuilder(self)
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
    
    func ShareToFile(dataFileURL:URL, fileName:String) {
        DispatchQueue.main.async {
            let activityViewController = UIActivityViewController(activityItems: [dataFileURL], applicationActivities: nil)
            let frame = UIScreen.main.bounds
            activityViewController.popoverPresentationController?.sourceView = self.view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.width / 2 - 60, y: frame.size.height - 50, width: 120, height: 50)
            self.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    func ShareBackupData(dataFileURL:URL, fileName:String) {
        if !MFMailComposeViewController.canSendMail() {
            ShareToFile(dataFileURL: dataFileURL, fileName: fileName)
            return
        }
        DispatchQueue.main.async {
            let dialog = NiftyUtilitySwift.EasyDialogBuilder(self)
            dialog.title(title: NSLocalizedString("SettingsViewController_ShareBackupDataSelectHow_Title", comment: "バックアップデータの送信方式を選んで下さい"))
                .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
                    dialog.dismiss(animated: false, completion: nil)
                })
            .addButton(title: NSLocalizedString("SettingsViewController_ShareBackupDataSelectHow_Mail", comment: "メールに添付する"), callback: { (dialog) in
                dialog.dismiss(animated: false) {
                    if let data = try? Data(contentsOf: dataFileURL, options: .dataReadingMapped) {
                        self.sendMailWithBinary(data: data, fileName: fileName, mimeType: "application/octet-stream")
                    }else{
                        NiftyUtilitySwift.EasyDialogOneButton(viewController: self, title: NSLocalizedString("SettingsViewController_ShareBackupSelect_FailedAppendToMail", comment: "メールへのファイルの添付に失敗しました。"), message: nil, buttonTitle: nil, buttonAction: nil)
                    }
                }
            }).addButton(title: NSLocalizedString("SettingsViewController_ShareBackupDataSelectHow_ShareButton", comment: "シェア")) { (dialog) in
                dialog.dismiss(animated: false) {
                    self.ShareToFile(dataFileURL: dataFileURL, fileName: fileName)
                }
            }.build().show()
        }
    }
    /// 現在の状態をファイルにして mail に添付します。
    func ShareBackupData(withAllStoryContent:Bool){
        let labelTag = 100
        let dialog = NiftyUtilitySwift.EasyDialogBuilder(self)
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
            let fileName = backupData.lastPathComponent
            self.ShareBackupData(dataFileURL: backupData, fileName: fileName)
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
                    let novelID = RealmNovel.AddNewNovelOnlyText(content: "", title: NSLocalizedString("GlobalDataSingleton_NewUserBookTitle", comment: "新規ユーザ小説"))
                    nextViewController.targetNovelID = novelID
                }
                break
            default:
                break
            }
        }
    }
}
