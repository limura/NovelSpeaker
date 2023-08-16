//
//  RealmModels.swift
//
//  Created by 飯村卓司 on 2019/04/14.
//  Copyright © 2019 limura products. All rights reserved.
//

import Foundation
import RealmSwift
import IceCream
import CloudKit
import UIKit
import AVFoundation

@objc class RealmUtil : NSObject {
    static let currentSchemaVersion : UInt64 = 13
    static let deleteRealmIfMigrationNeeded: Bool = false
    static let CKContainerIdentifier = "iCloud.com.limuraproducts.novelspeaker"

    static var syncEngine: SyncEngine? = nil
    static let lock = NSLock()
    
    static var writeCount = 0
    static let writeCountPullInterval = 1000 // realm.write を何回したら pull するか

    static func Migrate_0_To_1(migration:Migration, oldSchemaVersion:UInt64) {
    }
    static func Migrate_1_To_2(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmSpeechModSetting.className()) { (oldObject, newObject) in
            //guard let oldObject = oldObject, let newObject = newObject else { return }
            //guard let before = oldObject["before"] as? String else { return }
            //newObject["beforeBefore"] = before
        }
    }
    static func Migrate_Novel_LikeLevelTo_GlobalState_NovelLikeOrder(migration:Migration, oldSchemaVersion:UInt64) {
        /*
         RealmNovel.likeLevel で保存していた「お気に入り度合い」を、
         RealmGlobalState.novelLikeOrder:List<String> に保存するようにします。
         */
        struct likeLevelData {
            let novelID:String
            let likeLevel:Int
        }
        var oldLikeData:[likeLevelData] = []
        migration.enumerateObjects(ofType: RealmNovel.className()) { (oldObject, newObject) in
            guard let oldObject = oldObject, let likeLevel = oldObject["likeLevel"] as? Int, likeLevel > 0, let novelID = oldObject["novelID"] as? String else { return }
            oldLikeData.append(likeLevelData(novelID: novelID, likeLevel: likeLevel))
        }
        let novelLikeOrderArray = oldLikeData.sorted { (a, b) -> Bool in
            a.likeLevel > b.likeLevel
        }.map({$0.novelID})
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            guard let newObject = newObject else { return }
            let newNovelLikeOrder = List<String>()
            newNovelLikeOrder.removeAll()
            newNovelLikeOrder.append(objectsIn: novelLikeOrderArray)
            newObject["novelLikeOrder"] = newNovelLikeOrder
        }
    }
    static func Migrate_3_To_4(migration:Migration, oldSchemaVersion:UInt64) {
        Migrate_Novel_LikeLevelTo_GlobalState_NovelLikeOrder(migration: migration, oldSchemaVersion: oldSchemaVersion)
    }
    static func Migrate_4_To_5(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            newObject?["isAnnounceAtRepatSpeechTime"] = true
        }
    }
    static func Migrate_5_To_6(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmDisplaySetting.className()) { (oldObject, newObject) in
            newObject?["lineSpacing"] = Float(26.0)
        }
    }
    static func Migrate_6_To_7(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            newObject?["isEnableSwipeOnStoryView"] = true
        }
    }
    static func Migrate_7_To_8(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            newObject?["isDisableNarouRuby"] = false
        }
    }
    static func Migrate_8_To_9(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmDisplaySetting.className()) { (oldObject, newObject) in
            newObject?["m_ViewType"] = RealmDisplaySetting.ViewType.normal.rawValue
        }
    }
    static func Migrate_9_To_10(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            newObject?["m_repeatSpeechLoopType"] = RepeatSpeechLoopType.normal.rawValue
        }
    }
    static func Migrate_10_To_11(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            newObject?["isNeedDisableIdleTimerWhenSpeechTime"] = false
        }
    }
    static func Migrate_12_To_13(migration:Migration, oldSchemaVersion:UInt64) {
        migration.enumerateObjects(ofType: RealmGlobalState.className()) { (oldObject, newObject) in
            newObject?["likeButtonDialogType"] = LikeButtonDialogType.noDialog.rawValue
        }
    }

    static func MigrateFunc(migration:Migration, oldSchemaVersion:UInt64) {
        if oldSchemaVersion == 0 {
            Migrate_0_To_1(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 1 {
            Migrate_1_To_2(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 3 {
            Migrate_3_To_4(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 4 {
            Migrate_4_To_5(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 5 {
            Migrate_5_To_6(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 6 {
            Migrate_6_To_7(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 7 {
            Migrate_7_To_8(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 8 {
            Migrate_8_To_9(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 9 {
            Migrate_9_To_10(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 10 {
            Migrate_10_To_11(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion <= 12 {
            Migrate_12_To_13(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
    }
    
    static func GetLocalRealmFilePath() -> URL? {
        let fileManager = FileManager.default
        do {
            let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return directory.appendingPathComponent("local.realm")
        }catch{
            return nil
        }
    }
    @objc static func RemoveLocalRealmFile() {
        if let path = GetLocalRealmFilePath() {
            let fileManager = FileManager.default
            do {
                try fileManager.removeItem(at: path)
            }catch{
                print("file \(path.absoluteString) remove failed.")
            }
        }
    }
    static func GetLocalRealmConfiguration() -> Realm.Configuration {
        return Realm.Configuration(
            fileURL: GetLocalRealmFilePath(),
            schemaVersion: currentSchemaVersion,
            migrationBlock: MigrateFunc,
            deleteRealmIfMigrationNeeded: deleteRealmIfMigrationNeeded,
            shouldCompactOnLaunch: { (totalBytes, usedBytes) in
                return totalBytes * 2 < usedBytes
        })
    }
    static func GetLocalRealm(queue:DispatchQueue? = nil) throws -> Realm {
        lock.lock()
        defer {
            lock.unlock()
        }
        let config = GetLocalRealmConfiguration()
        let realm = try Realm(configuration: config, queue: queue)
        return realm
    }
    static func GetCloudRealmFilePath() -> URL? {
        let fileManager = FileManager.default
        do {
            let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return directory.appendingPathComponent("cloud.realm")
        }catch{
            return nil
        }
    }
    @objc static func RemoveCloudRealmFile() {
        // 注意：
        // Cloud側(というかIceCream側)は、SyncEngine に渡している
        // Realm object を消さないと、同じデータに対する Realm object が
        // 複数存在することになってしまうため、
        // ここで実態や参照を消しても SyncEngine 側は古いものを参照してしまう。
        // ということで、これを使う場合は強制終了させる必要があるかも。
        if let path = GetCloudRealmFilePath() {
            let fileManager = FileManager.default
            do {
                try fileManager.removeItem(at: path)
            }catch{
                print("file \(path.absoluteString) remove failed.")
            }
        }
    }
    static func ClearCloudRealmModels() {
        // とりあえず中身を消す
        do {
            let realm = try GetCloudRealm()
            try realm.write {
                for obj in realm.objects(RealmCloudVersionChecker.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmNovel.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmSpeechModSetting.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmSpeechWaitConfig.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmSpeakerSetting.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmSpeechSectionConfig.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmGlobalState.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmDisplaySetting.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmNovelTag.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmStoryBulk.self) {
                    obj.isDeleted = true
                }
            }
        }catch{
        }
    }

    fileprivate static func GetCloudRealmConfiguration() -> Realm.Configuration {
        return Realm.Configuration(
            fileURL: GetCloudRealmFilePath(),
            schemaVersion: currentSchemaVersion,
            migrationBlock: MigrateFunc,
            deleteRealmIfMigrationNeeded: deleteRealmIfMigrationNeeded,
            shouldCompactOnLaunch: { (totalBytes, usedBytes) in
                return totalBytes * 2 < usedBytes
        })
    }
    fileprivate static func GetCloudRealmWithoutLock(queue:DispatchQueue? = nil) throws -> Realm {
        let config = GetCloudRealmConfiguration()
        let realm = try Realm(configuration: config, queue: queue)
        realm.autorefresh = true
        return realm
    }
    static func GetCloudRealm(queue:DispatchQueue? = nil) throws -> Realm {
        lock.lock()
        defer {
            lock.unlock()
        }
        let realm = try GetCloudRealmWithoutLock(queue: queue)
        return realm
    }
    static func GetContainer() -> CKContainer {
        return CKContainer(identifier: CKContainerIdentifier)
    }
    fileprivate static func CreateSyncEngine() throws -> SyncEngine {
        let container = GetContainer()
        let realmConfiguration = RealmUtil.GetCloudRealmConfiguration()
        return SyncEngine(objects: [
            SyncObject(realmConfiguration: realmConfiguration, type: RealmCloudVersionChecker.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmStoryBulk.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmNovel.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmSpeechModSetting.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmSpeechWaitConfig.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmSpeakerSetting.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmSpeechSectionConfig.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmGlobalState.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmDisplaySetting.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmNovelTag.self),
            SyncObject(realmConfiguration: realmConfiguration, type: RealmBookmark.self),
            ], databaseScope: .private, container: container)
    }

    static func EnableSyncEngine() throws {
        lock.lock()
        defer { lock.unlock() }
        if syncEngine != nil { return }
        self.syncEngine = try CreateSyncEngine()
    }
    
    static func stopSyncEngine() {
        syncEngine = nil
    }
    static func FetchAllLongLivedOperationIDs(completionHandler: @escaping ([CKOperation.ID]?, Error?) -> Void) {
        let container = GetContainer()
        container.fetchAllLongLivedOperationIDs(completionHandler: completionHandler)
    }
    static func GetCloudAccountStatus(completionHandler: @escaping (CKAccountStatus, Error?) -> Void) {
        let container = GetContainer()
        container.accountStatus(completionHandler: completionHandler)
    }
    @objc static func CheckCloudAccountStatus(completionHandler: @escaping (Bool, String?) -> Void) {
        GetCloudAccountStatus { (accountStatus, error) in
            if let error = error {
                completionHandler(false, error.localizedDescription)
                return
            }
            switch accountStatus {
            case .available:
                completionHandler(true, nil)
            case .restricted:
                completionHandler(false, NSLocalizedString("SettingsViewController_iCloudAccountInvalid_restricted", comment: "iCloud アカウントが制限付きの状態でしたので利用できません。"))
            case .noAccount:
                completionHandler(false, NSLocalizedString("SettingsViewController_iCloudAccountInvalid_noAccount", comment: "iCloud アカウントが設定されていません。"))
            case .temporarilyUnavailable:
                completionHandler(false, NSLocalizedString("SettingsViewController_iCloudAccountInvalid_temporarilyUnavailable", comment: "iCloud アカウントが利用できない状態のようです。(temporarilyUnavailable)"))
            case .couldNotDetermine:
                fallthrough
            @unknown default:
                completionHandler(false, NSLocalizedString("SettingsViewController_iCloudAccountInvalid_cloudNotDetermine", comment: "iCloud アカウントの状態を取得できませんでした。"))
            }
        }
    }
    // LongLivedOperationID が全部消えるまで待ちます。
    static func WaitAllLongLivedOperationIDCleared(watchInterval:TimeInterval = 1.0, completion:@escaping (()->Void)) {
        FetchAllLongLivedOperationIDs { (operationIDArray, error) in
            guard error == nil, let operationIDArray = operationIDArray, operationIDArray.count > 0 else {
                completion()
                return
            }
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + watchInterval) {
                WaitAllLongLivedOperationIDCleared(completion: completion)
            }
        }
    }
    
    static func CountAllCloudRealmRecords(realm:Realm) -> Int {
        let targetRealmClasses = [
            RealmCloudVersionChecker.self,
            RealmStoryBulk.self,
            RealmNovel.self,
            RealmSpeechWaitConfig.self,
            RealmSpeakerSetting.self,
            RealmSpeechSectionConfig.self,
            RealmGlobalState.self,
            RealmDisplaySetting.self,
            RealmNovelTag.self,
            RealmBookmark.self,
        ]
        var count = 0
        realm.refresh()
        for realmClass in targetRealmClasses {
            count += realm.objects(realmClass).count
        }
        return count
    }
    static func FetchCloudData(syncObjectType:AnyClass, predicate:NSPredicate) {
        // TODO: IceCream側でなんとかして欲しいんだけどどうしたもんか。
        //syncEngine?.query(syncObjectType: syncObjectType, predicate: predicate)
    }
    
    static var isCheckCloudDataIsValidInterrupt:Bool = false
    @objc static func SetCheckCloudDataIsValidInterrupt(isInterrupt:Bool) {
        isCheckCloudDataIsValidInterrupt = isInterrupt
    }
    enum CheckCloudDataIsValidResult {
        case validDataAlive
        case validDataNotAlive
        case dataAliveButNotValid
        case networkError
        case checkFailed
    }
    /// iCloud上にあるデータが使い物になるかどうかを確認します。
    /// 全てのデータが取得できたという事を確認する事が難しいため、
    /// 全てのデータが取得できていなかったとしても、使い物になるかどうかの確認だけをして、
    /// 使い物になりそうであれば completion method で true を返します。
    /// 動作としては、syncEngine?.pull() してから暫く待って、
    /// iCloud 側のデータが増えているならもう少し(timeoutLimitまで)待ってみて、
    /// それでも駄目なら駄目だったと返します(completion に false を入れて呼び出します)。
    /// timeout については、
    /// minimumTimeoutLimit の間、iCloud 上のデータのRecord数が 0 のまま新しい record を取得できないのであれば false
    /// record数は増えていたが、timeoutLimit の間に有効なデータが取得できなければ false を返す事になります。
    static func CheckCloudDataIsValid(minimumTimeoutLimit: TimeInterval = 10.0, timeoutLimit: TimeInterval = 60.0 * 5, completion: ((CheckCloudDataIsValidResult) -> Void)?) {

        // カンジ悪く必要そうなものを別途 fetch してしまいます(というか、RealmNovel や RealmStory は数が多すぎるので fetch したくないんですけど、syncEngine を起動した時に fetch が走ってしまいます)
        FetchCloudData(syncObjectType: RealmCloudVersionChecker.self, predicate: NSPredicate(format: "id = %@", RealmCloudVersionChecker.uniqueID))
        FetchCloudData(syncObjectType: RealmGlobalState.self, predicate: NSPredicate(format: "id = %@", RealmGlobalState.UniqueID))
        FetchCloudData(syncObjectType: RealmSpeakerSetting.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechSectionConfig.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechWaitConfig.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechModSetting.self, predicate: NSPredicate(value: true))

        autoreleasepool {
            guard let realm = try? GetCloudRealm() else {
                completion?(.validDataNotAlive)
                return
            }
            realm.refresh()
            let startCount = CountAllCloudRealmRecords(realm: realm)
            let minimumTimelimitDate = Date(timeIntervalSinceNow: minimumTimeoutLimit)
            let timelimitDate = Date(timeIntervalSinceNow: timeoutLimit)
            if startCount > 0 && NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm) {
                completion?(.validDataAlive)
                return
            }

            isCheckCloudDataIsValidInterrupt = false
            var syncEnginePullEnd:Bool = false
            syncEngine?.pull(completionHandler: { (err) in
                if let err = err {
                    print("syncEngine.pull completion error: \(err.localizedDescription)")
                }else{
                    print("syncEngine.pull completion. not error.")
                }
                syncEnginePullEnd = true
            })
            func watcher(completion: ((CheckCloudDataIsValidResult) -> Void)?, startCount:Int, minimumTimelimitDate:Date, timelimitDate:Date) {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                    if isCheckCloudDataIsValidInterrupt {
                        completion?(.checkFailed)
                        return
                    }
                    autoreleasepool {
                        guard let realm = try? GetCloudRealm() else {
                            completion?(.validDataNotAlive)
                            return
                        }
                        realm.refresh()
                        let currentCount = CountAllCloudRealmRecords(realm: realm)
                        if currentCount > startCount && NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm) {
                            completion?(.validDataAlive)
                            FetchCloudData(syncObjectType: RealmStoryBulk.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmNovel.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmDisplaySetting.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmNovelTag.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmBookmark.self, predicate: NSPredicate(value: true))

                            return
                        }
                        if Date() > timelimitDate || syncEnginePullEnd == true {
                            if startCount < currentCount {
                                completion?(.dataAliveButNotValid)
                                return
                            }
                            completion?(.validDataNotAlive)
                            return
                        }
                        if startCount <= 0 && currentCount <= 0 && Date() > minimumTimelimitDate {
                            // minimumTimeoutLimit秒経っても count が 0 から何も増えてないということは多分何も入っていない
                            // ……と、思うんだけれど、ネットワークが繋がっていなくてもここに来てしまうので、
                            // 一応インターネットから何かを取り出せるかどうかを確認する。
                            NiftyUtility.httpGet(url: URL(string: NiftyUtility.IMPORTANT_INFORMATION_TEXT_URL)!, successAction: { (_, _) in
                                // 取り出せるのなら本当にデータは無いのだろうということで
                                // データは無かったと報告する
                                completion?(.validDataNotAlive)
                            }) { (err) in
                                // エラーしているならネットワークエラーっぽい
                                completion?(.networkError)
                            }
                            return
                        }
                        watcher(completion: completion, startCount: startCount, minimumTimelimitDate: minimumTimelimitDate, timelimitDate: timelimitDate)
                    }
                }
            }
            watcher(completion: completion, startCount: startCount, minimumTimelimitDate: minimumTimelimitDate, timelimitDate: timelimitDate)
        }
    }
    
    /// IceCream の使っている Custom Zone が作られたよフラグを管理している UserDefaults 値を消します。
    /// IceCream/IceCream/Classes/SyncObject.swift では
    /// UserDefaults.standard.set(newValue, forKey: T.className() + IceCreamKey.hasCustomZoneCreatedKey.value)
    /// とやっているようなので、それっぽいキーがあったら消す、という事をするわけです。
    static func ForceClearIceCreamCustomZoneCreatedFlug() {
        let defaults = UserDefaults.standard
        let targetIceCreamKeyArray = [ // wow! magic word!
            "icecream.keys.hasCustomZoneCreatedKey",
        ]
        for key in defaults.dictionaryRepresentation().keys {
            for targetKey in targetIceCreamKeyArray {
                if key.contains(targetKey) {
                    print("delete IceCream Key: \(key)")
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }
    // IceCream の使っている iCloud 同期の状態管理をしている UserDefaults 値を消します。
    // (WARN: targetIceCreamKeyArray に書かれている値は IceCream の source code から推測して作られた値なので、
    // 将来的にこのままではおかしな動作になる可能性があります)
    // 効果としては、SyncEngine.pull() で取得される値が前回からの差分で更新があったもののみ、というのが「全て」に変わります。
    static func ForceRemoveIceCreamDatabaseSyncTokens() {
        let defaults = UserDefaults.standard
        let targetIceCreamKeyArray = [ // wow! magic word!
            "icecream.keys.databaseChangesTokenKey",
            "icecream.keys.zoneChangesTokenKey",
            "icecream.keys.subscriptionIsLocallyCachedKey",
            "icecream.keys.hasCustomZoneCreatedKey",
        ]
        for key in defaults.dictionaryRepresentation().keys {
            for targetKey in targetIceCreamKeyArray {
                if key.contains(targetKey) {
                    print("delete IceCream Key: \(key)")
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }
    @objc static func CloudPull() {
        syncEngine?.pull()
    }
    @objc static func CloudPush() {
        syncEngine?.pushAll()
    }
    
    // iCloud 上の全てのデータを消します
    static func ClearCloudData() throws {
        try EnableSyncEngine()
        ForceRemoveIceCreamDatabaseSyncTokens()
        CloudPull()
        WaitAllLongLivedOperationIDCleared {
            ClearCloudRealmModels()
            CloudPush()
        }
    }

    static let UseCloudRealmKey = "RealmUtil_UseCloudRealm"
    @objc static func IsUseCloudRealm() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [UseCloudRealmKey: false])
        return defaults.bool(forKey: UseCloudRealmKey)
    }
    static func SetIsUseCloudRealm(isUse:Bool) {
        let defaults = UserDefaults.standard
        defaults.set(isUse, forKey: UseCloudRealmKey)
        NovelSpeakerNotificationTool.AnnounceRealmSettingChanged()
    }
    // IsUseCloudRealm が true になるように書き換えます。
    // 同時に全ての NotificationToken を作り直させたり、
    // 使わなくなった Realm のデータファイルを消したりします。
    // 注: EnableSyncEngine() は呼び出しません。
    // というか、EnableSyncEngine() はこれを呼ぶ前の
    // iCloud側 が使えるかを確認する時に呼び出されているはずです。
    // これが呼び出されるのは iCloud側のデータ が正しく入っている
    // (つまり既に SyncEngine が動いている)状態のはずです。
    static func ChangeToCloudRealm(){
        SetIsUseCloudRealm(isUse: true)
        RealmObserverHandler.shared.AnnounceRestartObservers()
        RemoveLocalRealmFile()
    }
    // IsUseCloudRealm が false になるように書き換えます。
    // 同時に全ての NotificationToken を作り直させたり、
    // 使わなくなった Realm のデータファイルを消したりします。
    static func ChangeToLocalRealm(){
        SetIsUseCloudRealm(isUse: false)
        stopSyncEngine()
        RealmObserverHandler.shared.AnnounceRestartObservers()
        RemoveCloudRealmFile()
    }
    static func GetRealm(queue:DispatchQueue? = nil) throws -> Realm {
        if IsUseCloudRealm() {
            if syncEngine == nil {
                try EnableSyncEngine()
            }
            return try GetCloudRealm(queue: queue)
        }
        return try GetLocalRealm(queue: queue)
    }
    @discardableResult
    static func RealmBlock<Result>(block: (_ realm:Realm) throws -> Result) rethrows -> Result {
        return try autoreleasepool {
            let realm = try RealmUtil.GetRealm()
            return try block(realm)
        }
    }
    static func RealmDispatchQueueAsyncBlock(queue: DispatchQueue? = nil, block: @escaping (_ realm:Realm) -> Void) {
        (queue ?? DispatchQueue.main).async {
            autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm(queue: queue) else {
                    return
                }
                block(realm)
            }
        }
    }
    
    @objc static func IsValidRealmData() -> Bool {
        return RealmBlock { (realm) -> Bool in
            return RealmGlobalState.GetInstanceWith(realm: realm) != nil
        }
    }
    static func refresh() {
        RealmBlock { (realm) in
            realm.refresh()
        }
    }

    // TODO: 書き込み失敗を無視している
    static func WriteWith(realm:Realm, withoutNotifying:[NotificationToken?] = [], block:((_ realm:Realm)->Void)) {
        //realm.refresh()
        guard realm.isInWriteTransaction == false else {
            block(realm)
            return
        }
        let withoutNotifying = withoutNotifying.filter { (token) -> Bool in
            token != nil
            } as! [NotificationToken]
        realm.beginWrite()
        block(realm)
        do {
            if withoutNotifying.count <= 0 {
                try realm.commitWrite()
            }else{
                try realm.commitWrite(withoutNotifying: withoutNotifying)
            }
        }catch{
            print("realm.write failed.")
        }
        writeCount += 1
        if writeCount % writeCountPullInterval == 0 && IsUseCloudRealm() {
            CloudPull()
        }
    }

    static func Write(block:((_ realm:Realm)->Void)) {
        RealmBlock { (realm) in
            WriteWith(realm: realm, withoutNotifying: [], block: block)
        }
    }

    static func Write(withoutNotifying:[NotificationToken?], block:((_ realm:Realm)->Void)) {
        RealmBlock { (realm) in
            WriteWith(realm: realm, withoutNotifying: withoutNotifying, block: block)
        }
    }

    static func Delete(realm:Realm, model:Object) {
        if var model = model as? CanWriteIsDeleted {
            model.isDeleted = true
        }
        if !IsUseCloudRealm() {
            realm.delete(model)
        }
    }
    static func LocalOnlyDelete(realm:Realm, model:Object) {
        if var model = model as? CanWriteIsDeleted {
            model.isDeleted = true
        }
        realm.delete(model)
    }
    
    static func CheckIsLocalRealmCreated() -> Bool {
        let filePath = GetLocalRealmFilePath()
        if let path = filePath?.path {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }
    static func CheckIsCloudRealmCreated() -> Bool {
        let filePath = GetCloudRealmFilePath()
        if let path = filePath?.path {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    static var runLoop:RunLoop? = nil
    static var runLoopThread:Thread? = nil
    @objc static func startRealmRunLoopThread() {
        runLoopThread = Thread {
            runLoop = RunLoop.current
            guard let thread = runLoopThread else { return }
            while thread.isCancelled != true {
                RunLoop.current.run(mode: .default, before: .distantFuture)
            }
            Thread.exit()
        }
        guard let thread = runLoopThread else { return }
        thread.name = "RealmUtil runLoopThread: \(UUID().uuidString)"
        thread.start()
    }
    static func doOnRunLoop(block: @escaping () -> Void) {
        guard let runLoop = runLoop else { return }
        autoreleasepool {
            runLoop.perform(block)
        }
    }
    static func stopRunLoop() {
        guard let thread = runLoopThread else { return }
        thread.cancel()
    }
    
    @objc static func sync() {
        self.RealmBlock { realm in
            realm.refresh()
        }
    }
    
}

extension Object {
    @discardableResult
    func RealmUtilBlock<Result>(block: (_ realm:Realm) throws -> Result) rethrows -> Result {
        if let realm = self.realm {
            return try block(realm)
        }
        return try RealmUtil.RealmBlock { (realm) -> Result in
            return try block(realm)
        }
    }
}

protocol CanWriteIsDeleted {
    var isDeleted: Bool { get set }
}

struct Story: Codable {
    var url:String = ""
    var subtitle:String = ""
    var content:String = ""
    var novelID:String = ""
    var chapterNumber = 0
    var downloadDate:Date = Date(timeIntervalSince1970: -1)
    
    enum CodingKeys: String, CodingKey {
        case url
        case subtitle
        case content
        case novelID
        case chapterNumber
        case downloadDate
    }
    init() {}
    init(url:String, subtitle:String, content:String, novelID:String, chapterNumber:Int, downloadDate:Date) {
        self.url = url
        self.subtitle = subtitle
        self.content = content
        self.novelID = novelID
        self.chapterNumber = chapterNumber
        self.downloadDate = downloadDate
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        url = try values.decode(String.self, forKey: CodingKeys.url)
        subtitle = try values.decode(String.self, forKey: CodingKeys.subtitle)
        content = NovelSpeakerUtility.NormalizeNewlineString(string:(try values.decode(String.self, forKey: CodingKeys.content)))
        novelID = try values.decode(String.self, forKey: CodingKeys.novelID)
        chapterNumber = try values.decode(Int.self, forKey: CodingKeys.chapterNumber)
        downloadDate = try values.decode(Date.self, forKey: CodingKeys.downloadDate)
    }
    
    func CreateDuplicateOne() -> Story {
        return Story(url: url, subtitle: subtitle, content: content, novelID: novelID, chapterNumber: chapterNumber, downloadDate: downloadDate)
    }
    
    func readLocation(realm: Realm) -> Int {
        guard let bookmark = RealmBookmark.SearchObjectFromWith(realm: realm, type: .novelSpeechLocation, hint: novelID), bookmark.chapterNumber == chapterNumber else { return 0 }
        return bookmark.location
    }
    
    var storyID:String {
        get {
            return RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber)
        }
    }

    static func SetReadLocationWith(realm:Realm, novelID:String, chapterNumber:Int, location:Int) {
        let bookmark:RealmBookmark
        if let bookmarkTmp = RealmBookmark.SearchObjectFromWith(realm: realm, type: .novelSpeechLocation, hint: novelID) {
            bookmark = bookmarkTmp
        }else{
            bookmark = RealmBookmark()
            bookmark.novelID = novelID
            bookmark.id = RealmBookmark.CreateUniqueID(type: .novelSpeechLocation, hint: novelID)
        }
        bookmark.chapterNumber = chapterNumber
        bookmark.location = location
        realm.add(bookmark, update: .modified)
    }
    func SetCurrentReadLocationWith(realm:Realm, location:Int) {
        Story.SetReadLocationWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber, location: location)
        if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
            novel.m_readingChapterReadingPoint = location
        }
    }
    func GetSubtitle() -> String {
        if subtitle.count > 0 {
            return subtitle
        }
        for line in content.components(separatedBy: .newlines) {
            let trimedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimedLine.count > 0 {
                return trimedLine
            }
        }
        return "-"
    }
    
    func ownerNovel(realm: Realm) -> RealmNovel? {
        return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)
    }
}

// 現在実行中のバイナリの RealmUtil.currentSchemaVersion と、
// iCloud に保存されている currentSchemaVersion の違いを確認するための仕組みを提供します。
// 使い方としては RealmCloudVersionChecker.RunChecker() を呼び出して
// その RunChecker に与えた handler への呼び出しに適切に対応する、という形です。
// handler が呼び出された場合は iCloud に保存されているデータのバージョンが
// 現在実行中のバイナリでは対応できない未来のバージョンであるという事になるため、
// "一旦 SyncEngine を止めてから"
// 「iCloud の同期を止める」か
// 「アプリのアップデートを行う」の選択肢を出すような対応をユーザに求める
// といった対応を行うべきです。
// なお、この仕組みで発見できるのは「iCloud側に保存されている情報からすると
// 現在実行中のバイナリよりも新しいバージョンのデータ形式で
// iCloud側の情報が保存されている可能性がある」という事が検知できるだけです。
// なお、Realm+IceCream はそのようなデータ型でもそのまま使う事もできてしまうため、
// 古い schemaVersion のシステムが新しい schemaVersion のシステムのデータを書き換える事で
// データの不思議な改変が起こる可能性が発生します。
// 前述の通り、この仕組みは問題が発生している事を確認できるだけでその発生を止める事はできないため
// schemaVersion を上げる(データ型の変更を行う)場合には
// データの不思議な改変を起こさないような手法での更新を行う必要があることを肝に銘じてください。
// 問題が発生している事を確認できるだけ、というのは、
// iCloud側に保存されているデータが実行中の端末に降りてくるまでにタイムラグがあるため、
// この仕組みによって検知する「前」にデータを扱ってしまっている可能性があるためです。
// 従って、この仕組みではそのような問題へは対処"できません"。
//
// memo:
// 将来的にこの仕組みに頼る事になるような事がある場合に問題を大きくしないようにメモを残します。
// Realm+IceCream では class xxx : Object のメンバ変数を「追加」するだけにしたほうが良いです。
// メンバ変数の名前を変更した場合、iCloud上では
// 変更前のカラムが残った状態で変更後のカラムが追加されてしまいます。
// つまり、その後永遠に前のカラムが残った状態で運用されてしまうなどの問題が発生します。
// また、primaryKey に当たるメンバ変数の名前を変更する事は絶対に避けたほうが良いです。
// primaryKey が変わる前の object が残されてしまい、新しい primaryKey の object は観測できない、というような挙動を取ることになります。
// (なお、primaryKey を変更した後に最初に起動した端末ではその端末側に保存された Realm データが新しい primaryKey に変更されて保存されなおすために正常に動作したように見える挙動をとってしまうため、問題に気づきにくい状態になります)
// なお、似た話として Object の primaryKey を「書き換える」ような場合には
// 元の primaryKey の物を RealmUtil.delete() した上で、
// 新しく別の Object を生成して realm.write するべきです。
// そうしないと iCloud 上で古いデータが消えてしまいます。
@objc final class RealmCloudVersionChecker : Object {
    // インスタンスは一個限定です
    static let uniqueID = "NovelSepakerVersionChecker"
    @objc dynamic var id = RealmCloudVersionChecker.uniqueID
    @objc dynamic var isDeleted: Bool = false
    // 現在利用している RealmUtil.currentSchemaVersion を入れてある、という事にします
    @objc dynamic var currentSchemaVersion:Int = 0
    
    static func CheckCloudDataHasInvalidVersion() -> Bool {
        guard let cloudRealm = try? RealmUtil.GetCloudRealm(), let obj = cloudRealm.object(ofType: RealmCloudVersionChecker.self, forPrimaryKey: uniqueID) else { return false }
        return obj.currentSchemaVersion > RealmUtil.currentSchemaVersion
    }
    
    static var checkerObserverToken:NotificationToken? = nil
    // RunChecker() に渡した checkHandler が呼び出された時は
    // これに保存されている currentSchemaVersion が
    // このバイナリの期待している RealmUtil.currentSchemaVersion よりも大きい値だったという意味になります。
    static func RunChecker(checkerHandler:((_ newSchemaVersion:Int)->Void)?) {
        if !RealmUtil.IsUseCloudRealm() { return }
        RealmUtil.RealmBlock { (realm) -> Void in
            let obj:RealmCloudVersionChecker
            if let currentObj = realm.object(ofType: RealmCloudVersionChecker.self, forPrimaryKey: uniqueID) {
                obj = currentObj
            }else{
                obj = RealmCloudVersionChecker()
                obj.currentSchemaVersion = Int(RealmUtil.currentSchemaVersion)
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    realm.add(obj, update: .modified)
                }
            }
            if obj.currentSchemaVersion > RealmUtil.currentSchemaVersion {
                checkerHandler?(obj.currentSchemaVersion)
                return
            }
            checkerObserverToken = obj.observe({ (change) in
                switch change {
                case .change(_, let propertys):
                    for property in propertys {
                        if property.name == "currentSchemaVersion", let newValue = property.newValue as? Int {
                            if newValue > RealmUtil.currentSchemaVersion {
                                checkerHandler?(newValue)
                            }else{
                                
                            }
                            break
                        }
                    }
                default:
                    break
                }
            })
            // このタイミングで現在のバイナリの currentSchemaVersion の方が
            // 保存されている currentSchemaVersion より新しければ、
            // その値で上書きしておきます。
            if obj.currentSchemaVersion < RealmUtil.currentSchemaVersion {
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [checkerObserverToken]) { (realm) in
                    obj.currentSchemaVersion = Int(RealmUtil.currentSchemaVersion)
                }
            }
        }
    }
    static func StopChecker() {
        checkerObserverToken = nil
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["id", "isDeleted"]
    }
}
extension RealmCloudVersionChecker: CKRecordConvertible {
}
extension RealmCloudVersionChecker: CKRecordRecoverable {
}
extension RealmCloudVersionChecker: CanWriteIsDeleted {
}

// MARK: Model
@objc final class RealmStoryBulk : Object {
    @objc dynamic var id = "" // primary key は RealmStoryBulk.CreateUniqueID() で生成したものを使います。
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var novelID = ""
    @objc dynamic var chapterNumber = 0
    //let contentArray = List<Data>()
    @objc dynamic var storyListAsset:CreamAsset?
    
    static var bulkCount = 100
    static var storyCache:Story? = nil
    static var bulkCache:RealmStoryBulk? = nil
    
    // URL をファイル名として使いやすい文字列に変換します。具体的には、
    // 1. "/" を "%2F" に変換する(a)
    // 2. 変換後の文字列の長さが250未満であればそれを使う (FILE_MAX が 255 らしいので)
    // 3. Deflate で圧縮してbase64表現にしてみる(b)
    //    (b) が (a) よりも短い文字列であれば (b) を使う。そうでなければ (a) を使う。
    // というような事をします。
    // PATH_MAX は 1024 らしいのだけれど、保存場所のpathがどのくらいの深さにあるのかわからんのでなんとも言えない。
    static func URIToUniqueID(urlString:String) -> String {
        let tmpString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "/").inverted) ?? urlString
        if tmpString.count < 250 {
            return tmpString
        }
        guard let data = urlString.data(using: .utf8), let zipedData = NiftyUtility.compress(data: data) else {
            return tmpString
        }
        let base64ZipedData = zipedData.base64EncodedString()
        if base64ZipedData.count < tmpString.count {
            return base64ZipedData
        }
        return tmpString
    }
    // deflate の後 base64 にされたものか、"/" を "%2F" に変換されたもののどちらかが入っているはずなので
    // とりあえず base64 decode できるかを試して失敗したら "%2F" を元に戻したものを返します。
    static func UniqueIDToURI(uniqueID:String) -> String {
        guard let zipedData = Data(base64Encoded: uniqueID), let data = NiftyUtility.decompress(data: zipedData), let uri = String(data: data, encoding: .utf8) else {
            return uniqueID.replacingOccurrences(of: "%2f", with: "/").replacingOccurrences(of: "%2F", with: "/")
        }
        return uri
    }
    static func CreateUniqueID(novelID:String, chapterNumber:Int) -> String {
        return "\(chapterNumber):\(URIToUniqueID(urlString: novelID))"
    }
    static func CalcBulkChapterNumber(chapterNumber:Int) -> Int {
        return Int((chapterNumber - 1) / bulkCount) * bulkCount
    }
    static func CreateUniqueBulkID(novelID:String, chapterNumber:Int) -> String {
        let chapterNumberBulk = CalcBulkChapterNumber(chapterNumber: chapterNumber)
        return CreateUniqueID(novelID: novelID, chapterNumber: chapterNumberBulk)
    }
    static func StoryIDToNovelID(storyID:String) -> String {
        if let colonIndex = storyID.firstIndex(of: ":") {
            let index = storyID.index(colonIndex, offsetBy: 1)
            return UniqueIDToURI(uniqueID: String(storyID[index...]))
        }
        return ""
    }
    static func StoryIDToChapterNumber(storyID:String) -> Int {
        if let index = storyID.firstIndex(of: ":") {
            let numString = String(storyID[..<index])
            if let result = Int(numString) {
                return result
            }
        }
        return 0
    }
    static func StoryIDToBulkID(storyID:String) -> String {
        return CreateUniqueBulkID(novelID: StoryIDToNovelID(storyID: storyID), chapterNumber: StoryIDToChapterNumber(storyID: storyID))
    }
    
    static func StoryCreamAssetToStoryArray(asset:CreamAsset) -> [Story]? {
        guard let zipedData = asset.storedData() else {
            print("LoadStoryArray storedData() return nil. filePath: \(asset.filePath.absoluteString)")
            return nil
        }
        guard let data = NiftyUtility.decompress(data: zipedData) else {
            print("LoadStoryArray dataInflate() failed.")
            return nil
        }
        guard let storyDict = try? JSONDecoder().decode([Story].self, from: data) else {
            print("LoadStoryArray JSONDecoder.decode failed.")
            return nil
        }
        return storyDict
    }
    
    func LoadStoryArray() -> [Story]? {
        guard let asset = self.storyListAsset else {
            print("LoadStoryArray storyListAsset is nil")
            return nil
        }
        return RealmStoryBulk.StoryCreamAssetToStoryArray(asset: asset)
    }
    
    func OverrideStoryListAsset(storyArray:[Story]) {
        guard let data = try? JSONEncoder().encode(storyArray) else {
            print("WARN: [Story] の JSONEncode に失敗")
            return
        }
        guard let zipedData = NiftyUtility.compress(data: data) else {
            print("WARN: [Story] を JSON に変換した後、compress で失敗した")
            return
        }
        self.storyListAsset = CreamAsset.create(object: self, propName: "", data: zipedData)
    }
    #if false
    // 複数同時に登録する奴がチェックをサボっているために壊れたデータを生成してしまう可能性があるのでそれをチェックしながら追加するようなものを作ろうと思ったけれど、うまく作れていない物の残骸
    //
    /// Story を複数同時に登録する場合に使います。
    /// 注意: storyArray は chapterNumber が小さい順に sort されており、かつ、chapterNumber に抜けが無い事が必要です。
    /// SetStoryArrayWith() 内部ではその事実を"確認しません"。
    static func SetStoryArrayWith_new(realm:Realm, storyArray:[Story]) {
        print("SetStoryArrayWith in: \(storyArray.count)")
        func mergeBulkStoryArray(originalBulkStoryArray:[Story]?, newStoryArray:[Story]) -> [Story] {
            guard let newFirstStory = newStoryArray.first else {
                AppInformationLogger.AddLog(message: "newStoryArray に中身がありませんでしたので、空の配列を返します。", isForDebug: true)
                return []
            }
            let novelID = newFirstStory.novelID
            let bulkChapterNumber = CalcBulkChapterNumber(chapterNumber: newFirstStory.chapterNumber)
            if let originalFirstStory = originalBulkStoryArray?.first, originalFirstStory.chapterNumber != bulkChapterNumber {
                AppInformationLogger.AddLog(message: "originalBulkStoryArray が存在するのにその bulk の最初の chapterNumber(\(bulkChapterNumber)) の chapter が最初の chapter になっていない (\(originalFirstStory.chapterNumber) だった) ので、空の配列を返します。", isForDebug: true)
                return []
            }
            // lastChapterNumber: この bulk に保存されるべき chapter の最後の物
            // これは、newStoryArray の最後の物か、originalBulkStoryArray の最後の物のどちらか大きい値の物になるべき。
            var lastChapterNumber:Int = bulkChapterNumber
            lastChapterNumber = max(lastChapterNumber, originalBulkStoryArray?.last?.chapterNumber ?? 0)
            lastChapterNumber = max(lastChapterNumber, newStoryArray.last?.chapterNumber ?? 0)
            var currentChapterNumber = bulkChapterNumber
            var originalIndex:Int = 0
            var newIndex:Int = 0
            var result:[Story] = []
            var dummyDataAlertLogged = false
            // 一つづつ走査してresultに入れる。入れる優先順位は newStoryArray > originalBulkStoryArray > dummy の順
            while currentChapterNumber < lastChapterNumber {
                if newStoryArray.count > newIndex, currentChapterNumber == newStoryArray[newIndex].chapterNumber {
                    result.append(newStoryArray[newIndex])
                    newIndex += 1
                    originalIndex += 1
                    currentChapterNumber += 1
                    dummyDataAlertLogged = false
                    continue
                }else if let originalArray = originalBulkStoryArray, originalArray.count > originalIndex, currentChapterNumber == originalArray[originalIndex].chapterNumber {
                    result.append(originalArray[originalIndex])
                    originalIndex += 1
                    currentChapterNumber += 1
                    dummyDataAlertLogged = false
                    continue
                }
                // ここに来るということは、追加するべき物が newStoryArray にも originalBulkStoryArray にもなかった。ということでダミーデータで埋める
                if dummyDataAlertLogged == false {
                    AppInformationLogger.AddLog(message: "newStoryArray にも originalBulkStoryArray にも無い chapterNumber(\(currentChapterNumber)) を追加しないといけなかったので、ダミーデータを追加します。", isForDebug: true)
                    dummyDataAlertLogged = true
                }
                var dummyStory = Story()
                dummyStory.content = "-"
                dummyStory.chapterNumber = currentChapterNumber
                dummyStory.novelID = novelID
                result.append(dummyStory)
                currentChapterNumber += 1
            }
            return result
        }
        // [Story] を bulkCount に整列された [[Story]] に変換します
        func splitStoryArray(storyArray:[Story]) -> [[Story]] {
            var result:[[Story]] = []
            var index = 0
            while index < storyArray.count {
                let current = storyArray[index]
                let bulkChapterNumber = CalcBulkChapterNumber(chapterNumber: current.chapterNumber)
                let sliceMaxIndex = min(bulkCount - (current.chapterNumber - bulkChapterNumber), storyArray.count - index)
                let slice = storyArray[index..<sliceMaxIndex]
                result.append(Array(slice))
                index += sliceMaxIndex
            }
            return result
        }
        guard let firstChapter = storyArray.first, let lastChapter = storyArray.last else { return }
        let firstChapterNumber = firstChapter.chapterNumber
        let lastChapterNumber = lastChapter.chapterNumber
        for (i, s) in storyArray.enumerated() {
            if s.chapterNumber != (i + firstChapterNumber) {
                AppInformationLogger.AddLog(message: "追加されようとしている [Story] は chapterNumber にずれがあるようです。エラーとして追加はせず終了します。\n期待している chapterNumber: \(i + firstChapterNumber), 実際の chapterNumber: \(s.chapterNumber)", isForDebug: true)
                return
            }
        }
        let firstBulkChapterNumber = CalcBulkChapterNumber(chapterNumber: firstChapterNumber)
        var bulkIndex = 1
        while bulkIndex < firstBulkChapterNumber {
            
        }
        let splitedNewStoryArray = splitStoryArray(storyArray: storyArray)
        for bulkStoryArray in splitedNewStoryArray {
            guard let first = bulkStoryArray.first else { continue }
            
        }
        // 入力された [Story] よりも前の bulk が存在しなかった場合、それについてはダミーデータを入れておく必要があります。
        if let firstStory = storyArray.first {
            var bulkChapterNumber = CalcBulkChapterNumber(chapterNumber: firstStory.chapterNumber)
            while bulkChapterNumber > 0 {
                
            }
        }
        
        while storyArray.count > index {
            // 入力された [Story] を bulkCount 毎に処理します。
            // 既存の bulk があった場合には、その bulk の中に入っている [Story] を上書きする形で処理します。
            // また、bulk 内の [Story] が足りない場合にはダミーの [Story] を追加します。
            let currentStory = storyArray[index]
            let currentChapterNumber = currentStory.chapterNumber
            // 今入れようとしているBulkの [Story] を格納する配列
            var bulkStoryArray:[Story] = []
            let bulkOptional = SearchStoryBulkWith(realm: realm, novelID: currentStory.novelID, chapterNumber: currentChapterNumber)
            let prevBulkStoryArrayOptional = bulkOptional?.LoadStoryArray()
            if let bulk = bulkOptional, bulk.chapterNumber != currentChapterNumber, var prevBulkStoryArray = prevBulkStoryArrayOptional {
                // bulkの開始点である chapterNumber(bulkChapterNumber) と、入力された [Story] の(現時点での)先頭の chapterNumber が違うということで、既に保存されている bulk の中の [Story] が必要となる。
                if bulk.chapterNumber > currentChapterNumber {
                    AppInformationLogger.AddLog(message: "FATAL: [Story] を追加しようとした時、bulkの先頭の chapterNumber(\(bulk.chapterNumber))の方が追加されようとしている側の chapterNumber(\(currentChapterNumber)) よりも大きくなっています。これはロジック的に起こり得ないはずです。", appendix: [:], isForDebug: true)
                    return
                }
                // bulkChapterNumber != currentChapterNumber で、かつ、bulkChapterNumber > currentChapterNumber なのであるから、bulkChapterNumber < currentChapterNumber である。
                // 従って、内部に保存されている bulk の側から Story を取り出して埋めてやる必要がある。
                // lessChapterCount: 内部に保存されている bulk の側から埋められるべき Story の数
                let lessChapterCount = currentChapterNumber - bulk.chapterNumber
                if prevBulkStoryArray.count < lessChapterCount {
                    AppInformationLogger.AddLog(message: "[Story] を追加されようとしたけれど、追加されようとしている Story は Bulk内に保存されている Story よりも未来の物で、その間が存在しないようです。仕方がないので空の Story を追加します。", appendix: [
                        "既存のBulkの chapterNumber (開始点)": "\(bulk.chapterNumber)",
                        "既存のBulkの LoadStoryArray().count": "\(prevBulkStoryArray.count)",
                        "既存のBulkの .last.chapterNumber": "\(prevBulkStoryArray.last?.chapterNumber ?? -1)",
                        "追加されようとしている [Story].first.chapterNumber": "\(currentStory.chapterNumber)",
                    ], isForDebug: true)
                    var dummyStory = Story()
                    dummyStory.novelID = currentStory.novelID
                    dummyStory.chapterNumber = bulk.chapterNumber + prevBulkStoryArray.count
                    dummyStory.content = NSLocalizedString("RealmStoryBulk_DummStoryContent", comment: "-")
                    while prevBulkStoryArray.count < lessChapterCount {
                        prevBulkStoryArray.append(dummyStory)
                    }
                }
                bulkStoryArray.append(contentsOf: prevBulkStoryArray)
            }
            // この if文 を抜けてきた時点で、bulkStoryArray には入力された [Story] では足りない分の [Story] が格納されている
            // capacity: bulkCount まで詰めるとあと何個の Story が入れられるか
            let capacity = bulkCount - bulkStoryArray.count
            // storyArray から今回bulkに入れる Story の数
            let insertCount = min(capacity, storyArray.count - index)
            let sliceStoryArray = storyArray[index..<insertCount + index]
            bulkStoryArray.append(contentsOf: sliceStoryArray)
            // この時点で bulkStoryArray.count は bulkCount を上回っていないはずです
            assert(bulkStoryArray.count <= bulkCount)

            if let prevBulkStoryArray = prevBulkStoryArrayOptional, bulkStoryArray.count < prevBulkStoryArray.count {
                // 先に bulk に入っていた Story で追加された Story よりも後ろの物があった
                let sliceStoryArray = prevBulkStoryArray[bulkStoryArray.count..<prevBulkStoryArray.count]
                bulkStoryArray.append(contentsOf: sliceStoryArray)
            }
            // この時点でも bulkStoryArray.count は bulkCount を上回っていないはずです
            assert(bulkStoryArray.count <= bulkCount)

            let bulk:RealmStoryBulk
            if let originalBulk = bulkOptional {
                bulk = originalBulk
                if let cachedBulk = bulkCache, cachedBulk.id == bulk.id { bulkCache = nil }
            }else{
                bulk = RealmStoryBulk()
                bulk.id = CreateUniqueBulkID(novelID: currentStory.novelID, chapterNumber: currentStory.chapterNumber)
                bulk.novelID = currentStory.novelID
                bulk.chapterNumber = StoryIDToChapterNumber(storyID: bulk.id)
            }
            print("SetStoryArrayWith bulkChapter: \(bulk.chapterNumber) assign [Story].count: \(bulkStoryArray.count)")
            bulk.OverrideStoryListAsset(storyArray: Array(bulkStoryArray))
            realm.add(bulk, update: .modified)
            index += bulkStoryArray.count
        }
    }
    #endif
    
    /// Story を複数同時に登録する場合に使います。
    /// 注意: storyArray は chapterNumber が小さい順に sort されており、かつ、chapterNumber に抜けが無い事が必要です。
    /// SetStoryArrayWith() 内部ではその事実を"確認しません"。
    static func SetStoryArrayWith(realm:Realm, storyArray:[Story]) {
        var index = 0
        while storyArray.count > index {
            let story = storyArray[index]
            if let cachedStory = storyCache, cachedStory.chapterNumber == story.chapterNumber && cachedStory.novelID == story.novelID {
                storyCache = story
            }
            let novelID = story.novelID
            let chapterNumber = story.chapterNumber
            let bulkOptional = SearchStoryBulkWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber)
            let length = min(storyArray.count - index, bulkCount)
            var targetStoryArray = Array(storyArray[index ..< index + length])
            if length < bulkCount, let bulk = bulkOptional, let currentStoryArray = bulk.LoadStoryArray() {
                var tmpStoryArray:[Story] = []
                var lastChapterNumber = chapterNumber - 1
                for story in currentStoryArray {
                    if story.chapterNumber == chapterNumber {
                        break
                    }
                    tmpStoryArray.append(story)
                    lastChapterNumber = story.chapterNumber
                }
                if lastChapterNumber != chapterNumber - 1 {
                    AppInformationLogger.AddLog(message: "WARN: chapterNumber が期待していない値になっている。(既にある奴の末尾: \(lastChapterNumber), 追加される奴の先頭: \(chapterNumber), bulk.chapterNumber: \(bulk.chapterNumber), currentStoryArray.count: \(currentStoryArray.count)", appendix: ["stackTrace":NiftyUtility.GetStackTrace()], isForDebug: true)
                }
                tmpStoryArray.append(contentsOf: targetStoryArray)
                targetStoryArray = tmpStoryArray
            }
            let bulk:RealmStoryBulk
            if let originalBulk = bulkOptional {
                bulk = originalBulk
                if let cachedBulk = bulkCache, cachedBulk.id == bulk.id { bulkCache = nil }
            }else{
                bulk = RealmStoryBulk()
                bulk.id = CreateUniqueBulkID(novelID: novelID, chapterNumber: story.chapterNumber)
                bulk.novelID = novelID
                bulk.chapterNumber = StoryIDToChapterNumber(storyID: bulk.id)
            }
            bulk.OverrideStoryListAsset(storyArray: Array(targetStoryArray))
            realm.add(bulk, update: .modified)
            index += length
        }
    }
    
    /// Story を一つづつ登録する場合に使いますが、こちらは Realm.write で囲った物から呼び出される事を期待しています。
    /// 逆に言うと、Realm の write transaction を内部で呼び出しませんので、外部で呼び出す必要があります。
    static func SetStoryWith(realm:Realm, story:Story) {
        let novelID = story.novelID
        if story.chapterNumber <= 0 {
            print("story.chapterNumber <= 0! \(story.chapterNumber)")
        }
        if let cachedStory = storyCache, cachedStory.chapterNumber == story.chapterNumber && cachedStory.novelID == story.novelID {
            storyCache = story
        }
        if let bulk = SearchStoryBulkWith(realm: realm, novelID: novelID, chapterNumber: story.chapterNumber) {
            if let cachedBulk = bulkCache, cachedBulk.id == bulk.id { bulkCache = nil }
            var storyArray:[Story]
            if var storyArrayTmp = bulk.LoadStoryArray() {
                let bulkIndex = (story.chapterNumber - 1) % bulkCount
                if bulkIndex >= 0 && storyArrayTmp.count > bulkIndex {
                    storyArrayTmp[bulkIndex] = story
                }else{
                    if bulkIndex != storyArrayTmp.count {
                        print("WARN: 未来の chapter が追加されている？")
                    }
                    storyArrayTmp.append(story)
                }
                storyArray = storyArrayTmp
            }else{
                // bulk.storyListAsset からの読み込みに失敗したので空であったと仮定して1つ目として入れる
                storyArray = [story]
            }
            bulk.OverrideStoryListAsset(storyArray: storyArray)
            realm.add(bulk, update: .modified)
        }else{
            // bulk が無いので作る
            let bulk = RealmStoryBulk()
            bulk.id = CreateUniqueBulkID(novelID: novelID, chapterNumber: story.chapterNumber)
            bulk.novelID = novelID
            bulk.chapterNumber = StoryIDToChapterNumber(storyID: bulk.id)
            if (story.chapterNumber - 1) != bulk.chapterNumber {
                BehaviorLogger.AddLog(description: "WARN: 未来の chapter が追加されている。ここで追加されるのは bulk の ID にある chapterNumber と差がないもののはずです。", data: ["novelID": bulk.novelID, "bulkChapterNumber": bulk.chapterNumber, "bulkID": bulk.id])
            }
            bulk.OverrideStoryListAsset(storyArray: [story])
            realm.add(bulk, update: .modified)
        }
    }
    
    static func RemoveLastStoryWith(realm:Realm, novelID:String, checkTargetStoryID:String?) {
        guard let lastStoryBulk = realm.objects(RealmStoryBulk.self).filter("isDeleted = FALSE AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true).last else { return }
        guard var storyArray = lastStoryBulk.LoadStoryArray() else {
            print("WARN: RemoveLastStoryWith() LoadStoryArray() failed.")
            return
        }
        if let checkTargetStoryID = checkTargetStoryID, let story = storyArray.last, story.storyID != checkTargetStoryID {
            return
        }
        if let lastStory = storyArray.last, let cachedStory = storyCache, cachedStory.chapterNumber == lastStory.chapterNumber && cachedStory.novelID == lastStory.novelID {
            storyCache = nil
        }
        if let cachedBulk = bulkCache, cachedBulk.id == lastStoryBulk.id {
            bulkCache = nil
        }
        
        if storyArray.count <= 1 {
            realm.delete(lastStoryBulk)
        }else{
            storyArray.removeLast()
            lastStoryBulk.OverrideStoryListAsset(storyArray: storyArray)
            realm.add(lastStoryBulk, update: .modified)
        }
    }
    static func RemoveLastStoryWithCheckWith(realm: Realm, storyID:String) {
        RemoveLastStoryWith(realm: realm, novelID: StoryIDToNovelID(storyID: storyID), checkTargetStoryID: storyID)
    }
    static func RemoveAllStoryWith(realm:Realm, novelID:String) {
        if let cachedStory = storyCache, cachedStory.novelID == novelID {
            storyCache = nil
        }
        if let cachedBulk = bulkCache, cachedBulk.novelID == novelID {
            bulkCache = nil
        }
        let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID= %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        realm.delete(storyBulkArray)
    }
    // 指定された storyID を含み、それ以降のStoryを全て削除します。
    static func RemoveStoryChapterAndAfterWith(realm: Realm, storyID:String) {
        let novelID = StoryIDToNovelID(storyID: storyID)
        if let cachedStory = storyCache, cachedStory.novelID == novelID {
            storyCache = nil
        }
        if let cachedBulk = bulkCache, cachedBulk.novelID == novelID {
            bulkCache = nil
        }
        let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID= %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        let chapterNumber = StoryIDToChapterNumber(storyID: storyID)
        let bulkChapterNumber = CalcBulkChapterNumber(chapterNumber: chapterNumber)
        var isNeedDelete = false
        for storyBulk in storyBulkArray {
            if storyBulk.chapterNumber == bulkChapterNumber {
                isNeedDelete = true
                if bulkChapterNumber == chapterNumber {
                    // bulkChapterNumber が chapterNumber と同じという事は、その bulk は削除して良い。
                    realm.delete(storyBulk)
                    continue
                }
                if var storyArray = storyBulk.LoadStoryArray() {
                    while storyArray.last?.chapterNumber != chapterNumber {
                        storyArray.removeLast()
                    }
                    if storyArray.last?.chapterNumber == chapterNumber {
                        storyArray.removeLast()
                    }
                    storyBulk.OverrideStoryListAsset(storyArray: storyArray)
                    realm.add(storyBulk, update: .modified)
                }
            }
            if isNeedDelete {
                realm.delete(storyBulk)
                continue
            }
        }
        if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
            if chapterNumber > 1 {
                novel.m_lastChapterStoryID = CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber - 1)
            }
            realm.add(novel, update: .modified)
        }
    }
    
    // story.storyID で指定される位置に story を挿入します。
    // story.storyID で表される story 以降(story.storyIDで指定された物を含む) の物は storyID が +1 されます。
    #if !os(watchOS) // 何故かここを watchOS でビルドしようとすると abort(6) とかで失敗する(´・ω・`)
    static func InsertStoryWith(realm:Realm, story:Story) -> Bool {
        // bulk に story をねじ込みます。
        // bulk に元々入っていた story のうち、story 以降(story.storyIDで指定された物を含む) の物は storyID が +1 されます。
        // bulk に収まりきらなかった story があった場合、返り値の二番目に添えられます(storyIDは新しい物に書き換えられています)
        // bulk が対象の bulk でなかったり、story.storyID よりも前の storyID の story がない場合など
        // 不正な追加がなされようとした場合には (nil, 未定義) を返します
        func insertStoryTo(prevStoryArray:[Story]?, story:Story) -> ([Story]?, Story?) {
            let bulkStoryID_Target = CreateUniqueBulkID(novelID: story.novelID, chapterNumber: story.chapterNumber)
            var resultStoryArray:[Story] = []
            var isHit:Bool = false
            if (prevStoryArray?.count ?? 0) <= 0 && (story.chapterNumber % bulkCount) == 1 {
                return ([story], nil)
            }
            guard let prevStoryArray = prevStoryArray else { return (nil, nil) }
            for var currentStory in prevStoryArray {
                let bulkStoryID_Current = CreateUniqueBulkID(novelID: currentStory.novelID, chapterNumber: currentStory.chapterNumber)
                guard bulkStoryID_Target == bulkStoryID_Current else { return (nil, nil) }
                if currentStory.storyID == story.storyID {
                    resultStoryArray.append(story)
                    isHit = true
                }
                if currentStory.chapterNumber >= story.chapterNumber {
                    currentStory.chapterNumber += 1
                }
                resultStoryArray.append(currentStory)
            }
            if isHit == false, let lastChapterNumber = resultStoryArray.last?.chapterNumber, lastChapterNumber + 1 == story.chapterNumber {
                resultStoryArray.append(story)
                isHit = true
            }
            guard isHit == true else { return (nil, nil) }
            var kickOutStory:Story? = nil
            if resultStoryArray.count > bulkCount {
                kickOutStory = resultStoryArray.popLast()
            }
            return (resultStoryArray, kickOutStory)
        }
        var targetStory:Story? = story
        while let targetStoryUnwrapped = targetStory {
            let targetBulk = SearchStoryBulkWith(realm: realm, storyID: targetStoryUnwrapped.storyID)
            if targetBulk == nil && targetStoryUnwrapped.chapterNumber > bulkCount && SearchStoryBulkWith(realm: realm, storyID: CreateUniqueBulkID(novelID: targetStoryUnwrapped.novelID, chapterNumber: targetStoryUnwrapped.chapterNumber - bulkCount)) == nil {
                // 指定された story が入る bulk が無くて、
                // その一つ前の bulk もない場合は insert しちゃ駄目
                return false
            }
            let (storyArray, kickOutStory) = insertStoryTo(prevStoryArray: targetBulk?.LoadStoryArray() ?? nil, story: targetStoryUnwrapped)
            guard let storyArray = storyArray, storyArray.count > 0 else { return false }
            if let targetBulk = targetBulk {
                targetBulk.OverrideStoryListAsset(storyArray: storyArray)
                realm.add(targetBulk, update: .modified)
            }else{
                guard let story = storyArray.first else { return false }
                let bulk = RealmStoryBulk()
                bulk.id = CreateUniqueBulkID(novelID: story.novelID, chapterNumber: story.chapterNumber)
                bulk.novelID = story.novelID
                bulk.chapterNumber = StoryIDToChapterNumber(storyID: bulk.id)
                bulk.OverrideStoryListAsset(storyArray: Array(storyArray))
                realm.add(bulk, update: .modified)
            }
            targetStory = kickOutStory
        }
        if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: story.novelID) {
            novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: RealmStoryBulk.StoryIDToChapterNumber(storyID: novel.m_lastChapterStoryID) + 1)
            novel.lastDownloadDate = Date(timeIntervalSinceNow: -1)
            novel.lastReadDate = Date(timeIntervalSinceNow: 0)
            realm.add(novel, update: .modified)
        }
        return true
    }
    #endif
    
    // Write transaction の中で使います
    static func RemoveStoryWith(realm:Realm, story:Story) -> Bool {
        guard var storyBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: story.storyID) else { return false }
        var targetStory:Story? = story
        let targetNovelID = storyBulk.novelID
        while targetStory != nil {
            let nextBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: storyBulk.novelID, chapterNumber: storyBulk.chapterNumber + RealmStoryBulk.bulkCount + 1)
            let nextBulkFirstStory:Story? = nextBulk?.LoadStoryArray()?.first
            guard let currentStoryArray = storyBulk.LoadStoryArray() else { return false }
            var updatedStoryArray:[Story] = []
            var chapterNumber = storyBulk.chapterNumber + 1
            for var story in currentStoryArray {
                if story.storyID == targetStory?.storyID { continue }
                story.chapterNumber = chapterNumber
                chapterNumber += 1
                updatedStoryArray.append(story)
            }
            if updatedStoryArray.count < RealmStoryBulk.bulkCount, let nextBulkFirstStory = nextBulkFirstStory {
                var tmpStory = nextBulkFirstStory.CreateDuplicateOne()
                tmpStory.chapterNumber = chapterNumber
                updatedStoryArray.append(tmpStory)
                targetStory = nextBulkFirstStory
            }else{
                targetStory = nil
            }
            
            // Realm write transaction が必要な部分
            if updatedStoryArray.count > 0 {
                storyBulk.OverrideStoryListAsset(storyArray: updatedStoryArray)
                realm.add(storyBulk, update: .modified)
            }else{
                realm.delete(storyBulk)
            }
            
            guard let nextBulk = nextBulk else { break }
            storyBulk = nextBulk
        }

        // RealmNovel で書き換わる部分をなんとかする
        // ここまで来たなら目標の Story は消えているので RealmNovel 側で保持している StoryID をその分をずらす必要がある
        if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: targetNovelID) {
            if let lastChapterNumber = novel.lastChapterNumber {
                novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: lastChapterNumber - 1)
            }
            let readingChapterStoryID = novel.m_readingChapterStoryID
            if readingChapterStoryID == story.storyID {
                novel.m_readingChapterStoryID = ""
            }else{
                let readingChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: readingChapterStoryID)
                if readingChapterNumber >= story.chapterNumber {
                    novel.m_readingChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID:  targetNovelID, chapterNumber: readingChapterNumber - 1)
                }
            }
            realm.add(novel, update: .modified)
        }

        return true
    }
    
    static func SearchStoryBulkWith(realm:Realm, novelID:String, chapterNumber:Int) -> RealmStoryBulk? {
        //realm.refresh()
        let chapterNumberBulk = CalcBulkChapterNumber(chapterNumber: chapterNumber)
        if let cachedBulk = bulkCache, cachedBulk.chapterNumber == chapterNumberBulk && cachedBulk.novelID == novelID { return cachedBulk }
        //print("SearchStoryBulkWith(\"\(novelID)\", \"\(chapterNumber)\")")
        guard let result = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@ AND chapterNumber = %@", novelID, chapterNumberBulk).first else { return nil }
        return result
    }
    
    static func SearchStoryBulkWith(realm:Realm, storyID:String) -> RealmStoryBulk? {
        let novelID = StoryIDToNovelID(storyID: storyID)
        let chapterNumber = StoryIDToChapterNumber(storyID: storyID)
        return SearchStoryBulkWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber)
    }
    static func SearchStoryBulkWith(realm: Realm, novelID:String) -> Results<RealmStoryBulk>?{
        print("SearchStoryBulk(\"\(novelID)\")")
        return realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
    }
    
    static func StoryBulkArrayToStory(storyArray:[Story], chapterNumber: Int) -> Story? {
        let bulkIndex = (chapterNumber - 1) % bulkCount
        if bulkIndex < 0 || storyArray.count <= bulkIndex {
            return nil
        }
        return storyArray[bulkIndex]
    }
    
    static func SearchStoryWith(realm:Realm, novelID:String, chapterNumber:Int) -> Story? {
        if let cachedStory = storyCache, cachedStory.novelID == novelID && cachedStory.chapterNumber == chapterNumber {
            return cachedStory
        }
        guard let bulk = SearchStoryBulkWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber), let storyArray = bulk.LoadStoryArray() else { return nil }
        let bulkIndex = (chapterNumber - 1) % bulkCount
        if bulkIndex < 0 || storyArray.count <= bulkIndex {
            return nil
        }
        return storyArray[bulkIndex]
    }
    static func SearchStoryWith(realm:Realm, storyID:String) -> Story? {
        return SearchStoryWith(realm:realm, novelID: StoryIDToNovelID(storyID: storyID), chapterNumber: StoryIDToChapterNumber(storyID: storyID))
    }
    
    // 対象の小説について保存されている Story の個数と最後のStoryの chapterNumber のタプルを返します
    static func CountStoryFor(realm:Realm, novelID:String) -> (Int, Int, Story?) {
        var count:Int = 0
        var lastStoryChapterNumber:Int = -1
        var lastStory:Story? = nil
        let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        for storyBulk in storyBulkArray {
            autoreleasepool {
                if let storyArray = storyBulk.LoadStoryArray() {
                    count += storyArray.count
                    if let currentLastStory = storyArray.last {
                        lastStory = currentLastStory
                    }
                    lastStoryChapterNumber = storyArray.last?.chapterNumber ?? lastStoryChapterNumber
                }else{
                    print("WARN: SearchAllStoryFor LoadStoryArray() failed in \(storyBulk.id)")
                }
            }
        }
        return (count, lastStoryChapterNumber, lastStory)
    }
    
    static func GetAllChapterNumberFor(realm: Realm, novelID:String) -> [[Int]] {
        var result:[[Int]] = []
        let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        for storyBulk in storyBulkArray {
            autoreleasepool {
                if let storyArray = storyBulk.LoadStoryArray() {
                    let chapterNumberArray = storyArray.map({$0.chapterNumber})
                    result.append(chapterNumberArray)
                }else{
                    print("WARN: SearchAllStoryFor LoadStoryArray() failed in \(storyBulk.id)")
                }
            }
        }
        return result
    }
    
    static func SearchAllStoryBulkFor(realm: Realm, novelID:String, iterate:((RealmStoryBulk)->Void)){
        autoreleasepool {
            let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
            for storyBulk in storyBulkArray {
                autoreleasepool {
                    iterate(storyBulk)
                }
            }
        }
    }

    static func SearchAllStoryFor(realm: Realm, novelID:String, filterFunc:((Story)->Bool)? = nil, iterate:((Story)->Void)) {
        print("SearchAllStoryFor(\"\(novelID)\")")
        let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        for storyBulk in storyBulkArray {
            autoreleasepool {
            if let storyArray = storyBulk.LoadStoryArray() {
                    for story in storyArray {
                        if let filterFunc = filterFunc, filterFunc(story) == false {
                            continue
                        }
                        iterate(story)
                    }
                }else{
                    print("WARN: SearchAllStoryFor LoadStoryArray() failed in \(storyBulk.id)")
                }
            }
        }
    }
    /*
    static func SearchAllStoryFor(realm: Realm, novelID:String) -> [Story]? {
        print("SearchAllStoryFor(\"\(novelID)\")")
        let storyBulkArray = realm.objects(RealmStoryBulk.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        var result = [Story]()
        for storyBulk in storyBulkArray {
            if let storyArray = storyBulk.LoadStoryArray() {
                result.append(contentsOf: storyArray)
            }else{
                print("WARN: SearchAllStoryFor LoadStoryArray() failed in \(storyBulk.id)")
            }
        }
        return result
    }*/
    
    static func GetAllObjectsWith(realm: Realm) -> Results<RealmStoryBulk>? {
        return realm.objects(RealmStoryBulk.self).filter("isDeleted = false")
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["novelID", "chapterNumber", "isDeleted"]
    }
}
extension RealmStoryBulk: CKRecordConvertible {
}
extension RealmStoryBulk: CKRecordRecoverable {
}
extension RealmStoryBulk: CanWriteIsDeleted {
}

@objc enum NovelType: Int {
    case URL = 1
    case UserCreated = 2
}

@objc final class RealmNovel : Object, Identifiable {
    @objc dynamic var novelID : String = RealmNovel.CreateUniqueID() // novelID は primary key です。
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var m_type : Int = NovelType.URL.rawValue
    @objc dynamic var writer : String = ""
    @objc dynamic var title : String = ""
    @objc dynamic var url : String = ""
    @objc dynamic var createdDate : Date = Date()
    //@objc dynamic var likeLevel : Int8 = 0
    @objc dynamic var isNeedSpeechAfterDelete : Bool = false
    @objc dynamic var defaultSpeakerID : String = ""
    @objc dynamic var isNotNeedUpdateCheck: Bool = false

    // RealmStory等 に保存していて参照時にはそこから生成しようと思ったのだけれどアホみたいに遅いのでこちらに保存するようにします。
    @objc dynamic var m_lastChapterStoryID : String = ""
    @objc dynamic var lastDownloadDate : Date = Date()
    @objc dynamic var m_readingChapterStoryID : String = ""
    @objc dynamic var lastReadDate : Date = Date(timeIntervalSince1970: 0)
    let downloadDateArray = List<Date>()
    @objc dynamic var m_readingChapterReadingPoint : Int = 0
    @objc dynamic var m_readingChapterContentCount : Int = 0
    
    var id:String { get {return novelID} }

    var type : NovelType {
        get {
            return NovelType(rawValue: self.m_type) ?? NovelType.UserCreated
        }
        set {
            self.m_type = newValue.rawValue
        }
    }
    
    func RemoveRealmLink() -> RealmNovel {
        let obj = RealmNovel()
        obj.novelID = novelID
        obj.isDeleted = isDeleted
        obj.m_type = m_type
        obj.writer = writer
        obj.title = title
        obj.url = url
        obj.createdDate = createdDate
        obj.isNeedSpeechAfterDelete = isNeedSpeechAfterDelete
        obj.defaultSpeakerID = defaultSpeakerID
        obj.m_lastChapterStoryID = m_lastChapterStoryID
        obj.lastDownloadDate = lastDownloadDate
        obj.m_readingChapterStoryID = m_readingChapterStoryID
        obj.lastReadDate = lastReadDate
        obj.downloadDateArray.removeAll()
        obj.downloadDateArray.append(objectsIn: downloadDateArray)
        obj.m_readingChapterReadingPoint = m_readingChapterReadingPoint
        obj.m_readingChapterContentCount = m_readingChapterContentCount
        return obj
    }
    
    func linkedSpeechModSettingsWith(realm:Realm) -> [RealmSpeechModSetting]? {
        return realm.objects(RealmSpeechModSetting.self).filter({ (speechModSetting) -> Bool in
            return !speechModSetting.isDeleted && speechModSetting.targetNovelIDArray.contains(self.novelID)
        })
    }
    func linkedSpeechSectionConfigsWith(realm:Realm) -> [RealmSpeechSectionConfig]? {
        return realm.objects(RealmSpeechSectionConfig.self).filter({ (speechSectionConfig) -> Bool in
            return !speechSectionConfig.isDeleted && speechSectionConfig.targetNovelIDArray.contains(self.novelID)
        })
    }
    func linkedDisplaySettingsWith(realm:Realm) -> [RealmDisplaySetting]? {
        return realm.objects(RealmDisplaySetting.self).filter({ (displaySetting) -> Bool in
            return !displaySetting.isDeleted && displaySetting.targetNovelIDArray.contains(self.novelID)
        })
    }
    func linkedTagsWith(realm:Realm) -> [RealmNovelTag]? {
        return realm.objects(RealmNovelTag.self).filter({ (novelTag) -> Bool in
            return !novelTag.isDeleted && novelTag.targetNovelIDArray.contains(self.novelID)
        })
    }
    func firstChapterWith(realm:Realm) -> Story? {
        return RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 1))
    }
    func lastChapterWith(realm:Realm) -> Story? {
        return RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.m_lastChapterStoryID)
    }
    var lastChapterNumber : Int? {
        get {
            let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: m_lastChapterStoryID)
            if chapterNumber <= 0 {
                return nil
            }
            return chapterNumber
        }
    }
    func lastDownloadURLWith(realm:Realm) -> String? {
        return lastChapterWith(realm: realm)?.url
    }
    func readingChapterWith(realm:Realm) -> Story? {
        if self.m_readingChapterStoryID == "" { return nil }
        return RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.m_readingChapterStoryID)
    }
    var readingChapterNumber: Int? {
        get {
            let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: self.m_readingChapterStoryID)
            if chapterNumber <= 0 { return nil }
            return chapterNumber
        }
    }
    var isNewFlug: Bool {
        return lastDownloadDate > lastReadDate
    }
    
    func defaultSpeakerWith(realm:Realm) -> RealmSpeakerSetting? {
        if self.defaultSpeakerID.count <= 0 {
            return RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm)
        }
        guard let obj = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: self.defaultSpeakerID) else { return nil }
        if obj.isDeleted { return nil }
        return obj
    }
    
    // 推測によるアップデート頻度。単位は1日に何章分ダウンロードされたのか(1日に1章なら1、10日に1章なら0.1、1日に3章なら3)。
    // 計算としては 章数 / (現在 - 直近から数えて10個前のものがダウンロードされた日付)[日] なので、最後にダウンロードされた日付が古くても評価は下がる。
    // 最初に1000件とかダウンロードされた小説が既に更新終了していたとしても、10件分しか効果がないので10日経つと1に、100日経てば0.1になる。
    static let updateFrequencyTargetCount = 10
    func updateFrequency(novelLikeOrder:List<String>)-> Double {
        var likeLevel:Int = 0
        if let likeOrderIndex = novelLikeOrder.index(of: self.novelID) {
            likeLevel = novelLikeOrder.count - likeOrderIndex
        }
        guard let targetDownloadDate = downloadDateArray.suffix(10).first else {
            return 1.0 / 60.0*60.0*24.0*30.0 // 未ダウンロードのものは30日に1度の頻度とする。
        }
        let count = Double(downloadDateArray.suffix(RealmNovel.updateFrequencyTargetCount).count)
        let diffTimeInSec = Date().timeIntervalSince1970 - targetDownloadDate.timeIntervalSince1970
        // likeLevel がある場合は updateFrequency を1日分早い感じにします。
        return count / (diffTimeInSec / (60.0*60.0*24)) + Double(likeLevel) * count
    }
    
    public static func CreateUniqueID() -> String {
        return "\(NovelSpeakerUtility.UserCreatedContentPrefix)\(NSUUID().uuidString)"
    }
    
    static func GetAllObjectsWith(realm: Realm) -> Results<RealmNovel>? {
        return realm.objects(RealmNovel.self).filter("isDeleted = false")
    }
    
    static func SearchNovelWith(realm:Realm, novelID:String) -> RealmNovel? {
        if let result = realm.object(ofType: RealmNovel.self, forPrimaryKey: novelID), result.isDeleted == false {
            return result
        }
        // 登録したばかりの小説は読み込めない場合があるみたいなので、refresh() してからもう一回やってみます
        realm.refresh()
        if let result = realm.object(ofType: RealmNovel.self, forPrimaryKey: novelID), result.isDeleted == false {
            return result.RemoveRealmLink()
        }
        return nil
    }

    static func SearchNovelWith(realm: Realm, novelIDArray:[String]) -> Results<RealmNovel>? {
        return realm.objects(RealmNovel.self).filter("novelID IN %@", novelIDArray)
    }
    
    @discardableResult
    static func AddNewNovelOnlyText(content:String, title:String) -> String {
        return RealmUtil.RealmBlock { (realm) -> String in
            let novel = RealmNovel()
            novel.type = .UserCreated
            novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            novel.lastReadDate = Date(timeIntervalSince1970: 1)
            novel.lastDownloadDate = Date()
            var story = Story()
            story.novelID = novel.novelID
            story.chapterNumber = 1
            story.content = content.replacingOccurrences(of: "\u{00}", with: "")
            RealmUtil.WriteWith(realm: realm) { (realm) in
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: 1)
                novel.AppendDownloadDate(realm: realm, date: novel.lastDownloadDate)
                realm.add(novel, update: .modified)
            }
            return novel.novelID
        }
    }
    static func AddNewNovelWithMultiplText(contents:[String], title:String) -> String {
        return RealmUtil.RealmBlock { (realm) -> String in
            let novel = RealmNovel()
            novel.type = .UserCreated
            novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: contents.count)
            var chapterNumber = 1
            RealmUtil.WriteWith(realm: realm) { realm in
                for content in contents {
                    if content.count <= 0 { continue }
                    var story = Story()
                    story.novelID = novel.novelID
                    story.chapterNumber = chapterNumber
                    story.content = content.replacingOccurrences(of: "\u{00}", with: "")
                    RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                    chapterNumber += 1
                    novel.AppendDownloadDate(realm: realm, date: Date())
                }
                realm.add(novel, update: .modified)
            }
            return novel.novelID
        }
    }
    // contentArray を1章目からのものとして上書きします。realm は Write で渡してください
    static func OverrideStoryContentArrayWith(realm:Realm, novelID:String, contentArray:[String]) -> Bool {
        guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return false }
        var chapterNumber = 1
        var storyArray:[Story] = []
        for content in contentArray {
            if content.count <= 0 { continue }
            var story = Story()
            story.novelID = novel.novelID
            story.chapterNumber = chapterNumber
            story.content = content.replacingOccurrences(of: "\u{00}", with: "")
            storyArray.append(story)
            chapterNumber += 1
            novel.AppendDownloadDate(realm: realm, date: Date())
        }
        RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
        return true
    }
    

    static func AddNewNovelWithFirstStoryState(state:StoryState) -> (String?, String?)  {
        return RealmUtil.RealmBlock { (realm) -> (String?, String?) in
            let novelID = state.url.absoluteString
            guard novelID.count > 0 else { return (nil, NSLocalizedString("RealmNovel_AddNewNovelWithFirstStoryState_ERROR_InvalidNovelID", comment: "不正なNovelIDが指定されています")) }
            guard let content = state.content, content.count > 0 else { return (nil, NSLocalizedString("RealmNovel_AddNewNovelWithFirstStoryState_ERROR_InvalidContent", comment: "本文の中身がありませんでした")) }
            let prevNovel = SearchNovelWith(realm: realm, novelID: novelID)
            if prevNovel != nil { return (nil, NSLocalizedString("RealmNovel_AddNewNovelWithFirstStoryState_ERROR_NovelAlreadyAlive", comment: "本棚に同じ小説が登録されています(URLが同じ場合はタイトルが変わっても同じ小説と判定されます)") + ": " + (prevNovel?.title ?? "nil")) }
            let novel = RealmNovel()
            novel.novelID = novelID
            novel.url = novelID
            novel.title = (state.title ?? novelID).trimmingCharacters(in: .whitespacesAndNewlines)
            if let writer = state.author {
                novel.writer = writer
            }
            novel.type = .URL
            novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 1)
            var story = Story()
            story.content = content.replacingOccurrences(of: "\u{00}", with: "")
            story.novelID = novel.novelID
            story.chapterNumber = 1
            story.url = novelID
            RealmUtil.WriteWith(realm: realm) { (realm) in
                realm.add(novel, update: .modified)
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                for tagName in state.tagArray {
                    RealmNovelTag.AddTag(realm: realm, name: tagName, novelID: novelID, type: "keyword")
                }
            }
            return (novelID, nil)
        }
    }
    
    func AppendDownloadDate(realm:Realm, date:Date) {
        downloadDateArray.append(date)
        while downloadDateArray.count > 10 {
            downloadDateArray.remove(at: 0)
        }
    }
    func AppendDownloadDate(realm:Realm, dateArray:[Date]) {
        var dateArray = Array(downloadDateArray)
        dateArray.append(contentsOf: dateArray)
        while dateArray.count > 10 {
            dateArray.remove(at: 0)
        }
        downloadDateArray.removeAll()
        downloadDateArray.append(objectsIn: dateArray)
    }
    
    func delete(realm:Realm) {
        RealmStoryBulk.RemoveAllStoryWith(realm: realm, novelID: self.novelID)
        if let speechModSettingArray = linkedSpeechModSettingsWith(realm: realm) {
            for speechModSetting in speechModSettingArray {
                speechModSetting.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let speechSectionConfigArray = linkedSpeechSectionConfigsWith(realm: realm) {
            for speechSectionConfig in speechSectionConfigArray {
                speechSectionConfig.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let displaySettingArray = linkedDisplaySettingsWith(realm: realm) {
            for displaySetting in displaySettingArray {
                displaySetting.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let tagArray = linkedTagsWith(realm: realm) {
            for tag in tagArray {
                tag.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let globalState = RealmGlobalState.GetInstanceWith(realm: realm), let index = globalState.novelLikeOrder.index(of: self.novelID) {
            globalState.novelLikeOrder.remove(at: index)
        }
        if let bookmark = RealmBookmark.GetSpeechBookmark(realm: realm, novelID: self.novelID) {
            bookmark.delete(realm: realm)
        }
        NovelSpeakerUtility.RemoveOuterNovelAttributes(novelID: self.novelID)
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override var description:String
    {
        get {
            return title
        }
    }
    
    override class func primaryKey() -> String? {
        return "novelID"
    }
    
    override static func indexedProperties() -> [String] {
        return ["writer", "title", "novelID", "isDeleted", "lastDownloadDate", "lastReadDate", "isNotNeedUpdateCheck"]
    }
}
extension RealmNovel: CKRecordConvertible {
}
extension RealmNovel: CKRecordRecoverable {
}
extension RealmNovel: CanWriteIsDeleted {
}
func == (lhs: RealmNovel, rhs: RealmNovel) -> Bool {
    return lhs.novelID == rhs.novelID
}

@objc final class RealmSpeechModSetting : Object {
    @objc dynamic var before : String = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var after : String = ""
    @objc dynamic var createdDate = Date()
    @objc dynamic var isUseRegularExpression : Bool = false
    
    static let anyTarget = "novelspeakerdata://any"
    let targetNovelIDArray = List<String>()
    
    func targetNovelArrayWith(realm:Realm) -> [RealmNovel]? {
        return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
            return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
        })
    }
    
    static func GetAllObjectsWith(realm:Realm) -> Results<RealmSpeechModSetting>? {
        return realm.objects(RealmSpeechModSetting.self).filter("isDeleted = false")
    }

    static func SearchFromWith(realm: Realm, beforeString:String) -> RealmSpeechModSetting? {
        if let result = realm.object(ofType: RealmSpeechModSetting.self, forPrimaryKey: beforeString), result.isDeleted == false {
            return result
        }
        return nil
    }

    static func SearchSettingsFor(realm: Realm, novelID:String) -> LazyFilterSequence<Results<RealmSpeechModSetting>>? {
        return realm.objects(RealmSpeechModSetting.self).filter("isDeleted = false").filter({ (setting) -> Bool in
                return setting.targetNovelIDArray.contains(anyTarget) || setting.targetNovelIDArray.contains(novelID)
        })
    }

    func unref(realm:Realm, novelID:String) {
        if let index = targetNovelIDArray.index(of: novelID) {
            targetNovelIDArray.remove(at: index)
            if targetNovelIDArray.count <= 0 {
                delete(realm: realm)
            }
        }
    }
    func delete(realm:Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }

    override class func primaryKey() -> String? {
        return "before"
    }
    
    override static func indexedProperties() -> [String] {
        return ["before", "after", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechModSetting: CKRecordConvertible {
}
extension RealmSpeechModSetting: CKRecordRecoverable {
}
extension RealmSpeechModSetting: CanWriteIsDeleted {
}

@objc final class RealmSpeechWaitConfig : Object {
    @objc dynamic var targetText : String = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var delayTimeInSec : Float = 0.0
    @objc dynamic var createdDate = Date()
    
    static func GetAllObjectsWith(realm: Realm) -> Results<RealmSpeechWaitConfig>? {
        return realm.objects(RealmSpeechWaitConfig.self).filter("isDeleted = false")
    }

    static func SearchFromWith(realm:Realm, targetText:String) -> RealmSpeechWaitConfig? {
        if let result = realm.object(ofType: RealmSpeechWaitConfig.self, forPrimaryKey: targetText), result.isDeleted == false {
            return result
        }
        return nil
    }

    func delete(realm:Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override class func primaryKey() -> String? {
        return "targetText"
    }
    
    override static func indexedProperties() -> [String] {
        return ["targetText", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechWaitConfig: CKRecordConvertible {
}
extension RealmSpeechWaitConfig: CKRecordRecoverable {
}
extension RealmSpeechWaitConfig: CanWriteIsDeleted {
}

@objc final class RealmSpeakerSetting : Object {
    // name が primary key です
    @objc dynamic var name = NSLocalizedString("SpeakerSetting_NewSpeakerSetting", comment: "新規話者設定")
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var pitch : Float = 1.0
    @objc dynamic var rate : Float = 0.5
    @objc dynamic var lmd : Float = 1.0
    @objc dynamic var acc : Float = 1.0
    @objc dynamic var base : Int32 = 1
    @objc dynamic var volume : Float = 1.0
    @objc dynamic var type : String = "AVSpeechSynthesizer"
    @objc dynamic var voiceIdentifier : String = GuessBestVoiceIdentifier()
    @objc dynamic var locale : String = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    @objc dynamic var createdDate = Date()
    
    static func GetAllObjectsWith(realm: Realm) -> Results<RealmSpeakerSetting>? {
        return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false")
    }
    
    static func GuessBestVoiceIdentifier() -> String {
        let bestVoiceIdentifier:[String:[String]] = [
            "ja": [
                "com.apple.ttsbundle.siri_female_ja-JP_premium",
                "com.apple.ttsbundle.siri_male_ja-JP_premium",
                "com.apple.ttsbundle.siri_female_ja-JP-premium",
                "com.apple.ttsbundle.siri_male_ja-JP-premium",
                "com.apple.ttsbundle.siri_female_ja-JP_compact",
                "com.apple.ttsbundle.siri_male_ja-JP_compact",
                "com.apple.ttsbundle.Kyoko-premium",
                "com.apple.ttsbundle.Otoya-premium",
                "com.apple.ttsbundle.Kyoko-compact",
                "com.apple.ttsbundle.Otoya-compact"
            ]
        ]
        let currentLocale = Locale.current.identifier
        let aliveVoices = AVSpeechSynthesisVoice.speechVoices()
        // 利用可能な言語は国しかみないことにします。("ja_JP" なら ja しかみないの意味)
        let currentCountry = currentLocale.components(separatedBy: "_").first ?? "ja"
        let currentLocaleVoiceArray = aliveVoices.filter({$0.language.range(of: currentCountry)?.lowerBound == $0.language.startIndex})
        
        // 事前に定義されている良い話者リストがあるならそこから選ぶ
        if let targetList = bestVoiceIdentifier[currentCountry] {
            for identifier in targetList {
                if currentLocaleVoiceArray.filter({$0.identifier == identifier}).count > 0 {
                    return identifier
                }
            }
        }
        // 事前に用意されていないのならテキトーにsortした後、_premium とついている最初のものを選ぶ
        for voice in currentLocaleVoiceArray.sorted(by: {$0.identifier > $1.identifier}) {
            if voice.identifier.contains("premium") {
                return voice.identifier
            }
        }
        // それでも無いならテキトーに作った object の identifier を使う
        let dummyVoice = AVSpeechSynthesisVoice()
        return dummyVoice.identifier
    }
    
    static func SearchFromWith(realm: Realm, name:String) -> RealmSpeakerSetting? {
        if let result = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: name), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    func delete(realm:Realm) {
        if let sectionConfigArray = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm)?.filter("speakerID = %@", self.name) {
            for sectionConfig in sectionConfigArray {
                sectionConfig.unref(realm: realm, speakerID: self.name)
            }
        }
        if let novelArray = RealmNovel.GetAllObjectsWith(realm: realm)?.filter("defaultSpeakerID = %@", self.name), let defaultSpeakerID = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm)?.name {
            for novel in novelArray {
                novel.defaultSpeakerID = defaultSpeakerID
            }
        }
        RealmUtil.Delete(realm: realm, model: self)
    }

    override class func primaryKey() -> String? {
        return "name"
    }
    
    override static func indexedProperties() -> [String] {
        return ["name", "createdDate", "isDeleted"]
    }
}
extension RealmSpeakerSetting: CKRecordConvertible {
}
extension RealmSpeakerSetting: CKRecordRecoverable {
}
extension RealmSpeakerSetting: CanWriteIsDeleted {
}

@objc final class RealmSpeechSectionConfig : Object {
    @objc dynamic var name = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var startText = "「"
    @objc dynamic var endText = "」"
    @objc dynamic var createdDate = Date()
    @objc dynamic var speakerID: String = ""
    
    static let anyTarget = "novelspeakerdata://any"
    let targetNovelIDArray = List<String>()
    
    func speakerWith(realm:Realm) -> RealmSpeakerSetting? {
        return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.speakerID).first
    }
    func targetNovelArrayWith(realm: Realm) -> [RealmNovel]? {
        return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
            return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
        })
    }
    // 指定された NovelID に対する default設定以外 の section config をリストにして返します。
    // 複雑なクエリになるので何度も呼び出すような使い方はしないほうが良いです。
    static func SearchSettingsFor(realm: Realm, novelID:String) -> Dictionary<String, RealmSpeechSectionConfig>.Values? {
        var result:[String:RealmSpeechSectionConfig] = [:]
        // anyTarget の物を一旦設定して
        for target in realm.objects(RealmSpeechSectionConfig.self).filter("isDeleted = false").filter({ (setting) -> Bool in
            return setting.targetNovelIDArray.contains(anyTarget)
        }) {
            result[target.startText] = target
        }
        // novelID の物で上書きしたものが目標の設定
        for target in realm.objects(RealmSpeechSectionConfig.self).filter("isDeleted = false").filter({ (setting) -> Bool in
            return setting.targetNovelIDArray.contains(novelID)
        }) {
            result[target.startText] = target
        }
        return result.values
    }

    static func GetAllObjectsWith(realm:Realm) -> Results<RealmSpeechSectionConfig>? {
        return realm.objects(RealmSpeechSectionConfig.self).filter("isDeleted = false")
    }
    
    static func SearchFromWith(realm: Realm, name:String) -> RealmSpeechSectionConfig? {
        if let result = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: name), result.isDeleted == false {
            return result
        }
        return nil
    }

    func unref(realm: Realm, novelID: String) {
        if let index = targetNovelIDArray.index(of: novelID) {
            targetNovelIDArray.remove(at: index)
            if targetNovelIDArray.count <= 0 {
                delete(realm: realm)
            }
        }
    }
    func unref(realm: Realm, speakerID: String) {
        if self.speakerID == speakerID {
            delete(realm: realm)
        }
    }
    func delete(realm: Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    func AddTargetNovelIDWith(realm: Realm, novelID: String) {
        if novelID.count <= 0 {
            return
        }
        if targetNovelIDArray.contains(novelID) { return }
        RealmUtil.WriteWith(realm: realm) { (realm) in
            self.targetNovelIDArray.append(novelID)
        }
    }
    
    override class func primaryKey() -> String? {
        return "name"
    }
    
    override static func indexedProperties() -> [String] {
        return ["name", "startText", "createdDate", "speakerID", "isDeleted"]
    }
}
extension RealmSpeechSectionConfig: CKRecordConvertible {
}
extension RealmSpeechSectionConfig: CKRecordRecoverable {
}
extension RealmSpeechSectionConfig: CanWriteIsDeleted {
}

enum SpeechViewButtonTypes:String, Codable {
    case openCurrentWebPage = "openCurrentWebPage"
    case openWebPage = "openWebPage"
    case reload = "reload"
    case share = "share"
    case search = "search"
    case edit = "edit"
    case backup = "backup"
    case detail = "detail"
    case skipBackward = "skipBackward"
    case skipForward = "skipForward"
    case showTableOfContents = "showTableOfContents"
    case searchByText = "searchByText"
}

struct SpeechViewButtonSetting: Codable {
    let type:SpeechViewButtonTypes
    var isOn:Bool
    
    static let defaultSetting:[SpeechViewButtonSetting] = [
        SpeechViewButtonSetting(type: .showTableOfContents, isOn: false),
        SpeechViewButtonSetting(type: .skipBackward, isOn: false),
        SpeechViewButtonSetting(type: .skipForward, isOn: false),
        SpeechViewButtonSetting(type: .openCurrentWebPage, isOn: false),
        SpeechViewButtonSetting(type: .openWebPage, isOn: true),
        SpeechViewButtonSetting(type: .reload, isOn: true),
        SpeechViewButtonSetting(type: .share, isOn: true),
        SpeechViewButtonSetting(type: .search, isOn: true),
        SpeechViewButtonSetting(type: .searchByText, isOn: false),
        SpeechViewButtonSetting(type: .backup, isOn: false),
        SpeechViewButtonSetting(type: .detail, isOn: true),
        SpeechViewButtonSetting(type: .edit, isOn: true),
    ]
    // 与えられた配列を、defaultSetting に存在するtypeの物を全て含んだ状態にして返します。
    // つまり、壊れていて空の配列になっていれば defaultSetting そのものになるし、
    // 新しい要素が将来的に追加された時に、その要素が含まれないデータを読み込んだ場合でも
    // その新しい要素が追加された状態の配列に修正する、という事をします。
    static func ValidateAndFixSettingArray(settingArray:[SpeechViewButtonSetting]) -> [SpeechViewButtonSetting] {
        var result:[SpeechViewButtonSetting] = []
        var aliveSet:Set<SpeechViewButtonTypes> = Set<SpeechViewButtonTypes>()
        for setting in defaultSetting {
            aliveSet.insert(setting.type)
        }
        for setting in settingArray {
            result.append(setting)
            aliveSet.remove(setting.type)
        }
        for type in aliveSet {
            for setting in defaultSetting {
                if type == setting.type {
                    result.append(setting)
                    break
                }
            }
        }
        return result
    }
    static func DataToSettingArray(data:Data) -> [SpeechViewButtonSetting] {
        guard let result = try? JSONDecoder().decode([SpeechViewButtonSetting].self, from: data) else { return defaultSetting }
        return ValidateAndFixSettingArray(settingArray: result)
    }
    static func SettingArrayToData(settingArray:[SpeechViewButtonSetting]) -> Data? {
        return try? JSONEncoder().encode(settingArray)
    }
}

enum BookshelfViewButtonTypes:String, Codable {
    case iCloudPull = "iCloudPull"
    case iCloudPush = "iCloudPush"
    case search = "search"
    case edit = "edit"
    case reload = "reaload"
    case order = "order"
    case downloadStatus = "downloadStatus"
    case switchFolder = "switchFolder"
    case stopDownload = "stopDownload"
}

struct BookshelfViewButtonSetting: Codable {
    let type:BookshelfViewButtonTypes
    var isOn:Bool
    
    static let defaultSetting:[BookshelfViewButtonSetting] = [
        //BookshelfViewButtonSetting(type: .iCloudPull, isOn: false),
        //BookshelfViewButtonSetting(type: .iCloudPush, isOn: false),
        //BookshelfViewButtonSetting(type: .search, isOn: false),
        BookshelfViewButtonSetting(type: .switchFolder, isOn: true),
        //BookshelfViewButtonSetting(type: .downloadStatus, isOn: false),
        BookshelfViewButtonSetting(type: .order, isOn: true),
        BookshelfViewButtonSetting(type: .stopDownload, isOn: false),
        BookshelfViewButtonSetting(type: .reload, isOn: true),
        BookshelfViewButtonSetting(type: .edit, isOn: true),
    ]
    // 与えられた配列を、defaultSetting に存在するtypeの物を全て含んだ状態にして返します。
    // つまり、壊れていて空の配列になっていれば defaultSetting そのものになるし、
    // 新しい要素が将来的に追加された時に、その要素が含まれないデータを読み込んだ場合でも
    // その新しい要素が追加された状態の配列に修正する、という事をします。
    static func ValidateAndFixSettingArray(settingArray:[BookshelfViewButtonSetting]) -> [BookshelfViewButtonSetting] {
        var result:[BookshelfViewButtonSetting] = []
        var aliveSet:Set<BookshelfViewButtonTypes> = Set<BookshelfViewButtonTypes>()
        for setting in defaultSetting {
            aliveSet.insert(setting.type)
        }
        for setting in settingArray {
            result.append(setting)
            aliveSet.remove(setting.type)
        }
        for type in aliveSet {
            for setting in defaultSetting {
                if type == setting.type {
                    result.append(setting)
                    break
                }
            }
        }
        return result
    }
    static func DataToSettingArray(data:Data) -> [BookshelfViewButtonSetting] {
        guard let result = try? JSONDecoder().decode([BookshelfViewButtonSetting].self, from: data) else { return defaultSetting }
        return ValidateAndFixSettingArray(settingArray: result)
    }
    static func SettingArrayToData(settingArray:[BookshelfViewButtonSetting]) -> Data? {
        return try? JSONEncoder().encode(settingArray)
    }
}
// HTTPCookie を Codable にするのが難しそうだったのでwrapperでごまかします。
// で、HTTPCookie.name とかを参照しても良さそうなのですが、
// アクセサからは全ての情報を参照できなさそうなので
// properties の内容を問答無用で全部保存することにします。(´・ω・`)
class CodableHTTPCookie: Codable {
    class CodableValue: Codable, CustomStringConvertible {
        // HTTPCookie.properties の value には Date と String しか存在しなさそう
        // (HTTPCookieのドキュメントによると "All properties can handle an NSString value, but some can also handle other types." らしいので文字列で指定するのはアリの模様)ですが
        // 意味的には bool 等もあるようなので一応それらも保存できるようにします。
        enum CodableValueType:String, Codable {
            case date
            case string
            case int
            case bool
        }
        let date:Date?
        let string:String?
        let int:Int?
        let bool:Bool?
        let type:CodableValueType
        
        init(date:Date){
            self.date = date
            string = nil
            int = nil
            bool = nil
            type = .date
        }
        init(string:String){
            self.string = string
            date = nil
            int = nil
            bool = nil
            type = .string
        }
        init(int:Int){
            self.int = int
            date = nil
            string = nil
            bool = nil
            type = .int
        }
        init(bool:Bool){
            self.bool = bool
            date = nil
            string = nil
            int = nil
            type = .bool
        }
        func GetValue() -> Any? {
            switch type {
            case .date:
                return date
            case .string:
                return string
            case .int:
                return int
            case .bool:
                return bool
            }
            return nil
        }
        var description:String {
            get {
                switch type {
                case .date:
                    return date?.description ?? "nil(date)"
                case .string:
                    return string ?? "nil(string)"
                case .int:
                    guard let int = int else { return "nil(int)" }
                    return "\(int)"
                case .bool:
                    guard let bool = bool else { return "nil(bool)" }
                    return bool ? "true" : "false"
                }
            }
        }
    }
    
    let properties:[String : CodableValue]
    
    init(from:HTTPCookie) {
        guard let fromProperties = from.properties else { properties = [:]; return }
        var prop:[String:CodableValue] = [:]
        for (key, value) in fromProperties {
            if let date = value as? Date {
                prop[key.rawValue] = CodableValue(date:date)
            }else if let string = value as? String {
                prop[key.rawValue] = CodableValue(string: string)
            }else if let int = value as? Int {
                prop[key.rawValue] = CodableValue(int: int)
            }else if let bool = value as? Bool {
                prop[key.rawValue] = CodableValue(bool: bool)
            }else{
                print("WARNING: HTTPCookie に謎の type が保存されていた: \(key.rawValue): \(String(describing: type(of: value)))")
            }
        }
        properties = prop
    }
    
    var httpCookie: HTTPCookie? {
        get {
            var prop:[HTTPCookiePropertyKey:Any] = [:]
            for (key, value) in properties {
                if let value = value.GetValue() {
                    prop[HTTPCookiePropertyKey(key)] = value
                }
            }
            return HTTPCookie(properties: prop)
        }
    }
    
    
    static func ConvertArrayToCodable(cookieArray:[HTTPCookie]) -> [CodableHTTPCookie] {
        return cookieArray.map({$0.createCodable()})
    }
    static func ConvertArrayFromCodable(cookieArray:[CodableHTTPCookie]) -> ([HTTPCookie], [CodableHTTPCookie]) {
        var result:[HTTPCookie] = []
        var failedResult:[CodableHTTPCookie] = []
        for cookie in cookieArray {
            if let httpCookie = cookie.httpCookie {
                result.append(httpCookie)
            }else{
                failedResult.append(cookie)
            }
        }
        return (result, failedResult)
    }
}

extension HTTPCookie {
    func createCodable() -> CodableHTTPCookie {
        return CodableHTTPCookie(from: self)
    }
}

@objc enum NovelDisplayType: Int {
    case textView = 1
}

/// 本棚の並び替え順
@objc enum NarouContentSortType: Int {
    case NovelUpdatedAt = 0
    case Title = 1
    case Writer = 2
    case Ncode = 3
    case SelfCreatedFolder = 4
    case KeywordTag = 5
    case NovelUpdatedAtWithFolder = 6
    case LastReadDate = 7
    case LikeLevel = 8
    case WebSite = 9
    case CreatedDate = 10
}

/// 繰り返し再生の対象タイプ
@objc enum RepeatSpeechType: Int {
    case NoRepeat = 0 // 繰り返し再生はしない
    case RewindToFirstStory = 1 // 全ての章が対象(全ての章を読み終えたら最初の章に戻る)
    case RewindToThisStory = 2 // 一つの章が対象(一つの章を読み終えたらその章の最初に戻る)
    case GoToNextLikeNovel = 3 // 「お気に入り」に登録されている小説のうち、未読の物に切り替えて再生する
    case GoToNextSameFolderdNovel = 4 // 同じ「フォルダ」に登録されている小説のうち、未読のものに切り替えて再生する
    case GoToNextSelectedFolderdNovel = 5 // 指定フォルダの小説のうち未読の物を再生
    case GoToNextSameWriterNovel = 6 // 同じ著者の小説のうち未読の物を再生
    case GoToNextSameWebsiteNovel = 7 // 同じWebサイトの小説のうち未読の物を再生
}

/// 残されるメニュー項目の対象タイプ
enum MenuItemsNotRemovedType: String {
    /*
     発見した全てのもの
     canPerformAction: _accessibilityPauseSpeaking:
     canPerformAction: _accessibilitySpeak:
     canPerformAction: _accessibilitySpeakLanguageSelection:
     canPerformAction: _accessibilitySpeakSentence:
     canPerformAction: _accessibilitySpeakSpellOut:
     canPerformAction: _addShortcut:
     canPerformAction: _define:
     canPerformAction: _findSelected:
     canPerformAction: _insertDrawing:
     canPerformAction: _lookup:
     canPerformAction: _promptForReplace:
     canPerformAction: _share:
     canPerformAction: _showTextStyleOptions:
     canPerformAction: _translate:
     canPerformAction: _transliterateChinese:
     canPerformAction: captureTextFromCamera:
     canPerformAction: checkSpeechTextWithSender:
     canPerformAction: copy:
     canPerformAction: cut:
     canPerformAction: delete:
     canPerformAction: makeTextWritingDirectionLeftToRight:
     canPerformAction: makeTextWritingDirectionRightToLeft:
     canPerformAction: paste:
     canPerformAction: select:
     canPerformAction: selectAll:
     canPerformAction: setSpeechModForThisNovelSettingWithSender:
     canPerformAction: setSpeechModSettingWithSender:
     canPerformAction: toggleBoldface:
     canPerformAction: toggleItalics:
     canPerformAction: toggleUnderline:
     
     呼び出された順のもの(おそらく表示順)
     "cut:",
     "copy:", // コピー
     "paste:",
     "delete:",
     "select:",
     "selectAll:",
     "_promptForReplace:",
     "_transliterateChinese:",
     "_insertDrawing:",
     "captureTextFromCamera:",
     "toggleBoldface:",
     "toggleItalics:",
     "toggleUnderline:",
     "makeTextWritingDirectionRightToLeft:",
     "makeTextWritingDirectionLeftToRight:",
     "_findSelected:",
     "_define:", // 調べる
     "_translate:", // 翻訳
     "_addShortcut:", // ユーザ辞書...
     "_accessibilitySpeak:", // 読み上げ
     "_accessibilitySpeakSpellOut:", // スペル
     "_share:",
     "setSpeechModSettingWithSender:",
     "setSpeechModForThisNovelSettingWithSender:",
     "checkSpeechTextWithSender:",
     */
    case copy // コピー
    case define // 調べる
    case translate // 翻訳
    case addShortcut // ユーザ辞書...
    case share // 共有

    func localizedString() -> String {
        switch self {
        case .copy:
            return NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_copy", comment: "コピー")
        case .define:
            return NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_define", comment: "調べる")
        case .translate:
            return NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_translate", comment: "翻訳")
        case .addShortcut:
            return NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_addShortcut", comment: "ユーザ辞書...")
        case .share:
            return NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_share", comment: "共有")
        }
    }
    static func convertFromLocalizedString(localizedString: String) -> MenuItemsNotRemovedType? {
        switch localizedString {
        case NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_copy", comment: "コピー"):
            return .copy
        case NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_define", comment: "調べる"):
            return .define
        case NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_addShortcut", comment: "ユーザ辞書..."):
            return .addShortcut
        case NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_translate", comment: "翻訳"):
            return .translate
        case NSLocalizedString("RealmModels_MenuItemsNotRemoved_Name_share", comment: "共有"):
            return .share
        default:
            return nil
        }
    }
    
    func isTargetSelector(selector: Selector) -> Bool {
        switch self {
            #if !os(watchOS)
        case .copy:
            return selector == #selector(UIResponderStandardEditActions.copy(_:))
            #else
        default:
            return false
            #endif
        case .define:
            return selector.description == "_define:"
        case .addShortcut:
            return selector.description == "_addShortcut:"
        case .translate:
            return selector.description == "_translate:"
        case .share:
            return selector.description == "_share:"
        }
    }
}

enum RepeatSpeechLoopType: String {
    case normal = "Normal"
    case noCheckReadingPoint = "NoCheckReadingPoint"
}

enum LikeButtonDialogType: Int {
    case noDialog = 0 // ダイアログを出さない
    case dialogOnRequested = 1 // ONにするときだけダイアログを出す
    case dialogOffRequested = 2 // OFFにするときだけダイアログを出す
    case dialogAlwaysRequested = 3 // ONでもOFFでもダイアログを出す
}

@objc final class RealmGlobalState: Object {
    static public let UniqueID = "only one object"
    @objc dynamic var id = UniqueID
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var maxSpeechTimeInSec = 60*60*24-60
    @objc dynamic var isSpeechWaitSettingUseExperimentalWait = false
    let webImportBookmarkArray = List<String>()
    @objc dynamic var readedPrivacyPolicy = ""
    @objc dynamic var isOpenRecentNovelInStartTime = true
    @objc dynamic var isLicenseReaded = false
    @objc dynamic var isDuckOthersEnabled = false
    @objc dynamic var isMixWithOthersEnabled = false
    @objc dynamic var isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = false
    @objc dynamic var isPlaybackDurationEnabled = false
    @objc dynamic var isShortSkipEnabled = false
    @objc dynamic var isReadingProgressDisplayEnabled = false
    @objc dynamic var isMenuItemIsAddNovelSpeakerItemsOnly = false
    @objc dynamic var isPageTurningSoundEnabled = false
    @objc dynamic var m_bookSelfSortType : Int = Int(NarouContentSortType.Title.rawValue)
    @objc dynamic var IsDisallowsCellularAccess = false
    @objc dynamic var IsNeedConfirmDeleteBook = false
    @objc dynamic var fgColor = Data()
    @objc dynamic var bgColor = Data()
    @objc dynamic var defaultDisplaySettingID = ""
    @objc dynamic var defaultSpeakerID = ""
    @objc dynamic var currentReadingNovelID = ""
    @objc dynamic var currentWebSearchSite = ""
    let autoSplitStringList = List<String>()
    @objc dynamic var novelSpeakerSiteInfoURL = ""
    @objc dynamic var autopagerizeSiteInfoURL = ""
    @objc dynamic var defaultSpeechModURL = ""
    @objc dynamic var searchInfoURL = ""
    @objc dynamic var speechViewButtonSettingArrayData = Data()
    @objc dynamic var cookieArrayData = Data()
    @objc dynamic var m_DisplayType : Int = NovelDisplayType.textView.rawValue
    @objc dynamic var bookshelfViewButtonSettingArrayData = Data()
    @objc dynamic var m_repeatSpeechType : Int = RepeatSpeechType.NoRepeat.rawValue
    @objc dynamic var m_repeatSpeechLoopType : String = RepeatSpeechLoopType.normal.rawValue
    @objc dynamic var isAnnounceAtRepatSpeechTime = true
    @objc dynamic var isOverrideRubyIsEnabled = false
    @objc dynamic var notRubyCharactorStringArray = "・、 　?？!！"
    @objc dynamic var isIgnoreURIStringSpeechEnabled = false
    @objc dynamic var isEnableSwipeOnStoryView = true
    @objc dynamic var isDisableNarouRuby = false
    @objc dynamic var isNeedDisableIdleTimerWhenSpeechTime = false
    @objc dynamic var likeButtonDialogType: Int = LikeButtonDialogType.noDialog.rawValue
    let novelLikeOrder = List<String>()
    let menuItemsNotRemoved = List<String>()
    
    static let isForceSiteInfoReloadIsEnabledKey = "NovelSpeaker_IsForceSiteInfoReloadIsEnabled"
    static func GetIsForceSiteInfoReloadIsEnabled() -> Bool {
        let userDefaults = UserDefaults.standard
        userDefaults.register(defaults: [RealmGlobalState.isForceSiteInfoReloadIsEnabledKey : false])
        return userDefaults.bool(forKey: RealmGlobalState.isForceSiteInfoReloadIsEnabledKey)
    }
    static func SetIsForceSiteInfoReloadIsEnabled(newValue:Bool) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(newValue, forKey: RealmGlobalState.isForceSiteInfoReloadIsEnabledKey)
    }
    
    var bookShelfSortType : NarouContentSortType {
        get {
            return NarouContentSortType(rawValue: Int(m_bookSelfSortType)) ?? NarouContentSortType.Title
        }
        set {
            m_bookSelfSortType = Int(newValue.rawValue)
        }
    }
    // 表示形式用(将来的に縦書きにするとかWebページそのものを表示するとかそういうのに対応しようって奴)
    var novelDisplayType : NovelDisplayType {
        get {
            return NovelDisplayType(rawValue: self.m_DisplayType) ?? NovelDisplayType.textView
        }
        set {
            self.m_DisplayType = newValue.rawValue
        }
    }
    var repeatSpeechType : RepeatSpeechType {
        get {
            return RepeatSpeechType(rawValue: Int(m_repeatSpeechType)) ?? RepeatSpeechType.NoRepeat
        }
        set {
            m_repeatSpeechType = Int(newValue.rawValue)
        }
    }
    var repeatSpeechLoopType : RepeatSpeechLoopType {
        get {
            return RepeatSpeechLoopType(rawValue: m_repeatSpeechLoopType) ?? RepeatSpeechLoopType.normal
        }
        set {
            m_repeatSpeechLoopType = newValue.rawValue
        }
    }
    func defaultDisplaySettingWith(realm:Realm) -> RealmDisplaySetting? {
        return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false AND name = %@", self.defaultDisplaySettingID).first
    }
    func defaultSpeakerWith(realm: Realm) -> RealmSpeakerSetting? {
        return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.defaultSpeakerID).first
    }
    func calcLikeLevel(novelID:String) -> Int {
        guard let index = novelLikeOrder.index(of: novelID) else { return 0 }
        return novelLikeOrder.count - index
    }
    // background fetch の設定は その端末 だけに依存するようにしないとおかしなことになるので、UserDefaults.standard を使います
    static let isBackgroundNovelFetchEnabledKey = "NovelSpeaker_RealmModels_IsBackgroundNovelFetchEnabled"
    var isBackgroundNovelFetchEnabled : Bool {
        get {
            let userDefaults = UserDefaults.standard
            userDefaults.register(defaults: [RealmGlobalState.isBackgroundNovelFetchEnabledKey : false])
            return userDefaults.bool(forKey: RealmGlobalState.isBackgroundNovelFetchEnabledKey)
        }
        set {
            let userDefaults = UserDefaults.standard
            userDefaults.set(newValue, forKey: RealmGlobalState.isBackgroundNovelFetchEnabledKey)
        }
    }
    var backgroundColor:UIColor? {
        get {
            if let color = try? JSONSerialization.jsonObject(with: bgColor, options: .allowFragments) as? NSDictionary, let red = color.object(forKey: "red") as? NSNumber, let green = color.object(forKey: "green") as? NSNumber, let blue = color.object(forKey: "blue") as? NSNumber, let alpha = color.object(forKey: "alpha") as? NSNumber {
                return UIColor(red: CGFloat(red.floatValue), green: CGFloat(green.floatValue), blue: CGFloat(blue.floatValue), alpha: CGFloat(alpha.floatValue))
            }
            #if !os(watchOS)
            if #available(iOS 13.0, *) {
                return UIColor.systemBackground
            }
            #endif
            return UIColor.white
        }
        set(color) {
            var red:CGFloat = -1.0
            var green:CGFloat = -1.0
            var blue:CGFloat = -1.0
            var alpha:CGFloat = -1.0
            guard let color = color else {
                bgColor = Data()
                return
            }
            if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                var colorSetting = Dictionary<String,Float>()
                colorSetting["red"] = Float(red)
                colorSetting["green"] = Float(green)
                colorSetting["blue"] = Float(blue)
                colorSetting["alpha"] = Float(alpha)
                if let jsonData = try? JSONSerialization.data(withJSONObject: colorSetting, options: []) {
                    bgColor = jsonData
                }
            }
        }
    }
    var foregroundColor:UIColor? {
        get {
            if let color = try? JSONSerialization.jsonObject(with: fgColor, options: .allowFragments) as? NSDictionary, let red = color.object(forKey: "red") as? NSNumber, let green = color.object(forKey: "green") as? NSNumber, let blue = color.object(forKey: "blue") as? NSNumber, let alpha = color.object(forKey: "alpha") as? NSNumber {
                return UIColor(red: CGFloat(red.floatValue), green: CGFloat(green.floatValue), blue: CGFloat(blue.floatValue), alpha: CGFloat(alpha.floatValue))
            }
            #if !os(watchOS)
            if #available(iOS 13.0, *) {
                return UIColor.label
            }
            #endif
            return UIColor.black
        }
        set(color) {
            var red:CGFloat = -1.0
            var green:CGFloat = -1.0
            var blue:CGFloat = -1.0
            var alpha:CGFloat = -1.0
            guard let color = color else {
                fgColor = Data()
                return
            }
            if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                var colorSetting = Dictionary<String,Float>()
                colorSetting["red"] = Float(red)
                colorSetting["green"] = Float(green)
                colorSetting["blue"] = Float(blue)
                colorSetting["alpha"] = Float(alpha)
                if let jsonData = try? JSONSerialization.data(withJSONObject: colorSetting, options: []) {
                    fgColor = jsonData
                }
            }
        }
    }
    static func GetLastReadStory(realm: Realm) -> Story? {
        return GetLastReadNovel(realm: realm)?.readingChapterWith(realm: realm)
    }
    static func GetLastReadNovel(realm: Realm) -> RealmNovel? {
        guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return nil }
        return RealmNovel.SearchNovelWith(realm: realm, novelID: globalState.currentReadingNovelID)
    }
    
    static public func GetInstanceWith(realm:Realm) -> RealmGlobalState? {
        guard let obj = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: UniqueID) else { return nil }
        if obj.isDeleted { return nil }
        return obj
    }

    func GetSpeechViewButtonSetting() -> [SpeechViewButtonSetting] {
        return SpeechViewButtonSetting.DataToSettingArray(data: self.speechViewButtonSettingArrayData)
    }
    func SetSpeechViewButtonSettingWith(realm:Realm, newValue:[SpeechViewButtonSetting]) {
        self.speechViewButtonSettingArrayData = SpeechViewButtonSetting.SettingArrayToData(settingArray: newValue) ?? Data()
    }
    
    func GetBookshelfViewButtonSetting() -> [BookshelfViewButtonSetting] {
        return BookshelfViewButtonSetting.DataToSettingArray(data: self.bookshelfViewButtonSettingArrayData)
    }
    func SetBookshelfViewButtonSettingWith(realm:Realm, newValue:[BookshelfViewButtonSetting]) {
        self.bookshelfViewButtonSettingArrayData = BookshelfViewButtonSetting.SettingArrayToData(settingArray: newValue) ?? Data()
    }
    
    @discardableResult
    func MergeCookieArrayWith(realm:Realm, cookieArray:[HTTPCookie]) -> Bool {
        let currentCookieArray = GetCookieArray() ?? []
        let filterdCookieArray = NiftyUtility.RemoveExpiredCookie(cookieArray: NiftyUtility.MergeCookieArray(currentCookieArray: currentCookieArray, newCookieArray: cookieArray))
        let codableArray = CodableHTTPCookie.ConvertArrayToCodable(cookieArray: filterdCookieArray)
        guard let cookieData = try? JSONEncoder().encode(codableArray) else { return false }
        self.cookieArrayData = cookieData
        return true
    }
    
    func GetCookieArray() -> [HTTPCookie]? {
        guard let codableArray = try? JSONDecoder().decode([CodableHTTPCookie].self, from: self.cookieArrayData) else { return nil }
        return NiftyUtility.RemoveExpiredCookie(cookieArray: CodableHTTPCookie.ConvertArrayFromCodable(cookieArray: codableArray).0)
    }

    override class func primaryKey() -> String? {
        return "id"
    }
}
extension RealmGlobalState: CKRecordConvertible {
}
extension RealmGlobalState: CKRecordRecoverable {
}
extension RealmGlobalState: CanWriteIsDeleted {
}

