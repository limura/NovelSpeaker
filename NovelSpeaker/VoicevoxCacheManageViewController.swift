//
//  VoicevoxCacheManageViewController.swift
//  NovelSpeaker
//
//  事前に作った VOICEVOX 音声(ディスクキャッシュ)の容量確認と削除。
//
//  1作品を丸ごと作ると数百MB〜数GBになるので、どれだけ使っているかを見られて、
//  要らなくなった物を消せる場所が必要になる。本棚には出さない(既にごちゃごちゃしているため)。
//

import UIKit
import Eureka
import RealmSwift

class VoicevoxCacheManageViewController: FormViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "作成済みのVOICEVOX音声"
        createCells()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        form.removeAll()
        createCells()
        tableView.reloadData()
    }

    private static func novelTitle(novelID: String) -> String {
        return RealmUtil.RealmBlock { (realm) -> String? in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.title
        } ?? "(本棚に無い小説)"
    }

    private static func sizeText(_ summary: VoicevoxDiskCacheSummary) -> String {
        let megabytes = Double(summary.byteCount) / 1024 / 1024
        return "\(VoicevoxCacheGenerationProgress.durationText(seconds: summary.audioSeconds))ぶん / \(String(format: "%.1f", megabytes))MB"
    }

    private func createCells() {
        let total = VoicevoxDiskCacheStore.shared.totalSummary()
        let summarySection = Section("合計")
        summarySection <<< LabelRow() {
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

        let novelIDs = VoicevoxDiskCacheStore.shared.cachedNovelIDs()
        if novelIDs.isEmpty {
            let emptySection = Section()
            emptySection <<< LabelRow() {
                $0.title = "作成済みの音声はありません。\n小説の詳細画面の「VOICEVOX音声を今の位置から生成する」から作れます。"
                $0.cell.textLabel?.numberOfLines = 0
            }
            form +++ emptySection
            return
        }

        let novelSection = Section("小説ごと(タップで削除)")
        // 大きい物から並べる。消したくなるのは大抵いちばん場所を取っている物なので。
        let entries = novelIDs.map { (novelID: $0, summary: VoicevoxDiskCacheStore.shared.summary(novelID: $0)) }
            .sorted(by: { $0.summary.byteCount > $1.summary.byteCount })
        for entry in entries {
            let title = Self.novelTitle(novelID: entry.novelID)
            novelSection <<< ButtonRow() {
                $0.title = "\(title)\n\(Self.sizeText(entry.summary))"
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.textAlignment = .left
            }.onCellSelection({ [weak self] _, _ in
                guard let self = self else { return }
                _ = NiftyUtility.EasyDialogTwoButton(
                    viewController: self,
                    title: "作成済みの音声を削除",
                    message: "「\(title)」の音声(\(Self.sizeText(entry.summary)))を削除します。\n\n削除しても本文は消えません。もう一度作り直す事もできます。",
                    button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
                    button1Action: nil,
                    button2Title: NSLocalizedString("OK_button", comment: "OK"),
                    button2Action: {
                        if VoicevoxCacheGenerator.shared.runningNovelID == entry.novelID {
                            VoicevoxCacheGenerator.shared.stop()
                        }
                        VoicevoxDiskCacheStore.shared.remove(novelID: entry.novelID)
                        VoicevoxCacheGenerationState.shared.setEnabled(false, novelID: entry.novelID)
                        DispatchQueue.main.async { self.reload() }
                    })
            })
        }
        form +++ novelSection

        let allSection = Section()
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
}
