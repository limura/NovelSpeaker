//
//  DownloadQueueHolder.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/22.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift
import UserNotifications
#if !os(watchOS)
import FTLinearActivityIndicator
import BackgroundTasks
#endif

fileprivate class QueueItem {
    let novelID:String
    let updateFrequency:Double
    init(novelID:String, updateFrequency:Double) {
        self.novelID = novelID
        self.updateFrequency = updateFrequency
    }
    
    var hostName:String {
        get {
            if let url = URL(string: novelID), let host = url.host {
                return host
            }
            return ""
        }
    }
}

// novelID(String、内部的には URL文字列) を Queue として保持します。getNextQueue() で取り出して使いますが、
// 使い終わったら downloadDone() で使い終わった事を報告する義務があります。
// downloadDone() が行われないと、同一hostのQueueは取り出されません。
// 逆に言うと、この queue を使う事で、同一hostへの並列(同時)アクセスを防ぐことができます。
class DownloadQueueHolder: NSObject {
    let lock = NSLock()
    fileprivate var queue:[String:[QueueItem]] = [String:[QueueItem]]()
    var nowDownloading = [String:String]()
    
    func addQueue(novelArray:ThreadSafeReference<Results<RealmNovel>>) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novelArray = realm.resolve(novelArray) else { return }
            let novelLikeOrder = RealmGlobalState.GetInstanceWith(realm: realm)?.novelLikeOrder ?? List<String>()
            let downloadingNovelIDArray = GetCurrentDownloadingNovelIDArray()
            
            self.lock.lock()
            defer { self.lock.unlock() }
            for novel in novelArray {
                if novel.isNotNeedUpdateCheck { continue }
                if novel.type == .UserCreated {
#if !os(watchOS)
                    if NovelSpeakerUtility.IsRegisteredOuterNovel(novelID: novel.novelID) {
                        NovelSpeakerUtility.CheckAndUpdateRgisterdOuterNovel(novelID: novel.novelID)
                    }
#endif
                    continue
                }
                if novel.type != .URL { continue }
                if downloadingNovelIDArray.contains(novel.novelID) { continue }
                let updateFrequency = novel.updateFrequency(novelLikeOrder: novelLikeOrder)
                let item = QueueItem(novelID: novel.novelID, updateFrequency: updateFrequency)
                let hostName = item.hostName
                if var queueList = queue[hostName] {
                    if queueList.filter({$0.novelID == item.novelID}).first != nil {
                        continue
                    }
                    queueList.append(item)
                    queue[hostName] = queueList
                }else{
                    queue[hostName] = [item]
                }
            }
            for hostName in queue.keys {
                if let queueList = queue[hostName] {
                    queue[hostName] = queueList.sorted(by: { (a, b) -> Bool in
                        a.updateFrequency > b.updateFrequency
                    })
                }
            }
        }
    }
    
    func addQueue(novelID:String) {
        var updateFrequencyTmp:Double? = nil
        guard novelID.count > 0 else { return }
        RealmUtil.RealmBlock { (realm) -> Void in
            let novelLikeOrder = RealmGlobalState.GetInstanceWith(realm: realm)?.novelLikeOrder ?? List<String>()
            if let updateFrequency = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.updateFrequency(novelLikeOrder: novelLikeOrder) {
                updateFrequencyTmp = updateFrequency
            }
        }
        guard let updateFrequency = updateFrequencyTmp else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        let item = QueueItem(novelID: novelID, updateFrequency: updateFrequency)
        let hostName = item.hostName
        if var queueList = queue[hostName] {
            for queue in queueList {
                if queue.novelID == item.novelID {
                    return
                }
            }
            queueList.append(item)
            queue[hostName] = queueList.sorted(by: { (a, b) -> Bool in
                a.updateFrequency > b.updateFrequency
            })
        }else{
            queue[hostName] = [item]
        }
    }
    func downloadDone(novelID:String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        let item = QueueItem(novelID: novelID, updateFrequency: 0.0)
        let hostName = item.hostName
        nowDownloading.removeValue(forKey: hostName)
    }
    func getNextQueue() -> String? {
        var item:QueueItem = QueueItem(novelID: "", updateFrequency: -1.0)
        self.lock.lock()
        defer { self.lock.unlock() }
        for hostName in queue.keys {
            if nowDownloading.keys.contains(hostName) {
                continue
            }
            guard let itemList = queue[hostName], let targetItem = itemList.first else { continue }
            if item.updateFrequency < targetItem.updateFrequency {
                item = targetItem
            }
        }
        if item.novelID == "" {
            // 一通りダウンロードが終わったようなのでその時点でのcookieを保存します
            HTTPCookieSyncTool.shared.Save()
            return nil
        }
        if var itemList = queue[item.hostName] {
            itemList.removeFirst()
            queue[item.hostName] = itemList
        }
        nowDownloading[item.hostName] = item.novelID
        
        return item.novelID
    }
    
    func GetCurrentDownloadingNovelIDArray() -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return Array(nowDownloading.values)
    }
    func GetCurrentQueuedNovelIDArray() -> [String] {
        var result:[String] = []
        self.lock.lock()
        defer { self.lock.unlock() }
        for items in queue.values {
            result.append(contentsOf: items.map({ (item) -> String in
                return item.novelID
            }))
        }
        return result
    }
    func GetCurrentDownloadStatusSummary() -> String {
        self.lock.lock()
        defer { self.lock.unlock() }
        var resultMap:[String:Int] = [:]
        for (key, item) in queue {
            resultMap[key] = item.count
        }
        for host in nowDownloading.keys {
            if var v = resultMap[host] {
                v += 1
            }else{
                resultMap[host] = 1
            }
        }
        return resultMap.map({"\($0.key): \($0.value)"}).joined(separator: "\n")
    }
    func ClearAllQueue() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.nowDownloading.removeAll()
        self.queue.removeAll()
    }
}

