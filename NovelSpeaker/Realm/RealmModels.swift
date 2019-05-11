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

class RealmUtil {
    static let currentSchemaVersion : UInt64 = 0
    static let deleteRealmIfMigrationNeeded: Bool = false
    static let CKContainerIdentifier = "iCloud.com.limuraproducts.novelspeaker"
    
    static var syncEngine: SyncEngine? = nil
    static let lock = NSLock()
    static var realmLocalCache:[String:Realm] = [:]
    static var realmCloudCache:[String:Realm] = [:]
    
    static func Migrate_0_To_1(migration:Migration, oldSchemaVersion:UInt64) {
        
    }
    static func MigrateFunc(migration:Migration, oldSchemaVersion:UInt64) {
        if oldSchemaVersion < 1 {
            Migrate_0_To_1(migration: migration, oldSchemaVersion: oldSchemaVersion)
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
    static func RemoveLocalRealmFile() {
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
        realmLocalCache.values.forEach { (realm) in
            realm.invalidate()
        }
        realmLocalCache.removeAll()
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
        realmLocalCache[threadID] = realm
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
        // cache を削除する
        realmCloudCache.values.forEach { (realm) in
            realm.invalidate()
        }
        realmCloudCache.removeAll()
    }
    static func ClearCloudRealmModels() {
        // とりあえず中身を消す
        do {
            let realm = try GetCloudRealm()
            try realm.write {
                for obj in realm.objects(RealmStory.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmNovel.self) {
                    obj.isDeleted = true
                }
                for obj in realm.objects(RealmStory.self) {
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
        // cache を削除する
        for r in realmCloudCache.values {
            r.invalidate()
        }
        realmCloudCache.removeAll()
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
        realmCloudCache[threadID] = realm
        return realm
    }
    static func GetContainer() -> CKContainer {
        return CKContainer(identifier: CKContainerIdentifier)
    }
    static func CreateSyncEngine() throws -> SyncEngine {
        let container = GetContainer()
        let realm = try RealmUtil.GetCloudRealm()
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
            ], container: container, in: realm)
    }
    static func EnableSyncEngine() throws {
        syncEngine = try CreateSyncEngine()
    }
    static func CloudSync() {
        // pull() で iCloud 上の最新データで上書きした後に、pushAll() する。
        // というのは、どうも pushAll() をしないでも local の変更を勝手に push されているようであるというのと、
        // どうやら pushAll() というのは local の変更を push するものではなく
        // 「今現在のデータを全部上書きで登録する」というものらしいので。
        syncEngine?.pull()
        syncEngine?.pushAll()
    }
    static func CloudPull() {
        syncEngine?.pull()
    }
    static func CloudPush() {
        syncEngine?.pushAll()
    }
}

// MARK: Model
@objc final class RealmStory : Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var chapterNumber = 0
    @objc dynamic var contentZiped = Data()
    @objc dynamic var readLocation = 0
    @objc dynamic var url = ""
    @objc dynamic var downloadDate = Date()
    @objc dynamic var lastReadDate = Date()
    @objc dynamic var subtitle = ""

    @objc dynamic var novelID = ""
    let downloadFailedLog = List<Date>()

    var linkedQueues : [RealmSpeechQueue]? {
        get {
            return self.realm?.objects(RealmSpeechQueue.self).filter({ (speechQueue) -> Bool in
                return !speechQueue.isDeleted && speechQueue.targetStoryIDArray.contains(self.id)
            })
        }
    }
    var owner : RealmNovel? {
        get {
            return self.realm?.objects(RealmNovel.self).filter("isDeleted = false AND novelID = %@", self.novelID).first
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["novelID", "chapterNumber", "downloadDate", "lastReadDate", "isDeleted"]
    }
}
extension RealmStory: CKRecordConvertible {
}
extension RealmStory: CKRecordRecoverable {
}

@objc final class RealmNovel : Object {
    @objc dynamic var novelID : String = "" // novelID は primary key です。
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var type : Int32 = 0
    @objc dynamic var writer : String = ""
    @objc dynamic var title : String = ""
    @objc dynamic var url : String = ""
    @objc dynamic var urlSecret : String = ""
    @objc dynamic var createDate : Date = Date()
    @objc dynamic var likeLevel : Int8 = 0
    @objc dynamic var isNeedSpeechAfterDelete : Bool = false
    
    // 1対多や1対1といったリレーションシップがあると、IceCream と相性が悪いというか
    // 一つのobjectの書き換えがリレーションがついたobject全ての書き換えイベントになってしまって
    // 大量の sync request(?) が飛んでしまうということらしいので、
    // とりあえずリレーションについては相手のIDを保存するという弱い結合形式で行きます。
    // 何故そうなるのかは詳しくはこの issue を参照。
    // https://github.com/caiyue1993/IceCream/issues/88
    // ということで、以下のような link されているものを検索するようなクエリは遅くなるかもしれん。というか多分遅い。
    var linkedStorys : Results<RealmStory>? {
        get {
            return self.realm?.objects(RealmStory.self).filter("isDeleted = false AND novelID = %@", self.novelID)
        }
    }
    var linkedSpeechModSettings : [RealmSpeechModSetting]? {
        get {
            return self.realm?.objects(RealmSpeechModSetting.self).filter({ (speechModSetting) -> Bool in
                return !speechModSetting.isDeleted && speechModSetting.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    var linkedSpeechSectionConfigs : [RealmSpeechSectionConfig]? {
        get {
            return self.realm?.objects(RealmSpeechSectionConfig.self).filter({ (speechSectionConfig) -> Bool in
                return !speechSectionConfig.isDeleted && speechSectionConfig.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    var linkedDisplaySettings : [RealmDisplaySetting]? {
        get {
            return self.realm?.objects(RealmDisplaySetting.self).filter({ (displaySetting) -> Bool in
                return !displaySetting.isDeleted && displaySetting.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    
    var linkedTags : [RealmNovelTag]? {
        get {
            return self.realm?.objects(RealmNovelTag.self).filter({ (novelTag) -> Bool in
                return !novelTag.isDeleted && novelTag.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    
    var linkedRealmSpeechOverrideSettings : [RealmSpeechOverrideSetting]? {
        get {
            return self.realm?.objects(RealmSpeechOverrideSetting.self).filter({ (speechOverrideSetting) -> Bool in
                return !speechOverrideSetting.isDeleted && speechOverrideSetting.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    
    var lastDownloadURL : String? {
        get {
            return linkedStorys?.sorted(byKeyPath: "chapterNumber", ascending: true).last?.url
        }
    }
    var lastDownloadDate: Date? {
        get {
            return linkedStorys?.sorted(byKeyPath: "downloadDate", ascending: true).last?.downloadDate
        }
    }
    var readingChapter: RealmStory? {
        get {
            return linkedStorys?.sorted(byKeyPath: "lastReadDate", ascending: true).last
        }
    }
    var lastReadDate: Date? {
        get {
            return readingChapter?.lastReadDate
        }
    }
    var isNewFlug: Bool {
        get {
            if let dd = lastDownloadDate {
                if let lr = lastReadDate {
                    return dd > lr
                }
            }
            return false
        }
    }
    
    override class func primaryKey() -> String? {
        return "novelID"
    }
    
    override static func indexedProperties() -> [String] {
        return ["writer", "title", "novelID", "likeLevel", "isDeleted"]
    }
}
extension RealmNovel: CKRecordConvertible {
}
extension RealmNovel: CKRecordRecoverable {
}

@objc final class RealmSpeechModSetting : Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var before : String = ""
    @objc dynamic var after : String = ""
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return self.realm?.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["before", "after", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechModSetting: CKRecordConvertible {
}
extension RealmSpeechModSetting: CKRecordRecoverable {
}

@objc final class RealmSpeechWaitConfig : Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var delayTimeInSec : Float = 0.0
    @objc dynamic var targetText : String = ""
    @objc dynamic var createdDate = Date()
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["targetText", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechWaitConfig: CKRecordConvertible {
}
extension RealmSpeechWaitConfig: CKRecordRecoverable {
}

@objc final class RealmSpeakerSetting : Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var pitch : Float = 1.0
    @objc dynamic var rate : Float = 1.0
    @objc dynamic var lmd : Float = 1.0
    @objc dynamic var acc : Float = 1.0
    @objc dynamic var base : Int32 = 1
    @objc dynamic var volume : Float = 1.0
    @objc dynamic var type : String = ""
    @objc dynamic var voiceIdentifier : String = ""
    @objc dynamic var locale : String = ""
    @objc dynamic var createdDate = Date()
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["id", "name", "createdDate", "isDeleted"]
    }
}
extension RealmSpeakerSetting: CKRecordConvertible {
}
extension RealmSpeakerSetting: CKRecordRecoverable {
}

@objc final class RealmSpeechSectionConfig : Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var startText = ""
    @objc dynamic var endText = ""
    @objc dynamic var createdDate = Date()
    
    @objc dynamic var speakerID: String = ""
    let targetNovelIDArray = List<String>()
    
    var speaker : RealmSpeakerSetting? {
        get {
            return self.realm?.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND id = %@", self.speakerID).first
        }
    }
    var targetNovelArray : [RealmNovel]? {
        get {
            return self.realm?.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["name", "startText", "createdDate", "speakerID", "isDeleted"]
    }
}
extension RealmSpeechSectionConfig: CKRecordConvertible {
}
extension RealmSpeechSectionConfig: CKRecordRecoverable {
}

@objc final class RealmSpeechQueue: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var createdDate = Date()
    
    let targetStoryIDArray = List<String>()
    
    var targetStoryArray : [RealmStory]? {
        get {
            return self.realm?.objects(RealmStory.self).filter({ (story) -> Bool in
                return !story.isDeleted && self.targetStoryIDArray.contains(story.id)
            })
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["createdDate", "name", "isDeleted"]
    }
}
extension RealmSpeechQueue: CKRecordConvertible {
}
extension RealmSpeechQueue: CKRecordRecoverable {
}

@objc final class RealmGlobalState: Object {
    @objc dynamic var id = "only one object"
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
    @objc dynamic var isMenuItemIsAddSpeechModSettingOnly = false
    @objc dynamic var isBackgroundNovelFetchEnabled = false
    @objc dynamic var bookSelfSortType : Int32 = 0
    
    @objc dynamic var defaultDisplaySettingID = ""
    @objc dynamic var defaultSpeakerID = ""
    @objc dynamic var defaultSpeechOverrideSettingID = ""
    
    var defaultDisplaySetting : RealmDisplaySetting? {
        get {
            return self.realm?.objects(RealmDisplaySetting.self).filter("isDeleted = false AND id = %@", self.defaultDisplaySettingID).first
        }
    }
    var defaultSpeaker : RealmSpeakerSetting? {
        get {
            return self.realm?.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND id = %@", self.defaultSpeakerID).first
        }
    }
    var defaultSpeechOverrideSetting : RealmSpeechOverrideSetting? {
        get {
            return self.realm?.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false AND id = %@", self.defaultSpeechOverrideSettingID).first
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
}
extension RealmGlobalState: CKRecordConvertible {
}
extension RealmGlobalState: CKRecordRecoverable {
}

@objc final class RealmDisplaySetting: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var textSizeValue: Float = 16.0
    @objc dynamic var fontID = ""
    @objc dynamic var name : String = ""
    @objc dynamic var isVertical: Bool = false
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return self.realm?.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    override static func indexedProperties() -> [String] {
        return ["id", "name", "createdDate", "isDeleted"]
    }
}
extension RealmDisplaySetting:CKRecordConvertible{
}
extension RealmDisplaySetting:CKRecordRecoverable{
}

@objc final class RealmNovelTag: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var type : String = ""
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return self.realm?.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["name", "targetNovelArray", "type", "createdDate", "isDeleted"]
    }
}
extension RealmNovelTag: CKRecordConvertible {
}
extension RealmNovelTag: CKRecordRecoverable {
}

@objc final class RealmSpeechOverrideSetting: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var createdDate = Date()
    @objc dynamic var repeatSpeechType : Int32 = 1
    @objc dynamic var isPageTurningSoundEnabled = false
    @objc dynamic var isOverrideRubyIsEnabled = false
    @objc dynamic var notRubyCharactorStringArray = "・、 　?？!！"
    @objc dynamic var isIgnoreURIStringSpeechEnabled = false

    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            return self.realm?.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    override class func primaryKey() -> String? {
        return "id"
    }
    
    override static func indexedProperties() -> [String] {
        return ["name", "targetNovelArray", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechOverrideSetting: CKRecordConvertible {
}
extension RealmSpeechOverrideSetting: CKRecordRecoverable {
}

