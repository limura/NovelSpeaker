//
//  BookShelfRATreeViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/10/26.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import RATreeView
import RealmSwift
import Eureka

/*
class BookShelfRATreeViewCellData {
    public var novelID:String?
    public var childrens:[BookShelfRATreeViewCellData]?
    public var title:String?
}

func == (lhs: BookShelfRATreeViewCellData, rhs: BookShelfRATreeViewCellData) -> Bool {
    if lhs.novelID == rhs.novelID && lhs.title == rhs.title {
        if let lhsc = lhs.childrens, let rhsc = rhs.childrens {
            if lhsc == rhsc {
                return true
            }
        }
    }
    return false
}
extension BookShelfRATreeViewCellData: Equatable {}
*/

class BookShelfRATreeViewController: UIViewController, RATreeViewDataSource, RATreeViewDelegate, UIScrollViewDelegate, RealmObserverResetDelegate {
    var displayDataArray : [BookShelfRATreeViewCellData] = [];
    var treeView:RATreeView?
    var searchText:String? = nil
    var searchButton:UIBarButtonItem = UIBarButtonItem()
    var switchFolderButton:UIBarButtonItem = UIBarButtonItem()
    var iCloudPullButton:UIBarButtonItem = UIBarButtonItem()
    var iCloudPushButton:UIBarButtonItem = UIBarButtonItem()
    var stopDownloadButton:UIBarButtonItem = UIBarButtonItem()
    var resumeSpeechFloatingButton:FloatingButton? = nil
    var nextViewStoryID: String?
    var isNextViewNeedResumeSpeech:Bool = false
    var isNextViewNeedUpdateReadDate:Bool = true
    
    var novelArrayNotificationToken : NotificationToken? = nil
    var globalStateNotificationToken: NotificationToken? = nil
    var novelTagNotificationToken : NotificationToken? = nil
    
    static var instance:BookShelfRATreeViewController? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        BookShelfRATreeViewController.instance = self
        StoryHtmlDecoder.shared.LoadSiteInfoIfNeeded()

