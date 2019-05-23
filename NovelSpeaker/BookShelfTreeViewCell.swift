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
    
    var storyObserveToken: NotificationToken? = nil
    var storyForNovelArrayObserveToken: NotificationToken? = nil
    var watchNovelIDArray:[String] = []
    
    deinit {
        self.unregistDownloadStatusNotification()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        unregistStoryObserver()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    func activateNewImageView() {
        if self.newImageView.isHidden {
            self.newImageView.isHidden = false
        }
    }
    func deactivateNewImageView() {
        if !self.newImageView.isHidden {
            self.newImageView.isHidden = true
        }
    }
    func applyDepth(treeLevel:Int) {
        let depthWidth = CGFloat(self.depthWidth * Float(treeLevel))
        self.treeDepthImageView.removeConstraint(self.treeDepthImageViewWidthConstraint)
        self.treeDepthImageViewWidthConstraint = self.treeDepthImageView.widthAnchor.constraint(equalToConstant: depthWidth)
        self.treeDepthImageViewWidthConstraint.isActive = true
    }
    func applyCurrentReadingPointToIndicator(novelID:String) {
        guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID), let story = novel.readingChapter else {
            self.readProgressView.progress = 0.0
            return
        }
        let chapterNumber = Float(story.chapterNumber)
        let readLocation = Float(story.readLocation)
        let contentCount = Float(story.content?.count ?? story.readLocation)
        let lastChapterNumber = Float(novel.lastChapterNumber ?? 1)
        let progress = ((chapterNumber - 1.0) + readLocation / contentCount) / lastChapterNumber
        self.readProgressView.progress = progress
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

    func registerStoryObserver(novelID:String) {
        self.storyObserveToken = RealmStory.GetAllObjects()?.filter("novelID = %@", novelID).observe({ (change) in
            switch (change) {
            case .initial(_):
                break
            case .update(_, _, let insertions, let modifications):
                // 「更新有」の反映
                if insertions.count > 0 {
                    DispatchQueue.main.async {
                        self.activateNewImageView()
                    }
                }else if modifications.count > 0{
                    DispatchQueue.main.async {
                        self.checkAndUpdateNewImage(novelIDArray: [novelID])
                    }
                }
                // 読んだ位置の更新
                DispatchQueue.main.async {
                    self.applyCurrentReadingPointToIndicator(novelID: novelID)
                }
            case .error(_):
                break
            }
        })
    }
    func checkAndUpdateNewImage(novelIDArray:[String]) {
        guard let novelArray = RealmNovel.GetAllObjects()?.filter("novelID IN %@", novelIDArray) else { return }
        for novel in novelArray {
            if novel.isNewFlug {
                activateNewImageView()
                return
            }
        }
        deactivateNewImageView()
    }
    // TODO: StoryObserver といいつつ、New フラグしか見張ってない
    func registerStoryForNovelArrayObserver(novelIDArray:[String]) {
        self.storyForNovelArrayObserveToken = RealmStory.GetAllObjects()?.filter("novelID IN %@", novelIDArray).observe({ (change) in
            switch (change) {
            case .initial(_):
                break
            case .update(let objs, _, let insertions, let modifications):
                // New! の 表示/非表示 周り
                if insertions.count > 0 {
                    DispatchQueue.main.async {
                        self.activateNewImageView()
                    }
                }else if modifications.count > 0 {
                    var novelIDSet = Set<String>()
                    for index in modifications {
                        if objs.count > index {
                            let story = objs[index]
                            novelIDSet.insert(story.novelID)
                        }
                    }
                    DispatchQueue.main.async {
                        self.checkAndUpdateNewImage(novelIDArray: Array(novelIDSet))
                    }
                }
            case .error(_):
                break
            }
        })
    }
    func unregistStoryObserver() {
        self.storyObserveToken = nil
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
        titleLabel.text = title
        self.checkAndUpdateNewImage(novelIDArray: watchNovelIDArray)
        if watchNovelIDArray.count == 1 {
            let novelID = watchNovelIDArray[0]
            self.readProgressView.isHidden = false
            applyCurrentReadingPointToIndicator(novelID: novelID)
            registerStoryObserver(novelID: novelID)
            self.storyForNovelArrayObserveToken = nil
        }else{
            self.readProgressView.isHidden = true
            registerStoryForNovelArrayObserver(novelIDArray: watchNovelIDArray)
            self.storyObserveToken = nil
        }
        applyCurrentDownloadIndicatorVisibleStatus(novelIDArray: watchNovelIDArray)
        self.watchNovelIDArray = watchNovelIDArray
    }
    
    public var height : CGFloat {
        get {
            return CGFloat(self.titleLabel.bounds.height) + CGFloat(12) + CGFloat(10.5)
        }
    }
    
}
