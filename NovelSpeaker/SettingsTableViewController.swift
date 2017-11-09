//
//  SettingsTableViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/09.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import MessageUI

class SettingsTableViewControllerSwift: UITableViewController, MFMailComposeViewControllerDelegate {
    static let SettingsTableViewDefaultCellID = "SettingsTableViewCellDefault"

    @IBOutlet var settingsTableView: UITableView!
    var m_NarouContentCacheData:NarouContentCacheData? = nil;

    override func viewDidLoad() {
        super.viewDidLoad()

        let maxSpeechTimeTableViewCellNib = UINib.init(nibName: MaxSpeechTimeTableViewCellID, bundle: nil)
        tableView.register(maxSpeechTimeTableViewCellNib, forCellReuseIdentifier: MaxSpeechTimeTableViewCellID)
        
        GlobalDataSingleton.getInstance().reloadSpeechSetting();
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - TableView data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 12 // + 1 // USE_LOG_VIEW
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        //UITableViewCell* cell = [self tableView:tableView cellForRowAtIndexPath:indexPath];
        let cell:UITableViewCell? = nil;
        if (cell == nil) {
            switch (indexPath.row) {
            case 0: fallthrough
            case 1: fallthrough
            case 2: fallthrough
            case 3: fallthrough
            case 5: fallthrough
            case 6: fallthrough
            case 7: fallthrough
            case 8: fallthrough
            case 9: fallthrough
            case 10: fallthrough
            case 11: fallthrough
            case 12: // ifdef USE_LOG_VIEW
                return 40.0;
            case 4:
                return 220.0;
            default:
                break;
            }
            return 31.0;
        }
        return (cell?.frame.size.height)!;
    }
    
    func GetDefaultTableView(tableView: UITableView!, cellForRowAtIndexPath indexPath:IndexPath) -> UITableViewCell {
        var cell:UITableViewCell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewControllerSwift.SettingsTableViewDefaultCellID, for: indexPath)
        if cell == nil {
            cell = UITableViewCell.init(style: UITableViewCellStyle.default, reuseIdentifier: SettingsTableViewControllerSwift.SettingsTableViewDefaultCellID)
        }
        cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
        
        switch(indexPath.row)
        {
        case 0:
            cell.textLabel?.text =
                NSLocalizedString("SettingsTableViewController_SettingOfTheQualityOfVoice", comment:"声質の設定");
            break;
        case 1:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_CorrectionOfTheReading", comment:"読みの修正");
            break;
        case 2:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_SettingOfTheTextSize", comment:"文字サイズの設定");
            break;
        case 3:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_SettingOfTheSpeechDelay", comment:"読み上げ時の間の設定");
            break;
        case 5:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_CreateNewUserText", comment:"新規自作本の追加");
            break;
        case 6:
            cell.textLabel?.text = GlobalDataSingleton.getInstance().getBackgroundNovelFetchEnabled() ?
                NSLocalizedString("SettingTableViewController_BackgroundFetch_Enabled", comment:"新規小説の自動ダウンロード: 有効")
                : NSLocalizedString("SettingTableViewController_BackgroundFetch_Disabled", comment:"新規小説のダウンロード: 無効");
            break;
        case 7:
            cell.textLabel?.text = GlobalDataSingleton.getInstance().getOverrideRubyIsEnabled() ?
                NSLocalizedString("SettingTableViewController_OverrideRubyIsEnabled", comment:"小説家になろうタイプのルビをルビだけよむようにする：有効")
                : NSLocalizedString("SettingTableViewController_OverrideRubyIsDisabled", comment:"小説家になろうタイプのルビをルビだけよむようにする：無効");
            break;
        case 8:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_AddDefaultCorrectionOfTheReading", comment:"標準の読みの修正を上書き追加");
            break;
        case 9:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_GetNcodeDownloadURLScheme", comment:"再ダウンロード用URLスキームの取得");
            break;
        case 10:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_GoToReleaseLog", comment:"更新履歴");
            break;
        case 11:
            cell.textLabel?.text = NSLocalizedString("SettingTableViewController_RightNotation", comment:"権利表記");
            break;
        case 12: // USE_LOG_VIEW
            cell.textLabel?.text = "debug log";
            break;
        default:
            cell.textLabel?.text = "-";
            break;
        }

