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
    // チェック済みを上にまとめる時に使う、「並べ直した」時点でチェックが付いていた ID の集合。
    // チェックのON/OFFでは更新しない(指の下で行が動いて隣の小説を誤って触ってしまうのを防ぐため)。
    // Realm 由来(小説の追加・更新等)の再構築でも更新しない(ユーザ操作でないタイミングで並びが勝手に変わらないようにするため)。
    // 更新するのは 画面を開いた時 / 並び替えを変えた時 / 検索を変えた時 / 「チェック済みを上にまとめ直す」を選んだ時 の4つだけ。
    var pinnedNovelIDSet:Set<String> = []
    // 現在表示している並び順。Realm 由来の再構築ではこの並びを維持し、増えた小説だけを末尾に足して、
    // 減った小説は抜けるだけにする。
    // (これが無いと、裏で小説が1つ更新されただけで「更新順」等の並びが動いてしまい、
    //  チェックしようとしていた行が指の下から逃げる)
    // pinnedNovelIDSet と同じタイミングでだけ捨てる(捨てると次の再構築で並び替え本来の順番に戻る)。
    var displayedNovelIDOrder:[String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.OverrideTitle ?? NSLocalizedString("MultipleNovelIDSelectorViewController_Title", comment: "小説を選択")

        self.sortType = MultipleNovelIDSelectorViewController.defaultSortType()
        resetDisplayOrderSnapshot()
        createSelectorCells()
        // 文字ボタンだと横幅が足りず「…」に畳まれて存在に気づけないため、アイコンにする。
        // VoiceOver 用に accessibilityLabel には(アイコンにする前の)文字列を入れる。
        self.filterButton = UIBarButtonItem.init(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(filterButtonClicked(sender:)))
        self.filterButton.accessibilityLabel = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索")
        self.sortButton = UIBarButtonItem.init(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: self, action: #selector(sortButtonClicked(sender:)))
        self.sortButton.accessibilityLabel = sortButtonTitle()
        navigationItem.rightBarButtonItems = [filterButton, sortButton]
        registNotificationCenter()
        RestartObservers()
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
            self.novelArrayNotificationToken = allNovels.observe({ [weak self] (change) in
                switch change {
                case .initial(_):
                    break
                case .update(_, let deletions, let insertions, _):
                    // 小説の増減の時だけ作り直す。
                    // 変更(modifications)まで拾うと、ダウンロードで最終更新日時が書き変わる度に
                    // 一覧を作り直す事になってしまう(この画面で表示している内容には影響しない)。
                    if deletions.count > 0 || insertions.count > 0 {
                        DispatchQueue.main.async {
                            self?.rebuildSelectorCellsKeepingScrollPosition()
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
            self.novelTagNotificationToken = allFolders.observe({ [weak self] change in
                switch change {
                case .initial(_):
                    break
                case .update(_, deletions: _, insertions: _, modifications: _):
                    DispatchQueue.main.async {
                        self?.rebuildSelectorCellsKeepingScrollPosition()
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    // Realm 側で小説が増減した時に呼ぶ。ユーザ操作ではないので、並び順(displayedNovelIDOrder)も
    // スクロール位置も維持したまま、増減だけを反映する。
    func rebuildSelectorCellsKeepingScrollPosition() {
        let contentOffset = self.tableView.contentOffset
        self.form.removeAll(keepingCapacity: true)
        self.createSelectorCells()
        self.tableView.layoutIfNeeded()
        let minOffsetY = -self.tableView.adjustedContentInset.top
        let maxOffsetY = max(minOffsetY, self.tableView.contentSize.height + self.tableView.adjustedContentInset.bottom - self.tableView.bounds.height)
        self.tableView.contentOffset = CGPoint(x: contentOffset.x, y: min(max(contentOffset.y, minOffsetY), maxOffsetY))
    }

    // 「並べ直す」操作。チェック済みの集合を取り直し、維持していた並び順を捨てる。
    // これを呼ばずに再構築した場合は、今表示されている並びがそのまま維持される。
    func resetDisplayOrderSnapshot() {
        self.pinnedNovelIDSet = self.SelectedNovelIDSet
        self.displayedNovelIDOrder = []
    }

    // 維持している並び順に沿って並べ替える。今回初めて出てきた小説は末尾に置く。
    // displayedNovelIDOrder が空の時(並べ直した直後)は並び替え本来の順番をそのまま使う。
    func applyDisplayedOrder(_ novels:[RealmNovel]) -> [RealmNovel] {
        if self.displayedNovelIDOrder.count <= 0 { return novels }
        var novelIDToIndexTable:[String:Int] = [:]
        for (index, novelID) in self.displayedNovelIDOrder.enumerated() {
            novelIDToIndexTable[novelID] = index
        }
        var knownNovels:[(index:Int, novel:RealmNovel)] = []
        var newNovels:[RealmNovel] = []
        for novel in novels {
            if let index = novelIDToIndexTable[novel.novelID] {
                knownNovels.append((index: index, novel: novel))
            }else{
                newNovels.append(novel)
            }
        }
        knownNovels.sort(by: { $0.index < $1.index })
        return knownNovels.map({ $0.novel }) + newNovels
    }

    func createAnyNovelIDCheckRow() -> CheckRow {
        return CheckRow(MultipleNovelIDSelectorViewController.AnyTypeTag) {
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

    func createNovelCheckRow(novel:RealmNovel, novelIDToFolderNameTable:[String:[String]]) -> CheckRow {
        let novelID = novel.novelID
        return CheckRow(novelID) {
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

    // 単一選択モード用の行。タップで即 singleSelectionHandler を呼ぶ(呼び出し側が確認ダイアログを出す)。
    func createNovelLabelRow(novel:RealmNovel, novelIDToFolderNameTable:[String:[String]]) -> LabelRow {
        let novelID = novel.novelID
        return LabelRow(novelID) {
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
    }

    func createSelectorCells() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard var allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
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
            let sortedNovels = self.applyDisplayedOrder(MultipleNovelIDSelectorViewController.applySort(results: allNovels, sortType: self.sortType).filter({ !self.ExcludeNovelIDSet.contains($0.novelID) }))
            self.displayedNovelIDOrder = sortedNovels.map({ $0.novelID })
            if self.IsSingleSelection {
                // 単一選択モードにはチェックが無いので上にまとめる対象も無い。
                let section = Section()
                for novel in sortedNovels {
                    section <<< self.createNovelLabelRow(novel: novel, novelIDToFolderNameTable: novelIDToFolderNameTable)
                }
                self.form +++ section
                return
            }
            // 「全ての小説」は常に一覧の一番上に置きたいので、どのセクションに入るかだけが変わるようにしておく。
            let isAnyNovelIDPinned = self.IsUseAnyNovelID && self.pinnedNovelIDSet.contains(MultipleNovelIDSelectorViewController.AnyTypeTag)
            let pinnedNovels = sortedNovels.filter({ self.pinnedNovelIDSet.contains($0.novelID) })
            let unpinnedNovels = sortedNovels.filter({ !self.pinnedNovelIDSet.contains($0.novelID) })
            if pinnedNovels.count <= 0 && !isAnyNovelIDPinned {
                // 上にまとめる対象が無いならセクションを分けても意味が無いので、見出しの無い一枚の一覧にする。
                let section = Section()
                if self.IsUseAnyNovelID {
                    section <<< self.createAnyNovelIDCheckRow()
                }
                for novel in unpinnedNovels {
                    section <<< self.createNovelCheckRow(novel: novel, novelIDToFolderNameTable: novelIDToFolderNameTable)
                }
                self.form +++ section
                return
            }
            let pinnedSection = Section(NSLocalizedString("MultipleNovelIDSelectorViewController_SelectedSectionHeader", comment: "選択中"))
            let unpinnedSection = Section(NSLocalizedString("MultipleNovelIDSelectorViewController_UnselectedSectionHeader", comment: "その他"))
            if self.IsUseAnyNovelID {
                if isAnyNovelIDPinned {
                    pinnedSection <<< self.createAnyNovelIDCheckRow()
                }else{
                    unpinnedSection <<< self.createAnyNovelIDCheckRow()
                }
            }
            for novel in pinnedNovels {
                pinnedSection <<< self.createNovelCheckRow(novel: novel, novelIDToFolderNameTable: novelIDToFolderNameTable)
            }
            for novel in unpinnedNovels {
                unpinnedSection <<< self.createNovelCheckRow(novel: novel, novelIDToFolderNameTable: novelIDToFolderNameTable)
            }
            if pinnedSection.count > 0 {
                self.form +++ pinnedSection
            }
            if unpinnedSection.count > 0 {
                self.form +++ unpinnedSection
            }
        }
    }

    @objc func filterButtonClicked(sender: UIBarButtonItem) {
        NiftyUtility.EasyDialogTextInput(
            viewController: self,
            title: NSLocalizedString("SpeechModSettingsTableView_SearchTitle", comment: "検索"),
            message: nil,
            textFieldText: self.filterString,
            placeHolder: NSLocalizedString("BookShelfTableViewController_SearchMessage", comment: "小説名 と 作者名 が対象となります"), action: { (text) in
            self.filterString = text
            self.resetDisplayOrderSnapshot()
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
            if !self.IsSingleSelection {
                section <<< LabelRow() {
                    $0.title = NSLocalizedString("MultipleNovelIDSelectorViewController_RegroupSelectedNovels", comment: "チェック済みを上にまとめ直す")
                    $0.cell.textLabel?.numberOfLines = 0
                    $0.cell.accessibilityTraits = .button
                }.onCellSelection({ [weak self] (_, _) in
                    self?.resetDisplayOrderSnapshot()
                    DispatchQueue.main.async {
                        self?.form.removeAll(keepingCapacity: true)
                        self?.createSelectorCells()
                    }
                    vc.close(animated: true, completion: nil)
                })
            }
            for type in MultipleNovelIDSelectorViewController.selectableSortTypes {
                section <<< LabelRow() {
                    $0.title = MultipleNovelIDSelectorViewController.sortTypeDisplayString(type)
                    $0.cell.textLabel?.numberOfLines = 0
                    $0.cell.accessibilityTraits = .button
                }.onCellSelection({ [weak self] (_, _) in
                    self?.sortType = type
                    self?.resetDisplayOrderSnapshot()
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
