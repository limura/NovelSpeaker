//
//  BookShelfTreeViewCell.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/18.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class BookShelfTreeViewCell: UITableViewCell {
    public static let id = "BookShelfTreeViewCell"
    final let depthWidth:Float = 32.0
    
    @IBOutlet weak var treeDepthImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var downloadingActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var newImageView: UIImageView!
    @IBOutlet weak var readProgressView: UIProgressView!
    @IBOutlet weak var treeDepthImageViewWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var likeButton: UIButton!
    
    var storyObserveToken: NotificationToken? = nil
    var storyForNovelArrayObserveToken: NotificationToken? = nil
    var globalStateObserveToken: NotificationToken? = nil
    var novelObserveToken: NotificationToken? = nil
    var novelArrayObserveToken: NotificationToken? = nil
    var bookmarkObserveToken: NotificationToken? = nil
    var watchNovelIDArray:[String] = []
    
    static let staticRealmQueue:DispatchQueue? = DispatchQueue(label: "NovelSpeakerBookShelfTableCellQueue")
    let realmQueue:DispatchQueue? = BookShelfTreeViewCell.staticRealmQueue
    
    deinit {
        self.unregistDownloadStatusNotification()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        registerDownloadStatusNotification()

        likeButton.imageView?.contentMode = .scaleAspectFit
        likeButton.contentHorizontalAlignment = .fill
        likeButton.contentVerticalAlignment = .fill
        downloadingActivityIndicator.isHidden = true
    }
    
    func unregistAllObserver() {
        storyObserveToken = nil
        storyForNovelArrayObserveToken = nil
        globalStateObserveToken = nil
        novelObserveToken = nil
        novelArrayObserveToken = nil
        bookmarkObserveToken = nil
    }
    func cleanCellDisplay() {
        likeButton.imageView?.contentMode = .scaleAspectFit
        likeButton.contentHorizontalAlignment = .fill
        likeButton.contentVerticalAlignment = .fill
        likeButton.imageView?.image = UIImage(named: "NotLikeStar.png")
        downloadingActivityIndicator.isHidden = true
        newImageView.isHidden = true
        readProgressView.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        unregistAllObserver()
        cleanCellDisplay()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func activateNewImageView() {
        DispatchQueue.main.async {
            if self.newImageView.isHidden {
                self.newImageView.isHidden = false
            }
        }
    }
    func deactivateNewImageView() {
        DispatchQueue.main.async {
            if !self.newImageView.isHidden {
                self.newImageView.isHidden = true
            }
        }
    }
    func applyDepth(treeLevel:Int) {
        let depthWidth = CGFloat(self.depthWidth * Float(treeLevel))
        self.treeDepthImageView.removeConstraint(self.treeDepthImageViewWidthConstraint)
        self.treeDepthImageViewWidthConstraint = self.treeDepthImageView.widthAnchor.constraint(equalToConstant: depthWidth)
        self.treeDepthImageViewWidthConstraint.isActive = true
    }
    func applyCurrentReadingPointToIndicator(novelID:String) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID), let readingChapterNumber = novel.readingChapterNumber else {
                DispatchQueue.main.async {
                    self.readProgressView.progress = 0.0
                }
                return
            }
            let lastChapterNumber = novel.lastChapterNumber ?? 1
            let readLocation:Float
            let contentCount:Float
            if lastChapterNumber == readingChapterNumber, let lastChapter = novel.lastChapterWith(realm: realm) {
                readLocation = Float(lastChapter.readLocation(realm: realm))
                contentCount = Float(lastChapter.content.count)
            }else{
                readLocation = 1.0
                contentCount = 1.0
            }
            let progress = ((Float(readingChapterNumber) - 1.0) + readLocation / contentCount) / Float(lastChapterNumber)
            if self.watchNovelIDArray != [novelID] { return }
            DispatchQueue.main.async {
                if readingChapterNumber == lastChapterNumber && contentCount <= (readLocation + 10) {
                    self.readProgressView.tintColor = UIColor(displayP3Red: 0.6, green: 0.3, blue: 0.9, alpha: 1.0)
                }else{
                    self.readProgressView.tintColor = UIColor(displayP3Red: 255/256.0, green: 188/256.0, blue: 2/256.0, alpha: 1.0)
                }
                self.readProgressView.progress = progress
            }
        }
    }
    func applyCurrentDownloadIndicatorVisibleStatus(novelIDArray:[String]) {
        let downloadQueued = NovelDownloadQueue.shared.GetCurrentQueuedNovelIDArray()
        let nowDownloading = NovelDownloadQueue.shared.GetCurrentDownloadingNovelIDArray()

        var isQueued = false
        var isNowDownloading = false
        for novelID in novelIDArray {
            if downloadQueued.contains(novelID) {
                isQueued = true
            }
            if nowDownloading.contains(novelID) {
                isNowDownloading = true
            }
        }

        DispatchQueue.main.async {
            var isModeChanged = false
            if isQueued || isNowDownloading {
                if self.downloadingActivityIndicator.isHidden {
                    self.downloadingActivityIndicator.isHidden = false
                    isModeChanged = true
                }
            }else{
                if !self.downloadingActivityIndicator.isHidden {
                    self.downloadingActivityIndicator.isHidden = true
                    isModeChanged = true
                }
            }
            if isNowDownloading {
                if !self.downloadingActivityIndicator.isAnimating {
                    self.downloadingActivityIndicator.startAnimating()
                    isModeChanged = true
                }
            }else{
                if self.downloadingActivityIndicator.isAnimating {
                    self.downloadingActivityIndicator.stopAnimating()
                    isModeChanged = true
                }
            }
            if isModeChanged {
                self.downloadingActivityIndicator.layoutIfNeeded()
            }
        }
    }
    
    func applyLikeStarStatus(novelID:String) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else {
                DispatchQueue.main.async {
                    self.likeButton.isHidden = true
                }
                return
            }
            if self.watchNovelIDArray.count != 1 {
                return
            }
            if let currentNovelID = self.watchNovelIDArray.first, currentNovelID != novelID {
                return
            }
            let likeLevel = novel.likeLevel
            DispatchQueue.main.async {
                if likeLevel > 0 {
                    self.likeButton.imageView?.image = UIImage(named: "LikeStar.png")
                }else{
                    self.likeButton.imageView?.image = UIImage(named: "NotLikeStar.png")
                }
            }
        }
    }
    
    func registerNovelArrayObserver(novelIDArray:[String]) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            self.novelArrayObserveToken = RealmNovel.SearchNovelWith(realm: realm, novelIDArray: novelIDArray)?.observe({ (change) in
                switch change {
                case .error(_):
                    break
                case .update(_, let deleteIndexArray, let insertionIndexArray, let modificationIndexArray):
                    if deleteIndexArray.count > 0 || insertionIndexArray.count > 0 || modificationIndexArray.count > 0 {
                        self.checkAndUpdateNewImage(novelIDArray: novelIDArray)
                    }
                case .initial(_):
                    break
                }
            })
        }
    }
    
    func registerNovelObserver(novelID:String) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            self.novelObserveToken = novel.observe { (change) in
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        if property.name == "likeLevel" {
                            self.applyLikeStarStatus(novelID: novelID)
                        }
                        if property.name == "m_readingChapterStoryID" {
                            self.applyCurrentReadingPointToIndicator(novelID: novelID)
                        }
                        if property.name == "lastDownloadDate" || property.name == "lastReadDate" {
                            self.checkAndUpdateNewImage(novelIDArray: [novelID])
                        }
                        if property.name == "title", let newTitle = property.newValue as? String, newTitle.count > 0 {
                            DispatchQueue.main.async {
                                self.titleLabel.text = newTitle
                            }
                        }
                    }
                case .deleted:
                    break
                }
            }
        }
    }

    func registerStoryObserver(novelID:String) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            self.storyObserveToken = RealmStoryBulk.GetAllObjectsWith(realm: realm)?.filter("novelID = %@", novelID).observe({ (change) in
                switch (change) {
                case .initial(_):
                    break
                case .update(_, _, let insertions, _):
                    // 「更新有」の反映
                    if insertions.count > 0 {
                        self.activateNewImageView()
                    }
                    // 読んだ位置の更新
                    self.applyCurrentReadingPointToIndicator(novelID: novelID)
                case .error(_):
                    break
                }
            })
        }
    }
    func registerBookmarkObserver(novelID:String) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            self.bookmarkObserveToken = RealmBookmark.SearchObjectFromWith(realm: realm, type: .novelSpeechLocation, hint: novelID)?.observe({ (change) in
                switch change {
                case .change(_, let propertys):
                    for property in propertys {
                        if property.name == "location" {
                            self.applyCurrentReadingPointToIndicator(novelID: novelID)
                            break
                        }
                    }
                    break
                default:
                    break
                }
            })
        }
    }
    
    func checkAndUpdateNewImage(novelIDArray:[String]) {
        if novelIDArray != self.watchNovelIDArray { return }
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            guard let novelArray = RealmNovel.GetAllObjectsWith(realm: realm)?.filter("novelID IN %@", novelIDArray) else { return }
            if novelIDArray != self.watchNovelIDArray { return }
            for novel in novelArray {
                if novel.isNewFlug {
                    self.activateNewImageView()
                    return
                }
            }
            self.deactivateNewImageView()
        }
    }
    // TODO: StoryObserver といいつつ、New フラグしか見張ってない
    func registerStoryForNovelArrayObserver(novelIDArray:[String]) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            self.storyForNovelArrayObserveToken = RealmStoryBulk.GetAllObjectsWith(realm: realm)?.filter("novelID IN %@", novelIDArray).observe({ (change) in
                if novelIDArray != self.watchNovelIDArray { return }
                switch (change) {
                case .initial(_):
                    break
                case .update(_, _, let insertions, _):
                    // New! の 表示/非表示 周り
                    if insertions.count > 0 {
                        self.activateNewImageView()
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    func unregistStoryObserver() {
        self.storyObserveToken = nil
    }
    func registerGlobalStateObserver() {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: realmQueue) { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            let isDisplay = globalState.isReadingProgressDisplayEnabled
            DispatchQueue.main.async {
                if isDisplay && self.watchNovelIDArray.count == 1 {
                    self.readProgressView.isHidden = false
                }else{
                    self.readProgressView.isHidden = true
                }
            }
            self.globalStateObserveToken = globalState.observe { (changes) in
                switch changes {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        if property.name == "isReadingProgressDisplayEnabled" {
                            if let isDisplayEnabled = property.newValue as? Bool {
                                DispatchQueue.main.async {
                                    if isDisplayEnabled && self.watchNovelIDArray.count == 1 {
                                        self.readProgressView.isHidden = false
                                    }else{
                                        self.readProgressView.isHidden = true
                                    }
                                }
                            }
                            break
                        }
                    }
                case .deleted:
                    break
                }
            }
        }
    }
    
    func registerDownloadStatusNotification(){
        NotificationCenter.default.addObserver(self, selector: #selector(downloadStatusChanged(notification:)), name: Notification.Name.NovelSpeaker.DownloadStatusChanged, object: nil)
    }
    func unregistDownloadStatusNotification(){
        NotificationCenter.default.removeObserver(self)
    }
    @objc func downloadStatusChanged(notification:Notification) {
        applyCurrentDownloadIndicatorVisibleStatus(novelIDArray: self.watchNovelIDArray)
    }

    func cellSetup(title:String, treeLevel: Int, watchNovelIDArray: [String]) {
        applyDepth(treeLevel: treeLevel)
        if title.count <= 0 {
            titleLabel.text = NSLocalizedString("BookShelfTreeViewCell_UnknownTitle", comment: "(小説名未設定)")
        }else{
            titleLabel.text = title
        }
        self.checkAndUpdateNewImage(novelIDArray: watchNovelIDArray)
        registerGlobalStateObserver()
        if watchNovelIDArray.count == 1 {
            let novelID = watchNovelIDArray[0]
            self.readProgressView.isHidden = false
            applyCurrentReadingPointToIndicator(novelID: novelID)
            registerStoryObserver(novelID: novelID)
            registerNovelObserver(novelID: novelID)
            registerBookmarkObserver(novelID: novelID)
            applyLikeStarStatus(novelID: novelID)
            self.likeButton.isHidden = false
            self.storyForNovelArrayObserveToken = nil
        }else{
            self.readProgressView.isHidden = true
            self.likeButton.isHidden = true
            registerStoryForNovelArrayObserver(novelIDArray: watchNovelIDArray)
            registerNovelArrayObserver(novelIDArray: watchNovelIDArray)
            self.storyObserveToken = nil
            self.bookmarkObserveToken = nil
        }
        applyCurrentDownloadIndicatorVisibleStatus(novelIDArray: watchNovelIDArray)
        self.watchNovelIDArray = watchNovelIDArray
    }
    
    public var height : CGFloat {
        get {
            return CGFloat(self.titleLabel.bounds.height) + CGFloat(12) + CGFloat(10.5)
        }
    }
    
    @IBAction func likeButtonClicked(_ sender: Any) {
        RealmUtil.Write { (realm) in
            guard self.watchNovelIDArray.count == 1, let novelID = self.watchNovelIDArray.first, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            if novel.likeLevel > 0 {
                novel.likeLevel = 0
            }else{
                novel.likeLevel = 1
            }
        }
    }
}
