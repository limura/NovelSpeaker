//
//  WatchActionComplications.swift
//  NovelSpeakerWatchWidget
//
//  操作系コンプリケーション(第1弾)。circular ファミリで、タップすると widgetURL の
//  ディープリンクを開いて ことせかい アプリ本体を起動し、アプリ側で操作を実行する。
//  (ウィジェット拡張プロセスでは WCSession も発話も使えないため、Button(intent:) ではなく
//   widgetURL でアプリを起動する方式。WatchWidgetAction / 調査メモ参照)
//
//  ラインナップ:
//  - 再生・一時停止(playpause): 現在の発話元(iPhone/Watch単体)の再生をトグル
//  - 本文ページ(book.fill):     本文ページを開く
//  - 更新確認(arrow.clockwise): すべての小説の更新を確認する
//
//  見た目: ことせかい のグリフを少し小さくして左上に寄せ、右下に機能を表す SF Symbol を
//  少し重ねて置く(グリフ下側の白くゴチャついた部分と機能アイコンが重ならないようにして、
//  単色文字盤でも機能アイコンが埋もれないようにする)。
//  さらに widgetLabel に「対象小説名(再生・本文) / アプリ名(更新確認)」を出して、
//  何のウィジェットかが文字でも分かるようにする(対応文字盤では曲線ラベルとして出る)。
//

import WidgetKit
import SwiftUI
import AppIntents

/// 操作系コンプリケーションの設定(機能アイコンの色)。
/// 色が変わるだけでカラー文字盤での複数配置時の視認性が格段に上がるため選べるようにする。
/// 実行用の intent ではない(操作は widgetURL)。色の enum は「この小説を再生」と共用
struct ActionColorConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "色の設定"
    static var description = IntentDescription("機能アイコンの色を選べます。")

    @Parameter(title: "色", default: .orange)
    var color: PlayNovelWidgetColor
}

struct ActionComplicationEntry: TimelineEntry {
    let date: Date
    /// 対象小説のタイトル(再生トグル/本文の widgetLabel 用。無ければアプリ名にフォールバック)
    let novelTitle: String?
    /// 機能アイコンの地色(fullColor 文字盤でのみ効く)
    let tint: Color
}

/// 表示内容は「今読んでいる小説名」くらいなので、App Group から読んだ単一エントリ・自動更新なし
/// (小説・章が変わった時は Watch アプリ側が reloadAllTimelines する)
struct ActionComplicationProvider: AppIntentTimelineProvider {
    /// 文字盤の一覧に出すプリセット名(NSLocalizedString のキー。各ウィジェットの表示名)
    let recommendationNameKey: String

    func placeholder(in context: Context) -> ActionComplicationEntry {
        ActionComplicationEntry(date: Date(), novelTitle: nil, tint: .orange)
    }
    func snapshot(for configuration: ActionColorConfigurationIntent, in context: Context) async -> ActionComplicationEntry {
        return currentEntry(configuration: configuration)
    }
    func timeline(for configuration: ActionColorConfigurationIntent, in context: Context) async -> Timeline<ActionComplicationEntry> {
        return Timeline(entries: [currentEntry(configuration: configuration)], policy: .never)
    }

    func recommendations() -> [AppIntentRecommendation<ActionColorConfigurationIntent>] {
        if #available(watchOS 26.0, *) {
            // watchOS 26 の文字盤は recommendations が空だと「設定可能なエントリ」を1つ出し、
            // 追加時に設定 UI(色)が開く(「この小説を再生」で実機確認した挙動)。
            // プリセットを返すと固定の色しか選べなくなるため、空を返して設定 UI に任せる
            return []
        }
        // 旧 watchOS の文字盤には設定 UI が無いため、既定色のプリセットを1つ返す
        return [AppIntentRecommendation(intent: ActionColorConfigurationIntent(),
                                        description: Text(NSLocalizedString(recommendationNameKey, comment: "")))]
    }

    private func currentEntry(configuration: ActionColorConfigurationIntent) -> ActionComplicationEntry {
        let data = WatchComplicationData.load()
        let title = (data?.hasNovel == true) ? data?.title : nil
        return ActionComplicationEntry(date: Date(), novelTitle: title, tint: configuration.color.color)
    }
}

