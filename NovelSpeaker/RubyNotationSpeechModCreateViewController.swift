//
//  RubyNotationSpeechModCreateViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2026/08/27.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

/// 小説本文から抽出したルビ表記の一覧を出して、選んだものをその小説専用の読みの修正として登録する画面です。
///
/// 候補が数千件になる事があるので Eureka ではなく素の UITableView で作っています
/// (Eureka は Row を先に全部作るので、数千行あると目に見えて重くなるため)。
class RubyNotationSpeechModCreateViewController: UITableViewController {
    static let cellID = "RubyNotationSpeechModCreateCell"
    /// 一度に表示する件数。下までスクロールしたら伸びていきます。
    static let displayCountStep = 200

    public var novelID:String = ""

    /// 抽出した全ての候補(絞り込み前)
    var allCandidateArray:[RubyNotationCandidate] = []
    /// 表示条件と並び順を適用した後の候補
    var displayCandidateArray:[RubyNotationCandidate] = []
    /// 今表示している件数(displayCandidateArray の先頭からこの数だけ出す)
    var displayCount = RubyNotationSpeechModCreateViewController.displayCountStep

    var checkedBeforeSet:Set<String> = []
    /// 既にこの小説を適用対象にしている読み替え設定の「読み替え前 → 読み替え後」。
    /// 同じ読み替え後で登録済みなのか、別の読み替えが登録されているのかを区別するために持っています。
    var registeredAfterTable:[String:String] = [:]

