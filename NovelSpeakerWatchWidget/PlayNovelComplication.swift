//
//  PlayNovelComplication.swift
//  NovelSpeakerWatchWidget
//
//  設定可能コンプリケーション「この小説を再生」(第2弾)。
//  ユーザが「小説」と「アイコン・色」を選んで配置し、タップするとその小説を
//  現在の発話元(iPhone/Watch単体)で再生する(widgetURL でアプリを起動)。
//
//  - 小説の選択肢は App Group の要約ストア(WatchNovelSummaryStore)= Watch に転送済みの小説から。
//  - families: corner(選択アイコン+曲線ラベルの小説名) / rectangular(アイコン+小説名+読了ゲージ)。
//  - 設定 UI は WidgetConfigurationIntent(AppIntents)で出す。設定用 intent は「選択肢の供給」と
//    「設定の保持」に使うだけで、実行は widgetURL 経由なので調査スパイクの落とし穴には掛からない。
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 設定パラメータ(小説・アイコン・色)

/// 選べる小説(App Group の要約ストアから供給)
struct PlayNovelChoice: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "小説")
    static var defaultQuery = PlayNovelChoiceQuery()

    var id: String   // novelID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct PlayNovelChoiceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlayNovelChoice] {
        let all = WatchNovelSummaryStore.load()
        return identifiers.compactMap { id in
            all.first(where: { $0.novelID == id }).map { PlayNovelChoice(id: $0.novelID, title: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [PlayNovelChoice] {
        return WatchNovelSummaryStore.load().map { PlayNovelChoice(id: $0.novelID, title: $0.title) }
    }
}

/// 表示アイコン(複数配置時の区別用)
enum PlayNovelWidgetIcon: String, AppEnum {
    case play, book, bookmark, headphones, star, sparkles

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "アイコン")
    static var caseDisplayRepresentations: [PlayNovelWidgetIcon: DisplayRepresentation] = [
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

/// 表示色(fullColor 文字盤でのみ効く。単色文字盤ではシステムの色に従う)
enum PlayNovelWidgetColor: String, AppEnum {
    case orange, red, purple, blue, teal, green

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "色")
    static var caseDisplayRepresentations: [PlayNovelWidgetColor: DisplayRepresentation] = [
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

struct PlayNovelConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "この小説を再生"
    static var description = IntentDescription("指定した小説を、現在の発話元(iPhone/Watch単体)で再生します。")

    @Parameter(title: "小説")
    var novel: PlayNovelChoice?

    @Parameter(title: "アイコン", default: .play)
    var icon: PlayNovelWidgetIcon

    @Parameter(title: "色", default: .orange)
    var color: PlayNovelWidgetColor
}

// MARK: - タイムライン

struct PlayNovelEntry: TimelineEntry {
    let date: Date
    let novelID: String?
    let title: String?
    let progress: Double
    let iconSystemName: String
    let tint: Color
}

struct PlayNovelProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PlayNovelEntry {
        PlayNovelEntry(date: Date(), novelID: nil, title: nil, progress: 0,
                       iconSystemName: PlayNovelWidgetIcon.play.systemName, tint: .orange)
    }

    func snapshot(for configuration: PlayNovelConfigurationIntent, in context: Context) async -> PlayNovelEntry {
        return entry(for: configuration)
    }

    func timeline(for configuration: PlayNovelConfigurationIntent, in context: Context) async -> Timeline<PlayNovelEntry> {
        // 更新は Watch アプリの reloadAllTimelines で駆動するので固定1エントリ
        return Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    // watchOS では実装が必須(ギャラリーの推奨候補。小説はユーザが選ぶので候補は出さない)
    func recommendations() -> [AppIntentRecommendation<PlayNovelConfigurationIntent>] {
        return []
    }

    private func entry(for configuration: PlayNovelConfigurationIntent) -> PlayNovelEntry {
        let novelID = configuration.novel?.id
        // 選択済みの小説の最新情報(タイトル・読了進捗)は要約ストアから引き直す
        let summary = novelID.flatMap { WatchNovelSummaryStore.summary(novelID: $0) }
        return PlayNovelEntry(
            date: Date(),
            novelID: novelID,
            title: summary?.title ?? configuration.novel?.title,
            progress: summary?.overallProgress ?? 0,
            iconSystemName: configuration.icon.systemName,
            tint: configuration.color.color)
    }
}

// MARK: - 表示

struct PlayNovelComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PlayNovelEntry

    private var appName: String { NSLocalizedString("Watch_Widget_AppName", comment: "ことせかい") }
    private var displayTitle: String { entry.title ?? NSLocalizedString("Watch_Widget_PlayNovel_Unset", comment: "小説を選択") }

    // 単色系文字盤では色分けが効かないのでシステムに任せ、fullColor のみ選択色を適用する
    private var iconTint: Color? { renderingMode == .fullColor ? entry.tint : nil }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(entry.novelID.map { WatchWidgetAction.playNovel(novelID: $0).url })
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            ActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint)
        }
    }

    // 角: ことせかい+選択アイコンの合成を角に、小説名を縁の曲線ラベルに
    // (合成なので角では機能アイコンは小さめだが、circular と見た目を揃える)
    @ViewBuilder
    private var corner: some View {
        ActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint)
            .widgetLabel { Text(entry.title ?? appName) }
    }

    // 長方形: [ことせかい+選択アイコンの合成] 小説名 + 読了ゲージ(小説未選択なら促し文)
    @ViewBuilder
    private var rectangular: some View {
        HStack(spacing: 7) {
            ActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint)
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
                } else {
                    Text(NSLocalizedString("Watch_Widget_PlayNovel_TapToConfigure", comment: "長押しで小説を選択"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PlayNovelComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.playNovel",
                               intent: PlayNovelConfigurationIntent.self,
                               provider: PlayNovelProvider()) { entry in
            PlayNovelComplicationView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_PlayNovel_Name", comment: "この小説を再生"))
        .description(NSLocalizedString("Watch_Widget_PlayNovel_Desc", comment: "指定した小説を再生します。"))
        .supportedFamilies([.accessoryCorner, .accessoryRectangular])
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    PlayNovelComplication()
} timeline: {
    PlayNovelEntry(date: .now, novelID: "sample", title: "転生したらスライムだった件",
                   progress: 0.4, iconSystemName: "play.fill", tint: .orange)
    PlayNovelEntry(date: .now, novelID: nil, title: nil, progress: 0,
                   iconSystemName: "play.fill", tint: .orange)
}

#Preview("Corner", as: .accessoryCorner) {
    PlayNovelComplication()
} timeline: {
    PlayNovelEntry(date: .now, novelID: "sample", title: "転生したらスライムだった件",
                   progress: 0.4, iconSystemName: "book.fill", tint: .teal)
}
