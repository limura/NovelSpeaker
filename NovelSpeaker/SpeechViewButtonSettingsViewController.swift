//
//  SpeechViewButtonSettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/10/21.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class SpeechViewButtonSettingsViewController: FormViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = NSLocalizedString("SpeechViewButtonSettingsViewController_Title", comment: "小説本文画面の右上に表示されるボタン群の設定")

        RealmUtil.RealmBlock { (realm) in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                self.CreateRows(settingArray: SpeechViewButtonSetting.defaultSetting)
                return
            }
            self.CreateRows(settingArray: globalState.GetSpeechViewButtonSetting())
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.saveCurrentSetting()
    }
    
    func saveCurrentSetting() {
        var newSetting:[SpeechViewButtonSetting] = []
        for row in self.form.allRows {
            guard let tag = row.tag, let type = SpeechViewButtonTypes.init(rawValue: tag) else { continue }
            if let _ = row as? LabelRow, type == .detail {
                newSetting.append(SpeechViewButtonSetting(type: type, isOn: true))
                continue
            }
            guard let switchRow = row as? SwitchRow, let value = switchRow.value else { continue }
            let rowSetting = SpeechViewButtonSetting(type: type, isOn: value)
            newSetting.append(rowSetting)
        }
        RealmUtil.Write { (realm) in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            globalState.SetSpeechViewButtonSettingWith(realm: realm, newValue: newSetting)
        }
    }
    
    func CreateRows(settingArray:[SpeechViewButtonSetting]) {
        self.form +++ MultivaluedSection(multivaluedOptions: .Reorder) { section in
            for setting in settingArray {
                switch setting.type {
                case .openCurrentWebPage:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_OpenCurrentWebPage", comment: "現在のページをWeb取込タブで開く")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(named: "earth")?.withRenderingMode(.alwaysTemplate)
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .openWebPage:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_OpenWebPage", comment: "Web取込タブで開く")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(named: "earth")?.withRenderingMode(.alwaysTemplate)
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .reload:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Reload", comment: "その小説の更新確認を行う")
                        $0.value = setting.isOn
                        if #available(iOS 13.0, *) {
                            $0.cell.imageView?.image = UIImage(systemName: "arrow.clockwise")
                        }
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .share:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Share", comment: "小説のURLをシェアする")
                        $0.value = setting.isOn
                        if #available(iOS 13.0, *) {
                            $0.cell.imageView?.image = UIImage(systemName: "square.and.arrow.up")
                        }
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .search:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Search", comment: "小説内を検索(何も入れずに検索すると章のリストを表示します)")
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.value = setting.isOn
                        if #available(iOS 13.0, *) {
                            $0.cell.imageView?.image = UIImage(systemName: "magnifyingglass")
                        }
                    }.onChange({_ in self.saveCurrentSetting()})
                case .edit:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Edit", comment: "小説を編集する")
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.value = setting.isOn
                    }.onChange({_ in self.saveCurrentSetting()})
                case .backup:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Backup", comment: "小説をバックアップする")
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.value = setting.isOn
                    }.onChange({_ in self.saveCurrentSetting()})
                case .detail:
                    section <<< LabelRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_Detail", comment: "小説の詳細を表示する")
                        $0.cell.textLabel?.numberOfLines = 0
                    }
                case .skipBackward:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_SkipBackward", comment: "少し巻き戻す")
                        if #available(iOS 13.0, *) {
                            $0.cell.imageView?.image = UIImage(systemName: "gobackward.30")
                        }
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .skipForward:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_SkipForward", comment: "少し進める")
                        if #available(iOS 13.0, *) {
                            $0.cell.imageView?.image = UIImage(systemName: "goforward.30")
                        }
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .showTableOfContents:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("SpeechViewButtonType_ShowTableOfContents", comment: "章リスト(目次)")
                        if #available(iOS 13.0, *) {
                            $0.cell.imageView?.image = UIImage(systemName: "list.bullet")
                        }
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                default:
                    continue
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
