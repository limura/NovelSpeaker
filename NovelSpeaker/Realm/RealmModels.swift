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
    static let currentSchemaVersion : UInt64 = 0
    static let deleteRealmIfMigrationNeeded: Bool = true
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

    static let UseCloudRealmKey = "RealmUtil_UseCloudRealm"
    @objc static func IsUseCloudRealm() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [UseCloudRealmKey: false])
        return defaults.bool(forKey: UseCloudRealmKey)
    }
    static func SetIsUseCloudRealm(isUse:Bool) {
        let defaults = UserDefaults.standard
        defaults.set(isUse, forKey: UseCloudRealmKey)
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
    @objc static func IsValidRealmData() -> Bool {
        return RealmGlobalState.GetInstance() != nil
    }
    @discardableResult
    static func refresh() -> Bool {
        guard let realm = try? GetRealm() else {
            return false
        }
        return realm.refresh()
    }
    
    // TODO: 書き込み失敗を無視している
    static func Write(block:((_ realm:Realm)->Void)) {
        guard let realm = try? RealmUtil.GetRealm() else {
            print("realm get failed.")
            return
        }
        realm.refresh()
        do {
            try realm.write {
                block(realm)
            }
        }catch{
            print("realm.write failed.")
        }
    }

    // TODO: 書き込み失敗を無視している
    static func Write(withoutNotifying:[NotificationToken?], block:((_ realm:Realm)->Void)) {
        guard let realm = try? RealmUtil.GetRealm() else { return }
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
    }

    static func Delete(realm:Realm, model:Object) {
        if var model = model as? CanWriteIsDeleted {
            model.isDeleted = true
        }
        if !IsUseCloudRealm() {
            realm.delete(model)
        }
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
    @objc dynamic var lastReadDate = Date(timeIntervalSince1970: 0)
    @objc dynamic var downloadDate = Date()
    @objc dynamic var subtitle = ""

    var linkedQueues : [RealmSpeechQueue]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechQueue.self).filter({ (speechQueue) -> Bool in
                return !speechQueue.isDeleted && speechQueue.targetStoryIDArray.contains(self.id)
            })
        }
    }
    var owner : RealmNovel? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter("isDeleted = false AND novelID = %@", self.novelID).first
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
            return Int(string: numString) ?? 0
        }
        return 0
    }
    static func SearchStory(novelID:String, chapterNumber:Int) -> RealmStory? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmStory.self, forPrimaryKey: CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber)), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    static func GetAllObjects() -> Results<RealmStory>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmStory.self).filter("isDeleted = false")
    }
    static func CreateNewStory(novelID:String, chapterNumber:Int) -> RealmStory {
        let story = RealmStory()
        story.id = CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber)
        story.chapterNumber = chapterNumber
        story.novelID = novelID
        return story
    }

    static func SearchStoryFrom(storyID:String) -> RealmStory? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmStory.self, forPrimaryKey: storyID), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    func delete(realm:Realm) {
        if let queueArray = linkedQueues {
            for queue in queueArray {
                queue.unref(realm:realm, story: self)
            }
        }
        RealmUtil.Delete(realm: realm, model: self)
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
extension RealmStory: CanWriteIsDeleted {
}

@objc enum NovelType: Int {
    case URL = 1
    case UserCreated = 2
}

@objc final class RealmNovel : Object {
    @objc dynamic var novelID : String = RealmNovel.CreateUniqueID() // novelID は primary key です。
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var _type : Int = NovelType.URL.rawValue
    @objc dynamic var writer : String = ""
    @objc dynamic var title : String = ""
    @objc dynamic var url : String = ""
    @objc dynamic var _urlSecret : String = ""
    @objc dynamic var createdDate : Date = Date()
    @objc dynamic var likeLevel : Int8 = 0
    @objc dynamic var isNeedSpeechAfterDelete : Bool = false
    
    var type : NovelType {
        get {
            return NovelType(rawValue: self._type) ?? NovelType.UserCreated
        }
        set {
            self._type = newValue.rawValue
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
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmStory.self).filter("isDeleted = false AND novelID = %@", self.novelID)
        }
    }
    var linkedSpeechModSettings : [RealmSpeechModSetting]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechModSetting.self).filter({ (speechModSetting) -> Bool in
                return !speechModSetting.isDeleted && speechModSetting.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    var linkedSpeechSectionConfigs : [RealmSpeechSectionConfig]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechSectionConfig.self).filter({ (speechSectionConfig) -> Bool in
                return !speechSectionConfig.isDeleted && speechSectionConfig.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    var linkedDisplaySettings : [RealmDisplaySetting]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmDisplaySetting.self).filter({ (displaySetting) -> Bool in
                return !displaySetting.isDeleted && displaySetting.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    
    var linkedTags : [RealmNovelTag]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovelTag.self).filter({ (novelTag) -> Bool in
                return !novelTag.isDeleted && novelTag.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    
    var linkedRealmSpeechOverrideSettings : [RealmSpeechOverrideSetting]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechOverrideSetting.self).filter({ (speechOverrideSetting) -> Bool in
                return !speechOverrideSetting.isDeleted && speechOverrideSetting.targetNovelIDArray.contains(self.novelID)
            })
        }
    }
    
    var lastChapter : RealmStory? {
        get {
            return linkedStorys?.sorted(byKeyPath: "chapterNumber", ascending: true).last
        }
    }
    var lastChapterNumber : Int? {
        get {
            return lastChapter?.chapterNumber
        }
    }
    var lastDownloadURL : String? {
        get {
            return lastChapter?.url
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
        if let dd = lastDownloadDate {
            if let lr = lastReadDate {
                return dd > lr
            }
        }
        return false
    }
    
    var urlSecret: [String] {
        get {
            return _urlSecret.components(separatedBy: ";")
        }
    }
    
    // 推測によるアップデート頻度。単位は1日に何度更新されるのか(1日に1度なら1、10日に1度なら0.1、1日に3度なら3)。
    // 計算としては 章数 / (現在 - 直近から数えて10個前のものがダウンロードされた日付)[日] なので、最後にダウンロードされた日付が古くても評価は下がる。
    // 最初に1000件とかダウンロードされた小説が既に更新終了していたとしても、10件分しか効果がないので10日経つと1に、100日経てば0.1になる。
    var updateFrequency: Double {
        get {
            guard let storys = linkedStorys?.sorted(byKeyPath: "downloadDate", ascending: true) else {
                return 1.0 / 30.0 // 未ダウンロードのものは30日に1度の頻度とする。
            }
            let count:Double
            let targetStory:RealmStory?
            if storys.count >= 10 {
                count = 10.0
                targetStory = storys[storys.count - 10]
            }else{
                count = Double(storys.count)
                targetStory = storys.first
            }
            let targetDownloadDate:Date
            if let story = targetStory {
                targetDownloadDate = story.downloadDate
            }else{
                targetDownloadDate = Date(timeIntervalSinceNow: -60*60*24*30)
            }
            let diffTimeInSec = Date().timeIntervalSince1970 - targetDownloadDate.timeIntervalSince1970
            return Double(count) / (diffTimeInSec / (60.0*60.0*24))
        }
    }
    
    public static func CreateUniqueID() -> String {
        return "https://example.com/\(NSUUID().uuidString)"
    }
    
    static func GetAllObjects() -> Results<RealmNovel>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmNovel.self).filter("isDeleted = false")
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
        let novel = RealmNovel()
        novel.type = .UserCreated
        novel.title = title
        RealmUtil.Write { (realm) in
            realm.add(novel, update: true)
        }
        let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: 1)
        story.content = content
        story.lastReadDate = Date(timeIntervalSinceNow: -60)
        RealmUtil.Write { (realm) in
            realm.add(story, update: true)
        }
    }
    static func AddNewNovelWithMultiplText(contents:[String], title:String) {
        let novel = RealmNovel()
        novel.type = .UserCreated
        novel.title = title
        RealmUtil.Write { (realm) in
            realm.add(novel, update: true)
        }
        var chapterNumber = 1
        for content in contents {
            if content.count <= 0 { continue }
            let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: chapterNumber)
            story.content = content
            if chapterNumber != 1 {
                story.lastReadDate = Date(timeIntervalSinceNow: -60)
            }
            RealmUtil.Write { (realm) in
                realm.add(story, update: true)
            }
            chapterNumber += 1
        }
    }
    
    static func AddNewNovelWithFirstStory(url:URL, htmlStory:HtmlStory, cookieParameter:String, title:String, author:String?, tag:[Any]?, firstContent:String) -> Bool {
        let novelID = url.absoluteString
        guard novelID.count > 0 else {
            return false
        }
        if SearchNovelFrom(novelID: url.absoluteString) != nil {
            // already downloaded.
            return false
        }
        let novel = RealmNovel()
        novel.novelID = novelID
        novel._urlSecret = cookieParameter
        novel.title = title
        if let author = author {
            novel.writer = author
        }
        novel.type = .URL
        guard let realm = try? RealmUtil.GetRealm() else { return false }
        try! realm.write {
            realm.add(novel, update: true)
        }
        let story = RealmStory.CreateNewStory(novelID: novel.novelID, chapterNumber: 1)
        story.content = firstContent
        if let subtitle = htmlStory.subtitle {
            story.subtitle = subtitle
        }
        if let storyUrl = htmlStory.url {
            story.url = storyUrl
        }
        try! realm.write {
            story.lastReadDate = Date(timeIntervalSinceNow: -60)
            realm.add(story, update: true)
        }
        if let tagArray = tag {
            for tagName in tagArray {
                if let tagName = tagName as? String {
                    RealmNovelTag.AddTag(tagName: tagName, novelID: novelID, type: "keyword")
                }
            }
        }
        return true
    }
    
    func delete(realm:Realm) {
        if let storyArray = linkedStorys {
            for story in storyArray {
                story.delete(realm: realm)
            }
        }
        if let speechModSettingArray = linkedSpeechModSettings {
            for speechModSetting in speechModSettingArray {
                speechModSetting.unref(realm:realm, novel: self)
            }
        }
        if let speechSectionConfigArray = linkedSpeechSectionConfigs {
            for speechSectionConfig in speechSectionConfigArray {
                speechSectionConfig.unref(realm:realm, novel: self)
            }
        }
        if let displaySettingArray = linkedDisplaySettings {
            for displaySetting in displaySettingArray {
                displaySetting.unref(realm:realm, novel: self)
            }
        }
        if let tagArray = linkedTags {
            for tag in tagArray {
                tag.unref(realm:realm, novel: self)
            }
        }
        if let realmSpeechOverrideSettingArray = linkedRealmSpeechOverrideSettings {
            for realmSpeechOverrideSetting in realmSpeechOverrideSettingArray {
                realmSpeechOverrideSetting.unref(realm:realm, novel: self)
            }
        }
        RealmUtil.Delete(realm: realm, model: self)
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
    
    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechModSetting>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeechModSetting.self).filter("isDeleted = false")
    }
    static func SearchFrom(beforeString:String) -> RealmSpeechModSetting? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmSpeechModSetting.self, forPrimaryKey: beforeString), result.isDeleted == false {
            return result
        }
        return nil
    }

    func unref(realm:Realm, novel:RealmNovel) {
        if let index = targetNovelIDArray.index(of: novel.novelID) {
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
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeechWaitConfig.self).filter("isDeleted = false")
    }

    static func SearchFrom(targetText:String) -> RealmSpeechWaitConfig? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
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
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false")
    }
    
    static func SearchFrom(name:String) -> RealmSpeakerSetting? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmSpeakerSetting.self, forPrimaryKey: name), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    func applyTo(speaker:Speaker) {
        speaker.setPitch(pitch)
        speaker.setRate(rate)
        speaker.setVoiceWithIdentifier(voiceIdentifier)
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
extension RealmSpeakerSetting: CKRecordConvertible {
}
extension RealmSpeakerSetting: CKRecordRecoverable {
}
extension RealmSpeakerSetting: CanWriteIsDeleted {
}

@objc final class RealmSpeechSectionConfig : Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var startText = "「"
    @objc dynamic var endText = "」"
    @objc dynamic var createdDate = Date()
    
    @objc dynamic var speakerID: String = ""
    let targetNovelIDArray = List<String>()
    
    var speaker : RealmSpeakerSetting? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.speakerID).first
        }
    }
    var targetNovelArray : [RealmNovel]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechSectionConfig>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeechSectionConfig.self).filter("isDeleted = false")
    }

    static func SearchFrom(id:String) -> RealmSpeechSectionConfig? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmSpeechSectionConfig.self, forPrimaryKey: id), result.isDeleted == false {
            return result
        }
        return nil
    }

    func unref(realm: Realm, novel: RealmNovel) {
        if let index = targetNovelIDArray.index(of: novel.novelID) {
            targetNovelIDArray.remove(at: index)
            if targetNovelIDArray.count <= 0 {
                delete(realm: realm)
            }
        }
    }
    func delete(realm: Realm) {
        RealmUtil.Delete(realm: realm, model: self)
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
extension RealmSpeechSectionConfig: CanWriteIsDeleted {
}

@objc final class RealmSpeechQueue: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var createdDate = Date()
    
    let targetStoryIDArray = List<String>()
    
    var targetStoryArray : [RealmStory]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmStory.self).filter({ (story) -> Bool in
                return !story.isDeleted && self.targetStoryIDArray.contains(story.id)
            })
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechQueue>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeechQueue.self).filter("isDeleted = false")
    }

    static func SearchFrom(id:String) -> RealmSpeechQueue? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmSpeechQueue.self, forPrimaryKey: id), result.isDeleted == false {
            return result
        }
        return nil
    }

    func unref(realm:Realm, story:RealmStory) {
        if let index = targetStoryIDArray.index(of: story.id) {
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
    @objc dynamic var isMenuItemIsAddSpeechModSettingOnly = false
    @objc dynamic var isBackgroundNovelFetchEnabled = false
    @objc dynamic var isPageTurningSoundEnabled = false
    @objc dynamic var _bookSelfSortType : Int = Int(NarouContentSortType.ncode.rawValue)
    
    @objc dynamic var defaultDisplaySettingID = ""
    @objc dynamic var defaultSpeakerID = ""
    @objc dynamic var defaultSpeechOverrideSettingID = ""
    
    var bookShelfSortType : NarouContentSortType {
        get {
            return NarouContentSortType(rawValue: UInt(_bookSelfSortType)) ?? NarouContentSortType.ncode
        }
        set {
            _bookSelfSortType = Int(newValue.rawValue)
        }
    }
    
    var defaultDisplaySetting : RealmDisplaySetting? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false AND id = %@", self.defaultDisplaySettingID).first
        }
    }
    var defaultSpeaker : RealmSpeakerSetting? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", self.defaultSpeakerID).first
        }
    }
    var defaultSpeechOverrideSetting : RealmSpeechOverrideSetting? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false AND id = %@", self.defaultSpeechOverrideSettingID).first
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
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmStory.self).sorted(byKeyPath: "lastReadDate", ascending: true).last
    }
    static func GetLastReadNovel() -> RealmNovel? {
        guard let realm = try? RealmUtil.GetRealm(), let lastReadStory = GetLastReadStory() else { return nil }
        realm.refresh()
        return realm.object(ofType: RealmNovel.self, forPrimaryKey: lastReadStory.novelID)
    }

    static public func GetInstance() -> RealmGlobalState? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.object(ofType: RealmGlobalState.self, forPrimaryKey: UniqueID)
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
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var textSizeValue: Float = 58.0
    @objc dynamic var fontID = ""
    @objc dynamic var name : String = ""
    @objc dynamic var isVertical: Bool = false
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    static func GetAllObjects() -> Results<RealmDisplaySetting>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmDisplaySetting.self).filter("isDeleted = false")
    }

    static func SearchFrom(id:String) -> RealmDisplaySetting? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        if let result = realm.object(ofType: RealmDisplaySetting.self, forPrimaryKey: id), result.isDeleted == false {
            return result
        }
        return nil
    }
    
    static func convertFontSizeValue(textSizeValue:Float) -> Float {
        var value = textSizeValue
        if value < 1.0 {
            value = 1.0;
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

    func unref(realm: Realm, novel: RealmNovel) {
        if let index = targetNovelIDArray.index(of: novel.novelID) {
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
        return ["id", "name", "createdDate", "isDeleted"]
    }
}
extension RealmDisplaySetting:CKRecordConvertible{
}
extension RealmDisplaySetting:CKRecordRecoverable{
}
extension RealmDisplaySetting: CanWriteIsDeleted {
}

@objc final class RealmNovelTag: Object {
    @objc dynamic var name = "" // name を primaryKey にします。
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var type : String = ""
    @objc dynamic var createdDate = Date()
    
    let targetNovelIDArray = List<String>()
    
    var targetNovelArray : [RealmNovel]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    static func GetAllObjects() -> Results<RealmNovelTag>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmNovelTag.self).filter("isDeleted = false")
    }
    
    static func SearchWith(tagName:String) -> RealmNovelTag? {
        return GetAllObjects()?.filter("name = %@", tagName).first
    }
    
    static func AddTag(tagName:String, novelID: String, type: String) {
        if tagName.count <= 0 || novelID.count <= 0 {
            return
        }
        if let tag = SearchWith(tagName: tagName) {
            if !tag.targetNovelIDArray.contains(novelID) {
                tag.targetNovelIDArray.append(novelID)
            }
        }else{
            let tag = RealmNovelTag()
            tag.name = tagName
            tag.targetNovelIDArray.append(novelID)
            tag.type = type
            if let realm = try? RealmUtil.GetRealm() {
                realm.add(tag, update: true)
            }
        }
    }
    
    func unref(realm:Realm, novel:RealmNovel) {
        if let index = targetNovelIDArray.index(of: novel.novelID) {
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
        return ["name", "targetNovelArray", "type", "createdDate", "isDeleted"]
    }
}
extension RealmNovelTag: CKRecordConvertible {
}
extension RealmNovelTag: CKRecordRecoverable {
}
extension RealmNovelTag: CanWriteIsDeleted {
}

@objc final class RealmSpeechOverrideSetting: Object {
    @objc dynamic var id = NSUUID().uuidString
    @objc dynamic var isDeleted: Bool = false
    @objc dynamic var name = ""
    @objc dynamic var createdDate = Date()
    @objc dynamic var _repeatSpeechType : Int = Int(RepeatSpeechType.noRepeat.rawValue)
    @objc dynamic var isOverrideRubyIsEnabled = false
    @objc dynamic var notRubyCharactorStringArray = "・、 　?？!！"
    @objc dynamic var isIgnoreURIStringSpeechEnabled = false

    let targetNovelIDArray = List<String>()
    
    var repeatSpeechType : RepeatSpeechType {
        get {
            return RepeatSpeechType(rawValue: UInt(_repeatSpeechType)) ?? RepeatSpeechType.noRepeat
        }
        set {
            _repeatSpeechType = Int(newValue.rawValue)
        }
    }
    
    var targetNovelArray : [RealmNovel]? {
        get {
            guard let realm = try? RealmUtil.GetRealm() else { return nil }
            realm.refresh()
            return realm.objects(RealmNovel.self).filter({ (novel) -> Bool in
                return !novel.isDeleted && self.targetNovelIDArray.contains(novel.novelID)
            })
        }
    }
    
    static func GetAllObjects() -> Results<RealmSpeechOverrideSetting>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false")
    }
    static func SearchObjectFrom(novelID:String) -> LazyFilterSequence<Results<RealmSpeechOverrideSetting>>? {
        guard let realm = try? RealmUtil.GetRealm() else { return nil }
        realm.refresh()
        return realm.objects(RealmSpeechOverrideSetting.self).filter("isDeleted = false").filter({ (setting) -> Bool in
            return setting.targetNovelIDArray.contains(novelID)
        })
    }
    static func SearchObjectFrom(id:String) -> RealmSpeechOverrideSetting? {
        return GetAllObjects()?.filter("id = %@", id).first
    }
    func unref(realm:Realm, novel:RealmNovel) {
        if let index = targetNovelIDArray.index(of: novel.novelID) {
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
        return ["name", "targetNovelArray", "createdDate", "isDeleted"]
    }
}
extension RealmSpeechOverrideSetting: CKRecordConvertible {
}
extension RealmSpeechOverrideSetting: CKRecordRecoverable {
}
extension RealmSpeechOverrideSetting: CanWriteIsDeleted {
}

