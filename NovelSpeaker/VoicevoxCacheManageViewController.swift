//
//  VoicevoxCacheManageViewController.swift
//  NovelSpeaker
//
//  事前に作った VOICEVOX 音声(ディスクキャッシュ)の確認と削除。
//
//  音声1時間ぶんで約15MB。長編を何作も貯めると簡単に数GBになり、
//  さらに発話設定を変えると同じ箇所の音声が別々に貯まる。
//  「気付いたらストレージが足りない」が起きやすいので、
//   - どれだけ使っているかが見える
//   - 要らない物をまとめて消せる(絞り込み・複数選択)
//   - 今の設定で使われなくなった物を選んで消せる
//   - そもそも上限を決められる
//  という所まで用意する。本棚には出さない(既にごちゃごちゃしているため)。
//

import UIKit
import Eureka
import RealmSwift

class VoicevoxCacheManageViewController: FormViewController, UISearchBarDelegate {

    /// 並び替え。
    ///
    /// 「最近読んでいない物のキャッシュをまとめて消したい」といった用途があるので、
    /// 容量だけでなく読んだ日付でも並べられるようにする。
    /// 本棚のようなフォルダ分けまでは持ち込まない(大掛かりな割に、
    /// この画面でやりたい事は「消す物を見つける」だけなので)。
    enum SortType: Int, CaseIterable {
        case sizeDescending
        case lastReadDateAscending
        case lastReadDateDescending
        case titleAscending
        case novelUpdatedAtDescending

        var title: String {
            switch self {
            case .sizeDescending: return "容量が大きい順"
            case .lastReadDateAscending: return "最近読んでいない順"
            case .lastReadDateDescending: return "最近読んだ順"
            case .titleAscending: return "タイトル順"
            case .novelUpdatedAtDescending: return "更新が新しい順"
            }
        }
    }

