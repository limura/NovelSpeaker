//
//  BookShelfTreeViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2024/06/22.
//  Copyright © 2024 IIMURA Takuji. All rights reserved.
//

import Foundation
import UIKit
import RealmSwift
import Eureka

enum BookShelfSelectionState {
    case unselected
    case partiallySelected
    case fullySelected
}

class BookShelfRATreeViewCellData {
    public var novelID:String?
    public var childrens:[BookShelfRATreeViewCellData]?
    public var title:String?
    var isExpanded: Bool = false
    weak var parentNode: BookShelfRATreeViewCellData?
    var selectionState: BookShelfSelectionState = .unselected
    
    var labelText: String {
        get {
            return title ?? "-"
        }
    }
    
    var childNodeCount: Int {
        get {
            return childrens?.count ?? 0
        }
    }
    func addChild(_ child: BookShelfRATreeViewCellData) {
        if childrens == nil {
            childrens = [child]
        }else{
            childrens?.append(child)
        }
        child.parentNode = self
    }
    
    func updateSelectionState() {
        if childrens?.isEmpty ?? true {
            return
        }
        
        let selectedCount = childrens?.filter { $0.selectionState == .fullySelected }.count ?? -1
        if selectedCount == childrens?.count {
            selectionState = .fullySelected
        } else if selectedCount > 0 {
            selectionState = .partiallySelected
        } else {
            selectionState = .unselected
        }
    }
    
    func toggleSelection() {
        switch selectionState {
        case .unselected, .partiallySelected:
            selectionState = .fullySelected
            childrens?.forEach { $0.selectionState = .fullySelected }
        case .fullySelected:
            selectionState = .unselected
            childrens?.forEach { $0.selectionState = .unselected }
        }
    }
}

func == (lhs: BookShelfRATreeViewCellData, rhs: BookShelfRATreeViewCellData) -> Bool {
    if lhs.novelID == rhs.novelID && lhs.title == rhs.title {
        if lhs.childrens == nil && rhs.childrens == nil {
            return true
        }
        if let lhsc = lhs.childrens, let rhsc = rhs.childrens {
            if lhsc == rhsc {
                return true
            }
        }
    }
    return false
}
extension BookShelfRATreeViewCellData: Equatable {}

class BookShelfTreeViewController:UITableViewController, RealmObserverResetDelegate {
    var displayDataArray : [BookShelfRATreeViewCellData] = [];
    var showCheckboxes: Bool = false  // チェックボックスの表示/非表示を制御
    var searchText:String? = nil
    var searchButton:UIBarButtonItem = UIBarButtonItem()
    var switchFolderButton:UIBarButtonItem = UIBarButtonItem()
    var iCloudPullButton:UIBarButtonItem = UIBarButtonItem()
    var iCloudPushButton:UIBarButtonItem = UIBarButtonItem()
    var stopDownloadButton:UIBarButtonItem = UIBarButtonItem()
    var resumeSpeechFloatingButton:FloatingButton? = nil
    var toggleCheckboxButton:UIBarButtonItem = UIBarButtonItem()
    var nextViewStoryID: String?
    var isNextViewNeedResumeSpeech:Bool = false
    var isNextViewNeedUpdateReadDate:Bool = true
    
    var novelArrayNotificationToken : NotificationToken? = nil
    var globalStateNotificationToken: NotificationToken? = nil
    var novelTagNotificationToken : NotificationToken? = nil

    static var instance:BookShelfTreeViewController? = nil
    override func viewDidLoad() {
        super.viewDidLoad()
        BookShelfTreeViewController.instance = self
        StoryHtmlDecoder.shared.LoadSiteInfoIfNeeded()

        tableView.register(UINib(nibName: BookShelfTreeViewCell.id, bundle: nil), forCellReuseIdentifier: String(describing: BookShelfTreeViewCell.self))
        

        // このタイミングで StorySpeaker のインスタンスを作っておきます。
        // Realm observe が走るので、main thread で作っておかねばならぬらしい(´・ω・`)
        _ = StorySpeaker.shared
        
        self.title = NSLocalizedString("BookShelfRATreeViewController_Title", comment: "本棚")
        
        // 編集ボタン等を配置
        self.searchButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索"), style: .done, target: self, action: #selector(searchButtonClicked))
        self.switchFolderButton = UIBarButtonItem.init(image: UIImage(systemName: "rectangle.expand.vertical"), style: .plain, target: self, action: #selector(switchFolderButtonClicked))
        self.switchFolderButton.accessibilityLabel = NSLocalizedString("BookShelfRATreeViewController_SwitchFolderButton_VoiceOverTitle", comment: "フォルダ開閉")

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
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.0) {
                    self.tableView.reloadData()
                    self.tableView.layoutIfNeeded()
                } completion: { finished in
                    //if finished { // この finished が false で呼び出されるタイミングがあるぽいので finished は確認しないことにします
                        self.reloadAllDataAndScrollToCurrentReadingContent()
                    //}
                }
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
        self.refreshControl = refreshControl
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
        self.HighlightCurrentReadingNovel(doScroll: false)
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
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        var num = 0
        for node in displayDataArray {
            num += 1
            if node.isExpanded {
                num += node.childNodeCount
            }
        }
        return num
    }
    
