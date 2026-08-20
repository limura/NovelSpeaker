//
//  NovelSpeakerWatchWidget.swift
//  NovelSpeakerWatchWidget
//
//  Watch 文字盤のコンプリケーション(WidgetKit accessory 系)。
//  - ランチャー(タップで ことせかい を起動)を兼ねつつ、「今読んでいる小説」の進捗を表示する。
//  - データは App Group 共有ストア(WatchComplicationData)を Watch アプリが書き、ここが読む。
//    まだ何も読んでいない/データが無い時はアプリアイコンのグリフだけ出す(ランチャーとして機能)。
//
//  families:
//  - accessoryCircular: 読了ゲージのリング + 中央にグリフ
//  - accessoryCorner: グリフ + 角のラベル(章/総章 など)
//  - accessoryRectangular: 小説タイトル + 章タイトル(or 章/総章) + ゲージバー
//
//  更新は Watch アプリ側の WidgetCenter.reloadAllTimelines で駆動する(OS が間引くので
//  リアルタイム追従はしない。章切替・停止などの節目で更新される鮮度)。
//

import WidgetKit
import SwiftUI

@main
struct NovelSpeakerWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        LauncherComplication()
        // 操作系(第1弾): タップで widgetURL からアプリを起動して操作する(circular / corner)
        PlayPauseComplication()
        TextPageComplication()
        CheckUpdatesComplication()
        // 第2弾: 設定可能ウィジェット「この小説を再生」(circular / corner / rectangular)
        PlayNovelComplication()
        // 発話元を切り替えて再生を開始するワンショット(circular / corner)
        PlayOnWatchComplication()
        PlayOnPhoneComplication()
        // アクション3枠(rectangular)。AccessoryWidgetGroup は watchOS 11+
        if #available(watchOS 11.0, *) {
            ActionGroupComplication()
        }
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let data: WatchComplicationData?
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), data: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), data: WatchComplicationData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // 更新は Watch アプリの reloadAllTimelines で駆動するので、固定1エントリ・自動更新なし
        completion(Timeline(entries: [ComplicationEntry(date: Date(), data: WatchComplicationData.load())],
                            policy: .never))
    }
}

/// ブランドのグリフ。カラー文字盤(fullColor)ではアプリアイコン(橙背景+白グリフ)を
/// 円形にして出し、単色系の文字盤では透過テンプレートの白グリフを出す
/// (単色系にカラーアイコンを渡すと脱色されて灰色の塗り潰し円になるため)
struct BrandGlyph: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            Image("LauncherIconColor")
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
        } else {
            Image("LauncherGlyph")
                .resizable()
                .scaledToFit()
        }
    }
}

struct LauncherComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var reading: WatchComplicationData? {
        guard let data = entry.data, data.hasNovel else { return nil }
        return data
    }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            BrandGlyph().padding(2)
        }
    }

    // 円形: 読了ゲージのリング + 中央グリフ。データが無ければグリフだけ(ランチャー)。
    // 円の中に長い小説名は入らないので、名前は widgetLabel(インフォグラフ等では
    // サブダイヤルの外周/下に文字が出せる場面がある)に「小説名・章/総章」で載せる
    @ViewBuilder
    private var circular: some View {
        if let reading = reading, reading.chapterCount > 0 {
            ZStack {
                Circle().stroke(.tertiary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.01, reading.overallProgress))
                    .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                BrandGlyph().padding(7)
            }
            .padding(1)
            .widgetLabel {
                Text(String(format: NSLocalizedString("Watch_Widget_TitleChapterFormat", comment: "%1$@・%2$@"),
                            reading.title, reading.chapterFraction))
            }
        } else {
            BrandGlyph().padding(2)
        }
    }

    // 角: ことせかいグリフを角本体に、縁に沿った widgetLabel に読了ゲージ(曲線ゲージ)を出す。
    // 進捗が無ければ widgetLabel は小説名(未選択ならアプリ名)にフォールバック
    @ViewBuilder
    private var corner: some View {
        if let reading = reading, reading.chapterCount > 0 {
            BrandGlyph()
                .padding(2)
                .widgetLabel {
                    Gauge(value: reading.overallProgress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
        } else if let reading = reading {
            BrandGlyph().padding(2).widgetLabel { Text(reading.title) }
        } else {
            BrandGlyph().padding(2).widgetLabel { Text(NSLocalizedString("Watch_Widget_AppName", comment: "ことせかい")) }
        }
    }

    // 長方形: [アイコン]タイトル + 「章/総章 章タイトル(あれば)」 + ゲージバー。
    // 表示領域が広いので識別用にアプリアイコン(グリフ)を先頭に出す
    @ViewBuilder
    private var rectangular: some View {
        if let reading = reading {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    BrandGlyph().frame(width: 14, height: 14)
                    Text(reading.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(reading.rectangularDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if reading.chapterCount > 0 {
                    Gauge(value: reading.overallProgress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                BrandGlyph().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString("Watch_Widget_AppName", comment: "ことせかい")).font(.headline)
                    Text(NSLocalizedString("Watch_Widget_TapToOpen", comment: "タップして開く")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct LauncherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.watchkitapp.launcher",
                            provider: LauncherProvider()) { entry in
            LauncherComplicationView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Watch_Widget_Launcher_Name", comment: "Watchアプリの起動"))
        .description(NSLocalizedString("Watch_Widget_Description", comment: "読んでいる小説の進捗を表示し、タップで ことせかい を開きます。"))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}

// Xcode のキャンバス(Editor → Canvas)で、実機のキャッシュに関係なく本物の描画を確認できる。
// data あり/なしの両方を見られるようにサンプルデータを入れておく
private let sampleReading: WatchComplicationData = {
    var d = WatchComplicationData()
    d.novelID = "sample"
    d.title = "転生したらスライムだった件"
    d.chapterSubtitle = "第三章 · 嵐の予感"
    d.chapterNumber = 12
    d.chapterCount = 240
    d.progressInChapter = 0.4
    return d
}()

#Preview("Circular", as: .accessoryCircular) {
    LauncherComplication()
} timeline: {
    ComplicationEntry(date: .now, data: sampleReading)
    ComplicationEntry(date: .now, data: nil)
}

#Preview("Corner", as: .accessoryCorner) {
    LauncherComplication()
} timeline: {
    ComplicationEntry(date: .now, data: sampleReading)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LauncherComplication()
} timeline: {
    ComplicationEntry(date: .now, data: sampleReading)
    ComplicationEntry(date: .now, data: nil)
}
