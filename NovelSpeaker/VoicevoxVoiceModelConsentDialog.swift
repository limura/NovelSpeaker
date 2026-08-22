//
//  VoicevoxVoiceModelConsentDialog.swift
//  NovelSpeaker
//
//  音声モデルを取得する前に、規約を提示して同意を取るダイアログ。
//
//  **同意済みでも毎回出す。**「提示」が義務なのであって、
//  一度同意したから省いてよいという話ではない。
//  ただ、既に同意した事のある規約は、その旨をボタンに出して分かるようにする。
//
//  規約は外部のページにあるので、読むには外に出る事になる。
//  そのため「規約を読む」ではダイアログを閉じない。
//  戻ってきた時にそのまま同意できる。
//

import UIKit

#if !os(watchOS)
enum VoicevoxVoiceModelConsentDialog {

    /// - Parameters:
    ///   - requestedStyleDisplayName: 「ずんだもん - ささやき」のような、取得のきっかけになったスタイル。
    ///   - onStarted: 取得を積んだ後に呼ばれる。画面の更新用。
    static func present(on viewController: UIViewController,
                        model: VoicevoxVoiceModelCatalog.VoiceModel,
                        catalog: VoicevoxVoiceModelCatalog,
                        requestedStyleDisplayName: String?,
                        requestedStyleId: UInt32? = nil,
                        onStarted: (() -> Void)? = nil) {
        let consentStore = VoicevoxVoiceModelConsentStore.shared
        let message = VoicevoxVoiceModelConsentText.message(
            model: model,
            requestedStyleDisplayName: requestedStyleDisplayName,
            termsPageURL: catalog.termsPageURL)

        var builder = NiftyUtility.EasyDialogBuilder(viewController)
            .title(title: NSLocalizedString("VoicevoxConsent_DialogTitle", comment: "音声モデルの利用規約"))
            .textView(content: message, heightMultiplier: 0.5)

        // ★取得前に声を確かめられるようにする。ただしサンプル音声そのものは
        // アプリに持ってこられない(公式のサンプルは「VOICEVOX の開発のための利用のみ許可」)
        // ので、公式サイトのそのキャラクターのページへ送る。
        if let styleId = requestedStyleId,
           let speaker = model.speakers.first(where: { $0.styles.contains { $0.styleId == styleId } }),
           let pageURLString = speaker.officialPageURL, let pageURL = URL(string: pageURLString) {
            builder = builder.addButton(title: String(format: NSLocalizedString(
                "VoicevoxConsent_ListenOnSiteFormat", comment: "公式サイトで声を聞く(%@)"), speaker.name), callback: { _ in
                // 読む・聞くではダイアログを閉じない。戻ってきたらそのまま同意できる。
                UIApplication.shared.open(pageURL, options: [:], completionHandler: nil)
            })
        }

        for group in VoicevoxVoiceModelConsentText.groups(of: model) {
            guard let termsURL = group.termsURL, let url = URL(string: termsURL) else { continue }
            let agreedBefore = consentStore.hasConsented(termsURL: termsURL)
            let title = String(format: NSLocalizedString(
                "VoicevoxConsent_ReadTermsFormat", comment: "規約を読む(%@)"), group.hostName)
                + (agreedBefore ? NSLocalizedString("VoicevoxConsent_AlreadyAgreedSuffix", comment: " ・同意済み") : "")
            builder = builder.addButton(title: title, callback: { _ in
                // ここでは閉じない。読んで戻ってきたらそのまま同意できるようにする。
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            })
        }

        builder = builder.addButton(title: NSLocalizedString(
            "VoicevoxConsent_AgreeAndDownload", comment: "規約に同意して取得"), callback: { dialog in
            DispatchQueue.main.async {
                dialog.dismiss(animated: false) {
                    consentStore.recordConsent(model: model, vvmTag: catalog.vvmTag)
                    let blocker = VoicevoxVoiceModelDownloader.shared.enqueue(model: model)
                    if let blocker = blocker {
                        presentBlocker(on: viewController, model: model, blocker: blocker)
                        return
                    }
                    onStarted?()
                }
            }
        })
        builder = builder.addButton(title: NSLocalizedString("Cancel_button", comment: "キャンセル"), callback: { dialog in
            DispatchQueue.main.async { dialog.dismiss(animated: true) }
        })
        builder.build().show()
    }

