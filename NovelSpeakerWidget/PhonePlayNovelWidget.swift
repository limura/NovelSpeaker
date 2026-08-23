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
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Phone_Widget_Config_Novel", table: "WidgetLocalizable"))
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

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Phone_Widget_Config_Icon", table: "WidgetLocalizable"))
    static var caseDisplayRepresentations: [PhonePlayNovelWidgetIcon: DisplayRepresentation] = [
        .play:       DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Icon_Play", table: "WidgetLocalizable")),
        .book:       DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Icon_Book", table: "WidgetLocalizable")),
        .bookmark:   DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Icon_Bookmark", table: "WidgetLocalizable")),
        .headphones: DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Icon_Headphones", table: "WidgetLocalizable")),
        .star:       DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Icon_Star", table: "WidgetLocalizable")),
        .sparkles:   DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Icon_Sparkles", table: "WidgetLocalizable")),
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

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Phone_Widget_Config_Color", table: "WidgetLocalizable"))
    static var caseDisplayRepresentations: [PhonePlayNovelWidgetColor: DisplayRepresentation] = [
        .orange: DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Color_Orange", table: "WidgetLocalizable")),
        .red:    DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Color_Red", table: "WidgetLocalizable")),
        .purple: DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Color_Purple", table: "WidgetLocalizable")),
        .blue:   DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Color_Blue", table: "WidgetLocalizable")),
        .teal:   DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Color_Teal", table: "WidgetLocalizable")),
        .green:  DisplayRepresentation(title: LocalizedStringResource("Phone_Widget_Config_Color_Green", table: "WidgetLocalizable")),
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
    static var title = LocalizedStringResource("Phone_Widget_PlayNovel_Name", table: "WidgetLocalizable")
    static var description = IntentDescription(LocalizedStringResource("Phone_Widget_PlayNovel_ControlDesc", table: "WidgetLocalizable"))

    @Parameter(title: LocalizedStringResource("Phone_Widget_Config_Novel", table: "WidgetLocalizable"))
    var novel: PhonePlayNovelChoice?

    @Parameter(title: LocalizedStringResource("Phone_Widget_Config_Icon", table: "WidgetLocalizable"), default: .play)
    var icon: PhonePlayNovelWidgetIcon

    @Parameter(title: LocalizedStringResource("Phone_Widget_Config_Color", table: "WidgetLocalizable"), default: .orange)
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
    /// ウィジェット追加画面(ギャラリー)のプレビューかどうか。
    /// プレビューでは「未設定」ではなく機能の見本として表示する
    var isPreview: Bool = false
}

struct PhonePlayNovelProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhonePlayNovelEntry {
        PhonePlayNovelEntry(date: Date(), novelID: nil, title: nil, progress: 0,
                            iconSystemName: PhonePlayNovelWidgetIcon.play.systemName, tint: .orange,
                            isPreview: true)
    }

    func snapshot(for configuration: PhonePlayNovelConfigurationIntent, in context: Context) async -> PhonePlayNovelEntry {
        return entry(for: configuration, isPreview: context.isPreview)
    }

    func timeline(for configuration: PhonePlayNovelConfigurationIntent, in context: Context) async -> Timeline<PhonePlayNovelEntry> {
        // 更新はアプリ側の WidgetCenter.reloadAllTimelines で駆動するので固定1エントリ
        return Timeline(entries: [entry(for: configuration, isPreview: false)], policy: .never)
    }

    private func entry(for configuration: PhonePlayNovelConfigurationIntent, isPreview: Bool) -> PhonePlayNovelEntry {
        let novelID = configuration.novel?.id
        // 選択済みの小説の最新情報(タイトル・読了進捗)は共有ストアから引き直す
        let summary = novelID.flatMap { PhoneWidgetDataStore.summary(novelID: $0) }
        return PhonePlayNovelEntry(
            date: Date(),
            novelID: novelID,
            title: summary?.title ?? configuration.novel?.title,
            progress: summary?.overallProgress ?? 0,
            // 小説が未選択の間は歯車バッジにして「要設定」であることを見た目でも示す
            // (円形ウィジェットは文字が出せないのでこれが唯一の手掛かりになる)。
            // ギャラリーのプレビューは「未設定」ではなく機能の見本なので通常のアイコンで出す
            iconSystemName: (novelID == nil && !isPreview) ? "gearshape.fill" : configuration.icon.systemName,
            tint: configuration.color.color,
            isPreview: isPreview)
    }
}

// MARK: - 表示

