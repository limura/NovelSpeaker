//
//  VoicevoxCreditViewController.swift
//  NovelSpeaker
//
//  VOICEVOX のクレジット表記。「このアプリについて」の並びに常設する。
//
//  取得前に規約を提示して同意を取るだけでは足りず、
//  **クレジット表記を出し続ける**所までが利用の条件になっている。
//  取得済みのキャラクターだけを並べるので、消せばその行も消える。
//
//  クレジットの文字列はカタログの物をそのまま出す。
//  話者名から組み立ててはいけない
//  (もち子さん の表記は "VOICEVOX:もち子(cv 明日葉よもぎ)" で話者名と違う)。
//

import UIKit

#if !os(watchOS)
class VoicevoxCreditViewController: UITableViewController {

    private var entries: [VoicevoxCreditList.Entry] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "VOICEVOX のクレジット表記"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "credit")
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        let catalog = VoicevoxVoiceModelCatalogLoader.preferred(
            embedded: VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(), remote: nil)
        let stored = Set(VoicevoxVoiceModelStore.shared.storedModelIDs(
            readableFormats: VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions).keys)
        entries = VoicevoxCreditList.entries(catalog: catalog, storedModelIDs: stored)
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // 1件も取得していない時は、その旨の1行を出す(空の画面にしない)。
        return max(entries.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "作った音声を公開する場合は、次の表記が必要です"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "行を選ぶと、そのキャラクターの利用規約を開きます。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "credit", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        guard entries.isEmpty == false else {
            content.text = "取得済みの音声モデルはありません。"
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            cell.accessoryType = .none
            return cell
        }
        let entry = entries[indexPath.row]
        content.text = entry.credit
        content.secondaryText = entry.termsURL
        cell.contentConfiguration = content
        cell.selectionStyle = entry.termsURL == nil ? .none : .default
        cell.accessoryType = entry.termsURL == nil ? .none : .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < entries.count,
              let termsURL = entries[indexPath.row].termsURL,
              let url = URL(string: termsURL) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
#endif