        let treeView = RATreeView()
        view.addSubview(treeView)
        treeView.frame = view.bounds
        treeView.dataSource = self
        treeView.delegate = self
        treeView.scrollView.delegate = self
        treeView.register(UINib(nibName: BookShelfTreeViewCell.id, bundle: nil), forCellReuseIdentifier: String(describing: BookShelfTreeViewCell.self))
        let guide:UILayoutGuide
        if #available(iOS 11.0, *) {
            guide = self.view.safeAreaLayoutGuide
        } else {
            guide = self.view.layoutMarginsGuide
        }
        treeView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 0).isActive = true
        treeView.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: 2).isActive = true
        treeView.rightAnchor.constraint(equalTo: guide.rightAnchor, constant: -2).isActive = true
        treeView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: 0).isActive = true
        treeView.translatesAutoresizingMaskIntoConstraints = false
        treeView.estimatedRowHeight = 44
        treeView.rowHeight = UITableView.automaticDimension
        self.treeView = treeView
        
        // このタイミングで StorySpeaker のインスタンスを作っておきます。
        // Realm observe が走るので、main thread で作っておかねばならぬらしい(´・ω・`)
        _ = StorySpeaker.shared
        
        self.title = NSLocalizedString("BookShelfRATreeViewController_Title", comment: "本棚")
        
        // 編集ボタン等を配置
        self.searchButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索"), style: .done, target: self, action: #selector(searchButtonClicked))
        if #available(iOS 13.0, *) {
            self.switchFolderButton = UIBarButtonItem.init(image: UIImage(systemName: "rectangle.expand.vertical"), style: .plain, target: self, action: #selector(switchFolderButtonClicked))
            self.switchFolderButton.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_SwitchFolderButton_VoiceOverTitle", comment: "フォルダ開閉")
        }else{
            self.switchFolderButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfRATreeViewController_ExpandFolderButton", comment: "フォルダ開閉"), style: UIBarButtonItem.Style.done, target: self, action: #selector(switchFolderButtonClicked))
        }
        self.assinButtons()

        if NiftyUtility.IsVersionUped() {
            showVersionUpNotice()
            NiftyUtility.UpdateCurrentVersionSaveData()
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm), let novel = RealmGlobalState.GetLastReadNovel(realm: realm), globalState.isOpenRecentNovelInStartTime {
                self.pushNextView(novelID: novel.novelID, isNeedSpeech: false, isNeedUpdateReadDate: false)
            }
        }
        // reloadAllDataAndScrollToCurrentReadingContent() がかなり時間かかる場合があるので、
        // 初期値を置いてからロードは別threadでやらせます。
        // ここで時間を取られて起動に時間がかかったとみなされてシステムから殺されるという挙動が確認されたための対処になります。
        do {
            let dummyCell = BookShelfRATreeViewCellData()
            dummyCell.childrens = nil
            dummyCell.novelID = nil
            dummyCell.title = NSLocalizedString("BookShelfRATreeViewController_InitialDummyCellTitle", comment: "本棚の小説を読み込んでいます……")
            self.displayDataArray = [
                dummyCell
            ]
            self.treeView?.reloadData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.reloadAllDataAndScrollToCurrentReadingContent()
            }
        }
        
        NiftyUtility.CheckNewImportantImformation(hasNewInformationAlive: { (text) in
            if text.count > 0 {
                DispatchQueue.main.async {
                    if let item = self.tabBarController?.tabBar.items?[3] {
                        item.badgeValue = "!"
                    }
                }
            }
        }) {
            // nothing to do.
        }
        
        #if !targetEnvironment(macCatalyst)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshControlValueChangedEvent), for: .valueChanged)
        treeView.scrollView.addSubview(refreshControl)
        #endif
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        registObserver()
        registNotificationCenter()
    }
    
    deinit {
        self.unregistNotificationCenter()
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.HilightCurrentReadingNovel()
        self.assignCloudPullPushButtonStatus()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let floatingButton = self.resumeSpeechFloatingButton {
            floatingButton.hide()
            self.resumeSpeechFloatingButton = nil
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        self.treeView?.setEditing(editing, animated: animated)
    }

    func StopObservers() {
        novelArrayNotificationToken = nil
        globalStateNotificationToken = nil
        novelTagNotificationToken = nil
    }
    
    func RestartObservers() {
        StopObservers()
        registObserver()
    }

    func registNotificationCenter() {
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.RealmSettingChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.reloadAllDataAndScrollToCurrentReadingContent()
                self.registObserver()
            }
        }
    }
    
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }
    
    func registNovelArrayObserver() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novelArray = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
            novelArrayNotificationToken = novelArray.observe { (change) in
                switch change {
                case .initial(_):
                    break
                case .update(let objects, let deletions, let insertions, let modifications):
                    if deletions.count > 0 || insertions.count > 0 {
                        DispatchQueue.main.async {
                            self.reloadAllData()
                        }
                        return
                    }
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard modifications.count > 0, let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                        let sortType = globalState.bookShelfSortType
                        if sortType == .LastReadDate {
                            let gapDate = Date(timeIntervalSinceNow: -5) // 5秒前までなら今書き変わったと思い込む
                            for index in modifications {
                                if objects.count > index {
                                    let obj = objects[index]
                                    if obj.lastReadDate > gapDate {
                                        if let novelID = self.displayDataArray.first?.novelID, novelID == obj.novelID {
                                            // 既に先頭がその小説なら表示しなおす必要は無い
                                            continue
                                        }
                                        DispatchQueue.main.async {
                                            self.reloadAllData()
                                        }
                                        return
                                    }
                                }
                            }
                        }else if sortType == .NovelUpdatedAt || sortType == .NovelUpdatedAtWithFolder {
                            let gapDate = Date(timeIntervalSinceNow: -5) // 5秒前までなら今書き変わったと思い込む
                            for index in modifications {
                                if objects.count > index {
                                    let obj = objects[index]
                                    if obj.lastDownloadDate > gapDate {
                                        if let novelID = self.displayDataArray.first?.novelID, novelID == obj.novelID {
                                            // 既に先頭がその小説なら表示しなおす必要は無い
                                            continue
                                        }
                                        DispatchQueue.main.async {
                                            self.reloadAllData()
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                case .error(_):
                    break
                }
            }
        }
    }
    
    func registGlobalStateObserver() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            self.globalStateNotificationToken = globalState.observe({ (change) in
                switch change {
                case .change(_, let propertyArray):
                    for property in propertyArray {
                        if property.name == "bookshelfViewButtonSettingArrayData" {
                            DispatchQueue.main.async {
                                self.assinButtons()
                            }
                        }
                    }
                    break
                case .deleted:
                    break
                case .error(_):
                    break
                }
            })
        }
    }
    
    func registNovelTagObserver() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let tagArray = RealmNovelTag.GetAllObjectsWith(realm: realm) else { return }
            self.novelTagNotificationToken = tagArray.observe({ (change) in
                switch change {
                case .error(_):
                    break
                case .initial(_):
                    break
                case .update(_, deletions: _, insertions: _, modifications: _):
                    let sortType = RealmUtil.RealmBlock { (realm) -> NarouContentSortType in
                        guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return .Title }
                        return globalState.bookShelfSortType
                    }
                    if sortType != .KeywordTag { return }
                    DispatchQueue.main.async {
                        self.reloadAllData()
                    }
                }
            })
        }
    }
    
    func registObserver() {
        registNovelArrayObserver()
        registGlobalStateObserver()
        registNovelTagObserver()
    }
    
    func assignRightBarButtons() {
        let buttonSettingArray = RealmUtil.RealmBlock { (realm) -> [BookshelfViewButtonSetting] in
            guard let settingArray = RealmGlobalState.GetInstanceWith(realm: realm)?.GetBookshelfViewButtonSetting() else { return BookshelfViewButtonSetting.defaultSetting }
            return settingArray
        }
        var barButtonItemArray:[UIBarButtonItem] = []
        for buttonSetting in buttonSettingArray {
            if buttonSetting.isOn == false { continue }
            switch buttonSetting.type {
            case .multiSelect:
                break
            case .downloadStatus:
                break
            case .edit:
                barButtonItemArray.append(self.editButtonItem)
            case .switchFolder:
                barButtonItemArray.append(self.switchFolderButton)
            case .order:
                barButtonItemArray.append(UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SortTypeSelectButton", comment: "sort"), style: UIBarButtonItem.Style.done, target: self, action: #selector(sortTypeSelectButtonClicked)))
            case .reload:
                barButtonItemArray.append(UIBarButtonItem.init(barButtonSystemItem: UIBarButtonItem.SystemItem.refresh, target: self, action: #selector(refreshButtonClicked)))
            case .search:
                break
            case .iCloudPull:
                let button:UIBarButtonItem
                if #available(iOS 13.0, *), let image = UIImage(systemName: "icloud.and.arrow.down") {
                    button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(iCloudPullButtonClicked))
                    button.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_iCloudPullButton_VoiceOverText", comment: "iCloud上のデータの読み込みを開始")
                }else{
                    button = UIBarButtonItem(title: NSLocalizedString("BookShelfRATreeViewController_iCloudPullButtonTitle", comment: "iCloudから取得"), style: .plain, target: self, action: #selector(iCloudPullButtonClicked))
                    button.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_iCloudPullButton_VoiceOverText", comment: "iCloud上のデータの読み込みを開始")
                }
                button.isEnabled = RealmUtil.IsUseCloudRealm()
                self.iCloudPullButton = button
                barButtonItemArray.append(button)
            case .iCloudPush:
                let button:UIBarButtonItem
                if #available(iOS 13.0, *), let image = UIImage(systemName: "icloud.and.arrow.up") {
                    button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(iCloudPushButtonClicked))
                    button.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_iCloudPushButton_VoiceOverText", comment: "iCloudへのデータアップロードを開始")
                }else{
                    button = UIBarButtonItem(title: NSLocalizedString("BookShelfRATreeViewController_iCloudPushButtonTitle", comment: "iCloudへ送信"), style: .plain, target: self, action: #selector(iCloudPushButtonClicked))
                    button.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_iCloudPushButton_VoiceOverText", comment: "iCloudへのデータアップロードを開始")
                }
                button.isEnabled = RealmUtil.IsUseCloudRealm()
                self.iCloudPushButton = button
                barButtonItemArray.append(button)
            case .stopDownload:
                let button:UIBarButtonItem
                if #available(iOS 13.0, *), let image = UIImage(systemName: "pause.circle") {
                    button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(stopDownloadButtonClicked))
                    button.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_stopDownloadButton_VoiceOverText", comment: "ダウンロードを停止")
                }else{
                    button = UIBarButtonItem(title: NSLocalizedString("BookShelfRATreeViewController_stopDownloadButtonTitle", comment: "停止"), style: .plain, target: self, action: #selector(stopDownloadButtonClicked))
                    button.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_stopDownloadButton_VoiceOverText", comment: "ダウンロードを停止")
                }
                self.stopDownloadButton = button
                barButtonItemArray.append(button)
            }
        }
        self.navigationItem.rightBarButtonItems = barButtonItemArray.reversed()
    }
    
    func assignLeftBarButtons() {
        self.navigationItem.leftBarButtonItems = [self.searchButton]
    }
    
    func assinButtons() {
        assignRightBarButtons()
        assignLeftBarButtons()
    }

    // 検索条件やソート条件を考慮した上での NarouContent の Array を返します
    func getNovelArray(realm: Realm, sortType:NarouContentSortType) -> [RealmNovel]? {
        let startTime = DispatchTime.now()
        defer {
            FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime, functionName: "BookShelfRATreeViewController.getNovelArray()")
        }
        guard var allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return nil }
        if let searchText = self.searchText, searchText.count > 0 {
            allNovels = allNovels.filter("title CONTAINS %@ OR writer CONTAINS %@", searchText, searchText)
        }
        switch sortType {
        case .Ncode:
            return Array(allNovels.sorted(byKeyPath: "novelID", ascending: true))
        case .NovelUpdatedAtWithFolder:
            fallthrough
        case .NovelUpdatedAt:
            return Array(allNovels.sorted(byKeyPath: "lastDownloadDate", ascending: false))
        case .LastReadDate:
            return Array(allNovels.sorted(byKeyPath: "lastReadDate", ascending: false))
        case .Writer:
            return Array(allNovels.sorted(byKeyPath: "writer", ascending: false))
        case .LikeLevel:
            let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
            let sortedNovels = allNovels.sorted { (a, b) -> Bool in
                return globalState?.calcLikeLevel(novelID: a.novelID) ?? 0 > globalState?.calcLikeLevel(novelID: b.novelID) ?? 0
            }
            return sortedNovels
        case .WebSite:
            return allNovels.sorted(by: { (a, b) -> Bool in
                guard let ah = URL(string: a.novelID)?.host, let bh = URL(string: b.novelID)?.host else {
                    return a.novelID < b.novelID
                }
                return ah < bh
            })
        case .CreatedDate:
            return Array(allNovels.sorted(byKeyPath: "createdDate", ascending: false))
        case .Title:
            fallthrough
        case .SelfCreatedFolder:
            fallthrough
        case .KeywordTag:
            fallthrough
        @unknown default:
            return Array(allNovels.sorted(byKeyPath: "title", ascending: false))
        }
    }
    
    // 単純な本棚データの作成
    func createSimpleBookShelfRATreeViewCellDataTree(sortType:NarouContentSortType) -> (Bool,[BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool,[BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: sortType) else { return (false,[]) }
            var result:[BookShelfRATreeViewCellData] = []
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return (false, result)
        }
    }
    
    // 更新日時でフォルダ分けします(フォルダ分けする版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithFolder() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool,[BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.NovelUpdatedAt) else { return (false,[]) }
            struct filterStruct {
                let title:String
                let date:Date
            }
            let filterList = [
                filterStruct(title: NSLocalizedString("BookShelfRATreeViewController_UpTo1DayAgo", comment: "1日前まで"), date: Date(timeIntervalSinceNow: -60*60*24)),
                filterStruct(title: NSLocalizedString("BookShelfRATreeViewController_UpTo7DayAgo", comment: "7日前まで"), date: Date(timeIntervalSinceNow: -60*60*24*7)),
                filterStruct(title: NSLocalizedString("BookShelfRATreeViewController_UpTo30DayAgo", comment: "30日前まで"), date: Date(timeIntervalSinceNow: -60*60*24*30)),
                filterStruct(title: NSLocalizedString("BookShelfRATreeViewController_UpTo6MonthsAgo", comment: "6ヶ月前まで"), date: Date(timeIntervalSinceNow: -60*60*24*30*6)),
                filterStruct(title: NSLocalizedString("BookShelfRATreeViewController_UpTo1YearAgo", comment: "1年前まで"), date: Date(timeIntervalSinceNow: -60*60*24*365)),
                filterStruct(title: NSLocalizedString("BookShelfRATreeViewController_BeforeThat", comment: "それ以前"), date: Date(timeIntervalSinceNow: -60*60*24*365*100)),
            ]
            var result = [] as [BookShelfRATreeViewCellData]
            var prevDate = Date(timeIntervalSinceNow: 9999999999)
            for filter in filterList {
                let folder = BookShelfRATreeViewCellData()
                folder.title = filter.title
                folder.childrens = []
                for novel in novels.sorted(by: {$0.lastDownloadDate < $1.lastDownloadDate}) {
                    let lastDownloadDate = novel.lastDownloadDate
                    if lastDownloadDate <= prevDate && lastDownloadDate > filter.date {
                        let data = BookShelfRATreeViewCellData()
                        data.novelID = novel.novelID
                        data.title = novel.title
                        folder.childrens?.append(data)
                    }
                }
                result.append(folder)
                prevDate = filter.date
            }
            return (true, result)
        }
    }

    // 更新日時でフォルダ分けします(フォルダ分けしない版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> (Bool, [BookShelfRATreeViewCellData]) {
        let startTime = DispatchTime.now()
        defer {
            FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime)
        }
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.NovelUpdatedAt) else { return (false,[]) }
            let startTime = DispatchTime.now()
            defer {
                FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime, functionName: "createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder/create [BookShelfRATreeViewCellData]")
            }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return (false, result)
        }
    }

    // 作者名でフォルダ分けします
    func createWriterBookShelfRATreeViewCellDataTree() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.Title) else { return (false,[]) }
            var dic = [String:Any]()
            for novel in novels {
                if var array = dic[novel.writer] as? [RealmNovel]{
                    array.append(novel)
                    dic[novel.writer] = array
                }else{
                    var array = [RealmNovel]()
                    array.append(novel)
                    dic[novel.writer] = array
                }
            }
            var targets = [String]()
            for key in dic.keys {
                targets.append(key)
            }
            targets.sort(){ $0 < $1 }
            
            var result = [BookShelfRATreeViewCellData]()
            for target in targets {
                let folder = BookShelfRATreeViewCellData()
                folder.childrens = [BookShelfRATreeViewCellData]()
                folder.title = target == "" ? NSLocalizedString("BookShelfRATreeViewController_UnknownWriter", comment: "(作者名不明)") : target
                if let novels = dic[target] as? [RealmNovel] {
                    for novel in novels.sorted(by: {$0.title < $1.title}) {
                        let data = BookShelfRATreeViewCellData()
                        data.novelID = novel.novelID
                        data.title = novel.title
                        folder.childrens?.append(data)
                    }
                }
                result.append(folder)
            }
            return (true, result)
        }
    }
    
    // 自作のフォルダでフォルダ分けします
    func createBookShelfTagFolderRATreeViewCellDataTree() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.Title), let tags = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) else { return (false,[]) }
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            var novelID2NovelMap = [String:RealmNovel]()
            for novel in novels {
                novelID2NovelMap[novel.novelID] = novel
            }
            for tag in tags {
                guard let novels = tag.targetNovelArrayFrom(novelID2NovelMap: novelID2NovelMap) else { continue }
                let folder = BookShelfRATreeViewCellData()
                folder.childrens = [BookShelfRATreeViewCellData]()
                folder.title = tag.name
                for novel in novels {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    folder.childrens?.append(data)
                    listedNovelIDSet.insert(novel.novelID)
                }
                result.append(folder)
            }
            result.sort(by: { (a, b) -> Bool in
                a.title! < b.title!
            })
            var noListedNovels = [RealmNovel]()
            for novel in novels {
                if listedNovelIDSet.contains(novel.novelID) { continue }
                noListedNovels.append(novel)
            }
            if noListedNovels.count > 0 {
                let folder = BookShelfRATreeViewCellData()
                folder.title = NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)")
                folder.childrens = [BookShelfRATreeViewCellData]()
                for novel in noListedNovels {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    data.title = novel.title
                    folder.childrens?.append(data)
                }
                result.append(folder)
            }
            return (true, result)
        }
    }
    
    // キーワード(Tag)でフォルダ分けします
    func createBookShelfKeywordTagRATreeViewCellDataTree() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            // ２つ以上の小説が登録されていないタグは無視します。
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.Title), let tags = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Keyword)?.filter({ (tag) -> Bool in
                return tag.targetNovelIDArray.count >= 2
            }) else { return (false,[]) }
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            var novelIDToNovelMap:[String:RealmNovel] = [:]
            for novel in novels {
                novelIDToNovelMap[novel.novelID] = novel
            }
            for tag in tags {
                let folder = BookShelfRATreeViewCellData()
                folder.childrens = [BookShelfRATreeViewCellData]()
                folder.title = tag.name
                for novelID in tag.targetNovelIDArray {
                    if let novel = novelIDToNovelMap[novelID] {
                        let data = BookShelfRATreeViewCellData()
                        data.novelID = novel.novelID
                        data.title = novel.title
                        folder.childrens?.append(data)
                        listedNovelIDSet.insert(novel.novelID)
                    }
                }
                result.append(folder)
            }
            result.sort(by: { (a, b) -> Bool in
                a.title! < b.title!
            })
            var noListedNovels = [RealmNovel]()
            for novel in novels {
                if listedNovelIDSet.contains(novel.novelID) { continue }
                noListedNovels.append(novel)
            }
            if noListedNovels.count > 0 {
                let folder = BookShelfRATreeViewCellData()
                folder.title = NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)")
                folder.childrens = [BookShelfRATreeViewCellData]()
                for novel in noListedNovels {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    folder.childrens?.append(data)
                }
                result.append(folder)
            }
            return (true, result)
        }
    }

    // 小説を開いた日時でフォルダ分けします(フォルダ分けしない版)
    func createLastReadDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> (Bool, [BookShelfRATreeViewCellData]) {
        let startTime = DispatchTime.now()
        defer {
            FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime, functionName: "createLastReadDateBookShelfRATreeViewCellDataTreeWithoutFolder")
        }
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.LastReadDate) else { return (false,[]) }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return (false, result)
        }
    }

    // 小説のお気に入りレベルで並べ替えます
    func createLikeLevelBookShelfRATreeViewCellDataTreeWithoutFolder() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.LikeLevel) else { return (false,[]) }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return (false, result)
        }
    }
    
    func HostStringToLocalizedString(host:String) -> String {
        let convertTable:[String:String] = [
            "novelspeaker.example.com": NSLocalizedString("BookShelfRATreeViewController_HostNameTable_novelspeaker.example.com", comment: "自作小説"),
        ]
        guard let name = convertTable[host] else { return host }
        return name
    }
    
    // Webサイト(host)で並べ替えます
    func createWebSiteBookShelfRATreeViewCellDataTree() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool,[BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.WebSite) else { return (false,[]) }
            let hosts = novels.map { (novel) -> String in
                guard let host = URL(string: novel.novelID)?.host else { return NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)") }
                return host
            }.reduce([], {$0.contains($1) ? $0 : $0 + [$1]}).sorted()
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            for host in hosts {
                let folder = BookShelfRATreeViewCellData()
                folder.childrens = [BookShelfRATreeViewCellData]()
                folder.title = HostStringToLocalizedString(host: host)
                for novel in novels.filter({ (novel) -> Bool in
                    guard let novelHost = URL(string: novel.novelID)?.host else { return false }
                    return novelHost == host
                }).sorted(by: {$0.title < $1.title}) {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    data.title = novel.title
                    folder.childrens?.append(data)
                    listedNovelIDSet.insert(novel.novelID)
                }
                result.append(folder)
            }
            result.sort(by: { (a, b) -> Bool in
                a.title! < b.title!
            })
            let noListedNovels = novels.filter({listedNovelIDSet.contains($0.novelID) == false})
            if noListedNovels.count > 0 {
                let folder = BookShelfRATreeViewCellData()
                folder.title = NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)")
                folder.childrens = [BookShelfRATreeViewCellData]()
                for novel in noListedNovels {
                    let data = BookShelfRATreeViewCellData()
                    data.title = novel.title
                    data.novelID = novel.novelID
                    folder.childrens?.append(data)
                }
                result.append(folder)
            }
            return (true, result)
        }
    }
    
    // 本棚に登録された順でフォルダ分けします(フォルダ分けしない版)
    func createCreatedDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> (Bool, [BookShelfRATreeViewCellData]) {
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.CreatedDate) else { return (false,[]) }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return (false, result)
        }
    }



    func getBookShelfRATreeViewCellDataTree() -> (Bool, [BookShelfRATreeViewCellData]) {
        let startTime = DispatchTime.now()
        defer {
            FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime)
        }
        var sortType:NarouContentSortType = .Title
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            sortType = globalState.bookShelfSortType
        }
        switch sortType {
        case .Ncode: fallthrough
        case .Title:
            return createSimpleBookShelfRATreeViewCellDataTree(sortType: sortType)
        case .NovelUpdatedAtWithFolder:
            return createUpdateDateBookShelfRATreeViewCellDataTreeWithFolder()
        case .NovelUpdatedAt:
            return createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder()
        case .LastReadDate:
            return createLastReadDateBookShelfRATreeViewCellDataTreeWithoutFolder()
        case .Writer:
            return createWriterBookShelfRATreeViewCellDataTree()
        case .SelfCreatedFolder:
            return createBookShelfTagFolderRATreeViewCellDataTree()
        case .KeywordTag:
            return createBookShelfKeywordTagRATreeViewCellDataTree()
        case .LikeLevel:
            return createLikeLevelBookShelfRATreeViewCellDataTreeWithoutFolder()
        case .WebSite:
            return createWebSiteBookShelfRATreeViewCellDataTree()
        case .CreatedDate:
            return createCreatedDateBookShelfRATreeViewCellDataTreeWithoutFolder()
        default:
            break
        }
        return createSimpleBookShelfRATreeViewCellDataTree(sortType: NarouContentSortType.Title)
    }
    
    func scrollToCurrentReadingContent() {
        return // XXX testing
        /*
        DispatchQueue.global(qos: .userInitiated).async {
            guard let novelID = RealmUtil.RealmBlock(block: { realm in
                return RealmGlobalState.GetLastReadNovel(realm: realm)?.novelID
            }) else { return }
            
            for cellItem in self.displayDataArray {
                // tree が展開されるのは一段目までです(´・ω・`)
                if let childrens = cellItem.childrens {
                    for cellItemChild in childrens {
                        if cellItemChild.novelID == novelID {
                            DispatchQueue.main.async {
                                self.treeView?.beginUpdates()
                                self.treeView?.expandRow(forItem: cellItem)
                                self.treeView?.scrollToRow(forItem: cellItem, at: RATreeViewScrollPositionTop, animated: false)
                                self.treeView?.endUpdates()
                                self.addPreviousNovelSpeakButtonIfNeeded()
                                self.setExpandIcon()
                            }
                            return
                        }
                    }
                }
                if cellItem.novelID == novelID {
                    DispatchQueue.main.async {
                        self.treeView?.beginUpdates()
                        self.treeView?.scrollToRow(forItem: cellItem, at: RATreeViewScrollPositionTop, animated: false)
                        self.treeView?.endUpdates()
                        self.addPreviousNovelSpeakButtonIfNeeded()
                        self.setCollapseIcon()
                    }
                    return
                }
            }
        }
         */
    }
    
    func setExpandIcon() {
        if #available(iOS 13.0, *) {
            DispatchQueue.main.async {
                self.switchFolderButton.image = UIImage(systemName: "rectangle.compress.vertical")
            }
        }
    }
    func setCollapseIcon() {
        if #available(iOS 13.0, *) {
            DispatchQueue.main.async {
                self.switchFolderButton.image = UIImage(systemName: "rectangle.expand.vertical")
            }
        }
    }

    func checkAndUpdateSwitchFolderButtonImage() {
        if isFolderExpanded() {
            setExpandIcon()
        }else{
            setCollapseIcon()
        }
    }
    
    func reloadAllData() {
        let startTime = DispatchTime.now()
        defer {
            FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime, functionName: "BookShelfRATreeViewController.reloadAllData()")
        }
        let (hasFolder, displayDataArray) = getBookShelfRATreeViewCellDataTree()
        self.displayDataArray = displayDataArray
        let treeViewReloadDataStartTime = DispatchTime.now()
        NiftyUtility.DispatchSyncMainQueue {
            self.treeView?.reloadData()
        }
        FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: treeViewReloadDataStartTime, functionName: "BookShelfRATreeViewController.reloadAllData()/treeView.reloadData()")
        let hilightCurrentReadingNovelStartTime = DispatchTime.now()
        self.HilightCurrentReadingNovel()
        FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: hilightCurrentReadingNovelStartTime, functionName: "BookShelfRATreeViewController.reloadAllData()/HilightCurrentReadingNovel()")
        if hasFolder {
            self.switchFolderButton.isEnabled = true
        }else{
            self.switchFolderButton.isEnabled = false
        }
    }

    func reloadAllData(completion:(()->Void)?) {
        UIView.animate(withDuration: 0.0) {
            self.reloadAllData()
        } completion: { (finished) in
            completion?()
        }
    }

    func reloadAllDataAndScrollToCurrentReadingContent(){
        DispatchQueue.global(qos: .userInitiated).async {
            let startTime = DispatchTime.now()
            defer {
                FunctionExecutionMetrics.shared.RecordExecutionTime(startTime: startTime)
                FunctionExecutionMetrics.shared.PrintMetrics()
            }
            self.reloadAllData()
            self.scrollToCurrentReadingContent()
        }
    }

    func showVersionUpNotice(){
        NiftyUtility.EasyDialogBuilder(self)
            .title(title: NSLocalizedString("BookShelfTableViewController_AnnounceNewViersion", comment: "アップデートされました"))
            .textView(content: NSLocalizedString("BookShelfTableViewController_AnnounceNewVersionMessage", comment: "Version 1.1.2\r\n..."), heightMultiplier: 0.63)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                dialog.dismiss(animated: true, completion: nil)
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                    if globalState.isOpenRecentNovelInStartTime {
                        if let lastReadNovel = RealmGlobalState.GetLastReadNovel(realm: realm) {
                            self.pushNextView(novelID: lastReadNovel.novelID, isNeedSpeech: false, isNeedUpdateReadDate: false)
                        }
                    }
                }
            })
            .build(isForMessageDialog: true).show()
    }

    @objc func refreshButtonClicked(sender: Any) {
        DispatchQueue.global(qos: .background).async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novels = RealmNovel.GetAllObjectsWith(realm: realm)?.filter("isNotNeedUpdateCheck = false") else { return }
                NovelDownloadQueue.shared.addQueueArray(novelArray: ThreadSafeReference(to: novels))
            }
        }
    }
    
    @objc func iCloudPullButtonClicked(sender: Any) {
        if RealmUtil.IsUseCloudRealm() {
            DispatchQueue.main.async {
                RealmUtil.CloudPull()
                NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("BookShelfRATreeViewController_iCloudPullButton_Clicked", comment: "iCloud上のデータの再ダウンロードを開始しました。"), buttonTitle: nil, buttonAction: nil)
            }
        }
    }
    @objc func iCloudPushButtonClicked(sender: Any) {
        if RealmUtil.IsUseCloudRealm() {
            DispatchQueue.main.async {
                RealmUtil.CloudPush()
                NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("BookShelfRATreeViewController_iCloudPushButton_Clicked", comment: "iCloudへのデータのアップロードを開始しました。"), buttonTitle: nil, buttonAction: nil)
            }
        }
    }
    @objc func stopDownloadButtonClicked(sender: Any) {
        NovelDownloadQueue.shared.downloadStop()
    }
    
    func assignCloudPullPushButtonStatus() {
        let isEnabled = RealmUtil.IsUseCloudRealm()
        self.iCloudPullButton.isEnabled = isEnabled
        self.iCloudPushButton.isEnabled = isEnabled
    }

    func getDisplayStringToSortTypeDictionary() -> [String:NarouContentSortType]{
        return [
            //NSLocalizedString("BookShelfTableViewController_SortTypeNcode", comment: "Ncode順"): NarouContentSortType.ncode
            NSLocalizedString("BookShelfTableViewController_SortTypeWriter", comment: "作者名順"): NarouContentSortType.Writer
            , NSLocalizedString("BookShelfTableViewController_SortTypeNovelName", comment: "小説名順"): NarouContentSortType.Title
            , NSLocalizedString("BookShelfTableViewController_SortTypeUpdateDate", comment: "更新順"): NarouContentSortType.NovelUpdatedAt
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeFolder", comment: "自作フォルダ順"): NarouContentSortType.SelfCreatedFolder
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeKeywardTag", comment: "タグ名順"): NarouContentSortType.KeywordTag
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeUpdateDateWithFilder", comment: "最終ダウンロード順(フォルダ分類版)"): NarouContentSortType.NovelUpdatedAtWithFolder
            , NSLocalizedString("BookShelfRATreeViewController_StoryTypeLastReadDate", comment: "小説を開いた日時順"): NarouContentSortType.LastReadDate
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeLikeLevel", comment: "お気に入り順"): NarouContentSortType.LikeLevel
            , NSLocalizedString("BookShelfRATreeViewController_SorteTypeWebSite", comment: "Webサイト順"): NarouContentSortType.WebSite
            , NSLocalizedString("BookShelfRATreeViewController_SorteTypeCreatedDate", comment: "本棚登録順"): NarouContentSortType.CreatedDate
        ]
    }

    func getCurrentSortTypeDisplayString() -> String {
        return RealmUtil.RealmBlock { (realm)  -> String in
            let dic = getDisplayStringToSortTypeDictionary()
            guard let sortType = RealmGlobalState.GetInstanceWith(realm: realm)?.bookShelfSortType else { return "-" }
            for (key, type) in dic {
                if type == sortType {
                    return key
                }
            }
            return "-"
        }
    }
    
    func convertDisplayStringToSortType(key: String) -> NarouContentSortType {
        let dic = getDisplayStringToSortTypeDictionary()
        if let type = dic[key] {
            return type
        }
        return NarouContentSortType.NovelUpdatedAt
    }
    
    func isFolderExpanded() -> Bool {
        for cellData in self.displayDataArray {
            if cellData.childrens?.count ?? 0 > 0, self.treeView?.isCell(forItemExpanded: cellData) ?? false {
                return true
            }
        }
        return false
    }
    
    @objc func switchFolderButtonClicked(sender:Any) {
        DispatchQueue.main.async {
            let isExpanded = self.isFolderExpanded()
            NiftyUtility.EasyDialogNoButton(viewController: self, title: NSLocalizedString("BookShelfRATreeViewController_NowSwitchingFolderMessage", comment: "フォルダ開閉中……"), message: nil) { (dialog) in
                DispatchQueue.main.async {
                    self.treeView?.beginUpdates()
                    for cellItem in self.displayDataArray {
                        if let childrens = cellItem.childrens, childrens.count > 0 {
                            if isExpanded {
                                self.treeView?.collapseRow(forItem: cellItem, with: RATreeViewRowAnimationNone)
                                self.setCollapseIcon()
                            }else{
                                self.treeView?.expandRow(forItem: cellItem, with: RATreeViewRowAnimationNone)
                                self.setExpandIcon()
                            }
                        }
                    }
                    self.treeView?.endUpdates()
                    dialog.dismiss(animated: false, completion: nil)
                }
            }
        }
    }
    
    @objc func sortTypeSelectButtonClicked(sender:Any) {
        let selectTargets = getDisplayStringToSortTypeDictionary().map({ (arg0) -> String in
            let (key, _) = arg0
            return key
        }).sorted(by: { (a:String, b:String) -> Bool in
            a < b
        })
        func finish(result:String?) {
            guard let selectedText = result else { return }
            let sortType = self.convertDisplayStringToSortType(key: selectedText)
            DispatchQueue.main.async {
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            globalState.bookShelfSortType = sortType
                        }
                    }
                }
                self.reloadAllData()
            }
        }
        EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: { (vc) in
            let section = Section()
            for target in selectTargets {
                section <<< LabelRow() {
                    $0.title = target
                    $0.cell.textLabel?.numberOfLines = 0
                    $0.cell.accessibilityTraits = .button
                }.onCellSelection({ (_, row) in
                    finish(result: target)
                    vc.close(animated: true, completion: nil)
                })
            }
            section <<< ButtonRow() {
                $0.title = "Cancel"
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.accessibilityTraits = .button
            }.onCellSelection({ (_, _) in
                finish(result: nil)
                vc.close(animated: true, completion: nil)
            })
            vc.form +++ section
        }, parentViewController: self, animated: true, completion: nil)
    }
    
    @objc func searchButtonClicked(sender:Any) {
        let assignNewSearchText = { (dialog:EasyDialog) in
            let filterTextField = dialog.view.viewWithTag(100) as! UITextField
            let newFilterString = filterTextField.text ?? ""
            if self.searchText == newFilterString {
                dialog.dismiss(animated: false, completion: nil)
                return
            }
            self.searchText = newFilterString
            if newFilterString == "" {
                self.searchButton.title = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索")
            }else{
                self.searchButton.title = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索") + "(" + newFilterString + ")"
            }
            DispatchQueue.main.async {
                self.reloadAllData()
            }
            dialog.dismiss(animated: false, completion: nil)
        }
        if let parent = self.parent {
            NiftyUtility.EasyDialogBuilder(parent)
            .title(title: NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索"))
            .label(text: NSLocalizedString("BookShelfTableViewController_SearchMessage", comment: "小説名 と 作者名 が対象となります"), textAlignment: .left)
            .textField(tag: 100, placeholder: nil, content: searchText, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: UITextField.BorderStyle.none, clearButtonMode: .always, shouldReturnEventHandler: assignNewSearchText)
            .addButton(title: NSLocalizedString("BookShelfTableViewController_SearchClear", comment: "クリア"), callback: { (dialog) in
                let filterTextField = dialog.view.viewWithTag(100) as! UITextField
                filterTextField.text = ""
                assignNewSearchText(dialog)
            })
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback:assignNewSearchText)
            .build().show()
        }
    }

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "bookShelfToReaderSegue" {
            if let nextViewController = segue.destination as? SpeechViewController {
                nextViewController.storyID = nextViewStoryID
                nextViewController.isNeedResumeSpeech = isNextViewNeedResumeSpeech
                nextViewController.isNeedUpdateReadDate = isNextViewNeedUpdateReadDate
            }
        }else if segue.identifier == "bookShelfToWebViewReaderSegue"{
            if let nextViewController = segue.destination as? WebSpeechViewController {
                nextViewController.targetStoryID = nextViewStoryID
                nextViewController.isNeedResumeSpeech = isNextViewNeedResumeSpeech
                nextViewController.isNeedUpdateReadDate = isNextViewNeedUpdateReadDate
            }
        }
    }
    func showNovelInformation(novelID:String) {
        let nextViewController = NovelDetailViewController()
        nextViewController.novelID = novelID
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }
    
    // 次のビューに飛ばします。
    func pushNextView(novelID:String, isNeedSpeech: Bool, isNeedUpdateReadDate: Bool){
        NovelDownloader.flushWritePool(novelID: novelID)
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            guard let story = novel.readingChapterWith(realm: realm) ?? novel.firstChapterWith(realm: realm) else {
                let targetChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: novel.m_readingChapterStoryID)
                let (novelCount, _, _) = RealmStoryBulk.CountStoryFor(realm: realm, novelID: novel.novelID)
                guard novelCount > 0 else {
                    if novel.type == .URL {
                        DispatchQueue.main.async {
                            NiftyUtility.EasyDialogForButton(
                                viewController: self,
                                title: nil,
                                message: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseNoStory", comment: "本文が何も読み込まれていないようです。この小説の再ダウンロードを試みますか？"),
                                button1Title: nil,
                                button1Action: nil,
                                button2Title: NSLocalizedString("Cancel_button", comment: "Cancel"),
                                button2Action: nil,
                                button3Title: NSLocalizedString("BookShelfRATreeViewController_ShowNovelInformationButtonTitle", comment: "小説情報を表示する"),
                                button3Action: { self.showNovelInformation(novelID: novelID) },
                                button4Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OK", comment: "ダウンロードする"), // OK
                                button4Action: {
                                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                            })
                        }
                    }
                    return
                }
                //print("targetChapterNumber: \(targetChapterNumber), novelList.count: \(novelList.count)")
                if novelCount < targetChapterNumber {
                    DispatchQueue.main.async {
                        NiftyUtility.EasyDialogTwoButton(
                            viewController: self,
                            title: nil,
                            message: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber", comment: "読み上げ位置がダウンロードされていない章を示しています。この小説の追加の章のダウンロードを試みますか？"),
                            button1Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OpenFirstStory", comment: "最初の章を開く"),
                            button1Action: {
                                RealmUtil.RealmBlock { (realm) -> Void in
                                    if let nextViewStoryID = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.firstChapterWith(realm: realm)?.storyID {
                                        self.PushToNovelSpeechViewController(nextViewStoryID: nextViewStoryID, isNextViewNeedResumeSpeech: isNeedSpeech, isNextViewNeedUpdateReadDate: isNeedUpdateReadDate)
                                        return
                                    }
                                }
                        },
                            button2Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OK", comment: "ダウンロードする"),
                            button2Action: {
                                NovelDownloadQueue.shared.addQueue(novelID: novelID)
                        })
                    }
                    return
                }
                if let story = novel.firstChapterWith(realm: realm) {
                    print("sendStoryID: \(nextViewStoryID ?? "unknown"), story.chapterNumber \(story.chapterNumber)")
                    self.PushToNovelSpeechViewController(nextViewStoryID: story.storyID, isNextViewNeedResumeSpeech: isNeedSpeech, isNextViewNeedUpdateReadDate: isNeedUpdateReadDate)
                }
                return
            }
            PushToNovelSpeechViewController(nextViewStoryID: story.storyID, isNextViewNeedResumeSpeech: isNeedSpeech, isNextViewNeedUpdateReadDate: isNeedUpdateReadDate)
        }
    }
    
    func PushToNovelSpeechViewController(nextViewStoryID: String, isNextViewNeedResumeSpeech:Bool, isNextViewNeedUpdateReadDate: Bool) {
        self.nextViewStoryID = nextViewStoryID
        self.isNextViewNeedResumeSpeech = isNextViewNeedResumeSpeech
        self.isNextViewNeedUpdateReadDate = isNextViewNeedUpdateReadDate
        RealmUtil.RealmBlock { realm in
            let viewType = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm)?.viewType ?? RealmDisplaySetting.ViewType.normal
            switch viewType {
            case .normal:
                self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
            case .webViewVertical, .webViewHorizontal, .webViewOriginal, .webViewVertical2Column:
                self.performSegue(withIdentifier: "bookShelfToWebViewReaderSegue", sender: self)
            }
        }
    }
    
    func treeView(_ treeView: RATreeView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return self.displayDataArray.count
        }
        if let data = item as? BookShelfRATreeViewCellData? {
            if let childrens = data?.childrens {
                return childrens.count
            }
        }
        return 0
    }
    
    func treeView(_ treeView: RATreeView, cellForItem item: Any?) -> UITableViewCell {
        guard let cell = treeView.dequeueReusableCell(withIdentifier: String(describing: BookShelfTreeViewCell.self)) as? BookShelfTreeViewCell,
            let item = item as? BookShelfRATreeViewCellData else {
                fatalError()
        }
        
        let level = treeView.levelForCell(forItem: item)

        RealmUtil.RealmBlock { (realm) -> Void in
            if let novelID = item.novelID, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                let likeLevel = RealmGlobalState.GetInstanceWith(realm: realm)?.calcLikeLevel(novelID: novelID) ?? 0
                cell.cellSetup(novel: novel, treeLevel: level, likeLevel: likeLevel)
            }else if let title = item.title {
                func getChildNovelIDs(itemArray:[BookShelfRATreeViewCellData]) -> [String] {
                    var childrenArray:[String] = []
                    for child in itemArray {
                        if let novelID = child.novelID {
                            childrenArray.append(novelID)
                        }else if let childrens = child.childrens{
                            childrenArray.append(contentsOf: getChildNovelIDs(itemArray: childrens))
                        }
                    }
                    return childrenArray
                }
                let childrenIDArray:[String]
                if let childrens = item.childrens {
                    childrenIDArray = getChildNovelIDs(itemArray: childrens)
                }else{
                    childrenIDArray = []
                }
                cell.cellSetup(title: title, treeLevel: level, watchNovelIDArray: childrenIDArray)
            }
        }
        
        return cell
    }
    
    func treeView(_ treeView: RATreeView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            // item == nil なら一番上ということ
            return self.displayDataArray[index]
        } else if let item = item as? BookShelfRATreeViewCellData {
            if let childrens = item.childrens {
                return childrens[index]
            }
            fatalError()
        } else {
            fatalError()
        }
    }
    
    /// セルが選択された時
    func treeView(_ treeView: RATreeView, didSelectRowForItem item: Any) {
        if let data = item as? BookShelfRATreeViewCellData {
            if let novelID = data.novelID {
                // currentReadingNovelID の小説を開いた(最後に開いていた小説を開いた)なら、
                // updateReadDate は呼ばないで良いという事にします。
                let currentReadingNovelID:String = RealmUtil.RealmBlock { (realm) -> String in
                    guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return "" }
                    return globalState.currentReadingNovelID
                }
                pushNextView(novelID: novelID, isNeedSpeech: false, isNeedUpdateReadDate: currentReadingNovelID != novelID)
            }
        }
    }

    func treeView(_ treeView: RATreeView, canEditRowForItem item: Any) -> Bool {
        return RealmUtil.RealmBlock { (realm) -> Bool in
            if let data = item as? BookShelfRATreeViewCellData {
                if let novelID = data.novelID {
                    let likeLevel = RealmGlobalState.GetInstanceWith(realm: realm)?.calcLikeLevel(novelID: novelID) ?? 0
                    return likeLevel <= 0
                }
            }
            return false
        }
    }
    
    func treeView(_ treeView: RATreeView, didExpandRowForItem item: Any) {
        self.checkAndUpdateSwitchFolderButtonImage()
    }
    
    func treeView(_ treeView: RATreeView, didCollapseRowForItem item: Any) {
        self.checkAndUpdateSwitchFolderButtonImage()
    }

    func reloadAllAndReopenCells() {
        var expandedFolderList:[BookShelfRATreeViewCellData] = []
        let visibleCells = self.treeView?.visibleCells()
        for data in self.displayDataArray {
            if let childrens = data.childrens, childrens.count > 0 {
                if self.treeView?.isCell(forItemExpanded: data) ?? false {
                    expandedFolderList.append(data)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.reloadAllData {
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.0) {
                        for data in expandedFolderList {
                            self.treeView?.expandRow(forItem: data, with: RATreeViewRowAnimationNone)
                        }
                    } completion: { (result) in
                        if let data = visibleCells?.first as? BookShelfRATreeViewCellData {
                            print("scroll to: \(data.title ?? "-")")
                            self.treeView?.scrollToRow(forItem: data, at: RATreeViewScrollPositionTop, animated: true)
                        }
                    }
                }
            }
        }
    }

    func deleteNovel(item: Any, novelID: String) {
        DispatchQueue.main.async {
            NiftyUtility.EasyDialogNoButton(
                viewController: self,
                title: NSLocalizedString("BookShelfRATreeViewController_NovelDeletingTitle", comment: "小説を削除しています……"),
                message: nil,
                completion: { (dialog) in
                DispatchQueue.main.async {
                    RealmUtil.Write(withoutNotifying: [self.novelArrayNotificationToken]) { (realm) in
                        if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                            novel.delete(realm: realm)
                        }
                    }
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            let parent = self.treeView?.parent(forItem: item)
                            if let parent = parent as? BookShelfRATreeViewCellData, let childrens = parent.childrens {
                                for (idx, cellData) in childrens.enumerated() {
                                    if let thisNovelID = cellData.novelID, novelID == thisNovelID {
                                        self.treeView?.deleteItems(at: IndexSet([idx]), inParent: parent, with: RATreeViewRowAnimationFade)
                                        break
                                    }
                                }
                            }else{
                                for (idx, cellData) in self.displayDataArray.enumerated() {
                                    if let thisNovelID = cellData.novelID, novelID == thisNovelID {
                                        self.treeView?.deleteItems(at: IndexSet([idx]), inParent: parent, with: RATreeViewRowAnimationFade)
                                        break
                                    }
                                }
                            }
                            self.reloadAllAndReopenCells()
                        }
                    }
                }
            })
        }
    }

    // 削除されたりした時に呼ばれるぽい
    func treeView(_ treeView: RATreeView, commit editingStyle: UITableViewCell.EditingStyle, forRowForItem item: Any) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            guard let data = item as? BookShelfRATreeViewCellData, let novelID = data.novelID else { return }
            let title:String
            if let titleString = data.title {
                title = titleString
            }else{
                title = "-"
            }
            RealmUtil.RealmBlock { (realm) -> Void in
                if RealmGlobalState.GetInstanceWith(realm: realm)?.IsNeedConfirmDeleteBook ?? false {
                    NiftyUtility.EasyDialogTwoButton(viewController: self, title: NSLocalizedString("BookShelfTableViewController_WarningForDeleteBookTitle", comment: "本の削除"), message: NSLocalizedString("BookShelfTableViewController_WarningDeleteBookMessage", comment: "本を削除しますか？\n") + title, button1Title: nil, button1Action: nil, button2Title: NSLocalizedString("BookShelfTableViewController_WarningDeleteBookOKButtonTitle", comment: "削除"), button2Action: {
                        self.deleteNovel(item: item, novelID: novelID)
                    })
                }else{
                    deleteNovel(item: item, novelID: novelID)
                }
            }
        }
        else if editingStyle == UITableViewCell.EditingStyle.insert {
            print("editingStyle == .insert")
        }
    }
    
    // cell の高さを求められる時に呼ばれる
    func treeView(_ treeView: RATreeView, heightForRowForItem item: Any) -> CGFloat {
        let fontForFontSize = UIFont.preferredFont(forTextStyle: .body)
        return fontForFontSize.lineHeight + 10.5 + 12
    }
    func treeView(_ treeView: RATreeView, estimatedHeightForRowForItem item: Any) -> CGFloat {
        let fontForFontSize = UIFont.preferredFont(forTextStyle: .body)
        return fontForFontSize.lineHeight + 10.5 + 12
    }

    #if !targetEnvironment(macCatalyst)
    @objc func refreshControlValueChangedEvent(sendor:UIRefreshControl) {
        sendor.endRefreshing()
        DispatchQueue.global(qos: .background).async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novels = RealmNovel.GetAllObjectsWith(realm: realm)?.filter("isNotNeedUpdateCheck = false") else { return }
                NovelDownloadQueue.shared.addQueueArray(novelArray: ThreadSafeReference(to: novels))
            }
        }
    }
    #endif

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if let floatingButton = self.resumeSpeechFloatingButton {
            let isEnd = floatingButton.scrollViewDidScroll(scrollView)
            if isEnd {
                self.resumeSpeechFloatingButton = nil
            }
        }
    }
    
    func addPreviousNovelSpeakButtonIfNeeded(){
        RealmUtil.RealmBlock { (realm) -> Void in
            if RealmGlobalState.GetInstanceWith(realm: realm)?.isOpenRecentNovelInStartTime ?? true {
                return
            }

            guard let lastReadStory = RealmGlobalState.GetLastReadStory(realm: realm), let lastReadNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: lastReadStory.novelID) else {
                return
            }
            if let storyCount = lastReadNovel.lastChapterNumber, lastReadStory.chapterNumber >= storyCount && (lastReadStory.readLocation(realm: realm) + 5) >= lastReadStory.content.lengthOfBytes(using: .utf8) {
                return
            }
            let lastReadNovelID = lastReadNovel.novelID
            let lastReadNovelTitle = lastReadNovel.title

            if let oldFloatingButton = self.resumeSpeechFloatingButton {
                oldFloatingButton.hide()
                self.resumeSpeechFloatingButton = nil
            }
            self.resumeSpeechFloatingButton = FloatingButton.createNewFloatingButton()
            guard let floatingButton = self.resumeSpeechFloatingButton else {
                return
            }
            
            floatingButton.assignToView(view: (self.treeView?.scrollView)!, currentOffset: self.treeView?.scrollView.contentOffset ?? CGPoint(x: -1, y: -1), text: String(format: NSLocalizedString("BookShelfTableViewController_Resume:", comment: "再生:%@"), lastReadNovelTitle), animated: true) {
                floatingButton.hideAnimate()
                self.resumeSpeechFloatingButton = nil
                if ActivityIndicatorManager.isEnable(id: NovelSpeakerUtility.GetLongLivedOperationIDWatcherID()) {
                    DispatchQueue.main.async {
                        let lock = NSLock()
                        var isDismiss:Bool = false
                        let dialog = NiftyUtility.EasyDialogBuilder(self)
                            .text(content: NSLocalizedString("BookShelfRATreeViewController_WaitingiCloudSync_Message", comment: "iCloud上のデータ同期を待っています。\n同期が完了した場合、自動で再生を開始します。(なお、完了判定は失敗する事があります)"))
                            .addButton(title: NSLocalizedString("BookShelfRATreeViewController_WaitingiCloudSync_DismissButton", comment: "同期を待たずに再生を開始する")) { (dialog) in
                                lock.lock()
                                defer { lock.unlock() }
                                if isDismiss == true { return }
                                isDismiss = true
                                dialog.dismiss(animated: false) {
                                    self.pushNextView(novelID: lastReadNovelID, isNeedSpeech: true, isNeedUpdateReadDate: false)
                                }
                            }.addButton(title: NSLocalizedString("BookShelfRATreeViewController_WaitingiCloudSync_CancelButton", comment: "再生をキャンセルする")) { (dialog) in
                                lock.lock()
                                defer { lock.unlock() }
                                if isDismiss == true { return }
                                isDismiss = true
                                dialog.dismiss(animated: true, completion: nil)
                            }.build()
                        dialog.show()
                        func syncWatcher() {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                                lock.lock()
                                defer { lock.unlock() }
                                guard let self = self, isDismiss == false else { return }
                                if ActivityIndicatorManager.isEnable(id: NovelSpeakerUtility.GetLongLivedOperationIDWatcherID()) {
                                    syncWatcher()
                                    return
                                }
                                isDismiss = true
                                dialog.dismiss(animated: false) {
                                    self.pushNextView(novelID: lastReadNovelID, isNeedSpeech: true, isNeedUpdateReadDate: false)
                                }
                            }
                        }
                        syncWatcher()
                    }
                }else{
                    self.pushNextView(novelID: lastReadNovelID, isNeedSpeech: true, isNeedUpdateReadDate: false)
                }
            }
        }
    }

    func HighlightNovel(novelID:String) {
        DispatchQueue.global(qos: .userInitiated).async {
            for cellItem in self.displayDataArray {
                // tree が展開されるのは一段目までです(´・ω・`)
                if let childrens = cellItem.childrens {
                    for cellItemChild in childrens {
                        if cellItemChild.novelID == novelID {
                            DispatchQueue.main.async {
                                self.treeView?.beginUpdates()
                                self.treeView?.expandRow(forItem: cellItem)
                                self.treeView?.selectRow(forItem: cellItemChild, animated: false, scrollPosition: RATreeViewScrollPositionNone)
                                self.treeView?.endUpdates()
                                self.setExpandIcon()
                            }
                            return
                        }
                    }
                }
                if cellItem.novelID == novelID {
                    DispatchQueue.main.async {
                        //self.treeView?.beginUpdates()
                        self.treeView?.selectRow(forItem: cellItem, animated: false, scrollPosition: RATreeViewScrollPositionNone)
                        //self.treeView?.endUpdates()
                        self.checkAndUpdateSwitchFolderButtonImage()
                    }
                    return
                }
            }
        }
    }
    func HilightCurrentReadingNovel() {
        let novelID:String? = RealmUtil.RealmBlock { (realm) -> String? in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return nil }
            return globalState.currentReadingNovelID
        }
        guard let targetNovelID = novelID else { return }
        HighlightNovel(novelID: targetNovelID)
    }
    
    static func LoadWebPageOnWebImportTab(url:URL) {
        BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        return
        guard let instance = instance else { return }
        DispatchQueue.main.async {
            /// XXX TODO: 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
            let targetTabIndex = 2
            guard let viewController = instance.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController else { return }
            viewController.load(url: url)
            instance.tabBarController?.selectedIndex = targetTabIndex
        }
    }
    static func ReloadWebPageOnWebImportTab() {
        BookShelfTreeViewController.ReloadWebPageOnWebImportTab()
        return
        guard let instance = instance else { return }
        DispatchQueue.main.async {
            /// XXX TODO: 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
            let targetTabIndex = 2
            guard let viewController = instance.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController else { return }
            viewController.reloadWebView()
        }
    }
    static func OpenNovelOnBookShelf(novelID:String){
        BookShelfTreeViewController.OpenNovelOnBookShelf(novelID: novelID)
        return
        guard let instance = instance else { return  }
        DispatchQueue.main.async {
            return RealmUtil.RealmBlock { realm in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
                let targetTabIndex = 0
                guard let navigationController = instance.tabBarController?.viewControllers?[targetTabIndex] as? UINavigationController, let bookShelfTreeViewController = navigationController.viewControllers.first as? BookShelfRATreeViewController else {
                    return
                }
                navigationController.popToRootViewController(animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute:{
                    bookShelfTreeViewController.pushNextView(novelID: novelID, isNeedSpeech: false, isNeedUpdateReadDate: true)
                    instance.tabBarController?.selectedIndex = targetTabIndex
                })
            }
        }
    }
    
    func treeView(_ treeView: RATreeView, shouldExpandRowForItem item: Any) -> Bool {
        if let cellNode = item as? BookShelfRATreeViewCellData {
            return cellNode.childrens != nil
        }
        print("shouldExpandRowForItem unknown item got.")
        return false
    }
}
