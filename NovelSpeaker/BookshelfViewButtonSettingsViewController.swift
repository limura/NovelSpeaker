//
//  BookshelfViewButtonSettingsViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/12/12.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class BookshelfViewButtonSettingsViewController: FormViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("BookshelfViewButtonSettingsViewController_Title", comment: "本棚画面の右上に表示されるボタン群の設定")

        RealmUtil.RealmBlock { (realm) in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                self.CreateRows(settingArray: BookshelfViewButtonSetting.defaultSetting)
                return
            }
            self.CreateRows(settingArray: globalState.GetBookshelfViewButtonSetting())
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.saveCurrentSetting()
    }
    
    func saveCurrentSetting() {
        var newSetting:[BookshelfViewButtonSetting] = []
        for row in self.form.allRows {
            guard let tag = row.tag, let type = BookshelfViewButtonTypes.init(rawValue: tag) else { continue }
            guard let switchRow = row as? SwitchRow, let value = switchRow.value else { continue }
            let rowSetting = BookshelfViewButtonSetting(type: type, isOn: value)
            newSetting.append(rowSetting)
        }
        RealmUtil.Write { (realm) in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            globalState.SetBookshelfViewButtonSettingWith(realm: realm, newValue: newSetting)
        }
    }
    
    func CreateRows(settingArray:[BookshelfViewButtonSetting]) {
        self.form +++ MultivaluedSection(multivaluedOptions: .Reorder) { section in
            for setting in settingArray {
                switch setting.type {
                case .downloadStatus:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_DownloadStatus", comment: "ダウンロード状態の確認")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "waveform.badge.magnifyingglass")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .reload:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_Reload", comment: "小説の更新確認")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "arrow.clockwise")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .switchFolder:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_SwitchFolder", comment: "フォルダ開閉")
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "rectangle.expand.vertical")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .search:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_Search", comment: "小説検索")
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.value = setting.isOn
                        $0.cell.imageView?.image = UIImage(systemName: "magnifyingglass")
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .edit:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_Edit", comment: "小説リストを編集(小説の削除)")
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                    }.onChange({_ in self.saveCurrentSetting()})
                case .order:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_Order", comment: "小説の並び替え(順番)")
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.imageView?.image = UIImage(systemName: "arrow.up.arrow.down")
                    }.onChange({_ in self.saveCurrentSetting()})
                case .iCloudPull:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_iCloudPull", comment: "iCloud上のデータの強制取り込みを開始する(通常は必要ありません)")
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                        $0.cell.imageView?.image = UIImage(systemName: "icloud.and.arrow.down")
                    }.onChange({_ in self.saveCurrentSetting()})
                case .iCloudPush:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_iCloudPush", comment: "端末側のデータの「全て」をiCloudへ送信ししなおし始める(通常は必要ありませんし、本当に全てのデータをiCloud側に送信するため、通信量が増えますし全てを送信し終えるには時間がかかるはずです)")
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                        $0.cell.imageView?.image = UIImage(systemName: "icloud.and.arrow.up")
                    }.onChange({_ in self.saveCurrentSetting()})
                case .stopDownload:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_stopDownload", comment: "実行中の全てのダウンロードを止める")
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                        $0.cell.imageView?.image = UIImage(systemName: "pause.circle")
                    }.onChange({_ in self.saveCurrentSetting()})
                case .multiSelect:
                    section <<< SwitchRow(setting.type.rawValue) {
                        $0.title = NSLocalizedString("BookshelfViewButtonType_multiSelect", comment: "複数小説の選択・操作")
                        $0.value = setting.isOn
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                        $0.cell.imageView?.image = UIImage(systemName: "checkmark.square")
                    }
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
