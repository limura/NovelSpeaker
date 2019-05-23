//
//  DownloadQueueHolder.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/22.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

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
        guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        let item = QueueItem(novelID: novelID, updateFrequency: novel.updateFrequency)
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
        var item:QueueItem = QueueItem(novelID: "", updateFrequency: 0.0)
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
}

// 一つの小説をダウンロードしようとします。
// startDownload() を呼び出す事でダウンロードを開始します。
// ダウンロードが正常に終了したら successAction を、何らかの問題で失敗終了したら failedAction が呼び出されます。
// 注意：小説と最初の章が登録されている必要があります。つまり、続きの章のダウンロード用の物になります。
class NovelDownloader : NSObject {
    // 一度にダウンロードされる章の最大数
    static var maxCount = 1000
    // ダウンロードを止めたい時に true を入れます。
    static var isDownloadStop = false
    // 読み込みを何秒に一回にするのかの値[秒]
    static var queueDelayTime = 1.5
    
    private static func delayQueue(queuedDate: Date, block:@escaping ()->Void) {
        let now = Date()
        let diffTime = queuedDate.timeIntervalSince1970 - now.timeIntervalSince1970 + queueDelayTime
        if diffTime < 0 {
            block()
        }else{
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + diffTime) {
                block()
            }
        }
    }
    
    // 指定された URL を読み込んで、内容があるようであれば指定された chapterNumber のものとして(上書き)保存します。
    // maxCount を超えておらず、次のURLが取得できたのならそのURLを chapterNumber + 1 のものとして再度 downloadOnce() を呼び出します。
    private static func downloadOnce(novelID:String, uriLoader:UriLoader, count:Int, downloadCount:Int, chapterNumber:Int, targetURL:URL, urlSecret:[String], successAction:@escaping ((_ novelID:String, _ downloadCount:Int)->Void), failedAction:@escaping ((_ novelID: String, _ downloadCount:Int, _ errorDescription:String)->Void)) {
        if isDownloadStop {
            print("NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, downloadCount)
            return
        }
        if count > NovelDownloader.maxCount {
            print("NovelDownloader.downloadOnce(): ダウンロード回数が規定値(\(NovelDownloader.maxCount))を超えたのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, downloadCount)
            return
        }
        let queuedDate = Date()
        uriLoader.fetchOneUrl(
            targetURL, cookieArray: urlSecret,
            successAction: { (htmlStory) in
                guard let htmlStory = htmlStory else {
                    print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: htmlStory == nil")
                    failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \(novelID))")
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
                    return
                }
                guard RealmNovel.SearchNovelFrom(novelID: novelID) != nil else {
                    print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: 読み込みには成功したのですが、RealmNovel を検索したところ存在が確認できませんでした。ダウンロード中に本棚から削除された可能性があります。ダウンロードを停止します。(\(novelID))")
                    failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_FailedByNoRealmNovel", comment: "小説が本棚に登録されていなかったため、ダウンロードを終了します。") + "(novelID: \(novelID))")
                    return
                }
                let story = RealmStory.CreateNewStory(novelID: novelID, chapterNumber: chapterNumber)
                story.url = targetURL.absoluteString
                story.content = content
                story.downloadDate = queuedDate
                // 新しく読み込まれた小説の最後に読んだ時間を過去にしておかないと、それが最後の読んだ小説にされてしまう。
                story.lastReadDate = Date(timeIntervalSince1970: 0)
                if let subtitle = htmlStory.subtitle {
                    story.subtitle = subtitle
                }
                RealmUtil.Write(block: { (realm) in
                    /* // 通常の更新時にはタグの更新はしないでおきます
                     if let keywordArray = htmlStory.keyword {
                     for keyword in keywordArray {
                     guard let keyword = keyword as? String else { continue }
                     RealmNovelTag.AddTag(tagName: keyword, novelID: novelID, type: "keyword")
                     }
                     }
                     */
                    realm.add(story, update: true)
                })
                if let nextUrl = htmlStory.nextUrl {
                    delayQueue(queuedDate: queuedDate, block: {
                        downloadOnce(novelID: novelID, uriLoader: uriLoader, count: count + 1, downloadCount: downloadCount + 1, chapterNumber: chapterNumber + 1, targetURL: nextUrl, urlSecret: urlSecret, successAction: successAction, failedAction: failedAction)
                    })
                    return
                }else{
                    successAction(novelID, downloadCount + 1)
                    return
                }
            },
            failedAction: { (url, errString) in
                print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.failedAction: 何らかの問題でダウンロードに失敗しました。url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown")")
                failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown"))")
        })
    }
    
    // ダウンロードの開始点。最初の FetchOneUrl() は次の章への link の読み込みだけなので downloadOnce() に頼むだけで保存はしません。
    static func startDownload(novelID:String, uriLoader:UriLoader, successAction:@escaping ((_ novelID:String, _ downloadCount:Int)->Void), failedAction:@escaping ((_ novelID: String, _ downloadCount:Int, _ errorDescription:String)->Void)) {
        if isDownloadStop {
            print("NovelDownloader.downloadOnce(): isDownloadStop が true であったのでダウンロードを終了します。novelID: \(novelID)")
            successAction(novelID, 0)
            return
        }
        guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID), let lastChapter = novel.lastChapter, let lastDownloadURLString = novel.lastDownloadURL, let lastDownloadURL = URL(string: lastDownloadURLString) else {
            print("NovelDownloader.startDownload(): novel \(novelID) has invalid condition. download aborted.")
         failedAction(novelID, 0, NSLocalizedString("NovelDownloader_InvalidNovelID", comment: "小説のダウンロードに失敗しました。ダウンロードするためのデータ(URL等)を取得できずにダウンロードを開始できませんでした。小説データが保存されていないか削除された等の問題がありそうです。") + "(novelID: \"\(novelID)\")")
            return
        }
        let urlSecret = novel.urlSecret
        let chapterNumber = lastChapter.chapterNumber
        let queuedDate = Date()
        uriLoader.fetchOneUrl(
            lastDownloadURL,
            cookieArray: novel.urlSecret,
            successAction: { (htmlStory) in
                guard let htmlStory = htmlStory else {
                    print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.successAction: htmlStory is nil.")
                    failedAction(novelID, 0, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\")")
                    return
                }
                guard let targetURL = htmlStory.nextUrl, targetURL.absoluteString != lastDownloadURL.absoluteString else {
                    print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.successAction: nextUrl is nil or same URL. \(lastDownloadURL.absoluteString)")
                    successAction(novelID, 0)
                    return
                }
                delayQueue(queuedDate: queuedDate, block: {
                    downloadOnce(novelID: novelID, uriLoader: uriLoader, count: 0, downloadCount: 0, chapterNumber: chapterNumber + 1, targetURL: targetURL, urlSecret: urlSecret, successAction: successAction, failedAction: failedAction)
                })
            },
            failedAction: { (url, errString) in
                print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.failedAction: 何らかの問題でダウンロードに失敗しました。url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown")")
                failedAction(novelID, 0, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown"))")
        })
    }
}

