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
        GlobalDataSingleton.getInstance().reloadSpeechSetting()
    }
    
    func createSettingsTable(){
        form +++ Section()
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingsTableViewController_SettingOfTheQualityOfVoice", comment:"声質の設定")
                $0.presentationMode = .segueName(segueName: "speakSettingsSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_CorrectionOfTheReading", comment:"読みの修正")
                $0.presentationMode = .segueName(segueName: "speechModSettingSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SettingOfTheTextSize", comment:"文字サイズの設定")
                $0.presentationMode = .segueName(segueName: "textSizeSettingSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SettingOfTheSpeechDelay", comment:"読み上げ時の間の設定")
                $0.presentationMode = .segueName(segueName: "textDelaySettingSegue", onDismiss: nil)
            }
            
            <<< TimeIntervalCountDownRow() {
                $0.title = NSLocalizedString("SettingTableViewController_MaxSpeechTime", comment:"最大連続再生時間")
                let duration = GlobalDataSingleton.getInstance().getGlobalState().maxSpeechTimeInSec
                //Date(timeIntervalSince1970: duration as! TimeInterval)
                //Date(timeIntervalSinceReferenceDate: duration as! TimeInterval)
                $0.minuteInterval = 5
                $0.value = duration?.doubleValue
                }.onChange({ row in
                    let globalData = GlobalDataSingleton.getInstance()
                    let globalState = globalData?.getGlobalState()
                    globalState?.maxSpeechTimeInSec = row.value! as NSNumber
                    globalData?.updateGlobalState(globalState)
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
                                // TODO: ロジックが入ってる
                                let globalData = GlobalDataSingleton.getInstance()
                                globalData?.updateBackgroundNovelFetchMode(true)
                                globalData?.registerUserNotification()
                                globalData?.startBackgroundFetch()
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: true)
                                }
                            })
                            .build().show()
                    }else{
                        GlobalDataSingleton.getInstance().updateBackgroundNovelFetchMode(false)
                    }
                })
            
            <<< SwitchRow("OverrideRubySwitchRow") {
                $0.title = NSLocalizedString("SettingTableViewController_OverrideRuby", comment:"ルビはルビだけ読む")
                $0.value = GlobalDataSingleton.getInstance().getOverrideRubyIsEnabled()
                }.onChange({ row in
                    self.m_RubySwitchToggleHitCount += 1
                    GlobalDataSingleton.getInstance().setOverrideRubyIsEnabled(row.value!)
                })
            <<< TextRow("OverrideRubyTextRow") {
                $0.title = NSLocalizedString("SettingTableViewController_EditNotRubyStringTitle", comment:"非ルビ文字")
                $0.value = GlobalDataSingleton.getInstance().getNotRubyCharactorStringArray()
                $0.hidden = .function(["OverrideRubySwitchRow"], { form -> Bool in
                    let row: RowOf<Bool>! = form.rowBy(tag: "OverrideRubySwitchRow")
                    return row.value ?? false == false
                })
                }.onChange({ textRow in
                    GlobalDataSingleton.getInstance().setNotRubyCharactorStringArray(textRow.value)
                })
            <<< SwitchRow(){
                $0.title = NSLocalizedString("SettingTableViewController_DisplayBookmarkPositionOnBookshelf", comment: "本棚に栞の現在位置ゲージを表示する")
                $0.value = GlobalDataSingleton.getInstance().isReadingProgressDisplayEnabled()
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setReadingProgressDisplayEnabled(row.value!)
                    let notificationCenter = NotificationCenter.default
                    let notification = Notification(name: Notification.Name("NarouContentReadingPointChanged"))
                    notificationCenter.post(notification)
                })
            <<< SwitchRow(){
                $0.title = NSLocalizedString("SettingTableViewController_OnlyDisplayAddSpeechModSettings", comment: "本文中の長押しメニューを読み替え辞書へ登録のみにする")
                $0.value = GlobalDataSingleton.getInstance().getMenuItemIsAddSpeechModSettingOnly()
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = .systemFont(ofSize: 14.0)
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setMenuItemIsAddSpeechModSettingOnly(row.value!)
                })
            <<< SwitchRow(){
                $0.title = NSLocalizedString("SettingTableViewController_ShortSkipIsEnabled", comment: "コントロールセンターの前後の章(トラック)への移動ボタンを、少し前/少し後の文への移動にする")
                $0.value = GlobalDataSingleton.getInstance().isShortSkipEnabled()
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = .systemFont(ofSize: 14.0)
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setShortSkipEnabled(row.value!)
                })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_PlaybackDurationIsEnabled", comment: "コントロールセンターの再生時間ゲージを有効にする(表示される時間は概算で、正確な値にはなりません)")
                $0.value = GlobalDataSingleton.getInstance().isPlaybackDurationEnabled()
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = .systemFont(ofSize: 14.0)
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setPlaybackDurationIsEnabled(row.value!)
                })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_DarkThemeIsEnabled", comment: "小説を読む時に背景を暗くする")
                $0.value = GlobalDataSingleton.getInstance().isDarkThemeEnabled()
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setDarkThemeIsEnabled(row.value!)
                })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_PageTurningSoundIsEnabled", comment: "ページめくり時に音を鳴らす")
                $0.value = GlobalDataSingleton.getInstance().isPageTurningSoundEnabled()
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setPageTurningSoundIsEnabled(row.value!)
                })
            <<< SwitchRow() {
                $0.title = NSLocalizedString("SettingTableViewController_IgnoreURISpeechIsEnabled", comment: "URIを読み上げないようにする")
                $0.value = GlobalDataSingleton.getInstance().getIsIgnoreURIStringSpeechEnabled()
                $0.cell.textLabel?.numberOfLines = 0
                }.onChange({ (row) in
                    GlobalDataSingleton.getInstance().setIgnoreURIStringSpeechIsEnabled(row.value!)
                })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_AddDefaultCorrectionOfTheReading", comment:"標準の読みの修正を上書き追加")
                }.onCellSelection({ (butonCellof, buttonRow) in
                    self.ConfirmAddDefaultSpeechModSetting()
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
                        UIApplication.shared.openURL(url)
                    }
                })
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_SendBugReport", comment: "不都合報告をmailで開発者に送る")
                $0.presentationMode = .segueName(segueName: "BugReportViewSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_GoToReleaseLog", comment:"更新履歴")
                $0.presentationMode = .segueName(segueName: "updateLogSegue", onDismiss: nil)
            }
            
            <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_RightNotation", comment:"権利表記")
                $0.presentationMode = .segueName(segueName: "CreditPageSegue", onDismiss: nil)
            }
        
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
                $0.value = GlobalDataSingleton.getInstance().getForceSiteInfoReloadIsEnabled()
                }.onChange({ row in
                    GlobalDataSingleton.getInstance().setForceSiteInfoReloadIsEnabled(row.value!)
                })
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
        m_NarouContentCacheData = GlobalDataSingleton.getInstance().createNewUserBookWithSaved()
        performSegue(withIdentifier: "CreateNewUserTextSegue", sender: self)
    }
    /// 標準で用意された読み上げ辞書を上書き追加します。
    func AddDefaultSpeechModSetting(){
        let globalData = GlobalDataSingleton.getInstance()
        globalData?.insertDefaultSpeechModConfig()
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
        picker.setMessageBody(NSLocalizedString("SettingTableView_SendEmailForBackupBody", comment:"添付されたファイルを ことせかい で読み込む事で、小説のリストが再生成されます。"), isHTML: false)
        picker.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        present(picker, animated: true, completion: nil)
        return true;
    }
    
    /// 現在の本棚にある小説のリストを再ダウンロードするためのURLを取得して、シェアします。
    func ShareNcodeListURLScheme(){
        let backupData = GlobalDataSingleton.getInstance().createBackupJSONData()
        if backupData == nil {
            return
        }
        // どうやら勝手に NSData から Data へ変換してくれているっぽい？
        //let backupData = Data.init(referencing: backupNSData)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "yyyyMMddHHmm"
        let dateString = dateFormatter.string(from: Date())
        let fileName = String.init(format: "%@.novelspeaker-backup-json", dateString)
        sendMailWithBinary(data: backupData!, fileName: fileName, mimeType: "application/octet-stream")
    }
    
    // MFMailComposeViewController でmailアプリ終了時に呼び出されるのでこのタイミングで viewController を取り戻します
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let identifier = segue.identifier {
            switch identifier {
            case "CreateNewUserTextSegue":
                if let userBookViewController:EditUserBookViewController = segue.destination as? EditUserBookViewController {
                    userBookViewController.narouContentDetail = self.m_NarouContentCacheData
                }
                break
            default:
                break
            }
        }
    }
}