// 読み込みを何秒に一回にするのかの値[秒]
fileprivate var queueDelayTime = 1.05
// 一定時間に一回しか動かさないようにする。
fileprivate func delayQueue(queuedDate: Date, block:@escaping ()->Void) {
    let now = Date()
    let diffTime = queuedDate.timeIntervalSince1970 - now.timeIntervalSince1970 + queueDelayTime
    if diffTime < 0 {
        DispatchQueue.global(qos: .utility).async {
            block()
        }
    }else{
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + diffTime) {
            block()
        }
    }
}

// RealmStoryBulk を使う時に、Bulk で分割される分のStoryを「ちょうどよく」Writeするために write を保留するclass
class StoryBulkWritePool {
    let lock = NSLock()
    let novelID:String
    var storyArray:[Story] = []
    
    public init(novelID:String) {
        self.novelID = novelID
    }
    
    public func Flush() {
        lock.lock()
        defer { lock.unlock() }
        RealmUtil.Write { (realm) in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                let lastStory = RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                if let lastStory = lastStory {
                    novel.m_lastChapterStoryID = lastStory.storyID
                    novel.lastDownloadDate = lastStory.downloadDate
                }
                /*
                if let firstStory = storyArray.first, firstStory.chapterNumber == 1 {
                    novel.m_readingChapterStoryID = firstStory.storyID
                }
                */
                novel.AppendDownloadDate(realm: realm, dateArray: storyArray.map({$0.downloadDate}))
                realm.add(novel, update: .modified)
            }
        }
        storyArray.removeAll()
    }
    
    public func AddStory(story:Story) {
        /* // 同じStoryが登録されていても無視して古いのを優先して保存するようにしたのでチェックは外します
        // TODO: 同じStoryが登録されている場合があるのでチェックしています。
        // 本来ならこの操作は必要無いはずです。
        if storyArray.count <= 0 {
            if RealmUtil.RealmBlock(block: { (realm) -> Bool in
                let (_, lastChapterNumber, _) = RealmStoryBulk.CountStoryFor(realm: realm, novelID: story.novelID)
                print("novel.lastChapterNumber: \(lastChapterNumber), story.chapterNumber: \(story.chapterNumber)")
                if story.chapterNumber != (lastChapterNumber + 1) {
                    AppInformationLogger.AddLog(message: "StoryBulkWritePool.AddStory() で不正なchapterNumberのStoryが登録されようとしている", appendix: [
                        "StoryID": story.storyID,
                        "novel.lastChapterNumber +1 != story.chapterNumber": "\(lastChapterNumber) +1 != \(story.chapterNumber)",
                        "既に writePool に保存されている Story の数": "なし",
                        "stackTrace": NiftyUtility.GetStackTrace(),
                    ], isForDebug: true)
                    if story.chapterNumber == lastChapterNumber {
                        return true
                    }
                }
                return false
            }) {
                AppInformationLogger.AddLog(message: "リカバリできそうなのでこの Story は無視します。", appendix: ["StoryID": story.storyID], isForDebug: true)
                return
            }
        }else if let lastChapterNumber = storyArray.last?.chapterNumber, story.chapterNumber != (lastChapterNumber + 1) {
            AppInformationLogger.AddLog(message: "StoryBulkWritePool.AddStory() で不正なchapterNumberのStoryが登録されようとしている", appendix: [
                "StoryID": story.storyID,
                "novel.lastChapterNumber": "\(lastChapterNumber)",
                "既に writePool に保存されている Story の数": "\(storyArray.count)",
                "stackTrace": NiftyUtility.GetStackTrace(),
            ], isForDebug: true)
            if story.chapterNumber == lastChapterNumber {
                AppInformationLogger.AddLog(message: "リカバリできそうなのでこの Story は無視します。", appendix: ["StoryID": story.storyID], isForDebug: true)
                return
            }
        }
         */
        lock.lock()
        storyArray.append(story)
        let storyArrayCount:Int = storyArray.count
        lock.unlock()
        let chapterNumber = story.chapterNumber
        let maxLength = RealmStoryBulk.bulkCount - ((chapterNumber - 1) % RealmStoryBulk.bulkCount)
        if NovelDownloadQueue.shared.currentDownloadingNovelCount <= 1 || storyArrayCount >= maxLength || RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID) == novelID {
            Flush()
        }
    }
}

