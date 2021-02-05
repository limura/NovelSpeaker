//
//  NovelDetailViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/02.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class NovelDetailViewController: FormViewController, RealmObserverResetDelegate {
    public var novelID = ""
    var speakerSettingObserverToken:NotificationToken? = nil
    var speechSectionConfigObserverToken:NotificationToken? = nil
    var novelObserverToken:NotificationToken? = nil
    var tagObserverToken:NotificationToken? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("NovelDetailViewController_PageTitle", comment: "小説の詳細")
        createCells()
        observeNovel()
        observeSpeakerSetting()
        observeSpeechSectionConfig()
        observeTag()
        registNotificationCenter()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    func StopObservers() {
        speakerSettingObserverToken = nil
        speechSectionConfigObserverToken = nil
        novelObserverToken = nil
        tagObserverToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeNovel()
        observeSpeakerSetting()
        observeSpeechSectionConfig()
        observeTag()
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

    func observeNovel() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID) else { return }
            self.novelObserverToken = novel.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        if property.name == "defaultSpeakerID", let newValue = property.newValue as? String, let oldValue = property.oldValue as? String, newValue != oldValue {
                            DispatchQueue.main.async {
                                self.form.removeAll()
                                self.createCells()
                            }
                            return
                        }
                        if ["writer", "title"].contains(property.name) {
                            DispatchQueue.main.async {
                                self.form.removeAll()
                                self.createCells()
                            }
                            return
                        }
                    }
                case .deleted:
                    DispatchQueue.main.async {
                        self.navigationController?.popViewController(animated: true)
                    }
                }
            })
        }
    }

    func observeSpeakerSetting() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let speakerSettingList = RealmSpeakerSetting.GetAllObjectsWith(realm: realm) else { return }
            self.speakerSettingObserverToken = speakerSettingList.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .initial(_):
                    break
                case .update(_, _, _, _):
                    DispatchQueue.main.async {
                        print("observeSpeakerSetting() reload all.")
                        self.form.removeAll()
                        self.createCells()
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    func observeSpeechSectionConfig() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let sectionConfigList = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) else { return }
            self.speechSectionConfigObserverToken = sectionConfigList.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .initial(_):
                    break
                case .update(_, _, _, _):
                    DispatchQueue.main.async {
                        print("observeSpeechSectionConfig() reload all.")
                        self.form.removeAll()
                        self.createCells()
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    func observeTag() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let tagList = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Keyword) else { return }
            self.tagObserverToken = tagList.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .initial(_):
                    break
                case .update(let objs, _, _, _):
                    for obj in objs {
                        if obj.targetNovelIDArray.contains(self.novelID) {
                            DispatchQueue.main.async {
                                guard let row = self.form.rowBy(tag: "TagsLabel") as? LabelRow else { return }
                                self.assignTagList(row: row)
                            }
                            break
                        }
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    func assignTagList(row:LabelRow) {
        var tagListText = ""
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let tags = RealmNovelTag.SearchWith(realm: realm, novelID: self.novelID, type: RealmNovelTag.TagType.Keyword) else {
                print("can not get tags")
                return
            }
            var tagNames = Set<String>()
            for tag in tags {
                tagNames.insert(tag.name)
            }
            tagListText = Array(tagNames).sorted().joined(separator: ", ")
        }
        row.value = tagListText
    }
    
    func openInWebImportTab(url:URL) {
        BookShelfRATreeViewController.LoadWebPageOnWebImportTab(url: url)
    }
    
    func createCells() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.RemoveRealmLink(), let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                form +++ Section()
                <<< LabelRow() {
                    $0.title = NSLocalizedString("NovelDetailViewController_NovelLoadFailed", comment: "小説情報の取得に失敗しました。")
                }
                return
            }
            let detailSection = Section(NSLocalizedString("NovelDetailViewController_DetailSectionTitle", comment: "概要"))
            detailSection <<< LabelRow("TitleLabel") {
                $0.title = NSLocalizedString("NovelDetailViewController_Title", comment: "小説名")
                $0.value = novel.title
            }.onCellSelection({ (cellOf, row) in
                UIPasteboard.general.string = novel.title.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    var dialog = NiftyUtility.EasyDialogBuilder(self)
                    dialog = dialog.title(title: NSLocalizedString("NovelDetailViewController_ActionSection_Title_PopupTitle", comment: "小説名をコピーしました"))
                    dialog = dialog.label(text: NSLocalizedString("NovelDetailViewController_ActionSection_Title_PopupMessage", comment: "小説名を変更する事もできます。"))
                    dialog = dialog.textField(tag: 100, placeholder: nil, content: novel.title, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .none, clearButtonMode: .always)
                    dialog = dialog.addButton(title: NSLocalizedString("NovelDetailViewController_ActionSection_Title_Popup_Cancel", comment: "変更しない")) { (dialog) in
                            dialog.dismiss(animated: false, completion: nil)
                        }
                    dialog = dialog.addButton(title: NSLocalizedString("NovelDetailViewController_ActionSection_Title_Popup_Edit", comment: "この名前に変更")) { (dialog) in
                        dialog.dismiss(animated: false, completion: {
                            if let filterTextField = dialog.view.viewWithTag(100) as? UITextField, let newString = filterTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), RealmUtil.RealmBlock(block: { (realm) -> Bool in
                                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novel.novelID) else { return false }
                                RealmUtil.WriteWith(realm: realm) { (realm) in
                                    novel.title = newString
                                    realm.add(novel)
                                }
                                return true
                            }) {
                                DispatchQueue.main.async {
                                    NiftyUtility.EasyDialogOneButton(viewController: self, title: NSLocalizedString("NovelDetailViewController_ActionSection_Title_Popup_Edit_Accepted", comment: "小説名を変更しました"), message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                            }else{
                                DispatchQueue.main.async {
                                    NiftyUtility.EasyDialogOneButton(viewController: self, title: NSLocalizedString("NovelDetailViewController_ActionSection_Title_Popup_Edit_Rejected", comment: "小説名の変更に失敗しました"), message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                            }
                        })
                    }
                    dialog.build().show()
                }
            })
            if novel.type == .URL {
                detailSection <<< LabelRow("WriterLabel") {
                    $0.title = NSLocalizedString("NovelDetailViewController_Writer", comment: "著者")
                    $0.value = novel.writer
                }.onCellSelection({ (cellOf, row) in
                    UIPasteboard.general.string = novel.writer.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        var dialog = NiftyUtility.EasyDialogBuilder(self)
                        dialog = dialog.title(title: NSLocalizedString("NovelDetailViewController_ActionSection_Writer_PopupTitle", comment: "著者名をコピーしました"))
                        dialog = dialog.label(text: NSLocalizedString("NovelDetailViewController_ActionSection_Writer_PopupMessage", comment: "著者名を変更する事もできます。"))
                        dialog = dialog.textField(tag: 100, placeholder: nil, content: novel.writer, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .none, clearButtonMode: .always)
                        dialog = dialog.addButton(title: NSLocalizedString("NovelDetailViewController_ActionSection_Writer_Popup_Cancel", comment: "変更しない")) { (dialog) in
                                dialog.dismiss(animated: false, completion: nil)
                            }
                        dialog = dialog.addButton(title: NSLocalizedString("NovelDetailViewController_ActionSection_Writer_Popup_Edit", comment: "この名前に変更")) { (dialog) in
                            dialog.dismiss(animated: false, completion: {
                                if let filterTextField = dialog.view.viewWithTag(100) as? UITextField, let newString = filterTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), RealmUtil.RealmBlock(block: { (realm) -> Bool in
                                    guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novel.novelID) else { return false }
                                    RealmUtil.WriteWith(realm: realm) { (realm) in
                                        novel.writer = newString
                                        realm.add(novel)
                                    }
                                    return true
                                }) {
                                    DispatchQueue.main.async {
                                        NiftyUtility.EasyDialogOneButton(viewController: self, title: NSLocalizedString("NovelDetailViewController_ActionSection_Writer_Popup_Edit_Accepted", comment: "著者名を変更しました"), message: nil, buttonTitle: nil, buttonAction: nil)
                                    }
                                }else{
                                    DispatchQueue.main.async {
                                        NiftyUtility.EasyDialogOneButton(viewController: self, title: NSLocalizedString("NovelDetailViewController_ActionSection_Writer_Popup_Edit_Rejected", comment: "著者名の変更に失敗しました"), message: nil, buttonTitle: nil, buttonAction: nil)
                                    }
                                }
                            })
                        }
                        dialog.build().show()
                    }
                })

                detailSection <<< LabelRow("URLLabel") {
                    $0.title = NSLocalizedString("NovelDetailViewController_URL", comment: "URL")
                    $0.value = novel.url
                    $0.cell.accessoryType = .disclosureIndicator
                }.onCellSelection({ (cellOf, row) in
                    guard let url = URL(string: novel.url) else { return }
                    self.openInWebImportTab(url: url)
                })
                
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let chapterNumber = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID)?.readingChapterNumber, let story = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: self.novelID, chapterNumber: chapterNumber), let url = URL(string: story.url) else { return }
                    detailSection <<< LabelRow() {
                        $0.title = NSLocalizedString("NovelDetailViewController_CurrentPage", comment: "現在開いているページ")
                        $0.value = story.url
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.accessoryType = .disclosureIndicator
                    }.onCellSelection({ (cellOf, row) in
                        self.openInWebImportTab(url: url)
                    })
                }
            }
            detailSection <<< LabelRow("TagsLabel") {
                $0.title = NSLocalizedString("NovelDetailViewController_Tags", comment: "タグ")
                $0.cell.accessoryType = .disclosureIndicator
                assignTagList(row: $0)
            }.onCellSelection({ (cellOf, row) in
                let nextViewController = NovelKeywordTagSelecterViewController()
                nextViewController.novelID = self.novelID
                self.navigationController?.pushViewController(nextViewController, animated: true)
            })
            self.form +++ detailSection
            
            let actionSection = Section(NSLocalizedString("NovelDetailViewController_ActionSectionTitle", comment: "この小説に対する操作"))
            
            actionSection <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_ActionSection_SearchButton_Title", comment: "この小説内を検索(何も入れずに検索すると章のリストを表示します)")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                DispatchQueue.main.async {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let chapterNumber = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID)?.readingChapterNumber else { return }
                        StorySpeaker.shared.StopSpeech(realm: realm)
                        NovelSpeakerUtility.SearchStoryFor(storyID: RealmStoryBulk.CreateUniqueBulkID(novelID: self.novelID, chapterNumber: chapterNumber), viewController: self) { (story) in
                            StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
                            self.navigationController?.popViewController(animated: true)
                        }
                    }
                }
            })

            if novel.type == .URL {
                actionSection <<< ButtonRow() {
                    $0.title = NSLocalizedString("NovelDetailViewController_ActionSection_CheckUpdate", comment: "この小説の更新確認を行う")
                    $0.cell.textLabel?.numberOfLines = 0
                    $0.cell.accessoryType = .disclosureIndicator
                }.onCellSelection({ (cellOf, row) in
                    NovelDownloadQueue.shared.addQueue(novelID: self.novelID)
                    DispatchQueue.main.async {
                        NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("NovelDetailViewController_ActionSection_CheckUpdateDone_Message", comment: "更新チェックを開始しました"), buttonTitle: nil, buttonAction: nil)
                    }
                })
            }

            actionSection <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_ActionSection_CreateBackupForThisNovelButton", comment: "この小説のバックアップを生成する")
            }.onCellSelection({ (cellOf, row) in
                DispatchQueue.main.async {
                    NovelSpeakerUtility.CreateNovelOnlyBackup(novelIDArray: [self.novelID], viewController: self) { (fileUrl, fileName) in
                        DispatchQueue.main.async {
                            let activityViewController = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
                            let frame = UIScreen.main.bounds
                            activityViewController.popoverPresentationController?.sourceView = self.view
                            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.width / 2 - 60, y: frame.size.height - 50, width: 120, height: 50)
                            self.present(activityViewController, animated: true, completion: nil)
                        }
                    }
                }
            })
            
            if novel.type == .URL {
                actionSection <<< ButtonRow() {
                    $0.title = NSLocalizedString("NovelDetailViewController_ActionSection_ShareButton", comment: "この小説のURLをシェアする")
                }.onCellSelection({ (cellOf, row) in
                    NovelSpeakerUtility.ShareStory(viewController: self, novelID: self.novelID, barButton: nil)
                })
            }
            
            actionSection <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_ActionSection_EditNovelButton", comment: "この小説を編集する")
            }.onCellSelection({ (cellOf, row) in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "EditUserTextSegue", sender: self)
                }
            })
            
            self.form +++ actionSection
            
            let settingSection = Section(NSLocalizedString("NovelDetailViewController_SettingSectionTitle", comment: "この小説専用の設定"))
            // isNeedSpeechAfterDelete
            if let speaker = novel.defaultSpeakerWith(realm: realm) {
                settingSection <<< AlertRow<String>("SpeakerAlertRow") { (row) -> Void in
                    row.title = NSLocalizedString("NovelDetailViewController_SpeakerAlertRowTitle", comment: "標準の話者")
                    row.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
                    row.selectorTitle = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerSelectorTitle", comment: "話者を選択してください")
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let speakerSettingArray = RealmSpeakerSetting.GetAllObjectsWith(realm: realm)?.sorted(byKeyPath: "createdDate", ascending: true) else { return }
                        row.options = speakerSettingArray.map({$0.name})
                    }
                    row.value = speaker.name
                }.onChange({ (row) in
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let targetName = row.value, let speaker = RealmSpeakerSetting.SearchFromWith(realm: realm, name: targetName), let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID) else {
                            return
                        }
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.speakerSettingObserverToken, self.speechSectionConfigObserverToken, self.novelObserverToken]) { (realm) in
                            novel.defaultSpeakerID = speaker.name
                        }
                    }
                })
            }
            settingSection <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingsViewController_SpeechModSettingsButtonTitle", comment:"話者変更設定(会話文等で声質を変えたりする設定)")
            }.onCellSelection({ (_, _) in
                let nextViewController = SpeechSectionConfigsViewController()
                nextViewController.targetNovelID = self.novelID
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })
            settingSection <<< ButtonRow() {
                $0.title = NSLocalizedString("SettingTableViewController_CorrectionOfTheReading", comment:"読みの修正")
                $0.presentationMode = .segueName(segueName: "speechModSettingSegue", onDismiss: nil)
            }
            settingSection <<< SwitchRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_NovelUpdateCheck_SwitchRowTitle", comment: "この小説の更新確認を行わない")
                $0.cell.textLabel?.numberOfLines = 0
                $0.value = RealmUtil.RealmBlock { (realm) -> Bool in
                    guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID) else { return false }
                    return novel.isNotNeedUpdateCheck
                }
            }.onChange({ (row) in
                guard let value = row.value else { return }
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID), novel.isNotNeedUpdateCheck != value else { return }
                    RealmUtil.WriteWith(realm: realm) { (realm) in
                        novel.isNotNeedUpdateCheck = value
                        realm.add(novel, update: .modified)
                    }
                }
            })
            /*
            settingSection <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_AddRubyToSpeechModButtonTitle", comment: "小説中に出てくるルビ表記をこの小説用の読みの修正に上書き追加する")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                let novelID = self.novelID
                var result:[String:String] = [:]
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let storys = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.linkedStorysWith(realm: realm) else {
                        DispatchQueue.main.async {
                            NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("NovelDetailViewController_CanNotGetNovelData", comment: "小説本文データの抽出に失敗しました。"))
                        }
                        return
                    }
                    for story in storys {
                        let rubyDictionary =  NiftyUtility.FindRubyNotation(text: story.content)
                        for (before, after) in rubyDictionary {
                            result[before] = after
                        }
                    }
                }
                if result.count <= 0 {
                    NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("NovelDetailViewController_RubyNotFound", comment: "有効なルビ表記を発見できませんでした。"))
                    return
                }
                var message = ""
                RealmUtil.Write(block: { (realm) in
                    for (before, after) in result {
                        if before.count <= 0 || after.count <= 0 { continue }
                        let modSetting = RealmSpeechModSetting()
                        modSetting.before = before
                        modSetting.after = after
                        modSetting.isUseRegularExpression = false
                        modSetting.targetNovelIDArray.append(novelID)
                        realm.add(modSetting, update: .modified)
                        message += "\(before) → \(after)\n"
                    }
                })
                DispatchQueue.main.async {
                    NiftyUtility.EasyDialogBuilder(self)
                    .title(title: NSLocalizedString("NovelDetailViewController_SpeechModAdded", comment: "この小説用に以下の読み替えを登録しました"))
                    .textView(content: message.trimmingCharacters(in: .whitespacesAndNewlines), heightMultiplier: 0.7)
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                        dialog.dismiss(animated: true, completion: nil)
                    }).build().show()
                }
            })
            */
            settingSection <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_AddToFolderButtonTitle", comment: "フォルダへ分類")
            }.onCellSelection({ (_, _) in
                let nextViewController = AssignNovelFolderViewController()
                nextViewController.targetNovelID = self.novelID
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }).cellUpdate({ (cell, button) in
                cell.textLabel?.textAlignment = .left
                cell.accessoryType = .disclosureIndicator
                cell.editingAccessoryType = cell.accessoryType
                cell.textLabel?.textColor = nil
            })
            settingSection <<< SwitchRow() { (row) in
                row.value = globalState.novelLikeOrder.contains(novelID)
                row.title = NSLocalizedString("NovelDetailViewController_LikeLevelSwitchRowTitle", comment: "お気に入り")
            }.onChange({ (row) in
                RealmUtil.Write(block: { (realm) in
                    guard let value = row.value, let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                    if value {
                        if globalState.novelLikeOrder.contains(self.novelID) == false {
                            globalState.novelLikeOrder.append(self.novelID)
                        }
                    }else{
                        if let index = globalState.novelLikeOrder.index(of: self.novelID) {
                            globalState.novelLikeOrder.remove(at: index)
                        }
                    }
                })
            })

            form +++ settingSection
        }
    }

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "EditUserTextSegue" {
            if let nextViewController = segue.destination as? EditBookViewController {
                nextViewController.targetNovelID = self.novelID
            }
        }else if segue.identifier == "speechModSettingSegue" {
            guard let nextViewController = segue.destination as? SpeechModSettingsTableViewControllerSwift, self.novelID.count > 0 else { return }
            nextViewController.targetNovelID = self.novelID
        }
    }
}
