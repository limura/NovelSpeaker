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

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("NovelDetailViewController_PageTitle", comment: "小説の詳細")
        createCells()
        observeNovel()
        observeSpeakerSetting()
        observeSpeechSectionConfig()
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
        guard let novel = RealmNovel.SearchNovelFrom(novelID: self.novelID) else { return }
        self.novelObserverToken = novel.observe({ (change) in
            switch change {
            case .error(_):
                break
            case .change(let properties):
                for property in properties {
                    if property.name == "defaultSpeakerID" {
                        DispatchQueue.main.async {
                            print("observeNovel() reload all.")
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

    func observeSpeakerSetting() {
        guard let speakerSettingList = RealmSpeakerSetting.GetAllObjects() else { return }
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
    func observeSpeechSectionConfig() {
        guard let sectionConfigList = RealmSpeechSectionConfig.GetAllObjects() else { return }
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
    
    func createCells() {
        guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else {
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
            }.onCellSelection({ (celloF, row) in
                DispatchQueue.main.async {
                    /// XXX 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
                    let targetTabIndex = 2
                    guard let viewController = self.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController, let url = URL(string: novel.url) else { return }
                    viewController.openTargetUrl = url
                    self.tabBarController?.selectedIndex = targetTabIndex
                }
            })
        }
        self.form +++ detailSection
        let settingSection = Section(NSLocalizedString("NovelDetailViewController_SettingSectionTitle", comment: "この小説専用の設定"))
        // novel.likeLevel
        // isNeedSpeechAfterDelete
        if let speaker = novel.defaultSpeaker {
            settingSection <<< AlertRow<String>("SpeakerAlertRow") {
                $0.title = NSLocalizedString("NovelDetailViewController_SpeakerAlertRowTitle", comment: "標準の話者")
                $0.cancelTitle = NSLocalizedString("Cancel_button", comment: "Cancel")
                $0.selectorTitle = NSLocalizedString("SpeechSectionConfigsViewController_SpeakerSelectorTitle", comment: "話者を選択してください")
                guard let speakerSettingArray = RealmSpeakerSetting.GetAllObjects()?.sorted(byKeyPath: "createdDate", ascending: true) else { return }
                $0.options = speakerSettingArray.map({$0.name})
                $0.value = speaker.name
            }.onChange({ (row) in
                guard let targetName = row.value, let speaker = RealmSpeakerSetting.SearchFrom(name: targetName), let novel = RealmNovel.SearchNovelFrom(novelID: self.novelID) else {
                    return
                }
                RealmUtil.Write(withoutNotifying: [self.speakerSettingObserverToken, self.speechSectionConfigObserverToken, self.novelObserverToken]) { (realm) in
                    novel.defaultSpeakerID = speaker.name
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

        form +++ settingSection
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
