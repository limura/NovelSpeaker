//
//  SpeechViewBottomButtonSettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2026/08/18.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

// 小説本文画面の「画面下部」に表示するボタン群の設定。
// 右上のボタン群の設定とは独立していて、既定では全部 OFF(= 何も表示されない)。
// 右上のボタン群と違って、発話開始/停止と詳細も ON/OFF を選べる
// (「右上には出さず下だけに出す」ができないと、片手で持って押しにくいという要望に応えられないため)。
class SpeechViewBottomButtonSettingsViewController: FormViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("SpeechViewBottomButtonSettingsViewController_Title", comment: "小説本文画面の下部に表示するボタン群の設定")

        RealmUtil.RealmBlock { (realm) in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                self.CreateRows(settingArray: SpeechViewButtonSetting.bottomDefaultSetting, isOverlapsChapterBar: false)
                return
            }
            self.CreateRows(settingArray: globalState.GetSpeechViewBottomButtonSetting(), isOverlapsChapterBar: globalState.isSpeechViewBottomButtonOverlapsChapterBar)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.saveCurrentSetting()
    }

    func saveCurrentSetting() {
        var newSetting:[SpeechViewButtonSetting] = []
        var isOverlapsChapterBar = false
        for row in self.form.allRows {
            guard let tag = row.tag else { continue }
            if tag == "isSpeechViewBottomButtonOverlapsChapterBar" {
                if let switchRow = row as? SwitchRow, let value = switchRow.value {
                    isOverlapsChapterBar = value
                }
                continue
            }
            guard let type = SpeechViewButtonTypes.init(rawValue: tag), let switchRow = row as? SwitchRow, let value = switchRow.value else { continue }
            newSetting.append(SpeechViewButtonSetting(type: type, isOn: value))
        }
        // この画面は viewWillDisappear でも保存を呼ぶので、開いて戻っただけでも
        // ここを通る。中身が変わっていないのに書き込むと、Realm の変更通知が飛んで
        // 「設定タブ」が作り直され、スクロール位置が先頭に戻ってしまうため、
        // 実際に変わっている時だけ書き込む。
        let isChanged = RealmUtil.RealmBlock { (realm) -> Bool in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return false }
            if globalState.isSpeechViewBottomButtonOverlapsChapterBar != isOverlapsChapterBar { return true }
            let currentSetting = globalState.GetSpeechViewBottomButtonSetting()
            if currentSetting.count != newSetting.count { return true }
            for (current, new) in zip(currentSetting, newSetting) {
                if current.type != new.type || current.isOn != new.isOn { return true }
            }
            return false
        }
        if isChanged == false { return }
        RealmUtil.Write { (realm) in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            globalState.SetSpeechViewBottomButtonSettingWith(realm: realm, newValue: newSetting)
            globalState.isSpeechViewBottomButtonOverlapsChapterBar = isOverlapsChapterBar
        }
        NovelSpeakerNotificationTool.AnnounceSpeechViewRightTopButtonTitleChanged()
    }

    func CreateRows(settingArray:[SpeechViewButtonSetting], isOverlapsChapterBar:Bool) {
        self.form +++ Section(NSLocalizedString("SpeechViewBottomButtonSettingsViewController_PositionSectionTitle", comment: "表示位置"))
        <<< SwitchRow("isSpeechViewBottomButtonOverlapsChapterBar") {
            $0.title = NSLocalizedString("SpeechViewBottomButtonSettingsViewController_OverlapsChapterBar", comment: "ページ送りのバーに重ねて表示する")
            $0.value = isOverlapsChapterBar
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ _ in self.saveCurrentSetting() })

        self.form +++ MultivaluedSection(multivaluedOptions: .Reorder, header: NSLocalizedString("SpeechViewBottomButtonSettingsViewController_ButtonsSectionTitle", comment: "表示するボタン(並び順も変えられます)")) { section in
            for setting in settingArray {
                switch setting.type {
                case .speechStop:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_SpeechStop", comment: "発話の開始・停止")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "play.fill")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .openCurrentWebPage:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_OpenCurrentWebPage", comment: "現在のページをWeb取込タブで開く")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "globe.americas.fill")?.withRenderingMode(.alwaysTemplate)
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .openWebPage:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_OpenWebPage", comment: "Web取込タブで開く")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "globe.badge.chevron.backward")?.withRenderingMode(.alwaysTemplate)
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .reload:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Reload", comment: "その小説の更新確認を行う")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "arrow.clockwise")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .share:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Share", comment: "小説のURLをシェアする")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "square.and.arrow.up")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .search:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Search", comment: "小説内を検索(何も入れずに検索すると章のリストを表示します)")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "magnifyingglass")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .searchByText:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_SearchByText", comment: "小説本文中を検索(表示されているページ内を検索)")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "doc.text.magnifyingglass")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .edit:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Edit", comment: "小説を編集する")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "pencil")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .backup:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Backup", comment: "小説をバックアップする")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "tray.and.arrow.up")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .detail:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Detail", comment: "小説の詳細を表示する")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "book.pages")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .skipBackward:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_SkipBackward", comment: "少し巻き戻す")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "gobackward.30")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .skipForward:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_SkipForward", comment: "少し進める")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "goforward.30")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .showTableOfContents:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_ShowTableOfContents", comment: "章リスト(目次)")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "list.bullet")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .addPageToOtherNovel:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_AddPageToOtherNovel", comment: "他の小説にこのページを追加する")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "book.badge.plus")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        super.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
        DispatchQueue.global(qos: .utility).async {
            self.saveCurrentSetting()
        }
    }
}
