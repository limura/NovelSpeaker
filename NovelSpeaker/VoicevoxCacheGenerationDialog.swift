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
        let progressText = VoicevoxCacheGenerator.shared.progress?.description
            ?? NSLocalizedString("VoicevoxCacheGenerationDialog_GeneratingFallback", comment: "生成中です")
        _ = NiftyUtility.EasyDialogTwoButton(
            viewController: viewController,
            title: NSLocalizedString("VoicevoxCacheGenerationDialog_StopTitle", comment: "事前生成音声を作成中"),
            message: String(format: NSLocalizedString(
                "VoicevoxCacheGenerationDialog_StopMessageFormat",
                comment: "%@\n\n止めても、作った分はそのまま残ります。次に始める時は続きから作ります。"), progressText),
            button1Title: NSLocalizedString("VoicevoxCacheGenerationDialog_ContinueButton", comment: "生成を続ける"),
            button1Action: nil,
            button2Title: NSLocalizedString("VoicevoxCacheGenerationDialog_StopButton", comment: "生成を止める"),
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
            message = String(format: NSLocalizedString(
                "VoicevoxCacheGenerationDialog_ResumeMessageFormat",
                comment: "前回の続きから音声を作ります。既に作ってある分(%@ぶん)は作り直しません。"),
                VoicevoxCacheGenerationProgress.durationText(seconds: summary.audioSeconds))
        } else {
            message = NSLocalizedString(
                "VoicevoxCacheGenerationDialog_StartMessage",
                comment: "今の読み上げ位置から先の音声を作って端末に貯めます。")
        }
        _ = NiftyUtility.EasyDialogTwoButton(
            viewController: viewController,
            title: NSLocalizedString("VoicevoxCacheGenerationDialog_StartTitle", comment: "事前生成音声を作る"),
            message: message,
            button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
            button1Action: nil,
            button2Title: hasExisting
                ? NSLocalizedString("VoicevoxCacheGenerationDialog_ResumeButton", comment: "続きから作る")
                : NSLocalizedString("VoicevoxCacheGenerationDialog_StartButton", comment: "生成を始める"),
            button2Action: {
                VoicevoxCacheGenerator.shared.start(novelID: novelID)
            })
    }
}
#endif