// 一つの小説をダウンロードしようとします。
// startDownload() を呼び出す事でダウンロードを開始します。
// ダウンロードが正常に終了したら successAction を、何らかの問題で失敗終了したら failedAction が呼び出されます。
// 注意：小説と最初の章が登録されている必要があります。つまり、続きの章のダウンロード用の物になります。
class NovelDownloader : NSObject {
    // 一度にダウンロードされる章の最大数
    static var maxCount = 50000
    // ダウンロードを止めたい時に true を入れます。
    static var isDownloadStop : Bool {
        get {
            return NovelDownloadQueue.shared.isDownloadStop
        }
    }
    static var writePool:[String:StoryBulkWritePool] = [:]
    static func FlushAllWritePool() {
        writePoolLock.lock()
        for (_, pool) in writePool {
            pool.Flush()
        }
        writePool.removeAll()
        writePoolLock.unlock()
    }
    static let writePoolLock = NSLock()
    static func addWritePool(novelID:String, story:Story) {
        writePoolLock.lock()
        defer { writePoolLock.unlock() }
        if let pool = writePool[novelID] {
            pool.AddStory(story: story)
        }else{
            let pool = StoryBulkWritePool(novelID: novelID)
            pool.AddStory(story: story)
            writePool[novelID] = pool
        }
    }
    @discardableResult
    static func flushWritePool(novelID:String) -> Bool {
        writePoolLock.lock()
        defer { writePoolLock.unlock() }
        if let pool = writePool.removeValue(forKey: novelID) {
            pool.Flush()
            return true
        }
        return false
    }
    
