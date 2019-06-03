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

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("NovelDetailViewController_PageTitle", comment: "小説の詳細")
        createCells()
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
                RealmUtil.Write { (realm) in
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
