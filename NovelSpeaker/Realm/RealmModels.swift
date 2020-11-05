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
//import MessagePacker

@objc class RealmUtil : NSObject {
    static let currentSchemaVersion : UInt64 = 3
    static let deleteRealmIfMigrationNeeded: Bool = false
    static let CKContainerIdentifier = "iCloud.com.limuraproducts.novelspeaker"

    static var syncEngine: SyncEngine? = nil
    static let lock = NSLock()
    static var realmLocalCache:[String:Realm] = [:]
    static var realmCloudCache:[String:Realm] = [:]
    
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
    static func MigrateFunc(migration:Migration, oldSchemaVersion:UInt64) {
        if oldSchemaVersion == 0 {
            Migrate_0_To_1(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
        if oldSchemaVersion == 1 {
            Migrate_1_To_2(migration: migration, oldSchemaVersion: oldSchemaVersion)
        }
    }
    static func MigrateFuncForRealmStory(migration:Migration, oldSchemaVersion:UInt64) {
        
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
        lock.lock()
        defer {
            lock.unlock()
        }
        realmLocalCache.removeAll()
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
        let threadID = "\(Thread.current)"
        if let realm = realmLocalCache[threadID] {
            return realm
        }
        let config = GetLocalRealmConfiguration()
        let realm = try Realm(configuration: config, queue: queue)
        //realmLocalCache[threadID] = realm
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
        lock.lock()
        defer {
            lock.unlock()
        }
        realmCloudCache.removeAll()
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
    static func ClearCloudRealmCache() {
        // 注意：
        // Cloud側(というかIceCream側)では
        // SyncEngine にも Realm object を渡しているため、
        // 自分で持っている Realm object の cache を消してもあまり良い事は無いかもしれない。
        lock.lock()
        defer {
            lock.unlock()
        }
        // cache を削除する (これをやると別threadからの呼び出しになっちゃうのでできません)
        /*
        for r in realmCloudCache.values {
            r.invalidate()
        }
        */
        realmCloudCache.removeAll()
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
        let threadID = "\(Thread.current)"
        if let realm = realmCloudCache[threadID] {
            return realm
        }
        let realm = try GetCloudRealmWithoutLock(queue: queue)
        //realmCloudCache[threadID] = realm
        return realm
    }
    static func GetContainer() -> CKContainer {
        return CKContainer(identifier: CKContainerIdentifier)
    }
    fileprivate static func CreateSyncEngine() throws -> SyncEngine {
        let container = GetContainer()
        let realmConfiguration = RealmUtil.GetCloudRealmConfiguration()
        return SyncEngine(objects: [
            SyncObject<RealmCloudVersionChecker>(realmConfiguration: realmConfiguration),
            SyncObject<RealmStoryBulk>(realmConfiguration: realmConfiguration),
            SyncObject<RealmNovel>(realmConfiguration: realmConfiguration),
            SyncObject<RealmSpeechModSetting>(realmConfiguration: realmConfiguration),
            SyncObject<RealmSpeechWaitConfig>(realmConfiguration: realmConfiguration),
            SyncObject<RealmSpeakerSetting>(realmConfiguration: realmConfiguration),
            SyncObject<RealmSpeechSectionConfig>(realmConfiguration: realmConfiguration),
            SyncObject<RealmGlobalState>(realmConfiguration: realmConfiguration),
            SyncObject<RealmDisplaySetting>(realmConfiguration: realmConfiguration),
            SyncObject<RealmNovelTag>(realmConfiguration: realmConfiguration),
            SyncObject<RealmSpeechOverrideSetting>(realmConfiguration: realmConfiguration),
            SyncObject<RealmBookmark>(realmConfiguration: realmConfiguration),
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
            RealmSpeechOverrideSetting.self,
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
        FetchCloudData(syncObjectType: RealmSpeechOverrideSetting.self, predicate: NSPredicate(value: true))

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
                            NiftyUtilitySwift.httpGet(url: URL(string: NiftyUtilitySwift.IMPORTANT_INFORMATION_TEXT_URL)!, successAction: { (_, _) in
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
    static func RealmBlockWrite(block: (_ realm:Realm)->Void) {
        RealmBlock { (realm) in
            WriteWith(realm: realm, withoutNotifying: []) { (realm) in
                block(realm)
            }
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
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        url = try values.decode(String.self, forKey: CodingKeys.url)
        subtitle = try values.decode(String.self, forKey: CodingKeys.subtitle)
        content = NovelSpeakerUtility.NormalizeNewlineString(string:(try values.decode(String.self, forKey: CodingKeys.content)))
        novelID = try values.decode(String.self, forKey: CodingKeys.novelID)
        chapterNumber = try values.decode(Int.self, forKey: CodingKeys.chapterNumber)
        downloadDate = try values.decode(Date.self, forKey: CodingKeys.downloadDate)
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
        print("RunChecker in.")
        RealmUtil.RealmBlock { (realm) -> Void in
            let obj:RealmCloudVersionChecker
            if let currentObj = realm.object(ofType: RealmCloudVersionChecker.self, forPrimaryKey: uniqueID) {
                print("RunChecker obj get: \(currentObj.currentSchemaVersion)")
                obj = currentObj
            }else{
                obj = RealmCloudVersionChecker()
                obj.currentSchemaVersion = Int(RealmUtil.currentSchemaVersion)
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    print("RunChecker realm.add. \(obj.currentSchemaVersion)")
                    realm.add(obj, update: .modified)
                }
            }
            if obj.currentSchemaVersion > RealmUtil.currentSchemaVersion {
                checkerHandler?(obj.currentSchemaVersion)
                return
            }
            print("RunChecker observe.")
            checkerObserverToken = obj.observe({ (change) in
                print("RunChecker observe event got.")
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
                print("RunChecker update currentVersion: \(RealmUtil.currentSchemaVersion)")
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
        guard let data = urlString.data(using: .utf8), let zipedData = NiftyUtilitySwift.compress(data: data) else {
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
        guard let zipedData = Data(base64Encoded: uniqueID), let data = NiftyUtilitySwift.decompress(data: zipedData), let uri = String(data: data, encoding: .utf8) else {
            return uniqueID.removingPercentEncoding ?? uniqueID
        }
        return uri
    }
    static func CreateUniqueID(novelID:String, chapterNumber:Int) -> String {
        return "\(chapterNumber):\(URIToUniqueID(urlString: novelID))"
    }
    static func CreateUniqueBulkID(novelID:String, chapterNumber:Int) -> String {
        let chapterNumberBulk = Int((chapterNumber - 1) / bulkCount) * bulkCount
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
        guard let data = NiftyUtilitySwift.decompress(data: zipedData) else {
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
        guard let zipedData = NiftyUtilitySwift.compress(data: data) else {
            print("WARN: [Story] を JSON に変換した後、compress で失敗した")
            return
        }
        self.storyListAsset = CreamAsset.create(object: self, propName: "", data: zipedData)
    }
    
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
                    print("WARN: chapterNumber が期待していない値になっている。(既にある奴の末尾: \(lastChapterNumber), 追加される奴の先頭: \(chapterNumber), bulk.chapterNumber: \(bulk.chapterNumber), currentStoryArray.count: \(currentStoryArray.count)")
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
            guard let data = try? JSONEncoder().encode(storyArray) else {
                print("WARN: [Story] の JSONEncode に失敗(RemoveLastStoryWith)")
                return
            }
            lastStoryBulk.storyListAsset = CreamAsset.create(object: lastStoryBulk, propName: "", data: data)
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

    static func SearchStoryBulkWith(realm:Realm, novelID:String, chapterNumber:Int) -> RealmStoryBulk? {
        //realm.refresh()
        let chapterNumberBulk = Int((chapterNumber - 1) / bulkCount) * bulkCount
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
    }
    
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
    @objc dynamic var likeLevel : Int8 = 0
    @objc dynamic var isNeedSpeechAfterDelete : Bool = false
    @objc dynamic var defaultSpeakerID : String = ""

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
        obj.likeLevel = likeLevel
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
    
    // 1対多や1対1といったリレーションシップがあると、IceCream と相性が悪いというか
    // 一つのobjectの書き換えがリレーションがついたobject全ての書き換えイベントになってしまって
    // 大量の sync request(?) が飛んでしまうということらしいので、
    // とりあえずリレーションについては相手のIDを保存するという弱い結合形式で行きます。
    // 何故そうなるのかは詳しくはこの issue を参照。
    // https://github.com/caiyue1993/IceCream/issues/88
    // ということで、以下のような link されているものを検索するようなクエリは遅くなるかもしれん。というか多分遅い。
    func linkedStorysWith(realm:Realm) -> Array<Story>? {
        return RealmStoryBulk.SearchAllStoryFor(realm: realm, novelID: self.novelID)
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
    func linkedRealmSpeechOverrideSettingsWith(realm:Realm) -> [RealmSpeechOverrideSetting]? {
        return realm.objects(RealmSpeechOverrideSetting.self).filter({ (speechOverrideSetting) -> Bool in
            return !speechOverrideSetting.isDeleted && speechOverrideSetting.targetNovelIDArray.contains(self.novelID)
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
    var updateFrequency: Double {
        get {
            guard let targetDownloadDate = downloadDateArray.suffix(10).first else {
                return 1.0 / 60.0*60.0*24.0*30.0 // 未ダウンロードのものは30日に1度の頻度とする。
            }
            let count = Double(downloadDateArray.suffix(RealmNovel.updateFrequencyTargetCount).count)
            let diffTimeInSec = Date().timeIntervalSince1970 - targetDownloadDate.timeIntervalSince1970
            // likeLevel がある場合は updateFrequency を1日分早い感じにします。
            return count / (diffTimeInSec / (60.0*60.0*24)) + Double(self.likeLevel) * count
        }
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
            story.content = content
            RealmUtil.WriteWith(realm: realm) { (realm) in
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: 1)
                novel.AppendDownloadDate(realm: realm, date: novel.lastDownloadDate)
                realm.add(novel, update: .modified)
            }
            return novel.novelID
        }
    }
    static func AddNewNovelWithMultiplText(contents:[String], title:String) {
        RealmUtil.Write { (realm) in
            let novel = RealmNovel()
            novel.type = .UserCreated
            novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: contents.count)
            var chapterNumber = 1
            for content in contents {
                if content.count <= 0 { continue }
                var story = Story()
                story.novelID = novel.novelID
                story.chapterNumber = chapterNumber
                story.content = content
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                chapterNumber += 1
                novel.AppendDownloadDate(realm: realm, date: Date())
            }
            realm.add(novel, update: .modified)
        }
    }
    
    static func AddNewNovelWithFirstStoryState(state:StoryState) -> String? {
        return RealmUtil.RealmBlock { (realm) -> String? in
            let novelID = state.url.absoluteString
            guard novelID.count > 0 else { return nil }
            guard let content = state.content, content.count > 0 else { return nil }
            if SearchNovelWith(realm: realm, novelID: novelID) != nil { return nil }
            
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
            story.content = content
            story.novelID = novel.novelID
            story.chapterNumber = 1
            story.url = novelID
            RealmUtil.WriteWith(realm: realm) { (realm) in
                realm.add(novel, update: .modified)
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
            }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                for tagName in state.tagArray {
                    RealmNovelTag.AddTag(realm: realm, name: tagName, novelID: novelID, type: "keyword")
                }
            }
            return novelID
        }
    }
    
    func AppendDownloadDate(realm:Realm, date:Date) {
        downloadDateArray.append(date)
        while downloadDateArray.count > 10 {
            downloadDateArray.remove(at: 0)
        }
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
        if let realmSpeechOverrideSettingArray = linkedRealmSpeechOverrideSettingsWith(realm: realm) {
            for realmSpeechOverrideSetting in realmSpeechOverrideSettingArray {
                realmSpeechOverrideSetting.unref(realm:realm, novelID: self.novelID)
            }
        }
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
        return ["writer", "title", "novelID", "likeLevel", "isDeleted", "lastDownloadDate", "lastReadDate"]
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
    case openWebPage = "openWebPage"
    case reload = "reload"
    case share = "share"
    case search = "search"
    case edit = "edit"
    case backup = "backup"
    case detail = "detail"
}

struct SpeechViewButtonSetting: Codable {
    let type:SpeechViewButtonTypes
    var isOn:Bool
    
    static let defaultSetting:[SpeechViewButtonSetting] = [
        SpeechViewButtonSetting(type: .openWebPage, isOn: true),
        SpeechViewButtonSetting(type: .reload, isOn: true),
        SpeechViewButtonSetting(type: .share, isOn: true),
        SpeechViewButtonSetting(type: .search, isOn: true),
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
    case search = "search"
    case edit = "edit"
    case reload = "reaload"
    case order = "order"
    case downloadStatus = "downloadStatus"
}

struct BookshelfViewButtonSetting: Codable {
    let type:BookshelfViewButtonTypes
    var isOn:Bool
    
    static let defaultSetting:[BookshelfViewButtonSetting] = [
        //BookshelfViewButtonSetting(type: .search, isOn: false),
        BookshelfViewButtonSetting(type: .downloadStatus, isOn: false),
        BookshelfViewButtonSetting(type: .order, isOn: true),
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
    @objc dynamic var m_bookSelfSortType : Int = Int(NarouContentSortType.ncode.rawValue)
    @objc dynamic var IsDisallowsCellularAccess = false
    @objc dynamic var IsNeedConfirmDeleteBook = false
    @objc dynamic var fgColor = Data()
    @objc dynamic var bgColor = Data()
    @objc dynamic var defaultDisplaySettingID = ""
    @objc dynamic var defaultSpeakerID = ""
    @objc dynamic var defaultSpeechOverrideSettingID = ""
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
            return NarouContentSortType(rawValue: UInt(m_bookSelfSortType)) ?? NarouContentSortType.ncode
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
    func defaultDisplaySettingWith(realm:Realm) -> RealmDisplaySetting? {
        return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false AND name = %@", self.defaultDisplaySettingID).first
    }
    func defaultSpeakerWith(realm: Realm) -> RealmSpeakerSetting? {
        return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.defaultSpeakerID).first
    }
    func defaultSpeechOverrideSettingWith(realm: Realm) -> RealmSpeechOverrideSetting? {
        realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false AND name = %@", self.defaultSpeechOverrideSettingID).first
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
        let filterdCookieArray = NiftyUtilitySwift.RemoveExpiredCookie(cookieArray: NiftyUtilitySwift.MergeCookieArray(currentCookieArray: currentCookieArray, newCookieArray: cookieArray))
        let codableArray = CodableHTTPCookie.ConvertArrayToCodable(cookieArray: filterdCookieArray)
        guard let cookieData = try? JSONEncoder().encode(codableArray) else { return false }
        self.cookieArrayData = cookieData
        return true
    }
    
    func GetCookieArray() -> [HTTPCookie]? {
        guard let codableArray = try? JSONDecoder().decode([CodableHTTPCookie].self, from: self.cookieArrayData) else { return nil }
        return NiftyUtilitySwift.RemoveExpiredCookie(cookieArray: CodableHTTPCookie.ConvertArrayFromCodable(cookieArray: codableArray).0)
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
    @objc dynamic var fontID = ""
    @objc dynamic var isVertical: Bool = false
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
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
        static let Bookshelf = "bookshelf"
    }
    
    func targetNovelArrayWith(realm:Realm) -> [RealmNovel]? {
        return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
            return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
        })
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

@objc final class RealmSpeechOverrideSetting: Object {
    @objc dynamic var name = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var createdDate = Date()
    @objc dynamic var m_repeatSpeechType : Int = Int(RepeatSpeechType.noRepeat.rawValue)
    @objc dynamic var isOverrideRubyIsEnabled = false
    @objc dynamic var notRubyCharactorStringArray = "・、 　?？!！"
    @objc dynamic var isIgnoreURIStringSpeechEnabled = false

    let targetNovelIDArray = List<String>()
    
    var repeatSpeechType : RepeatSpeechType {
        get {
            return RepeatSpeechType(rawValue: UInt(m_repeatSpeechType)) ?? RepeatSpeechType.noRepeat
        }
        set {
            m_repeatSpeechType = Int(newValue.rawValue)
        }
    }
    
    func targetNovelArrayWith(realm: Realm) -> [RealmNovel]? {
        return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
            return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
        })
    }
    
    static func GetAllObjectsWith(realm:Realm) -> Results<RealmSpeechOverrideSetting>? {
        return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false")
    }
    static func SearchObjectFromWith(realm: Realm, novelID:String) -> LazyFilterSequence<Results<RealmSpeechOverrideSetting>>? {
        return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false").filter({ (setting) -> Bool in
            return setting.targetNovelIDArray.contains(novelID)
        })
    }
    static func SearchObjectFromWith(realm: Realm, name:String) -> RealmSpeechOverrideSetting? {
        guard let obj = realm.object(ofType: RealmSpeechOverrideSetting.self, forPrimaryKey: name) else { return nil }
        if obj.isDeleted { return nil }
        return obj
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
        return "name"
    }

    override static func indexedProperties() -> [String] {
        return ["name", "targetNovelArray", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechOverrideSetting: CKRecordConvertible {
}
extension RealmSpeechOverrideSetting: CKRecordRecoverable {
}
extension RealmSpeechOverrideSetting: CanWriteIsDeleted {
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
        RealmUtil.WriteWith(realm: realm) { (realm) in
            if let obj = SearchObjectFromWith(realm: realm, type: type, hint: hint) {
                obj.novelID = novelID
                obj.chapterNumber = chapterNumber
                obj.location = location
                realm.add(obj, update: .modified)
                return
            }
            let obj = RealmBookmark()
            obj.id = CreateUniqueID(type: type, hint: hint)
            obj.novelID = novelID
            obj.chapterNumber = chapterNumber
            obj.location = location
            realm.add(obj, update: .modified)
        }
    }
    
    static func SetSpeechBookmarkWith(realm: Realm, novelID: String, chapterNumber:Int, location: Int) {
        RealmUtil.WriteWith(realm: realm) { (realm) in
            let obj:RealmBookmark
            if let oldObj = SearchObjectFromWith(realm: realm, type: .novelSpeechLocation, hint: novelID) {
                obj = oldObj
                if obj.location == location && obj.novelID == novelID && obj.chapterNumber == chapterNumber {
                    return
                }
            }else{
                obj = RealmBookmark()
                obj.id = CreateUniqueID(type: .novelSpeechLocation, hint: novelID)
            }
            obj.novelID = novelID
            obj.chapterNumber = chapterNumber
            obj.location = location
            realm.add(obj, update: .modified)
        }
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