    static func startDownload(novelID:String, fetcher:StoryFetcher, currentState:StoryState? = nil, chapterNumber:Int = 0, downloadCount:Int = 0, successAction:@escaping ((_ novelID:String, _ downloadCount:Int)->Void), failedAction:@escaping ((_ novelID: String, _ downloadCount:Int, _ errorDescription:String)->Void)) {
        BehaviorLogger.AddLogSimple(description: "startDownload: \(novelID), chapter: \(chapterNumber)")
        if isDownloadStop {
            flushWritePool(novelID: novelID)
            BehaviorLogger.AddLogSimple(description: "NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, 0)
            return
        }
        if downloadCount > NovelDownloader.maxCount {
            flushWritePool(novelID: novelID)
            BehaviorLogger.AddLogSimple(description: "NovelDownloader.downloadOnce(): ダウンロード回数が規定値(\(NovelDownloader.maxCount))を超えたのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, downloadCount)
            return
        }
        func failedSearchNovel(hint:String) {
            flushWritePool(novelID: novelID)
            let msg = NSLocalizedString("NovelDownloader_InvalidNovelID", comment: "小説のダウンロードに失敗しました。ダウンロードするためのデータ(URL等)を取得できずにダウンロードを開始できませんでした。小説データが保存されていないか削除された等の問題がありそうです。") + "\n(novelID: \"\(novelID)\", hint: \(hint))"
            BehaviorLogger.AddLogSimple(description: msg)
            failedAction(novelID, 0, msg)
        }
        var isNovelAlive:Bool = true
        var lastChapter:Story? = nil
        RealmUtil.RealmBlock { (realm) -> Void in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                // novel.m_lastChapterStoryID は無視して StoryBulk 側のデータを使う事にします
                let (_, _, lastStory) = RealmStoryBulk.CountStoryFor(realm: realm, novelID: novel.novelID)
                lastChapter = lastStory
                // 一応 m_lastChapterStoryID が違うようであれば書き換えておきます。
                if let lastStory = lastStory {
                    if novel.m_lastChapterStoryID != RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: lastStory.chapterNumber) {
                        RealmUtil.WriteWith(realm: realm) { realm in
                            novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: lastStory.chapterNumber)
                            realm.add(novel, update: .modified)
                        }
                    }
                }
            }else{
                isNovelAlive = false
            }
        }
        if isNovelAlive == false {
            failedSearchNovel(hint: "SearchNovelWith() failed.")
            return
        }
        var chapterNumber = chapterNumber
        var lastDownloadURLTmp:URL? = nil
        if chapterNumber == 0 { // 初期状態なら
            // 読み込まれている分は飛ばして最後のURLから再開
            if let lastChapter = lastChapter, let targetURL = URL(string: lastChapter.url) {
                chapterNumber = lastChapter.chapterNumber
                lastDownloadURLTmp = targetURL
                // 章が読み込まれていないのなら最初の章を読み込む
            }else if let targetURL = URL(string: novelID) {
                chapterNumber = 1
                lastDownloadURLTmp = targetURL
            }else{
                // 章もなければ novelID もURLではない。エラーだ。(´・ω・`)
                failedSearchNovel(hint: "invalid novelID or no story")
                return
            }
        }
        let queuedDate = Date()
        let state:StoryState
        if let currentState = currentState {
            state = currentState
        }else if let lastDownloadURL = lastDownloadURLTmp {
            print("lastDownloadURL:", lastDownloadURL.absoluteString)
            state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfo(url: lastDownloadURL, cookieString: "", previousContent: nil)
        }else{
            failedSearchNovel(hint: "currentState and lastDownloadURL is nil.")
            return
        }
        fetcher.FetchNext(currentState: state, successAction: { (state) in
            if isDownloadStop {
                flushWritePool(novelID: novelID)
                BehaviorLogger.AddLogSimple(description: "NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します(FetchNext完了時)。novelID: \(novelID)")
                successAction(novelID, 0)
                return
            }
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else {
                    failedSearchNovel(hint: "SearchNovel failed in FetchNext success handler")
                    return
                }
                let lastChapter = novel.lastChapterWith(realm: realm)
                if chapterNumber == 1 && lastChapter == nil {
                    // 章が一つもダウンロードされていないようなので、
                    // 恐らくは小説名なども登録されていないと思われるため、
                    // このタイミングで小説名等をNovelに書き込む。
                    RealmUtil.WriteWith(realm: realm) { (realm) in
                        if let title = state.title, novel.title.count <= 0 {
                            novel.title = title
                        }
                        if let author = state.author, novel.writer.count <= 0 {
                            novel.writer = author
                        }
                        realm.add(novel, update: .modified)
                        for keyword in state.tagArray {
                            RealmNovelTag.AddTag(realm: realm, name: keyword, novelID: novelID, type: RealmNovelTag.TagType.Keyword)
                        }
                    }
                }
                var nextChapterNumber = chapterNumber
                // まだ読み込まれていない章であれば追加するために writePool に入れておきます。
                if let content = state.content, (lastChapter?.chapterNumber ?? 0) < chapterNumber {
                    if content.count <= 0 {
                        // 登録できそうな章ではあったけれど内容が無い場合は登録しません。
                        // その場合は nextChapterNumber が増えることもありません。
                    }else{
                        var story = Story()
                        story.novelID = novelID
                        story.chapterNumber = chapterNumber
                        story.content = content.replacingOccurrences(of: "\u{00}", with: "")
                        if let subtitle = state.subtitle {
                            story.subtitle = subtitle
                        }
                        story.url = state.url.absoluteString
                        story.downloadDate = queuedDate
                        // storyの書き込み自体は writePool に突っ込んで後でやってもらうことにします。
                        addWritePool(novelID: novelID, story: story)
                        nextChapterNumber += 1
                    }
                }else{
                    // 既に存在する章だったようなので読み飛ばします
                    print("story \(chapterNumber) not add queue (maybe, no content or already exists story)")
                    nextChapterNumber += 1
                }
                if !state.IsNextAlive {
                    print("NovelDownloader.startDownload() IsNextAlive is false quit. \(state.url.absoluteString)")
                    successAction(novelID, downloadCount)
                    return
                }
                if let nextUrl = state.nextUrl, nextUrl == state.url {
                    print("NovelDownloader.startDownload() IsNextAlive is true, but nextUrl is same current URL. then quit: \(state.url.absoluteString)")
                    successAction(novelID, downloadCount)
                    return
                }
                if let firstPageLink = state.firstPageLink, firstPageLink == state.url {
                    print("NovelDownloader.startDownload() IsNextAlive is true, but firstPageLink is same current URL. then quit: \(state.url.absoluteString)")
                    successAction(novelID, downloadCount)
                    return
                }
                let dummyDate:Date
                if state.isCanFetchNextImmediately {
                    dummyDate = Date(timeIntervalSince1970: 0)
                }else{
                    dummyDate = queuedDate
                }
                delayQueue(queuedDate: dummyDate, block: {
                    startDownload(novelID: novelID, fetcher: fetcher, currentState: state.CreateNextState(), chapterNumber: nextChapterNumber, downloadCount: downloadCount + 1, successAction: successAction, failedAction: failedAction)
                })
            }
        }) { (url, errorString) in
            flushWritePool(novelID: novelID)
            let msg = NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url.absoluteString), errString: \(errorString))"
            BehaviorLogger.AddLogSimple(description: msg)
            failedAction(novelID, 0, msg)
        }
    }
}

