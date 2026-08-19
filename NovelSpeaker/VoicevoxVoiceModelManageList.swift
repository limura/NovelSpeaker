//
//  VoicevoxVoiceModelManageList.swift
//  NovelSpeaker
//
//  設定 →「VOICEVOXの音声モデル」に並べる物と、クレジット表記の組み立て。
//
//  音声モデルは1つ60MB前後で、全部揃えると1.4GBになる。
//  作り置きした音声も別に数GB貯まるので、
//  **両方の容量を並べて見せないと**「何を消せば空くのか」が分からない。
//
//  消す時に効くのは「その音声モデルを使っている話者設定があるか」。
//  設計メモの当初案は「使用中の小説◯件」だったが、
//  小説と話者設定は「この小説だけ」「全ての小説」「会話文だけ」等の
//  条件付きで繋がっていて、数えても意味の薄い数になる。
//  **どの話者設定が使っているか**を名前で出す方が、消してよいか判断できる。
//
//  クレジット表記は取得済みのキャラクターだけを並べる。
//  消せばその行も消える。
//

import Foundation

struct VoicevoxVoiceModelManageItem: Equatable {
    let modelID: String
    let byteSize: Int64
    let speakerNames: [String]
    let isStored: Bool
    /// この音声モデルのスタイルを指している話者設定の名前。
    let usedBySettingNames: [String]

    var fileName: String { return "\(modelID).vvm" }
    var megabytesText: String { return String(format: "%.0fMB", Double(byteSize) / 1024.0 / 1024.0) }
    var speakerNamesText: String { return speakerNames.joined(separator: "・") }
}

struct VoicevoxVoiceModelManageSection: Equatable {
    enum Kind: Equatable {
        case stored
        case notStored

        var title: String {
            switch self {
            case .stored: return NSLocalizedString("VoicevoxStyleList_Available", comment: "取得済み")
            case .notStored: return NSLocalizedString("VoicevoxVoiceModelManage_NotStored", comment: "取得していない")
            }
        }
    }

    let kind: Kind
    let items: [VoicevoxVoiceModelManageItem]
}

enum VoicevoxVoiceModelManageListBuilder {

    /// - Parameters:
    ///   - storedModelIDs: 手元にある音声モデル。
    ///   - settingNamesByStyleId: styleId → その styleId を指している話者設定の名前。
    static func build(catalog: VoicevoxVoiceModelCatalog?,
                      storedModelIDs: Set<String>,
                      settingNamesByStyleId: [UInt32: [String]],
                      searchText: String) -> [VoicevoxVoiceModelManageSection] {
        guard let catalog = catalog else { return [] }
        var stored: [VoicevoxVoiceModelManageItem] = []
        var notStored: [VoicevoxVoiceModelManageItem] = []
        for model in catalog.voiceModels {
            var usedBy: [String] = []
            for styleId in model.allStyleIds {
                for name in settingNamesByStyleId[styleId] ?? [] where usedBy.contains(name) == false {
                    usedBy.append(name)
                }
            }
            let item = VoicevoxVoiceModelManageItem(
                modelID: model.id,
                byteSize: model.byteSize,
                speakerNames: model.speakers.map { $0.name },
                isStored: storedModelIDs.contains(model.id),
                usedBySettingNames: usedBy.sorted())
            if item.isStored { stored.append(item) } else { notStored.append(item) }
        }
        let sections = [
            VoicevoxVoiceModelManageSection(kind: .stored, items: filter(stored, searchText: searchText)),
            VoicevoxVoiceModelManageSection(kind: .notStored, items: filter(notStored, searchText: searchText)),
        ]
        return sections.filter { $0.items.isEmpty == false }
    }

    /// キャラクター名でもファイル名でも引けるようにする。
    static func filter(_ items: [VoicevoxVoiceModelManageItem],
                       searchText: String) -> [VoicevoxVoiceModelManageItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return items }
        return items.filter { item in
            item.speakerNamesText.localizedCaseInsensitiveContains(needle)
                || item.fileName.localizedCaseInsensitiveContains(needle)
        }
    }

    static func megabytesText(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.1fGB", Double(bytes) / 1024.0 / 1024.0 / 1024.0)
        }
        return String(format: "%.0fMB", Double(bytes) / 1024.0 / 1024.0)
    }

    /// 画面の一番上に出す要約。
    /// **音声モデルと作成済み音声を並べて出す。**片方だけ見せても、
    /// 「何を消せば空くのか」の判断ができないため。
    static func summaryText(storedCount: Int,
                            storedBytes: Int64,
                            generatedAudioBytes: Int64,
                            freeBytes: Int64) -> String {
        return String(format: NSLocalizedString(
            "VoicevoxVoiceModelManage_SummaryFormat",
            comment: "音声モデル %1$d件 %2$@ / 作成済み音声 %3$@ / 端末の空き %4$@"),
                      storedCount, megabytesText(storedBytes),
                      megabytesText(generatedAudioBytes), megabytesText(freeBytes))
    }

    /// 未取得の音声モデルを指している話者設定への注意書き。無ければ nil。
    ///
    /// これが出るのは「音声モデルを消したが、話者設定はそのまま」という状態。
    /// 設定は壊さずに残してあるので、取り直せば元に戻る事まで書く。
    static func missingModelWarning(settingNamesByStyleId: [UInt32: [String]],
                                    availableStyleIds: Set<UInt32>) -> String? {
        var names: [String] = []
        for (styleId, settingNames) in settingNamesByStyleId where availableStyleIds.contains(styleId) == false {
            for name in settingNames where names.contains(name) == false { names.append(name) }
        }
        guard names.isEmpty == false else { return nil }
        return String(format: NSLocalizedString(
            "VoicevoxVoiceModelManage_MissingWarningFormat",
            comment: "取得していない音声モデルを使う話者設定が %1$d件 あります(%2$@)。設定はそのままにしてあるので、取り直せば元の声に戻ります。"),
                      names.count, names.sorted().joined(separator: NSLocalizedString("Voicevox_NameSeparator", comment: "、")))
    }
}

/// クレジット表記。「このアプリについて」に常設する。
enum VoicevoxCreditList {
    struct Entry: Equatable {
        let credit: String
        let termsURL: String?
        let officialPageURL: String?
    }

    /// 取得済みの音声モデルに入っているキャラクターだけを並べる。
    /// 同じキャラクターが複数の音声モデルに入っている事があるので、重複は潰す。
    static func entries(catalog: VoicevoxVoiceModelCatalog?,
                        storedModelIDs: Set<String>) -> [Entry] {
        guard let catalog = catalog else { return [] }
        var seen = Set<String>()
        var entries: [Entry] = []
        for model in catalog.voiceModels where storedModelIDs.contains(model.id) {
            for speaker in model.speakers {
                let credit = speaker.credit ?? "VOICEVOX:\(speaker.name)"
                guard seen.contains(credit) == false else { continue }
                seen.insert(credit)
                entries.append(Entry(credit: credit,
                                     termsURL: speaker.termsURL,
                                     officialPageURL: speaker.officialPageURL))
            }
        }
        return entries.sorted { $0.credit < $1.credit }
    }
}
