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
    var nowDownloading = Set<String>()
    
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
        nowDownloading.remove(hostName)
    }
    func getNextQueue() -> String? {
        var item:QueueItem = QueueItem(novelID: "", updateFrequency: 0.0)
        self.lock.lock()
        defer { self.lock.unlock() }
        for hostName in queue.keys {
            if nowDownloading.contains(hostName) {
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
        return item.novelID
    }
}

class WebDownloadQueue : NSObject {
    static let shared = WebDownloadQueue()
    let queueHolder = DownloadQueueHolder()
    
    private override init() {
        super.init()
    }
    
    
}
