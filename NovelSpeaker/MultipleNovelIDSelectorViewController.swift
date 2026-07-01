//
//  MultipleNovelIDSelectorViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/01.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//
// 小説を複数選択するインタフェースを作る時に使います。
// 選択結果は delegate で渡されます。

import UIKit
import Eureka
import RealmSwift

protocol MultipleNovelIDSelectorDelegate : AnyObject {
    func MultipleNovelIDSelectorSelected(selectedNovelIDSet:Set<String>, hint:String)
}

class MultipleNovelIDSelectorViewController: FormViewController, RealmObserverResetDelegate {
    public var SelectedNovelIDSet:Set<String> = Set<String>()
    public var IsUseAnyNovelID = true
    public var Hint = ""
    public var IsNeedDisplayFolderName = false
    public var UnDisplayFolderID:String? = nil
    public var OverrideTitle:String? = nil
    public weak var delegate:MultipleNovelIDSelectorDelegate?
    
    static let AnyTypeTag = RealmSpeechModSetting.anyTarget
    
    var novelArrayNotificationToken:NotificationToken? = nil
    var novelTagNotificationToken:NotificationToken? = nil
    var filterString = ""
    var filterButton:UIBarButtonItem = UIBarButtonItem()

    // 単一選択モード(機能3/4 で使用)。true の時は行タップで即 singleSelectionHandler を呼ぶ。
    // 累積選択(CheckRow)や viewWillDisappear での delegate 通知は行わず、pop もしない(確認ダイアログのキャンセルで選択画面に留まれるように)。
    public var IsSingleSelection = false
    public var singleSelectionHandler: ((_ novelID: String) -> Void)? = nil
    // 一覧から除外する小説(機能3/4 で「現在開いている小説」を隠すために使う)。
    public var ExcludeNovelIDSet: Set<String> = []
    // 並び替え順。フォルダ分類系はフラット表示で扱えないので selectableSortTypes のみ対応。デフォルトは viewDidLoad で本棚ソートから決める。
    var sortType: NarouContentSortType = .NovelUpdatedAt
    var sortButton: UIBarButtonItem = UIBarButtonItem()
    // このピッカーで選べる並び替え(フォルダ分類・お気に入り・Webサイト等の集約系は除く)。
    static let selectableSortTypes: [NarouContentSortType] = [.NovelUpdatedAt, .Title, .Writer, .LastReadDate, .CreatedDate, .PageCount]

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.OverrideTitle ?? NSLocalizedString("MultipleNovelIDSelectorViewController_Title", comment: "小説を選択")

        self.sortType = MultipleNovelIDSelectorViewController.defaultSortType()
        createSelectorCells()
        // 文字ボタンだと横幅が足りず「…」に畳まれて存在に気づけないため、アイコンにする。
        // VoiceOver 用に accessibilityLabel には(アイコンにする前の)文字列を入れる。
        self.filterButton = UIBarButtonItem.init(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(filterButtonClicked(sender:)))
        self.filterButton.accessibilityLabel = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索")
        self.sortButton = UIBarButtonItem.init(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: self, action: #selector(sortButtonClicked(sender:)))
        self.sortButton.accessibilityLabel = sortButtonTitle()
        navigationItem.rightBarButtonItems = [filterButton, sortButton]
        registNotificationCenter()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }

    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    func StopObservers() {
        novelArrayNotificationToken = nil
        novelTagNotificationToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeNovelArray()
        observeNovelTag()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let delegate = self.delegate else { return }
        delegate.MultipleNovelIDSelectorSelected(selectedNovelIDSet: self.SelectedNovelIDSet, hint: self.Hint)
    }
    
    func registNotificationCenter() {
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.RealmSettingChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }

