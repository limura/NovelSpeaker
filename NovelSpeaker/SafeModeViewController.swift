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
            $0.title = NSLocalizedString("SafeModeViewController_TitleLabelTitle", comment: "短時間に複数回アプリが再起動したのを検知したため、セーフモードで起動しました。\n起動直後に強制終了してしまう場合には、「設定タブ」で設定を変更することである程度は回避できるかもしれません。\nまた、「設定タブ」で設定を変えてもどうにもならない場合、「設定タブ」内の「バックアップ用データの生成」からバックアップファイルを生成することで、ことせかい に保存されているデータを取り出す事ができるかもしれません。ただ、取り出されたデータを元に ことせかい を復元したとしても、そのデータが原因で同様の強制終了が発生する可能性はあります。そのような場合には、「設定タブ」→「開発者に問い合わせる」からその強制終了が発生してしまうバックアップデータを送って頂いた上で、開発者の手元で同様の問題が再現しました場合には、問題を解消することができるようになるかもしれません。")
            $0.cell.textLabel?.numberOfLines = 0
            //$0.cell.accessoryType = .disclosureIndicator
        }
        <<< ButtonRow() {
            $0.title = NSLocalizedString("SafeModeViewController_GoToSettingsTabButton_Title", comment: "「設定タブ」を開く")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (_, _) in
            let nextViewController = SettingsViewController()
            //nextViewController.modalPresentationStyle = .fullScreen
            //self.present(nextViewController, animated: true, completion: nil)
            self.navigationController?.pushViewController(nextViewController, animated: true)
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
}