        return cell;
    }
    
    func GetMaxSpeechTimeTableView(tableView:UITableView, cellForRowAtIndexPath:IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: MaxSpeechTimeTableViewCellID, for: cellForRowAtIndexPath)
        if cell != nil {
            return cell
        }
        cell = MaxSpeechTimeTableViewCell.init(style: UITableViewCellStyle.default, reuseIdentifier: MaxSpeechTimeTableViewCellID)
        return cell
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch (indexPath.row) {
        case 0: fallthrough
        case 1: fallthrough
        case 2: fallthrough
        case 3: fallthrough
        case 5: fallthrough
        case 6: fallthrough
        case 7: fallthrough
        case 8: fallthrough
        case 9: fallthrough
        case 10: fallthrough
        case 11:
            return GetDefaultTableView(tableView: tableView, cellForRowAtIndexPath:indexPath)
        case 12: // #ifdef USE_LOG_VIEW
            return GetDefaultTableView(tableView: tableView, cellForRowAtIndexPath:indexPath)
        case 4:
            return GetMaxSpeechTimeTableView(tableView: tableView, cellForRowAtIndexPath: indexPath)
        default:
            break
        }
        return GetDefaultTableView(tableView: tableView, cellForRowAtIndexPath:indexPath)
    }

    /// 標準で用意された読み上げ辞書を上書き追加します。
    func AddDefaultSpeechModSetting(){
        let globalData = GlobalDataSingleton.getInstance()
        globalData?.insertDefaultSpeechModConfig()
        EasyDialog.Builder(self)
            .title(title: NSLocalizedString("SettingTableViewController_AnAddressAddedAStandardParaphrasingDictionary", comment: "標準の読み替え辞書を上書き追加しました。"))
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: {dialog in
                dialog.dismiss(animated: true)
            })
            .build().show()
    }

    /// 標準で用意された読み上げ辞書で上書きして良いか確認した上で、上書き追加します。
    func ConfirmAddDefaultSpeechModSetting(){
        EasyDialog.Builder(self)
            .title(title: NSLocalizedString("SettingTableViewController_ConfirmAddDefaultSpeechModSetting", comment:"確認"))
            .label(text: NSLocalizedString("SettingtableViewController_ConfirmAddDefaultSpeechModSettingMessage", comment:"用意された読み替え辞書を追加・上書きします。よろしいですか？"))
            .addButton(title: NSLocalizedString("Cancel_button", comment:"Cancel"), callback: { dialog in
                dialog.dismiss(animated: true)
            })
            .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                self.AddDefaultSpeechModSetting()
                dialog.dismiss(animated: true, completion: nil)
            })
            .build().show()
    }
    
    /// ルビが振られたものについて、読み上げられない文字を登録するダイアログを表示します。
    func EditNotRubyString(){
        let currentSettingString = GlobalDataSingleton.getInstance().getNotRubyCharactorStringArray()
        EasyDialog.Builder(self)
            .title(title: NSLocalizedString("SettingTableViewController_EditNotRubyStringTitle", comment: "ルビでないと判断する文字集合"))
            .label(text: NSLocalizedString("SettingTableViewController_EditNotRubyStringHint", comment: "ここに書かれた文字のみのルビであればただの強調であると判断され、ルビではなく元の文字が読み上げられる事になります"))
            .textField(tag: 100, placeholder: NSLocalizedString("SettingTableViewController_EditNotRubyStringPlaceHolder", comment: "・"), content: currentSettingString ?? "・", keyboardType: UIKeyboardType.default, secure: false)
            .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { dialog in
                dialog.dismiss(animated: true)
            })
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                let newEntryTextField = dialog.view.viewWithTag(100) as! UITextField
                let newData = newEntryTextField.text ?? ""
                GlobalDataSingleton.getInstance().setNotRubyCharactorStringArray(newData)
                dialog.dismiss(animated: true)
            })
            .build().show()
    }

    /// ルビがふられた物について、ルビだけを読み上げるかどうかを確認します
    func RubyOverrideSettingToggle(){
        if let globalData = GlobalDataSingleton.getInstance() {
            if globalData.getOverrideRubyIsEnabled() {
                globalData.setOverrideRubyIsEnabled(false)
            }else{
                EditNotRubyString()
                globalData.setOverrideRubyIsEnabled(true)
            }
        }
        settingsTableView.reloadData()
    }

    /// BackgroundFetch で小説の更新分を取得するか否かの設定をトグルします。
    func BackgroundNovelFetchSettingToggle(){
        let globalData = GlobalDataSingleton.getInstance()!
        let application = UIApplication.shared
        let isEnabled = globalData.getBackgroundNovelFetchEnabled()
        if isEnabled {
            // TODO: ロジックが入ってる
            globalData.updateBackgroundNovelFetchMode(false)
            application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalNever)
            self.settingsTableView.reloadData()
        }else{
            EasyDialog.Builder(self)
                .title(title: NSLocalizedString("SettingTableViewController_ConfirmEnableBackgroundFetch_title", comment:"確認"))
                .label(text: NSLocalizedString("SettingtableViewController_ConfirmEnableBackgroundFetch", comment:"この設定を有効にすると、ことせかい を使用していない時等に小説の更新を確認するようになるため、ネットワーク通信が発生するようになります。よろしいですか？"))
                .addButton(title: NSLocalizedString("Cancel_button", comment: "cancel"), callback: { dialog in
                    dialog.dismiss(animated: true, completion: nil)
                })
                .addButton(title: NSLocalizedString("OK_button", comment:"OK"), callback: {dialog in
                    // TODO: ロジックが入ってる
                    globalData.updateBackgroundNovelFetchMode(true)
                    globalData.registerUserNotification()
                    globalData.startBackgroundFetch()
                    self.settingsTableView.reloadData()
                    dialog.dismiss(animated: true)
                })
                .build().show()
        }
    }
    // MFMailComposeViewController でmailアプリ終了時に呼び出されるのでこのタイミングで viewController を取り戻します
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true, completion: nil)
    }

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
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "yyyyMMddHHmm", options: 0, locale: Locale.current)
        let dateString = dateFormatter.string(from: Date())
        let fileName = String.init(format: "%@.novelspeaker-backup-json", dateString)
        sendMailWithBinary(data: backupData!, fileName: fileName, mimeType: "application/octet-stream")
    }

    // 新規のユーザ本を追加して、編集ページに遷移する
    func CreateNewUserText(){
        m_NarouContentCacheData = GlobalDataSingleton.getInstance().createNewUserBook()
        performSegue(withIdentifier: "CreateNewUserTextSegue", sender: self)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch (indexPath.row) {
        case 0:
            performSegue(withIdentifier: "speakSettingsSegue", sender: self)
            break;
        case 1:
            performSegue(withIdentifier: "speechModSettingSegue", sender: self)
            break;
        case 2:
            performSegue(withIdentifier: "textSizeSettingSegue", sender: self)
            break;
        case 3:
            performSegue(withIdentifier: "textDelaySettingSegue", sender: self)
            break;
        case 5:
            CreateNewUserText()
            break;
        case 6:
            BackgroundNovelFetchSettingToggle()
            break;
        case 7:
            RubyOverrideSettingToggle()
            break;
        case 8:
            ConfirmAddDefaultSpeechModSetting()
            break;
        case 9:
            ShareNcodeListURLScheme()
            break;
        case 10:
            performSegue(withIdentifier: "updateLogSegue", sender: self)
            break;
        case 11:
            performSegue(withIdentifier: "CreditPageSegue", sender: self)
            break;
        case 12: // ifdef USE_LOG_VIEW
            performSegue(withIdentifier: "debugLogViewSegue", sender: self)
            break;
        default:
            break;
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "CreateNewUserTextSegue" {
            let nextViewController:EditUserBookViewController = segue.destination as! EditUserBookViewController
            nextViewController.narouContentDetail = m_NarouContentCacheData;
        }
    }

}
