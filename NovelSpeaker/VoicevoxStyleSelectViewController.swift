//
//  VoicevoxStyleSelectViewController.swift
//  NovelSpeaker
//
//  VOICEVOX のスタイル(話者)を選ぶ画面。
//
//  スタイルは127個あり、その大半は手元に無い。
//  「今すぐ使える物」と「取ってくれば使える物」を節で分けて、
//  キャラクター名やスタイル名で絞り込めるようにしてある。
//
//  未取得の行を選んだ場合は、その場では設定を変えない。
//  規約に同意して取得し、**取得が終わってから**選ばれた事にする。
//  取得は数十MBあり時間がかかるので、
//  途中でやめた時に設定だけ変わってしまうと「喋らなくなった」と映る。
//

import UIKit

#if !os(watchOS)
class VoicevoxStyleSelectViewController: UITableViewController, UISearchResultsUpdating {

    /// 選ばれた時に呼ぶ。styleId をそのまま渡す。
    var onSelected: ((UInt32) -> Void)?
    /// 今選ばれている styleId(取得済みでなくてもよい)。
    var currentStyleId: UInt32?

    private var sections: [VoicevoxStyleListSection] = []
    private var catalog: VoicevoxVoiceModelCatalog?
    private let searchController = UISearchController(searchResultsController: nil)
    /// 取得し終わったら選んでよい styleId。利用者が待っている物。
    private var awaitingStyleId: UInt32?

    static func instantiate(currentStyleId: UInt32?,
                            onSelected: @escaping (UInt32) -> Void) -> VoicevoxStyleSelectViewController {
        let viewController = VoicevoxStyleSelectViewController(style: .grouped)
        viewController.currentStyleId = currentStyleId
        viewController.onSelected = onSelected
        return viewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("SpeakSettingsViewController_VoicevoxStyleTitle", comment: "VOICEVOX話者")
        catalog = VoicevoxVoiceModelCatalogLoader.preferred(
            embedded: VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(), remote: nil)

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString(
            "VoicevoxStyleSelectViewController_SearchPlaceholder", comment: "キャラクター名で絞り込み")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "style")
        NotificationCenter.default.addObserver(
            self, selector: #selector(downloadDidChange),
            name: .voicevoxVoiceModelDownloadDidChange, object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 一覧

    private func reload() {
        sections = VoicevoxStyleListBuilder.build(
            availableStyles: VoicevoxCore.cachedStyles,
            catalog: catalog,
            searchText: searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }

    @objc private func downloadDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 待っていたスタイルが使えるようになったなら、そのまま選んであげる。
            if let awaiting = self.awaitingStyleId,
               VoicevoxCore.cachedStyles.contains(where: { $0.styleId == awaiting }) {
                self.awaitingStyleId = nil
                self.onSelected?(awaiting)
                self.currentStyleId = awaiting
            }
            self.reload()
        }
    }

    private func item(at indexPath: IndexPath) -> VoicevoxStyleListItem? {
        guard indexPath.section < sections.count else { return nil }
        let items = sections[indexPath.section].items
        guard indexPath.row < items.count else { return nil }
        return items[indexPath.row]
    }

    // MARK: - UITableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].kind.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "style", for: indexPath)
        guard let item = item(at: indexPath) else { return cell }
        var content = cell.defaultContentConfiguration()
        content.text = item.displayName
        content.secondaryText = detailText(for: item, kind: sections[indexPath.section].kind)
        cell.contentConfiguration = content
        cell.accessoryType = (item.styleId == currentStyleId) ? .checkmark : .none
        return cell
    }

    /// 未取得の行に「何MB取ってくる事になるのか」を必ず出す。
    /// 押した後で数十MBの取得が始まる、という驚きを作らないため。
    private func detailText(for item: VoicevoxStyleListItem,
                            kind: VoicevoxStyleListSection.Kind) -> String? {
        guard kind == .downloadable, let modelID = item.modelID else { return nil }
        switch VoicevoxVoiceModelDownloader.shared.queue.state(ofModelID: modelID) {
        case .downloading(let receivedBytes, let totalBytes):
            let percent = totalBytes > 0 ? Int(Double(receivedBytes) / Double(totalBytes) * 100) : 0
            return "取得中 \(percent)%"
        case .queued:
            return "取得待ち"
        case .failed(let reason):
            return "取得できませんでした: \(reason)"
        case nil:
            let size = item.megabytesText ?? ""
            return "⬇︎ \(modelID).vvm \(size)"
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = item(at: indexPath) else { return }

        if sections[indexPath.section].kind == .available {
            currentStyleId = item.styleId
            onSelected?(item.styleId)
            tableView.reloadData()
            navigationController?.popViewController(animated: true)
            return
        }

        guard let modelID = item.modelID, let catalog = catalog,
              let model = catalog.model(withID: modelID) else { return }
        // 既に取得中なら二重に積まない。
        if VoicevoxVoiceModelDownloader.shared.queue.state(ofModelID: modelID) != nil {
            awaitingStyleId = item.styleId
            return
        }
        VoicevoxVoiceModelConsentDialog.present(
            on: self, model: model, catalog: catalog,
            requestedStyleDisplayName: item.displayName,
            onStarted: { [weak self] in
                // 取得が終わったらこのスタイルを選ぶ。設定を変えるのはその時。
                self?.awaitingStyleId = item.styleId
                self?.reload()
            })
    }
}
#endif
