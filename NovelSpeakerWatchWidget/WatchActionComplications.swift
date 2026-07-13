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
//  いずれも ことせかい のグリフに操作を表す SF Symbol バッジを重ねた見た目。
//  複数を文字盤に並べても区別できるよう、バッジで機能を示す。
//

import WidgetKit
import SwiftUI

struct ActionComplicationEntry: TimelineEntry {
    let date: Date
}

/// 表示内容は固定(タップでアプリを起動するだけ)なので、単一エントリ・自動更新なし
struct ActionComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActionComplicationEntry {
        ActionComplicationEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (ActionComplicationEntry) -> Void) {
        completion(ActionComplicationEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActionComplicationEntry>) -> Void) {
        completion(Timeline(entries: [ActionComplicationEntry(date: Date())], policy: .never))
    }
}

/// ことせかいのグリフに、操作を表す SF Symbol バッジを右下に重ねた circular 表示
struct ActionGlyphView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let badgeSystemName: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .bottomTrailing) {
                BrandGlyph()
                    .frame(width: side, height: side)
                Image(systemName: badgeSystemName)
                    .font(.system(size: side * 0.34, weight: .bold))
                    .foregroundStyle(badgeForeground)
                    .padding(side * 0.07)
                    .background(Circle().fill(badgeBackground))
                    .overlay(Circle().stroke(badgeStroke, lineWidth: max(1, side * 0.03)))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // fullColor(カラー文字盤)はオレンジ地×白でアプリアイコンと調和させ、
    // 単色系(accented/vibrant)は塗り分けが効かないのでバッジも単色でまとめる
    private var badgeForeground: some ShapeStyle {
        renderingMode == .fullColor ? AnyShapeStyle(.white) : AnyShapeStyle(.black)
    }
    private var badgeBackground: some ShapeStyle {
        renderingMode == .fullColor ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary)
    }
    private var badgeStroke: some ShapeStyle {
        renderingMode == .fullColor ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.clear)
    }
}

/// グリフ+バッジ表示に widgetURL を付けた circular コンプリケーションの中身
struct ActionComplicationView: View {
    let badgeSystemName: String
    let action: WatchWidgetAction

    var body: some View {
        ActionGlyphView(badgeSystemName: badgeSystemName)
            .padding(2)
            .containerBackground(for: .widget) { Color.clear }
            .widgetURL(action.url)
    }
}

// MARK: - 3種のコンプリケーション

struct PlayPauseComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.playToggle",
                            provider: ActionComplicationProvider()) { _ in
            ActionComplicationView(badgeSystemName: "playpause.fill", action: .togglePlayPause)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_PlayToggle_Name", comment: "再生・一時停止"))
        .description(NSLocalizedString("Watch_Widget_PlayToggle_Desc", comment: "タップで ことせかい を開き、再生/一時停止を切り替えます。"))
        .supportedFamilies([.accessoryCircular])
    }
}

struct TextPageComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.textPage",
                            provider: ActionComplicationProvider()) { _ in
            ActionComplicationView(badgeSystemName: "book.fill", action: .openTextPage)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_TextPage_Name", comment: "本文ページ"))
        .description(NSLocalizedString("Watch_Widget_TextPage_Desc", comment: "タップで ことせかい の本文ページを開きます。"))
        .supportedFamilies([.accessoryCircular])
    }
}

struct CheckUpdatesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.checkUpdates",
                            provider: ActionComplicationProvider()) { _ in
            ActionComplicationView(badgeSystemName: "arrow.clockwise", action: .checkUpdatesAll)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_CheckUpdates_Name", comment: "更新確認"))
        .description(NSLocalizedString("Watch_Widget_CheckUpdates_Desc", comment: "タップで ことせかい を開き、すべての小説の更新を確認します。"))
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview("PlayToggle", as: .accessoryCircular) {
    PlayPauseComplication()
} timeline: {
    ActionComplicationEntry(date: .now)
}

#Preview("TextPage", as: .accessoryCircular) {
    TextPageComplication()
} timeline: {
    ActionComplicationEntry(date: .now)
}

#Preview("CheckUpdates", as: .accessoryCircular) {
    CheckUpdatesComplication()
} timeline: {
    ActionComplicationEntry(date: .now)
}