@objc final class RealmDisplaySetting: Object {
    @objc dynamic var name : String = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var textSizeValue: Float = 58.0
    @objc dynamic var lineSpacing: Float = 3.0
    @objc dynamic var fontID = ""
    @objc dynamic var m_ViewType: String = ViewType.normal.rawValue
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    enum ViewType: String, CaseIterable {
        case normal = "Normal"
        case webViewVertical = "WebViewVertical"
        case webViewHorizontal = "WebViewHorizontal"
        case webViewVertical2Column = "WebViewVertical2Column"
        case webViewOriginal = "WebViewOriginal"
    }

    func targetNovelArrayWith(realm:Realm) -> [RealmNovel]? {
        return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
            return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
        })
    }
    
    static func GetAllObjectsWith(realm:Realm) -> Results<RealmDisplaySetting>? {
        return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false")
    }

    static func SearchFromWith(realm: Realm, name:String) -> RealmDisplaySetting? {
        if let result = realm.object(ofType: RealmDisplaySetting.self, forPrimaryKey: name), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    static func convertFontSizeValue(textSizeValue:Float) -> Float {
        var value = textSizeValue
        if value < 1.0 {
            value = 50.0;
        }else if value > 100.0 {
            value = 100.0;
        }
        let num = pow(1.05, value) + 1.0;
        return num;
    }

    var font : UIFont {
        get {
            let fontSize = RealmDisplaySetting.convertFontSizeValue(textSizeValue: self.textSizeValue)
            let fontName = self.fontID
            if fontName.count > 0, let font = UIFont(name: fontName, size: CGFloat(fontSize)) {
                return font
            }
            return UIFont.systemFont(ofSize: CGFloat(fontSize))
        }
    }

    // value は 1 から 100 までを変化していて、実際に開く行間の値(pixel数？)を返す。
    // 計算としては基本が 1.05^value の曲線(最初なだらかで最後急激に上がる奴)で、value が 100 の時には 500 になるような値とします。
    // NSAttributeString の lineSpacing は、フォントサイズを含んだ値になるようなので、
    // 「行間」という単語からするとよくわからん動きになるけれどまぁいいかとします。
    static func convertLineSpacingValueFrom(lineSpacing:Float) -> CGFloat {
        var value = Float(lineSpacing)
        if value < 0.0 {
            value = 0.0;
        }else if value > 100.0 {
            value = 100.0;
        }
        return CGFloat(pow(1.05, value) * 499 / pow(1.05, 99) + 1.0)
    }
    var lineSpacingDisplayValue: CGFloat {
        get {
            return RealmDisplaySetting.convertLineSpacingValueFrom(lineSpacing: self.lineSpacing)
        }
    }
    
    var viewType:ViewType {
        get {
            guard let viewType = ViewType(rawValue: m_ViewType) else { return ViewType.normal }
            return viewType
        }
        set {
            m_ViewType = newValue.rawValue
        }
    }

    func unref(realm: Realm, novelID: String) {
        if let index = targetNovelIDArray.index(of: novelID) {
            targetNovelIDArray.remove(at: index)
            if targetNovelIDArray.count <= 0 {
                delete(realm: realm)
            }
        }
    }
    func delete(realm:Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override class func primaryKey() -> String? {
        return "name"
    }
    override static func indexedProperties() -> [String] {
        return ["name", "createdDate", "isDeleted"]
    }
}
extension RealmDisplaySetting:CKRecordConvertible{
}
extension RealmDisplaySetting:CKRecordRecoverable{
}
extension RealmDisplaySetting: CanWriteIsDeleted {
}

@objc final class RealmNovelTag: Object {
    // type+name を primaryKey にします。
    @objc dynamic var id: String = ""
    @objc dynamic var type : String = ""
    @objc dynamic var name : String = ""
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var hint : String = ""
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    struct TagType {
        static let Keyword = "keyword"
        static let Folder = "folder"
    }
    
    func targetNovelArrayWith(realm:Realm) -> [RealmNovel]? {
        return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
            return !(novel.isDeleted) && self.targetNovelIDArray.contains(novel.novelID)
        }).sorted { (a, b) -> Bool in
            guard let aIndex = self.targetNovelIDArray.index(of: a.novelID) else { return false }
            guard let bIndex = self.targetNovelIDArray.index(of: b.novelID) else { return true }
            return aIndex < bIndex
        }
    }
    
    func targetNovelArrayFrom(novelID2NovelMap:[String:RealmNovel]) -> [RealmNovel]? {
        var result = [RealmNovel]()
        for novelID in self.targetNovelIDArray {
            if let novel = novelID2NovelMap[novelID] {
                result.append(novel)
            }
        }
        if result.count <= 0 { return nil }
        return result
    }
    
    static func CreateNewTag(name:String, type:String) -> RealmNovelTag {
        let tag = RealmNovelTag()
        tag.id = CreateUniqueID(name: name, type: type)
        tag.name = name
        tag.type = type
        return tag
    }
    
    static func GetAllObjectsWith(realm: Realm) -> Results<RealmNovelTag>? {
        return RealmUtil.RealmBlock {
            return $0.objects(RealmNovelTag.self).filter("isDeleted = false")
        }
    }
    static func GetObjectsFor(realm: Realm, type:String) -> Results<RealmNovelTag>? {
        return GetAllObjectsWith(realm: realm)?.filter("type = %@", type)
    }
    
    static func SearchWith(realm: Realm, name:String, type:String) -> RealmNovelTag? {
        guard let obj = realm.object(ofType: RealmNovelTag.self, forPrimaryKey: RealmNovelTag.CreateUniqueID(name: name, type: type)) else { return nil }
        if obj.isDeleted { return nil }
        return obj
    }

    static func SearchWith(realm: Realm, novelID:String, type:String) -> LazyFilterSequence<Results<RealmNovelTag>>? {
        return realm.objects(RealmNovelTag.self).filter("isDeleted = false AND type = %@", type).filter({ (tag) -> Bool in
            return tag.targetNovelIDArray.contains(novelID)
        })
    }
    
    // RealmWrite の中で呼んでください
    static func AddTag(realm: Realm, name:String, novelID: String, type: String) {
        let tagName = NovelSpeakerUtility.CleanTagString(tag: name)
        if tagName.count <= 0 || novelID.count <= 0 {
            return
        }
        if let tag = SearchWith(realm: realm, name: tagName, type: type) {
            if !tag.targetNovelIDArray.contains(novelID) {
                tag.targetNovelIDArray.append(novelID)
            }
        }else{
            let tag = CreateNewTag(name: tagName, type: type)
            tag.targetNovelIDArray.append(novelID)
            realm.add(tag, update: .modified)
        }
    }
    
    static func CreateUniqueID(name:String, type:String) -> String {
        return "\(type)\n\(name)"
    }
    static func TagIDToName(tagID:String) -> String {
        if let colonIndex = tagID.firstIndex(of: "\n") {
            let index = tagID.index(colonIndex, offsetBy: 1)
            return String(tagID[index...])
        }
        return ""
    }
    static func TagIDToType(tagID:String) -> String {
        if let index = tagID.firstIndex(of: "\n") {
            return String(tagID[..<index])
        }
        return ""
    }
    
    func unref(realm:Realm, novelID:String) {
        if let index = targetNovelIDArray.index(of: novelID) {
            targetNovelIDArray.remove(at: index)
            if targetNovelIDArray.count <= 0 {
                delete(realm: realm)
            }
        }
    }
    func delete(realm:Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["id", "name", "type", "createdDate", "isDeleted", "hint"]
    }
}
extension RealmNovelTag: CKRecordConvertible {
}
extension RealmNovelTag: CKRecordRecoverable {
}
extension RealmNovelTag: CanWriteIsDeleted {
}