    private static let sortTypeUserDefaultsKey = "NovelSpeaker.Voicevox.cacheManageSortType"
    private var sortType: SortType {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.sortTypeUserDefaultsKey)
            return SortType(rawValue: stored) ?? .sizeDescending
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.sortTypeUserDefaultsKey) }
    }

    /// 小説名の絞り込み文字列。
    private var searchText: String = ""
    /// 複数選択して消すためのモード。
    private var isSelecting = false
    private var selectedNovelIDs = Set<String>()

    private let searchBar = UISearchBar()
    /// viewDidLoad で組んだ直後の viewWillAppear で作り直さないための印。
    ///
    /// Eureka の form.removeAll() は「今テーブルに出ている section を消す」形で
    /// tableView に伝わるが、まだ一度も描画されていない段階では tableView 側の
    /// section 数が 0 のままなので
    /// 「attempt to delete section 3, but there are only 0 sections」で落ちる。
    private var hasAppearedOnce = false

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "作成済みのVOICEVOX音声"
        searchBar.placeholder = "小説名で絞り込む"
        searchBar.delegate = self
        searchBar.sizeToFit()
        searchBar.autocapitalizationType = .none
        tableView.tableHeaderView = searchBar
        updateRightBarButton()
        // 生成中はこの画面の数字が増えていくので、進捗に合わせて更新する。
        NotificationCenter.default.addObserver(self, selector: #selector(progressDidChange), name: VoicevoxCacheGenerator.progressDidChangeNotification, object: nil)
        createCells()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 初回は viewDidLoad で組んだ物がそのまま使えるので作り直さない
        //(まだ描画されていない状態で作り直すと落ちる)。
        guard hasAppearedOnce else {
            hasAppearedOnce = true
            return
        }
        reload()
    }

    // MARK: - 絞り込み

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        reload()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - 複数選択

    private func updateRightBarButton() {
        if isSelecting {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "やめる", style: .plain, target: self, action: #selector(endSelecting)),
                UIBarButtonItem(title: "選択を削除", style: .plain, target: self, action: #selector(deleteSelected)),
            ]
        } else {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: "選択", style: .plain, target: self, action: #selector(beginSelecting)),
            ]
        }
    }

    @objc private func beginSelecting() {
        isSelecting = true
        selectedNovelIDs.removeAll()
        updateRightBarButton()
        reload()
    }

    @objc private func endSelecting() {
        isSelecting = false
        selectedNovelIDs.removeAll()
        updateRightBarButton()
        reload()
    }

    @objc private func deleteSelected() {
        let targets = selectedNovelIDs
        guard targets.isEmpty == false else {
            NiftyUtility.EasyDialogMessageDialog(viewController: self, message: "削除する小説が選ばれていません。")
            return
        }
        var summary = VoicevoxDiskCacheSummary.empty
        for novelID in targets {
            summary = summary + VoicevoxDiskCacheStore.shared.summary(novelID: novelID)
        }
        _ = NiftyUtility.EasyDialogTwoButton(
            viewController: self,
            title: "選んだ音声を削除",
            message: "\(targets.count)作品の音声(\(Self.sizeText(summary)))を削除します。\n\n削除しても本文は消えません。",
            button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
            button1Action: nil,
            button2Title: NSLocalizedString("OK_button", comment: "OK"),
            button2Action: { [weak self] in
                for novelID in targets {
                    if VoicevoxCacheGenerator.shared.runningNovelID == novelID {
                        VoicevoxCacheGenerator.shared.stop()
                    }
                    VoicevoxDiskCacheStore.shared.remove(novelID: novelID)
                    VoicevoxCacheGenerationState.shared.setEnabled(false, novelID: novelID)
                }
                DispatchQueue.main.async {
                    self?.endSelecting()
                }
            })
    }

    // MARK: - 更新

    /// 生成中の行だけを書き換える。
    /// 画面ごと作り直すと、スクロール位置が飛んだり操作中の指が外れたりするため。
    @objc private func progressDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let novelID = VoicevoxCacheGenerator.shared.runningNovelID,
                  let row = self.form.rowBy(tag: Self.rowTag(novelID: novelID)) as? ButtonRow else {
                // 生成が終わった時は並び順(容量の大きい順)も変わるので作り直す。
                self.reload()
                return
            }
            row.title = self.rowTitle(novelID: novelID)
            row.updateCell()
            // 行数が変わっても高さは自動では再計算されないので、明示的に組み直す
            //(これが無いと1行に潰れて末尾が「…」で切れる)。
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
            if let summaryRow = self.form.rowBy(tag: Self.totalRowTag) as? LabelRow {
                summaryRow.title = Self.sizeText(VoicevoxDiskCacheStore.shared.totalSummary())
                summaryRow.updateCell()
            }
        }
    }

    private static let totalRowTag = "VoicevoxCacheTotalRow"
    private static func rowTag(novelID: String) -> String { return "VoicevoxCacheNovelRow-\(novelID)" }

    private func reload() {
        form.removeAll()
        createCells()
        tableView.reloadData()
    }

    // MARK: - 表示文言

    private static func novelTitle(novelID: String) -> String {
        return RealmUtil.RealmBlock { (realm) -> String? in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.title
        } ?? "(本棚に無い小説)"
    }

    private static func sizeText(_ summary: VoicevoxDiskCacheSummary) -> String {
        let megabytes = Double(summary.byteCount) / 1024 / 1024
        return "\(VoicevoxCacheGenerationProgress.durationText(seconds: summary.audioSeconds))ぶん / \(String(format: "%.1f", megabytes))MB"
    }

    /// 生成中の小説は、それと分かるように出す。
    private func rowTitle(novelID: String) -> String {
        let summary = VoicevoxDiskCacheStore.shared.summary(novelID: novelID)
        let title = Self.novelTitle(novelID: novelID)
        let mark = isSelecting ? (selectedNovelIDs.contains(novelID) ? "☑︎ " : "☐ ") : ""
        if VoicevoxCacheGenerator.shared.runningNovelID == novelID {
            let progress = VoicevoxCacheGenerator.shared.progress?.description ?? ""
            return "\(mark)▶ 生成中: \(title)\n\(Self.sizeText(summary))" + (progress.isEmpty ? "" : "\n\(progress)")
        }
        return "\(mark)\(title)\n\(Self.sizeText(summary))"
    }

    // MARK: - 画面の組み立て

    private func createCells() {
        let total = VoicevoxDiskCacheStore.shared.totalSummary()
        let summarySection = Section("合計")
        summarySection <<< LabelRow(Self.totalRowTag) {
            $0.title = Self.sizeText(total)
            $0.cell.textLabel?.numberOfLines = 0
        }
        if let freeBytes = VoicevoxCacheGenerator.freeBytes() {
            summarySection <<< LabelRow() {
                $0.title = "端末の空き容量: \(String(format: "%.1f", Double(freeBytes) / 1024 / 1024 / 1024))GB"
                $0.cell.textLabel?.numberOfLines = 0
            }
        }
        form +++ summarySection

        form +++ limitSection()

        let allNovelIDs = VoicevoxDiskCacheStore.shared.cachedNovelIDs()
        if allNovelIDs.isEmpty {
            let emptySection = Section()
            emptySection <<< LabelRow() {
                $0.title = "作成済みの音声はありません。\n小説の詳細画面の「VOICEVOX音声を今の読み上げ位置から生成する」から作れます。"
                $0.cell.textLabel?.numberOfLines = 0
            }
            form +++ emptySection
            return
        }

        var entries = allNovelIDs.map { (novelID: $0, summary: VoicevoxDiskCacheStore.shared.summary(novelID: $0)) }
        if searchText.isEmpty == false {
            entries = entries.filter { Self.novelTitle(novelID: $0.novelID).localizedCaseInsensitiveContains(searchText) }
        }
        entries = sorted(entries: entries)

        form +++ sortSection()

        let sectionTitle = isSelecting ? "小説ごと(タップで選択)" : "小説ごと(タップで削除)"
        let novelSection = Section(entries.isEmpty ? "「\(searchText)」に一致する小説はありません" : sectionTitle)
        for entry in entries {
            let novelID = entry.novelID
            let isGenerating = VoicevoxCacheGenerator.shared.runningNovelID == novelID
            novelSection <<< ButtonRow(Self.rowTag(novelID: novelID)) {
                $0.title = self.rowTitle(novelID: novelID)
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.textAlignment = .left
                if isGenerating {
                    $0.cell.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)
                }
            }.onCellSelection({ [weak self] _, row in
                guard let self = self else { return }
                if self.isSelecting {
                    if self.selectedNovelIDs.contains(novelID) {
                        self.selectedNovelIDs.remove(novelID)
                    } else {
                        self.selectedNovelIDs.insert(novelID)
                    }
                    row.title = self.rowTitle(novelID: novelID)
                    row.updateCell()
                    return
                }
                VoicevoxCacheDeleteDialog.present(on: self, novelID: novelID) { [weak self] in
                    self?.reload()
                }
            })
        }
        form +++ novelSection

        let allSection = Section()
        // 発話設定を変えると、同じ箇所の音声が古い鍵のまま残り続ける。
        // 本文から今の設定で鍵を作り直して、その集合に無い物を消す(ハッシュの逆算は要らない)。
        allSection <<< ButtonRow() {
            $0.title = "今の設定で使われない音声を削除する\n(話者や読みの修正を変えた後の掃除に使えます)"
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ [weak self] _, _ in
            self?.removeUnusedByCurrentSettings()
        })
        allSection <<< ButtonRow() {
            $0.title = "作成済みの音声を全て削除する"
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ [weak self] _, _ in
            guard let self = self else { return }
            _ = NiftyUtility.EasyDialogTwoButton(
                viewController: self,
                title: "作成済みの音声を全て削除",
                message: "作成済みの音声(\(Self.sizeText(total)))を全て削除します。\n\n削除しても本文は消えません。",
                button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
                button1Action: nil,
                button2Title: NSLocalizedString("OK_button", comment: "OK"),
                button2Action: {
                    VoicevoxCacheGenerator.shared.stop()
                    VoicevoxDiskCacheStore.shared.removeAll()
                    for novelID in VoicevoxCacheGenerationState.shared.enabledNovelIDs() {
                        VoicevoxCacheGenerationState.shared.setEnabled(false, novelID: novelID)
                    }
                    DispatchQueue.main.async { self.reload() }
                })
        })
        form +++ allSection
    }

    /// 並び替え。小説の情報は1回の Realm ブロックでまとめて拾う
    /// (小説ごとに Realm を開くと、件数が多い時に目に見えて遅くなる)。
    private func sorted(entries: [(novelID: String, summary: VoicevoxDiskCacheSummary)]) -> [(novelID: String, summary: VoicevoxDiskCacheSummary)] {
        if sortType == .sizeDescending {
            return entries.sorted(by: { $0.summary.byteCount > $1.summary.byteCount })
        }
        struct NovelInfo {
            let title: String
            let lastReadDate: Date
            let novelUpdatedAt: Date
        }
        let infoByNovelID = RealmUtil.RealmBlock { (realm) -> [String: NovelInfo] in
            var result: [String: NovelInfo] = [:]
            for entry in entries {
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: entry.novelID) else { continue }
                result[entry.novelID] = NovelInfo(
                    title: novel.title,
                    lastReadDate: novel.lastReadDate,
                    novelUpdatedAt: novel.lastDownloadDate
                )
            }
            return result
        }
        let distantPast = Date(timeIntervalSince1970: 0)
        switch sortType {
        case .sizeDescending:
            return entries.sorted(by: { $0.summary.byteCount > $1.summary.byteCount })
        case .lastReadDateAscending:
            return entries.sorted(by: { (infoByNovelID[$0.novelID]?.lastReadDate ?? distantPast) < (infoByNovelID[$1.novelID]?.lastReadDate ?? distantPast) })
        case .lastReadDateDescending:
            return entries.sorted(by: { (infoByNovelID[$0.novelID]?.lastReadDate ?? distantPast) > (infoByNovelID[$1.novelID]?.lastReadDate ?? distantPast) })
        case .titleAscending:
            return entries.sorted(by: { (infoByNovelID[$0.novelID]?.title ?? "") < (infoByNovelID[$1.novelID]?.title ?? "") })
        case .novelUpdatedAtDescending:
            return entries.sorted(by: { (infoByNovelID[$0.novelID]?.novelUpdatedAt ?? distantPast) > (infoByNovelID[$1.novelID]?.novelUpdatedAt ?? distantPast) })
        }
    }

    private func sortSection() -> Section {
        let section = Section()
        section <<< PickerInputRow<String>() {
            $0.title = "並び順"
            $0.options = SortType.allCases.map { $0.title }
            $0.value = sortType.title
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ [weak self] row in
            guard let self = self else { return }
            guard let selected = SortType.allCases.first(where: { $0.title == row.value }) else { return }
            self.sortType = selected
            DispatchQueue.main.async { self.reload() }
        })
        return section
    }

    private func limitSection() -> Section {
        let section = Section("使ってよい容量")
        section <<< StepperRow() {
            $0.title = "音声の合計の上限(GB・0で無制限)"
            $0.value = Double(VoicevoxCacheLimits.maximumTotalMegabytes) / 1024
            $0.cell.stepper.minimumValue = 0
            $0.cell.stepper.maximumValue = 64
            $0.cell.stepper.stepValue = 0.5
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ row in
            VoicevoxCacheLimits.maximumTotalMegabytes = Int((row.value ?? 2) * 1024)
        })
        section <<< StepperRow() {
            $0.title = "端末の空き容量がこれを切ったら止める(GB)"
            $0.value = Double(VoicevoxCacheLimits.minimumFreeMegabytes) / 1024
            $0.cell.stepper.minimumValue = 0
            $0.cell.stepper.maximumValue = 32
            $0.cell.stepper.stepValue = 0.5
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ row in
            VoicevoxCacheLimits.minimumFreeMegabytes = Int((row.value ?? 0.5) * 1024)
        })
        section <<< SwitchRow() {
            $0.title = "読み上げ中に合成した分も貯める"
            $0.value = VoicevoxCacheLimits.storesWhilePlaying
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ row in
            VoicevoxCacheLimits.storesWhilePlaying = row.value ?? true
        })
        return section
    }

    // MARK: - 今の設定で使われない音声の削除

    /// 発話設定を変えると鍵が変わり、古い音声は二度と使われないのに残り続ける。
    /// ハッシュの逆算は要らず、今の設定で本文から鍵を作り直して、その集合に無い物を消す。
    ///
    /// 先に「調べるだけ」を行って量を見せてから消す。
    /// 消えた後で「思ったより多かった/少なかった」と分かっても遅いので。
    ///
    /// 調べる対象は**音声を持っている小説だけ**。本棚に何千件あっても、
    /// キャッシュを作った物は普通ごく少数(1作品で数百MB使うため)なので、
    /// 全作品を舐める事にはならない。
    private func removeUnusedByCurrentSettings() {
        let novelIDs = VoicevoxDiskCacheStore.shared.cachedNovelIDs()
        guard novelIDs.isEmpty == false else {
            NiftyUtility.EasyDialogMessageDialog(viewController: self, message: "作成済みの音声がありません。")
            return
        }
        let pageCount = novelIDs.reduce(0) { $0 + VoicevoxDiskCacheStore.shared.chapterNumbers(novelID: $1).count }
        let dialog = NiftyUtility.EasyDialogBuilder(self)
            .label(text: "今の設定で使われない音声を探しています……\n(\(novelIDs.count)作品・\(pageCount)ページ)", textAlignment: .center)
            .build()
        dialog.show()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // (小説ID, ページ番号, 残す鍵) を集めながら、消える量を数える。
            var plan: [(novelID: String, chapterNumber: Int, keysToKeep: Set<String>)] = []
            var unused = VoicevoxDiskCacheSummary.empty
            for novelID in novelIDs {
                let chapterNumbers = VoicevoxDiskCacheStore.shared.chapterNumbers(novelID: novelID)
                let keysByChapter = VoicevoxCacheBlockSource.currentKeysByChapter(novelID: novelID, chapterNumbers: chapterNumbers)
                for chapterNumber in chapterNumbers {
                    let keysToKeep = keysByChapter[chapterNumber] ?? []
                    let chapterUnused = VoicevoxDiskCacheStore.shared.summary(novelID: novelID, chapterNumber: chapterNumber, notIn: keysToKeep)
                    if chapterUnused.entryCount == 0 { continue }
                    unused = unused + chapterUnused
                    plan.append((novelID, chapterNumber, keysToKeep))
                }
            }
            let unusedSummary = unused
            let removalPlan = plan
            DispatchQueue.main.async {
                dialog.dismiss(animated: false) {
                    guard let self = self else { return }
                    guard unusedSummary.entryCount > 0 else {
                        NiftyUtility.EasyDialogMessageDialog(viewController: self, message: "今の設定で使われない音声はありませんでした。")
                        return
                    }
                    _ = NiftyUtility.EasyDialogTwoButton(
                        viewController: self,
                        title: "今の設定で使われない音声",
                        message: "現在の発話設定では \(Self.sizeText(unusedSummary)) の音声が使われません。\n\n削除しますか？\n(削除しても本文は消えません。必要になれば作り直せます)",
                        button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
                        button1Action: nil,
                        button2Title: "削除する",
                        button2Action: { [weak self] in
                            DispatchQueue.global(qos: .userInitiated).async {
                                for entry in removalPlan {
                                    VoicevoxDiskCacheStore.shared.removeEntries(
                                        novelID: entry.novelID,
                                        chapterNumber: entry.chapterNumber,
                                        notIn: entry.keysToKeep
                                    )
                                }
                                DispatchQueue.main.async { self?.reload() }
                            }
                        })
                }
            }
        }
    }
}
