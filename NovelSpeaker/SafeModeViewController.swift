//
//  SafeModeViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/03/26.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class SafeModeViewController: FormViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        NovelSpeakerUtility.ClearCheckRestartFrequency()
        CreateForms()
    }
    

    func CreateForms() {
        self.form +++ Section(NSLocalizedString("SafeModeViewController_SectionTitle", comment: "セーフモード"))
        <<< LabelRow() {
            $0.title = NSLocalizedString("SafeModeViewController_TitleLabelTitle", comment: "短時間に複数回アプリが再起動したのを検知したため、セーフモードで起動しました。\n以下のメニューからバックアップファイルを生成することで、ことせかい に保存されているデータを取り出す事ができるかもしれません。ただ、取り出されたデータを元に ことせかい を復元したとしても、そのデータが原因で同様の強制終了が発生する可能性はあります。そのような場合には、「開発者に問い合わせる」を使って不都合報告メールを作成し、その強制終了が発生してしまうバックアップデータを添付して送って頂き、開発者の手元で同様の問題が再現しました場合には、問題を解消することができるようになるかもしれません。ただし、バックアップデータには ことせかい に保存されているデータが含まれますので、開発者に渡したくないデータが含まれている場合には添付しないようにしてください。")
            $0.cell.textLabel?.numberOfLines = 0
            //$0.cell.accessoryType = .disclosureIndicator
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SafeModeViewController_CreateShortBackupButton_Title", comment: "軽量バックアップを生成する")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (_, _) in
            self.ShareBackupData(withAllStoryContent: false)
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SafeModeViewController_CreateFullBackupButton_Title", comment: "完全バックアップを生成する")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (_, _) in
            self.ShareBackupData(withAllStoryContent: true)
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SafeModeViewController_SendProbremReport_Title", comment: "開発者に問い合わせる")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (_, _) in
            let nextViewController = BugReportViewController()
            nextViewController.additionalHintString = "safe mode: true"
            nextViewController.modalPresentationStyle = .fullScreen
            self.navigationController?.pushViewController(nextViewController, animated: true)
        })
        <<< ButtonRow("PickRealmData") {
            $0.title = NSLocalizedString("SettingsViewController_PickRealmData_Title", comment: "内部データベースを取り出す")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ cell, row in
            guard let dataFileURL = RealmUtil.IsUseCloudRealm() ? RealmUtil.GetCloudRealmFilePath() : RealmUtil.GetLocalRealmFilePath() else {
                DispatchQueue.main.async {
                    NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("SettingsViewController_PickRealmData_FailGetFilePath", comment: "内部データベースのファイルパスを入手できませんでした。"))
                }
                return
            }
            DispatchQueue.main.async {
                self.ShareToFile(dataFileURL: dataFileURL, fileName: "NovelSpeaker.realm")
            }
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SafeModeViewController_ExitSafeModeButton_Title", comment: "セーフモードを終了し、通常起動する")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (_, _) in
            self.goToMainStoryBoard()
        })
    }

    func goToMainStoryBoard() {
        DispatchQueue.main.async {
            NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
            // background Fetch は AppDelegate::init からの呼び出しでは動作しない場合がある
            // (というかマイグレーションが必要な場合は動かない)ので、
            // このタイミングで起動します。
            NovelDownloadQueue.shared.StartBackgroundFetchIfNeeded()
            StoryHtmlDecoder.shared.LoadSiteInfoIfNeeded()

            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let firstViewController = storyboard.instantiateInitialViewController() else { return }
            NiftyUtility.RegisterToplevelViewController(viewController: firstViewController)
            firstViewController.modalPresentationStyle = .fullScreen
            self.present(firstViewController, animated: true, completion: nil)
        }
    }
    
    func ShareToFile(dataFileURL:URL, fileName:String) {
        DispatchQueue.main.async {
            let activityViewController = UIActivityViewController(activityItems: [dataFileURL], applicationActivities: nil)
            let frame = UIScreen.main.bounds
            activityViewController.popoverPresentationController?.sourceView = self.view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.width / 2 - 60, y: frame.size.height - 50, width: 120, height: 50)
            self.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    func ShareBackupData(withAllStoryContent:Bool){
        let labelTag = 100
        let dialog = NiftyUtility.EasyDialogBuilder(self)
            .label(text: NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……"), textAlignment: NSTextAlignment.center, tag: labelTag)
            .build()
        DispatchQueue.main.async {
            dialog.show()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let backupData = NovelSpeakerUtility.CreateBackupData(withAllStoryContent: withAllStoryContent, progress: { (description) in
                DispatchQueue.main.async {
                    if let label = dialog.view.viewWithTag(labelTag) as? UILabel {
                        label.text = NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……") + "\r\n"
                            + description
                    }
                }
            }) else {
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                    NiftyUtility.EasyDialogOneButton(viewController: self, title: NSLocalizedString("SettingsViewController_GenerateBackupDataFailed", comment: "バックアップデータの生成に失敗しました。"), message: nil, buttonTitle: nil, buttonAction: nil)
                }
                return
            }
            let fileName = backupData.lastPathComponent
            DispatchQueue.main.async {
                dialog.dismiss(animated: false) {
                    self.ShareToFile(dataFileURL: backupData, fileName: fileName)
                }
            }
        }
    }
}
