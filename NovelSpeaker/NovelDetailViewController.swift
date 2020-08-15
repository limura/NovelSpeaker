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

class NovelDetailViewController: FormViewController {
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

    func observeNovel() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID) else { return }
            self.novelObserverToken = novel.observe({ (change) in
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        if property.name == "defaultSpeakerID", let newValue = property.newValue as? String, let oldValue = property.oldValue as? String, newValue != oldValue {
                            DispatchQueue.main.async {
                                print("defaultSpeakerID changed. observeNovel() reload all.")
                                self.form.removeAll()
                                self.createCells()
                            }
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
            self.speakerSettingObserverToken = speakerSettingList.observe({ (change) in
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
            self.speakerSettingObserverToken = sectionConfigList.observe({ (change) in
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
            self.tagObserverToken = tagList.observe({ (change) in
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
    
    func createCells() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.RemoveRealmLink() else {
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
            }
            if novel.type == .URL {
                detailSection <<< LabelRow("WriterLabel") {
                    $0.title = NSLocalizedString("NovelDetailViewController_Writer", comment: "著者")
                    $0.value = novel.writer
                }
                detailSection <<< LabelRow("URLLabel") {
                    $0.title = NSLocalizedString("NovelDetailViewController_URL", comment: "URL")
                    $0.value = novel.url
                    $0.cell.accessoryType = .disclosureIndicator
                }.onCellSelection({ (cellOf, row) in
                    DispatchQueue.main.async {
                        /// XXX 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
                        let targetTabIndex = 2
                        guard let viewController = self.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController, let url = URL(string: novel.url) else { return }
                        viewController.openTargetUrl = url
                        self.tabBarController?.selectedIndex = targetTabIndex
                    }
                })
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
            let settingSection = Section(NSLocalizedString("NovelDetailViewController_SettingSectionTitle", comment: "この小説専用の設定"))
            // novel.likeLevel
            // isNeedSpeechAfterDelete
            if let speaker = novel.defaultSpeaker {
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
            settingSection <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_AddRubyToSpeechModButtonTitle", comment: "小説中に出てくるルビ表記をこの小説用の読みの修正に上書き追加する")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ (cellOf, row) in
                let novelID = self.novelID
                var result:[String:String] = [:]
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let storys = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.linkedStorys else {
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("NovelDetailViewController_CanNotGetNovelData", comment: "小説本文データの抽出に失敗しました。"))
                        }
                        return
                    }
                    for story in storys {
                        let rubyDictionary =  NiftyUtilitySwift.FindRubyNotation(text: story.content)
                        for (before, after) in rubyDictionary {
                            result[before] = after
                        }
                    }
                }
                if result.count <= 0 {
                    NiftyUtilitySwift.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("NovelDetailViewController_RubyNotFound", comment: "有効なルビ表記を発見できませんでした。"))
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
                    NiftyUtilitySwift.EasyDialogBuilder(self)
                    .title(title: NSLocalizedString("NovelDetailViewController_SpeechModAdded", comment: "この小説用に以下の読み替えを登録しました"))
                    .textView(content: message.trimmingCharacters(in: .whitespacesAndNewlines), heightMultiplier: 0.7)
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                        dialog.dismiss(animated: true, completion: nil)
                    }).build().show()
                }
            })
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
            settingSection <<< CheckRow() {
                $0.title = NSLocalizedString("NovelDetailViewController_LikeLevelStepperRowTitle", comment: "お気に入り")
                $0.value = novel.likeLevel > 0
            }.onChange({ (row) in
                RealmUtil.Write(block: { (realm) in
                    guard let value = row.value, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.novelID) else { return }
                    if value {
                        novel.likeLevel = 1
                    }else{
                        novel.likeLevel = 0
                    }
                })
            })

            form +++ settingSection
        }
    }

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "speechModSettingSegue" {
            guard let nextViewController = segue.destination as? SpeechModSettingsTableViewControllerSwift, self.novelID.count > 0 else { return }
            nextViewController.targetNovelID = self.novelID
        }
    }

}
