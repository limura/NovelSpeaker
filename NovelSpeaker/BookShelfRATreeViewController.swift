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
    public var content:RealmNovel?
    public var childrens:[BookShelfRATreeViewCellData]?
    public var title:String?
}

func == (lhs: BookShelfRATreeViewCellData, rhs: BookShelfRATreeViewCellData) -> Bool {
    if lhs.content === rhs.content && lhs.title == rhs.title {
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
    var m_NextViewDetail: RealmNovel?
    var searchText:String? = nil
    var searchButton:UIBarButtonItem = UIBarButtonItem()
    var resumeSpeechFloatingButton:FloatingButton? = nil
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
        treeView.register(UINib(nibName: BookShelfTableViewCellID, bundle: nil), forCellReuseIdentifier: String(describing: BookShelfTableViewCell.self))
        self.treeView = treeView
        
        // 編集ボタン等を配置
        let refreshButton = UIBarButtonItem.init(barButtonSystemItem: UIBarButtonItem.SystemItem.refresh, target: self, action: #selector(refreshButtonClicked))
        let sortTypeSelectButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SortTypeSelectButton", comment: "sort"), style: UIBarButtonItem.Style.done, target: self, action: #selector(sortTypeSelectButtonClicked))
        self.navigationItem.rightBarButtonItems = [self.editButtonItem, refreshButton, sortTypeSelectButton]
        self.searchButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索"), style: .done, target: self, action: #selector(searchButtonClicked))
        self.navigationItem.leftBarButtonItems = [self.searchButton]

        // TODO: バージョンアップNoticeを出す
        if (GlobalDataSingleton.getInstance()?.isVersionUped())! {
            showVersionUpNotice()
        }
        if let globalState = RealmGlobalState.GetInstance(), let novel = RealmGlobalState.GetLastReadNovel(), globalState.isOpenRecentNovelInStartTime {
            self.pushNextView(novel: novel, isNeedSpeech: false)
        }
        reloadAllDataAndScrollToCurrentReadingContent()
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshControlValueChangedEvent), for: .valueChanged)
        treeView.scrollView.addSubview(refreshControl)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        registObserver()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let floatingButton = self.resumeSpeechFloatingButton {
            floatingButton.hide()
            self.resumeSpeechFloatingButton = nil
        }
        unregistObserver()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func registObserver() {
        guard let realm = try? RealmUtil.GetRealm() else { return }
        novelArrayNotificationToken = realm.objects(RealmNovel.self).observe { (change) in
            self.reloadAllData()
        }
    }
    func unregistObserver() {
        novelArrayNotificationToken = nil
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
        case .novelUpdatedAt:
            return allNovels.sorted(by: { (a, b) -> Bool in
                if let ad = a.lastDownloadDate, let bd = b.lastDownloadDate {
                    return ad > bd
                }else{
                    return a.novelID > b.novelID
                }
            })
        case .title:
            return Array(allNovels.sorted(byKeyPath: "title", ascending: true))
        case .writer:
            return Array(allNovels.sorted(byKeyPath: "writer", ascending: true))
        }
    }
    
    // 単純な本棚データの作成
    func createSimpleBookShelfRATreeViewCellDataTree(sortType:NarouContentSortType) -> [BookShelfRATreeViewCellData] {
        guard let novels = getNovelArray(sortType: sortType) else { return [] }
        var result:[BookShelfRATreeViewCellData] = []
        for novel in novels {
            let data = BookShelfRATreeViewCellData()
            data.childrens = nil
            data.content = novel
            data.title = nil
            result.append(data)
        }
        return result
    }
    
    // 更新日時でフォルダ分けします(フォルダ分けする版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithFolder() -> [BookShelfRATreeViewCellData] {
        guard let contents = getNovelArray(sortType: NarouContentSortType.novelUpdatedAt) else { return [] }
        struct filterStruct {
            let title:String
            let date:Date
        }
        let filterList = [
            // TODO: localize
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
            for content in contents {
                if let lastDownloadDate = content.lastDownloadDate {
                    if lastDownloadDate <= prevDate && lastDownloadDate > filter.date {
                        let data = BookShelfRATreeViewCellData()
                        data.content = content
                        folder.childrens?.append(data)
                    }
                }
            }
            result.append(folder)
            prevDate = filter.date
        }
        return result
    }

    // 更新日時でフォルダ分けします(フォルダ分けしない版)
    func createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> [BookShelfRATreeViewCellData] {
        guard let contents = getNovelArray(sortType: NarouContentSortType.novelUpdatedAt) else { return [] }
        var result = [] as [BookShelfRATreeViewCellData]
        for content in contents {
            let data = BookShelfRATreeViewCellData()
            data.childrens = nil
            data.content = content
            data.title = nil
            result.append(data)
        }
        return result
    }

    // 作者名でフォルダ分けします
    func createWriterBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        guard let contents = getNovelArray(sortType: NarouContentSortType.writer) else { return [] }
        var dic = [String:Any]()
        for content in contents {
            if var array = dic[content.writer] as? [RealmNovel]{
                array.append(content)
                dic[content.writer] = array
            }else{
                var array = [RealmNovel]()
                array.append(content)
                dic[content.writer] = array
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
            if let contents = dic[target] as? [RealmNovel] {
                for content in contents {
                    let data = BookShelfRATreeViewCellData()
                    data.content = content
                    folder.childrens?.append(data)
                }
            }
            result.append(folder)
        }
        return result
    }
    
    func getBookShelfRATreeViewCellDataTree() -> [BookShelfRATreeViewCellData] {
        guard let globalState = RealmGlobalState.GetInstance() else { return [] }
        let sortType = globalState.bookShelfSortType
        switch sortType {
        case .ncode: fallthrough
        case .title:
            return createSimpleBookShelfRATreeViewCellDataTree(sortType: sortType)
        case .novelUpdatedAt:
            return createUpdateDateBookShelfRATreeViewCellDataTreeWithoutFolder()
        case .writer:
            return createWriterBookShelfRATreeViewCellDataTree()
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
                guard let lastReadNovel = RealmGlobalState.GetLastReadNovel() else { return }
                UIView.animate(withDuration: 0.3, animations: {
                    for cellItem in self.displayDataArray {
                        // tree が展開されるのは一段目までです(´・ω・`)
                        if let childrens = cellItem.childrens {
                            for cellItemChild in childrens {
                                if cellItemChild.content == lastReadNovel {
                                    self.treeView?.expandRow(forItem: cellItem)
                                    self.treeView?.scrollToRow(forItem: cellItem, at: RATreeViewScrollPositionTop, animated: false)
                                    return
                                }
                            }
                        }
                        if cellItem.content == lastReadNovel {
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
                guard let globalState = RealmGlobalState.GetInstance() else { return }
                if globalState.isOpenRecentNovelInStartTime {
                    if let lastReadNovel = RealmGlobalState.GetLastReadNovel() {
                        self.pushNextView(novel: lastReadNovel, isNeedSpeech: false)
                    }
                }
            })
            .build().show()
    }

    @objc func refreshButtonClicked(sender: Any) {
        // TODO: 再ダウンロード回りを書き直す
        GlobalDataSingleton.getInstance().reDownloadAllContents()
    }

    func getDisplayStringToSortTypeDictionary() -> [String:NarouContentSortType]{
        return [
            NSLocalizedString("BookShelfTableViewController_SortTypeNcode", comment: "Ncode順"): NarouContentSortType.ncode
            , NSLocalizedString("BookShelfTableViewController_SortTypeWriter", comment: "作者名順"): NarouContentSortType.writer
            , NSLocalizedString("BookShelfTableViewController_SortTypeNovelName", comment: "小説名順"): NarouContentSortType.title
            , NSLocalizedString("BookShelfTableViewController_SortTypeUpdateDate", comment: "更新順"): NarouContentSortType.novelUpdatedAt
        ]
    }

    func getCurrentSortTypeDisplayString() -> String {
        let dic = getDisplayStringToSortTypeDictionary()
        let sortType = GlobalDataSingleton.getInstance().getBookSelfSortType()
        for (key, type) in dic {
            if type == sortType {
                return key
            }
        }
        return "-"
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
        let dialog = PickerViewDialog.createNewDialog([
            NSLocalizedString("BookShelfTableViewController_SortTypeNcode", comment: "Ncode順"),
            NSLocalizedString("BookShelfTableViewController_SortTypeWriter", comment: "作者名順"),
            NSLocalizedString("BookShelfTableViewController_SortTypeNovelName", comment: "小説名順"),
            NSLocalizedString("BookShelfTableViewController_SortTypeUpdateDate", comment: "更新順"),
        ], firstSelectedString: getCurrentSortTypeDisplayString(), parentView: targetView) { (selectedText) in
            let sortType = self.convertDisplayStringToSortType(key: selectedText!)
            GlobalDataSingleton.getInstance().setBookSelfSortType(sortType)
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
            /* TODO: これを設定しないとどの小説を読んでよいのかわからんはず
            if let nextViewController = segue.destination as? SpeechViewController {
                nextViewController.targetStory = story
            }
             */
        }
    }
    // 次のビューに飛ばします。
    func pushNextView(novel:RealmNovel, isNeedSpeech: Bool){
        m_NextViewDetail = novel
        self.isNextViewNeedResumeSpeech = isNeedSpeech
        self.performSegue(withIdentifier: "bookShelfToReaderSegue", sender: self)
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
        guard let cell = treeView.dequeueReusableCell(withIdentifier: String(describing: BookShelfTableViewCell.self)) as? BookShelfTableViewCell,
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

        if let content = item.content {
            // TODO: cell の扱いをRealm側に変えたい……('A`)
            //print("cellForItem: \(content.title) ncode:\(content.ncode) level: \(level)")
            cell.setTitleLabel(headSpace + content.title, ncode: content.novelID)
        }else if let title = item.title {
            //print("cellForItem: \(title) level: \(level)")
            cell.setTitleLabel(headSpace + title, ncode: nil)
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
            if let content = data.content {
                pushNextView(novel: content, isNeedSpeech: false)
            }
        }
    }

    func treeView(_ treeView: RATreeView, canEditRowForItem item: Any) -> Bool {
        if let data = item as? BookShelfRATreeViewCellData {
            if data.content != nil {
                return true
            }
        }
        return false
    }

    // 削除されたりした時に呼ばれるぽい
    func treeView(_ treeView: RATreeView, commit editingStyle: UITableViewCell.EditingStyle, forRowForItem item: Any) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            if let data = item as? BookShelfRATreeViewCellData {
                if let content = data.content {
                    let parent = self.treeView?.parent(forItem: item)
                    var index:Int = -1
                    if parent == nil {
                        for (idx, cellData) in self.displayDataArray.enumerated() {
                            if let thisContent = cellData.content {
                                if thisContent == content {
                                    index = idx
                                    break
                                }
                            }
                        }
                    }else if let parent = parent as? BookShelfRATreeViewCellData{
                        if let childrens = parent.childrens {
                            for (idx, child) in childrens.enumerated() {
                                if child.content == content {
                                    index = idx
                                }
                            }
                        }
                    }
                    if index >= 0 {
                        self.treeView?.deleteItems(at: IndexSet([index]), inParent: parent, with: RATreeViewRowAnimationFade)
                        if let realm = try? RealmUtil.GetRealm() {
                            realm.beginWrite()
                            content.delete(realm: realm)
                            if let token = self.novelArrayNotificationToken {
                                try! realm.commitWrite(withoutNotifying: [token])
                            }else{
                                try! realm.commitWrite()
                            }
                        }
                        for (idx, cellData) in self.displayDataArray.enumerated() {
                            if let thisContent = cellData.content {
                                if thisContent == content {
                                    // 一段目に content があったということは階層は無いので単に一つ消すだけで良い
                                    self.displayDataArray.remove(at: idx)
                                    break
                                }
                            }else if var childrens = cellData.childrens {
                                for (childIdx, childCellData) in childrens.enumerated() {
                                    if let thisContent = childCellData.content {
                                        if thisContent == content {
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
                    }
                }
            }
        }
        else if editingStyle == UITableViewCell.EditingStyle.insert {
            print("editingStyle == .insert")
        }
    }

    // ncodeのものが追加されたと仮定して RATreeView の状態を更新する
    func handleAddContent(novel:RealmNovel) {
        func dumpCurrentTree(head:[BookShelfRATreeViewCellData], level: Int){
            var spacer = ""
            for _ in 0...level{
                spacer += "  "
            }
            for cell in head {
                if let childrens = cell.childrens {
                    print("\(spacer)\(cell.title ?? "??")")
                    dumpCurrentTree(head: childrens, level: level + 1)
                }else if let content = cell.content{
                    print("\(spacer)\(content.title ?? "??")")
                }else{
                    print("\(spacer)\(cell.title ?? "??")")
                }
            }
        }
        
        //print("before:")
        //dumpCurrentTree(head: self.displayDataArray, level: 0)
        let newDisplayDataArray = getBookShelfRATreeViewCellDataTree()
        for (idx, cellData) in newDisplayDataArray.enumerated() {
            if let content = cellData.content {
                if content == novel {
                    // toplevel なら単にその新しく出来た cellData を insert するだけで良い
                    self.displayDataArray.insert(cellData, at: idx)
                    self.treeView?.insertItems(at: [idx], inParent: nil, with: RATreeViewRowAnimationFade)
                    print("insert top/[\(idx)]")
                    return
                }
            }else if let childrens = cellData.childrens {
                for (childIdx, childCellData) in childrens.enumerated() {
                    if let content = childCellData.content {
                        if content == novel {
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
                                print("displayDataArray.insert(\(cellData.title ?? "??"), at: \(idx))")
                                //dumpCurrentTree(head: self.displayDataArray, level: 0)
                                self.treeView?.insertItems(at: [idx], inParent: nil, with: RATreeViewRowAnimationFade)
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
        print("handleAddContent nothing to do...")
    }
    /* TODO: 小説が追加されたり削除されたイベントを受け取るのを作る
    @objc func narouContentListChanged(notification:NSNotification){
        guard let how = notification.userInfo!["how"] as? String, let ncode = notification.userInfo!["ncode"] as? String else {
            print("narouContentListChanged. but unknown userInfo")
            return
        }
        print("narouContentListChanged: \(how)")
        switch how {
        case NarouContentListChangedAnnounce_Add:
            // add は適切に処理してやらないといけない
            handleAddContent(ncode: ncode)
            break
        case NarouContentListChangedAnnounce_Change:
            // change は何もしなくて良い
            break
        case NarouContentListChangedAnnounce_Delete:
            // delete が呼ばれるパスは無いと信じたい(自前のdeleteの時はNotificationを切ってるので来ないはず)けどあったら寂しいのでreloadしておく
            reloadAllData()
            break
        default:
            break
        }
    }
     */

    @objc func refreshControlValueChangedEvent(sendor:UIRefreshControl) {
        GlobalDataSingleton.getInstance()?.reDownloadAllContents()
        sendor.endRefreshing()
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
        guard let realm = try? RealmUtil.GetRealm(), let lastReadStory = RealmGlobalState.GetLastReadStory(), let lastReadNovel = realm.object(ofType: RealmNovel.self, forPrimaryKey: lastReadStory.novelID) else {
            return
        }
        if let storyCount = lastReadNovel.linkedStorys?.count, lastReadStory.chapterNumber >= storyCount && (lastReadStory.readLocation + 5) >= lastReadStory.content?.lengthOfBytes(using: .utf8) ?? 0 {
            return
        }
        
        if let oldFloatingButton = self.resumeSpeechFloatingButton {
            oldFloatingButton.hide()
            self.resumeSpeechFloatingButton = nil
        }
        self.resumeSpeechFloatingButton = FloatingButton.createNewFloatingButton()
        guard let floatingButton = self.resumeSpeechFloatingButton else {
            return
        }
        
        floatingButton.assignToView(view: (self.treeView?.scrollView)!, text: String(format: NSLocalizedString("BookShelfTableViewController_Resume:", comment: "再生:%@"), lastReadNovel.title), animated: true) {
            self.pushNextView(novel: lastReadNovel, isNeedSpeech: true)
            floatingButton.hideAnimate()
        }
    }

}