class NovelDownloadQueue : NSObject {
    @objc static let shared = NovelDownloadQueue()
    private let queueHolder = DownloadQueueHolder()
    #if !os(watchOS)
    var maxSimultaneousDownloadCount = 5
    #else
    var maxSimultaneousDownloadCount = 1
    #endif
    let lock = NSLock()
    var downloadSuccessNovelIDSet = Set<String>()
    var downloadEndedNovelIDSet = Set<String>()
    public var isDownloadStop = true
    let semaphore = DispatchSemaphore(value: 0)
    
    let cacheFileExpireTimeinterval:Double = 60*60*6
    let DownloadCountKey = "NovelDownloadQueue_DownloadCount"
    let AlreadyBackgroundFetchedNovelIDListKey = "NovelDownloadQueue_AlreadyBackgroundFetchedNovelIDList"
    let backgroundFetchDeadlineTimeInSec:Double = 23.0
    let fetcherPoolLock = NSLock()
    var fetcherPool:[UUID:(Bool, StoryFetcher)] = [:]

    private override init() {
        super.init()
        startQueueWatcher()
    }
    
    func updateNetworkActivityIndicatorStatus(){
        #if !os(watchOS)
        let activityIndicatorID = "NovelDownloadQueue"
        DispatchQueue.main.async {
            if self.queueHolder.GetCurrentDownloadingNovelIDArray().count > 0 {
                ActivityIndicatorManager.enable(id: activityIndicatorID)
            }else{
                ActivityIndicatorManager.disable(id: activityIndicatorID)
            }
        }
        #endif
    }
    
    var currentDownloadingNovelCount:Int {
        get {
            return self.queueHolder.GetCurrentDownloadingNovelIDArray().count
        }
    }
    
    func GetFreeFetcher() -> (UUID, StoryFetcher) {
        let uuid = UUID()
        fetcherPoolLock.lock()
        defer { fetcherPoolLock.unlock() }
        if let result = fetcherPool.reduce(nil, { (result, tuple) -> (UUID, StoryFetcher)? in
            let (uuid, (isActive, fetcher)) = tuple
            if let result = result { return result }
            if !isActive { return (uuid, fetcher) }
            return nil
        }) {
            let (uuid, fetcher) = result
            fetcherPool[uuid] = (true, fetcher)
            return result
        }
        let fetcher = StoryFetcher()
        fetcherPool[uuid] = (true, fetcher)
        return (uuid, fetcher)
    }
    func FreeFetcher(uuid:UUID) {
        fetcherPoolLock.lock()
        defer { fetcherPoolLock.unlock() }
        if let (_, fetcher) = fetcherPool[uuid] {
            if !NovelSpeakerUtility.IsNotClearToAboutBlankOnDownloadBrowserUrl() {
                fetcher.LoadAboutPage()
            }
            fetcherPool[uuid] = (false, fetcher)
        }
    }
    func ClearUnusedFetcher() {
        fetcherPoolLock.lock()
        defer { fetcherPoolLock.unlock() }
        var removeList:[UUID] = []
        for key in fetcherPool {
            if key.value.0 == false {
                removeList.append(key.key)
            }
        }
        for uuid in removeList {
            fetcherPool.removeValue(forKey: uuid)
        }
    }
    
