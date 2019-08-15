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

@objc class RealmUtil : NSObject {
    static let currentSchemaVersion : UInt64 = 4
    static let currentSchemaVersionForRealmStory : UInt64 = 4
    static let deleteRealmIfMigrationNeeded: Bool = false
    //static let CKContainerIdentifier = "iCloud.com.limuraproducts.novelspeaker"
    static let CKContainerIdentifier = "iCloud.com.limuraproducts.RealmIceCreamTest"

    static var syncEngine: SyncEngine? = nil
    static var realmStorySyncEngine: SyncEngine? = nil
    static let lock = NSLock()
    static var realmLocalCache:[String:Realm] = [:]
    static var realmCloudCache:[String:Realm] = [:]
    static let lockRealmStory = NSLock()
    static var realmRealmStoryCache:[String:Realm] = [:]
    
    static var writeCount = 0
    static let writeCountPullInterval = 1000 // realm.write を何回したら pull するか
    public static let isUseCloudRealmForStory = true

    static func Migrate_0_To_1(migration:Migration, oldSchemaVersion:UInt64) {
        
    }
    static func MigrateFunc(migration:Migration, oldSchemaVersion:UInt64) {
        if oldSchemaVersion < 1 {
            Migrate_0_To_1(migration: migration, oldSchemaVersion: oldSchemaVersion)
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
    static func GetRealmStoryLocalRealmFilePath() -> URL? {
        if isUseCloudRealmForStory {
            return GetLocalRealmFilePath()
        }
        
        let fileManager = FileManager.default
        do {
            let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return directory.appendingPathComponent("localStory.realm")
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
    @objc static func RemoveRealmStoryLocalRealmFile() {
        if let path = GetRealmStoryLocalRealmFilePath() {
            let fileManager = FileManager.default
            do {
                try fileManager.removeItem(at: path)
            }catch{
                print("file \(path.absoluteString) remove failed.")
            }
        }
        lockRealmStory.lock()
        defer {
            lockRealmStory.unlock()
        }
        realmRealmStoryCache.removeAll()
    }
    static func GetLocalRealm() throws -> Realm {
        lock.lock()
        defer {
            lock.unlock()
        }
        let threadID = "\(Thread.current)"
        if let realm = realmLocalCache[threadID] {
            return realm
        }
        let config = Realm.Configuration(
            fileURL: GetLocalRealmFilePath(),
            schemaVersion: currentSchemaVersion,
            migrationBlock: MigrateFunc,
            deleteRealmIfMigrationNeeded: deleteRealmIfMigrationNeeded,
            shouldCompactOnLaunch: { (totalBytes, usedBytes) in
                return totalBytes * 2 < usedBytes
        })
        let realm = try Realm(configuration: config)
        //realmLocalCache[threadID] = realm
        return realm
    }
    static func GetRealmStoryLocalRealm() throws -> Realm {
        if isUseCloudRealmForStory {
            return try GetLocalRealm()
        }
        
        lockRealmStory.lock()
        defer { lockRealmStory.unlock() }
        let threadID = "\(Thread.current)"
        if let realm = realmRealmStoryCache[threadID] {
            return realm
        }
        let config = Realm.Configuration(
            fileURL: GetRealmStoryLocalRealmFilePath(),
            schemaVersion: currentSchemaVersionForRealmStory,
            migrationBlock: MigrateFuncForRealmStory,
            deleteRealmIfMigrationNeeded: deleteRealmIfMigrationNeeded,
            shouldCompactOnLaunch: { (totalBytes:Int, usedBytes:Int) in
                return Double(totalBytes) * 1.3 < Double(usedBytes)
        })
        do {
            let realm = try Realm(configuration: config)
            //realmLocalOnlyCache[threadID] = realm
            return realm
        }catch let error {
            print("GetLocalOnlyRealm try Realm() failed. \(error.localizedDescription)")
            throw error
        }
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
    static func GetRealmStoryCloudRealmFilePath() -> URL? {
        if isUseCloudRealmForStory {
            return GetCloudRealmFilePath()
        }
        
        let fileManager = FileManager.default
        do {
            let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return directory.appendingPathComponent("cloudStory.realm")
        }catch{
            return nil
        }

    }
    static func RemoveCloudRealmFile() {
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
                /*
                for obj in realm.objects(RealmStory.self) {
                    obj.isDeleted = true
                }
                */
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
                for obj in realm.objects(RealmSpeechQueue.self) {
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
    fileprivate static func GetCloudRealmWithoutLock() throws -> Realm {
        let config = Realm.Configuration(
            fileURL: GetCloudRealmFilePath(),
            schemaVersion: currentSchemaVersion,
            migrationBlock: MigrateFunc,
            deleteRealmIfMigrationNeeded: deleteRealmIfMigrationNeeded,
            shouldCompactOnLaunch: { (totalBytes, usedBytes) in
                return totalBytes * 2 < usedBytes
        })
        let realm = try Realm(configuration: config)
        realm.autorefresh = true
        return realm
    }
    fileprivate static func GetRealmStoryCloudRealmWithoutLock() throws -> Realm {
        if isUseCloudRealmForStory {
            return try GetCloudRealmWithoutLock()
        }
        
        let config = Realm.Configuration(
            fileURL: GetRealmStoryCloudRealmFilePath(),
            schemaVersion: currentSchemaVersionForRealmStory,
            migrationBlock: MigrateFuncForRealmStory,
            deleteRealmIfMigrationNeeded: deleteRealmIfMigrationNeeded,
            shouldCompactOnLaunch: { (totalBytes, usedBytes) in
                return Double(totalBytes) * 1.2 < Double(usedBytes)
        })
        let realm = try Realm(configuration: config)
        realm.autorefresh = true
        return realm
    }
    
    static func GetCloudRealm() throws -> Realm {
        lock.lock()
        defer {
            lock.unlock()
        }
        let threadID = "\(Thread.current)"
        if let realm = realmCloudCache[threadID] {
            return realm
        }
        let realm = try GetCloudRealmWithoutLock()
        //realmCloudCache[threadID] = realm
        return realm
    }
    static func GetRealmStoryCloudRealm() throws -> Realm {
        if isUseCloudRealmForStory {
            return try GetCloudRealm()
        }
        
        lockRealmStory.lock()
        defer {
            lockRealmStory.unlock()
        }
        let threadID = "\(Thread.current)"
        if let realm = realmRealmStoryCache[threadID] {
            return realm
        }
        let realm = try GetRealmStoryCloudRealmWithoutLock()
        //realmCloudCache[threadID] = realm
        return realm
    }
    static func GetContainer() -> CKContainer {
        return CKContainer(identifier: CKContainerIdentifier)
    }
    fileprivate static func CreateSyncEngine() throws -> SyncEngine {
        let container = GetContainer()
        let realm = try RealmUtil.GetCloudRealmWithoutLock()
        return SyncEngine(objects: [
            SyncObject<RealmStory>(realm: realm),
            SyncObject<RealmNovel>(realm: realm),
            SyncObject<RealmSpeechModSetting>(realm: realm),
            SyncObject<RealmSpeechWaitConfig>(realm: realm),
            SyncObject<RealmSpeakerSetting>(realm: realm),
            SyncObject<RealmSpeechSectionConfig>(realm: realm),
            SyncObject<RealmSpeechQueue>(realm: realm),
            SyncObject<RealmGlobalState>(realm: realm),
            SyncObject<RealmDisplaySetting>(realm: realm),
            SyncObject<RealmNovelTag>(realm: realm),
            SyncObject<RealmSpeechOverrideSetting>(realm: realm)
            ], databaseScope: .private, container: container)
    }
    fileprivate static func CreateRealmStorySyncEngine() throws -> SyncEngine {
        let container = GetContainer()
        let realm = try RealmUtil.GetRealmStoryCloudRealmWithoutLock()
        return SyncEngine(objects: [
            SyncObject<RealmStory>(realm: realm)
            ], databaseScope: .private, container: container)
    }

    static func EnableSyncEngine() throws {
        lock.lock()
        defer { lock.unlock() }
        if syncEngine != nil { return }
        self.syncEngine = try CreateSyncEngine()
    }
    static func EnableRealmStorySyncEngine() throws {
        if isUseCloudRealmForStory {
            return try EnableSyncEngine()
        }
        
        lockRealmStory.lock()
        defer { lockRealmStory.unlock() }
        if realmStorySyncEngine != nil { return }
        self.realmStorySyncEngine = try CreateRealmStorySyncEngine()
    }
    
    static func stopSyncEngine() {
        syncEngine = nil
        realmStorySyncEngine = nil
    }
    static func FetchAllLongLivedOperationIDs(completionHandler: @escaping ([CKOperation.ID]?, Error?) -> Void) {
        let container = GetContainer()
        container.fetchAllLongLivedOperationIDs(completionHandler: completionHandler)
    }
    static func GetCloudAccountStatus(completionHandler: @escaping (CKAccountStatus, Error?) -> Void) {
        let container = GetContainer()
        container.accountStatus(completionHandler: completionHandler)
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
            RealmStory.self,
            RealmNovel.self,
            RealmSpeechWaitConfig.self,
            RealmSpeakerSetting.self,
            RealmSpeechSectionConfig.self,
            RealmSpeechQueue.self,
            RealmGlobalState.self,
            RealmDisplaySetting.self,
            RealmNovelTag.self,
            RealmSpeechOverrideSetting.self
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
    static func CheckCloudDataIsValid(minimumTimeoutLimit: TimeInterval = 15.0, timeoutLimit: TimeInterval = 60.0 * 60.0, completion: ((Bool) -> Void)?) {

        // カンジ悪く必要そうなものを別途 fetch してしまいます(というか、RealmNovel や RealmStory は数が多すぎるので fetch したくないんですけど、syncEngine を起動した時に fetch が走ってしまいます)
        FetchCloudData(syncObjectType: RealmGlobalState.self, predicate: NSPredicate(format: "id = %@", RealmGlobalState.UniqueID))
        FetchCloudData(syncObjectType: RealmSpeakerSetting.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechSectionConfig.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechWaitConfig.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechModSetting.self, predicate: NSPredicate(value: true))
        FetchCloudData(syncObjectType: RealmSpeechOverrideSetting.self, predicate: NSPredicate(value: true))

        autoreleasepool {
            guard let realm = try? GetCloudRealm() else {
                completion?(false)
                return
            }
            realm.refresh()
            let startCount = CountAllCloudRealmRecords(realm: realm)
            let minimumTimelimitDate = Date(timeIntervalSinceNow: minimumTimeoutLimit)
            let timelimitDate = Date(timeIntervalSinceNow: timeoutLimit)
            if startCount > 0 && NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm) {
                completion?(true)
                return
            }

            syncEngine?.pull()
            func watcher(completion: ((Bool) -> Void)?, startCount:Int, minimumTimelimitDate:Date, timelimitDate:Date) {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                    autoreleasepool {
                        guard let realm = try? GetCloudRealm() else {
                            completion?(false)
                            return
                        }
                        realm.refresh()
                        let currentCount = CountAllCloudRealmRecords(realm: realm)
                        if currentCount > startCount && NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm) {
                            completion?(true)
                            FetchCloudData(syncObjectType: RealmStory.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmNovel.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmSpeechQueue.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmDisplaySetting.self, predicate: NSPredicate(value: true))
                            FetchCloudData(syncObjectType: RealmNovelTag.self, predicate: NSPredicate(value: true))

                            return
                        }
                        if Date() > timelimitDate {
                            completion?(false)
                            return
                        }
                        if startCount <= 0 && currentCount <= 0 && Date() > minimumTimelimitDate {
                            // minimumTimeoutLimit秒経っても count が 0 から何も増えてないということは多分何も入っていない
                            completion?(false)
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
    static let UseRealmStoryCloudRealmKey = "RealmUtil_RealmStoryUseCloudRealm"
    static func IsUseRealmStoryCloudRealm() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [UseRealmStoryCloudRealmKey: false])
        return defaults.bool(forKey: UseRealmStoryCloudRealmKey)
    }
    static func SetIsUseRealmStoryCloudRealm(isUse:Bool) {
        let defaults = UserDefaults.standard
        defaults.set(isUse, forKey: UseRealmStoryCloudRealmKey)
        //NovelSpeakerNotificationTool.AnnounceRealmSettingChanged()
    }
    static func GetRealm() throws -> Realm {
        if IsUseCloudRealm() {
            if syncEngine == nil {
                try EnableSyncEngine()
            }
            return try GetCloudRealm()
        }
        return try GetLocalRealm()
    }
    static func GetRealmStoryRealm() throws -> Realm {
        if isUseCloudRealmForStory {
            return try GetRealm()
        }
        
        if IsUseRealmStoryCloudRealm() {
            if realmStorySyncEngine == nil {
                try EnableRealmStorySyncEngine()
            }
            return try GetRealmStoryCloudRealm()
        }
        return try GetRealmStoryLocalRealm()
    }
    @objc static func IsValidRealmData() -> Bool {
        return RealmGlobalState.GetInstance() != nil
    }
    @discardableResult
    static func refresh() -> Bool {
        return autoreleasepool {
            guard let realm = try? GetRealm() else {
                return false
            }
            return realm.refresh()
        }
    }

    // TODO: 書き込み失敗を無視している
    static func WriteWith(realm:Realm, withoutNotifying:[NotificationToken?], block:((_ realm:Realm)->Void)) {
        realm.refresh()
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
        autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else {
                print("realm get failed.")
                return
            }
            WriteWith(realm: realm, withoutNotifying: [], block: block)
        }
    }

    static func Write(withoutNotifying:[NotificationToken?], block:((_ realm:Realm)->Void)) {
        autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else {
                print("realm get failed.")
                return
            }
            WriteWith(realm: realm, withoutNotifying: withoutNotifying, block: block)
        }
    }

    static func RealmStoryWrite(block:((_ realm:Realm)->Void)) {
        autoreleasepool {
            guard let realm = try? RealmUtil.GetRealmStoryRealm() else {
                print("realm get failed.")
                return
            }
            WriteWith(realm: realm, withoutNotifying: [], block: block)
        }
    }
    
    static func RealmStoryWrite(withoutNotifying:[NotificationToken?], block:((_ realm:Realm)->Void)) {
        autoreleasepool {
            guard let realm = try? RealmUtil.GetRealmStoryRealm() else {
                print("realm get failed.")
                return
            }
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

protocol CanWriteIsDeleted {
    var isDeleted: Bool { get set }
}

// MARK: Model
@objc final class RealmStory : Object {
    @objc dynamic var id = "" // primary key は RealmStory.CreateUniqueID() で生成したものを使います。
    @objc dynamic var novelID = ""
    @objc dynamic var chapterNumber = 0
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var contentZiped = Data()
    @objc dynamic var readLocation = 0
    @objc dynamic var url = ""
    //@objc dynamic var lastReadDate = Date(timeIntervalSince1970: 0)
    //@objc dynamic var downloadDate = Date()
    @objc dynamic var subtitle = ""

    var linkedQueues : [RealmSpeechQueue]? {
        get {
            return autoreleasepool {
                //guard let realm = try? RealmUtil.GetRealm() else { return nil }
                guard let realm = try? RealmUtil.GetRealmStoryRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeechQueue.self).filter({ (speechQueue) -> Bool in
                    return !speechQueue.isDeleted && speechQueue.targetStoryIDArray.contains(self.id)
                })
            }
        }
    }
    var owner : RealmNovel? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                guard let obj = realm.object(ofType: RealmNovel.self, forPrimaryKey: self.novelID) else { return nil }
                if obj.isDeleted { return nil }
                return obj
            }
        }
    }
    var content : String? {
        get {
            return NiftyUtility.stringInflate(self.contentZiped)
        }
        set (value) {
            self.contentZiped = NiftyUtility.stringDeflate(value, level: 9)
        }
    }
    static func CreateUniqueID(novelID:String, chapterNumber:Int) -> String {
        return "\(chapterNumber):\(novelID)"
    }
    static func StoryIDToNovelID(storyID:String) -> String {
        if let colonIndex = storyID.firstIndex(of: ":") {
            let index = storyID.index(colonIndex, offsetBy: 1)
            return String(storyID[index...])
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
    static func SearchStory(novelID:String, chapterNumber:Int) -> RealmStory? {
        return autoreleasepool {
            //guard let realm = try? RealmUtil.GetRealm() else { return nil }
            guard let realm = try? RealmUtil.GetRealmStoryRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmStory.self, forPrimaryKey: CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber)), result.isDeleted == false {
                return result
            }
            return nil
        }
    }

    static func GetAllObjects() -> Results<RealmStory>? {
        return autoreleasepool {
            //guard let realm = try? RealmUtil.GetRealm() else { return nil }
            guard let realm = try? RealmUtil.GetRealmStoryRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmStory.self).filter("isDeleted = false")
        }
    }
    static func CreateNewStory(novelID:String, chapterNumber:Int) -> RealmStory {
        let story = RealmStory()
        story.id = CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber)
        story.chapterNumber = chapterNumber
        story.novelID = novelID
        return story
    }

    static func SearchStoryFrom(storyID:String) -> RealmStory? {
        return autoreleasepool {
            //guard let realm = try? RealmUtil.GetRealm() else { return nil }
            guard let realm = try? RealmUtil.GetRealmStoryRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmStory.self, forPrimaryKey: storyID), result.isDeleted == false {
                return result
            }
            return nil
        }
    }
    static func SearchStoryFrom(novelID:String) -> Results<RealmStory>? {
        return autoreleasepool {
            //guard let realm = try? RealmUtil.GetRealm() else { return nil }
            guard let realm = try? RealmUtil.GetRealmStoryRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmStory.self).filter("isDeleted = false AND novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true)
        }
    }
    
    func GetSubtitle() -> String {
        if subtitle.count > 0 {
            return subtitle
        }
        guard let text = content else { return "-" }
        for line in text.components(separatedBy: .newlines) {
            let trimedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimedLine.count > 0 {
                return trimedLine
            }
        }
        return "-"
    }
    
    func delete(realm:Realm) {
        if let queueArray = linkedQueues {
            for queue in queueArray {
                queue.unref(realm:realm, storyID: self.id)
            }
        }
        RealmUtil.Delete(realm: realm, model: self)
        /*
        RealmUtil.RealmStoryWrite { (realm) in
            RealmUtil.LocalOnlyDelete(realm: realm, model: self)
        }
         */
    }

    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        //return ["novelID", "chapterNumber", "isDeleted"]
        return ["novelID"]
    }
}
extension RealmStory: CKRecordConvertible {
}
extension RealmStory: CKRecordRecoverable {
}
extension RealmStory: CanWriteIsDeleted {
}

@objc enum NovelType: Int {
    case URL = 1
    case UserCreated = 2
}

@objc final class RealmNovel : Object {
    @objc dynamic var novelID : String = RealmNovel.CreateUniqueID() // novelID は primary key です。
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var m_type : Int = NovelType.URL.rawValue
    @objc dynamic var writer : String = ""
    @objc dynamic var title : String = ""
    @objc dynamic var url : String = ""
    @objc dynamic var m_urlSecret : String = ""
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

    var type : NovelType {
        get {
            return NovelType(rawValue: self.m_type) ?? NovelType.UserCreated
        }
        set {
            self.m_type = newValue.rawValue
        }
    }
    
    // 1対多や1対1といったリレーションシップがあると、IceCream と相性が悪いというか
    // 一つのobjectの書き換えがリレーションがついたobject全ての書き換えイベントになってしまって
    // 大量の sync request(?) が飛んでしまうということらしいので、
    // とりあえずリレーションについては相手のIDを保存するという弱い結合形式で行きます。
    // 何故そうなるのかは詳しくはこの issue を参照。
    // https://github.com/caiyue1993/IceCream/issues/88
    // ということで、以下のような link されているものを検索するようなクエリは遅くなるかもしれん。というか多分遅い。
    var linkedStorys: Results<RealmStory>? {
        get {
            return RealmStory.SearchStoryFrom(novelID: self.novelID)
        }
    }
    var linkedSpeechModSettings : [RealmSpeechModSetting]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeechModSetting.self).filter({ (speechModSetting) -> Bool in
                    return !speechModSetting.isDeleted && speechModSetting.targetNovelIDArray.contains(self.novelID)
                })
            }
        }
    }
    var linkedSpeechSectionConfigs : [RealmSpeechSectionConfig]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeechSectionConfig.self).filter({ (speechSectionConfig) -> Bool in
                    return !speechSectionConfig.isDeleted && speechSectionConfig.targetNovelIDArray.contains(self.novelID)
                })
            }
        }
    }
    var linkedDisplaySettings : [RealmDisplaySetting]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmDisplaySetting.self).filter({ (displaySetting) -> Bool in
                    return !displaySetting.isDeleted && displaySetting.targetNovelIDArray.contains(self.novelID)
                })
            }
        }
    }
    
    var linkedTags : [RealmNovelTag]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmNovelTag.self).filter({ (novelTag) -> Bool in
                    return !novelTag.isDeleted && novelTag.targetNovelIDArray.contains(self.novelID)
                })
            }
        }
    }
    
    var linkedRealmSpeechOverrideSettings : [RealmSpeechOverrideSetting]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeechOverrideSetting.self).filter({ (speechOverrideSetting) -> Bool in
                    return !speechOverrideSetting.isDeleted && speechOverrideSetting.targetNovelIDArray.contains(self.novelID)
                })
            }
        }
    }
    
    var lastChapter : RealmStory? {
        get {
            return RealmStory.SearchStoryFrom(storyID: m_lastChapterStoryID)
        }
    }
    var lastChapterNumber : Int? {
        get {
            let chapterNumber = RealmStory.StoryIDToChapterNumber(storyID: m_lastChapterStoryID)
            if chapterNumber <= 0 {
                return nil
            }
            return chapterNumber
        }
    }
    var lastDownloadURL : String? {
        get {
            return lastChapter?.url
        }
    }
    var readingChapter: RealmStory? {
        get {
            return RealmStory.SearchStoryFrom(storyID: m_readingChapterStoryID)
        }
    }
    var isNewFlug: Bool {
        return lastDownloadDate > lastReadDate
    }
    
    var urlSecret: [String] {
        get {
            return m_urlSecret.components(separatedBy: ";")
        }
    }
    
    var defaultSpeaker : RealmSpeakerSetting? {
        get {
            if self.defaultSpeakerID.count <= 0 {
                return RealmGlobalState.GetInstance()?.defaultSpeaker
            }
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                guard let obj = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: self.defaultSpeakerID) else { return nil }
                if obj.isDeleted { return nil }
                return obj
            }
        }
    }
    
    // 推測によるアップデート頻度。単位は1日に何度更新されるのか(1日に1度なら1、10日に1度なら0.1、1日に3度なら3)。
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
        return "https://example.com/\(NSUUID().uuidString)"
    }
    
    static func GetAllObjects() -> Results<RealmNovel>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter("isDeleted = false")
        }
    }

    static func SearchNovelFrom(novelID:String) -> RealmNovel? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmNovel.self, forPrimaryKey: novelID), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    static func AddNewNovelOnlyText(content:String, title:String) {
        autoreleasepool {
            let novel = RealmNovel()
            novel.type = .UserCreated
            novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            novel.lastReadDate = Date(timeIntervalSince1970: 1)
            novel.lastDownloadDate = Date()
            let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: 1)
            story.content = content
            RealmUtil.RealmStoryWrite { (realm) in
                realm.add(story, update: .modified)
            }
            novel.m_lastChapterStoryID = story.id
            RealmUtil.Write { (realm) in
                novel.AppendDownloadDate(date: novel.lastDownloadDate, realm: realm)
                realm.add(novel, update: .modified)
            }
        }
    }
    static func AddNewNovelWithMultiplText(contents:[String], title:String) {
        autoreleasepool {
            RealmUtil.Write { (realm) in
                let novel = RealmNovel()
                novel.type = .UserCreated
                novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                novel.m_lastChapterStoryID = RealmStory.CreateUniqueID(novelID: novel.novelID, chapterNumber: contents.count)
                var chapterNumber = 1
                for content in contents {
                    if content.count <= 0 { continue }
                    let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: chapterNumber)
                    story.content = content
                    if chapterNumber != 1 {
                        //story.lastReadDate = Date(timeIntervalSinceNow: -60)
                    }
                    RealmUtil.RealmStoryWrite { (realm) in
                        realm.add(story, update: .modified)
                    }
                    chapterNumber += 1
                    novel.AppendDownloadDate(date: Date(), realm: realm)
                }
                realm.add(novel, update: .modified)
            }
        }
    }
    
    static func AddNewNovelWithFirstStory(url:URL, htmlStory:HtmlStory, cookieParameter:String, title:String, author:String?, tagArray:[String], firstContent:String) -> String? {
        return autoreleasepool {
            let novelID = url.absoluteString
            guard novelID.count > 0 else {
                return nil
            }
            if SearchNovelFrom(novelID: url.absoluteString) != nil {
                // already downloaded.
                return nil
            }
            let novel = RealmNovel()
            novel.novelID = novelID
            novel.url = novelID
            novel.m_urlSecret = cookieParameter
            novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let author = author {
                novel.writer = author
            }
            novel.type = .URL
            novel.m_lastChapterStoryID = RealmStory.CreateUniqueID(novelID: novelID, chapterNumber: 1)
            RealmUtil.Write { (realm) in
                realm.add(novel, update: .modified)
            }
            autoreleasepool {
                let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: 1)
                story.content = firstContent
                if let subtitle = htmlStory.subtitle {
                    story.subtitle = subtitle
                }
                if let storyUrl = htmlStory.url {
                    story.url = storyUrl
                }
                RealmUtil.RealmStoryWrite { (realm) in
                    //story.lastReadDate = Date(timeIntervalSince1970: 60)
                    realm.add(story, update: .modified)
                }
            }
            autoreleasepool {
                RealmUtil.Write { (realm) in
                    for tagName in tagArray {
                        RealmNovelTag.AddTag(realm: realm, name: tagName, novelID: novelID, type: "keyword")
                    }
                }
            }
            return novelID
        }
    }
    
    func AppendDownloadDate(date:Date, realm:Realm) {
        downloadDateArray.append(date)
        while downloadDateArray.count > 10 {
            downloadDateArray.remove(at: 0)
        }
    }
    
    func delete(realm:Realm) {
        if let storyArray = linkedStorys {
            for story in storyArray {
                story.delete(realm: realm)
            }
        }
        if let speechModSettingArray = linkedSpeechModSettings {
            for speechModSetting in speechModSettingArray {
                speechModSetting.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let speechSectionConfigArray = linkedSpeechSectionConfigs {
            for speechSectionConfig in speechSectionConfigArray {
                speechSectionConfig.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let displaySettingArray = linkedDisplaySettings {
            for displaySetting in displaySettingArray {
                displaySetting.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let tagArray = linkedTags {
            for tag in tagArray {
                tag.unref(realm:realm, novelID: self.novelID)
            }
        }
        if let realmSpeechOverrideSettingArray = linkedRealmSpeechOverrideSettings {
            for realmSpeechOverrideSetting in realmSpeechOverrideSettingArray {
                realmSpeechOverrideSetting.unref(realm:realm, novelID: self.novelID)
            }
        }
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override class func primaryKey() -> String? {
        return "novelID"
    }
    
    override static func indexedProperties() -> [String] {
        //return ["writer", "title", "novelID", "likeLevel", "isDeleted", "lastDownloadDate", "lastReadDate"]
        return ["writer", "title", "novelID", "lastDownloadDate", "lastReadDate"]
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
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                    return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
                })
            }
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechModSetting>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechModSetting.self).filter("isDeleted = false")
        }
    }
    static func SearchFrom(beforeString:String) -> RealmSpeechModSetting? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmSpeechModSetting.self, forPrimaryKey: beforeString), result.isDeleted == false {
                return result
            }
            return nil
        }
    }
    static func SearchSettingsFor(novelID:String) -> LazyFilterSequence<Results<RealmSpeechModSetting>>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechModSetting.self).filter("isDeleted = false").filter({ (setting) -> Bool in
                return setting.targetNovelIDArray.contains(anyTarget) || setting.targetNovelIDArray.contains(novelID)
            })
        }
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
        //return ["before", "after", "createdDate", "isDeleted"]
        return ["before", "after", "createdDate"]
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
    
    func ApplyDelaySettingTo(niftySpeaker:NiftySpeaker) {
        realm?.refresh()
        if realm?.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID)?.isSpeechWaitSettingUseExperimentalWait ?? false {
            if delayTimeInSec <= 0.0 {
                return
            }
            var waitString = "。"
            var x : Float = 0.0
            while x < delayTimeInSec {
                x += 0.1
                waitString += "_。"
            }
            if targetText.contains("\n") {
                niftySpeaker.addSpeechModText(targetText.replacingOccurrences(of: "\n", with: "\r"), to: waitString)
                niftySpeaker.addSpeechModText(targetText.replacingOccurrences(of: "\n", with: "\r\n"), to: waitString)
            }
            niftySpeaker.addSpeechModText(targetText, to: waitString)
        }else{
            niftySpeaker.addDelayBlockSeparator(targetText, delay: TimeInterval(delayTimeInSec))
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechWaitConfig>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechWaitConfig.self).filter("isDeleted = false")
        }
    }

    static func SearchFrom(targetText:String) -> RealmSpeechWaitConfig? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmSpeechWaitConfig.self, forPrimaryKey: targetText), result.isDeleted == false {
                return result
            }
            return nil
        }
    }
    
    func delete(realm:Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    override class func primaryKey() -> String? {
        return "targetText"
    }
    
    override static func indexedProperties() -> [String] {
        //return ["targetText", "createdDate", "isDeleted"]
        return ["targetText", "createdDate"]
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
    @objc dynamic var voiceIdentifier : String = "com.apple.ttsbundle.siri_female_ja-JP_premium"
    @objc dynamic var locale : String = "ja-JP"
    @objc dynamic var createdDate = Date()
    
    var speechConfig : SpeechConfig {
        get {
            let speechConfig = SpeechConfig()
            speechConfig.pitch = self.pitch
            speechConfig.rate = self.rate
            speechConfig.beforeDelay = 0
            speechConfig.voiceIdentifier = self.voiceIdentifier
            return speechConfig
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeakerSetting>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false")
        }
    }
    
    static func SearchFrom(name:String) -> RealmSpeakerSetting? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: name), result.isDeleted == false {
                return result
            }
            return nil
        }
    }
    
    func applyTo(speaker:Speaker) {
        speaker.setPitch(pitch)
        speaker.setRate(rate)
        speaker.setVoiceWithIdentifier(voiceIdentifier)
    }
    
    func delete(realm:Realm) {
        if let sectionConfigArray = RealmSpeechSectionConfig.GetAllObjects()?.filter("speakerID = %@", self.name) {
            for sectionConfig in sectionConfigArray {
                sectionConfig.unref(realm: realm, speakerID: self.name)
            }
        }
        if let novelArray = RealmNovel.GetAllObjects()?.filter("defaultSpeakerID = %@", self.name), let defaultSpeakerID = RealmGlobalState.GetInstance()?.defaultSpeaker?.name {
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
        //return ["name", "createdDate", "isDeleted"]
        return ["name", "createdDate"]
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
    
    var speaker : RealmSpeakerSetting? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.speakerID).first
            }
        }
    }
    var targetNovelArray : [RealmNovel]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                    return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
                })
            }
        }
    }
    // 指定された NovelID に対する default設定以外 の section config をリストにして返します。
    // 複雑なクエリになるので何度も呼び出すような使い方はしないほうが良いです。
    static func SearchSettingsFor(novelID:String) -> Dictionary<String, RealmSpeechSectionConfig>.Values? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
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
    }

    static func GetAllObjects() -> Results<RealmSpeechSectionConfig>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechSectionConfig.self).filter("isDeleted = false")
        }
    }

    static func SearchFrom(name:String) -> RealmSpeechSectionConfig? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: name), result.isDeleted == false {
                return result
            }
            return nil
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
    func unref(realm: Realm, speakerID: String) {
        if self.speakerID == speakerID {
            delete(realm: realm)
        }
    }
    func delete(realm: Realm) {
        RealmUtil.Delete(realm: realm, model: self)
    }
    
    func AddTargetNovelID(novelID: String) {
        if novelID.count <= 0 {
            return
        }
        if targetNovelIDArray.contains(novelID) { return }
        RealmUtil.Write { (realm) in
            self.targetNovelIDArray.append(novelID)
        }
    }
    
    override class func primaryKey() -> String? {
        return "name"
    }
    
    override static func indexedProperties() -> [String] {
        //return ["name", "startText", "createdDate", "speakerID", "isDeleted"]
        return ["name", "startText", "createdDate", "speakerID"]
    }
}
extension RealmSpeechSectionConfig: CKRecordConvertible {
}
extension RealmSpeechSectionConfig: CKRecordRecoverable {
}
extension RealmSpeechSectionConfig: CanWriteIsDeleted {
}