/// ことせかいのグリフ(左上・やや小さめ)に、操作を表す SF Symbol バッジ(右下)を重ねた表示。
/// circular / corner / rectangular で共用する。
/// badgeColor は fullColor 文字盤でのバッジ地色(「この小説を再生」の色選択に使う)。
struct ActionGlyphView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family
    let badgeSystemName: String
    var badgeColor: Color = .orange
    /// nil なら ことせかい のグリフをベースにする。SF Symbol 名を指定するとそれをベースにする
    /// (「Watchで再生」「iPhoneで再生」が applewatch / iphone を使う。これらの制限付きシンボルは
    ///  Apple 製品そのものを指す用途なら使用可)
    var baseSystemName: String? = nil

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // ベース(ことせかいグリフ等)を 2/3 弱に縮めて左上へ寄せる
                // (下側のゴチャつきを機能アイコンから外す)。
                // バッジと重なる部分はベース側をくり抜いて、バッジ(特に corner のリング)が
                // ベースの白い部分に重ならず暗い文字盤地の上に乗るようにする
                base(side: side)
                    .frame(width: side * 0.60, height: side * 0.60)
                    .mask {
                        Rectangle()
                            .overlay(
                                // バッジ(直径0.48)より一回り大きい穴。グリフ中心(0.38,0.38)から見た
                                // バッジ中心(0.66,0.66)の相対位置 = (0.28,0.28)
                                Circle()
                                    .frame(width: side * 0.52, height: side * 0.52)
                                    .offset(x: side * 0.28, y: side * 0.28)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    }
                    .offset(x: -side * 0.12, y: -side * 0.12)
                badge(side: side)
                    .offset(x: side * 0.16, y: side * 0.16)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ベース。ことせかいグリフ、または指定の SF Symbol(fullColor では ことせかい ぽいオレンジ、
    // 単色系では白のテンプレート。BrandGlyph の出し分けと同じ考え方)
    @ViewBuilder
    private func base(side: CGFloat) -> some View {
        if let baseSystemName = baseSystemName {
            Image(systemName: baseSystemName)
                .font(.system(size: side * 0.48, weight: .medium))
                .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(.orange) : AnyShapeStyle(.white))
                .minimumScaleFactor(0.5)
        } else {
            BrandGlyph()
        }
    }

    // 機能アイコン。
    // - fullColor 文字盤: 地の丸=選択色(既定オレンジ)×白記号。
    // - 単色系(circular/rectangular): 地の丸だけを widgetAccentable で「アクセント側グループ」に
    //   入れ、記号(白)とグリフ(白)は既定グループのまま。地の丸だけアクセント色になり白記号が読める。
    // - 単色系の corner: corner はアクセントグループの塗り分けが効かず、塗り丸だと丸も記号も
    //   白に潰れて「白い丸」になる(実機で確認)。塗り丸をやめて「白リング+白記号」にし、
    //   暗い文字盤背景を地として読ませる
    @ViewBuilder
    private func badge(side: CGFloat) -> some View {
        ZStack {
            if renderingMode == .fullColor {
                Circle().fill(badgeColor)
            } else if family == .accessoryCorner {
                Circle().stroke(.white, lineWidth: max(1, side * 0.035))
            } else {
                Circle().fill(.primary).widgetAccentable()
            }
            Image(systemName: badgeSystemName)
                .font(.system(size: side * 0.30, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: side * 0.48, height: side * 0.48)
    }
}

/// グリフ+バッジ表示に widgetLabel と widgetURL を付けた circular コンプリケーションの中身
struct ActionComplicationView: View {
    let entry: ActionComplicationEntry
    let badgeSystemName: String
    let action: WatchWidgetAction
    /// widgetLabel に小説タイトルを出すか(更新確認はアプリ名固定なので false)
    let usesNovelTitleLabel: Bool
    /// ベースを SF Symbol にする場合に指定(「Watchで再生」「iPhoneで再生」)
    var baseSystemName: String? = nil

    var body: some View {
        ActionGlyphView(badgeSystemName: badgeSystemName, badgeColor: entry.tint, baseSystemName: baseSystemName)
            .padding(2)
            .containerBackground(for: .widget) { Color.clear }
            .widgetLabel { Text(labelText) }
            .widgetURL(action.url)
    }

    private var labelText: String {
        let appName = NSLocalizedString("Watch_Widget_AppName", comment: "ことせかい")
        if usesNovelTitleLabel, let title = entry.novelTitle, !title.isEmpty {
            return title
        }
        return appName
    }
}

// MARK: - 3種のコンプリケーション

struct PlayPauseComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.playToggle",
                               intent: ActionColorConfigurationIntent.self,
                               provider: ActionComplicationProvider(recommendationNameKey: "Watch_Widget_PlayToggle_Name")) { entry in
            ActionComplicationView(entry: entry, badgeSystemName: "playpause.fill",
                                   action: .togglePlayPause, usesNovelTitleLabel: true)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_PlayToggle_Name", comment: "再生・一時停止"))
        .description(NSLocalizedString("Watch_Widget_PlayToggle_Desc", comment: "タップで ことせかい を開き、再生/一時停止を切り替えます。"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct TextPageComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.textPage",
                               intent: ActionColorConfigurationIntent.self,
                               provider: ActionComplicationProvider(recommendationNameKey: "Watch_Widget_TextPage_Name")) { entry in
            ActionComplicationView(entry: entry, badgeSystemName: "book.fill",
                                   action: .openTextPage, usesNovelTitleLabel: true)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_TextPage_Name", comment: "本文ページ"))
        .description(NSLocalizedString("Watch_Widget_TextPage_Desc", comment: "タップで ことせかい の本文ページを開きます。"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct CheckUpdatesComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.checkUpdates",
                               intent: ActionColorConfigurationIntent.self,
                               provider: ActionComplicationProvider(recommendationNameKey: "Watch_Widget_CheckUpdates_Name")) { entry in
            ActionComplicationView(entry: entry, badgeSystemName: "arrow.clockwise",
                                   action: .checkUpdatesAll, usesNovelTitleLabel: false)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_CheckUpdates_Name", comment: "更新確認"))
        .description(NSLocalizedString("Watch_Widget_CheckUpdates_Desc", comment: "タップで ことせかい を開き、すべての小説の更新を確認します。"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// Watch 単体再生モードに切り替えて再生を開始する。ベース=applewatch シンボル+▶バッジ。
/// (applewatch/iphone は制限付きシンボルだが「Apple 製品そのものを指す」用途なので使用可)
struct PlayOnWatchComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.playOnWatch",
                               intent: ActionColorConfigurationIntent.self,
                               provider: ActionComplicationProvider(recommendationNameKey: "Watch_Widget_PlayOnWatch_Name")) { entry in
            ActionComplicationView(entry: entry, badgeSystemName: "play.fill",
                                   action: .playOnWatch, usesNovelTitleLabel: true,
                                   baseSystemName: "applewatch")
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_PlayOnWatch_Name", comment: "ことせかい Watchで再生"))
        .description(NSLocalizedString("Watch_Widget_PlayOnWatch_Desc", comment: "タップで ことせかい を開き、Watch単体再生に切り替えて再生を開始します。"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

/// iPhone での再生に切り替えて再生を開始する。ベース=iphone シンボル+▶バッジ
struct PlayOnPhoneComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.playOnPhone",
                               intent: ActionColorConfigurationIntent.self,
                               provider: ActionComplicationProvider(recommendationNameKey: "Watch_Widget_PlayOnPhone_Name")) { entry in
            ActionComplicationView(entry: entry, badgeSystemName: "play.fill",
                                   action: .playOnPhone, usesNovelTitleLabel: true,
                                   baseSystemName: "iphone")
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_PlayOnPhone_Name", comment: "ことせかい iPhoneで再生"))
        .description(NSLocalizedString("Watch_Widget_PlayOnPhone_Desc", comment: "タップで ことせかい を開き、iPhoneでの再生に切り替えて再生を開始します。"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

// MARK: - アクション3枠(AccessoryWidgetGroup, watchOS 11+)

/// 3枠に置ける操作の種類
enum ActionSlotKind: String, AppEnum {
    case playToggle, playOnWatch, playOnPhone, textPage, checkUpdates, playNovel

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "操作")
    static var caseDisplayRepresentations: [ActionSlotKind: DisplayRepresentation] = [
        .playToggle:   DisplayRepresentation(title: "再生・停止"),
        .playOnWatch:  DisplayRepresentation(title: "Watchで再生"),
        .playOnPhone:  DisplayRepresentation(title: "iPhoneで再生"),
        .textPage:     DisplayRepresentation(title: "本文ページ"),
        .checkUpdates: DisplayRepresentation(title: "更新確認"),
        .playNovel:    DisplayRepresentation(title: "この小説を再生"),
    ]

    var badgeSystemName: String {
        switch self {
        case .playToggle:   return "playpause.fill"
        case .playOnWatch:  return "play.fill"
        case .playOnPhone:  return "play.fill"
        case .textPage:     return "book.fill"
        case .checkUpdates: return "arrow.clockwise"
        case .playNovel:    return "play.fill"
        }
    }

    var baseSystemName: String? {
        switch self {
        case .playOnWatch: return "applewatch"
        case .playOnPhone: return "iphone"
        default:           return nil
        }
    }

    /// この枠のディープリンク(novelID は playNovel の時だけ使う)
    func url(novelID: String?) -> URL? {
        switch self {
        case .playToggle:   return WatchWidgetAction.togglePlayPause.url
        case .playOnWatch:  return WatchWidgetAction.playOnWatch.url
        case .playOnPhone:  return WatchWidgetAction.playOnPhone.url
        case .textPage:     return WatchWidgetAction.openTextPage.url
        case .checkUpdates: return WatchWidgetAction.checkUpdatesAll.url
        case .playNovel:
            guard let novelID = novelID, !novelID.isEmpty else { return nil }
            return WatchWidgetAction.playNovel(novelID: novelID).url
        }
    }
}

/// アクション3枠の設定。「小説」は「この小説を再生」を選んだ枠でだけ使われる
struct ActionGroupConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "3つの操作"
    static var description = IntentDescription("3つの枠に置く操作を選べます。「小説」は「この小説を再生」を選んだ枠でだけ使われます。")

    @Parameter(title: "左の操作", default: .playToggle)
    var slot1: ActionSlotKind
    @Parameter(title: "左の小説")
    var novel1: PlayNovelChoice?

    @Parameter(title: "中央の操作", default: .playOnWatch)
    var slot2: ActionSlotKind
    @Parameter(title: "中央の小説")
    var novel2: PlayNovelChoice?

    @Parameter(title: "右の操作", default: .checkUpdates)
    var slot3: ActionSlotKind
    @Parameter(title: "右の小説")
    var novel3: PlayNovelChoice?
}

struct ActionGroupEntry: TimelineEntry {
    struct Slot {
        let kind: ActionSlotKind
        let novelID: String?
    }
    let date: Date
    let slots: [Slot]
}

struct ActionGroupProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActionGroupEntry {
        ActionGroupEntry(date: Date(), slots: [
            .init(kind: .playToggle, novelID: nil),
            .init(kind: .playOnWatch, novelID: nil),
            .init(kind: .checkUpdates, novelID: nil),
        ])
    }
    func snapshot(for configuration: ActionGroupConfigurationIntent, in context: Context) async -> ActionGroupEntry {
        return entry(for: configuration)
    }
    func timeline(for configuration: ActionGroupConfigurationIntent, in context: Context) async -> Timeline<ActionGroupEntry> {
        return Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    func recommendations() -> [AppIntentRecommendation<ActionGroupConfigurationIntent>] {
        if #available(watchOS 26.0, *) {
            // watchOS 26 の文字盤は空だと「設定可能なエントリ」が出る(他ウィジェットと同じ)
            return []
        }
        // 旧 watchOS では既定構成のプリセットを1つ返す
        return [AppIntentRecommendation(intent: ActionGroupConfigurationIntent(),
                                        description: Text(NSLocalizedString("Watch_Widget_ActionGroup_Name", comment: "ことせかい 3つの操作")))]
    }

    private func entry(for configuration: ActionGroupConfigurationIntent) -> ActionGroupEntry {
        return ActionGroupEntry(date: Date(), slots: [
            .init(kind: configuration.slot1, novelID: configuration.novel1?.id),
            .init(kind: configuration.slot2, novelID: configuration.novel2?.id),
            .init(kind: configuration.slot3, novelID: configuration.novel3?.id),
        ])
    }
}

@available(watchOS 11.0, *)
struct ActionGroupComplicationView: View {
    let entry: ActionGroupEntry

    var body: some View {
        AccessoryWidgetGroup(label: {
            Text(NSLocalizedString("Watch_Widget_AppName", comment: "ことせかい"))
        }, content: {
            slotView(entry.slots[0])
            slotView(entry.slots[1])
            slotView(entry.slots[2])
        })
        .containerBackground(for: .widget) { Color.clear }
    }

    // 各枠は単機能ウィジェットと同じ合成アイコン。タップは枠ごとの widgetURL で分ける
    @ViewBuilder
    private func slotView(_ slot: ActionGroupEntry.Slot) -> some View {
        ActionGlyphView(badgeSystemName: slot.kind.badgeSystemName,
                        baseSystemName: slot.kind.baseSystemName)
            .widgetURL(slot.kind.url(novelID: slot.novelID))
    }
}

@available(watchOS 11.0, *)
struct ActionGroupComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.actionGroup",
                               intent: ActionGroupConfigurationIntent.self,
                               provider: ActionGroupProvider()) { entry in
            ActionGroupComplicationView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_ActionGroup_Name", comment: "ことせかい 3つの操作"))
        .description(NSLocalizedString("Watch_Widget_ActionGroup_Desc", comment: "選んだ3つの操作を並べて置けます。"))
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview("PlayToggle", as: .accessoryCircular) {
    PlayPauseComplication()
} timeline: {
    ActionComplicationEntry(date: .now, novelTitle: "転生したらスライムだった件", tint: .orange)
}

#Preview("TextPage", as: .accessoryCircular) {
    TextPageComplication()
} timeline: {
    ActionComplicationEntry(date: .now, novelTitle: "転生したらスライムだった件", tint: .teal)
}

#Preview("CheckUpdates", as: .accessoryCircular) {
    CheckUpdatesComplication()
} timeline: {
    ActionComplicationEntry(date: .now, novelTitle: nil, tint: .purple)
}
