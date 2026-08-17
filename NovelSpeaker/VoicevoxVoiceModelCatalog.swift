//
//  VoicevoxVoiceModelCatalog.swift
//  NovelSpeaker
//
//  「この styleId を使うには、どのファイルを取ってくればよいか」の対応表。
//
//  1つのキャラクターのスタイルが複数のVVMに分かれて入っている(ずんだもんは
//  0/5/15.vvm の3つ)一方で、1つのVVMには複数のキャラクターが同居している。
//  そのため「選ぶのはスタイル、取ってくるのはVVM」という分離が要り、
//  その橋渡しをするのがこのカタログ。
//
//  中身は scripts/update_voicevox_catalog.py が公式リポジトリから作る。
//  アプリに同梱しつつ、RemoteConfig 経由で新しい物に差し替えられるようにしてある
//  (VVMが増えた時にアプリ更新を待たせないため)。
//
//  詳細は DESIGN_VOICEVOXの音声モデル取得.md を参照。
//

import Foundation

struct VoicevoxVoiceModelCatalog: Codable, Equatable {
    /// このカタログ自体の形式。アプリが解釈できる上限は `supportedFormatVersion`。
    let formatVersion: Int
    let generatedAt: String?
    /// このカタログが対象としている voicevox_core のバージョン。
    let coreVersion: String
    /// 実体を取ってくる voicevox_vvm のタグ。
    let vvmTag: String
    /// ここに並んでいるVVMの形式。**アプリに入っているコアが読める物でなければならない。**
    let vvmFormatVersion: Int
    /// VOICEVOX 音声モデル全体の利用規約(キャラ個別の規約とは別に、常に提示する)。
    let termsPageURL: String?
    let voiceModels: [VoiceModel]

    struct VoiceModel: Codable, Equatable {
        /// "0" や "12" といったファイル名の番号部分。
        let id: String
        let url: String
        let byteSize: Int64
        let vvmFormatVersion: Int
        let speakers: [Speaker]

        var megabytes: Double { return Double(byteSize) / 1024.0 / 1024.0 }
        var allStyleIds: [UInt32] { return speakers.flatMap { $0.styles.map { $0.styleId } } }
    }

    struct Speaker: Codable, Equatable {
        let name: String
        let uuid: String
        let version: String?
        /// キャラクター個別の利用規約。取得前に必ず提示する。
        let termsURL: String?
        /// クレジット表記。**話者名から組み立ててはいけない。**
        /// 例: もち子さん の表記は "VOICEVOX:もち子(cv 明日葉よもぎ)" で、話者名と違う。
        let credit: String?
        /// 規約の要約文(「企業が携わる場合は事前確認が必要」等の条件が書かれている事がある)。
        let policyText: String?
        let styles: [Style]
    }

    struct Style: Codable, Equatable {
        let name: String
        let styleId: UInt32
    }

    /// アプリが解釈できるカタログ形式の上限。
    static let supportedFormatVersion = 1
}

extension VoicevoxVoiceModelCatalog {
    struct Entry: Equatable {
        let model: VoiceModel
        let speaker: Speaker
        let style: Style

        /// 話者設定の選択行に出す表記。SpeakerSettingsViewController の表記と揃えてある。
        var displayName: String { return "\(speaker.name) - \(style.name)" }
    }

    func entry(forStyleId styleId: UInt32) -> Entry? {
        for model in voiceModels {
            for speaker in model.speakers {
                for style in speaker.styles where style.styleId == styleId {
                    return Entry(model: model, speaker: speaker, style: style)
                }
            }
        }
        return nil
    }

    func model(withID id: String) -> VoiceModel? {
        return voiceModels.first { $0.id == id }
    }

    /// styleId から、その音声モデルを含むVVMを引く。
    func model(forStyleId styleId: UInt32) -> VoiceModel? {
        return entry(forStyleId: styleId)?.model
    }

    var allStyleIds: Set<UInt32> {
        return Set(voiceModels.flatMap { $0.allStyleIds })
    }

    /// 同じ規約URLのキャラクターは束ねて数える。
    /// 同意画面に42行並べても読まれないため(zunko.jp 系だけで何人もいる)。
    func speakersGroupedByTermsURL(of model: VoiceModel) -> [(termsURL: String?, speakers: [Speaker])] {
        var order: [String] = []
        var grouped: [String: [Speaker]] = [:]
        for speaker in model.speakers {
            let key = speaker.termsURL ?? ""
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(speaker)
        }
        return order.map { key in (termsURL: key.isEmpty ? nil : key, speakers: grouped[key] ?? []) }
    }
}

enum VoicevoxVoiceModelCatalogLoader {
    static let embeddedResourceName = "VoicevoxVoiceModelCatalog"

    /// アプリに同梱しているカタログ。**これが最後の拠り所**なので、
    /// 取得元が落ちていてもVOICEVOXが全く使えなくなる事は無い。
    static func loadEmbedded(bundle: Bundle = Bundle.main) -> VoicevoxVoiceModelCatalog? {
        guard let url = bundle.url(forResource: embeddedResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> VoicevoxVoiceModelCatalog? {
        return try? JSONDecoder().decode(VoicevoxVoiceModelCatalog.self, from: data)
    }

    /// 取ってきたカタログを、同梱のものの代わりに使ってよいか。
    ///
    /// **これが無いと致命的な事が起きる。**
    /// 例えば公式が 0.17.0 に進んだ時、配布カタログを 0.17.0 向けに更新すると、
    /// 古いアプリ(コア 0.16.4)がそれを読んで**開けない形式のVVMを1.4GB取得してしまう**
    /// (コアは VOICEVOX_RESULT_INVALID_MODEL_HEADER_ERROR で弾く)。
    /// 「同梱カタログと同じVVM形式である事」を条件にして、それを防ぐ。
    static func isUsable(_ candidate: VoicevoxVoiceModelCatalog,
                         insteadOf embedded: VoicevoxVoiceModelCatalog) -> Bool {
        // 知らない形式のカタログは解釈できない。
        guard candidate.formatVersion <= VoicevoxVoiceModelCatalog.supportedFormatVersion else { return false }
        // このアプリに入っているコアが読めるVVMでなければ意味が無い。
        guard candidate.vvmFormatVersion == embedded.vvmFormatVersion else { return false }
        // 一覧が空の物で上書きすると、何も取得できなくなるだけ。
        guard candidate.voiceModels.isEmpty == false else { return false }
        return true
    }

    /// 同梱と取得済みのうち、実際に使うべき方を返す。
    static func preferred(embedded: VoicevoxVoiceModelCatalog?,
                          remote: VoicevoxVoiceModelCatalog?) -> VoicevoxVoiceModelCatalog? {
        guard let embedded = embedded else {
            // 同梱が読めないのは異常事態。取得できた物があるなら、それでも無いよりはよい。
            return remote
        }
        guard let remote = remote, isUsable(remote, insteadOf: embedded) else { return embedded }
        return remote
    }
}
