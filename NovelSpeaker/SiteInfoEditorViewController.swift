//
//  SiteInfoEditorViewController.swift
//  NovelSpeaker
//
//  最優先SiteInfo(この端末で編集され最優先で適用されるSiteInfo)の編集・追加と、
//  「この値で今すぐテスト」(本番にもキャッシュにも書かずにスクレイプ検査)を行う画面群。
//  設計メモ: DESIGN_SiteInfoエディタ.md / DESIGN_スクレイプ検査.md
//
//  画面構成:
//   - SiteInfoEditorEntryViewController … 最初に出るリスト。[最優先SiteInfo](この端末で編集・最優先適用)/
//     [標準データ(取得日)] の2セクション。＋ボタンで新規作成、行選択で編集画面へ。編集ボタンで削除モード(Catalystはスワイプ不可のため)。
//   - SiteInfoEditorViewController … 1サイト分の生セル(列→値の辞書)を編集。テスト/保存。
//     編集中の値が「同id の標準データ(キャッシュ)」とカラム単位で違う場合、その項目を目立たせる(編集すべきでない列を触っていないか気づくため)。
//
//  方針:
//   - 正本は「生セル文字列(列→値の辞書) cells」。本文系で編集するのは newPageElement のみ(pageElement は派生)。
//   - テスト時は cells → StorySiteInfo.makeFromCellDict → ScrapeInspector.InspectSingleSiteInfo(キャッシュ非依存)。
//   - 保存は LocalSiteInfoStore(ローカルCSV)へ upsert。常に最優先として適用される(空なら適用なし)。
//   - ユーザの目に触れる文字列は NSLocalizedString で日英ローカライズする(列名等の識別子はそのまま)。
//

#if !os(watchOS)

import Foundation
import UIKit
import Eureka

// MARK: - 最初に出るリスト画面(既存を選ぶ / 新規作成)

class SiteInfoEditorEntryViewController: UITableViewController, UISearchResultsUpdating {
    private var localRowsAll: [[String:String]] = []
    private var standardCellsAll: [[String:String]] = []
    private var localRows: [[String:String]] = []
    private var standardCells: [[String:String]] = []
    private var standardDateText: String? = nil
    private let searchController = UISearchController(searchResultsController: nil)
    private let cellID = "SiteInfoEntryCell"
    // section 0=操作(Export 等。ナビバーが狭い iOS26 対策で画面内に置く)/ 1=最優先SiteInfo / 2=標準データ
    private let actionSection = 0
    private let localSection = 1
    private let standardSection = 2

