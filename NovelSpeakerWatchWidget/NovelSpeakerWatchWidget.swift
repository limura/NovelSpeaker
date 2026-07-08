//
//  NovelSpeakerWatchWidget.swift
//  NovelSpeakerWatchWidget
//
//  Watch 文字盤のコンプリケーション(WidgetKit accessory 系)。
//  第一弾は「タップで ことせかい を起動する」静的ランチャーのみ
//  (accessoryCircular = 文字盤の丸枠、accessoryCorner = 四隅 + カーブしたラベル)。
//  TimelineProvider は固定1エントリで、データ共有(App Group)は使わない。
//
//  第二弾(未実装)の案: accessoryRectangular で「最後に聴いていた小説タイトル+章進捗」。
//  App Group + WidgetCenter.reloadTimelines が必要になる。
//

import WidgetKit
import SwiftUI

@main
struct NovelSpeakerWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        LauncherComplication()
    }
}

struct LauncherEntry: TimelineEntry {
    let date: Date
}

/// 静的ランチャーなのでタイムラインは常に1エントリ・更新なし
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        return LauncherEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

struct LauncherComplicationView: View {
    var body: some View {
        // コンプリケーションは文字盤上で単色描画される(不透明な正方形アイコンをそのまま渡すと
        // 脱色されて「灰色の塗り潰し円」になる)。アプリアイコンの白グリフ部分だけを
        // 透過テンプレート画像として切り出したもの(LauncherGlyph)を使う
        Image("LauncherGlyph")
            .resizable()
            .scaledToFit()
            .padding(2)
            .widgetLabel {
                // accessoryCorner の時だけ、角のカーブに沿ってアプリ名が出る
                Text("ことせかい")
            }
            .containerBackground(for: .widget) {
                Color.clear
            }
    }
}

struct LauncherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.launcher",
                            provider: LauncherProvider()) { _ in
            LauncherComplicationView()
        }
        .configurationDisplayName("ことせかい")
        .description("タップして ことせかい を開きます。")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

// Xcode のキャンバス(Editor → Canvas)で、実機のキャッシュに関係なく
// コンプリケーションの「本物の描画」を確認できる。灰色の角丸四角はプレースホルダ描画で、
// ここ(通常描画)ではグリフが出る
#Preview("Circular", as: .accessoryCircular) {
    LauncherComplication()
} timeline: {
    LauncherEntry(date: .now)
}

#Preview("Corner", as: .accessoryCorner) {
    LauncherComplication()
} timeline: {
    LauncherEntry(date: .now)
}