    func getNode(indexPath: IndexPath) -> (BookShelfRATreeViewCellData, Int)? {
        var num = 0
        for node in displayDataArray {
            if indexPath.row == num {
                return (node, 0)
            }
            num += 1
            if node.isExpanded {
                let target = indexPath.row - num
                if node.childNodeCount > target, let childrens = node.childrens {
                    return (childrens[target], 1)
                }
                num += node.childNodeCount
            }
        }
        return nil
    }
    func getIndexPath(node:BookShelfRATreeViewCellData) -> IndexPath? {
        var num = 0
        for folderNode in displayDataArray {
            if folderNode == node {
                return IndexPath(row: num, section: 0)
            }
            num += 1
            if folderNode.isExpanded, let childrens = folderNode.childrens {
                for novelNode in childrens {
                    if novelNode == node {
                        return IndexPath(row: num, section: 0)
                    }
                    num += 1
                }
            }
        }
        return nil
    }
    func searchIndexPathFor(novelID:String) -> IndexPath? {
        var num = 0
        for folderNode in displayDataArray {
            if folderNode.novelID == novelID {
                return IndexPath(row: num, section: 0)
            }
            num += 1
            if folderNode.isExpanded, let childrens = folderNode.childrens {
                for novelNode in childrens {
                    if novelNode.novelID == novelID {
                        return IndexPath(row: num, section: 0)
                    }
                    num += 1
                }
            }
        }
        return nil
    }
    func searchFolderIndexPathFor(title:String) -> IndexPath? {
        var num = 0
        for folderNode in displayDataArray {
            if folderNode.childrens != nil && folderNode.title == title {
                return IndexPath(row: num, section: 0)
            }
            num += 1
            if folderNode.isExpanded, let childrens = folderNode.childrens {
                num += childrens.count
            }
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: String(describing: BookShelfTreeViewCell.self)) as? BookShelfTreeViewCell else {
            fatalError()
        }
        guard let (item, indentLevel) = getNode(indexPath: indexPath) else { return cell }
        cell.checkboxTapHandler = { [weak self] in
            self?.checkboxTapped(for: indexPath)
        }
        
        RealmUtil.RealmBlock { (realm) -> Void in
            if let novelID = item.novelID, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                let likeLevel = RealmGlobalState.GetInstanceWith(realm: realm)?.calcLikeLevel(novelID: novelID) ?? 0
                cell.cellSetup(novel: novel, treeLevel: indentLevel, likeLevel: likeLevel, showCheckbox: self.showCheckboxes, checkboxState: item.selectionState)
            }else if var title = item.title {
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
                    title += "(\(childrenIDArray.count))"
                }else{
                    childrenIDArray = []
                }
                cell.cellSetup(title: title, treeLevel: indentLevel, watchNovelIDArray: childrenIDArray, showCheckbox: self.showCheckboxes, checkboxState: item.selectionState)
            }
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let isDeleteBlockOnBookshelfTreeView = RealmUtil.RealmBlock { realm -> Bool in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return false }
            return globalState.IsNeedConfirmDeleteBook && globalState.isDeleteBlockOnBookshelfTreeView
        }
        if isDeleteBlockOnBookshelfTreeView { return false }
        guard let (node, _) = getNode(indexPath: indexPath) else { return false }
        if let novelID = node.novelID {
            return RealmUtil.RealmBlock { (realm) -> Bool in
                let likeLevel = RealmGlobalState.GetInstanceWith(realm: realm)?.calcLikeLevel(novelID: novelID) ?? 0
                return likeLevel <= 0
            }
        }
        return false
    }
    
    func deleteNovel(item: BookShelfRATreeViewCellData, indexPath: IndexPath, novelID: String) {
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
                    item.parentNode?.childrens?.removeAll(where: {$0.novelID == novelID})
                    self.displayDataArray.removeAll(where: {$0.novelID == novelID})
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            self.tableView.beginUpdates()
                            self.tableView.deleteRows(at: [indexPath], with: .automatic)
                            self.tableView.endUpdates()
                        }
                    }
                }
            })
        }
    }

    // 削除されたりした時に呼ばれるぽい
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if let (node, _) = getNode(indexPath: indexPath), let novelID = node.novelID {
                let title = node.title ?? "-"
                let isNeedCheckDelete = RealmUtil.RealmBlock { realm -> Bool in
                    RealmGlobalState.GetInstanceWith(realm: realm)?.IsNeedConfirmDeleteBook ?? false
                }
                if isNeedCheckDelete {
                    NiftyUtility.EasyDialogTwoButton(viewController: self, title: NSLocalizedString("BookShelfTableViewController_WarningForDeleteBookTitle", comment: "本の削除"), message: NSLocalizedString("BookShelfTableViewController_WarningDeleteBookMessage", comment: "本を削除しますか？\n") + title, button1Title: nil, button1Action: nil, button2Title: NSLocalizedString("BookShelfTableViewController_WarningDeleteBookOKButtonTitle", comment: "削除"), button2Action: {
                        self.deleteNovel(item: node, indexPath: indexPath, novelID: novelID)
                    })
                }else{
                    deleteNovel(item: node, indexPath: indexPath, novelID: novelID)
                }
            }
        }
    }
    
    func checkboxTapped(for indexPath: IndexPath) {
        guard let (node, _) = getNode(indexPath: indexPath) else { return }
        
        node.toggleSelection()
        updateParentSelectionStates(for: node)
        tableView.reloadData()
    }
    
    @objc func downloadStatusButtonTapped() {
        // TODO: 現在これで取得できるのは Queue に入っているものだけなので、ダウンロード中のものが確認できないためこのままでは駄目です。
        var summary = NovelDownloadQueue.shared.GetCurrentDownloadStatusSummary()
        if summary.count <= 0 {
            summary = NSLocalizedString("BookShelfTreeViewController_downloadStatusBarButtonTapped_no_download_found", comment: "ダウンロードは実行されていませんでした。")
        }
        DispatchQueue.main.async {
            NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: summary, buttonTitle: nil, buttonAction: nil)
        }
    }

    func toggleCheckboxes() {
        showCheckboxes.toggle()
        if showCheckboxes {
            self.toggleCheckboxButton.image = UIImage(systemName: "checkmark.square.fill")
        }else{
            self.toggleCheckboxButton.image = UIImage(systemName: "checkmark.square")
        }
        updateToggleStateForVisibleCells()
    }
    
    func RunFolderManagePopupView(checkedFolder2NovelIDMap: [String:[String]], novelIDTitleMap: [String:String], checkedNovelIDArray: [String]) {
        var folder2NovelIDMap:[String:[String]] = [:]
        func getFolderImageSystemName(folderName:String) -> String {
            let targetFolderNovelIDSet = Set(folder2NovelIDMap[folderName] ?? [])
            let checkedNovelIDSet = Set(checkedNovelIDArray)
            let and = targetFolderNovelIDSet.intersection(checkedNovelIDSet)
            if and.count == 0 {
                return "square"
            }
            if checkedNovelIDArray.count == and.count {
                return "checkmark.square"
            }
            return "minus.square"
        }
        // フォルダへの登録や登録解除を行います。
        // 登録されていない状態では以前の状態に戻します。
        // 単純に追加登録や削除をしてしまうとフォルダ内の順番がおかしくなるので注意してください
        func loopFolderAssign(folderName:String, completion:(()->Void)?) {
            switch getFolderImageSystemName(folderName: folderName) {
            case "checkmark.square":
                // 全てが選択されているのなら、選択を外す
                DispatchQueue.global(qos: .userInitiated).async {
                    RealmUtil.Write { realm in
                        RealmNovelTag.UnrefFor(realm: realm, name: folderName, type: RealmNovelTag.TagType.Folder, novelIDArray: checkedNovelIDArray)
                    }
                    folder2NovelIDMap[folderName] = (firstTimeFolder2NovelIDMap[folderName] ?? folder2NovelIDMap[folderName] ?? []).filter({!checkedNovelIDArray.contains($0)})
                    completion?()
                }
                break
            case "square":
                // 空の場合は初期状態に戻す
                guard let newValue = firstTimeFolder2NovelIDMap[folderName] else { return }
                // ただし、初期状態が未選択だった場合は単に追加する必要があります。
                // 単に追加するのは "minus.square" と同じ処理なので fallthrough します。
                let firstFolderNovelIDSet = Set(firstTimeFolder2NovelIDMap[folderName] ?? [])
                let checkedNovelIDSet = Set(checkedNovelIDArray)
                if checkedFolder2NovelIDMap[folderName]?.count ?? 0 > 0 || !firstFolderNovelIDSet.intersection(checkedNovelIDSet).isEmpty {
                    DispatchQueue.global(qos: .userInitiated).async {
                        RealmUtil.Write { realm in
                            RealmNovelTag.AddTag(realm: realm, name: folderName, novelIDArray: newValue, type: RealmNovelTag.TagType.Folder)
                        }
                        folder2NovelIDMap[folderName] = newValue
                        completion?()
                    }
                    break
                }
                fallthrough
            case "minus.square":
                fallthrough
            default:
                // 一部が登録されているのであれば、残りを追加する形で登録します
                DispatchQueue.global(qos: .userInitiated).async {
                    guard var newValue = firstTimeFolder2NovelIDMap[folderName] else { return }
                    newValue.append(contentsOf: checkedNovelIDArray.filter({!newValue.contains($0)}))
                    RealmUtil.Write { realm in
                        RealmNovelTag.AddTag(realm: realm, name: folderName, novelIDArray: newValue, type: RealmNovelTag.TagType.Folder)
                    }
                    folder2NovelIDMap[folderName] = newValue
                    completion?()
                }
                break
            }
        }
        func addButton(title:String, section: Section, process:((_ cell:ButtonCellOf<String>)->Void)?) {
            section <<< ButtonRow() {
                $0.title = title
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.accessibilityTraits = .button
                $0.cell.imageView?.image = UIImage(systemName: getFolderImageSystemName(folderName: title))
            }.onCellSelection({ cell, row in
                process?(cell)
            })
        }
        RealmUtil.RealmBlock { realm in
            guard let folderArray = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) else { return }
            for folder in folderArray {
                folder2NovelIDMap[folder.name] = Array(folder.targetNovelIDArray)
            }
        }
        let firstTimeFolder2NovelIDMap = folder2NovelIDMap
        EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: { epvc in
            let section = Section(NSLocalizedString("BookShelfTreeViewController_checkboxselected_AssignFolder_MenuTitle", comment: "追加・削除対象のフォルダ"))
            let folderNames = RealmUtil.RealmBlock { realm -> [String] in
                guard let tags = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) else { return [] }
                return Array(tags.map({$0.name}))
            }
            for name in folderNames.sorted(by: {$0 < $1}) {
                addButton(title: name, section: section) { cell in
                    loopFolderAssign(folderName: name) {
                        DispatchQueue.main.async {
                            cell.imageView?.image = UIImage(systemName: getFolderImageSystemName(folderName: name))
                        }
                    }
                }
            }
            epvc.form +++ section
            let closeSection = Section ()
            closeSection <<< ButtonRow() {
                $0.title = NSLocalizedString("Close_button", comment: "Close")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.accessibilityTraits = .button
            }.onCellSelection({ cell, row in
                epvc.close(animated: true, completion: nil)
            })
            epvc.form +++ closeSection
            let novelSection = Section(NSLocalizedString("BookShelfTreeViewController_checkboxselected_targetTitles_section", comment: "対象の小説") + "(\(checkedFolder2NovelIDMap.map({$0.value.count}).reduce(0, {$0 + $1})))")
            for (folderName, novelIDArray) in checkedFolder2NovelIDMap {
                for novelID in novelIDArray {
                    let novelTitle = novelIDTitleMap[novelID]
                    novelSection <<< LabelRow() {
                        $0.title = "\(folderName) / \(novelTitle ?? "-")"
                        $0.cell.textLabel?.numberOfLines = 0
                        $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                    }
                }
            }
            epvc.form +++ novelSection
            epvc.willDisappear = {
                for topNode in self.displayDataArray {
                    topNode.updateSelectionState()
                }
            }
        }, parentViewController: self, animated: true, completion: nil)
    }
    
    @objc func toggleCheckboxesButtonTapped() {
        if NovelSpeakerUtility.IsNotDisplayNovelMultiSelectCheckbox() == false && self.showCheckboxes == false {
            NiftyUtility.EasyDialogOneButtonWithSwitch(viewController: self, title: nil, message: NSLocalizedString("BookShelfTreeViewController_toggleCheckboxesButtonTapped_InformationMessage", comment: "小説の複数選択モードに入りました。\nこのモードを抜けるには先ほど押したボタンをもう一度押す必要があります。"), switchMessage: NSLocalizedString("BookShelfTreeViewController_toggleCheckboxesButtonTapped_Information_IsNotDisplayInformationSwitch", comment: "このメッセージを二度と出さない"), button1Title: nil) { isNotDisplay in
                NovelSpeakerUtility.SetIsNotDisplayNovelMultiSelectCheckbox(IsDisplay: isNotDisplay)
            }
            toggleCheckboxes()
            return
        }
        if self.showCheckboxes == true {
            // チェックボックスが表示されていて、チェックされているものがあるのなら、それらに対してなにかをする
            var checkedNovelIDArray:[String] = []
            var novelIDTitleMap:[String:String] = [:]
            var checkedFolder2NovelIDMap:[String:[String]] = [:]
            for topNode in self.displayDataArray {
                if topNode.selectionState != .unselected, let childrens = topNode.childrens {
                    let folderName = topNode.title ?? "-"
                    checkedFolder2NovelIDMap[folderName] = []
                    for childNode in childrens {
                        if childNode.selectionState == .fullySelected, let novelID = childNode.novelID {
                            checkedFolder2NovelIDMap[folderName]?.append(novelID)
                            checkedNovelIDArray.append(novelID)
                            if let title = childNode.title {
                                novelIDTitleMap[novelID] = title
                            }
                        }
                    }
                }
                if topNode.selectionState == .fullySelected, let novelID = topNode.novelID {
                    checkedNovelIDArray.append(novelID)
                    if let title = topNode.title {
                        novelIDTitleMap[novelID] = title
                    }
                }
            }
            if checkedNovelIDArray.count > 0 {
                DispatchQueue.global(qos: .userInteractive).async {
                    DispatchQueue.main.async {
                        func AddNovelUpdateCheckButton(buttonSection:Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_QueueNovelUpdateCheck",
                                    comment: "更新確認を行う"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: true) {
                                    self.addQueueToNovelDownload(novelIDArray: checkedNovelIDArray)
                                }
                            })
                        }
                        func AddStopUpdateCheckButton(buttonSection:Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_StopUpdateCheck",
                                    comment: "更新を確認しないよう設定する"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({
                                cell,
                                row in
                                epvc.close(animated: false,
                                           completion: {
                                    NiftyUtility.EasyDialogNoButton(viewController: self, title: nil, message: String(format: NSLocalizedString("BookShelfTreeViewController_checkboxselected_StopUpdateCheck_working", comment: "%d件の小説の更新確認を停止しています"), checkedNovelIDArray.count)) { dialog in
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            RealmUtil.Write { realm in
                                                for novelID in novelIDTitleMap.keys {
                                                    if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                                                        novel.isNotNeedUpdateCheck = true
                                                        realm.add(novel, update: .modified)
                                                    }
                                                }
                                            }
                                            DispatchQueue.main.async {
                                                dialog.dismiss(animated: false) {
                                                    NiftyUtility.EasyDialogMessageDialog(
                                                        viewController: self,
                                                        message: String(format: NSLocalizedString(
                                                            "BookShelfTreeViewController_checkboxselected_StopUpdateCheck_done_mesage",
                                                            comment: "%d件の小説で更新確認を行わないように設定しました"
                                                        ), checkedNovelIDArray.count)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                })
                            })
                        }
                        func AddEnableUpdateCheckButton(buttonSection:Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_EnableUpdateCheck",
                                    comment: "更新を確認するよう設定する"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: false, completion: {
                                    NiftyUtility.EasyDialogNoButton(viewController: self, title: nil, message: String(format: NSLocalizedString("BookShelfTreeViewController_checkboxselected_EnableUpdateCheck_working", comment: "%d件の小説の更新確認を有効にしています"), checkedNovelIDArray.count)) { dialog in
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            RealmUtil.Write { realm in
                                                for novelID in novelIDTitleMap.keys {
                                                    if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                                                        novel.isNotNeedUpdateCheck = false
                                                        realm.add(novel, update: .modified)
                                                    }
                                                }
                                            }
                                            DispatchQueue.main.async {
                                                dialog.dismiss(animated: false) {
                                                    NiftyUtility.EasyDialogMessageDialog(
                                                        viewController: self,
                                                        message: String(format: NSLocalizedString(
                                                            "BookShelfTreeViewController_checkboxselected_EnableUpdateCheck_done_mesage",
                                                            comment: "%d件の小説で更新確認を行うように設定しました"
                                                        ), checkedNovelIDArray.count)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                })
                            })
                        }
                        func AddEnableLikeCheckButton(buttonSection: Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_EnableLikeCheck",
                                    comment: "お気に入りに登録する"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: false, completion: {
                                    NiftyUtility.EasyDialogNoButton(viewController: self, title: nil, message: String(format: NSLocalizedString("BookShelfTreeViewController_checkboxselected_EnableLikeCheck_working", comment: "%d件をお気に入りに登録中"), checkedNovelIDArray.count)) { dialog in
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            RealmUtil.Write { realm in
                                                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                                                for novelID in novelIDTitleMap.keys {
                                                    if globalState.novelLikeOrder.contains(novelID) == false {
                                                        globalState.novelLikeOrder.append(novelID)
                                                    }
                                                }
                                            }
                                            DispatchQueue.main.async {
                                                dialog.dismiss(animated: false) {
                                                    NiftyUtility.EasyDialogMessageDialog(
                                                        viewController: self,
                                                        message: String(format: NSLocalizedString(
                                                            "BookShelfTreeViewController_checkboxselected_EnableLikeCheck_done_mesage",
                                                            comment: "%d件の小説をお気に入りに設定しました"
                                                        ), checkedNovelIDArray.count)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                })
                            })
                        }
                        func AddDisableLikeCheckButton(buttonSection: Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_DisableLikeCheck",
                                    comment: "お気に入り登録を外す"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: true, completion: {
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        RealmUtil.Write { realm in
                                            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                                            for novelID in novelIDTitleMap.keys {
                                                if let index = globalState.novelLikeOrder.index(of: novelID) {
                                                    globalState.novelLikeOrder.remove(at: index)
                                                }
                                            }
                                        }
                                        DispatchQueue.main.async {
                                            NiftyUtility.EasyDialogMessageDialog(
                                                viewController: self,
                                                message: String(format: NSLocalizedString(
                                                    "BookShelfTreeViewController_checkboxselected_DisableLikeCheck_done_mesage",
                                                    comment: "%d件の小説をお気に入りから外しました"
                                                ), checkedNovelIDArray.count)
                                            )
                                        }
                                    }
                                })
                            })
                        }
                        func AddAssignFolderButton(buttonSection: Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_AssignFolder",
                                    comment: "フォルダへ追加・削除する"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: false) {
                                    self.RunFolderManagePopupView(checkedFolder2NovelIDMap: checkedFolder2NovelIDMap, novelIDTitleMap: novelIDTitleMap, checkedNovelIDArray: checkedNovelIDArray)
                                }
                            })
                        }
                        func AddAssignUniqueSpeechModButton(buttonSection: Section, epvc: EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_AssignUniqueSpeechMod",
                                    comment: "小説用の読みの修正に追加・削除する"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: false, completion: {
                                    EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: { epvc in
                                        func getSpeechModCheckSystemIconName(speechMod:ThreadSafeReference<RealmSpeechModSetting>, novelIDArray:[String]) -> String {
                                            return RealmUtil.RealmBlock { realm -> String in
                                                guard let speechMod = realm.resolve(speechMod) else { return "square" }
                                                let speechModNovelIDSet = Set(speechMod.targetNovelIDArray)
                                                let targetNovelIDSet = Set(novelIDArray)
                                                if targetNovelIDSet.isSubset(of: speechModNovelIDSet) {
                                                    return "checkmark.square"
                                                }else if targetNovelIDSet.intersection(speechModNovelIDSet).isEmpty {
                                                    return "square"
                                                }else {
                                                    return "minus.square"
                                                }
                                            }
                                        }
                                        func addSpeechModButton(buttonSection:Section, speechMod:ThreadSafeReference<RealmSpeechModSetting>, title: String) {
                                            
                                            buttonSection <<< ButtonRow() {
                                                $0.title = title
                                                $0.cell.textLabel?.numberOfLines = 0
                                                $0.cell.accessibilityTraits = .button
                                            }.onCellSelection({ cell, row in
                                                switch getSpeechModCheckSystemIconName(speechMod: speechMod, novelIDArray: checkedNovelIDArray) {
                                                case "checkmark.square":
                                                    // TODO: このあたりから再開する
                                                    break
                                                case "square":
                                                    break
                                                case "minus.square":
                                                    fallthrough
                                                default:
                                                    break
                                                }
                                            })
                                        }
                                        let buttonSection = Section()
                                        RealmUtil.RealmBlock { realm in
                                            let targetSpeechModArray = RealmSpeechModSetting.SearchSettingsForContainsAnyNovelID(realm: realm, novelIDArray: checkedNovelIDArray)
                                            
                                        }
                                        epvc.form +++ buttonSection
                                        let closeSection = Section ()
                                        closeSection <<< ButtonRow() {
                                            $0.title = NSLocalizedString("Close_button", comment: "Close")
                                            $0.cell.textLabel?.numberOfLines = 0
                                            $0.cell.accessibilityTraits = .button
                                        }.onCellSelection({ cell, row in
                                            epvc.close(animated: true, completion: nil)
                                        })
                                        epvc.form +++ closeSection
                                        let novelSection = Section(NSLocalizedString("BookShelfTreeViewController_checkboxselected_targetTitles_section", comment: "対象の小説"))
                                        for novelID in checkedNovelIDArray {
                                            let novelTitle = novelIDTitleMap[novelID]
                                            novelSection <<< LabelRow() {
                                                $0.title = "\(novelTitle ?? "-")"
                                                $0.cell.textLabel?.numberOfLines = 0
                                                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                                            }
                                        }
                                        epvc.form +++ novelSection

                                    }, parentViewController: self, animated: true, completion: nil)
                                })
                            })
                        }
                        func AddDeleteNovelButton(buttonSection: Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_DeleteNovel",
                                    comment: "小説を削除する"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: false, completion: {
                                    DispatchQueue.main.async {
                                        NiftyUtility.EasyDialogTwoButton(viewController: self, title: nil, message: String(format: NSLocalizedString("BookShelfTreeViewController_checkboxselected_confirm_delete", comment: "本当に%d件の小説を削除して良いですか？"), checkedNovelIDArray.count), button1Title: NSLocalizedString("Cancel_button", comment: "Cancel"), button1Action: nil, button2Title: NSLocalizedString("OK_button", comment: "OK")) {
                                            NiftyUtility.EasyDialogNoButton(viewController: self, title: nil, message: String(format: NSLocalizedString("BookShelfTreeViewController_checkboxselected_confirm_delete_working", comment: "%d個の小説を削除中"), checkedNovelIDArray.count)) { dialog in
                                                DispatchQueue.global(qos: .userInitiated).async {
                                                    RealmUtil.Write { realm in
                                                        for novelID in novelIDTitleMap.keys {
                                                            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                                                                novel.delete(realm: realm)
                                                            }
                                                        }
                                                    }
                                                    DispatchQueue.main.async {
                                                        dialog.dismiss(animated: false) {
                                                            NiftyUtility.EasyDialogMessageDialog(
                                                                viewController: self,
                                                                message: String(format: NSLocalizedString(
                                                                    "BookShelfTreeViewController_checkboxselected_confirm_delete_done_mesage",
                                                                    comment: "%d件の小説を削除しました"
                                                                ), checkedNovelIDArray.count)
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                })
                            })
                        }
                        func AddCreateBackupFileButton(buttonSection: Section, epvc:EurekaPopupViewController) {
                            buttonSection <<< ButtonRow() {
                                $0.title = NSLocalizedString(
                                    "BookShelfTreeViewController_checkboxselected_CreateBackupFile",
                                    comment: "バックアップファイルの生成"
                                )
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: false, completion: {
                                    NovelSpeakerUtility.CreateNovelOnlyBackup(novelIDArray: checkedNovelIDArray, viewController: self) { (fileUrl, fileName) in
                                        DispatchQueue.main.async {
                                            let activityViewController = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
                                            let frame = UIScreen.main.bounds
                                            activityViewController.popoverPresentationController?.sourceView = self.view
                                            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.width / 2 - 60, y: frame.size.height - 50, width: 120, height: 50)
                                            self.present(activityViewController, animated: true, completion: nil)
                                        }
                                    }
                                })
                            })
                        }
                        func AddCancelButton(cancelSection: Section, epvc:EurekaPopupViewController) {
                            cancelSection <<< ButtonRow() {
                                $0.title = NSLocalizedString("Cancel_button", comment: "Cancel")
                                $0.cell.textLabel?.numberOfLines = 0
                                $0.cell.accessibilityTraits = .button
                            }.onCellSelection({ cell, row in
                                epvc.close(animated: true, completion: nil)
                            })
                        }
                        EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: {
                            epvc in
                            let buttonSection = Section(NSLocalizedString("BookShelfTreeViewController_toggleCheckBoxesButtonTapped_firstMenu_title", comment: "選択された小説への操作"))
                            AddNovelUpdateCheckButton(buttonSection: buttonSection, epvc: epvc)
                            AddStopUpdateCheckButton(buttonSection: buttonSection, epvc: epvc)
                            AddEnableUpdateCheckButton(buttonSection: buttonSection, epvc: epvc)
                            AddEnableLikeCheckButton(buttonSection: buttonSection, epvc: epvc)
                            AddDisableLikeCheckButton(buttonSection: buttonSection, epvc: epvc)
                            AddAssignFolderButton(buttonSection: buttonSection, epvc: epvc)
                            AddDeleteNovelButton(buttonSection: buttonSection, epvc: epvc)
                            AddCreateBackupFileButton(buttonSection: buttonSection, epvc: epvc)
                            epvc.form +++ buttonSection
                            let cancelSection = Section()
                            AddCancelButton(cancelSection: cancelSection, epvc: epvc)
                            epvc.form +++ cancelSection
                            let novelSection = Section(NSLocalizedString("BookShelfTreeViewController_checkboxselected_targetTitles_section", comment: "対象の小説") + "(\(checkedNovelIDArray.count))")
                            for novelID in checkedNovelIDArray {
                                let novelTitle = novelIDTitleMap[novelID]
                                novelSection <<< LabelRow() {
                                    $0.title = novelTitle ?? "-"
                                    $0.cell.textLabel?.numberOfLines = 0
                                    $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
                                }
                            }
                            epvc.form +++ novelSection
                        },
                        parentViewController: self,
                        animated: true,
                        completion: nil)
                    }
                }
            }
        }
        toggleCheckboxes()
    }
    private func updateToggleStateForVisibleCells() {
        guard let indexPathsForVisibleRows = tableView.indexPathsForVisibleRows else { return }
        
        for indexPath in indexPathsForVisibleRows {
            if let cell = tableView.cellForRow(at: indexPath) as? BookShelfTreeViewCell, let (node, _) = getNode(indexPath: indexPath) {
                if self.showCheckboxes {
                    cell.displayCheckBoxButton()
                    cell.updateCheckboxImage(for: node.selectionState, showCheckbox: self.showCheckboxes)
                }else{
                    cell.hideCheckBoxButton()
                }
            }
        }
    }

    func updateParentSelectionStates(for node: BookShelfRATreeViewCellData) {
        var currentNode = node.parentNode
        while let parent = currentNode {
            parent.updateSelectionState()
            currentNode = parent.parentNode
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let (node, _) = getNode(indexPath: indexPath) else { return }
        if node.childrens != nil {
            toggleFolderExpandState(node: node)
            if self.isFolderExpanded() {
                self.setExpandIcon()
            }else{
                self.setCollapseIcon()
            }
            return
        }
        // フォルダの開閉以外であれば、チェックボックスの選択をしたことにする
        if self.showCheckboxes {
            self.checkboxTapped(for: indexPath)
            return
        }
        if let novelID = node.novelID {
            // currentReadingNovelID の小説を開いた(最後に開いていた小説を開いた)なら、
            // updateReadDate は呼ばないで良いという事にします。
            let currentReadingNovelID:String = RealmUtil.RealmBlock { (realm) -> String in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return "" }
                return globalState.currentReadingNovelID
            }
            pushNextView(novelID: novelID, isNeedSpeech: false, isNeedUpdateReadDate: currentReadingNovelID != novelID)
        }
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if let floatingButton = self.resumeSpeechFloatingButton {
            let isEnd = floatingButton.scrollViewDidScroll(scrollView)
            if isEnd {
                self.resumeSpeechFloatingButton = nil
            }
        }
    }
    
    #if !targetEnvironment(macCatalyst)
    @objc func refreshControlValueChangedEvent(sendor:UIRefreshControl) {
        sendor.endRefreshing()
        refreshButtonClicked(sender: self)
    }
    #endif

    // 検索条件やソート条件を考慮した上での NarouContent の Array を返します
    func getNovelArray(realm: Realm, sortType:NarouContentSortType) -> [RealmNovel]? {
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
            // .WebSite はどうせ host を key とした辞書に入れてからsortするのでここでsortして返す意味がありません。
            return Array(allNovels)
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
                        folder.addChild(data)
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
        return RealmUtil.RealmBlock { (realm) -> (Bool, [BookShelfRATreeViewCellData]) in
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.NovelUpdatedAt) else { return (false,[]) }
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
                        folder.addChild(data)
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
                    data.title = novel.title
                    folder.addChild(data)
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
                folder.childrens = [BookShelfRATreeViewCellData]()
                for novel in noListedNovels {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    data.title = novel.title
                    folder.addChild(data)
                }
                folder.title = NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)")
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
                        folder.addChild(data)
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
                folder.childrens = [BookShelfRATreeViewCellData]()
                for novel in noListedNovels {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    folder.addChild(data)
                }
                folder.title = NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)")
                result.append(folder)
            }
            return (true, result)
        }
    }

    // 小説を開いた日時でフォルダ分けします(フォルダ分けしない版)
    func createLastReadDateBookShelfRATreeViewCellDataTreeWithoutFolder() -> (Bool, [BookShelfRATreeViewCellData]) {
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
            guard let novels = getNovelArray(realm: realm, sortType: NarouContentSortType.WebSite) else { return (false, []) }
            var hostToNovelMap:[String:[RealmNovel]] = [:]
            let noListedString = NSLocalizedString("BookShelfRATreeViewController_BookshelfNoListed", comment: "(未分類)")
            for novel in novels {
                let host = URL(string: novel.novelID)?.host ?? noListedString
                if hostToNovelMap[host] == nil {
                    hostToNovelMap[host] = [RealmNovel]()
                }
                hostToNovelMap[host]?.append(novel)
            }
            var result = [BookShelfRATreeViewCellData]()
            for host in hostToNovelMap.keys {
                let folder = BookShelfRATreeViewCellData()
                folder.childrens = [BookShelfRATreeViewCellData]()
                folder.title = HostStringToLocalizedString(host: host)
                guard let novelSorted = hostToNovelMap[host]?.sorted(by: {$0.title < $1.title}) else { continue }
                for novel in novelSorted {
                    let data = BookShelfRATreeViewCellData()
                    data.novelID = novel.novelID
                    data.title = novel.title
                    folder.addChild(data)
                }
                result.append(folder)
            }
            result.sort(by: { (a, b) -> Bool in
                a.title! < b.title!
            })
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
    
    // targetNode.isExpanded の状態を反映させます。
    // この時、すでに表示されている部分にだけ反映させるので tableView.reloadAll() とは違う動きをします。
    func applyFolderExpandStateTo(node:BookShelfRATreeViewCellData, completion:(()->Void)?) {
        guard let targetNodeIndexPath = getIndexPath(node: node) else { return }
        var indexPaths: [IndexPath] = []
        
        let startIndex = targetNodeIndexPath.row + 1
        let endIndex = startIndex + node.childNodeCount
        for index in startIndex..<endIndex {
            indexPaths.append(IndexPath(row: index, section: targetNodeIndexPath.section))
        }
        
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.0, animations: {
                self.tableView.beginUpdates()
                if node.isExpanded {
                    self.tableView.insertRows(at: indexPaths, with: .automatic)
                } else {
                    self.tableView.deleteRows(at: indexPaths, with: .automatic)
                }
                self.tableView.endUpdates()
                self.tableView.layoutIfNeeded()
                self.checkAndUpdateSwitchFolderButtonImage()
            }, completion: { finished in
                // if finished { // この finished が false で呼び出されるタイミングがあるぽいので finished は確認しないことにします
                    completion?()
                //}
            })
        }
    }
    func toggleFolderExpandState(node:BookShelfRATreeViewCellData, completion:(()->Void)? = nil) {
        node.isExpanded = !node.isExpanded
        applyFolderExpandStateTo(node: node, completion: completion)
    }
    func expandFolder(node:BookShelfRATreeViewCellData, completion:(()->Void)? = nil) {
        if node.isExpanded == true {
            completion?()
            return
        }
        toggleFolderExpandState(node: node, completion: completion)
    }
    func collapseFolder(node:BookShelfRATreeViewCellData, completion:(()->Void)? = nil) {
        if node.isExpanded == false {
            completion?()
            return
        }
        toggleFolderExpandState(node: node, completion: completion)
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

            DispatchQueue.main.async {
                if let oldFloatingButton = self.resumeSpeechFloatingButton {
                    oldFloatingButton.hide()
                    self.resumeSpeechFloatingButton = nil
                }
                self.resumeSpeechFloatingButton = FloatingButton.createNewFloatingButton()
                guard let floatingButton = self.resumeSpeechFloatingButton else {
                    return
                }
                floatingButton.assignToView(view: self.tableView, currentOffset: self.tableView.contentOffset, text: String(format: NSLocalizedString("BookShelfTableViewController_Resume:", comment: "再生:%@"), lastReadNovelTitle), animated: true) {
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
    }
    
    func HighlightNovel(novelID:String, doScroll:Bool, completion:(()->Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            for cellItem in self.displayDataArray {
                // tree が展開されるのは一段目までです(´・ω・`)
                if let childrens = cellItem.childrens {
                    for cellItemChild in childrens {
                        if cellItemChild.novelID == novelID {
                            self.expandFolder(node: cellItem) {
                                if let indexPath = self.getIndexPath(node: cellItemChild) {
                                    DispatchQueue.main.async {
                                        UIView.animate(withDuration: 0.0) {
                                            let isVisible = self.tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                                            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: !doScroll ? .none : isVisible ? .none : .middle)
                                        } completion: { finished in
                                            //if finished { // この finished が false で呼び出されるタイミングがあるぽいので finished は確認しないことにします
                                                completion?()
                                            //}
                                        }
                                    }
                                }else{
                                    completion?()
                                }
                            }
                            return
                        }
                    }
                }
                if cellItem.novelID == novelID, let indexPath = self.getIndexPath(node: cellItem)  {
                    DispatchQueue.main.async {
                        UIView.animate(withDuration: 0.0) {
                            let isVisible = self.tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                            self.tableView.selectRow(at: indexPath, animated: false, scrollPosition: !doScroll ? .none : isVisible ? .none : .middle)
                        } completion: { finished in
                            //if finished { // この finished が false で呼び出されるタイミングがあるぽいので finished は確認しないことにします
                                completion?()
                            //}
                        }
                        self.checkAndUpdateSwitchFolderButtonImage()
                    }
                    return
                }
            }
            completion?()
        }
    }
    func HighlightCurrentReadingNovel(doScroll:Bool, completion:(()->Void)? = nil) {
        let novelID:String? = RealmUtil.RealmBlock { (realm) -> String? in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return nil }
            return globalState.currentReadingNovelID
        }
        guard let targetNovelID = novelID else {
            completion?()
            return
        }
        HighlightNovel(novelID: targetNovelID, doScroll: doScroll, completion: completion)
    }
    
    func setExpandIcon() {
        DispatchQueue.main.async {
            self.switchFolderButton.image = UIImage(systemName: "rectangle.compress.vertical")
        }
    }
    func setCollapseIcon() {
        DispatchQueue.main.async {
            self.switchFolderButton.image = UIImage(systemName: "rectangle.expand.vertical")
        }
    }
    
    func checkAndUpdateSwitchFolderButtonImage() {
        if isFolderExpanded() {
            setExpandIcon()
        }else{
            setCollapseIcon()
        }
    }
    
    func reloadAllData(doScroll: Bool, completion:(()->Void)? = nil) {
        let (hasFolder, displayDataArray) = getBookShelfRATreeViewCellDataTree()
        do {
            func transferSelectionStates(before: [BookShelfRATreeViewCellData], after: inout [BookShelfRATreeViewCellData]) {
                // beforeのnovelIDをキー、selectionStateを値とするDictionaryを作成
                let selectionStateMap = Dictionary(uniqueKeysWithValues: before.filter({$0.novelID != nil}).map { ($0.novelID ?? "", $0.selectionState) })
                
                // afterの各要素に対して、対応するselectionStateを適用
                for i in 0..<after.count {
                    guard let novelID = after[i].novelID else { continue }
                    if let state = selectionStateMap[novelID] {
                        after[i].selectionState = state
                    }
                }
            }
            
            let beforeArray = self.displayDataArray
            var afterArray = displayDataArray
            for n in 0..<beforeArray.count {
                if n >= afterArray.count { break }
                let before = beforeArray[n]
                let after = afterArray[n]
                if before.title == after.title, let beforeChildrens = before.childrens, var afterChildrens = after.childrens {
                    // 開いている状態をコピー
                    after.isExpanded = before.isExpanded
                    // チェック状態をコピー(フォルダの中の分)
                    if before.selectionState != .unselected {
                        transferSelectionStates(before: beforeChildrens, after: &afterChildrens)
                    }
                }
            }
            // チェック状態をコピー(フォルダの外の分)
            transferSelectionStates(before: beforeArray, after: &afterArray)
        }
        DispatchQueue.main.async {
            // 表示されているものを元にスクロール位置を合わせようと努力します
            var selectedNovelID:String? = nil
            if let selectedIndexPath = self.tableView.indexPathsForSelectedRows?.first, let (cellData, _) = self.getNode(indexPath: selectedIndexPath), let novelID = cellData.novelID {
                selectedNovelID = novelID
            }
            self.displayDataArray = displayDataArray
            UIView.animate(withDuration: 0.0) {
                self.tableView.reloadData()
                self.tableView.layoutIfNeeded()
            } completion: { finished in
                //if finished { // この finished が false で呼び出されるタイミングがあるぽいので finished は確認しないことにします
                    if hasFolder {
                        self.switchFolderButton.isEnabled = true
                    }else{
                        self.switchFolderButton.isEnabled = false
                    }
                    if let selectedNovelID = selectedNovelID {
                        self.HighlightNovel(novelID: selectedNovelID, doScroll: doScroll, completion: completion)
                    }else {
                        self.HighlightCurrentReadingNovel(doScroll: doScroll, completion: completion)
                    }
                //}
            }
        }
    }

    func reloadAllDataAndScrollToCurrentReadingContent(){
        DispatchQueue.global(qos: .userInitiated).async {
            self.reloadAllData(doScroll: true) {
                self.addPreviousNovelSpeakButtonIfNeeded()
            }
        }
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
                        DispatchQueue.global(qos: .userInteractive).async {
                            self.reloadAllData(doScroll: false)
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
                                        DispatchQueue.global(qos: .userInteractive).async {
                                            self.reloadAllData(doScroll: false)
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
                                        if let novelID = self.displayDataArray.first?.childrens?.first?.novelID, novelID == obj.novelID {
                                            // フォルダ分けされていたとしても、最初のフォルダの最初の要素であれば表示しなおす必要はない
                                            continue
                                        }
                                        DispatchQueue.global(qos: .userInteractive).async {
                                            self.reloadAllData(doScroll: false)
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
                case .update(let objects, deletions: _, insertions: _, modifications: _):
                    let sortType = RealmUtil.RealmBlock { (realm) -> NarouContentSortType in
                        guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return .Title }
                        return globalState.bookShelfSortType
                    }
                    switch sortType {
                    case .KeywordTag:
                        if objects.filter({$0.type == RealmNovelTag.TagType.Keyword}).count <= 0 {
                            return
                        }
                        break
                    case .SelfCreatedFolder:
                        if objects.filter({$0.type == RealmNovelTag.TagType.Folder}).count <= 0 {
                            return
                        }
                        break
                    default:
                        return
                    }
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.reloadAllData(doScroll: false)
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
            case .downloadStatus:
                barButtonItemArray.append(UIBarButtonItem(image: UIImage(systemName: "waveform.badge.magnifyingglass"), style: .plain, target: self, action: #selector(downloadStatusButtonTapped)))
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
            case .multiSelect:
                let button = UIBarButtonItem(image: UIImage(systemName: "checkmark.square"), style: .plain, target: self, action: #selector(toggleCheckboxesButtonTapped))
                button.accessibilityLabel = NSLocalizedString("BookShelfTreeViewController_ToggleCheckboxButton_AccessibilityLabel", comment: "選択")
                self.toggleCheckboxButton = button
                barButtonItemArray.append(button)
                break
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

    func addQueueToNovelDownload(novelArray:ThreadSafeReference<Results<RealmNovel>>) {
        func queue(completion:(()->Void)? = nil) {
            DispatchQueue.global(qos: .userInitiated).async {
                NovelDownloadQueue.shared.addQueueArray(novelArray: novelArray)
                completion?()
            }
        }
        if NovelSpeakerUtility.IsNotDisplayUpdateCheckDialog() {
            queue()
            return
        }
        DispatchQueue.main.async {
            NiftyUtility.EasyDialogOneButtonWithSwitch(viewController: self, title: nil, message: NSLocalizedString("BookShelfTreeViewController_refreshButtonClicked_startingDownload_dialog", comment: "更新確認を開始しています"), switchMessage: NSLocalizedString("BookShelfTreeViewController_refreshButtonClicked_startingDownload_dialog_neverAskMeSwitch", comment: "以降このダイアログを出さない"), button1Title: nil, button1Action: { isNeverAskMe in
                NovelSpeakerUtility.SetIsNotDisplayUpdateCheckDialog(IsDisplay: isNeverAskMe)
            }, completion: { dialog in
                queue() {
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false)
                    }
                }
            })
        }
    }
    func addQueueToNovelDownload(novelIDArray:[String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novels = RealmNovel.SearchNovelWith(realm: realm, novelIDArray: novelIDArray) else { return }
                self.addQueueToNovelDownload(novelArray: ThreadSafeReference(to: novels))
            }
        }
    }
    func addQueueToNovelDownloadAllNovels() {
        DispatchQueue.global(qos: .userInitiated).async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novels = RealmNovel.GetAllObjectsWith(realm: realm)?.filter("isNotNeedUpdateCheck = false") else { return }
                self.addQueueToNovelDownload(novelArray: ThreadSafeReference(to: novels))
            }
        }
    }

    @objc func refreshButtonClicked(sender: Any) {
        self.addQueueToNovelDownloadAllNovels()
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
    
    func isFolderExpanded() -> Bool {
        for cellData in self.displayDataArray {
            if cellData.isExpanded && cellData.childrens?.count ?? 0 > 0 {
                return true
            }
        }
        return false
    }
    
    @objc func switchFolderButtonClicked(sender:Any) {
        DispatchQueue.main.async {
            let isExpanded = self.isFolderExpanded()
            let doExpand = !isExpanded
            for node in self.displayDataArray {
                node.isExpanded = doExpand
            }
            if doExpand {
                self.setExpandIcon()
            }else{
                self.setCollapseIcon()
            }
            self.tableView.reloadData()
        }
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
            DispatchQueue.global(qos: .userInteractive).async {
                let isChanged = RealmUtil.RealmBlock { (realm) -> Bool in
                    if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                        let prevSortType = globalState.bookShelfSortType
                        RealmUtil.WriteWith(realm: realm) { (realm) -> Void in
                            globalState.bookShelfSortType = sortType
                        }
                        return sortType != prevSortType
                    }
                    return false
                }
                if isChanged {
                    self.reloadAllData(doScroll: true)
                }
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
            DispatchQueue.global(qos: .userInteractive).async {
                self.reloadAllData(doScroll: true)
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
    
    static func LoadWebPageOnWebImportTab(url:URL) {
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
        guard let instance = instance else { return }
        DispatchQueue.main.async {
            /// XXX TODO: 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
            let targetTabIndex = 2
            guard let viewController = instance.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController else { return }
            viewController.reloadWebView()
        }
    }
    static func OpenNovelOnBookShelf(novelID:String){
        guard let instance = instance else { return  }
        DispatchQueue.main.async {
            return RealmUtil.RealmBlock { realm in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
                let targetTabIndex = 0
                guard let navigationController = instance.tabBarController?.viewControllers?[targetTabIndex] as? UINavigationController, let bookShelfTreeViewController = navigationController.viewControllers.first as? BookShelfTreeViewController else {
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
    
    static func RefreshBookshelf() {
        guard let instance = instance else { return }
        DispatchQueue.main.async {
            instance.tableView.reloadData()
        }
    }
}
