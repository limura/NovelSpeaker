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

struct ActionComplicationEntry: TimelineEntry {
    let date: Date
    /// 対象小説のタイトル(再生トグル/本文の widgetLabel 用。無ければアプリ名にフォールバック)
    let novelTitle: String?
}

/// 表示内容は「今読んでいる小説名」くらいなので、App Group から読んだ単一エントリ・自動更新なし
/// (小説・章が変わった時は Watch アプリ側が reloadAllTimelines する)
struct ActionComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActionComplicationEntry {
        ActionComplicationEntry(date: Date(), novelTitle: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (ActionComplicationEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActionComplicationEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> ActionComplicationEntry {
        let data = WatchComplicationData.load()
        let title = (data?.hasNovel == true) ? data?.title : nil
        return ActionComplicationEntry(date: Date(), novelTitle: title)
    }
}

/// ことせかいのグリフ(左上・やや小さめ)に、操作を表す SF Symbol バッジ(右下)を重ねた表示。
/// circular / corner / rectangular で共用する。
/// badgeColor は fullColor 文字盤でのバッジ地色(「この小説を再生」の色選択に使う)。
struct ActionGlyphView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let badgeSystemName: String
    var badgeColor: Color = .orange

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // ことせかいグリフを 2/3 弱に縮めて左上へ寄せる(下側のゴチャつきを機能アイコンから外す)
                BrandGlyph()
                    .frame(width: side * 0.60, height: side * 0.60)
                    .offset(x: -side * 0.12, y: -side * 0.12)
                badge(side: side)
                    .offset(x: side * 0.16, y: side * 0.16)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // 機能アイコン。地の丸だけを widgetAccentable にして「アクセント側グループ」に入れ、
    // 記号(白)とグリフ(白)は既定グループのままにする。こうすると単色文字盤でも
    // 地の丸だけがアクセント色になり、白い記号が潰れず読める(白丸化バグの対策)。
    // fullColor 文字盤では地の丸=選択色(既定オレンジ)×白記号。
    @ViewBuilder
    private func badge(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(renderingMode == .fullColor ? AnyShapeStyle(badgeColor) : AnyShapeStyle(.primary))
                .widgetAccentable()
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
        ActionGlyphView(badgeSystemName: badgeSystemName)
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
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.playToggle",
                            provider: ActionComplicationProvider()) { entry in
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
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.textPage",
                            provider: ActionComplicationProvider()) { entry in
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
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.checkUpdates",
                            provider: ActionComplicationProvider()) { entry in
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
    ActionComplicationEntry(date: .now, novelTitle: "転生したらスライムだった件")
}

#Preview("TextPage", as: .accessoryCircular) {
    TextPageComplication()
} timeline: {
    ActionComplicationEntry(date: .now, novelTitle: "転生したらスライムだった件")
}

#Preview("CheckUpdates", as: .accessoryCircular) {
    CheckUpdatesComplication()
} timeline: {
    ActionComplicationEntry(date: .now, novelTitle: nil)
}
