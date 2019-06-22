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

    override func viewDidLoad() {
        super.viewDidLoad()

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
        self.treeView = treeView
        
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
        autoreleasepool {
            if let globalState = RealmGlobalState.GetInstance(), let novel = RealmGlobalState.GetLastReadNovel(), globalState.isOpenRecentNovelInStartTime {
                self.pushNextView(novelID: novel.novelID, isNeedSpeech: false)
            }
        }
        reloadAllDataAndScrollToCurrentReadingContent()
        
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
        autoreleasepool {
            guard let novelArray = RealmNovel.GetAllObjects() else { return }
            novelArrayNotificationToken = novelArray.observe { (change) in
                switch change {
                case .initial(_):
                    break
                case .update(_, let deletions, let insertions, _):
                    if deletions.count > 0 || insertions.count > 0 {
                        DispatchQueue.main.async {
                            self.reloadAllData()
                        }
                    }
                case .error(_):
                    break
                }
            }
        }
    }

    // 検索条件やソート条件を考慮した上での NarouContent の Array を返します
    func getNovelArray(sortType:NarouContentSortType) -> [RealmNovel]? {
        guard var allNovels = RealmNovel.GetAllObjects() else { return nil }
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
        return autoreleasepool {
            guard let novels = getNovelArray(sortType: sortType) else { return [] }
            var result:[BookShelfRATreeViewCellData] = []
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = nil
                result.append(data)
            }
            return result
        }
    }
    
    // 更新日時でフォルダ分けします(フォルダ分けする版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithFolder() -> [BookShelfRATreeViewCellData] {
        return autoreleasepool {
            guard let novels = getNovelArray(sortType: NarouContentSortType.novelUpdatedAt) else { return [] }
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
        return autoreleasepool {
            guard let novels = getNovelArray(sortType: NarouContentSortType.novelUpdatedAt) else { return [] }
            var result = [] as [BookShelfRATreeViewCellData]
            for novel in novels {
                let data = BookShelfRATreeViewCellData()
                data.childrens = nil
                data.novelID = novel.novelID
                data.title = nil
                result.append(data)
            }
            return result
        }
    }

    // 作者名でフォルダ分けします
    func createWriterBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        return autoreleasepool {
            guard let novels = getNovelArray(sortType: NarouContentSortType.writer) else { return [] }
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
        return autoreleasepool {
            guard let novels = getNovelArray(sortType: NarouContentSortType.writer), let tags = RealmNovelTag.GetObjectsFor(type: RealmNovelTag.TagType.Bookshelf) else { return [] }
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            for tag in tags {
                guard let novels = tag.targetNovelArray else { continue }
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
    
    // キーワード(Tag)でフォルダ分けします
    func createBookShelfKeywordTagRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        return autoreleasepool {
            guard let novels = getNovelArray(sortType: NarouContentSortType.writer), let tags = RealmNovelTag.GetObjectsFor(type: RealmNovelTag.TagType.Keyword) else { return [] }
            var result = [BookShelfRATreeViewCellData]()
            var listedNovelIDSet = Set<String>()
            for tag in tags {
                guard let novels = tag.targetNovelArray else { continue }
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

    
    func getBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        var sortType:NarouContentSortType = .title
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else { return }
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

    func reloadAllDataAndScrollToCurrentReadingContent(){
        self.displayDataArray = getBookShelfRATreeViewCellDataTree()
        if let treeView = self.treeView {
            treeView.reloadData()
            DispatchQueue.main.async {
                autoreleasepool {
                    guard let lastReadNovel = RealmGlobalState.GetLastReadNovel() else { return }
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
    }

    func reloadAllData(){
        self.displayDataArray = getBookShelfRATreeViewCellDataTree()
        if let treeView = self.treeView {
            treeView.reloadData()
        }
    }

    func showVersionUpNotice(){
        EasyDialog.Builder(self)
            .title(title: NSLocalizedString(
                "BookShelfTableViewController_AnnounceNewViersion"
                , comment: "アップデートされました"))
            .label(text: NSLocalizedString(
                "BookShelfTableViewController_AnnounceNewVersionMessage"
                , comment: "Version 1.1.2\r\n..."))
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                dialog.dismiss(animated: true, completion: nil)
                autoreleasepool {
                    guard let globalState = RealmGlobalState.GetInstance() else { return }
                    if globalState.isOpenRecentNovelInStartTime {
                        if let lastReadNovel = RealmGlobalState.GetLastReadNovel() {
                            self.pushNextView(novelID: lastReadNovel.novelID, isNeedSpeech: false)
                        }
                    }
                }
            })
            .build().show()
    }

    @objc func refreshButtonClicked(sender: Any) {
        autoreleasepool {
            guard let novels = RealmNovel.GetAllObjects() else { return }
            for novel in novels {
                if novel.type == .URL {
                    NovelDownloadQueue.shared.addQueue(novelID: novel.novelID)
                }
            }
        }
    }

    func getDisplayStringToSortTypeDictionary() -> [String:NarouContentSortType]{
        return [
            NSLocalizedString("BookShelfTableViewController_SortTypeNcode", comment: "Ncode順"): NarouContentSortType.ncode
            , NSLocalizedString("BookShelfTableViewController_SortTypeWriter", comment: "作者名順"): NarouContentSortType.writer
            , NSLocalizedString("BookShelfTableViewController_SortTypeNovelName", comment: "小説名順"): NarouContentSortType.title
            , NSLocalizedString("BookShelfTableViewController_SortTypeUpdateDate", comment: "更新順"): NarouContentSortType.novelUpdatedAt
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeBookshelf", comment: "自作フォルダ順"): NarouContentSortType.selfCreatedBookshelf
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeKeywardTag", comment: "タグ名順"): NarouContentSortType.keywordTag
            , NSLocalizedString("BookShelfRATreeViewController_SortTypeUpdateDateWithFilder", comment: "最終ダウンロード順(フォルダ分類版)"): NarouContentSortType.novelUpdatedAtWithFolder
        ]
    }

    func getCurrentSortTypeDisplayString() -> String {
        return autoreleasepool {
            let dic = getDisplayStringToSortTypeDictionary()
            guard let sortType = RealmGlobalState.GetInstance()?.bookShelfSortType else { return "-" }
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
                autoreleasepool {
                    if let globalState = RealmGlobalState.GetInstance() {
                        RealmUtil.Write { (realm) in
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
            EasyDialog.Builder(parent)
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
    // 次のビューに飛ばします。
    func pushNextView(novelID:String, isNeedSpeech: Bool){
        autoreleasepool {
            guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else { return }
            guard let story = novel.readingChapter else {
                let targetChapterNumber = RealmStory.StoryIDToChapterNumber(storyID: novel.m_readingChapterStoryID)
                guard let novelList = novel.linkedStorys, novelList.count > 0 else {
                    if novel.type == .URL {
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogTwoButton(
                                viewController: self,
                                title: nil,
                                message: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseNoStory", comment: "本文が何も読み込まれていないようです。この小説の再ダウンロードを試みますか？"),
                                button1Title: nil, // Cancel
                                button1Action: nil,
                                button2Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OK", comment: "ダウンロードする"), // OK
                                button2Action: {
                                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                            })
                        }
                    }
                    return
                }
                //print("targetChapterNumber: \(targetChapterNumber), novelList.count: \(novelList.count)")
                if novelList.count < targetChapterNumber {
                    let nextViewStoryID = novelList.first?.id
                    DispatchQueue.main.async {
                        NiftyUtilitySwift.EasyDialogTwoButton(
                            viewController: self,
                            title: nil,
                            message: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber", comment: "読み上げ位置がダウンロードされていない章を示しています。この小説の追加の章のダウンロードを試みますか？"),
                            button1Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OpenFirstStory", comment: "最初の章を開く"),
                            button1Action: {
                                if let nextViewStoryID = nextViewStoryID {
                                    self.nextViewStoryID = nextViewStoryID
                                    self.isNextViewNeedResumeSpeech = isNeedSpeech
                                    self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
                                }
                        },
                            button2Title: NSLocalizedString("BookShelfRATreeViewController_ConifirmDownloadNovelStartBecauseFewStoryNumber_OK", comment: "ダウンロードする"),
                            button2Action: {
                                NovelDownloadQueue.shared.addQueue(novelID: novelID)
                        })
                    }
                    return
                }
                if let story = novelList.first {
                    nextViewStoryID = story.id
                    self.isNextViewNeedResumeSpeech = isNeedSpeech
                    self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
                }
                return
            }
            nextViewStoryID = story.id
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

        autoreleasepool {
            if let novelID = item.novelID, let novel = RealmNovel.SearchNovelFrom(novelID: novelID) {
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
        return autoreleasepool {
            if let data = item as? BookShelfRATreeViewCellData {
                if let novelID = data.novelID, let novel = RealmNovel.SearchNovelFrom(novelID: novelID) {
                    return novel.likeLevel <= 0
                }
            }
            return false
        }
    }

    // 削除されたりした時に呼ばれるぽい
    func treeView(_ treeView: RATreeView, commit editingStyle: UITableViewCell.EditingStyle, forRowForItem item: Any) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            if let data = item as? BookShelfRATreeViewCellData {
                if let novelID = data.novelID {
                    let parent = self.treeView?.parent(forItem: item)
                    var index:Int = -1
                    if parent == nil {
                        for (idx, cellData) in self.displayDataArray.enumerated() {
                            if let thisNovelID = cellData.novelID {
                                if thisNovelID == novelID {
                                    index = idx
                                    break
                                }
                            }
                        }
                    }else if let parent = parent as? BookShelfRATreeViewCellData{
                        if let childrens = parent.childrens {
                            for (idx, child) in childrens.enumerated() {
                                if child.novelID == novelID {
                                    index = idx
                                }
                            }
                        }
                    }
                    if index >= 0 {
                        self.treeView?.deleteItems(at: IndexSet([index]), inParent: parent, with: RATreeViewRowAnimationFade)
                        for (idx, cellData) in self.displayDataArray.enumerated() {
                            if let thisNovelID = cellData.novelID {
                                if thisNovelID == novelID {
                                    // 一段目に novel があったということは階層は無いので単に一つ消すだけで良い
                                    self.displayDataArray.remove(at: idx)
                                    break
                                }
                            }else if var childrens = cellData.childrens {
                                for (childIdx, childCellData) in childrens.enumerated() {
                                    if let thisNovelID = childCellData.novelID {
                                        if thisNovelID == novelID {
                                            childrens.remove(at: childIdx)
                                            cellData.childrens = childrens
                                            self.displayDataArray[idx].childrens = childrens
                                        }
                                    }
                                }
                                if childrens.count <= 0 {
                                    // このchildを消したらchildが無くなったので、最上位のcellも消す
                                    self.displayDataArray.remove(at: idx)
                                    self.treeView?.deleteItems(at: IndexSet([idx]), inParent: nil, with: RATreeViewRowAnimationFade)
                                }
                            }
                        }
                        DispatchQueue.main.async {
                            let dialog = NiftyUtilitySwift.EasyDialogNoButton(
                                viewController: self,
                                title: NSLocalizedString("BookShelfRATreeViewController_NovelDeletingTitle", comment: "小説を削除しています……"),
                                message: nil)
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: {
                                autoreleasepool {
                                    if let novel = RealmNovel.SearchNovelFrom(novelID: novelID) {
                                        RealmUtil.Write { (realm) in
                                            novel.delete(realm: realm)
                                        }
                                    }
                                }
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: nil)
                                }
                            })
                        }
                    }
                }
            }
        }
        else if editingStyle == UITableViewCell.EditingStyle.insert {
            print("editingStyle == .insert")
        }
    }
    
    // cell の高さを求められる時に呼ばれる
    let fontForFontSize = UIFont.preferredFont(forTextStyle: .body)
    func treeView(_ treeView: RATreeView, heightForRowForItem item: Any) -> CGFloat {
        return self.fontForFontSize.pointSize + 10.5 + 12
    }
    func treeView(_ treeView: RATreeView, estimatedHeightForRowForItem item: Any) -> CGFloat {
        return self.fontForFontSize.pointSize + 10.5 + 12
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
                autoreleasepool {
                    if let childrens = cell.childrens {
                        print("\(spacer)\(cell.title ?? "??")")
                        dumpCurrentTree(head: childrens, level: level + 1)
                    }else if let novelID = cell.novelID, let novel = RealmNovel.SearchNovelFrom(novelID: novelID){
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
        autoreleasepool {
            guard let novels = RealmNovel.GetAllObjects() else { return }
            for novel in novels {
                if novel.type == .URL {
                    NovelDownloadQueue.shared.addQueue(novelID: novel.novelID)
                }
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
        if autoreleasepool(invoking: { () -> Bool in
            guard let globalState = RealmGlobalState.GetInstance() else {
                return true
            }
            if globalState.isOpenRecentNovelInStartTime {
                return true
            }
            return false
        }) {
            return
        }
        var lastReadNovelTitleTmp:String? = nil
        var lastReadNovelIDTmp:String? = nil
        autoreleasepool {
            guard let lastReadStory = RealmGlobalState.GetLastReadStory(), let lastReadNovel = RealmNovel.SearchNovelFrom(novelID: lastReadStory.novelID) else {
                return
            }
            if let storyCount = lastReadNovel.linkedStorys?.count, lastReadStory.chapterNumber >= storyCount && (lastReadStory.readLocation + 5) >= lastReadStory.content?.lengthOfBytes(using: .utf8) ?? 0 {
                return
            }
            lastReadNovelIDTmp = lastReadNovel.novelID
            lastReadNovelTitleTmp = lastReadNovel.title
        }
        guard let lastReadNovelTitle = lastReadNovelTitleTmp, let lastReadNovelID = lastReadNovelIDTmp else { return }
        
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
