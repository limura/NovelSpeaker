//
//  VoicevoxCacheDeleteDialog.swift
//  NovelSpeaker
//
//  作成済みの VOICEVOX 音声を削除するためのダイアログ。
//  設定内の管理画面と、小説の詳細画面の両方から同じ物を出す。
//
//  「もう聴いた所は要らない」は普通に起きるが、それを説明するのが難しい。
//  利用者が普段見ているページ番号で言い切る事で分かるようにする:
//  「今読んでいる15ページ目より前」を消す、という言い方にする。
//

import UIKit
import RealmSwift

#if !os(watchOS)
enum VoicevoxCacheDeleteDialog {

    static func present(on viewController: UIViewController, novelID: String, onChanged: @escaping () -> Void) {
        let summary = VoicevoxDiskCacheStore.shared.summary(novelID: novelID)
        let chapterCount = VoicevoxDiskCacheStore.shared.chapterNumbers(novelID: novelID).count
        let title = RealmUtil.RealmBlock { (realm) -> String? in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.title
        } ?? "(本棚に無い小説)"
        let readingChapterNumber = RealmUtil.RealmBlock { (realm) -> Int? in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.readingChapterNumber
        }

        let megabytes = Double(summary.byteCount) / 1024 / 1024
        var builder = NiftyUtility.EasyDialogBuilder(viewController)
            .title(title: "作成済みの音声を削除")
            .label(text: "「\(title)」\n"
                   + VoicevoxCacheGenerationProgress.storedText(chapterCount: chapterCount, audioSeconds: summary.audioSeconds)
                   + "(\(String(format: "%.1f", megabytes))MB)",
                   textAlignment: .left)

        // 読み終わった所より前だけを消す(そこに実際に音声がある時だけ出す)。
        if let readingChapterNumber = readingChapterNumber {
            let listened = VoicevoxDiskCacheStore.shared.summary(novelID: novelID, beforeChapterNumber: readingChapterNumber)
            if listened.entryCount > 0 {
                let listenedMegabytes = Double(listened.byteCount) / 1024 / 1024
                builder = builder.addButton(
                    title: "読み終わった分だけ削除\n(\(readingChapterNumber)ページ目より前の \(VoicevoxCacheGenerationProgress.durationText(seconds: listened.audioSeconds))・\(String(format: "%.1f", listenedMegabytes))MB)",
                    callback: { dialog in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false) {
                                VoicevoxDiskCacheStore.shared.removeChapters(novelID: novelID, beforeChapterNumber: readingChapterNumber)
                                onChanged()
                            }
                        }
                    })
            }
        }

        builder = builder.addButton(title: "この小説の音声を全て削除", callback: { dialog in
            DispatchQueue.main.async {
                dialog.dismiss(animated: false) {
                    if VoicevoxCacheGenerator.shared.runningNovelID == novelID {
                        VoicevoxCacheGenerator.shared.stop()
                    }
                    VoicevoxDiskCacheStore.shared.remove(novelID: novelID)
                    VoicevoxCacheGenerationState.shared.setEnabled(false, novelID: novelID)
                    onChanged()
                }
            }
        })
        builder = builder.addButton(title: NSLocalizedString("Cancel_button", comment: "キャンセル"), callback: { dialog in
            DispatchQueue.main.async { dialog.dismiss(animated: true) }
        })
        builder.build().show()
    }
}
#endif