    /// 未取得のスタイルで喋らせようとした時に、取得へ繋ぐ。
    ///
    /// 何も出さずに黙って失敗すると「押しても無反応」にしか見えない。
    /// - Returns: 未取得で、案内を出した場合は true。
    @discardableResult
    static func presentIfNotDownloaded(on viewController: UIViewController,
                                       styleId: UInt32,
                                       onStarted: (() -> Void)? = nil) -> Bool {
        guard VoicevoxCore.cachedStyles.contains(where: { $0.styleId == styleId }) == false else {
            return false
        }
        guard let catalog = VoicevoxVoiceModelCatalogLoader.preferredCatalog(),
              let entry = catalog.entry(forStyleId: styleId) else {
            NiftyUtility.EasyDialogBuilder(viewController)
                .title(title: NSLocalizedString("VoicevoxConsent_UnknownStyleTitle", comment: "この話者は使えません"))
                .label(text: String(format: NSLocalizedString(
                    "VoicevoxConsent_UnknownStyleMessageFormat",
                    comment: "選ばれているVOICEVOXの話者(スタイル番号 %u)が、この端末にも一覧にも見当たりません。"), styleId),
                       textAlignment: .left)
                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                    DispatchQueue.main.async { dialog.dismiss(animated: true) }
                })
                .build().show()
            return true
        }

        NiftyUtility.EasyDialogBuilder(viewController)
            .title(title: NSLocalizedString("VoicevoxConsent_NeedsModelTitle", comment: "音声モデルが必要です"))
            .label(text: String(format: NSLocalizedString(
                "VoicevoxConsent_NeedsModelMessageFormat",
                comment: "「%1$@」で読み上げるには、音声モデル %2$@.vvm (%3$@) の取得が必要です。"),
                entry.displayName, entry.model.id,
                VoicevoxVoiceModelConsentText.megabytesText(entry.model.byteSize)),
                   textAlignment: .left)
            .addButton(title: NSLocalizedString("VoicevoxConsent_DownloadButton", comment: "取得する"), callback: { dialog in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false) {
                        present(on: viewController, model: entry.model, catalog: catalog,
                                requestedStyleDisplayName: entry.displayName,
                                requestedStyleId: styleId,
                                onStarted: onStarted)
                    }
                }
            })
            .addButton(title: NSLocalizedString("Cancel_button", comment: "キャンセル"), callback: { dialog in
                DispatchQueue.main.async { dialog.dismiss(animated: true) }
            })
            .build().show()
        return true
    }

    /// 取得を始められなかった時の説明。
    static func presentBlocker(on viewController: UIViewController,
                               model: VoicevoxVoiceModelCatalog.VoiceModel,
                               blocker: VoicevoxVoiceModelDownloadBlocker) {
        let message: String
        switch blocker {
        case .alreadyStored:
            message = String(format: NSLocalizedString(
                "VoicevoxConsent_AlreadyStoredFormat", comment: "音声モデル %@.vvm は既に取得済みです。"), model.id)
        case .needsWiFi:
            // OS 側で待たせているので普段は出ないが、念のため。
            message = NSLocalizedString("VoicevoxConsent_NeedsWiFi", comment: "Wi-Fi に繋がるまで待ってから取得します。")
        case .notEnoughSpace(let requiredBytes, let freeBytes):
            message = String(format: NSLocalizedString(
                "VoicevoxConsent_NotEnoughSpaceFormat",
                comment: "端末の空き容量が足りません。\n必要: %1$@ / 空き: %2$@\n事前生成音声や、使っていない音声モデルを消すと空けられます。"),
                VoicevoxVoiceModelConsentText.megabytesText(requiredBytes),
                VoicevoxVoiceModelConsentText.megabytesText(freeBytes))
        }
        NiftyUtility.EasyDialogBuilder(viewController)
            .title(title: NSLocalizedString("VoicevoxConsent_CannotDownloadTitle", comment: "取得できません"))
            .label(text: message, textAlignment: .left)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                DispatchQueue.main.async { dialog.dismiss(animated: true) }
            })
            .build().show()
    }
}
#endif