    init() { super.init(style: .insetGrouped) } // grouped でセクションの区切りを目立たせる
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("SiteInfoEditor_Title", comment: "最優先SiteInfoの編集・追加")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellID)
        // セクション見出しに説明文(複数行)を入れるので、見出しを内容に合わせて自動高さにする。
        tableView.estimatedSectionHeaderHeight = 44
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newButtonTapped))
        addButton.accessibilityLabel = NSLocalizedString("SiteInfoEditor_New", comment: "新規作成")
        // editButtonItem は「編集」/「完了」をトグルし削除コントロールを出す(Catalyst でスワイプ削除できないため)。
        // back ボタンを潰さないよう右側に置く。
        navigationItem.rightBarButtonItems = [addButton, editButtonItem]
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("SiteInfoEditor_SearchPlaceholder", comment: "サイト名・url で絞り込み")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadDataFromStores() // 編集画面から戻った時に保存/削除を反映する
    }

    private func reloadDataFromStores() {
        localRowsAll = LocalSiteInfoStore.shared.rows
        var seen = Set<String>()
        var cells: [[String:String]] = []
        for array in StoryHtmlDecoder.shared.siteInfoArrayArray {
            for siteInfo in array {
                let key = siteInfo.url?.pattern ?? "(no-url):\(siteInfo.id)"
                if seen.contains(key) { continue }
                seen.insert(key)
                cells.append(siteInfo.toCellDict())
            }
        }
        cells.sort { ($0["name"] ?? "") < ($1["name"] ?? "") }
        standardCellsAll = cells
        if let date = StoryHtmlDecoder.shared.standardDataFetchedDate() {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateStyle = .medium
            f.timeStyle = .none
            standardDateText = f.string(from: date)
        } else {
            standardDateText = nil
        }
        applyFilter()
    }

    private func matches(_ cells: [String:String], _ text: String) -> Bool {
        if text.isEmpty { return true }
        return (cells["name"] ?? "").localizedCaseInsensitiveContains(text)
            || (cells["url"] ?? "").localizedCaseInsensitiveContains(text)
    }

    private func applyFilter() {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespaces)
        localRows = localRowsAll.filter { matches($0, text) }
        standardCells = standardCellsAll.filter { matches($0, text) }
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }

    private func cells(at indexPath: IndexPath) -> [String:String] {
        return indexPath.section == localSection ? localRows[indexPath.row] : standardCells[indexPath.row]
    }

    // MARK: 新規作成 / 編集画面へ

    @objc private func newButtonTapped() {
        pushEditor(with: [:])
    }

    private func pushEditor(with cells: [String:String]) {
        let editor = SiteInfoEditorViewController(initialCells: cells)
        navigationController?.pushViewController(editor, animated: true)
    }

    // MARK: テーブル

    override func numberOfSections(in tableView: UITableView) -> Int { return 3 }

    // 説明文は「リスト末尾だと最優先SiteInfoが増えた時に画面外へ追い出される」ため、見出し(タイトル直下)に入れる。
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == actionSection { return NSLocalizedString("SiteInfoEditor_ActionSection", comment: "操作") }
        if section == localSection {
            let desc = localRows.isEmpty
                ? NSLocalizedString("SiteInfoEditor_LocalHeaderDescEmpty", comment: "この端末で編集され、最優先で適用されるSiteInfo。まだありません。右上の＋で新規作成、または下の標準データから選んで編集できます。")
                : NSLocalizedString("SiteInfoEditor_LocalHeaderDesc", comment: "この端末で編集され、最優先で適用されます。削除は右上の「編集」ボタンから。")
            return NSLocalizedString("SiteInfoEditor_LocalSectionTitle", comment: "最優先SiteInfo") + "\n" + desc
        }
        let title = standardDateText.map { String(format: NSLocalizedString("SiteInfoEditor_StandardSectionTitleWithDate", comment: "標準データ(%@ 取得分)"), $0) }
            ?? NSLocalizedString("SiteInfoEditor_StandardSectionTitle", comment: "標準データ")
        return title + "\n" + NSLocalizedString("SiteInfoEditor_StandardHeaderDesc", comment: "アプリに読み込まれている標準のSiteInfo。選ぶと内容を引き継いで編集し、最優先SiteInfoとして保存できます。")
    }

    // 見出しの説明文を折り返し表示できるよう、ヘッダのラベルを複数行にする。
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        (view as? UITableViewHeaderFooterView)?.textLabel?.numberOfLines = 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == actionSection { return 1 }
        return section == localSection ? localRows.count : standardCells.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
        if indexPath.section == actionSection {
            var config = cell.defaultContentConfiguration()
            config.text = NSLocalizedString("SiteInfoEditor_Export", comment: "CSVで書き出して共有(Export)")
            config.textProperties.color = cell.tintColor
            cell.contentConfiguration = config
            cell.accessibilityLabel = NSLocalizedString("SiteInfoEditor_Export", comment: "CSVで書き出して共有(Export)")
            cell.accessoryType = .none
            return cell
        }
        let c = cells(at: indexPath)
        let name = (c["name"]?.isEmpty == false ? c["name"]! : NSLocalizedString("SiteInfoEditor_NoName", comment: "(名称未設定)"))
        let url = (c["url"]?.isEmpty == false ? c["url"]! : NSLocalizedString("SiteInfoEditor_NoURL", comment: "(url未設定)"))
        var config = cell.defaultContentConfiguration()
        config.text = name
        config.secondaryText = url
        config.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = config
        // VoiceOver: 名称を読み上げ、url は補足値にする(セクション見出しで最優先/標準の区別は読まれる)。
        cell.accessibilityLabel = name
        cell.accessibilityValue = url
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == actionSection {
            exportCSV(from: tableView.cellForRow(at: indexPath))
            return
        }
        pushEditor(with: cells(at: indexPath))
    }

    // MARK: Export(共有シートで CSV ファイルを出す)

    private func exportCSV(from sourceCell: UITableViewCell?) {
        if LocalSiteInfoStore.shared.rows.isEmpty {
            NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("SiteInfoEditor_ExportEmpty", comment: "書き出せる最優先SiteInfoがありません。先に編集・保存してください。"), buttonTitle: nil, buttonAction: nil)
            return
        }
        let csv = LocalSiteInfoStore.shared.csvString()
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(NSLocalizedString("SiteInfoEditor_ExportFileName", comment: "ことせかい_最優先SiteInfo.csv"))
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NiftyUtility.EasyDialogOneButton(viewController: self, title: nil, message: NSLocalizedString("SiteInfoEditor_ExportCreateFailed", comment: "CSVファイルの作成に失敗しました。"), buttonTitle: nil, buttonAction: nil)
            return
        }
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        // iPad/Catalyst は popover の源を指定しないとクラッシュする。
        if let pop = activity.popoverPresentationController {
            if let cell = sourceCell {
                pop.sourceView = cell
                pop.sourceRect = cell.bounds
            } else {
                pop.sourceView = self.view
                pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            }
        }
        present(activity, animated: true, completion: nil)
    }

    // MARK: 削除(最優先SiteInfo のみ。編集ボタンON時に削除コントロールが出る)

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == localSection
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return indexPath.section == localSection ? .delete : .none
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.section == localSection else { return }
        let urlPattern = localRows[indexPath.row]["url"] ?? ""
        LocalSiteInfoStore.shared.delete(urlPattern: urlPattern)
        _ = LocalSiteInfoStore.shared.save()
        StoryHtmlDecoder.shared.ReloadLocalPreferredSiteInfo()
        localRows.remove(at: indexPath.row)
        localRowsAll.removeAll { ($0["url"] ?? "") == urlPattern }
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }
}

