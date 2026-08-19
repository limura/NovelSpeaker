//
//  VoicevoxStyleList.swift
//  NovelSpeaker
//
//  スタイル選択画面に並べる物を組み立てる所。
//
//  スタイルは127個ある。従来の AlertRow の平坦な一覧は10個なら成立するが、
//  127個は探せない。そこで**絞り込みができる専用の画面**にする。
//
//  並べ方は「取得済みが上・未取得が下」。
//  未取得の物を混ぜて並べると、選んだ瞬間に取得が始まる行と
//  すぐ使える行が見分けられなくなる。
//
//  画面から切り離してあるのは、
//  「取得済みなのに未取得側にも出る」「絞り込むと消える」といった
//  数の合わない壊れ方を試験で捕まえるため。
//

import Foundation

struct VoicevoxStyleListItem: Equatable {
    let styleId: UInt32
    let speakerName: String
    let styleName: String
    /// 未取得の時に取ってくる音声モデル。取得済みの行では nil でもよい。
    let modelID: String?
    let byteSize: Int64?
    /// 公式サイトのキャラクター紹介ページ。取得前に声を確かめたい人の出口。
    let officialPageURL: String?

    var displayName: String { return "\(speakerName) - \(styleName)" }

    var megabytesText: String? {
        guard let byteSize = byteSize else { return nil }
        return String(format: "%.0fMB", Double(byteSize) / 1024.0 / 1024.0)
    }
}

struct VoicevoxStyleListSection: Equatable {
    enum Kind: Equatable {
        case available
        case downloadable

        var title: String {
            switch self {
            case .available: return NSLocalizedString("VoicevoxStyleList_Available", comment: "取得済み")
            case .downloadable: return NSLocalizedString("VoicevoxStyleList_Downloadable", comment: "取得するとつかえる")
            }
        }
    }

    let kind: Kind
    let items: [VoicevoxStyleListItem]
}

enum VoicevoxStyleListBuilder {

    /// - Parameters:
    ///   - availableStyles: いま実際に喋れるスタイル(コアが読み込めている物)。
    ///   - catalog: 取得できる物の一覧。無い場合(カタログが壊れている等)は取得済みだけを並べる。
    ///   - searchText: 絞り込み文字列。空なら全部。
    static func build(availableStyles: [VoicevoxStyle],
                      catalog: VoicevoxVoiceModelCatalog?,
                      searchText: String) -> [VoicevoxStyleListSection] {
        let availableIds = Set(availableStyles.map { $0.styleId })

        // 取得済みの行にも公式サイトへの出口を付ける。
        // 手元で喋らせれば声は確かめられるが、そのキャラクターの事を知りたい時に
        // 「取得したら辿れなくなる」のは不便なので、カタログから引いておく。
        var officialPageByStyleId: [UInt32: String] = [:]
        if let catalog = catalog {
            for model in catalog.voiceModels {
                for speaker in model.speakers {
                    guard let page = speaker.officialPageURL else { continue }
                    for style in speaker.styles { officialPageByStyleId[style.styleId] = page }
                }
            }
        }

        let availableItems = availableStyles.map { style in
            VoicevoxStyleListItem(styleId: style.styleId,
                                  speakerName: style.speakerName,
                                  styleName: style.name,
                                  modelID: nil,
                                  byteSize: nil,
                                  officialPageURL: officialPageByStyleId[style.styleId])
        }

        var downloadableItems: [VoicevoxStyleListItem] = []
        if let catalog = catalog {
            for model in catalog.voiceModels {
                for speaker in model.speakers {
                    for style in speaker.styles where availableIds.contains(style.styleId) == false {
                        downloadableItems.append(
                            VoicevoxStyleListItem(styleId: style.styleId,
                                                  speakerName: speaker.name,
                                                  styleName: style.name,
                                                  modelID: model.id,
                                                  byteSize: model.byteSize,
                                                  officialPageURL: speaker.officialPageURL))
                    }
                }
            }
        }

        let sections = [
            VoicevoxStyleListSection(kind: .available, items: filter(availableItems, searchText: searchText)),
            VoicevoxStyleListSection(kind: .downloadable, items: filter(downloadableItems, searchText: searchText)),
        ]
        // 空の見出しだけが残ると「絞り込んだら何も無い」のか
        // 「そもそもそちらは空」なのか分からなくなるので、空の節は落とす。
        return sections.filter { $0.items.isEmpty == false }
    }

    /// キャラクター名でもスタイル名でも引っかかるようにする。
    /// 「ずんだ」でも「ささやき」でも探せた方が早い。
    static func filter(_ items: [VoicevoxStyleListItem], searchText: String) -> [VoicevoxStyleListItem] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return items }
        return items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(needle)
        }
    }
}
