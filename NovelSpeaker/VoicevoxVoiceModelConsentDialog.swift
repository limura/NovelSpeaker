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
                        onStarted: (() -> Void)? = nil) {
        let consentStore = VoicevoxVoiceModelConsentStore.shared
        let message = VoicevoxVoiceModelConsentText.message(
            model: model,
            requestedStyleDisplayName: requestedStyleDisplayName,
            termsPageURL: catalog.termsPageURL)

        var builder = NiftyUtility.EasyDialogBuilder(viewController)
            .title(title: "音声モデルの利用規約")
            .textView(content: message, heightMultiplier: 0.5)

        for group in VoicevoxVoiceModelConsentText.groups(of: model) {
            guard let termsURL = group.termsURL, let url = URL(string: termsURL) else { continue }
            let agreedBefore = consentStore.hasConsented(termsURL: termsURL)
            let title = "規約を読む(\(group.hostName))" + (agreedBefore ? " ・同意済み" : "")
            builder = builder.addButton(title: title, callback: { _ in
                // ここでは閉じない。読んで戻ってきたらそのまま同意できるようにする。
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            })
        }

        builder = builder.addButton(title: "規約に同意して取得", callback: { dialog in
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

    /// 取得を始められなかった時の説明。
    static func presentBlocker(on viewController: UIViewController,
                               model: VoicevoxVoiceModelCatalog.VoiceModel,
                               blocker: VoicevoxVoiceModelDownloadBlocker) {
        let message: String
        switch blocker {
        case .alreadyStored:
            message = "音声モデル \(model.id).vvm は既に取得済みです。"
        case .needsWiFi:
            // OS 側で待たせているので普段は出ないが、念のため。
            message = "Wi-Fi に繋がるまで待ってから取得します。"
        case .notEnoughSpace(let requiredBytes, let freeBytes):
            message = "端末の空き容量が足りません。\n"
                + "必要: \(VoicevoxVoiceModelConsentText.megabytesText(requiredBytes))"
                + " / 空き: \(VoicevoxVoiceModelConsentText.megabytesText(freeBytes))\n"
                + "作成済みのVOICEVOX音声や、使っていない音声モデルを消すと空けられます。"
        }
        NiftyUtility.EasyDialogBuilder(viewController)
            .title(title: "取得できません")
            .label(text: message, textAlignment: .left)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { dialog in
                DispatchQueue.main.async { dialog.dismiss(animated: true) }
            })
            .build().show()
    }
}
#endif
