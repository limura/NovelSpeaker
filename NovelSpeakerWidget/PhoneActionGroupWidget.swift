//
//  PhoneActionGroupWidget.swift
//  NovelSpeakerWidgetExtension
//
//  ホーム画面の systemSmall(2x2 アイコン分)に4つの操作をまとめて置くウィジェット。
//  Watch 版の AccessoryWidgetGroup(アクション3枠)に相当する。
//  iOS のホーム画面ウィジェットは最小でもアイコン4つ分を占有するので、
//  「1つの操作に4つ分は大きい」という時にこれで密度を上げる。
//
//  枠の構成は固定: [再生・停止] [アプリの起動] / [小説1を再生] [小説2を再生]。
//  Watch 版で「枠ごとの操作選択+小説選択」の設定 UI が混乱した教訓から、
//  設定は「小説1」「小説2」の2つだけにしている(iOS の操作は3種しか無いので
//  固定構成でもほぼ全ての組み合わせを賄える)。
//  各枠は Button(intent:) なので、アプリの起動以外はアプリを開かずその場で動く。
//

import WidgetKit
import SwiftUI
import AppIntents

struct PhoneActionGroupConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "操作をまとめて配置"
    static var description = IntentDescription("再生・停止、アプリの起動、小説2冊の再生開始を1つのウィジェットに並べます。")

    @Parameter(title: "小説1")
    var novel1: PhonePlayNovelChoice?

    @Parameter(title: "小説1のアイコン", default: .play)
    var icon1: PhonePlayNovelWidgetIcon

    @Parameter(title: "小説1の色", default: .blue)
    var color1: PhonePlayNovelWidgetColor

    @Parameter(title: "小説2")
    var novel2: PhonePlayNovelChoice?

    @Parameter(title: "小説2のアイコン", default: .play)
    var icon2: PhonePlayNovelWidgetIcon

    @Parameter(title: "小説2の色", default: .green)
    var color2: PhonePlayNovelWidgetColor
}

struct PhoneActionGroupSlot {
    let novelID: String?
    let title: String?
    let iconSystemName: String
    let tint: Color
}

struct PhoneActionGroupEntry: TimelineEntry {
    let date: Date
    let slot1: PhoneActionGroupSlot
    let slot2: PhoneActionGroupSlot
    var isPreview: Bool = false
}

struct PhoneActionGroupProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhoneActionGroupEntry {
        PhoneActionGroupEntry(
            date: Date(),
            slot1: PhoneActionGroupSlot(novelID: nil, title: nil, iconSystemName: "play.fill", tint: .blue),
            slot2: PhoneActionGroupSlot(novelID: nil, title: nil, iconSystemName: "play.fill", tint: .green),
            isPreview: true)
    }

    func snapshot(for configuration: PhoneActionGroupConfigurationIntent, in context: Context) async -> PhoneActionGroupEntry {
        return entry(for: configuration, isPreview: context.isPreview)
    }

    func timeline(for configuration: PhoneActionGroupConfigurationIntent, in context: Context) async -> Timeline<PhoneActionGroupEntry> {
        return Timeline(entries: [entry(for: configuration, isPreview: false)], policy: .never)
    }

    private func entry(for configuration: PhoneActionGroupConfigurationIntent, isPreview: Bool) -> PhoneActionGroupEntry {
        // タイトルは共有ストアの最新値を優先(タイトル変更に追従させる)
        func slot(novel: PhonePlayNovelChoice?, icon: PhonePlayNovelWidgetIcon, color: PhonePlayNovelWidgetColor) -> PhoneActionGroupSlot {
            let summary = novel.flatMap { PhoneWidgetDataStore.summary(novelID: $0.id) }
            return PhoneActionGroupSlot(
                novelID: novel?.id,
                title: summary?.title ?? novel?.title,
                iconSystemName: icon.systemName,
                tint: color.color)
        }
        return PhoneActionGroupEntry(
            date: Date(),
            slot1: slot(novel: configuration.novel1, icon: configuration.icon1, color: configuration.color1),
            slot2: slot(novel: configuration.novel2, icon: configuration.icon2, color: configuration.color2),
            isPreview: isPreview)
    }
}

struct PhoneActionGroupWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    let entry: PhoneActionGroupEntry

    private var appName: String { NSLocalizedString("Phone_Widget_AppName", comment: "ことせかい") }

    private var whiteFG: Bool { PhoneWidgetTheme.usesWhiteForeground(renderingMode: renderingMode, colorScheme: colorScheme) }
    private var subtleStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // 再生・停止
                cell(caption: NSLocalizedString("Phone_Widget_PlayToggle_Short", comment: "再生・停止")) {
                    Button(intent: PhoneSpeechToggleIntent()) {
                        PhoneActionGlyphView(badgeSystemName: "playpause.fill", badgeColor: .orange, brandStyle: whiteFG)
                    }
                    .buttonStyle(.plain)
                }
                // アプリの起動
                cell(caption: appName) {
                    Button(intent: PhoneOpenAppIntent()) {
                        PhoneBrandGlyph(forceTemplate: whiteFG)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                novelSlot(entry.slot1)
                novelSlot(entry.slot2)
            }
        }
        .phoneWidgetContainerBackground()
    }

    // アイコン+小さいラベルの1枠。ラベルは見切れてもよいので小説名を出す
    @ViewBuilder
    private func cell(caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 2) {
            content()
                .frame(width: 42, height: 42)
            Text(caption)
                .font(.system(size: 9))
                .lineLimit(1)
                .foregroundStyle(subtleStyle)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func novelSlot(_ slot: PhoneActionGroupSlot) -> some View {
        if let novelID = slot.novelID {
            cell(caption: slot.title ?? "") {
                Button(intent: PhonePlayNovelIntent(novelID: novelID)) {
                    PhoneActionGlyphView(badgeSystemName: slot.iconSystemName, badgeColor: slot.tint, brandStyle: whiteFG)
                }
                .buttonStyle(.plain)
            }
        } else {
            // 未選択。タップはボタンにせず通常のアプリ起動にしておく
            // (ギャラリーのプレビューでは機能の見本として選択アイコンを出す)
            cell(caption: NSLocalizedString("Phone_Widget_PlayNovel_Unset", comment: "小説を選択")) {
                PhoneActionGlyphView(badgeSystemName: entry.isPreview ? slot.iconSystemName : "gearshape.fill", badgeColor: slot.tint, brandStyle: whiteFG)
            }
        }
    }
}

struct PhoneActionGroupWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "com.limuraproducts.novelspeaker.widget.actionGroup",
                               intent: PhoneActionGroupConfigurationIntent.self,
                               provider: PhoneActionGroupProvider()) { entry in
            PhoneActionGroupWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Phone_Widget_ActionGroup_Name", comment: "操作をまとめて配置"))
        .description(NSLocalizedString("Phone_Widget_ActionGroup_Desc", comment: "再生・停止、アプリの起動、選んだ小説2冊の再生開始を1つのウィジェットに並べます。"))
        .supportedFamilies([.systemSmall])
    }
}
