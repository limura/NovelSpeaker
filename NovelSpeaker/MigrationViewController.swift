//
//  MigrationViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/31.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit

class MigrationViewController: UIViewController {
    
    @IBOutlet weak var progressLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // 戻るボタンを見えなくします
        self.navigationItem.setHidesBackButton(true, animated: false)
        
        RealmUtil.CheckCloudAccountStatus { (result, error) in
            DispatchQueue.global(qos: .utility).async {
                self.CheckAndDoCoreDataMigration()
                self.CheckAndDoCoreDataToRealmMigration()
                if self.CheckAndiCloudStatusInvalidNotice(isiCloudAccountStatusValid: result, icloudAccountStatusCheckError: error) {
                    return
                }
                NovelSpeakerUtility.AddFirstStoryIfNeeded()
                self.goToMainStoryBoard()
            }
        }
    }
    
    func CheckAndiCloudStatusInvalidNotice(isiCloudAccountStatusValid:Bool, icloudAccountStatusCheckError:String?) -> Bool {
        // iCloud を使っていないか iCloud の状態が問題ないのであれば何もしない
        if RealmUtil.IsUseCloudRealm() == false || isiCloudAccountStatusValid == true {
            return false
        }
        // ここまで来たという事は、iCloud を使う設定になっているけれど、iCloud の状態がおかしかった
        if RealmUtil.CheckIsCloudRealmCreated() == false {
            // iCloud の Realm data が無いという事は、このままだと何のデータも無い事になる。
            // で、iCloud の状態が不正で local の Realm data が無いという事になり、
            // iCloud を使わない状態にして初期状態で起動するしかない。
            DispatchQueue.main.async {
                NiftyUtilitySwift.EasyDialogMessageDialog(viewController: self, title: NSLocalizedString("MigrationViewController_InvalidiCloudStatus_NoiCloudRealmData_Title", comment: "iCloud が使用できません"), message: NSLocalizedString("MigrationViewController_InvalidiCloudStatus_NoiCloudRealmData_Message", comment: "iCloud が利用できない状態のようなのですが、iCloud を利用する形で起動されています。内部に保存されている iCloud 側のデータも存在しないか消えてしまっているようなので、iCloud を利用しないように設定した上で起動することになります。") + "\n" + (icloudAccountStatusCheckError ?? NSLocalizedString("MigrationViewController_InvalidiCloudStatus_UnknowniCloudError", comment: "不明な iCloud 状態エラー")), completion: {
                    RealmUtil.SetIsUseCloudRealm(isUse: false)
                    NovelSpeakerUtility.AddFirstStoryIfNeeded()
                    self.goToMainStoryBoard()
                })
            }
            return true
        }
        // ここに来るという事は、
        // iCloud を使う設定になっている
        // iCloud の状態がおかしい
        // iCloud 側の Realm data がある
        // という状態であるので、local に直して起動して良いかどうかを確認する必要がある。
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogLongMessageTwoButton(viewController: self, title: NSLocalizedString("MigrationViewController_InvalidiCloudStatus_HasiCloudRealmData_Title", comment: "iCloud が使用できません"), message: NSLocalizedString("MigrationViewController_InvalidiCloudStatus_HasiCloudRealmData_Message", comment: "iCloud が利用できない状態のようなのですが、iCloud を利用する形で起動されています。このまま利用を続けた場合、後で iCloud の利用が可能になった時などに動作が不安定になる可能性があるかもしれません(そのような場合の動作不良についての対応は致しかねます事は予めご承知おきください)。このまま iCloud を利用する設定のままで起動しますか？") + "\n\n" + NSLocalizedString("MigrationViewController_InvalidiCloudStatus_HasiCloudRealmData_Message_AppendErrorDescription", comment: "検知されたエラー: ") + (icloudAccountStatusCheckError ?? NSLocalizedString("MigrationViewController_InvalidiCloudStatus_UnknowniCloudError", comment: "不明な iCloud 状態エラー")), button1Title: NSLocalizedString("MigrationViewController_InvalidiCloudStatus_HasiCloudRealmData_ConvertToLocalButton", comment: "iCloudを利用しない"), button1Action: {
                RealmUtil.SetIsUseCloudRealm(isUse: false)
                DispatchQueue.global(qos: .utility).async {
                    self.CopyLocalToCloud()
                    NovelSpeakerUtility.AddFirstStoryIfNeeded()
                    self.goToMainStoryBoard()
                }
            }, button2Title: NSLocalizedString("MigrationViewController_InvalidiCloudStatus_HasiCloudRealmData_StayButton", comment: "iCloudを利用したまま起動する")) {
                NovelSpeakerUtility.AddFirstStoryIfNeeded()
                self.goToMainStoryBoard()
            }
        }
        return true
    }
    
    func CheckAndDoCoreDataMigration() {
        if let globalData = GlobalDataSingleton.getInstance() {
            if globalData.isAliveOLDSaveDataFile() {
                globalData.moveOLDSaveDataFileToNewLocation()
            }
            if globalData.isAliveCoreDataSaveFile() && globalData.isRequiredCoreDataMigration() {
                DispatchQueue.main.async {
                    self.progressLabel.text = NSLocalizedString("MigrationViewController_DoingCoreDataMigration", comment: "旧データベースの更新を行っています。")
                }
                globalData.doCoreDataMigration()
            }
        }
    }
    
    func FetchValidCloudData() {
        DispatchQueue.main.async {
            self.progressLabel.text = NSLocalizedString("MigrationViewController_FetchAllCloudData_Progress", comment: "iCloud上のデータに利用可能なデータが残されているかを確認しています。")
        }
        let semaphore = DispatchSemaphore(value: 0)
        RealmUtil.CheckCloudDataIsValid { (result) in
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    @discardableResult
    func CopyLocalToCloud() -> Bool {
        return autoreleasepool {
            guard let localRealm = try? RealmUtil.GetLocalRealm(), let cloudRealm = try? RealmUtil.GetCloudRealm() else { return false }
            // TODO: ここで localRealm から cloudRealm に上書きコピーをして良いのかの確認プロセスが無い
            try! RealmToRealmCopyTool.DoCopy(from: localRealm, to: cloudRealm) { (text) in
                DispatchQueue.main.async {
                    self.progressLabel.text = text
                }
            }
            return true
        }
    }

    func CheckAndDoCoreDataToRealmMigration() {
        autoreleasepool {
            if RealmUtil.IsUseCloudRealm() {
                do {
                    try RealmUtil.EnableSyncEngine()
                }catch{
                    // TODO: exception を握りつぶしている
                }
                if RealmUtil.RealmBlock(block: { NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: $0) }) {
                    // iCloud の データがあるならそれを使う
                    return
                }
                // iCloud を使うようにマークされているが、
                // local に読み込まれた iCloud のデータは不正なものであったようである。
                // 仕方がないので iCloud側 のデータを全て読み直す事にする。
                self.FetchValidCloudData()
                // 再度確認する
                if RealmUtil.RealmBlock(block: { NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: $0) }) {
                   return
                }
                // local のがあるならそこからコピーする
                if RealmUtil.CheckIsLocalRealmCreated() && CopyLocalToCloud() {
                    return
                }
                if GlobalDataSingleton.getInstance()?.isAliveCoreDataSaveFile() ?? false {
                    // CoreData のがあるならそこからコピーする
                    CoreDataToRealmTool.ConvertFromCoreData { (text) in
                        DispatchQueue.main.async {
                            self.progressLabel.text = text
                        }
                    }
                    return
                }else{
                    // CoreData のものはなかったので CoreData からの移行は完了したと印をつけておく
                    CoreDataToRealmTool.RegisterConvertFromCoreDataFinished()
                }
                // それでもないなら default値 を入れておく
                NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
            }else{
                // Local Ream を使う場合で、
                if RealmUtil.CheckIsLocalRealmCreated() {
                    // realm file はあって
                    if CoreDataToRealmTool.IsConvertFromCoreDataFinished() {
                        // CoreData からの移行もできてるならそれを使う
                        print("CoreDataToRealmTool.IsConvertFromCoreDataFinished: return true. migrate done.")
                        return
                    }
                    // CoreData からの移行が完了していないらしいので Local Realm file は消しておきます
                    RealmUtil.RemoveLocalRealmFile()
                }
            }
            // ここに来るのは
            // ・LocalRealm を使用する
            // ・LocalRealm file は無い(か消した)
            // という状態。
            if !(GlobalDataSingleton.getInstance()?.isAliveCoreDataSaveFile() ?? true) {
                // CoreData のファイルが無いなら CoreData からの移行は完了したとマークしておく
                CoreDataToRealmTool.RegisterConvertFromCoreDataFinished()
                // 標準の設定を入れて終了
                print("NovelSpeakerUtility.InsertDefaultSettingsIfNeeded() call.")
                NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
                return
            }
            // そうでもないなら CoreData からの移行を行う
            CoreDataToRealmTool.ConvertFromCoreData { (text) in
                DispatchQueue.main.async {
                    self.progressLabel.text = text
                }
            }
            NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
        }
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
            NiftyUtilitySwift.RegisterToplevelViewController(viewController: firstViewController)
            firstViewController.modalPresentationStyle = .fullScreen
            self.present(firstViewController, animated: true, completion: nil)
        }
    }
}
