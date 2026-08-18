//
//  VoicevoxVoiceModelManageViewController.swift
//  NovelSpeaker
//
//  設定 →「VOICEVOXの音声モデル」。取得済みの確認・取得・削除。
//
//  「作成済みのVOICEVOX音声」の隣に置く。
//  音声モデル(1.4GB)と作り置きした音声(数GB)は別々に貯まるので、
//  管理する場所も隣り合っていないと、どちらを消せばよいのか分からなくなる。
//
//  ★消しても、作り置きした音声はそのまま鳴る。
//  音声のディスクキャッシュの鍵は styleId と本文から作っていて、
//  音声モデルの有無とは関係が無いため。
//  「全部作り終わったら音声モデルは消してよい」は 1.4GB の逃げ道になるので、
//  削除の確認ダイアログにも書いておく。
//

import UIKit
import RealmSwift

#if !os(watchOS)
class VoicevoxVoiceModelManageViewController: UITableViewController, UISearchResultsUpdating {

    private var sections: [VoicevoxVoiceModelManageSection] = []
    private var catalog: VoicevoxVoiceModelCatalog?
    private var summaryText: String = ""
    private var warningText: String?
    private let searchController = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "VOICEVOXの音声モデル"
        catalog = VoicevoxVoiceModelCatalogLoader.preferred(
            embedded: VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(), remote: nil)

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString(
            "VoicevoxStyleSelectViewController_SearchPlaceholder", comment: "キャラクター名で絞り込み")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "model")
        NotificationCenter.default.addObserver(
            self, selector: #selector(downloadDidChange),
            name: .voicevoxVoiceModelDownloadDidChange, object: nil)
        reload()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 集計

    /// styleId → その styleId を指している話者設定の名前。
    /// 「消してよいか」を決めるのに要る。
    private static func settingNamesByStyleId() -> [UInt32: [String]] {
        return RealmUtil.RealmBlock { (realm) -> [UInt32: [String]] in
            var result: [UInt32: [String]] = [:]
            guard let settings = RealmSpeakerSetting.GetAllObjectsWith(realm: realm) else { return result }
            for setting in settings where setting.type == "VOICEVOX" {
                guard let styleId = UInt32(setting.voiceIdentifier) else { continue }
                result[styleId, default: []].append(setting.name)
            }
            return result
        }
    }

    private func reload() {
        let store = VoicevoxVoiceModelStore.shared
        let formats = VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions
        let storedModelIDs = Set(store.storedModelIDs(readableFormats: formats).keys)
        let byStyleId = Self.settingNamesByStyleId()

        sections = VoicevoxVoiceModelManageListBuilder.build(
            catalog: catalog,
            storedModelIDs: storedModelIDs,
            settingNamesByStyleId: byStyleId,
            searchText: searchController.searchBar.text ?? "")
        summaryText = VoicevoxVoiceModelManageListBuilder.summaryText(
            storedCount: storedModelIDs.count,
            storedBytes: store.totalBytes(readableFormats: formats),
            generatedAudioBytes: Int64(VoicevoxDiskCacheStore.shared.totalSummary().byteCount),
            freeBytes: VoicevoxVoiceModelDownloader.freeDiskBytes())
        warningText = VoicevoxVoiceModelManageListBuilder.missingModelWarning(
            settingNamesByStyleId: byStyleId,
            availableStyleIds: Set(VoicevoxCore.cachedStyles.map { $0.styleId }))
        tableView.reloadData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }

    @objc private func downloadDidChange() {
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    // MARK: - UITableView

    /// 0番目は要約と注意書き。1番目以降が音声モデル。
    private func modelSection(_ section: Int) -> VoicevoxVoiceModelManageSection? {
        let index = section - 1
        guard index >= 0, index < sections.count else { return nil }
        return sections[index]
    }

    private func item(at indexPath: IndexPath) -> VoicevoxVoiceModelManageItem? {
        guard let section = modelSection(indexPath.section),
              indexPath.row < section.items.count else { return nil }
        return section.items[indexPath.row]
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count + 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return warningText == nil ? 1 : 2 }
        return modelSection(section)?.items.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return nil }
        return modelSection(section)?.kind.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "model", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .default

        if indexPath.section == 0 {
            content.text = indexPath.row == 0 ? summaryText : warningText
            content.textProperties.numberOfLines = 0
            if indexPath.row == 1 { content.textProperties.color = .systemOrange }
            cell.selectionStyle = .none
            cell.contentConfiguration = content
            return cell
        }

        guard let item = item(at: indexPath) else { return cell }
        content.text = "\(item.fileName)  \(item.megabytesText)"
        content.secondaryText = detailText(for: item)
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = item.isStored ? .disclosureIndicator : .none
        return cell
    }

    private func detailText(for item: VoicevoxVoiceModelManageItem) -> String {
        var lines = [item.speakerNamesText]
        switch VoicevoxVoiceModelDownloader.shared.queue.state(ofModelID: item.modelID) {
        case .downloading(let receivedBytes, let totalBytes):
            let percent = totalBytes > 0 ? Int(Double(receivedBytes) / Double(totalBytes) * 100) : 0
            lines.append("取得中 \(percent)%")
        case .queued:
            lines.append("取得待ち")
        case .failed(let reason):
            lines.append("取得できませんでした: \(reason)")
        case nil:
            if item.usedBySettingNames.isEmpty == false {
                lines.append("使っている話者設定: \(item.usedBySettingNames.joined(separator: "、"))")
            }
        }
        return lines.joined(separator: "\n")
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = item(at: indexPath) else { return }

        if item.isStored {
            presentDeleteConfirm(item: item)
            return
        }
        if VoicevoxVoiceModelDownloader.shared.queue.state(ofModelID: item.modelID) != nil {
            // 取得中の物を押しても何もしない(取り消しは長押しの方に置いてある)。
            return
        }
        guard let catalog = catalog, let model = catalog.model(withID: item.modelID) else { return }
        VoicevoxVoiceModelConsentDialog.present(
            on: self, model: model, catalog: catalog,
            requestedStyleDisplayName: nil,
            onStarted: { [weak self] in self?.reload() })
    }

    // MARK: - 削除

    private func presentDeleteConfirm(item: VoicevoxVoiceModelManageItem) {
        var message = "\(item.fileName) (\(item.megabytesText))\n\(item.speakerNamesText)\n\n"
        if item.usedBySettingNames.isEmpty {
            message += "この音声モデルを使っている話者設定はありません。\n"
        } else {
            message += "使っている話者設定: \(item.usedBySettingNames.joined(separator: "、"))\n"
                + "消しても設定はそのままにしておくので、取り直せば元の声に戻ります。\n"
        }
        // ★1.4GB の逃げ道。ここに書いておかないと気付かれない。
        message += "\n作成済みのVOICEVOX音声はそのまま再生できます。"
            + "作り終わった音声モデルは消してしまって構いません。"

        NiftyUtility.EasyDialogBuilder(self)
            .title(title: "音声モデルを削除")
            .label(text: message, textAlignment: .left)
            .addButton(title: "削除", callback: { [weak self] dialog in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false) {
                        VoicevoxVoiceModelStore.shared.remove(
                            modelID: item.modelID,
                            readableFormats: VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions)
                        // 消しただけでは話者一覧に残り続けるので作り直す。
                        VoicevoxCore.reloadStyleCatalogFromCurrentFiles()
                        self?.reload()
                    }
                }
            })
            .addButton(title: NSLocalizedString("Cancel_button", comment: "キャンセル"), callback: { dialog in
                DispatchQueue.main.async { dialog.dismiss(animated: true) }
            })
            .build().show()
    }
}
#endif
