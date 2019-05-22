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
                guard let content = htmlStory.content, content.count > 0 else {
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
                guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else {
                    print("NovelDownloader.downloadOnce().urlLoader.fetchOneUrl.successAction: 小説の読み込みには成功しましたが、RealmNovel 自体が存在しなくなっていたので読み込みを終了します。\(novelID)")
                    failedAction(novelID, downloadCount, NSLocalizedString("NovelDownloader_FailedByNoRealmNovel", comment: "小説が本棚に登録されていなかったため、ダウンロードを終了します。") + "(novelID: \(novelID))")
                    return
                }
                let story = RealmStory.CreateNewStory(novel: novel, chapterNumber: chapterNumber)
                story.url = targetURL.absoluteString
                story.content = content
                story.downloadDate = queuedDate
                if let subtitle = htmlStory.subtitle {
                    story.subtitle = subtitle
                }
                if let realm = try? RealmUtil.GetRealm() {
                    try! realm.write {
                        /* // 通常の更新時にはタグの更新はしないでおきます
                        if let keywordArray = htmlStory.keyword {
                            for keyword in keywordArray {
                                guard let keyword = keyword as? String else { continue }
                                RealmNovelTag.AddTag(tagName: keyword, novelID: novelID, type: "keyword")
                            }
                        }
                         */
                        realm.add(story, update: true)
                    }
                }
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
                    downloadOnce(novelID: novelID, uriLoader: uriLoader, count: 0, downloadCount: 0, chapterNumber: lastChapter.chapterNumber + 1, targetURL: targetURL, urlSecret: novel.urlSecret, successAction: successAction, failedAction: failedAction)
                })
            },
            failedAction: { (url, errString) in
                print("NovelDownloader.startDownload().urlLoader.fetchOneUrl.failedAction: 何らかの問題でダウンロードに失敗しました。url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown")")
                failedAction(novelID, 0, NSLocalizedString("NovelDownloader_htmlStoryIsNil", comment: "小説のダウンロードに失敗しました。") + "(novelID: \"\(novelID)\", url: \(url?.absoluteString ?? "unknown"), errString: \(errString ?? "unknown"))")
        })
    }
}

class WebDownloadQueue : NSObject {
    static let shared = WebDownloadQueue()
    let queueHolder = DownloadQueueHolder()
    
    private override init() {
        super.init()
    }
    
    
}
