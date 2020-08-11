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
import FTLinearActivityIndicator

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
    
    func addQueue(novelID:String) {
        var updateFrequencyTmp:Double? = nil
        guard novelID.count > 0 else { return }
        autoreleasepool {
            if let updateFrequency = RealmNovel.SearchNovelFrom(novelID: novelID)?.updateFrequency {
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
                a.updateFrequency < b.updateFrequency
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
    func ClearAllQueue() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.nowDownloading.removeAll()
        self.queue.removeAll()
    }
}

// 読み込みを何秒に一回にするのかの値[秒]
fileprivate var queueDelayTime = 1.5
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
            RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
            if let novel = RealmNovel.SearchNovelFrom(novelID: novelID) {
                if let lastStory = storyArray.last {
                    novel.m_lastChapterStoryID = lastStory.storyID
                    novel.lastDownloadDate = lastStory.downloadDate
                }
                if let firstStory = storyArray.first, firstStory.chapterNumber == 1 {
                    novel.m_readingChapterStoryID = firstStory.storyID
                }
                for story in storyArray {
                    novel.AppendDownloadDate(date: story.downloadDate, realm: realm)
                }
                realm.add(novel, update: .modified)
            }
        }
        storyArray.removeAll()
    }
    
    public func AddStory(story:Story) {
        lock.lock()
        storyArray.append(story)
        let storyArrayCount:Int = storyArray.count
        lock.unlock()
        let chapterNumber = story.chapterNumber
        let maxLength = RealmStoryBulk.bulkCount - ((chapterNumber - 1) % RealmStoryBulk.bulkCount)
        if NovelDownloadQueue.shared.currentDownloadingNovelCount <= 2 || storyArrayCount >= maxLength || RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID) == novelID {
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
        for (_, pool) in writePool {
            pool.Flush()
        }
    }
    
    // 指定された URL を読み込んで、内容があるようであれば指定された chapterNumber のものとして(上書き)保存します。
    // maxCount を超えておらず、次のURLが取得できたのならそのURLを chapterNumber + 1 のものとして再度 downloadOnce() を呼び出します。
    private static func downloadOnce(novelID:String, uriLoader:UriLoader, count:Int, downloadCount:Int, chapterNumber:Int, targetURL:URL, urlSecret:[String], successAction:@escaping ((_ novelID:String, _ downloadCount:Int)->Void), failedAction:@escaping ((_ novelID: String, _ downloadCount:Int, _ errorDescription:String)->Void)) {
        if isDownloadStop {
            print("NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します。novelID: \(novelID)")
            if let writePool = writePool.removeValue(forKey: novelID) {
                writePool.Flush()
            }
            successAction(novelID, downloadCount)
            return
        }
        if count > NovelDownloader.maxCount {
            print("NovelDownloader.downloadOnce(): ダウンロード回数が規定値(\(NovelDownloader.maxCount))を超えたのでダウンロードを終了します。novelID: \(novelID)")
            if let pool = writePool[novelID] { pool.Flush() }
            successAction(novelID, downloadCount)
            return
        }
        let queuedDate = Date()
        uriLoader.fetchOneUrl(
            targetURL, cookieArray: urlSecret,
            successAction: { (htmlStory) in
                autoreleasepool {
                    guard let htmlStory = htmlStory else {
                        print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: htmlStory == nil")
                        failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \(novelID))")
                        if let pool = writePool[novelID] { pool.Flush() }
                        return
                    }
                    guard let content = htmlStory.content, content.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
                        if let nextUrl = htmlStory.nextUrl {
                            print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: htmlStory.content の中身がありませんでしたが、nextUrl は取得できたのでそのまま読み込みを続けます。\(novelID)")
                            // chapterNumber は増やしませんが、施行回数は増やします
                            delayQueue(queuedDate: queuedDate, block: {
                                downloadOnce(novelID: novelID, uriLoader: uriLoader, count: count + 1, downloadCount: downloadCount, chapterNumber: chapterNumber, targetURL: nextUrl, urlSecret: urlSecret, successAction: successAction, failedAction: failedAction)
                            })
                        }else{
                            print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: htmlStory.content の中身がなく、nextUrl もありませんでしたのでここで読み込みを終了します。\(novelID)")
                            failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_FailedByNoContent", comment: "取得された小説の本文がなかったため、読み込みを終了します。") + "(novelID: \(novelID))")
                        }
                        if let pool = writePool[novelID] { pool.Flush() }
                        return
                    }
                    if RealmNovel.SearchNovelFrom(novelID: novelID) == nil {
                        print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: 読み込みには成功したのですが、RealmNovel を検索したところ存在が確認できませんでした。ダウンロード中に本棚から削除された可能性があります。ダウンロードを停止します。(\(novelID))")
                        failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_FailedByNoRealmNovel", comment: "小説が本棚に登録されていなかったため、ダウンロードを終了します。") + "(novelID: \(novelID))")
                        if let pool = writePool[novelID] { pool.Flush() }
                        return
                    }
                    var story = Story()
                    story.novelID = novelID
                    story.chapterNumber = chapterNumber
                    story.url = targetURL.absoluteString
                    story.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    story.downloadDate = queuedDate
                    if let subtitle = htmlStory.subtitle {
                        let trimedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimedSubtitle.count > 0 {
                            story.subtitle = trimedSubtitle
                        }
                    }
                    if chapterNumber == 1 {
                        //story.lastReadDate = Date(timeIntervalSince1970: 60)
                    }
                    if let pool = writePool[novelID] {
                        pool.AddStory(story: story)
                    }else{
                        let pool = StoryBulkWritePool(novelID: novelID)
                        pool.AddStory(story: story)
                        writePool[novelID] = pool
                    }
                    print("add new story to queue: \(novelID), chapterNumber: \(chapterNumber), url: \(targetURL.absoluteString)")
                    if let nextUrl = htmlStory.nextUrl {
                        delayQueue(queuedDate: queuedDate) {
                            downloadOnce(novelID: novelID, uriLoader: uriLoader, count: count + 1, downloadCount: downloadCount + 1, chapterNumber: chapterNumber + 1, targetURL: nextUrl, urlSecret: urlSecret, successAction: successAction, failedAction: failedAction)
                        }
                        return
                    }else{
                        if let pool = writePool[novelID] { pool.Flush() }
                        print("download done: \(novelID), downloadCount: \(downloadCount + 1)")
                        successAction(novelID, downloadCount + 1)
                        return
                    }
                }
            },
            failedAction: { (url, errString) in
                autoreleasepool {
                    print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.failedAction: 何らかの問題でダウンロードに失敗しました。url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown")")
                    failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown"))")
                }
        })
    }
    
    static func startDownload(novelID:String, fetcher:StoryFetcher, currentState:StoryState? = nil, chapterNumber:Int = 0, downloadCount:Int = 0, successAction:@escaping ((_ novelID:String, _ downloadCount:Int)->Void), failedAction:@escaping ((_ novelID: String, _ downloadCount:Int, _ errorDescription:String)->Void)) {
        BehaviorLogger.AddLogSimple(description: "startDownload: \(novelID), chapter: \(chapterNumber)")
        if isDownloadStop {
            if let pool = writePool[novelID] { pool.Flush() }
            print("NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, 0)
            return
        }
        if downloadCount > NovelDownloader.maxCount {
            if let pool = writePool[novelID] { pool.Flush() }
            BehaviorLogger.AddLogSimple(description: "NovelDownloader.downloadOnce(): ダウンロード回数が規定値(\(NovelDownloader.maxCount))を超えたのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, downloadCount)
            return
        }
        func failedSearchNovel(hint:String) {
            if let pool = writePool[novelID] { pool.Flush() }
            let msg = NSLocalizedString("NovelDownloader_InvalidNovelID", comment: "小説のダウンロードに失敗しました。ダウンロードするためのデータ(URL等)を取得できずにダウンロードを開始できませんでした。小説データが保存されていないか削除された等の問題がありそうです。") + "\n(novelID: \"\(novelID)\", hint: \(hint))"
            BehaviorLogger.AddLogSimple(description: msg)
            failedAction(novelID, 0, msg)
        }
        guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else {
            failedSearchNovel(hint: "SearchNovelFrom() failed.")
            return
        }
        var chapterNumber = chapterNumber
        var lastDownloadURLTmp:URL? = nil
        if chapterNumber == 0 { // 初期状態なら
            // 読み込まれている分は飛ばして最後のURLから再開
            if let lastChapter = novel.lastChapter, let lastDownloadURLString = novel.lastDownloadURL, let targetURL = URL(string: lastDownloadURLString) {
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
            state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfo(url: lastDownloadURL, cookieString: novel.urlSecretString)
        }else{
            failedSearchNovel(hint: "currentState and lastDownloadURL is nil.")
            return
        }
        fetcher.FetchNext(currentState: state, successAction: { (state) in
            guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else {
                failedSearchNovel(hint: "SearchNovel failed in FetchNext success handler")
                return
            }
            let lastChapter = novel.lastChapter
            if chapterNumber == 1 && lastChapter == nil {
                // 章が一つもダウンロードされていないようなので、
                // 恐らくは小説名なども登録されていないと思われるため、
                // このタイミングで小説名等をNovelに書き込む。
                autoreleasepool {
                    RealmUtil.Write { (realm) in
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
                    story.content = content
                    if let subtitle = state.subtitle {
                        story.subtitle = subtitle
                    }
                    story.url = state.url.absoluteString
                    story.downloadDate = queuedDate
                    // storyの書き込み自体は writePool に突っ込んで後でやってもらうことにします。
                    if let pool = writePool[novelID] {
                        pool.AddStory(story: story)
                    }else{
                        let pool = StoryBulkWritePool(novelID: novelID)
                        pool.AddStory(story: story)
                        writePool[novelID] = pool
                    }
                    print("story \(chapterNumber) add queue.")
                    nextChapterNumber += 1
                }
            }else{
                // 既に存在する章だったようなので読み飛ばします
                print("story \(chapterNumber) not add queue (maybe, no content or already exists story)")
                nextChapterNumber += 1
            }
            if !state.IsNextAlive {
                print("NovelDownloader.startDownload() IsNextAlive is false quit. \(state.url.absoluteString)")
                successAction(novelID, 0)
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
        }) { (url, errorString) in
            if let pool = writePool[novelID] { pool.Flush() }
            let msg = NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url.absoluteString), errString: \(errorString))"
            BehaviorLogger.AddLogSimple(description: msg)
            failedAction(novelID, 0, msg)
        }
    }
    
    // ダウンロードの開始点。最初の FetchOneUrl() は次の章への link の読み込みだけなので downloadOnce() に頼むだけで保存はしません。
    static func startDownload_Old(novelID:String, uriLoader:UriLoader, successAction:@escaping ((_ novelID:String, _ downloadCount:Int)->Void), failedAction:@escaping ((_ novelID: String, _ downloadCount:Int, _ errorDescription:String)->Void)) {
        if isDownloadStop {
            print("NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, 0)
            return
        }
        var urlSecret:[String] = []
        var chapterNumber = 1
        var lastDownloadURLTmp:URL? = nil
        autoreleasepool {
            guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else {
                print("NovelDownloader.startDownload(): novel \(novelID) has invalid condition. download aborted.")
                failedAction(novelID, 0, NSLocalizedString("NovelDownloader_InvalidNovelID", comment: "小説のダウンロードに失敗しました。ダウンロードするためのデータ(URL等)を取得できずにダウンロードを開始できませんでした。小説データが保存されていないか削除された等の問題がありそうです。") + "(novelID: \"\(novelID)\")")
                return
            }
            urlSecret = novel.urlSecret
            autoreleasepool {
                if let lastChapter = novel.lastChapter, let lastDownloadURLString = novel.lastDownloadURL, let targetURL = URL(string: lastDownloadURLString) {
                    chapterNumber = lastChapter.chapterNumber
                    lastDownloadURLTmp = targetURL
                }else if let targetURL = URL(string: novelID) {
                    chapterNumber = 1
                    lastDownloadURLTmp = targetURL
                }else{
                    print("NovelDownloader.startDownload(): novel \(novelID) has invalid condition. download aborted.")
                    failedAction(novelID, 0, NSLocalizedString("NovelDownloader_InvalidNovelID", comment: "小説のダウンロードに失敗しました。ダウンロードするためのデータ(URL等)を取得できずにダウンロードを開始できませんでした。小説データが保存されていないか削除された等の問題がありそうです。") + "(novelID: \"\(novelID)\")")
                    return
                }
            }
        }
        guard let lastDownloadURL = lastDownloadURLTmp else { return }
        let queuedDate = Date()
        uriLoader.fetchOneUrl(
            lastDownloadURL,
            cookieArray: urlSecret,
            successAction: { (htmlStory) in
                autoreleasepool {
                    guard let htmlStory = htmlStory, let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else {
                        print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.successAction: htmlStory is nil.")
                        failedAction(novelID, 0, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\")")
                        return
                    }
                    let targetURL:URL
                    if chapterNumber == 1 && novel.lastChapter == nil {
                        // 章がダウンロードされていないのでここで書き込んでしまう。
                        RealmUtil.Write { (realm) in
                            if let title = htmlStory.title, novel.title.count <= 0 {
                                novel.title = title
                            }
                            if let author = htmlStory.author, novel.writer.count <= 0 {
                                novel.writer = author
                            }
                            realm.add(novel, update: .modified)
                            if let keywords = htmlStory.keyword {
                                for keyword in keywords {
                                    guard let keyword = keyword as? String else { continue }
                                    RealmNovelTag.AddTag(realm: realm, name: keyword, novelID: novelID, type: RealmNovelTag.TagType.Keyword)
                                }
                            }
                        }
                        if let firstPage = htmlStory.firstPageLink {
                            // 最初の章へのlinkがあった。downloadOnce() に頑張ってもらう。
                            targetURL = firstPage
                            chapterNumber = 0 // あとで +1 して downloadOnce() が呼ばれるので。
                        }else{
                            let storyID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 1)
                            var story = Story()
                            story.novelID = novelID
                            story.chapterNumber = 1
                            story.content = (htmlStory.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            story.subtitle = (htmlStory.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            story.url = lastDownloadURL.absoluteString
                            RealmUtil.Write { (realm) in
                                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                                print("\(storyID) saved.")
                                novel.m_lastChapterStoryID = storyID
                                novel.lastDownloadDate = queuedDate
                                novel.m_readingChapterStoryID = storyID
                                novel.AppendDownloadDate(date: queuedDate, realm: realm)
                                realm.add(novel, update: .modified)
                            }
                            if let url = htmlStory.nextUrl {
                                targetURL = url
                            }else{
                                print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.successAction: nextUrl is nil. \(lastDownloadURL.absoluteString)")
                                successAction(novelID, 0)
                                return
                            }
                        }
                    }else{
                        guard let url = htmlStory.nextUrl, url.absoluteString != lastDownloadURL.absoluteString else {
                            print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.successAction: nextUrl is nil or same URL. \(lastDownloadURL.absoluteString)")
                            successAction(novelID, 0)
                            return
                        }
                        targetURL = url
                    }
                    delayQueue(queuedDate: queuedDate, block: {
                        downloadOnce(novelID: novelID, uriLoader: uriLoader, count: 0, downloadCount: 0, chapterNumber: chapterNumber + 1, targetURL: targetURL, urlSecret: urlSecret, successAction: successAction, failedAction: failedAction)
                    })
                }
            },
            failedAction: { (url, errString) in
                autoreleasepool {
                    print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.failedAction: 何らかの問題でダウンロードに失敗しました。url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown")")
                    failedAction(novelID, 0, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown"))")
                }
        })
    }
}

class NovelDownloadQueue : NSObject {
    @objc static let shared = NovelDownloadQueue()
    private let queueHolder = DownloadQueueHolder()
    var maxSimultaneousDownloadCount = 5
    let lock = NSLock()
    var downloadSuccessNovelIDSet = Set<String>()
    var downloadEndedNovelIDSet = Set<String>()
    public var isDownloadStop = true
    let semaphore = DispatchSemaphore(value: 0)
    
    let cacheFileExpireTimeinterval:Double = 60*60*6
    let novelSpeakerSiteInfoUrl = "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1/items.json"
    let novelSpeakerSiteInfoCacheFileName = "NovelSpeakerSiteInfoCache"
    let autopagerizeSiteInfoUrl = "http://wedata.net/databases/AutoPagerize/items.json"
    let autopagerizeSiteInfoCacheFileName = "AutopagerizeSiteInfoCache"
    let DownloadCountKey = "NovelDownloadQueue_DownloadCount"
    let AlreadyBackgroundFetchedNovelIDListKey = "NovelDownloadQueue_AlreadyBackgroundFetchedNovelIDList"
    let backgroundFetchDeadlineTimeInSec:Double = 20.0
    var tmpUriLoader:UriLoader? = nil
    let fetcherPoolLock = NSLock()
    var fetcherPool:[UUID:(Bool, StoryFetcher)] = [:]
    var siteInfoLoadDate:Date = Date(timeIntervalSince1970: 0)
    let siteInfoReloadTimeinterval:Double = 60*60*6

    private override init() {
        super.init()
        startQueueWatcher()
    }
    
    func reloadSiteInfoIfNeeded() {
        // SiteInfo を読み出そうとすると Realm object を生成してしまうため、
        // CoreDataからのマイグレーションが必要な場合は何もしない事にします。
        if CoreDataToRealmTool.IsNeedMigration() { return }
        let semaphore = DispatchSemaphore(value: 0)
        let expireDate = Date(timeIntervalSinceNow: -siteInfoReloadTimeinterval)
        if expireDate > siteInfoLoadDate || RealmGlobalState.GetInstance()?.isForceSiteInfoReloadIsEnabled ?? false {
            StoryHtmlDecoder.shared.ClearSiteInfo()
            StoryHtmlDecoder.shared.LoadSiteInfo { (err) in
                if let err = err {
                    print("reloadSiteInfoIfNeeded LoadSiteInfo failed.", err.localizedDescription)
                }
                semaphore.signal()
            }
            siteInfoLoadDate = Date()
            semaphore.wait()
        }
    }
    
    func clearSiteInfoCache() {
        NiftyUtilitySwift.FileCachedHttpGet_RemoveCacheFile(cacheFileName: novelSpeakerSiteInfoCacheFileName)
        NiftyUtilitySwift.FileCachedHttpGet_RemoveCacheFile(cacheFileName: autopagerizeSiteInfoCacheFileName)
        tmpUriLoader = nil
    }
    
    func createUriLoader() -> UriLoader {
        return autoreleasepool {
            let newUriLoader = UriLoader()
            let semaphore = DispatchSemaphore(value: 0)
            var cacheExpireTimeinterval:Double = 0
            autoreleasepool {
                if let instance = RealmGlobalState.GetInstance(), instance.isForceSiteInfoReloadIsEnabled {
                    cacheExpireTimeinterval = 0
                }else{
                    cacheExpireTimeinterval = cacheFileExpireTimeinterval
                }
            }
            var novelSpeakerSiteInfoData:Data? = nil
            var autopagerizeSiteInfoData:Data? = nil
            if let url = URL(string: novelSpeakerSiteInfoUrl) {
                NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: novelSpeakerSiteInfoCacheFileName, expireTimeinterval: cacheExpireTimeinterval, successAction: { (data) in
                    novelSpeakerSiteInfoData = data
                    semaphore.signal()
                }) { (err) in
                    semaphore.signal()
                }
            }
            if let url = URL(string: autopagerizeSiteInfoUrl) {
                NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: autopagerizeSiteInfoCacheFileName, expireTimeinterval: cacheExpireTimeinterval, successAction: { (data) in
                    autopagerizeSiteInfoData = data
                    semaphore.signal()
                }) { (err) in
                    semaphore.signal()
                }
            }
            semaphore.wait() // for novelSpeakerCacheData
            semaphore.wait() // for autopagerizeCacheData
            if let data = novelSpeakerSiteInfoData {
                newUriLoader.addCustomSiteInfo(from: data)
            }
            if let data = autopagerizeSiteInfoData {
                newUriLoader.addSiteInfo(from: data)
            }
            print("UriLoader has SiteInfo: \(newUriLoader.holdSiteInfoCont())")
            return newUriLoader
        }
    }
    
    func updateNetworkActivityIndicatorStatus(){
        let activityIndicatorID = "NovelDownloadQueue"
        DispatchQueue.main.async {
            if self.queueHolder.GetCurrentDownloadingNovelIDArray().count > 0 {
                ActivityIndicatorManager.enable(id: activityIndicatorID)
            }else{
                ActivityIndicatorManager.disable(id: activityIndicatorID)
            }
        }
    }
    
    var currentDownloadingNovelCount:Int {
        get {
            return self.queueHolder.GetCurrentDownloadingNovelIDArray().count
        }
    }
    
    func GetFreeFetcher() -> (UUID, StoryFetcher) {
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
        let uuid = UUID()
        let fetcher = StoryFetcher()
        fetcherPool[uuid] = (true, fetcher)
        return (uuid, fetcher)
    }
    func FreeFetcher(uuid:UUID) {
        fetcherPoolLock.lock()
        defer { fetcherPoolLock.unlock() }
        if let (_, fetcher) = fetcherPool[uuid] {
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
            StoryHtmlDecoder.shared.WaitLoadSiteInfoReady {
                autoreleasepool {
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
        }
        self.updateNetworkActivityIndicatorStatus()
        NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
    }
    
    func startQueueWatcher() {
        DispatchQueue.global(qos: .utility).async {
            while true {
                self.reloadSiteInfoIfNeeded()
                self.semaphore.wait()
                self.dispatch()
            }
        }
    }
    
    func addQueue(novelID:String) {
        NovelSpeakerUtility.CheckAndRecoverStoryCount(novelID: novelID)
        self.queueHolder.addQueue(novelID: novelID)
        self.isDownloadStop = false
        semaphore.signal()
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
    }
    
    @objc static func DownloadFlush() {
        NovelDownloadQueue.shared.downloadStop()
        NovelDownloader.FlushAllWritePool()
    }
    
    func GetCurrentDownloadingNovelIDArray() -> [String] {
        return self.queueHolder.GetCurrentDownloadingNovelIDArray()
    }
    func GetCurrentQueuedNovelIDArray() -> [String] {
        return self.queueHolder.GetCurrentQueuedNovelIDArray()
    }

    @objc func StartBackgroundFetchIfNeeded() {
        autoreleasepool {
            if CoreDataToRealmTool.IsNeedMigration() {
                // 起動時に background fetch を叩くのだけれど、Realm への移行が行われる段階の時は Realm object を作ってしまうとファイルができてしまうので実行させません。
                // TODO: つまり、移行が終わったら StartBackgroundFetchIfNeeded() を呼び出す必要があるのだけれどそれをやっていないはず。
                return
            }
            guard let globalState = RealmGlobalState.GetInstance() else { return }
            if !globalState.isBackgroundNovelFetchEnabled {
                DispatchQueue.main.async {
                    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalNever)
                }
                return
            }
            var hour:TimeInterval = 60*60
            if hour < UIApplication.backgroundFetchIntervalMinimum {
                hour = UIApplication.backgroundFetchIntervalMinimum
            }
            DispatchQueue.main.async {
                UIApplication.shared.setMinimumBackgroundFetchInterval(hour)
            }
        }
    }
    func GetCurrentDownloadCount() -> Int {
        let userDefaults = UserDefaults.standard
        userDefaults.register(defaults: [DownloadCountKey : Int(0)])
        return userDefaults.integer(forKey: DownloadCountKey)
    }
    func SetCurrentDownloadCount(count:Int) {
        UserDefaults.standard.set(count, forKey: DownloadCountKey)
        DispatchQueue.main.async {
            if count <= 0 {
                UIApplication.shared.applicationIconBadgeNumber = -1
            }else{
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
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
    
    @objc func HandleBackgroundFetch(application:UIApplication, performFetchWithCompletionHandler:@escaping (UIBackgroundFetchResult) -> Void) {
        let startTime = Date()
        if GetCurrentQueuedNovelIDArray().count > 0 || StorySpeaker.shared.isPlayng {
            performFetchWithCompletionHandler(.noData)
            return
        }
        let fetchedNovelIDList = GetAlreadyBackgroundFetchedNovelIDList()
        var targetNovelIDList:[String] = []
        autoreleasepool {
            guard let novelArray = RealmNovel.GetAllObjects() else {
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
            performFetchWithCompletionHandler(.noData)
            return
        }
        
        self.downloadSuccessNovelIDSet.removeAll()
        self.downloadEndedNovelIDSet.removeAll()
        // 一旦ダウンロードを止めて、queueにリストを全部入れてから再開させることで、更新頻度の高いものから順にダウンロードさせます
        self.isDownloadStop = true
        for novelID in targetNovelIDList {
            addQueue(novelID: novelID)
        }
        self.isDownloadStop = false
        self.downloadStart()
        
        // 30秒で処理を終わらねばならないのでタイマを使います
        let deadlineTimeInterval = backgroundFetchDeadlineTimeInSec - (Date().timeIntervalSince1970 - startTime.timeIntervalSince1970)
        Timer.scheduledTimer(withTimeInterval: deadlineTimeInterval, repeats: false) { (timer) in
            self.downloadStop()
            // downloadStop() した後、ダウンロードが終了するまで9秒待ちます。
            Timer.scheduledTimer(withTimeInterval: 9.0, repeats: false){ (timer) in
                let downloadEndedNovelIDArray = Array(self.downloadEndedNovelIDSet)
                self.AddNovelIDListToAlreadyBackgroundFetchedNovelIDList(novelIDArray: downloadEndedNovelIDArray)
                self.downloadEndedNovelIDSet.removeAll()
                
                let novelIDArray = self.downloadSuccessNovelIDSet
                if novelIDArray.count <= 0 {
                    performFetchWithCompletionHandler(.noData)
                    return
                }
                let downloadSuccessTitle = String(format: NSLocalizedString("GlobalDataSingleton_NovelUpdateAlertBody", comment: "%d個の更新があります。"), novelIDArray.count)
                var novelTitleArray:[String] = []
                for novelID in novelIDArray {
                    autoreleasepool {
                        guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else { return }
                        novelTitleArray.append(novel.title)
                    }
                }
                let displayDownloadCount = self.GetCurrentDownloadCount() + novelIDArray.count
                self.SetCurrentDownloadCount(count: displayDownloadCount)
                DispatchQueue.main.async {
                    NiftyUtility.invokeNotificationNow(downloadSuccessTitle, message: novelTitleArray.joined(separator: "\n"), badgeNumber: displayDownloadCount)
                }
                performFetchWithCompletionHandler(.newData)
            }
        }
    }

}