struct PhonePlayNovelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    let entry: PhonePlayNovelEntry

    // 未選択時の1行目。ギャラリーのプレビューでは機能名を出し、
    // 実際に置かれた未設定ウィジェットでは「小説を選択」を出す
    private var displayTitle: String {
        if let title = entry.title { return title }
        if entry.isPreview {
            return NSLocalizedString("Phone_Widget_PlayNovel_Name", tableName: "WidgetLocalizable", bundle: .main, comment: "指定小説の再生を開始")
        }
        return NSLocalizedString("Phone_Widget_PlayNovel_Unset", tableName: "WidgetLocalizable", bundle: .main, comment: "小説を選択")
    }

    // 単色系(ロック画面)では色分けが効かないのでシステムに任せ、フルカラーのみ選択色を適用する
    private var iconTint: Color? { renderingMode == .fullColor ? entry.tint : nil }

    private var whiteFG: Bool { PhoneWidgetTheme.usesWhiteForeground(renderingMode: renderingMode, colorScheme: colorScheme) }
    private var primaryStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white) : AnyShapeStyle(.primary) }
    private var subtleStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary) }

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
        .phoneWidgetContainerBackground()
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
                    } else {
                        Text(NSLocalizedString("Phone_Widget_PlayNovel_UnsetHint", tableName: "WidgetLocalizable", bundle: .main, comment: "長押しなどの編集で小説を選択"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        default:
            // ホーム画面(systemSmall): 合成アイコン + 小説名 + 読了ゲージ + タップ時の動作
            // (未選択の間は選択手順の案内を出す)。
            // 「再生・停止」と違いトグルではないことが分かるよう、末尾に動作を明示する
            VStack(spacing: 5) {
                PhoneActionGlyphView(badgeSystemName: entry.iconSystemName, badgeColor: entry.tint, brandStyle: whiteFG)
                    .frame(width: 46, height: 46)
                if entry.novelID != nil {
                    Text(displayTitle)
                        .font(.caption)
                        .foregroundStyle(primaryStyle)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    Gauge(value: entry.progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(whiteFG ? .white : iconTint)
                    Spacer(minLength: 0)
                    Text(NSLocalizedString("Phone_Widget_PlayNovel_TapHint", tableName: "WidgetLocalizable", bundle: .main, comment: "タップで再生を開始"))
                        .font(.caption2)
                        .foregroundStyle(subtleStyle)
                } else {
                    Text(NSLocalizedString("Phone_Widget_PlayNovel_UnsetHint", tableName: "WidgetLocalizable", bundle: .main, comment: "長押しなどの編集で小説を選択"))
                        .font(.caption2)
                        .foregroundStyle(subtleStyle)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
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
        .configurationDisplayName(NSLocalizedString("Phone_Widget_PlayNovel_Name", tableName: "WidgetLocalizable", bundle: .main, comment: "指定小説の再生を開始"))
        .description(NSLocalizedString("Phone_Widget_PlayNovel_Desc", tableName: "WidgetLocalizable", bundle: .main, comment: "指定した小説の読み上げを、ことせかい を開かずに開始します。小説の候補は最近読んだ順に並びます。"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - コントロール版(iOS 18+。コントロールセンター+ロック画面下部の角スロット)

/// コントロールの設定 intent(小説の選択のみ。アイコン・色はコントロールでは選べない)
@available(iOSApplicationExtension 18.0, *)
struct PhonePlayNovelControlIntent: ControlConfigurationIntent {
    static var title = LocalizedStringResource("Phone_Widget_PlayNovel_Name", table: "WidgetLocalizable")
    static var description = IntentDescription(LocalizedStringResource("Phone_Widget_PlayNovel_ControlDesc", table: "WidgetLocalizable"))

    @Parameter(title: LocalizedStringResource("Phone_Widget_Config_Novel", table: "WidgetLocalizable"))
    var novel: PhonePlayNovelChoice?
}

@available(iOSApplicationExtension 18.0, *)
struct PhonePlayNovelControlValue {
    var novelID: String?
    var title: String?
}

@available(iOSApplicationExtension 18.0, *)
struct PhonePlayNovelControlValueProvider: AppIntentControlValueProvider {
    func previewValue(configuration: PhonePlayNovelControlIntent) -> PhonePlayNovelControlValue {
        PhonePlayNovelControlValue(novelID: configuration.novel?.id, title: configuration.novel?.title)
    }
    func currentValue(configuration: PhonePlayNovelControlIntent) async throws -> PhonePlayNovelControlValue {
        PhonePlayNovelControlValue(novelID: configuration.novel?.id, title: configuration.novel?.title)
    }
}

@available(iOSApplicationExtension 18.0, *)
struct PhonePlayNovelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // kind の "2" は世代番号(コントロール一覧の絵の作り直し用。NovelSpeakerWidget.swift 参照)
        AppIntentControlConfiguration(kind: "com.limuraproducts.novelspeaker.widget.control.playNovel3",
                                      provider: PhonePlayNovelControlValueProvider()) { value in
            // 未選択のまま押した場合は PhonePlayNovelIntent 側で何もしない。
            // 未選択の間は歯車アイコンで「要設定」を示す。選択済みは
            // ことせかいグリフ+▶の合成カスタムシンボル
            ControlWidgetButton(action: PhonePlayNovelIntent(novelID: value.novelID ?? "")) {
                Label {
                    Text(value.title ?? NSLocalizedString("Phone_Widget_PlayNovel_Unset", tableName: "WidgetLocalizable", bundle: .main, comment: "小説を選択"))
                } icon: {
                    if value.novelID == nil {
                        Image(systemName: "gearshape.fill")
                    } else {
                        Image("NovelSpeakerGlyphPlay3")
                    }
                }
            }
        }
        .displayName(LocalizedStringResource("Phone_Widget_PlayNovel_Name", table: "WidgetLocalizable"))
        .description(LocalizedStringResource("Phone_Widget_PlayNovel_ControlDesc", table: "WidgetLocalizable"))
    }
}