@objc final class RealmBookmark: Object {
    @objc dynamic var id = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var createdDate = Date()
    @objc dynamic var novelID:String = ""
    @objc dynamic var chapterNumber:Int = 0
    @objc dynamic var location:Int = 0
    
    enum BookmarkType:String {
        case novelSpeechLocation = "novelSpeechLocation"
        case userBookmark = "userBookmark"
    }
    
    static func CreateUniqueID(type:BookmarkType, hint:String) -> String {
        return "\(type.rawValue):\(hint)"
    }
    static func UniqueIDToHint(uniqueID:String) -> String {
        if let colonIndex = uniqueID.firstIndex(of: ":") {
            let index = uniqueID.index(colonIndex, offsetBy: 1)
            return String(uniqueID[index...])
        }
        return ""
    }
    static func UniqueIDToType(uniqueID:String) -> BookmarkType? {
        if let index = uniqueID.firstIndex(of: ":") {
            switch String(uniqueID[..<index]) {
            case BookmarkType.novelSpeechLocation.rawValue:
                return BookmarkType.novelSpeechLocation
            case BookmarkType.userBookmark.rawValue:
                return BookmarkType.userBookmark
            default:
                return nil
            }
        }
        return nil
    }

    static func SetBookmarkWith(realm: Realm, type:BookmarkType, hint:String, novelID:String, chapterNumber:Int, location:Int){
        if let obj = SearchObjectFromWith(realm: realm, type: type, hint: hint) {
            if obj.novelID == novelID, obj.chapterNumber == chapterNumber, obj.location == location { return }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                obj.novelID = novelID
                obj.chapterNumber = chapterNumber
                obj.location = location
                realm.add(obj, update: .modified)
            }
            return
        }
        RealmUtil.WriteWith(realm: realm) { (realm) in
            let obj = RealmBookmark()
            obj.id = CreateUniqueID(type: type, hint: hint)
            obj.novelID = novelID
            obj.chapterNumber = chapterNumber
            obj.location = location
            realm.add(obj, update: .modified)
        }
    }
    
    static func SetSpeechBookmarkWith(realm: Realm, novelID: String, chapterNumber:Int, location: Int) {
        SetBookmarkWith(realm: realm, type: .novelSpeechLocation, hint: novelID, novelID: novelID, chapterNumber: chapterNumber, location: location)
    }
    
    static func GetSpeechBookmark(realm: Realm, novelID: String) -> RealmBookmark? {
        return SearchObjectFromWith(realm: realm, type: .novelSpeechLocation, hint: novelID)
    }

    static func SearchObjectFromWith(realm: Realm, type:BookmarkType, hint:String) -> RealmBookmark? {
        return realm.object(ofType: RealmBookmark.self, forPrimaryKey: CreateUniqueID(type: type, hint: hint))
    }
    
    static func GetAllObjectsWith(realm: Realm) -> Results<RealmBookmark>? {
        return realm.objects(RealmBookmark.self).filter("isDeleted = false")
    }
    
    func delete(realm:Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }

    override static func indexedProperties() -> [String] {
        return ["id", "storyID"]
    }
}
extension RealmBookmark: CKRecordConvertible {
}
extension RealmBookmark: CKRecordRecoverable {
}
extension RealmBookmark: CanWriteIsDeleted {
}