class NovelDownloadQueue : NSObject {
    static let shared = NovelDownloadQueue()
    private let queueHolder = DownloadQueueHolder()
    var maxSimultaneousDownloadCount = 5
    let lock = NSLock()
    var downloadSuccessNovelIDArray:[String] = []
    private var isDownloadStop = true
    let semaphore = DispatchSemaphore(value: 0)
    
    let cacheFileExpireTimeinterval:Double = 60*60*24
    let novelSpeakerSiteInfoUrl = "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1/items.json"
    let novelSpeakerSiteInfoCacheFileName = "NovelSpeakerSiteInfoCache"
    let autopagerizeSiteInfoUrl = "http://wedata.net/databases/AutoPagerize/items.json"
    let autopagerizeSiteInfoCacheFileName = "AutopagerizeSiteInfoCache"
    
    private override init() {
        super.init()
        startQueueWatcher()
    }
    
    func createUriLoader() -> UriLoader {
        let newUriLoader = UriLoader()
        let semaphore = DispatchSemaphore(value: 0)
        var novelSpeakerSiteInfoData:Data? = nil
        var autopagerizeSiteInfoData:Data? = nil
        if let url = URL(string: novelSpeakerSiteInfoUrl) {
            NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: novelSpeakerSiteInfoCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: { (data) in
                novelSpeakerSiteInfoData = data
                semaphore.signal()
            }) { (err) in
                semaphore.signal()
            }
        }
        if let url = URL(string: autopagerizeSiteInfoUrl) {
            NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: autopagerizeSiteInfoCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: { (data) in
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
        return newUriLoader
    }
    
    func updateNetworkActivityIndicatorStatus(){
        DispatchQueue.main.async {
            if self.queueHolder.GetCurrentDownloadingNovelIDArray().count > 0 {
                UIApplication.shared.isNetworkActivityIndicatorVisible = true
            }else{
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
        }
    }
    
    func startQueueWatcher() {
        DispatchQueue.global(qos: .utility).async {
            while true {
                self.semaphore.wait()
                var tmpUriLoader:UriLoader? = nil
                while self.isDownloadStop == false, self.queueHolder.GetCurrentDownloadingNovelIDArray().count < self.maxSimultaneousDownloadCount, let nextTargetNovelID = self.queueHolder.getNextQueue() {
                    autoreleasepool {
                        let uriLoader:UriLoader
                        if tmpUriLoader != nil {
                            uriLoader = tmpUriLoader!
                        }else{
                            uriLoader = self.createUriLoader()
                            tmpUriLoader = uriLoader
                        }
                        print("startDownload: \(nextTargetNovelID)")
                        NovelDownloader.startDownload(novelID: nextTargetNovelID, uriLoader: uriLoader, successAction: { (novelID, downloadCount) in
                            self.queueHolder.downloadDone(novelID: nextTargetNovelID)
                            self.lock.lock()
                            defer { self.lock.unlock() }
                            self.downloadSuccessNovelIDArray.append(nextTargetNovelID)
                            self.updateNetworkActivityIndicatorStatus()
                            NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
                            self.semaphore.signal()
                        }, failedAction: { (novelID, downloadCount, errorMessage) in
                            self.queueHolder.downloadDone(novelID: nextTargetNovelID)
                            self.updateNetworkActivityIndicatorStatus()
                            NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
                            self.semaphore.signal()
                        })
                    }
                }
                self.updateNetworkActivityIndicatorStatus()
                NovelSpeakerNotificationTool.AnnounceDownloadStatusChanged()
            }
        }
    }
    
    func addQueue(novelID:String) {
        self.queueHolder.addQueue(novelID: novelID)
        self.isDownloadStop = false
        semaphore.signal()
    }

    // ダウンロードを再開します。(semaphore.signal() を呼ぶ事で強制的に一回 queue の確認を走らせます)
    func downloadStart() {
        self.isDownloadStop = false
        semaphore.signal()
    }
    
    func downloadStop() {
        self.isDownloadStop = true
    }
    
    func GetCurrentDownloadingNovelIDArray() -> [String] {
        return self.queueHolder.GetCurrentDownloadingNovelIDArray()
    }
    func GetCurrentQueuedNovelIDArray() -> [String] {
        return self.queueHolder.GetCurrentQueuedNovelIDArray()
    }
}