    var sortType:RubyNotationExtractor.SortType = .bareChapterCount
    /// 1文字の読み替え前も表示するかどうか。
    /// 1文字のものは「王」が「魔王」の中でも発火するというような事になるので、既定では隠しています。
    var isShowShortBefore = false
    /// 裸で出てこない(＝常にルビが振られている)ものも表示するかどうか。
    /// 常にルビが振られているなら「ルビはルビだけ読む」で足りるので、登録しても新しく直る所が無く、既定では隠しています。
    var isShowNoBareCandidate = false
    var filterString = ""
    /// 表示条件で隠している候補の数。隠している事を画面上部に出すために数えています。
    var hiddenNoBareCount = 0
    var hiddenShortBeforeCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "RubyNotationSpeechModCreateViewController viewDidLoad", data: ["novelID": novelID])

        self.title = NSLocalizedString("RubyNotationSpeechModCreateViewController_Title", comment: "ルビから読みの修正を作る")
        self.tableView.register(RubyNotationCandidateCell.self, forCellReuseIdentifier: RubyNotationSpeechModCreateViewController.cellID)
        self.tableView.register(RubyNotationHiddenCountHeaderView.self, forHeaderFooterViewReuseIdentifier: RubyNotationHiddenCountHeaderView.reuseID)
        self.tableView.allowsMultipleSelection = false
        // 「隠しています」の表示はセクションヘッダに出します。
        // plain スタイルのセクションヘッダはスクロールしても上に貼り付いたままなので、
        // 候補が何百件あっても隠している事に気付けます。
        self.tableView.sectionHeaderTopPadding = 0
        self.tableView.estimatedSectionHeaderHeight = 36
        updateNavigationItem()
        loadRegisteredState()
        startExtract()
    }

    // MARK: - 画面上部のボタン

    func updateNavigationItem() {
        let registerButton = UIBarButtonItem(title: NSLocalizedString("RubyNotationSpeechModCreateViewController_RegisterButton", comment: "登録"), style: .done, target: self, action: #selector(registerButtonClicked))
        registerButton.isEnabled = checkedBeforeSet.count > 0
        let menuButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: createMenu())
        menuButton.accessibilityLabel = NSLocalizedString("RubyNotationSpeechModCreateViewController_MenuButtonAccessibilityLabel", comment: "表示の設定")
        self.navigationItem.rightBarButtonItems = [registerButton, menuButton]
    }

    func createMenu() -> UIMenu {
        let sortMenu = UIMenu(title: NSLocalizedString("RubyNotationSpeechModCreateViewController_SortMenuTitle", comment: "並び順"), options: [.displayInline], children: [
            createSortAction(.bareChapterCount, NSLocalizedString("RubyNotationSpeechModCreateViewController_SortByBareChapterCount", comment: "本文中に出てくる章数が多い順")),
            createSortAction(.bareCount, NSLocalizedString("RubyNotationSpeechModCreateViewController_SortByBareCount", comment: "本文中に出てくる回数が多い順")),
            createSortAction(.appearance, NSLocalizedString("RubyNotationSpeechModCreateViewController_SortByAppearance", comment: "本文に出てきた順")),
            createSortAction(.beforeString, NSLocalizedString("RubyNotationSpeechModCreateViewController_SortByBeforeString", comment: "読み替え前の文字順")),
        ])
        let displayMenu = UIMenu(title: "", options: [.displayInline], children: [
            UIAction(title: NSLocalizedString("RubyNotationSpeechModCreateViewController_ShowShortBefore", comment: "1文字のものも表示する"), state: isShowShortBefore ? .on : .off, handler: { [weak self] _ in
                guard let self = self else { return }
                self.isShowShortBefore = !self.isShowShortBefore
                self.applyFilterAndSort()
                self.updateNavigationItem()
            }),
            UIAction(title: NSLocalizedString("RubyNotationSpeechModCreateViewController_ShowNoBareCandidate", comment: "常にルビが振られているものも表示する"), state: isShowNoBareCandidate ? .on : .off, handler: { [weak self] _ in
                guard let self = self else { return }
                self.isShowNoBareCandidate = !self.isShowNoBareCandidate
                self.applyFilterAndSort()
                self.updateNavigationItem()
            }),
        ])
        let actionMenu = UIMenu(title: "", options: [.displayInline], children: [
            UIAction(title: NSLocalizedString("RubyNotationSpeechModCreateViewController_SearchMenu", comment: "検索"), image: UIImage(systemName: "magnifyingglass"), handler: { [weak self] _ in
                self?.showSearchDialog()
            }),
            UIAction(title: NSLocalizedString("RubyNotationSpeechModCreateViewController_UncheckAll", comment: "チェックを全て外す"), attributes: checkedBeforeSet.count > 0 ? [] : [.disabled], handler: { [weak self] _ in
                guard let self = self else { return }
                self.checkedBeforeSet.removeAll()
                self.tableView.reloadData()
                self.updateNavigationItem()
            }),
        ])
        return UIMenu(title: "", children: [sortMenu, displayMenu, actionMenu])
    }

    func createSortAction(_ type:RubyNotationExtractor.SortType, _ title:String) -> UIAction {
        return UIAction(title: title, state: self.sortType == type ? .on : .off, handler: { [weak self] _ in
            guard let self = self else { return }
            self.sortType = type
            self.applyFilterAndSort()
            self.updateNavigationItem()
        })
    }

    func showSearchDialog() {
        NiftyUtility.EasyDialogTextInput2Button(
            viewController: self,
            title: NSLocalizedString("RubyNotationSpeechModCreateViewController_SearchTitle", comment: "検索"),
            message: nil,
            textFieldText: self.filterString,
            placeHolder: NSLocalizedString("RubyNotationSpeechModCreateViewController_SearchPlaceholder", comment: "絞り込む文字列を入力します"),
            leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
            rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
            leftButtonAction: nil,
            rightButtonAction: { [weak self] text in
                guard let self = self else { return }
                self.filterString = text
                DispatchQueue.main.async {
                    self.applyFilterAndSort()
                }
            })
    }

    // MARK: - 抽出

    func startExtract() {
        let novelID = self.novelID
        let notRubyCharacterString = RealmUtil.RealmBlock { (realm) -> String in
            return RealmGlobalState.GetInstanceWith(realm: realm)?.notRubyCharactorStringArray ?? ""
        }
        // 抽出はバックグラウンドで走るので、キャンセルの合図はスレッドを跨いで読み書きされる。
        let cancelFlag = CancelFlag()
        let progressTag = 100
        let dialog = NiftyUtility.EasyDialogBuilder(self)
            .label(text: NSLocalizedString("RubyNotationSpeechModCreateViewController_ExtractingTitle", comment: "小説本文からルビ表記を探しています"), textAlignment: .center)
            .label(text: "0 %", textAlignment: .center, tag: progressTag)
            .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { dialog in
                cancelFlag.cancel()
                DispatchQueue.main.async {
                    dialog.dismiss(animated: true, completion: nil)
                }
            })
            .build()
        dialog.show {
            var lastProgressText = ""
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result:[RubyNotationCandidate]?
                do {
                    result = try RubyNotationExtractor.Extract(novelID: novelID, notRubyCharacterString: notRubyCharacterString, progress: { value in
                        let text = "\(Int(value * 100)) %"
                        if text == lastProgressText { return }
                        lastProgressText = text
                        DispatchQueue.main.async {
                            (dialog.view.viewWithTag(progressTag) as? UILabel)?.text = text
                        }
                    }, isCanceled: { return cancelFlag.isCanceled })
                } catch {
                    result = nil
                }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // キャンセル時はキャンセルボタン側で既にダイアログを閉じているので、
                    // ここで閉じ直すと completion が呼ばれずに画面から出られなくなる事がある。
                    // なので、閉じるかどうかはキャンセルされたかどうかで分ける。
                    if cancelFlag.isCanceled {
                        self.navigationController?.popViewController(animated: true)
                        return
                    }
                    dialog.dismiss(animated: false, completion: {
                        guard let result = result else {
                            // 抽出に失敗した(小説本文が読めない等)
                            NiftyUtility.EasyDialogOneButton(
                                viewController: self,
                                title: nil,
                                message: NSLocalizedString("RubyNotationSpeechModCreateViewController_CanNotReadNovelContent", comment: "小説本文を読み込めませんでした。"),
                                buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                                buttonAction: {
                                    self.navigationController?.popViewController(animated: true)
                                })
                            return
                        }
                        self.allCandidateArray = result
                        self.applyFilterAndSort()
                        if self.displayCandidateArray.count <= 0 {
                            NiftyUtility.EasyDialogOneButton(
                                viewController: self,
                                title: nil,
                                message: self.allCandidateArray.count > 0
                                    ? NSLocalizedString("RubyNotationSpeechModCreateViewController_RubyFoundButNoEffect", comment: "ルビ表記は見つかりましたが、どれも常にルビが振られているため、読みの修正として登録しても新しく直る箇所がありません。\n(「ルビはルビだけ読む」を有効にしていれば、これらは既に正しく読まれます)")
                                    : NSLocalizedString("RubyNotationSpeechModCreateViewController_RubyNotFound", comment: "この小説からはルビ表記を見つけられませんでした。"),
                                buttonTitle: NSLocalizedString("OK_button", comment: "OK"),
                                buttonAction: {
                                    self.navigationController?.popViewController(animated: true)
                                })
                        }
                    })
                }
            }
        }
    }

    // MARK: - 表示内容の作成

    /// 既にこの小説用に登録されている読み替えを拾っておきます
    func loadRegisteredState() {
        let novelID = self.novelID
        self.registeredAfterTable = RealmUtil.RealmBlock { (realm) -> [String:String] in
            guard let settingArray = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return [:] }
            var result:[String:String] = [:]
            for setting in settingArray where setting.targetNovelIDArray.contains(novelID) {
                result[setting.before] = setting.after
            }
            return result
        }
    }

    func applyFilterAndSort() {
        let searchedArray:[RubyNotationCandidate]
        if filterString.count > 0 {
            searchedArray = self.allCandidateArray.filter({ $0.before.contains(filterString) || $0.after.contains(filterString) })
        } else {
            searchedArray = self.allCandidateArray
        }
        // 表示条件で隠したものを、理由ごとに数えておきます(画面上部に「隠しています」と出すため)。
        // 両方に当てはまるものは、より「登録しても効果が無い」方の理由に数えます。
        var noBareCount = 0
        var shortBeforeCount = 0
        var array:[RubyNotationCandidate] = []
        for candidate in searchedArray {
            if !isShowNoBareCandidate, candidate.bareCount <= 0 { noBareCount += 1; continue }
            if !isShowShortBefore, candidate.isShortBefore { shortBeforeCount += 1; continue }
            array.append(candidate)
        }
        self.hiddenNoBareCount = noBareCount
        self.hiddenShortBeforeCount = shortBeforeCount
        self.displayCandidateArray = RubyNotationExtractor.Sort(candidates: array, sortType: self.sortType)
        self.displayCount = RubyNotationSpeechModCreateViewController.displayCountStep
        self.tableView.reloadData()
        if self.displayCandidateArray.count > 0 {
            self.tableView.setContentOffset(CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top), animated: false)
        }
    }

    /// 隠している候補がある時に、画面上部に出す文言。隠しているものが無ければ nil。
    func hiddenCountDescription() -> String? {
        var reasonArray:[String] = []
        if hiddenNoBareCount > 0 {
            reasonArray.append(String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_HiddenReasonNoBareFormat", comment: "常にルビが振られているもの %d件"), hiddenNoBareCount))
        }
        if hiddenShortBeforeCount > 0 {
            reasonArray.append(String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_HiddenReasonShortFormat", comment: "1文字のもの %d件"), hiddenShortBeforeCount))
        }
        if reasonArray.count <= 0 { return nil }
        return String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_HiddenCountFormat", comment: "%@ を隠しています。タップすると表示します。"), reasonArray.joined(separator: NSLocalizedString("RubyNotationSpeechModCreateViewController_HiddenReasonSeparator", comment: "、")))
    }

    /// 隠しているものを表示するように切り替えます(上部の「隠しています」をタップした時)
    func showHiddenCandidates() {
        if hiddenNoBareCount > 0 { self.isShowNoBareCandidate = true }
        if hiddenShortBeforeCount > 0 { self.isShowShortBefore = true }
        applyFilterAndSort()
        updateNavigationItem()
    }

    // MARK: - UITableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return min(self.displayCount, self.displayCandidateArray.count)
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let text = hiddenCountDescription() else { return nil }
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: RubyNotationHiddenCountHeaderView.reuseID) as? RubyNotationHiddenCountHeaderView
        header?.apply(text: text, tapHandler: { [weak self] in
            self?.showHiddenCandidates()
        })
        return header
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return hiddenCountDescription() == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: RubyNotationSpeechModCreateViewController.cellID, for: indexPath)
        guard indexPath.row < self.displayCandidateArray.count else { return cell }
        let candidate = self.displayCandidateArray[indexPath.row]
        (cell as? RubyNotationCandidateCell)?.apply(
            candidate: candidate,
            isChecked: self.checkedBeforeSet.contains(candidate.before),
            registeredAfter: self.registeredAfterTable[candidate.before])
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // 下の方まで来たら表示件数を増やします。
        // 最初から数千行出すと重くなるので、少しずつ伸ばす形にしています。
        guard self.displayCount < self.displayCandidateArray.count else { return }
        guard indexPath.row >= self.displayCount - 20 else { return }
        let newCount = min(self.displayCount + RubyNotationSpeechModCreateViewController.displayCountStep, self.displayCandidateArray.count)
        guard newCount > self.displayCount else { return }
        let addedIndexPathArray = (self.displayCount ..< newCount).map({ IndexPath(row: $0, section: 0) })
        self.displayCount = newCount
        DispatchQueue.main.async {
            tableView.insertRows(at: addedIndexPathArray, with: .none)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < self.displayCandidateArray.count else { return }
        let candidate = self.displayCandidateArray[indexPath.row]
        if self.checkedBeforeSet.contains(candidate.before) {
            self.checkedBeforeSet.remove(candidate.before)
        } else {
            self.checkedBeforeSet.insert(candidate.before)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateNavigationItem()
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let displayedCount = min(self.displayCount, self.displayCandidateArray.count)
        if self.displayCandidateArray.count <= 0 { return nil }
        return String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_FooterFormat", comment: "%d件中 %d件を表示しています"), self.displayCandidateArray.count, displayedCount)
    }

    // MARK: - 登録

    @objc func registerButtonClicked() {
        let targetArray = self.allCandidateArray.filter({ self.checkedBeforeSet.contains($0.before) })
        if targetArray.count <= 0 { return }
        let novelID = self.novelID

        // 同じ「読み替え前」の設定が既にあって、読み替え後が違うものを拾い出します。
        // RealmSpeechModSetting.before は primary key で、しかも小説を跨いで共有されているため、
        // 何も考えずに上書きすると他の小説用の設定を壊してしまいます。
        var conflictArray:[(candidate:RubyNotationCandidate, currentAfter:String)] = []
        RealmUtil.RealmBlock { (realm) -> Void in
            for candidate in targetArray {
                guard let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: candidate.before) else { continue }
                if setting.after != candidate.after {
                    conflictArray.append((candidate: candidate, currentAfter: setting.after))
                }
            }
        }
        if conflictArray.count <= 0 {
            applyRegister(targetArray: targetArray, novelID: novelID, isOverwriteConflict: false)
            return
        }
        var message = String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_ConflictMessageFormat", comment: "以下の%d件は、既に別の読み替えが登録されています。\n読み替え後をルビの内容で上書きしますか？\n(上書きすると、同じ読み替えを使っている他の小説での読み方も変わります)"), conflictArray.count)
        message += "\n\n"
        for conflict in conflictArray.prefix(10) {
            message += String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_ConflictLineFormat", comment: "%@ : %@ → %@"), conflict.candidate.before, conflict.currentAfter, conflict.candidate.after) + "\n"
        }
        if conflictArray.count > 10 {
            message += String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_ConflictMoreFormat", comment: "ほか %d件"), conflictArray.count - 10) + "\n"
        }
        NiftyUtility.EasyDialogTwoButton(
            viewController: self,
            title: nil,
            message: message,
            button1Title: NSLocalizedString("RubyNotationSpeechModCreateViewController_ConflictKeepCurrent", comment: "既存の読み替えを残す"),
            button1Action: { [weak self] in
                guard let self = self else { return }
                self.applyRegister(targetArray: targetArray, novelID: novelID, isOverwriteConflict: false)
            },
            button2Title: NSLocalizedString("RubyNotationSpeechModCreateViewController_ConflictOverwrite", comment: "上書きする"),
            button2Action: { [weak self] in
                guard let self = self else { return }
                self.applyRegister(targetArray: targetArray, novelID: novelID, isOverwriteConflict: true)
            })
    }

    /// - Parameter isOverwriteConflict: 既存の設定と読み替え後が違う時に、ルビの内容で上書きするかどうか
    /// - Parameter isOverwriteConflict: 既存の設定と読み替え後が違う時に、ルビの内容で上書きするかどうか
    func applyRegister(targetArray:[RubyNotationCandidate], novelID:String, isOverwriteConflict:Bool) {
        var registeredBeforeArray:[String] = []
        var skippedCount = 0
        RealmUtil.Write { (realm) in
            for candidate in targetArray {
                if let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: candidate.before) {
                    // 既存の設定がある場合は、その設定を壊さないように
                    // 「この小説を適用対象に足す」だけにします。
                    if setting.after != candidate.after {
                        if !isOverwriteConflict { skippedCount += 1; continue }
                        setting.after = candidate.after
                        setting.isUseRegularExpression = false
                    }
                    if !setting.targetNovelIDArray.contains(novelID) {
                        setting.targetNovelIDArray.append(novelID)
                    }
                    realm.add(setting, update: .modified)
                } else {
                    let setting = RealmSpeechModSetting()
                    setting.before = candidate.before
                    setting.after = candidate.after
                    setting.isUseRegularExpression = false
                    setting.targetNovelIDArray.append(novelID)
                    realm.add(setting, update: .modified)
                }
                registeredBeforeArray.append(candidate.before)
            }
        }
        // 登録できたものだけチェックを外して「登録済み」に変えます。
        // (既存の読み替えを残した分はチェックを付けたままにして、登録されなかった事が分かるようにする)
        // 抽出には時間がかかるので、画面は閉じずにそのまま続けられるようにしておきます。
        for before in registeredBeforeArray {
            self.checkedBeforeSet.remove(before)
        }
        loadRegisteredState()
        self.tableView.reloadData()
        updateNavigationItem()
        let message:String
        if skippedCount > 0 && registeredBeforeArray.count <= 0 {
            message = NSLocalizedString("RubyNotationSpeechModCreateViewController_NothingRegistered", comment: "既存の読み替えを残したので、何も登録していません")
        } else if skippedCount > 0 {
            message = String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_RegisteredWithSkipFormat", comment: "%d件登録しました (%d件は既存の読み替えを残しました)"), registeredBeforeArray.count, skippedCount)
        } else {
            message = String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_RegisteredFormat", comment: "%d件登録しました"), registeredBeforeArray.count)
        }
        NiftyUtility.ShowFloatingMessage(viewController: self, message: message)
    }
}