    func observeNovelArray() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
            self.novelArrayNotificationToken = allNovels.observe({ (change) in
                switch change {
                case .initial(_):
                    break
                case .update(_, let deletions, let insertions, let modifications):
                    if deletions.count > 0 || insertions.count > 0 || modifications.count > 0 {
                        DispatchQueue.main.async {
                            self.form.removeAll()
                            self.createSelectorCells()
                        }
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    func observeNovelTag() {
        RealmUtil.RealmBlock { realm in
            guard let allFolders = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) else { return }
            self.novelTagNotificationToken = allFolders.observe({ change in
                switch change {
                case .initial(_):
                    break
                case .update(_, deletions: _, insertions: _, modifications: _):
                    DispatchQueue.main.async {
                        self.form.removeAll()
                        self.createSelectorCells()
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    func createSelectorCells() {
        let section = Section()
        RealmUtil.RealmBlock { (realm) -> Void in
            guard var allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
            if IsUseAnyNovelID {
                section <<< CheckRow(MultipleNovelIDSelectorViewController.AnyTypeTag) {
                    $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AnyTargetName", comment: "全ての小説")
                    $0.value = self.SelectedNovelIDSet.contains(MultipleNovelIDSelectorViewController.AnyTypeTag)
                }.onChange({ (row) in
                    guard let value = row.value else { return }
                    if value {
                        self.SelectedNovelIDSet.insert(MultipleNovelIDSelectorViewController.AnyTypeTag)
                    }else{
                        self.SelectedNovelIDSet.remove(MultipleNovelIDSelectorViewController.AnyTypeTag)
                    }
                })
            }
            if self.filterString.count > 0 {
                allNovels = allNovels.filter("title CONTAINS %@ OR writer CONTAINS %@", self.filterString, self.filterString)
            }
            var novelIDToFolderNameTable:[String:[String]] = [:]
            if self.IsNeedDisplayFolderName, let folderArray = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) {
                for folder in folderArray {
                    if let unDisplayFolderID = self.UnDisplayFolderID, unDisplayFolderID == folder.id {
                        continue
                    }
                    for novelID in folder.targetNovelIDArray {
                        if var folderNameList = novelIDToFolderNameTable[novelID] {
                            folderNameList.append(folder.name)
                            novelIDToFolderNameTable[novelID] = folderNameList
                        }else{
                            novelIDToFolderNameTable[novelID] = [folder.name]
                        }
                    }
                }
            }
            let sortedNovels = MultipleNovelIDSelectorViewController.applySort(results: allNovels, sortType: self.sortType).filter({ !self.ExcludeNovelIDSet.contains($0.novelID) })
            for novel in sortedNovels {
                let novelID = novel.novelID
                if self.IsSingleSelection {
                    // 単一選択: タップで即 singleSelectionHandler を呼ぶ(呼び出し側が確認ダイアログを出す)。
                    section <<< LabelRow(novelID) {
                        $0.cellStyle = .subtitle
                        $0.title = novel.title
                    }.cellUpdate({ cell, row in
                        cell.accessoryType = .disclosureIndicator
                        cell.textLabel?.numberOfLines = 0
                        if let folderNameArray = novelIDToFolderNameTable[novelID] {
                            cell.detailTextLabel?.text = folderNameArray.joined(separator: ", ")
                        }
                    }).onCellSelection({ [weak self] cell, row in
                        cell.setSelected(false, animated: true)
                        self?.singleSelectionHandler?(novelID)
                    })
                } else {
                    section <<< CheckRow(novelID) {
                        $0.cellStyle = .subtitle
                        $0.title = novel.title
                        $0.value = self.SelectedNovelIDSet.contains(novelID)
                    }.onChange({ (row) in
                        guard let value = row.value else { return }
                        if value {
                            self.SelectedNovelIDSet.insert(novelID)
                        }else{
                            self.SelectedNovelIDSet.remove(novelID)
                        }
                    }).cellUpdate({ cell, row in
                        guard let folderNameArray = novelIDToFolderNameTable[novelID] else { return }
                        cell.detailTextLabel?.text = folderNameArray.joined(separator: ", ")
                    })
                }
            }
        }
        form +++ section
    }

    @objc func filterButtonClicked(sender: UIBarButtonItem) {
        NiftyUtility.EasyDialogTextInput(
            viewController: self,
            title: NSLocalizedString("SpeechModSettingsTableView_SearchTitle", comment: "検索"),
            message: nil,
            textFieldText: self.filterString,
            placeHolder: NSLocalizedString("BookShelfTableViewController_SearchMessage", comment: "小説名 と 作者名 が対象となります"), action: { (text) in
            self.filterString = text
            DispatchQueue.main.async {
                self.form.removeAll(keepingCapacity: true)
                self.createSelectorCells()
                if self.filterString.count <= 0 {
                    self.filterButton.accessibilityLabel = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索")
                }else{
                    self.filterButton.accessibilityLabel = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索") + "(\(self.filterString))"
                }
            }
        })
    }

    // MARK: - 並び替え

    // フラット表示で扱える並び替えの初期値を本棚の並び替え設定から決める。フォルダ分類系など扱えない種別なら NovelUpdatedAt にフォールバック。
    static func defaultSortType() -> NarouContentSortType {
        return RealmUtil.RealmBlock { (realm) -> NarouContentSortType in
            if let type = RealmGlobalState.GetInstanceWith(realm: realm)?.bookShelfSortType, selectableSortTypes.contains(type) {
                return type
            }
            return .NovelUpdatedAt
        }
    }

    // 本棚の getNovelArray と同じ keyPath でフラットに並び替える(このピッカーが対応する種別のみ)。
    static func applySort(results: Results<RealmNovel>, sortType: NarouContentSortType) -> [RealmNovel] {
        switch sortType {
        case .Title:
            return Array(results.sorted(byKeyPath: "title", ascending: true))
        case .Writer:
            return Array(results.sorted(byKeyPath: "writer", ascending: true))
        case .LastReadDate:
            return Array(results.sorted(byKeyPath: "lastReadDate", ascending: false))
        case .CreatedDate:
            return Array(results.sorted(byKeyPath: "createdDate", ascending: false))
        case .PageCount:
            return results.sorted(by: { (a, b) -> Bool in
                RealmStoryBulk.StoryIDToChapterNumber(storyID: a.m_lastChapterStoryID) < RealmStoryBulk.StoryIDToChapterNumber(storyID: b.m_lastChapterStoryID)
            })
        case .NovelUpdatedAt:
            fallthrough
        default:
            return Array(results.sorted(byKeyPath: "lastDownloadDate", ascending: false))
        }
    }

    static func sortTypeDisplayString(_ type: NarouContentSortType) -> String {
        switch type {
        case .Writer:
            return NSLocalizedString("BookShelfTableViewController_SortTypeWriter", comment: "作者名順")
        case .Title:
            return NSLocalizedString("BookShelfTableViewController_SortTypeNovelName", comment: "小説名順")
        case .LastReadDate:
            return NSLocalizedString("BookShelfRATreeViewController_StoryTypeLastReadDate", comment: "小説を開いた日時順")
        case .CreatedDate:
            return NSLocalizedString("BookShelfRATreeViewController_SorteTypeCreatedDate", comment: "本棚登録順")
        case .PageCount:
            return NSLocalizedString("BookShelfRATreeViewController_SortTypePageCount", comment: "ページ数順")
        case .NovelUpdatedAt:
            fallthrough
        default:
            return NSLocalizedString("BookShelfTableViewController_SortTypeUpdateDate", comment: "更新順")
        }
    }

    func sortButtonTitle() -> String {
        return NSLocalizedString("MultipleNovelIDSelectorViewController_SortButton", comment: "並び替え") + "(\(MultipleNovelIDSelectorViewController.sortTypeDisplayString(self.sortType)))"
    }

    @objc func sortButtonClicked(sender: UIBarButtonItem) {
        EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: { (vc) in
            let section = Section()
            for type in MultipleNovelIDSelectorViewController.selectableSortTypes {
                section <<< LabelRow() {
                    $0.title = MultipleNovelIDSelectorViewController.sortTypeDisplayString(type)
                    $0.cell.textLabel?.numberOfLines = 0
                    $0.cell.accessibilityTraits = .button
                }.onCellSelection({ [weak self] (_, _) in
                    self?.sortType = type
                    DispatchQueue.main.async {
                        self?.form.removeAll(keepingCapacity: true)
                        self?.createSelectorCells()
                        self?.sortButton.accessibilityLabel = self?.sortButtonTitle()
                    }
                    vc.close(animated: true, completion: nil)
                })
            }
            section <<< ButtonRow() {
                $0.title = NSLocalizedString("Cancel_button", comment: "Cancel")
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.accessibilityTraits = .button
            }.onCellSelection({ (_, _) in
                vc.close(animated: true, completion: nil)
            })
            vc.form +++ section
        }, parentViewController: self, animated: true, completion: nil)
    }
}

extension MultipleNovelIDSelectorViewController {
    // 単一選択(検索・並び替え付き)→確認ダイアログ→onConfirmed の共通フロー(機能3/4 で流用)。
    // 確認をキャンセルすると選択画面に留まる(誤タップから戻れる)。OK すると選択画面を pop してから onConfirmed を呼ぶ。
    // confirmMessage は選択された小説のタイトルを受け取って確認文言を返すクロージャ。
    static func PushSingleSelector(parent: UIViewController, excludeNovelID: String?, title: String, confirmMessage: @escaping (_ targetNovelTitle: String) -> String, onConfirmed: @escaping (_ targetNovelID: String) -> Void) {
        let selector = MultipleNovelIDSelectorViewController()
        selector.IsUseAnyNovelID = false
        selector.IsSingleSelection = true
        selector.IsNeedDisplayFolderName = true
        selector.OverrideTitle = title
        if let excludeNovelID = excludeNovelID {
            selector.ExcludeNovelIDSet = [excludeNovelID]
        }
        selector.singleSelectionHandler = { [weak selector] novelID in
            guard let selector = selector else { return }
            let novelTitle = RealmUtil.RealmBlock { (realm) -> String in
                return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.title ?? ""
            }
            NiftyUtility.EasyDialogBuilder(selector)
                .label(text: confirmMessage(novelTitle), textAlignment: .left)
                .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { dialog in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                })
                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            selector.navigationController?.popViewController(animated: true)
                            onConfirmed(novelID)
                        }
                    }
                })
                .build().show()
        }
        parent.navigationController?.pushViewController(selector, animated: true)
    }
}
