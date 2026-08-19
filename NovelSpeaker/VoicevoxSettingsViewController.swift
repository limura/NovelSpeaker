//
//  VoicevoxSettingsViewController.swift
//  NovelSpeaker
//
//  VOICEVOX まわりの設定の入口をここに集める。
//
//  これまでは「作成済みのVOICEVOX音声」「VOICEVOXの音声モデル」「貯金の下限」が
//  設定画面の別々の場所にあり、しかも下限はデバッグ欄に紛れていた。
//  数が増えて探せなくなっていたので、1段掘って束ねる。
//
//  ここに置くのは**入口と、どこにも属さない小さな設定**だけにする。
//  容量の上限のような「その画面を見ながら決める設定」は、
//  その画面(作成済みのVOICEVOX音声)に置いたままにする。
//  設定だけをここに集めると、今の使用量を見ないまま数字を決める事になる。
//

import UIKit
import Eureka

#if !os(watchOS)
class VoicevoxSettingsViewController: FormViewController {

    /// 「貯金の下限」の選択肢(分)。0 は「続けない」。
    /// ステッパーだと桁の大きい値まで押し続ける事になり、
    /// 文字も重なるので、選ぶ形にしてある。
    private static let keepGeneratingChoices = [0, 5, 15, 30, 60, 120, 180]

    private static func keepGeneratingText(minutes: Int) -> String {
        if minutes <= 0 { return "続けない" }
        if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60)時間" }
        return "\(minutes)分"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "VOICEVOX"
        createForm()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 音声モデルを取得・削除して戻ってきた時に、件数の表示を合わせる。
        updateVoiceModelSummary()
    }

    private func createForm() {
        form +++ Section("音声モデル")
        // 取得済みの件数と容量をここに出す(1つ60MB前後あるので、掘らずに分かる方が良い)。
        // ButtonRow では右側に値を出せないので LabelRow を使う。
        <<< LabelRow("VoicevoxVoiceModelRow") {
            $0.title = "音声モデルの取得と削除"
            $0.cell.textLabel?.numberOfLines = 0
        }.cellUpdate({ (cell, _) in
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
        }).onCellSelection({ [weak self] (_, _) in
            self?.navigationController?.pushViewController(
                VoicevoxVoiceModelManageViewController(), animated: true)
        })
        <<< SwitchRow() {
            // 既定は切。1つ60MB前後あるので、黙ってモバイル通信で落とさない。
            // 切のままでも失敗はせず、Wi-Fi に繋がるまで OS が待つ。
            $0.title = "モバイル通信でも取得する"
            $0.value = VoicevoxVoiceModelDownloader.allowsCellularAccess
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ row in
            VoicevoxVoiceModelDownloader.allowsCellularAccess = row.value ?? false
        })

        form +++ Section("作成済みの音声")
        <<< ButtonRow() {
            $0.title = "作成済みのVOICEVOX音声"
            $0.cell.textLabel?.numberOfLines = 0
            $0.presentationMode = .show(controllerProvider: ControllerProvider.callback(builder: {
                return VoicevoxCacheManageViewController()
            }), onDismiss: nil)
        }.cellUpdate({ (cell, _) in
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
            cell.textLabel?.textColor = nil
        })
        <<< PickerInputRow<String>() {
            $0.title = "再生中に生成を続ける貯金の下限"
            $0.options = Self.keepGeneratingChoices.map { Self.keepGeneratingText(minutes: $0) }
            $0.value = Self.keepGeneratingText(minutes: VoicevoxCacheLead.keepGeneratingBelowMinutes)
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange({ row in
            guard let value = row.value,
                  let minutes = Self.keepGeneratingChoices.first(where: {
                      Self.keepGeneratingText(minutes: $0) == value
                  }) else { return }
            VoicevoxCacheLead.keepGeneratingBelowMinutes = minutes
        })

        form +++ Section(footer: "作った音声を公開する場合はクレジット表記が必要です。")
        <<< ButtonRow() {
            $0.title = "クレジット表記"
            $0.cell.textLabel?.numberOfLines = 0
            $0.presentationMode = .show(controllerProvider: ControllerProvider.callback(builder: {
                return VoicevoxCreditViewController()
            }), onDismiss: nil)
        }.cellUpdate({ (cell, _) in
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
            cell.textLabel?.textColor = nil
        })

        updateVoiceModelSummary()
    }

    /// 音声モデルの行に「何件・何MB」を出す。
    private func updateVoiceModelSummary() {
        guard let row = form.rowBy(tag: "VoicevoxVoiceModelRow") as? LabelRow else { return }
        let formats = VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions
        let store = VoicevoxVoiceModelStore.shared
        let count = store.storedModelIDs(readableFormats: formats).count
        let bytes = store.totalBytes(readableFormats: formats)
        row.value = count == 0
            ? "0件"
            : "\(count)件 \(VoicevoxVoiceModelManageListBuilder.megabytesText(bytes))"
        row.updateCell()
    }
}
#endif