/// 候補1件分のセル。
/// 「読み替え前 → 読み替え後」と、その下に本文中の出現数などの手がかりを出します。
class RubyNotationCandidateCell : UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        self.textLabel?.numberOfLines = 0
        self.textLabel?.adjustsFontForContentSizeCategory = true
        self.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.detailTextLabel?.numberOfLines = 0
        self.detailTextLabel?.adjustsFontForContentSizeCategory = true
        self.detailTextLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        self.detailTextLabel?.textColor = .secondaryLabel
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// - Parameter registeredAfter: 既にこの小説用に登録されている読み替え後(登録されていなければ nil)
    func apply(candidate:RubyNotationCandidate, isChecked:Bool, registeredAfter:String?) {
        self.textLabel?.text = String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_CandidateTitleFormat", comment: "%@ → %@"), candidate.before, candidate.after)
        var detailArray:[String] = []
        detailArray.append(String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_BareCountFormat", comment: "ルビ無しで %d箇所 / %d章"), candidate.bareCount, candidate.bareChapterCount))
        detailArray.append(String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_RubyCountFormat", comment: "ルビ付き %d箇所"), candidate.rubyCount))
        if candidate.honorificCount > 0 {
            detailArray.append(NSLocalizedString("RubyNotationSpeechModCreateViewController_MaybePersonName", comment: "人名かも"))
        }
        if candidate.isPartOfOtherCandidate {
            detailArray.append(NSLocalizedString("RubyNotationSpeechModCreateViewController_PartOfOtherWord", comment: "他の語の一部としても出てきます"))
        }
        if let registeredAfter = registeredAfter {
            if registeredAfter == candidate.after {
                detailArray.append(NSLocalizedString("RubyNotationSpeechModCreateViewController_AlreadyRegistered", comment: "登録済み"))
            } else {
                // 同じ読み替え前で違う読み替えが登録されている。登録しようとすると上書きするかを聞かれる。
                detailArray.append(String(format: NSLocalizedString("RubyNotationSpeechModCreateViewController_AlreadyRegisteredWithOtherFormat", comment: "別の読み替えが登録済み (%@)"), registeredAfter))
            }
        }
        self.detailTextLabel?.text = detailArray.joined(separator: " / ")
        self.accessoryType = isChecked ? .checkmark : .none
        self.accessibilityTraits = isChecked ? [.button, .selected] : [.button]
    }
}

/// 「◯件を隠しています」を出すセクションヘッダ。
/// plain スタイルのセクションヘッダは上に貼り付いたままスクロールするので、
/// 候補が何百件あっても、隠しているものがある事に気付けます。
class RubyNotationHiddenCountHeaderView : UITableViewHeaderFooterView {
    static let reuseID = "RubyNotationHiddenCountHeader"
    let label = UILabel()
    var tapHandler:(()->Void)? = nil

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        var background = UIBackgroundConfiguration.listPlainHeaderFooter()
        background.backgroundColor = .secondarySystemBackground
        self.backgroundConfiguration = background
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
        contentView.isUserInteractionEnabled = true
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
        self.isAccessibilityElement = true
        self.accessibilityTraits = .button
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(text:String, tapHandler:@escaping ()->Void) {
        self.label.text = text
        self.accessibilityLabel = text
        self.tapHandler = tapHandler
    }

    @objc func headerTapped() {
        tapHandler?()
    }
}

/// スレッドを跨いで読み書きされるキャンセルの合図。
/// (抽出はバックグラウンドで走り、キャンセルボタンはメインスレッドから押される)
final class CancelFlag {
    private let lock = NSLock()
    private var canceledValue = false
    var isCanceled:Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceledValue
    }
    func cancel() {
        lock.lock()
        canceledValue = true
        lock.unlock()
    }
}
