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

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // ことせかいグリフを 2/3 弱に縮めて左上へ寄せる(下側のゴチャつきを機能アイコンから外す)。
                // バッジと重なる部分はグリフ側をくり抜いて、バッジ(特に corner のリング)が
                // グリフの白い部分に重ならず暗い文字盤地の上に乗るようにする
                BrandGlyph()
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

    var body: some View {
        ActionGlyphView(badgeSystemName: badgeSystemName, badgeColor: entry.tint)
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
