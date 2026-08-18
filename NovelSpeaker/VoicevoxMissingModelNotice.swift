//
//  VoicevoxMissingModelNotice.swift
//  NovelSpeaker
//
//  「選ばれているVOICEVOXの話者の音声モデルが手元に無い」事を利用者に伝える所。
//
//  この状態は普通に起きる。
//   - 端末を買い替えた(設定は iCloud で来るが、音声モデルは来ない)
//   - 容量が足りなくなって音声モデルを消した
//  どちらの場合も**話者設定は壊さずに残してある**ので、取り直せば元の声に戻る。
//
//  黙って無音のまま次のブロックへ進むのが一番良くない。
//  そこで、その場は端末の音声で代わりに読み上げつつ、
//  「設定タブ」→「アプリ内エラーのお知らせ」に取得への入口を出す。
//  これは AVSpeechSynthesizer の話者が OS 更新で消えた時の作りに揃えてある。
//
//  同じ話者で何度も読み上げる度に通知が積まれても邪魔なので、
//  dedupeKey で styleId ごとに1件にまとめる。
//

import Foundation

enum VoicevoxMissingModelNotice {
    /// 「アプリ内エラーのお知らせ」のボタンから、音声モデルの取得へ飛ぶための識別子。
    static let actionType = "openVoicevoxVoiceModelDownload"
    static let category = "voicevoxVoiceModel"

    static func dedupeKey(styleId: UInt32) -> String {
        return "voicevoxVoiceModel.missing:\(styleId)"
    }

    /// カタログから引ける名前があればそれを使う。
    /// 「スタイル番号 22」とだけ出されても、誰の事なのか分からない。
    static func displayName(styleId: UInt32) -> String? {
        if let style = VoicevoxCore.cachedStyles.first(where: { $0.styleId == styleId }) {
            return "\(style.speakerName) - \(style.name)"
        }
        guard let catalog = VoicevoxVoiceModelCatalogLoader.preferred(
                embedded: VoicevoxVoiceModelCatalogLoader.loadEmbeddedFile(), remote: nil) else { return nil }
        return catalog.entry(forStyleId: styleId)?.displayName
    }

    static func message(styleId: UInt32, displayName: String?) -> String {
        let who = displayName ?? "スタイル番号 \(styleId)"
        return "VOICEVOXの話者「\(who)」の音声モデルがこの端末にありません。"
            + "その箇所は端末の音声で読み上げました。"
            + "話者設定はそのままにしてあるので、音声モデルを取得すれば元の声に戻ります。"
    }

    static func post(styleId: UInt32) {
        let name = displayName(styleId: styleId)
        let action = AppInformationLogAction(
            title: "音声モデルを取得する",
            actionType: actionType,
            payload: ["styleId": AnyCodable("\(styleId)")])
        AppInformationLogger.AddLogWithStruct(
            message: message(styleId: styleId, displayName: name),
            appendix: [:],
            isForDebug: false,
            category: category,
            dedupeKey: dedupeKey(styleId: styleId),
            actions: [action])
    }

    /// 「アプリ内エラーのお知らせ」のボタンが押された時に、対象の styleId を取り出す。
    static func styleId(from action: AppInformationLogAction) -> UInt32? {
        guard action.actionType == actionType else { return nil }
        guard let text = action.payload["styleId"]?.value as? String else { return nil }
        return UInt32(text)
    }
}