    func dispatch() {
        while self.isDownloadStop == false && self.queueHolder.GetCurrentDownloadingNovelIDArray().count < self.maxSimultaneousDownloadCount, let nextTargetNovelID = self.queueHolder.getNextQueue() {
            StoryHtmlDecoder.shared.WaitLoadSiteInfoReady { errorString in
                // TODO: SiteInfo の load に失敗した時用の処理が書かれていない
                if let errorString = errorString {
                    AppInformationLogger.AddLog(message: NSLocalizedString("NovelDownloadQueue_DownloadFailedByErrorSiteInfo", comment: "SiteInfo の読み込みが失敗しているようなのでダウンロードを諦めます"), appendix: ["novelID": nextTargetNovelID, "errorString": errorString], isForDebug: true)
                    self.downloadStop()
                    self.updateNetworkActivityIndicatorStatus()
                    NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
                    return
                }
                let queuedDate = Date()
                print("startDownload: \(nextTargetNovelID)")
                NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
                let (fetcherUUID, fetcher) = self.GetFreeFetcher()
                NovelDownloader.startDownload(novelID: nextTargetNovelID, fetcher: fetcher, successAction: { (novelID, downloadCount) in
                    self.queueHolder.downloadDone(novelID: nextTargetNovelID)
                    self.FreeFetcher(uuid: fetcherUUID)
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    if downloadCount > 0 {
                        self.downloadSuccessNovelIDSet.insert(nextTargetNovelID)
                    }
                    self.downloadEndedNovelIDSet.insert(nextTargetNovelID)
                    self.updateNetworkActivityIndicatorStatus()
                    NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
                    delayQueue(queuedDate: queuedDate, block: {
                        self.semaphore.signal()
                    })
                }, failedAction: { (novelID, downloadCount, errorMessage) in
                    self.queueHolder.downloadDone(novelID: nextTargetNovelID)
                    self.FreeFetcher(uuid: fetcherUUID)
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    self.downloadEndedNovelIDSet.insert(nextTargetNovelID)
                    self.updateNetworkActivityIndicatorStatus()
                    NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
                    delayQueue(queuedDate: queuedDate, block: {
                        self.semaphore.signal()
                    })
                })
            }
        }
        self.updateNetworkActivityIndicatorStatus()
        NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
    }
    
    func startQueueWatcher() {
        DispatchQueue.global(qos: .utility).async {
            while true {
                self.semaphore.wait()
                self.dispatch()
            }
        }
    }
    
    func addQueue(novelID:String) {
        NovelSpeakerUtility.CheckAndRecoverStoryCount(novelID: novelID)
        #if !os(watchOS)
        if NovelSpeakerUtility.IsRegisteredOuterNovel(novelID: novelID) {
            NovelSpeakerUtility.CheckAndUpdateRgisterdOuterNovel(novelID: novelID)
            return
        }
        #endif
        self.queueHolder.addQueue(novelID: novelID)
        self.downloadStart()
    }

    var AddQueueIsActive = false
    func addQueueArray(novelArray:ThreadSafeReference<Results<RealmNovel>>) {
        if AddQueueIsActive { return }
        AddQueueIsActive = true
        defer { AddQueueIsActive = false }
        self.downloadStop()
        self.queueHolder.addQueue(novelArray: novelArray)
        NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
        self.downloadStart()
    }
    
    func addQueueArray(novelIDArray:[String]) {
        RealmUtil.RealmBlock { realm in
            guard let novelArray = RealmNovel.SearchNovelWith(realm: realm, novelIDArray: novelIDArray) else { return }
            self.addQueueArray(novelArray: ThreadSafeReference(to: novelArray))
        }
    }
    
    func ClearAllDownloadQueue() {
        downloadStop()
        self.queueHolder.ClearAllQueue()
    }

    // ダウンロードを再開します。(semaphore.signal() を呼ぶ事で強制的に一回 queue の確認を走らせます)
    func downloadStart() {
        self.isDownloadStop = false
        semaphore.signal()
    }
    
    func downloadStop() {
        self.isDownloadStop = true
        self.queueHolder.ClearAllQueue()
    }
    
    @objc static func DownloadFlush() -> Int {
        let currentQueuedCount = NovelDownloadQueue.shared.GetCurrentQueuedNovelIDArray().count
        NovelDownloadQueue.shared.downloadStop()
        NovelDownloader.FlushAllWritePool()
        HTTPCookieSyncTool.shared.SaveSync()
        return currentQueuedCount
    }
    
    func GetCurrentDownloadingNovelIDArray() -> [String] {
        return self.queueHolder.GetCurrentDownloadingNovelIDArray()
    }
    func GetCurrentQueuedNovelIDArray() -> [String] {
        return self.queueHolder.GetCurrentQueuedNovelIDArray()
    }
    func GetCurrentDownloadStatusSummary() -> String {
        return self.queueHolder.GetCurrentDownloadStatusSummary()
    }

