//
//  SpeechModTableViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/10.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit

class SpeechModSettingsTableViewControllerSwift: UITableViewController, CreateNewSpeechModSettingDelegate {
    let m_Speaker = Speaker()
    static let speechModSettingsTableViewDefaultCellID = "speechModSettingsTableViewDefaultCell"
    var m_FilterString = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "SpeechModSettingsTableViewControllerSwift viewDidLoad", data: [:])

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        m_Speaker.setVoiceWithIdentifier(GlobalDataSingleton.getInstance().getVoiceIdentifier())
        
        // 追加ボタンとEditボタンと検索ボタンをつけます。
        let addButton = UIBarButtonItem.init(barButtonSystemItem: UIBarButtonSystemItem.add, target: self, action: #selector(SpeechModSettingsTableViewControllerSwift.addButtonClicked))
        let filterButton = UIBarButtonItem.init(barButtonSystemItem: UIBarButtonSystemItem.search, target: self, action: #selector(SpeechModSettingsTableViewControllerSwift.filterButtonClicked))
        navigationItem.rightBarButtonItems = [addButton, editButtonItem, filterButton]
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        let speechModSettingArray = GetSpeechModArray()
        return (speechModSettingArray.count);
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: SpeechModSettingsTableViewControllerSwift.speechModSettingsTableViewDefaultCellID, for: indexPath)

        if cell == nil {
            cell = UITableViewCell.init(style: UITableViewCellStyle.default, reuseIdentifier: SpeechModSettingsTableViewControllerSwift.speechModSettingsTableViewDefaultCellID)
        }

        let modSetting = GetSpeechModSettingFromRow(row: indexPath.row)
        if modSetting == nil {
            cell.textLabel?.text = "-"
        }else{
            cell.textLabel?.text = String(format: NSLocalizedString("SpeechModSettingsTableViewController_DisplayPattern", comment:"\"%@\" を \"%@\" に"), (modSetting?.beforeString)!, (modSetting?.afterString)!)
        }
        return cell
    }

    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }

    // スワイプでは削除させない
    // from http://codingcafe.jp/uitableview%E3%81%A7%E3%82%B9%E3%83%AF%E3%82%A4%E3%83%97%E5%89%8A%E9%99%A4%E3%82%92%E7%84%A1%E5%8A%B9%E3%81%AB/
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        if self.isEditing {
            return UITableViewCellEditingStyle.delete
        }else{
            return UITableViewCellEditingStyle.none
        }
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            let modSetting = GetSpeechModSettingFromRow(row: indexPath.row)
            if modSetting != nil {
                GlobalDataSingleton.getInstance().deleteSpeechModSetting(modSetting)
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }

    // セルが選択された時
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let modSetting = GetSpeechModSettingFromRow(row: indexPath.row)
        if modSetting == nil {
            return;
        }
        let sampleText = String(format: NSLocalizedString("SpeechModSettingsTableViewController_SpeakTestPattern", comment:"%@を%@に"), (modSetting?.beforeString)!, (modSetting?.afterString)!)
        m_Speaker.speech(sampleText)
    }

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "newSpeechSettingSegue" {
            let controller:CreateSpeechModSettingViewController = segue.destination as! CreateSpeechModSettingViewController
            controller.createNewSpeechModSettingDelegate = self;
        }
    }

    @objc func addButtonClicked(){
        performSegue(withIdentifier: "newSpeechSettingSegue", sender: self)
    }
    
    @objc func filterButtonClicked(){
        EasyDialog.Builder(self)
            .title(title: NSLocalizedString("SpeechModSettingsTableView_SearchTitle", comment: "検索"))
            .textField(tag: 100, placeholder: NSLocalizedString("SpeechModSettingsTableView_SearchPlaceholder", comment: "検索対象の文字列を入力します"), content: m_FilterString, keyboardType: UIKeyboardType.default, secure: false, focusKeyboard: true)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                let filterTextField = dialog.view.viewWithTag(100) as! UITextField
                let newFilterString = filterTextField.text ?? ""
                self.m_FilterString = newFilterString
                self.tableView.reloadData()
                DispatchQueue.main.async {
                    dialog.dismiss(animated: true, completion: nil)
                }
                })
            .build().show()
    }
    
    func GetSpeechModArray() -> [SpeechModSettingCacheData] {
        let speechModSettingArray = GlobalDataSingleton.getInstance().getAllSpeechModSettings()
        var result:[SpeechModSettingCacheData] = []
        for speechMod:SpeechModSettingCacheData in speechModSettingArray! as! [SpeechModSettingCacheData] {
            if m_FilterString.count > 0 && (!speechMod.beforeString.contains(m_FilterString)) && (!speechMod.afterString.contains(m_FilterString)) {
                continue
            }
            result.append(speechMod)
        }
        return result
    }
    
    func GetSpeechModSettingFromRow(row:Int) -> SpeechModSettingCacheData? {
        let speechModSettingArray = GetSpeechModArray()
        if speechModSettingArray.count <= row {
            return nil;
        }
        return speechModSettingArray[row]
    }
    
    @objc func newSpeechModSettingAdded(){
        tableView.reloadData()
    }
}
