//
//  VoicevoxCacheGenerationDialog.swift
//  NovelSpeaker
//
//  VOICEVOX音声の事前生成を始める/止めるためのダイアログ。
//  小説の詳細画面と、本文画面の右上ボタンの両方から同じ物を出す。
//

import UIKit

#if !os(watchOS)
enum VoicevoxCacheGenerationDialog {

    /// 生成中なら「進捗と停止」、そうでなければ「開始の確認」を出す。
    static func present(on viewController: UIViewController, novelID: String) {
        if VoicevoxCacheGenerator.shared.runningNovelID == novelID {
            presentStopConfirmation(on: viewController, novelID: novelID)
            return
        }
        presentStartConfirmation(on: viewController, novelID: novelID)
    }

    private static func presentStopConfirmation(on viewController: UIViewController, novelID: String) {
        let progressText = VoicevoxCacheGenerator.shared.progress?.description ?? "生成中です"
        _ = NiftyUtility.EasyDialogTwoButton(
            viewController: viewController,
            title: "VOICEVOX音声を生成中",
            message: "\(progressText)\n\n止めても、作った分はそのまま残ります。次に始める時は続きから作ります。",
            button1Title: "生成を続ける",
            button1Action: nil,
            button2Title: "生成を止める",
            button2Action: {
                VoicevoxCacheGenerator.shared.stop()
            })
    }

    private static func presentStartConfirmation(on viewController: UIViewController, novelID: String) {
        let summary = VoicevoxDiskCacheStore.shared.summary(novelID: novelID)
        let hasExisting = summary.entryCount > 0
        // 既に作ってある時に「今の読み上げ位置から作ります」とだけ書くと、
        // 作り済みの所をもう一度作り直すように読めてしまうので、書き分ける。
        let message: String
        if hasExisting {
            message = "前回の続きから音声を作ります。"
                + "既に作ってある分(\(VoicevoxCacheGenerationProgress.durationText(seconds: summary.audioSeconds))ぶん)は作り直しません。"
                + "\n\n作っている間は画面を消さずに置いておいてください(画面が消えると一時停止します)。"
                + "\n音声1時間ぶんで約15MBを使います。"
        } else {
            message = "今の読み上げ位置から先の音声を作って端末に貯めます。"
                + "\n\n作っている間は画面を消さずに置いておいてください(画面が消えると一時停止します)。"
                + "\n音声1時間ぶんで約15MBを使います。"
                + "\n\n作った音声はこの端末でだけ使えます。"
        }
        _ = NiftyUtility.EasyDialogTwoButton(
            viewController: viewController,
            title: "VOICEVOX音声の生成",
            message: message,
            button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
            button1Action: nil,
            button2Title: hasExisting ? "続きから作る" : "生成を始める",
            button2Action: {
                VoicevoxCacheGenerator.shared.start(novelID: novelID)
            })
    }
}
#endif
