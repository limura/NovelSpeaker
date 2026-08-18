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
//  **カタログはVVMの形式ごとに一式を持つ。**
//
//  VVM には形式(vvm_format_version)があり、新しいコアは古い形式も読めるが、
//  古いコアは新しい形式を読めない(0.17.0 で 1→2 に変わった)。
//  つまり互換性を決めているのは形式であって、コアのバージョンではない
//  (0.17.0 のソースに「互換性維持のために残している旧式(vvm_format_version=1)」とある)。
//
//  1つのカタログに形式ごとの一式を並べておけば、**1つの配布ファイルで
//  過去に出した全てのアプリを賄える**。iOSのバージョンが上がって更新できなくなった
//  端末でも、自分が読める形式の一式を使い続けられる。
//  タグは凍結されるので古いアプリに新キャラは来ないが、
//  **配布URLが変わった時に直せる**のが効く(凍結カタログしか持たないと、そこで詰む)。
//
//  中身は scripts/update_voicevox_catalog.py が公式リポジトリから作る。
//  アプリに同梱しつつ、RemoteConfig 経由で新しい物に差し替えられるようにしてある。
//
//  詳細は DESIGN_VOICEVOXの音声モデル取得.md を参照。
//

import Foundation

/// 配布・同梱されるカタログファイル全体。形式ごとの一式(`variants`)を持つ。
struct VoicevoxVoiceModelCatalogFile: Codable, Equatable {
    /// このカタログファイル自体の形式。アプリが解釈できる上限は `supportedFormatVersion`。
    let formatVersion: Int
    let generatedAt: String?
    let variants: [VoicevoxVoiceModelCatalog]

    /// アプリが解釈できるカタログ形式の上限。
    static let supportedFormatVersion = 2

    /// このアプリのコアが読める形式のうち、**一番新しい物**の一式を選ぶ。
    ///
    /// 新しいコアは古い形式も読めるので、読める中で新しい方を選んでおけば
    /// 将来キャラが増えた時にも自然に追随できる。
    func catalog(readableVvmFormatVersions: Set<Int>) -> VoicevoxVoiceModelCatalog? {
        guard formatVersion <= Self.supportedFormatVersion else { return nil }
        return variants
            .filter { readableVvmFormatVersions.contains($0.vvmFormatVersion) }
            .filter { $0.voiceModels.isEmpty == false }
            .max { $0.vvmFormatVersion < $1.vvmFormatVersion }
    }
}

/// ある1つのVVM形式に対する一式。
struct VoicevoxVoiceModelCatalog: Codable, Equatable {
    /// ここに並んでいるVVMの形式。**アプリに入っているコアが読める物でなければならない。**
    let vvmFormatVersion: Int
    /// 実体を取ってくる voicevox_vvm のタグ。main を指してはいけない。
    let vvmTag: String
    /// この形式を読める最小のコアのバージョン(表示・診断用)。
    let minimumCoreVersion: String
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

    /// **アプリに同梱しているコアが読めるVVMの形式。**
    ///
    /// コアを上げたらここも足すこと(0.17.0 に上げるなら [1, 2])。
    /// 新しいコアは古い形式も読めるので、足すだけでよく、消してはいけない。
    /// 消すと、その形式で既に取得済みのファイルが使えない扱いになる。
    static let readableVvmFormatVersions: Set<Int> = [1]

    /// アプリに同梱しているカタログ。**これが最後の拠り所**なので、
    /// 取得元が落ちていてもVOICEVOXが全く使えなくなる事は無い。
    static func loadEmbeddedFile(bundle: Bundle = Bundle.main) -> VoicevoxVoiceModelCatalogFile? {
        guard let url = bundle.url(forResource: embeddedResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> VoicevoxVoiceModelCatalogFile? {
        return try? JSONDecoder().decode(VoicevoxVoiceModelCatalogFile.self, from: data)
    }

    /// 取ってきたカタログを、同梱のものの代わりに使ってよいか。
    ///
    /// **これが無いと致命的な事が起きる。**
    /// 公式が 0.17.0 に進んで配布カタログを更新した時、形式1の一式が
    /// 落ちていたり、このアプリのコアが読めない形式しか無かったりすると、
    /// 利用者は**開けないVVMを1.4GB取得する**事になる
    /// (コアは VOICEVOX_RESULT_INVALID_MODEL_HEADER_ERROR で弾く)。
    /// 「このアプリが読める形式の一式が、中身入りで存在する事」を条件にして防ぐ。
    static func isUsable(_ candidate: VoicevoxVoiceModelCatalogFile,
                         readableVvmFormatVersions: Set<Int> = readableVvmFormatVersions) -> Bool {
        return candidate.catalog(readableVvmFormatVersions: readableVvmFormatVersions) != nil
    }

    /// 同梱と取得済みのうち、実際に使うべき一式を返す。
    static func preferred(embedded: VoicevoxVoiceModelCatalogFile?,
                          remote: VoicevoxVoiceModelCatalogFile?,
                          readableVvmFormatVersions: Set<Int> = readableVvmFormatVersions)
        -> VoicevoxVoiceModelCatalog? {
        if let remote = remote,
           let fromRemote = remote.catalog(readableVvmFormatVersions: readableVvmFormatVersions) {
            return fromRemote
        }
        return embedded?.catalog(readableVvmFormatVersions: readableVvmFormatVersions)
    }
}
