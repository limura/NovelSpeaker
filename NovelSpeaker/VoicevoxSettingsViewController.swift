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

    /// 「聴いた所を残しておく時間」の選択肢(分)。0 は「残さない」。
    private static let keepBehindChoices = [0, 5, 10, 20, 30, 60]

    private static func keepGeneratingText(minutes: Int) -> String {
        return durationText(minutes: minutes,
                            zeroText: NSLocalizedString("VoicevoxSettings_KeepGeneratingNever", comment: "続けない"))
    }

    private static func keepBehindText(minutes: Int) -> String {
        return durationText(minutes: minutes,
                            zeroText: NSLocalizedString("VoicevoxSettings_KeepBehindNever", comment: "残さない"))
    }

    private static func durationText(minutes: Int, zeroText: String) -> String {
        if minutes <= 0 { return zeroText }
        if minutes >= 60 && minutes % 60 == 0 { return String(format: NSLocalizedString("VoicevoxSettings_HoursFormat", comment: "%d時間"), minutes / 60) }
        return String(format: NSLocalizedString("VoicevoxSettings_MinutesFormat", comment: "%d分"), minutes)
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
        updateTemporarySummary()
    }

    private func createForm() {
        form +++ Section(NSLocalizedString("VoicevoxSettings_VoiceModelSectionTitle", comment: "音声モデル"))
        // 取得済みの件数と容量をここに出す(1つ60MB前後あるので、掘らずに分かる方が良い)。
        // ButtonRow では右側に値を出せないので LabelRow を使う。
        <<< LabelRow("VoicevoxVoiceModelRow") {
            $0.title = NSLocalizedString("VoicevoxSettings_VoiceModelRowTitle", comment: "音声モデルの取得と削除")
            $0.cell.textLabel?.numberOfLines = 0
        }.cellUpdate({ (cell, row) in
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
            cell.accessibilityHint = NSLocalizedString(
                "VoicevoxSettings_VoiceModelRowHint",
                comment: "VOICEVOXの話者ごとの音声モデルを取得したり削除したりします。1つあたり60MB前後あります。")
        }).onCellSelection({ [weak self] (_, _) in
            self?.navigationController?.pushViewController(
                VoicevoxVoiceModelManageViewController(), animated: true)
        })
        <<< SwitchRow() {
            // 既定は切。1つ60MB前後あるので、黙ってモバイル通信で落とさない。
            // 切のままでも失敗はせず、Wi-Fi に繋がるまで OS が待つ。
            $0.title = NSLocalizedString("VoicevoxSettings_AllowsCellular", comment: "モバイル通信でも取得する")
            $0.value = VoicevoxVoiceModelDownloader.allowsCellularAccess
            $0.cell.textLabel?.numberOfLines = 0
        }.cellUpdate({ (cell, _) in
            cell.accessibilityHint = NSLocalizedString(
                "VoicevoxSettings_AllowsCellularHint",
                comment: "切っている間は取得を諦めずに、Wi-Fi に繋がるまで待ちます。")
        }).onChange({ row in
            VoicevoxVoiceModelDownloader.allowsCellularAccess = row.value ?? false
        })

        form +++ Section(NSLocalizedString("VoicevoxSettings_GeneratedAudioSectionTitle", comment: "作成済みの音声"))
        <<< ButtonRow() {
            $0.title = NSLocalizedString("VoicevoxSettings_CacheManageRowTitle", comment: "作成済みのVOICEVOX音声")
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
            $0.title = NSLocalizedString("VoicevoxSettings_KeepGeneratingRowTitle", comment: "読み上げ中に作り足す下限")
            $0.options = Self.keepGeneratingChoices.map { Self.keepGeneratingText(minutes: $0) }
            $0.value = Self.keepGeneratingText(minutes: VoicevoxCacheLead.keepGeneratingBelowMinutes)
            $0.cell.textLabel?.numberOfLines = 0
        }.cellUpdate({ (cell, _) in
            cell.accessibilityHint = NSLocalizedString(
                "VoicevoxSettings_KeepGeneratingRowHint",
                comment: "先に作ってある音声の残りがこの時間より短くなったら、読み上げながら続きを作ります。")
        }).onChange({ row in
            guard let value = row.value,
                  let minutes = Self.keepGeneratingChoices.first(where: {
                      Self.keepGeneratingText(minutes: $0) == value
                  }) else { return }
            VoicevoxCacheLead.keepGeneratingBelowMinutes = minutes
        })

        // 一時分は「勝手にストレージを使っている」物なので、
        // 使っている量と、放っておいても消える事をここに出しておく。
        form +++ Section(header: NSLocalizedString("VoicevoxSettings_TemporarySectionTitle", comment: "読み上げ中に作った音声"),
                         footer: NSLocalizedString("VoicevoxSettings_TemporarySectionFooter",
                                                   comment: "読み上げ中に足りなくなって作った音声は一時的に保存され、聴き終わった所から順に消えます。別の小説を読み始めると、前の小説の分は消えます。"))
        <<< LabelRow("VoicevoxTemporaryRow") {
            $0.title = NSLocalizedString("VoicevoxSettings_TemporaryRowTitle", comment: "一時的に保存されている音声")
            $0.cell.textLabel?.numberOfLines = 0
        }

        form +++ Section(NSLocalizedString("VoicevoxSettings_AdvancedSectionTitle", comment: "通常は変更する必要のないもの"))
        <<< PickerInputRow<String>() {
            $0.title = NSLocalizedString("VoicevoxSettings_KeepBehindRowTitle", comment: "聴いた所を残しておく時間")
            $0.options = Self.keepBehindChoices.map { Self.keepBehindText(minutes: $0) }
            $0.value = Self.keepBehindText(minutes: VoicevoxTemporaryAudio.keepBehindMinutes)
            $0.cell.textLabel?.numberOfLines = 0
        }.cellUpdate({ (cell, _) in
            cell.accessibilityHint = NSLocalizedString(
                "VoicevoxSettings_KeepBehindRowHint",
                comment: "少し戻って聴き直す時に作り直さずに済む長さです。長くすると、その分だけ一時的に使う容量が増えます。")
        }).onChange({ row in
            guard let value = row.value,
                  let minutes = Self.keepBehindChoices.first(where: {
                      Self.keepBehindText(minutes: $0) == value
                  }) else { return }
            VoicevoxTemporaryAudio.keepBehindMinutes = minutes
        })

        form +++ Section(footer: NSLocalizedString("VoicevoxSettings_CreditSectionFooter", comment: "作った音声を公開する場合はクレジット表記が必要です。"))
        <<< ButtonRow() {
            $0.title = NSLocalizedString("VoicevoxSettings_CreditRowTitle", comment: "クレジット表記")
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
        updateTemporarySummary()
    }

    /// 一時分の容量。断りなく使っている物なので、量が見えている事が大事。
    private func updateTemporarySummary() {
        guard let row = form.rowBy(tag: "VoicevoxTemporaryRow") as? LabelRow else { return }
        let summary = VoicevoxDiskCacheStore.shared.temporaryTotalSummary()
        row.value = VoicevoxVoiceModelManageListBuilder.megabytesText(Int64(summary.byteCount))
        row.updateCell()
    }

    /// 音声モデルの行に「何件・何MB」を出す。
    private func updateVoiceModelSummary() {
        guard let row = form.rowBy(tag: "VoicevoxVoiceModelRow") as? LabelRow else { return }
        let formats = VoicevoxVoiceModelCatalogLoader.readableVvmFormatVersions
        let store = VoicevoxVoiceModelStore.shared
        let count = store.storedModelIDs(readableFormats: formats).count
        let bytes = store.totalBytes(readableFormats: formats)
        row.value = count == 0
            ? NSLocalizedString("VoicevoxSettings_NoVoiceModelValue", comment: "0件")
            : String(format: NSLocalizedString("VoicevoxSettings_VoiceModelCountFormat", comment: "%1$d件 %2$@"), count, VoicevoxVoiceModelManageListBuilder.megabytesText(bytes))
        row.updateCell()
    }
}
#endif
