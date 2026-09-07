//
//  SpeechModTableViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/10.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class SpeechModSettingsTableViewControllerSwift: UITableViewController, RealmObserverResetDelegate {
    static let speechModSettingsTableViewDefaultCellID = "speechModSettingsTableViewDefaultCell"
    private enum SpeechEngineFilter: Equatable {
        case all
        case system
        case voicevox
    }

    var m_FilterString = ""
    private var m_FilterSpeechEngine: SpeechEngineFilter = .all
    var speechModSettingObserverToken:NotificationToken? = nil
    public var targetNovelID = RealmSpeechModSetting.anyTarget

    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "SpeechModSettingsTableViewControllerSwift viewDidLoad", data: [:])

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        if self.targetNovelID != RealmSpeechModSetting.anyTarget {
            self.title = NSLocalizedString("SpeechModSettingsTableViewControllerSwift_ThisNovelOnly", comment: "読みの修正(小説専用設定)")
        }
        
        // 追加・編集・検索は常に表示し、音声エンジンの絞り込みだけを
        // フィルタアイコンのメニューへまとめる。検索が見た目から消えないようにする。
        let addButton = UIBarButtonItem.init(barButtonSystemItem: UIBarButtonItem.SystemItem.add, target: self, action: #selector(SpeechModSettingsTableViewControllerSwift.addButtonClicked))
        let searchButton = UIBarButtonItem(
            barButtonSystemItem: .search,
            target: self,
            action: #selector(SpeechModSettingsTableViewControllerSwift.filterButtonClicked))
        let engineFilterButton = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: nil,
            action: nil)
        engineFilterButton.accessibilityLabel = NSLocalizedString("SpeechModSettingsTableView_FilterMenu", comment: "適用する音声合成で絞り込む")
        engineFilterButton.accessibilityValue = speechEngineFilterAccessibilityValue()
        engineFilterButton.menu = makeEngineFilterMenu()
        navigationItem.rightBarButtonItems = [addButton, .fixedSpace(0), editButtonItem, .fixedSpace(0), searchButton, .fixedSpace(0), engineFilterButton]
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        addNotificationReceiver()
        self.tableView.reloadData()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func StopObservers() {
        removeNotificationReceiver()
    }
    func RestartObservers() {
        StopObservers()
        addNotificationReceiver()
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
    
    func addNotificationReceiver(){
        RealmUtil.RealmBlock { (realm) -> Void in
            self.speechModSettingObserverToken = realm.objects(RealmSpeechModSetting.self).observe { [weak self] (collectionChange) in
                guard let self = self else { return }
                print("RealmSpeechModSetting change got.")
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
    }
    func removeNotificationReceiver(){
        self.speechModSettingObserverToken = nil
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return RealmUtil.RealmBlock { (realm) -> Int in
            if let speechModSettingArray = GetSpeechModArrayWith(realm: realm) {
                return (speechModSettingArray.count);
            }
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SpeechModSettingsTableViewControllerSwift.speechModSettingsTableViewDefaultCellID, for: indexPath)

        /*
        if cell == nil {
            cell = UITableViewCell.init(style: UITableViewCell.CellStyle.default, reuseIdentifier: SpeechModSettingsTableViewControllerSwift.speechModSettingsTableViewDefaultCellID)
        }
        */

        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        RealmUtil.RealmBlock { (realm) -> Void in
            let modSetting = GetSpeechModSettingFromRowWith(realm: realm, row: indexPath.row)
            if modSetting == nil {
                cell.textLabel?.text = "-"
            }else{
                cell.textLabel?.text = String(format: NSLocalizedString("SpeechModSettingsTableViewController_DisplayPattern", comment:"\"%@\" を \"%@\" に"), (modSetting?.before)!, (modSetting?.after)!)
            }
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
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if self.isEditing {
            return UITableViewCell.EditingStyle.delete
        }else{
            return UITableViewCell.EditingStyle.none
        }
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            RealmUtil.RealmBlock { (realm) -> Void in
                if let modSetting = GetSpeechModSettingFromRowWith(realm: realm, row: indexPath.row) {
                    if let targetModSetting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: modSetting.before) {
                        RealmUtil.WriteWith(realm: realm) { (realm)  in
                            targetModSetting.delete(realm: realm)
                        }
                    }
                }
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }

    // セルが選択された時
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let modSetting = GetSpeechModSettingFromRowWith(realm: realm, row: indexPath.row) {
                PushToCreateSpeechModSettingViewControllerSwift(modSetting: modSetting)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
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
    //override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    //}

    @objc func addButtonClicked(){
        PushToCreateSpeechModSettingViewControllerSwift(modSetting: nil)
    }
    
    @objc func filterButtonClicked(){
        NiftyUtility.EasyDialogBuilder(self)
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

    private func makeEngineFilterMenu() -> UIMenu {
        let allAction = UIAction(
            title: NSLocalizedString("SpeechModSettingsTableView_FilterAll", comment: "すべて"),
            state: m_FilterSpeechEngine == .all ? .on : .off) { [weak self] _ in
                self?.setSpeechEngineFilter(.all)
            }
        let systemAction = UIAction(
            title: NSLocalizedString("SpeechModSettingsTableView_FilterSystem", comment: "システムの音声"),
            state: m_FilterSpeechEngine == .system ? .on : .off) { [weak self] _ in
                self?.setSpeechEngineFilter(.system)
            }
        let voicevoxAction = UIAction(
            title: NSLocalizedString("SpeechModSettingsTableView_FilterVoicevox", comment: "VOICEVOX"),
            state: m_FilterSpeechEngine == .voicevox ? .on : .off) { [weak self] _ in
                self?.setSpeechEngineFilter(.voicevox)
            }
        let engineMenu = UIMenu(
            title: NSLocalizedString("SpeechModSettingsTableView_FilterMenu", comment: "適用する音声合成で絞り込む"),
            options: .displayInline,
            children: [allAction, systemAction, voicevoxAction])
        return UIMenu(children: [engineMenu])
    }

    private func setSpeechEngineFilter(_ filter: SpeechEngineFilter) {
        m_FilterSpeechEngine = filter
        if let engineFilterButton = navigationItem.rightBarButtonItems?.last {
            engineFilterButton.menu = makeEngineFilterMenu()
            engineFilterButton.accessibilityValue = speechEngineFilterAccessibilityValue()
        }
        tableView.reloadData()
    }

    private func speechEngineFilterAccessibilityValue() -> String {
        switch m_FilterSpeechEngine {
        case .all:
            return NSLocalizedString("SpeechModSettingsTableView_FilterAll", comment: "すべて")
        case .system:
            return NSLocalizedString("SpeechModSettingsTableView_FilterSystem", comment: "システムの音声")
        case .voicevox:
            return NSLocalizedString("SpeechModSettingsTableView_FilterVoicevox", comment: "VOICEVOX")
        }
    }
    
    func PushToCreateSpeechModSettingViewControllerSwift(modSetting:RealmSpeechModSetting?) {
        let nextViewController = CreateSpeechModSettingViewControllerSwift()
        nextViewController.targetSpeechModSettingBeforeString = modSetting?.before
        nextViewController.isUseAnyNovelID = self.targetNovelID == RealmSpeechModSetting.anyTarget ? true : false
        if (modSetting?.targetNovelIDArray.count ?? 0) == 0 {
            nextViewController.targetNovelID = self.targetNovelID
        }
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }
    
    func GetSpeechModArrayWith(realm: Realm) -> LazyFilterSequence<Results<RealmSpeechModSetting>>? {
        guard var speechModSettingArray = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return nil }
        if m_FilterString.count > 0 {
            speechModSettingArray = speechModSettingArray.filter("( before CONTAINS %@ OR after CONTAINS %@ )", m_FilterString, m_FilterString)
        }
        speechModSettingArray = speechModSettingArray.sorted(byKeyPath: "before", ascending: false)
        let targetNovelID = self.targetNovelID
        let targetAnyNovel = targetNovelID == RealmSpeechModSetting.anyTarget || targetNovelID.isEmpty
        let speechEngineFilter = m_FilterSpeechEngine
        let defaultSpeechModEngineTypes = NovelSpeakerUtility.GetDefaultSpeechModEngineTypes()
        return speechModSettingArray.filter({ (setting) -> Bool in
            let targetMatches = targetAnyNovel || setting.targetNovelIDArray.contains(targetNovelID)
            guard targetMatches else { return false }
            switch speechEngineFilter {
            case .all:
                return true
            case .system:
                let effective = NovelSpeakerUtility.EffectiveSpeechEngineTypes(
                    of: setting, defaultSpeechModEngineTypes: defaultSpeechModEngineTypes)
                return effective.isEmpty || effective.contains(.any) || effective.contains(.avSpeechSynthesizer)
            case .voicevox:
                let effective = NovelSpeakerUtility.EffectiveSpeechEngineTypes(
                    of: setting, defaultSpeechModEngineTypes: defaultSpeechModEngineTypes)
                return effective.isEmpty || effective.contains(.any) || effective.contains(.voicevox)
            }
        })
    }
    
    func GetSpeechModSettingFromRowWith(realm: Realm, row:Int) -> RealmSpeechModSetting? {
        guard let speechModSettingArray = GetSpeechModArrayWith(realm: realm) else { return nil }
        let array = Array(speechModSettingArray)
        if array.count <= row {
            return nil;
        }
        return array[row]
    }
}
