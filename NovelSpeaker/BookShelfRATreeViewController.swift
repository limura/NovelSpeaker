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

class BookShelfRATreeViewController: UIViewController, RATreeViewDataSource, RATreeViewDelegate, UIScrollViewDelegate {

    var displayDataArray : [BookShelfRATreeViewCellData] = [];
    var treeView:RATreeView?
    var searchText:String? = nil
    var searchButton:UIBarButtonItem = UIBarButtonItem()
    var resumeSpeechFloatingButton:FloatingButton? = nil
    var nextViewStoryID: String?
    var isNextViewNeedResumeSpeech:Bool = false
    
    var novelArrayNotificationToken : NotificationToken? = nil
    
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
        treeView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8).isActive = true
        treeView.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: 8).isActive = true
        treeView.rightAnchor.constraint(equalTo: guide.rightAnchor, constant: 8).isActive = true
        treeView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: 8).isActive = true
        treeView.translatesAutoresizingMaskIntoConstraints = false
        treeView.estimatedRowHeight = 44
        treeView.rowHeight = UITableView.automaticDimension
        self.treeView = treeView
        
        // このタイミングで StorySpeaker のインスタンスを作っておきます。
        // Realm observe が走るので、main thread で作っておかねばならぬらしい(´・ω・`)
        _ = StorySpeaker.shared
        
        self.title = NSLocalizedString("BookShelfRATreeViewController_Title", comment: "本棚")
        
        // 編集ボタン等を配置
        let refreshButton = UIBarButtonItem.init(barButtonSystemItem: UIBarButtonItem.SystemItem.refresh, target: self, action: #selector(refreshButtonClicked))
        let sortTypeSelectButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SortTypeSelectButton", comment: "sort"), style: UIBarButtonItem.Style.done, target: self, action: #selector(sortTypeSelectButtonClicked))
        self.navigationItem.rightBarButtonItems = [self.editButtonItem, refreshButton, sortTypeSelectButton]
        self.searchButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索"), style: .done, target: self, action: #selector(searchButtonClicked))
        self.navigationItem.leftBarButtonItems = [self.searchButton]

        if NiftyUtilitySwift.IsVersionUped() {
            showVersionUpNotice()
            NiftyUtilitySwift.UpdateCurrentVersionSaveData()
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm), let novel = RealmGlobalState.GetLastReadNovel(realm: realm), globalState.isOpenRecentNovelInStartTime {
                self.pushNextView(novelID: novel.novelID, isNeedSpeech: false)
            }
        }
        reloadAllDataAndScrollToCurrentReadingContent()
        
        NiftyUtilitySwift.CheckNewImportantImformation(hasNewInformationAlive: { (text) in
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
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshControlValueChangedEvent), for: .valueChanged)
        treeView.scrollView.addSubview(refreshControl)
        registObserver()
        registNotificationCenter()

        autoreleasepool {
            view.layoutIfNeeded()
        }
    }
    
    deinit {
        self.unregistNotificationCenter()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.HilightCurrentReadingNovel()
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
    
    func registObserver() {
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
                            return
                        }
                    }
                    RealmUtil.RealmBlock { (realm) -> Void in
                        if modifications.count > 0, let sortType = RealmGlobalState.GetInstanceWith(realm: realm)?.bookShelfSortType, sortType == .lastReadDate {
                            let gapDate = Date(timeIntervalSinceNow: -5) // 5秒前までなら今書き変わったと思い込む
                            for index in modifications {
                                if objects.count > index {
                                    let obj = objects[index]
                                    if obj.lastReadDate > gapDate {
                                        if let novelID = self.displayDataArray.first?.novelID, novelID == obj.novelID {
                                            // 既に先頭がその小説なら表示しなおす必要は無い
                                            continue
                                        }
                                        self.reloadAllData()
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

    // 検索条件やソート条件を考慮した上での NarouContent の Array を返します
    func getNovelArray(realm: Realm, sortType:NarouContentSortType) -> [RealmNovel]? {
        guard var allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return nil }
        if let searchText = self.searchText, searchText.count > 0 {
            allNovels = allNovels.filter("title CONTAINS %@ OR writer CONTAINS %@", searchText, searchText)
        }
        switch sortType {
        case .ncode:
            return Array(allNovels.sorted(byKeyPath: "novelID", ascending: true))
        case .novelUpdatedAtWithFolder:
            fallthrough
        case .novelUpdatedAt:
            return Array(allNovels.sorted(byKeyPath: "lastDownloadDate", ascending: false))
        case .lastReadDate:
            return Array(allNovels.sorted(byKeyPath: "lastReadDate", ascending: false))
        case .writer:
            return Array(allNovels.sorted(byKeyPath: "writer", ascending: false))
        case .title:
            fallthrough
        case .selfCreatedBookshelf:
            fallthrough
        case .keywordTag:
            fallthrough
        @unknown default:
            return Array(allNovels.sorted(byKeyPath: "title", ascending: false))
        }
    }
    
    // 単純な本棚データの作成
    func createSimpleBookShelfRATreeViewCellDataTree(sortType:NarouContentSortType) -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            guard let novels = getNovelArray(realm: realm, sortType: sortType) else { return [] }
            var result:[BookShelfRATreeViewCellData] = []
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return result
        }
    }
    
    // 更新日時でフォルダ分けします(フォルダ分けする版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithFolder() -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.novelUpdatedAt) else { return [] }
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
                for novel in novels {
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
            return result
        }
    }

    // 更新日時でフォルダ分けします(フォルダ分けしない版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.novelUpdatedAt) else { return [] }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return result
        }
    }

    // 作者名でフォルダ分けします
    func createWriterBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.title) else { return [] }
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
                    for novel in novels {
                        let data = BookShelfRATreeViewCellData()
                        data.novelID = novel.novelID
                        data.title = novel.title
                        folder.childrens?.append(data)
                    }
                }
                result.append(folder)
            }
            return result
        }
    }
    
    // 自作のフォルダでフォルダ分けします
    func createBookShelfTagBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.title), let tags = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Bookshelf) else { return [] }
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            for tag in tags {
                guard let novels = tag.targetNovelArrayWith(realm: realm) else { continue }
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
            return result
        }
    }
    
    // キーワード(Tag)でフォルダ分けします
    func createBookShelfKeywordTagRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            // ２つ以上の小説が登録されていないタグは無視します。
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.title), let tags = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Keyword)?.filter({ (tag) -> Bool in
                return tag.targetNovelIDArray.count >= 2
            }) else { return [] }
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            for tag in tags {
                guard let novels = tag.targetNovelArrayWith(realm: realm) else { continue }
                let folder = BookShelfRATreeViewCellData()
                folder.childrens = [BookShelfRATreeViewCellData]()
                folder.title = tag.name
                for novel in novels {
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
            return result
        }
    }

    // 小説を開いた日時でフォルダ分けします(フォルダ分けしない版)
    func createLastReadDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> [BookShelfRATreeViewCellData] {
        return RealmUtil.RealmBlock { (realm) -> [BookShelfRATreeViewCellData] in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.lastReadDate) else { return [] }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = novel.title
                result.append(data)
            }
            return result
        }
    }
    
    func getBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        var sortType:NarouContentSortType = .title
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            sortType = globalState.bookShelfSortType
        }
        switch sortType {
        case .ncode: fallthrough
        case .title:
            return createSimpleBookShelfRATreeViewCellDataTree(sortType: sortType)
        case .novelUpdatedAtWithFolder:
            return createUpdateDateBookShelfRATreeViewCellDataTreeWithFolder()
        case .novelUpdatedAt:
            return createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder()
        case .lastReadDate:
            return createLastReadDateBookShelfRATreeViewCellDataTreeWithoutFolder()
        case .writer:
            return createWriterBookShelfRATreeViewCellDataTree()
        case .selfCreatedBookshelf:
            return createBookShelfTagBookShelfRATreeViewCellDataTree()
        case .keywordTag:
            return createBookShelfKeywordTagRATreeViewCellDataTree()
        default:
            break
        }
        return createSimpleBookShelfRATreeViewCellDataTree(sortType: NarouContentSortType.title)
    }
    
    func scrollToCurrentReadingContent() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let lastReadNovel = RealmGlobalState.GetLastReadNovel(realm: realm) else { return }
                let novelID = lastReadNovel.novelID
                UIView.animate(withDuration: 0.3, animations: {
                    for cellItem in self.displayDataArray {
                        // tree が展開されるのは一段目までです(´・ω・`)
                        if let childrens = cellItem.childrens {
                            for cellItemChild in childrens {
                                if cellItemChild.novelID == novelID {
                                    self.treeView?.expandRow(forItem: cellItem)
                                    self.treeView?.scrollToRow(forItem: cellItem, at: RATreeViewScrollPositionTop, animated: false)
                                    return
                                }
                            }
                        }
                        if cellItem.novelID == novelID {
                            self.treeView?.scrollToRow(forItem: cellItem, at: RATreeViewScrollPositionTop, animated: false)
                            return
                        }
                    }
                }, completion: { (finished) in
                    self.addPreviousNovelSpeakButtonIfNeeded()
                })
            }
        }
    }
    
    func reloadAllData() {
        self.displayDataArray = getBookShelfRATreeViewCellDataTree()
        self.treeView?.reloadData()
    }

    func reloadAllDataAndScrollToCurrentReadingContent(){
        reloadAllData()
        scrollToCurrentReadingContent()
    }

    func showVersionUpNotice(){
        NiftyUtilitySwift.EasyDialogBuilder(self)
            .title(title: NSLocalizedString("BookShelfTableViewController_AnnounceNewViersion", comment: "アップデートされました"))
            .textView(content: NSLocalizedString("BookShelfTableViewController_AnnounceNewVersionMessage", comment: "Version 1.1.2\r\n..."), heightMultiplier: 0.63)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                dialog.dismiss(animated: true, completion: nil)
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                    if globalState.isOpenRecentNovelInStartTime {
                        if let lastReadNovel = RealmGlobalState.GetLastReadNovel(realm: realm) {
                            self.pushNextView(novelID: lastReadNovel.novelID, isNeedSpeech: false)
                        }
                    }
                }
            })
            .build().show()
    }

    @objc func refreshButtonClicked(sender: Any) {
        DispatchQueue.global(qos: .background).async {
            RealmUtil.Write { (realm) -> Void in
                guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
                NovelDownloadQueue.shared.addQueueArray(realm: realm, novelArray: novels)
            }
        }
    }

    func getDisplayStringToSortTypeDictionary() -> [String:NarouContentSortType]{
        return [
            //NSLocalizedString("BookShelfTableViewController_SortTypeNcode", comment: "Ncode順"): NarouContentSortType.ncode
            NSLocalizedString("BookShelfTableViewController_SortTypeWriter", comment: "作者名順"): NarouContentSortType.writer
            , NSLocalizedString("BookShelfTableViewController_SortTypeNovelName", comment: "小説名順"): NarouContentSortType.title
            , NSLocalizedString("BookShelfTableViewController_SortTypeUpdateDate", comment: "更新順"): NarouContentSortType.novelUpdatedAt
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeBookshelf", comment: "自作フォルダ順"): NarouContentSortType.selfCreatedBookshelf
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeKeywardTag", comment: "タグ名順"): NarouContentSortType.keywordTag
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeUpdateDateWithFilder", comment: "最終ダウンロード順(フォルダ分類版)"): NarouContentSortType.novelUpdatedAtWithFolder
            , NSLocalizedString("BookShelfRATreeViewController_StoryTypeLastReadDate", comment: "小説を開いた日時順"): NarouContentSortType.lastReadDate
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
        return NarouContentSortType.novelUpdatedAt
    }
    
    @objc func sortTypeSelectButtonClicked(sender:Any) {
        let targetView = self.view
        let dialog = PickerViewDialog.createNewDialog(
            getDisplayStringToSortTypeDictionary().map({ (arg0) -> String in
                let (key, _) = arg0
                return key
            }).sorted(by: { (a:String, b:String) -> Bool in
                a < b
            }),
            firstSelectedString: getCurrentSortTypeDisplayString(), parentView: targetView) { (selectedText) in
                guard let selectedText = selectedText else { return }
                let sortType = self.convertDisplayStringToSortType(key: selectedText)
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            globalState.bookShelfSortType = sortType
                        }
                    }
                }
                self.reloadAllData()
        }
        dialog?.popup(nil)
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
            NiftyUtilitySwift.EasyDialogBuilder(parent)
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
            }
        }
    }
    func showNovelInformation(novelID:String) {
        let nextViewController = NovelDetailViewController()
        nextViewController.novelID = novelID
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }
    
    // 次のビューに飛ばします。
    func pushNextView(novelID:String, isNeedSpeech: Bool){
        RealmUtil.RealmBlock { (realm) -> Void in
            NovelDownloader.flushWritePool(novelID: novelID)
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            guard let story = novel.readingChapterWith(realm: realm) ?? novel.firstChapterWith(realm: realm) else {
                let targetChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: novel.m_readingChapterStoryID)
                guard let novelCount = novel.linkedStorysWith(realm: realm)?.count, novelCount > 0 else {
                    if novel.type == .URL {
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogForButton(
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
                        NiftyUtilitySwift.EasyDialogTwoButton(
                            viewController: self,
                            title: nil,
                            message: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber", comment: "読み上げ位置がダウンロードされていない章を示しています。この小説の追加の章のダウンロードを試みますか？"),
                            button1Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OpenFirstStory", comment: "最初の章を開く"),
                            button1Action: {
                                RealmUtil.RealmBlock { (realm) -> Void in
                                    if let nextViewStoryID = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.firstChapterWith(realm: realm)?.storyID {
                                        self.nextViewStoryID = nextViewStoryID
                                        self.isNextViewNeedResumeSpeech = isNeedSpeech
                                        self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
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
                    nextViewStoryID = story.storyID
                    print("sendStoryID: \(nextViewStoryID ?? "unknown"), story.chapterNumber \(story.chapterNumber)")
                    self.isNextViewNeedResumeSpeech = isNeedSpeech
                    self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
                }
                return
            }
            nextViewStoryID = story.storyID
            self.isNextViewNeedResumeSpeech = isNeedSpeech
            self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
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
        var headSpace = ""
        if level > 0 {
            for _ in 1 ... level {
                headSpace += "   "
            }
        }

        RealmUtil.RealmBlock { (realm) -> Void in
            if let novelID = item.novelID, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                cell.cellSetup(title: novel.title, treeLevel: level, watchNovelIDArray: [novelID])
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
                pushNextView(novelID: novelID, isNeedSpeech: false)
            }
        }
    }

    func treeView(_ treeView: RATreeView, canEditRowForItem item: Any) -> Bool {
        return RealmUtil.RealmBlock { (realm) -> Bool in
            if let data = item as? BookShelfRATreeViewCellData {
                if let novelID = data.novelID, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                    return novel.likeLevel <= 0
                }
            }
            return false
        }
    }
    
    func deleteNovel(item: Any, novelID: String) {
        let parent = self.treeView?.parent(forItem: item)
        var isNeedReload:Bool = false
        var expandedItemList:[BookShelfRATreeViewCellData] = []
        if parent == nil {
            // parent が居ない場合は一つだけしか無いはずなので普通に消して良い
            for (idx, cellData) in self.displayDataArray.enumerated() {
                if let thisNovelID = cellData.novelID, thisNovelID == novelID {
                    self.treeView?.deleteItems(at: IndexSet([idx]), inParent: parent, with: RATreeViewRowAnimationFade)
                    self.displayDataArray.remove(at: idx)
                    break
                }
            }
        }else if let _ = parent as? BookShelfRATreeViewCellData{
            // parent があるということはフォルダ分けされているので削除対象が複数のフォルダ内にある可能性があるため、
            // データを消して再度フォルダ分けからやり直す必要がある
            isNeedReload = true
            for item in self.displayDataArray {
                if let treeView = self.treeView, let cell = treeView.cell(forItem: item), treeView.isCellExpanded(cell) {
                    expandedItemList.append(item)
                }
            }
        }
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogNoButton(
                viewController: self,
                title: NSLocalizedString("BookShelfRATreeViewController_NovelDeletingTitle", comment: "小説を削除しています……"),
                message: nil,
                completion: { (dialog) in
                DispatchQueue.global(qos: .utility).async {
                    RealmUtil.Write { (realm) in
                        if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                            novel.delete(realm: realm)
                        }
                    }
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                        if isNeedReload, let treeView = self.treeView {
                            self.reloadAllData()
                            for currentItem in self.displayDataArray {
                                for item in expandedItemList {
                                    if let currentItemTitle = currentItem.title, let itemTitle = item.title, currentItemTitle == itemTitle {
                                        treeView.expandRow(forItem: currentItem)
                                    }
                                }
                            }
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
                    NiftyUtilitySwift.EasyDialogTwoButton(viewController: self, title: NSLocalizedString("BookShelfTableViewController_WarningForDeleteBookTitle", comment: "本の削除"), message: NSLocalizedString("BookShelfTableViewController_WarningDeleteBookMessage", comment: "本を削除しますか？\n") + title, button1Title: nil, button1Action: nil, button2Title: NSLocalizedString("BookShelfTableViewController_WarningDeleteBookOKButtonTitle", comment: "削除"), button2Action: {
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


    // TODO: なにやら昔色々やっていたものを今でも使えるようにできるといいね(´・ω・`)
    // ncodeのものが追加されたと仮定して RATreeView の状態を更新する
    func handleAddNovel(novelID:String) {
        func dumpCurrentTree(head:[BookShelfRATreeViewCellData], level: Int){
            var spacer = ""
            for _ in 0...level{
                spacer += "  "
            }
            for cell in head {
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let childrens = cell.childrens {
                        print("\(spacer)\(cell.title ?? "??")")
                        dumpCurrentTree(head: childrens, level: level + 1)
                    }else if let novelID = cell.novelID, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID){
                        print("\(spacer)\(novel.title)")
                    }else{
                        print("\(spacer)\(cell.title ?? "??")")
                    }
                }
            }
        }
        
        //print("before:")
        //dumpCurrentTree(head: self.displayDataArray, level: 0)
        let newDisplayDataArray = getBookShelfRATreeViewCellDataTree()
        for (idx, cellData) in newDisplayDataArray.enumerated() {
            if let thisNovelID = cellData.novelID {
                if thisNovelID == novelID {
                    // toplevel なら単にその新しく出来た cellData を insert するだけで良い
                    self.displayDataArray.insert(cellData, at: idx)
                    self.treeView?.insertItems(at: [idx], inParent: nil, with: RATreeViewRowAnimationFade)
                    print("insert top/[\(idx)]")
                    return
                }
            }else if let childrens = cellData.childrens {
                for (childIdx, childCellData) in childrens.enumerated() {
                    if let thisNovelID = childCellData.novelID {
                        if thisNovelID == novelID {
                            //self.treeView?.beginUpdates()
                            var parent = cellData
                            // toplevel ではない場合、もしかするとtoplevelのcellDataもinsertする必要があるかもしれないので、childrens.count が 1 であることでそれを確認する
                            if childrens.count == 1 {
                                self.displayDataArray.insert(cellData, at: idx)
                                // TODO: 本来ならこの後insertしていくといいのだが、
                                // 2017/12/16 時点での RATreeView(version 2.1.2?) では、
                                // 追加するcellよりも上に、追加されるcellよりもlevelの低い(数字の大きい)cellが開いていた場合に insertItems がうまく動かない
                                // という問題を抱えている (issue として追加してみた https://github.com/Augustyniak/RATreeView/issues/248 )
                                // ので、このまま reloadAllData() して終わりとする。
                                self.reloadAllData()
                                return
                                //print("displayDataArray.insert(\(cellData.title ?? "??"), at: \(idx))")
                                //dumpCurrentTree(head: self.displayDataArray, level: 0)
                                //self.treeView?.insertItems(at: [idx], inParent: nil, with: RATreeViewRowAnimationFade)
                            }else{
                                // childrens.count が 1 でないのなら、oldDisplayDataArray[idx] に parent が居るはず
                                self.displayDataArray[idx].childrens?.insert(childCellData, at: childIdx)
                                parent = self.displayDataArray[idx]
                            }
                            //print("after:")
                            //dumpCurrentTree(head: self.displayDataArray, level: 0)
                            self.treeView?.insertItems(at: [childIdx], inParent: parent, with: RATreeViewRowAnimationFade)
                            //print("insert top[\(idx)]/\(parent.title ?? "??"),\(cellData.title ?? "??")[\(childIdx)]/\(childCellData.title ?? "??")")
                            //self.treeView?.endUpdates()
                            return
                        }
                    }
                }
            }
        }
        print("handleAddNovel nothing to do...")
    }

    @objc func refreshControlValueChangedEvent(sendor:UIRefreshControl) {
        sendor.endRefreshing()
        DispatchQueue.global(qos: .background).async {
            RealmUtil.Write { (realm) -> Void in
                guard let novels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
                NovelDownloadQueue.shared.addQueueArray(realm: realm, novelArray: novels)
            }
        }
    }

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
            
            floatingButton.assignToView(view: (self.treeView?.scrollView)!, text: String(format: NSLocalizedString("BookShelfTableViewController_Resume:", comment: "再生:%@"), lastReadNovelTitle), animated: true) {
                self.pushNextView(novelID: lastReadNovelID, isNeedSpeech: true)
                floatingButton.hideAnimate()
            }
        }
    }

    func HighlightNovel(novelID:String) {
        DispatchQueue.main.async {
            for cellItem in self.displayDataArray {
                // tree が展開されるのは一段目までです(´・ω・`)
                if let childrens = cellItem.childrens {
                    for cellItemChild in childrens {
                        if cellItemChild.novelID == novelID {
                            self.treeView?.expandRow(forItem: cellItem)
                            self.treeView?.selectRow(forItem: cellItem, animated: false, scrollPosition: RATreeViewScrollPositionNone)
                            return
                        }
                    }
                }
                if cellItem.novelID == novelID {
                    self.treeView?.selectRow(forItem: cellItem, animated: false, scrollPosition: RATreeViewScrollPositionNone)
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
        guard let instance = instance else { return }
        DispatchQueue.main.async {
            /// XXX TODO: 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
            let targetTabIndex = 2
            guard let viewController = instance.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController else { return }
            viewController.openTargetUrl = url
            instance.tabBarController?.selectedIndex = targetTabIndex
        }
    }
}