// MARK: - 1サイト分の編集画面

class SiteInfoEditorViewController: FormViewController {

    // 生セル(列名→値)。これを正本として編集する。テスト時に StorySiteInfo へパースする。
    private var cells: [String: String]
    // 同id の標準データ(キャッシュ)。差分(標準と違うカラム)を目立たせる基準。無ければ nil。
    private var baselineCells: [String: String]?

    init(initialCells: [String: String]) {
        self.cells = initialCells
        super.init(style: .grouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 1行テキストで編集する列(タグ = 列名)。タイトルのうち日本語の説明を含むものだけローカライズする(列名自体は識別子なので不変)。
    private static let singleLineColumns: [(tag: String, title: String)] = [
        ("name", NSLocalizedString("SiteInfoEditor_Col_name", comment: "name (サイト名)")),
        ("url", NSLocalizedString("SiteInfoEditor_Col_url", comment: "url (マッチ正規表現)")),
        ("title", "title"),
        ("subtitle", "subtitle"),
        ("firstPageLink", "firstPageLink"),
        ("nextLink", "nextLink"),
        ("tag", "tag"),
        ("author", "author"),
        ("injectStyle", "injectStyle"),
        ("nextButton", "nextButton"),
        ("firstPageButton", "firstPageButton"),
        ("forceClickButton", "forceClickButton"),
        ("resourceUrl", "resourceUrl"),
        ("overrideUserAgent", "overrideUserAgent"),
        ("scrollTo", "scrollTo"),
        ("waitSecondInHeadless", NSLocalizedString("SiteInfoEditor_Col_waitSecondInHeadless", comment: "waitSecondInHeadless (秒)")),
    ]

    // 複数行テキストで編集する列。
    private static let multiLineColumns: [(tag: String, title: String, placeholder: String)] = [
        ("newPageElement", NSLocalizedString("SiteInfoEditor_Col_newPageElement", comment: "newPageElement (本文のxpath。または複数の取り込み対象を指定するために複数行で『ID:タイトル/title=xpath』の形式)"), "//div[@id='novel_honbun']"),
        ("forceErrorMessageAndElement", NSLocalizedString("SiteInfoEditor_Col_forceErrorMessageAndElement", comment: "forceErrorMessageAndElement (gate文言:xpath)"), "ログインが必要です://xpath"),
        ("checkTargets", NSLocalizedString("SiteInfoEditor_Col_checkTargets", comment: "checkTargets (検査対象。1行1エントリ / [auth] URL => content,nextLink)"), "[auth] https://example.com/n/1/ => content,nextLink"),
    ]

    // ON/OFF(文字列 "true"/"false" として cells に持つ)で編集する列。
    private static let boolColumns: [(tag: String, title: String)] = [
        ("isNeedHeadless", "isNeedHeadless"),
        ("isNeedWhitespaceSplitForTag", "isNeedWhitespaceSplitForTag"),
    ]

    private static let falseValues: Set<String> = ["false", "False", "nil", "0", ""]

    // 列 → 表示タイトル(差分マーカーの付け外しで素のタイトルへ戻すために使う)。
    private static let columnTitle: [String: String] = {
        var m: [String: String] = [:]
        for c in singleLineColumns { m[c.tag] = c.title }
        for c in boolColumns { m[c.tag] = c.title }
        for c in multiLineColumns { m[c.tag] = c.title }
        return m
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("SiteInfoEditor_Title", comment: "最優先SiteInfoの編集・追加")
        // テスト/保存ボタンはフォーム内にもあるが、スクロールで画面外に出ても押せるようナビバー右上にも置く(短く)。
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: NSLocalizedString("SiteInfoEditor_Test", comment: "テスト"), style: .plain, target: self, action: #selector(testBarButtonTapped)),
            UIBarButtonItem(title: NSLocalizedString("SiteInfoEditor_Save", comment: "保存"), style: .plain, target: self, action: #selector(saveBarButtonTapped)),
        ]
        recomputeBaseline()
        buildForm()
        refreshAllDiffIndicators()
    }

    @objc private func testBarButtonTapped() { runTest() }
    @objc private func saveBarButtonTapped() { saveToLocalStore() }

    private func recomputeBaseline() {
        baselineCells = (cells["id"]).flatMap { StoryHtmlDecoder.shared.standardSiteInfoCellsById($0) }
    }

    private func buildForm() {
        let actionSection = Section(NSLocalizedString("SiteInfoEditor_ActionSection", comment: "操作"))
        form +++ actionSection
        actionSection <<< ButtonRow() {
            $0.title = NSLocalizedString("SiteInfoEditor_TestNow", comment: "この値で今すぐテスト")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ [weak self] _, _ in
            self?.runTest()
        })
        // 「スプレッドシート用にコピー」は通常は作者しか使わないので、設定タブのデバッグメニューで ON にした時だけ表示する。
        if NovelSpeakerUtility.GetIsSiteInfoEditorSpreadsheetCopyEnabled() {
            actionSection <<< ButtonRow() {
                $0.title = NSLocalizedString("SiteInfoEditor_CopyForSpreadsheet", comment: "スプレッドシート用にコピー")
                $0.cell.textLabel?.numberOfLines = 0
            }.onCellSelection({ [weak self] _, _ in
                self?.copyForSpreadsheet()
            })
        }

        // 識別用に id を表示(編集はしない。RealmNovelImportSetting 紐付けキーのため)。
        let infoSection = Section(NSLocalizedString("SiteInfoEditor_FieldsSection", comment: "SiteInfo の項目"))
        form +++ infoSection
        infoSection <<< LabelRow("id") {
            $0.title = "id"
            $0.cell.detailTextLabel?.numberOfLines = 0
            $0.value = cells["id"]
        }

        for col in SiteInfoEditorViewController.singleLineColumns {
            infoSection <<< TextRow(col.tag) {
                $0.title = col.title
                $0.cell.textField.autocorrectionType = .no
                $0.cell.textField.autocapitalizationType = .none
                $0.value = cells[col.tag]
            }.onChange({ [weak self] row in
                self?.cells[col.tag] = row.value
                if col.tag == "url" { self?.validateUrlRow(row) }
                self?.refreshDiffIndicator(for: col.tag)
            }).cellUpdate({ [weak self] cell, row in
                // url 正規表現が壊れていると isMatchUrl が常に false でテストが走らない。崩れを赤字で示す。
                if row.tag == "url" { self?.colorUrlCell(cell, row: row) }
            })
        }

        for col in SiteInfoEditorViewController.multiLineColumns {
            // TextAreaRow は値が入ると placeholder が消えて何の項目か分からなくなるため、
            // 直前に常時表示の説明ラベル(項目名+入力例)を置く。差分マーカーもこのラベルへ付ける(タグ desc:<列>)。
            infoSection <<< LabelRow("desc:\(col.tag)") {
                $0.title = col.title
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = .preferredFont(forTextStyle: .caption1)
            }
            <<< TextAreaRow(col.tag) {
                $0.placeholder = col.placeholder
                $0.textAreaHeight = .dynamic(initialTextViewHeight: 90)
                $0.cell.textView.autocorrectionType = .no
                $0.cell.textView.autocapitalizationType = .none
                $0.value = cells[col.tag]
            }.onChange({ [weak self] row in
                self?.cells[col.tag] = row.value
                self?.refreshDiffIndicator(for: col.tag)
            })
        }

        for col in SiteInfoEditorViewController.boolColumns {
            infoSection <<< SwitchRow(col.tag) {
                $0.title = col.title
                $0.value = boolValue(cells[col.tag])
            }.onChange({ [weak self] row in
                self?.cells[col.tag] = (row.value ?? false) ? "true" : "false"
                self?.refreshDiffIndicator(for: col.tag)
            })
        }
    }

    private func boolValue(_ string: String?) -> Bool {
        guard let string = string else { return false }
        return !SiteInfoEditorViewController.falseValues.contains(string)
    }

    // MARK: - 差分(標準データと違うカラム)の強調

    // 差分マーカーを付ける対象 row のタグ(複数行は説明ラベル desc:<列>、その他は列row自身)。
    private func indicatorTag(for column: String) -> String {
        if SiteInfoEditorViewController.multiLineColumns.contains(where: { $0.tag == column }) {
            return "desc:\(column)"
        }
        return column
    }

    private func isChangedFromBaseline(_ column: String) -> Bool {
        guard let baseline = baselineCells else { return false }
        return (cells[column] ?? "") != (baseline[column] ?? "")
    }

    private func refreshDiffIndicator(for column: String) {
        guard let title = SiteInfoEditorViewController.columnTitle[column] else { return }
        let changed = isChangedFromBaseline(column)
        let marked = changed ? String(format: NSLocalizedString("SiteInfoEditor_DiffMarker", comment: "⚠️ %@（標準データと差分あり）"), title) : title
        guard let row = form.allRows.first(where: { $0.tag == indicatorTag(for: column) }) else { return }
        if let labelRow = row as? LabelRow {
            labelRow.title = marked
            labelRow.updateCell()
        } else if let textRow = row as? TextRow {
            textRow.title = marked
            textRow.updateCell()
        } else if let switchRow = row as? SwitchRow {
            switchRow.title = marked
            switchRow.updateCell()
        }
    }

    private func refreshAllDiffIndicators() {
        for column in SiteInfoEditorViewController.columnTitle.keys {
            refreshDiffIndicator(for: column)
        }
    }

    // MARK: - URL 正規表現バリデーション

    private func urlCompileError(_ pattern: String?) -> String? {
        guard let pattern = pattern, !pattern.isEmpty else { return nil } // 空は「未入力」でエラー表示しない
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [])
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func validateUrlRow(_ row: TextRow) {
        row.updateCell()
    }

    private func colorUrlCell(_ cell: TextCell, row: TextRow) {
        if urlCompileError(row.value) != nil {
            cell.textLabel?.textColor = .systemRed
        } else {
            cell.textLabel?.textColor = nil
        }
    }

    // MARK: - 保存(ローカル最優先SiteInfo)

    private func saveToLocalStore() {
        view.endEditing(true)
        // url 必須・正規表現コンパイル可否を検証(壊れた url は最優先注入されても isMatchUrl が常に false で無意味)。
        let url = cells["url"] ?? ""
        if url.isEmpty {
            showSimpleAlert(title: NSLocalizedString("SiteInfoEditor_CannotSave", comment: "保存できません"), message: NSLocalizedString("SiteInfoEditor_SaveURLEmpty", comment: "url(マッチ正規表現)が空です。保存するには url を入力してください。"))
            return
        }
        if let err = urlCompileError(url) {
            showSimpleAlert(title: NSLocalizedString("SiteInfoEditor_CannotSave", comment: "保存できません"), message: String(format: NSLocalizedString("SiteInfoEditor_SaveURLRegexError", comment: "url 正規表現がコンパイルできません:\n%@"), err))
            return
        }
        LocalSiteInfoStore.shared.upsert(cells)
        let ok = LocalSiteInfoStore.shared.save()
        StoryHtmlDecoder.shared.ReloadLocalPreferredSiteInfo()
        // 採番された id をフォームへ反映(新規だった場合 id が付与される)。
        if let saved = LocalSiteInfoStore.shared.rows.first(where: { ($0["url"] ?? "") == url }) {
            cells = saved
            applyCellsToForm()
        }
        showSimpleAlert(
            title: ok ? NSLocalizedString("SiteInfoEditor_Saved", comment: "保存しました") : NSLocalizedString("SiteInfoEditor_SaveFailed", comment: "保存に失敗しました"),
            message: ok
                ? NSLocalizedString("SiteInfoEditor_SavedMessage", comment: "この SiteInfo を最優先として保存しました。以降のダウンロード/テストでこの内容が優先されます。\n元に戻す(=最優先をやめる)には一覧へ戻り「編集」ボタンからこの行を削除してください。")
                : NSLocalizedString("SiteInfoEditor_SaveWriteFailed", comment: "ファイルへの書き込みに失敗しました。"))
    }

    private func showSimpleAlert(title: String?, message: String) {
        NiftyUtility.EasyDialogOneButton(viewController: self, title: title, message: message, buttonTitle: nil, buttonAction: nil)
    }

    // MARK: - スプレッドシート用コピー(TSV値方式)

    private func copyForSpreadsheet() {
        view.endEditing(true)
        UIPasteboard.general.string = LocalSiteInfoStore.spreadsheetTSVRow(cells)
        showSimpleAlert(title: NSLocalizedString("SiteInfoEditor_Copied", comment: "コピーしました"), message: NSLocalizedString("SiteInfoEditor_CopiedMessage", comment: "スプレッドシートの id 列のセルから貼り付けてください。pageElement(数式列)は触られず再計算されます。"))
    }

    // cells の内容を各 row へ反映する(タグ一致で値を上書き)。保存後の id 反映などに使う。
    private func applyCellsToForm() {
        for row in form.allRows {
            guard let tag = row.tag else { continue }
            if let switchRow = row as? SwitchRow {
                switchRow.value = boolValue(cells[tag])
                switchRow.updateCell()
            } else if tag == "id", let labelRow = row as? LabelRow {
                labelRow.value = cells[tag]
                labelRow.updateCell()
            } else if let textRow = row as? TextRow {
                textRow.value = cells[tag]
                textRow.updateCell()
            } else if let areaRow = row as? TextAreaRow {
                areaRow.value = cells[tag]
                areaRow.updateCell()
            }
        }
        refreshAllDiffIndicators()
    }

    // MARK: - テスト実行

    private func runTest() {
        view.endEditing(true)
        // 事前バリデーション: url 正規表現の崩れ。
        var preNotes: [String] = []
        if let err = urlCompileError(cells["url"]) {
            preNotes.append(String(format: NSLocalizedString("SiteInfoEditor_Test_URLRegexError", comment: "⚠️ url 正規表現がコンパイルできません(このままだと検査が走りません): %@"), err))
        }
        if (cells["url"]?.isEmpty ?? true) {
            preNotes.append(NSLocalizedString("SiteInfoEditor_Test_URLEmpty", comment: "⚠️ url が空です。isMatchUrl が常に false になり、本番ではこの SiteInfo が選ばれません。"))
        }
        // 特殊フォーマット列(newPageElement の複数行 / forceErrorMessageAndElement / checkTargets)の構文チェック。
        // パーサが黙って無視してしまう書式ミスをテスト時に気づけるようにする。
        let formatWarnings = StorySiteInfo.validateNewPageElementFormat(cells["newPageElement"])
            + StorySiteInfo.validateForceErrorMessageAndElementFormat(cells["forceErrorMessageAndElement"])
            + ScrapeCheckTarget.validateFormat(cells["checkTargets"])
        preNotes += formatWarnings.map { "⚠️ " + $0 }

        let resultTitle = NSLocalizedString("SiteInfoEditor_TestResultTitle", comment: "テスト結果")
        // 生セル → StorySiteInfo。urlString は id の源情報(テスト用ダミー。永続化しないため影響なし)。
        guard let siteInfo = StorySiteInfo.makeFromCellDict(cells, urlString: "siteinfo-editor://local") else {
            showReport(title: resultTitle,
                       body: (preNotes + [NSLocalizedString("SiteInfoEditor_Test_NoNewPageElement", comment: "newPageElement が無いため StorySiteInfo を生成できませんでした。")]).joined(separator: "\n"))
            return
        }

        if siteInfo.checkTargets.isEmpty {
            let body = (preNotes + [
                NSLocalizedString("SiteInfoEditor_Test_NoCheckTargets_1", comment: "checkTargets が未設定です。テスト対象URLがないため検査を実行できません。"),
                NSLocalizedString("SiteInfoEditor_Test_NoCheckTargets_2", comment: "例) checkTargets 欄に下記のように記入してください:"),
                "  https://example.com/n/1/ => content,nextLink",
                NSLocalizedString("SiteInfoEditor_Test_NoCheckTargets_3", comment: "  [auth] 付きで未ログイン時 SKIP 扱いにできます。"),
            ]).joined(separator: "\n")
            showReport(title: resultTitle, body: body)
            return
        }

        let inspector = ScrapeInspector()
        _ = NiftyUtility.EasyDialogNoButton(viewController: self, title: nil, message: NSLocalizedString("SiteInfoEditor_Testing", comment: "テスト中…\n(しばらくお待ちください)"), completion: { dialog in
            inspector.InspectSingleSiteInfo(siteInfo: siteInfo, completion: { results in
                _ = inspector // 完了まで inspector を保持する(InspectSingleSiteInfo 内は [weak self] のため)
                let report = ScrapeInspector.report(results: results)
                let body = preNotes.isEmpty ? report : (preNotes.joined(separator: "\n") + "\n\n" + report)
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        self.showReport(title: resultTitle, body: body)
                    })
                }
            })
        })
    }

    private func showReport(title: String, body: String) {
        NiftyUtility.EasyDialogBuilder(self)
            .title(title: title)
            .textView(content: body, heightMultiplier: 0.6)
            .addButton(title: NSLocalizedString("SettingsTableViewController_AppInformation_CopyLogButtonTitle", comment: "このログをコピーする")) { d in
                UIPasteboard.general.setValue(body, forPasteboardType: "public.text")
                DispatchQueue.main.async { d.dismiss(animated: true, completion: nil) }
            }
            .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { d in
                DispatchQueue.main.async { d.dismiss(animated: true, completion: nil) }
            }
            .build().show()
    }
}

#endif
