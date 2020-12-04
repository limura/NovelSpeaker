//
//  AutoSplitStringSettingViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/09/21.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import Eureka
import RealmSwift

class AutoSplitStringSettingViewController: UITableViewController, RealmObserverResetDelegate {
    
    let defaultCellID = "AutoSplitStringSettingViewController_TableCellID"
    var globalDataNotificationToken:NotificationToken? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "AutoSplitStringSettingViewController viewDidLoad", data: [:])
        
        // 追加ボタンとEditボタンと検索ボタンをつけます。
        let addButton = UIBarButtonItem.init(barButtonSystemItem: UIBarButtonItem.SystemItem.add, target: self, action: #selector(AutoSplitStringSettingViewController.addButtonClicked))
        navigationItem.rightBarButtonItems = [self.editButtonItem, addButton]
        self.tableView.isEditing = false
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: defaultCellID)
        self.title = NSLocalizedString("AutoSplitStringSettingViewController_Title", comment: "テキスト分割文字列の設定")
        
        registerObserver()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    func StopObservers(){
        globalDataNotificationToken = nil
    }
    func RestartObservers(){
        StopObservers()
        registerObserver()
    }
    
    func registerObserver() {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalData = RealmGlobalState.GetInstanceWith(realm: realm) {
                self.globalDataNotificationToken = globalData.observe({ (change) in
                    switch change {
                    case .change(_, let propertys):
                        for property in propertys {
                            if property.name == "autoSplitStringList" {
                                DispatchQueue.main.async {
                                    self.tableView.reloadData()
                                }
                                return
                            }
                        }
                    case .deleted:
                        break
                    default:
                        break
                    }
                })
            }
        }
    }
    
    func GetSplitTextFromIndexPath(path:Int) -> String? {
        return RealmUtil.RealmBlock { (realm) -> String? in
            guard let targetList = RealmGlobalState.GetInstanceWith(realm: realm)?.autoSplitStringList, targetList.count > path else {
                return nil
            }
            return targetList[path]
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return RealmUtil.RealmBlock { (realm) -> Int in
            return RealmGlobalState.GetInstanceWith(realm: realm)?.autoSplitStringList.count ?? 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: defaultCellID, for: indexPath)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        if let text = GetSplitTextFromIndexPath(path: indexPath.row) {
            cell.textLabel?.text = text.replacingOccurrences(of: "\n", with: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"))
        }else{
            cell.textLabel?.text = "-"
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .delete
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            RealmUtil.RealmBlock { (realm) in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm), globalState.autoSplitStringList.count > indexPath.row else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalDataNotificationToken]) { (realm) in
                    globalState.autoSplitStringList.remove(at: indexPath.row)
                }
            }
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
    
    func assignNewSplitString(text:String) {
        let text = text.replacingOccurrences(of: NSLocalizedString("SpeechWaitConfigTableView_TargetText_Enter", comment: "<改行>"), with: "\n")
        if text.count <= 0 {
            NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("AutoSplitStringSettingViewController_AddSplitTargetDialog_Error_NoText", comment: "空文字列は指定できません"), buttonTitle: nil) {
                self.addButtonClicked()
            }
            return
        }
        
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                return
            }
            if globalState.autoSplitStringList.contains(text) {
                NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("AutoSplitStringSettingViewController_AddSplitTargetDialog_AlreadyAssigned", comment: "既に存在する設定です"), buttonTitle: nil) {
                    self.addButtonClicked()
                }
                return
            }
            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalDataNotificationToken]) { (realm) in
                globalState.autoSplitStringList.append(text)
            }
        }
        self.tableView.reloadData()
    }
    
    @objc func addButtonClicked(){
        DispatchQueue.main.async {
            NiftyUtility.EasyDialogBuilder(self)
            .title(title: NSLocalizedString("AutoSplitStringSettingViewController_AddSplitTargetDialog_Title", comment: "分割対象文字の追加"))
            .textField(tag: 100, placeholder: NSLocalizedString("AutoSplitStringSettingViewController_AddSplitTargetDialog_PlaceHolder", comment: "改行を表現するには <改行> と入力します"), content: nil, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .roundedRect, clearButtonMode: .always) { (dialog) -> (Void) in
                let text:String
                if let textField = dialog.view.viewWithTag(100) as? UITextField {
                    text = textField.text ?? ""
                }else{
                    text = ""
                }
                dialog.dismiss(animated: false) {
                    self.assignNewSplitString(text: text)
                }
            }
            .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel")) { (dialog) in
                    dialog.dismiss(animated: false, completion: nil)
                }
            .addButton(title: NSLocalizedString("AutoSplitStringSettingViewController_AddSplitTargetDialog_EnterButton", comment: "追加")) { (dialog) in
                let text:String
                if let textField = dialog.view.viewWithTag(100) as? UITextField {
                    text = textField.text ?? ""
                }else{
                    text = ""
                }
                dialog.dismiss(animated: false) {
                    self.assignNewSplitString(text: text)
                }
            }.build().show()
        }
    }
    
    @objc func editButtonClicked(sender: UIBarButtonItem) {
        tableView.setEditing(!tableView.isEditing, animated: true)
        print("editButtonClicked.")
    }
}