    #if !os(watchOS)
    // Background Process で 30秒の壁を破るの話
    // https://grandbig.github.io/blog/2019/09/22/backgroundtasks/
    let BackgroundProcessIdentifier = "com.limuraproducts.novelspeaker.backgroundprocessingtask"
    @objc func RegisterBackgroundProcess() {
        if #available(iOS 13.0, macOS 11.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: self.BackgroundProcessIdentifier, using: nil) { (task) in
                // Operation class を使ってゴニョゴニョやるのが普通っぽいけど
                // どうせ一つしかタスク走らないしコレでいいのではないかしらん……？
                guard let task = task as? BGProcessingTask else { return }
                self.scheduleBackgroundProcess()
                task.expirationHandler = {
                    NovelDownloadQueue.shared.downloadStop()
                    task.setTaskCompleted(success: false)
                }
                // ここで main thread にして DoBackgroundFetch() を呼び出さないと Timer が発火しないのでダウンロードがいつまでも回り続けてしまう
                DispatchQueue.main.async {
                    NovelDownloadQueue.shared.DoBackgroundFetch(timeoutTimeInterval: 60*5) { (successCount) in
                        task.setTaskCompleted(success: true)
                    }
                }
            }
        }
    }
    
    @objc func scheduleBackgroundProcess() {
        if #available(iOS 13.0, macOS 11.0, *) {
            if CoreDataToRealmTool.IsNeedMigration() {
                return
            }
            let isBackgroundNovelFetchEnabled = RealmUtil.RealmBlock { (realm) -> Bool in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return false }
                return globalState.isBackgroundNovelFetchEnabled
            }
            if isBackgroundNovelFetchEnabled == false { return }
            let request = BGProcessingTaskRequest(identifier: self.BackgroundProcessIdentifier)
            request.requiresNetworkConnectivity = true
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: 60*60)
            do {
                try BGTaskScheduler.shared.submit(request)
            }catch{
                print("BGTask schedule failed. \(error)")
            }
        }
    }
    #endif

    @objc func StartBackgroundFetchIfNeeded() {
        #if !os(watchOS)
        if CoreDataToRealmTool.IsNeedMigration() {
            // 起動時に background fetch を叩くのだけれど、Realm への移行が行われる段階の時は Realm object を作ってしまうとファイルができてしまうので実行させません。
            // TODO: つまり、移行が終わったら StartBackgroundFetchIfNeeded() を呼び出す必要があるのだけれどそれをやっていないはず。
            return
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            if !globalState.isBackgroundNovelFetchEnabled {
                DispatchQueue.main.async {
                    // TODO: setMinimumBackgroundFetchInterval は deprecated らしいので対応すべき(直上のscheduleBackgroundProcess辺りで実装済みなので、ビルドできなくなったらStartBackgroundFetchIfNeeded()自体を削除する感じかしらん。どうやらscheduleBackgroundProcess()はこの関数内からは呼び出してないみたいなので)
                    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
                }
                return
            }
            var hour:TimeInterval = 60*60
            if hour < UIApplication.backgroundFetchIntervalMinimum {
                hour = UIApplication.backgroundFetchIntervalMinimum
            }
            if #available(iOS 13.0, macOS 11.0, *) {
                // shceduleBackgroundProcess() は applicationDidEnterBackground 側で仕込む必要があるぽいです
                //scheduleBackgroundProcess()
            }else{
                DispatchQueue.main.async {
                    UIApplication.shared.setMinimumBackgroundFetchInterval(hour)
                }
            }
        }
        #endif
    }
    func GetCurrentDownloadCount() -> Int {
        let userDefaults = UserDefaults.standard
        userDefaults.register(defaults: [DownloadCountKey : Int(0)])
        return userDefaults.integer(forKey: DownloadCountKey)
    }
    func SetCurrentDownloadCount(count:Int) {
        UserDefaults.standard.set(count, forKey: DownloadCountKey)
        #if !os(watchOS)
        DispatchQueue.main.async {
            if count <= 0 {
                UIApplication.shared.applicationIconBadgeNumber = -1
            }else{
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
        #endif
    }
    @objc func ClearDownloadCountBadge() {
        SetCurrentDownloadCount(count: 0)
    }
    func GetAlreadyBackgroundFetchedNovelIDList() -> [String] {
        let userDefaults = UserDefaults.standard
        userDefaults.register(defaults: [AlreadyBackgroundFetchedNovelIDListKey: []])
        return userDefaults.stringArray(forKey: AlreadyBackgroundFetchedNovelIDListKey) ?? []
    }
    func AddNovelIDListToAlreadyBackgroundFetchedNovelIDList(novelIDArray:[String]) {
        var fetchedList = GetAlreadyBackgroundFetchedNovelIDList()
        for novelID in novelIDArray {
            if !fetchedList.contains(novelID) {
                fetchedList.append(novelID)
            }
        }
        UserDefaults.standard.setValue(fetchedList, forKey: AlreadyBackgroundFetchedNovelIDListKey)
    }
    func ClearAlreadyBackgroundFetchedNovelIDListKey() {
        UserDefaults.standard.setValue([] as [String], forKey: AlreadyBackgroundFetchedNovelIDListKey)
    }
    
    #if !os(watchOS)
    func DoBackgroundFetch(timeoutTimeInterval:TimeInterval, completion:((Int)->Void)?) {
        let startTime = Date()
        if GetCurrentQueuedNovelIDArray().count > 0 || StorySpeaker.shared.isPlayng {
            completion?(0)
            return
        }
        let fetchedNovelIDList = GetAlreadyBackgroundFetchedNovelIDList()
        var targetNovelIDList:[String] = []
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novelArray = RealmNovel.GetAllObjectsWith(realm: realm)?.filter("isNotNeedUpdateCheck = false") else {
                return
            }
            for novel in novelArray {
                if novel.type == .URL && !fetchedNovelIDList.contains(novel.novelID) {
                    targetNovelIDList.append(novel.novelID)
                }
            }
        }
        if targetNovelIDList.count <= 0 {
            ClearAlreadyBackgroundFetchedNovelIDListKey()
            completion?(0)
            return
        }
        
        self.downloadSuccessNovelIDSet.removeAll()
        self.downloadEndedNovelIDSet.removeAll()
        // 30秒で処理を終わらねばならないのでタイマを使います
        let deadlineTimeInterval = timeoutTimeInterval - (Date().timeIntervalSince1970 - startTime.timeIntervalSince1970)

        // バックグラウンドで動く時は並列で動作しないようにします。
        self.maxSimultaneousDownloadCount = 1
        // この処理は結構重いのでタイマの基準時間はこれよりも先にとっておきます
        self.addQueueArray(novelIDArray: targetNovelIDList)
        
        Timer.scheduledTimer(withTimeInterval: deadlineTimeInterval, repeats: false) { (timer) in
            self.downloadStop()
            // downloadStop() した後、ダウンロードが終了するまで3秒待ちます。
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false){ (timer) in
                NovelDownloader.FlushAllWritePool()
                // 並列を戻します。
                self.maxSimultaneousDownloadCount = 5
                let downloadEndedNovelIDArray = Array(self.downloadEndedNovelIDSet)
                self.AddNovelIDListToAlreadyBackgroundFetchedNovelIDList(novelIDArray: downloadEndedNovelIDArray)
                self.downloadEndedNovelIDSet.removeAll()
                HTTPCookieSyncTool.shared.Save()
                
                let novelIDArray = self.downloadSuccessNovelIDSet
                if novelIDArray.count <= 0 {
                    completion?(0)
                    return
                }
                let downloadSuccessTitle = String(format: NSLocalizedString("GlobalDataSingleton_NovelUpdateAlertBody", comment: "%d個の更新があります。"), novelIDArray.count)
                var novelTitleArray:[String] = []
                RealmUtil.RealmBlock { (realm) -> Void in
                    for novelID in novelIDArray {
                        guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { continue }
                        novelTitleArray.append(novel.title)
                    }
                }
                let displayDownloadCount = self.GetCurrentDownloadCount() + novelIDArray.count
                self.SetCurrentDownloadCount(count: displayDownloadCount)
                DispatchQueue.main.async {
                    NiftyUtility.InvokeNotificationNow(title: downloadSuccessTitle, message: novelTitleArray.joined(separator: "\n"), badgeNumber: displayDownloadCount)
                }
                completion?(novelIDArray.count)
            }
        }
    }
    
    @objc func HandleBackgroundFetch(application:UIApplication, performFetchWithCompletionHandler:@escaping (UIBackgroundFetchResult) -> Void) {
        DispatchQueue.main.async {
            self.DoBackgroundFetch(timeoutTimeInterval: self.backgroundFetchDeadlineTimeInSec) { (successCount) in
                if successCount > 0 {
                    performFetchWithCompletionHandler(.newData)
                }else{
                    performFetchWithCompletionHandler(.noData)
                }
            }
        }
    }
    #endif
}