@objc final class RealmSpeechQueue: Object {
    @objc dynamic var name = "" // primary key
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var createdDate = Date()
    
    let targetStoryIDArray = List<String>()
    
    var targetStoryArray : [RealmStory]? {
        get {
            return autoreleasepool {
                //guard let realm = try? RealmUtil.GetRealm() else { return nil }
                guard let realm = try? RealmUtil.GetRealmStoryRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmStory.self).filter({ (story) -> Bool in
                    return !story.isDeleted && self.targetStoryIDArray.contains(story.id)
                })
            }
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechQueue>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechQueue.self).filter("isDeleted = false")
        }
    }

    static func SearchFrom(name:String) -> RealmSpeechQueue? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmSpeechQueue.self, forPrimaryKey: name), result.isDeleted == false {
                return result
            }
            return nil
        }
    }

    func unref(realm:Realm, storyID:String) {
        if let index = targetStoryIDArray.index(of: storyID) {
            targetStoryIDArray.remove(at: index)
            if targetStoryIDArray.count <= 0 {
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
        //return ["createdDate", "name", "isDeleted"]
        return ["createdDate", "name"]
    }
}
extension RealmSpeechQueue: CKRecordConvertible {
}
extension RealmSpeechQueue: CKRecordRecoverable {
}
extension RealmSpeechQueue: CanWriteIsDeleted {
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
    @objc dynamic var isDarkThemeEnabled = false
    @objc dynamic var isPlaybackDurationEnabled = false
    @objc dynamic var isShortSkipEnabled = false
    @objc dynamic var isReadingProgressDisplayEnabled = false
    @objc dynamic var isForceSiteInfoReloadIsEnabled = false
    @objc dynamic var isMenuItemIsAddNovelSpeakerItemsOnly = false
    @objc dynamic var isPageTurningSoundEnabled = false
    @objc dynamic var m_bookSelfSortType : Int = Int(NarouContentSortType.ncode.rawValue)
    
    @objc dynamic var defaultDisplaySettingID = ""
    @objc dynamic var defaultSpeakerID = ""
    @objc dynamic var defaultSpeechOverrideSettingID = ""
    @objc dynamic var currentReadingNovelID = ""
    
    var bookShelfSortType : NarouContentSortType {
        get {
            return NarouContentSortType(rawValue: UInt(m_bookSelfSortType)) ?? NarouContentSortType.ncode
        }
        set {
            m_bookSelfSortType = Int(newValue.rawValue)
        }
    }
    
    var defaultDisplaySetting : RealmDisplaySetting? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false AND name = %@", self.defaultDisplaySettingID).first
            }
        }
    }
    var defaultSpeaker : RealmSpeakerSetting? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.defaultSpeakerID).first
            }
        }
    }
    var defaultSpeechOverrideSetting : RealmSpeechOverrideSetting? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false AND name = %@", self.defaultSpeechOverrideSettingID).first
            }
        }
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
    var backgroundColor:UIColor {
        get {
            if isDarkThemeEnabled {
                return UIColor.black
            }
            return UIColor.white
        }
    }
    var tintColor:UIColor {
        get {
            if isDarkThemeEnabled {
                return UIColor.white
            }
            return UIColor.black
        }
    }
    var scrollviewIndicatorStyle:UIScrollView.IndicatorStyle {
        get {
            if isDarkThemeEnabled {
                return .white
            }
            return .black
        }
    }
    var uibarStyle:UIBarStyle{
        get {
            if isDarkThemeEnabled {
                return .black
            }
            return .default
        }
    }
    // TODO: UIAppearance でテーマできちゃうぜやったーと思ったけど全然駄目だったのでとりあえず放置(´・ω・`)
    func ApplyThemaToAppearance() {
        let backgroundColor:UIColor
        if isDarkThemeEnabled{
            backgroundColor = UIColor.black
        }else{
            backgroundColor = UIColor.white
        }
        let tintColor:UIColor
        if isDarkThemeEnabled{
            tintColor = UIColor.white
        }else{
            tintColor = UIColor.black
        }
        let buttonTextColor:UIColor
        if isDarkThemeEnabled{
            buttonTextColor = UIColor.white
        }else{
            buttonTextColor = UIColor.blue
        }
        let barStyle:UIBarStyle
        if isDarkThemeEnabled{
            barStyle = .black
        }else{
            barStyle = .default
        }
        let indicatorStyle:UIScrollView.IndicatorStyle
        if isDarkThemeEnabled{
            indicatorStyle = .white
        }else{
            indicatorStyle = .black
        }
        UIView.appearance().backgroundColor = backgroundColor
        UIView.appearance().tintColor = tintColor
        UITextView.appearance().textColor = tintColor
        UITabBar.appearance().barTintColor = backgroundColor
        UINavigationBar.appearance().barTintColor = backgroundColor
        UIButton.appearance().setTitleColor(buttonTextColor, for: .normal)
        UINavigationBar.appearance().barStyle = barStyle
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: tintColor]
        UIScrollView.appearance().indicatorStyle = indicatorStyle
    }
    static func FallbackApplyAppearance() {
        UIView.appearance().backgroundColor = UIColor.white
        UIView.appearance().tintColor = UIColor.black
        UITextView.appearance().textColor = UIColor.black
        UITabBar.appearance().barTintColor = UIColor.white
        UINavigationBar.appearance().barStyle = UIBarStyle.default
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.black]
        UIScrollView.appearance().indicatorStyle = UIScrollView.IndicatorStyle.black
    }
    static func GetLastReadStory() -> RealmStory? {
        return GetLastReadNovel()?.readingChapter
    }
    static func GetLastReadNovel() -> RealmNovel? {
        guard let globalState = RealmGlobalState.GetInstance() else { return nil }
        return RealmNovel.SearchNovelFrom(novelID: globalState.currentReadingNovelID)
    }

    static public func GetInstance() -> RealmGlobalState? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        guard let obj = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: UniqueID) else { return nil }
        if obj.isDeleted { return nil }
        return obj
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
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                    return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
                })
            }
        }
    }
    
    static func GetAllObjects() -> Results<RealmDisplaySetting>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false")
        }
    }

    static func SearchFrom(name:String) -> RealmDisplaySetting? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            if let result = realm.object(ofType: RealmDisplaySetting.self, forPrimaryKey: name), result.isDeleted == false {
                return result
            }
            return nil
        }
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
        //return ["name", "createdDate", "isDeleted"]
        return ["name", "createdDate"]
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
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                    return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
                })
            }
        }
    }
    
    static func CreateNewTag(name:String, type:String) -> RealmNovelTag {
        let tag = RealmNovelTag()
        tag.id = CreateUniqueID(name: name, type: type)
        tag.name = name
        tag.type = type
        return tag
    }
    
    static func GetAllObjects() -> Results<RealmNovelTag>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovelTag.self).filter("isDeleted = false")
        }
    }
    static func GetObjectsFor(type:String) -> Results<RealmNovelTag>? {
        return GetAllObjects()?.filter("type = %@", type)
    }
    
    static func SearchWith(name:String, type:String) -> RealmNovelTag? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            guard let obj = realm.object(ofType: RealmNovelTag.self, forPrimaryKey: RealmNovelTag.CreateUniqueID(name: name, type: type)) else { return nil }
            if obj.isDeleted { return nil }
            return obj
        }
    }
    static func SearchWith(novelID:String, type:String) -> LazyFilterSequence<Results<RealmNovelTag>>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovelTag.self).filter("isDeleted = false AND type = %@", type).filter({ (tag) -> Bool in
                return tag.targetNovelIDArray.contains(novelID)
            })
        }

    }
    
    // RealmWrite の中で呼んでください
    static func AddTag(realm: Realm, name:String, novelID: String, type: String) {
        let tagName = NovelSpeakerUtility.CleanTagString(tag: name)
        if tagName.count <= 0 || novelID.count <= 0 {
            return
        }
        if let tag = SearchWith(name: tagName, type: type) {
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
        //return ["id", "name", "type", "createdDate", "isDeleted", "hint"]
        return ["id", "name", "type", "createdDate", "hint"]
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
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return autoreleasepool {
                guard let realm = try? RealmUtil.GetRealm() else { return nil }
                realm.refresh()
                return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                    return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
                })
            }
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechOverrideSetting>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false")
        }
    }
    static func SearchObjectFrom(novelID:String) -> LazyFilterSequence<Results<RealmSpeechOverrideSetting>>? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false").filter({ (setting) -> Bool in
                return setting.targetNovelIDArray.contains(novelID)
            })
        }
    }
    static func SearchObjectFrom(name:String) -> RealmSpeechOverrideSetting? {
        return autoreleasepool {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            guard let obj = realm.object(ofType: RealmSpeechOverrideSetting.self, forPrimaryKey: name) else { return nil }
            if obj.isDeleted { return nil }
            return obj
        }
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
        //return ["name", "targetNovelArray", "createdDate", "isDeleted"]
        return ["name", "createdDate"]
    }
}
extension RealmSpeechOverrideSetting: CKRecordConvertible {
}
extension RealmSpeechOverrideSetting: CKRecordRecoverable {
}
extension RealmSpeechOverrideSetting: CanWriteIsDeleted {
}

