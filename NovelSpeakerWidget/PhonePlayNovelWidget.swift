//
//  PhonePlayNovelWidget.swift
//  NovelSpeakerWidgetExtension
//
//  設定可能ウィジェット「指定小説の再生を開始」(iPhone版)。
//  ユーザが「小説」と「アイコン・色」を選んで配置し、タップするとその小説の読み上げを
//  アプリを開かずに開始する(Button(intent:) + AudioPlaybackIntent。
//  Watch 版と違い widgetURL でのアプリ起動は不要)。
//
//  - 小説の選択肢は App Group の共有ストア(PhoneWidgetDataStore)から
//    (アプリ本体が最近読んだ順の上位を書いている)。
//  - 設定 UI はウィジェットの長押し→編集(iOS では全 OS バージョンで出る。
//    watchOS のような recommendations の縛りは無い)。
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 設定パラメータ(小説・アイコン・色)

/// 選べる小説(App Group の共有ストアから供給)
struct PhonePlayNovelChoice: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "小説")
    static var defaultQuery = PhonePlayNovelChoiceQuery()

    var id: String   // novelID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct PhonePlayNovelChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PhonePlayNovelChoice] {
        let all = PhoneWidgetDataStore.loadSummaries()
        return identifiers.compactMap { id in
            all.first(where: { $0.novelID == id }).map { PhonePlayNovelChoice(id: $0.novelID, title: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [PhonePlayNovelChoice] {
        return PhoneWidgetDataStore.loadSummaries().map { PhonePlayNovelChoice(id: $0.novelID, title: $0.title) }
    }
}

/// 表示アイコン(複数配置時の区別用。Watch 版と同じ6種)
enum PhonePlayNovelWidgetIcon: String, AppEnum {
    case play, book, bookmark, headphones, star, sparkles

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "アイコン")
    static var caseDisplayRepresentations: [PhonePlayNovelWidgetIcon: DisplayRepresentation] = [
        .play:       DisplayRepresentation(title: "再生(▶)"),
        .book:       DisplayRepresentation(title: "本"),
        .bookmark:   DisplayRepresentation(title: "しおり"),
        .headphones: DisplayRepresentation(title: "ヘッドフォン"),
        .star:       DisplayRepresentation(title: "星"),
        .sparkles:   DisplayRepresentation(title: "きらめき"),
    ]

    var systemName: String {
        switch self {
        case .play:       return "play.fill"
        case .book:       return "book.fill"
        case .bookmark:   return "bookmark.fill"
        case .headphones: return "headphones"
        case .star:       return "star.fill"
        case .sparkles:   return "sparkles"
        }
    }
}

/// 表示色(フルカラー表示でのみ効く。ロック画面の単色系ではシステムの色に従う)
enum PhonePlayNovelWidgetColor: String, AppEnum {
    case orange, red, purple, blue, teal, green

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "色")
    static var caseDisplayRepresentations: [PhonePlayNovelWidgetColor: DisplayRepresentation] = [
        .orange: DisplayRepresentation(title: "オレンジ"),
        .red:    DisplayRepresentation(title: "赤"),
        .purple: DisplayRepresentation(title: "紫"),
        .blue:   DisplayRepresentation(title: "青"),
        .teal:   DisplayRepresentation(title: "ティール"),
        .green:  DisplayRepresentation(title: "緑"),
    ]

    var color: Color {
        switch self {
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .blue:   return .blue
        case .teal:   return .teal
        case .green:  return .green
        }
    }
}

struct PhonePlayNovelConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "指定小説の再生を開始"
    static var description = IntentDescription("指定した小説の読み上げを、ことせかい を開かずに開始します。")

    @Parameter(title: "小説")
    var novel: PhonePlayNovelChoice?

    @Parameter(title: "アイコン", default: .play)
    var icon: PhonePlayNovelWidgetIcon

    @Parameter(title: "色", default: .orange)
    var color: PhonePlayNovelWidgetColor
}

// MARK: - タイムライン

struct PhonePlayNovelEntry: TimelineEntry {
    let date: Date
    let novelID: String?
    let title: String?
    let progress: Double
    let iconSystemName: String
    let tint: Color
}

struct PhonePlayNovelProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhonePlayNovelEntry {
        PhonePlayNovelEntry(date: Date(), novelID: nil, title: nil, progress: 0,
                            iconSystemName: PhonePlayNovelWidgetIcon.play.systemName, tint: .orange)
    }

    func snapshot(for configuration: PhonePlayNovelConfigurationIntent, in context: Context) async -> PhonePlayNovelEntry {
        return entry(for: configuration)
    }

    func timeline(for configuration: PhonePlayNovelConfigurationIntent, in context: Context) async -> Timeline<PhonePlayNovelEntry> {
        // 更新はアプリ側の WidgetCenter.reloadAllTimelines で駆動するので固定1エントリ
        return Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: PhonePlayNovelConfigurationIntent) -> PhonePlayNovelEntry {
        let novelID = configuration.novel?.id
        // 選択済みの小説の最新情報(タイトル・読了進捗)は共有ストアから引き直す
        let summary = novelID.flatMap { PhoneWidgetDataStore.summary(novelID: $0) }
        return PhonePlayNovelEntry(
            date: Date(),
            novelID: novelID,
            title: summary?.title ?? configuration.novel?.title,
            progress: summary?.overallProgress ?? 0,
            iconSystemName: configuration.icon.systemName,
            tint: configuration.color.color)
    }
}

// MARK: - 表示

struct PhonePlayNovelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PhonePlayNovelEntry

    private var displayTitle: String { entry.title ?? NSLocalizedString("Phone_Widget_PlayNovel_Unset", comment: "小説を選択") }

    // 単色系(ロック画面)では色分けが効かないのでシステムに任せ、フルカラーのみ選択色を適用する
    private var iconTint: Color? { renderingMode == .fullColor ? entry.tint : nil }

    var body: some View {
        // 小説が選択済みならタップでその場再生(アプリは開かない)。
        // 未選択の間はボタンにせず、タップは普通のアプリ起動にしておく
        Group {
            if let novelID = entry.novelID {
                Button(intent: PhonePlayNovelIntent(novelID: novelID)) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            // ロック画面(円形): 合成アイコンだけ
            PhoneActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint)
                .padding(2)
        case .accessoryRectangular:
            // ロック画面(横長): [合成アイコン] 小説名 + 読了ゲージ
            HStack(spacing: 7) {
                PhoneActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if entry.novelID != nil {
                        Gauge(value: entry.progress) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(iconTint)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            // ホーム画面(systemSmall): 合成アイコン + 小説名 + 読了ゲージ
            VStack(spacing: 8) {
                PhoneActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint)
                    .frame(width: 56, height: 56)
                Text(displayTitle)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                if entry.novelID != nil {
                    Gauge(value: entry.progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(iconTint)
                }
            }
        }
    }
}

struct PhonePlayNovelWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.widget.playNovel",
                               intent: PhonePlayNovelConfigurationIntent.self,
                               provider: PhonePlayNovelProvider()) { entry in
            PhonePlayNovelWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Phone_Widget_PlayNovel_Name", comment: "指定小説の再生を開始"))
        .description(NSLocalizedString("Phone_Widget_PlayNovel_Desc", comment: "指定した小説の読み上げを、ことせかい を開かずに開始します。小説の候補は最近読んだ順に並びます。"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
