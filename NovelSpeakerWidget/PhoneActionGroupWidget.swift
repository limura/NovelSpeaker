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

    @Parameter(title: "小説2")
    var novel2: PhonePlayNovelChoice?
}

struct PhoneActionGroupEntry: TimelineEntry {
    let date: Date
    let novel1ID: String?
    let novel1Title: String?
    let novel2ID: String?
    let novel2Title: String?
    var isPreview: Bool = false
}

struct PhoneActionGroupProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PhoneActionGroupEntry {
        PhoneActionGroupEntry(date: Date(), novel1ID: nil, novel1Title: nil, novel2ID: nil, novel2Title: nil, isPreview: true)
    }

    func snapshot(for configuration: PhoneActionGroupConfigurationIntent, in context: Context) async -> PhoneActionGroupEntry {
        return entry(for: configuration, isPreview: context.isPreview)
    }

    func timeline(for configuration: PhoneActionGroupConfigurationIntent, in context: Context) async -> Timeline<PhoneActionGroupEntry> {
        return Timeline(entries: [entry(for: configuration, isPreview: false)], policy: .never)
    }

    private func entry(for configuration: PhoneActionGroupConfigurationIntent, isPreview: Bool) -> PhoneActionGroupEntry {
        PhoneActionGroupEntry(
            date: Date(),
            novel1ID: configuration.novel1?.id,
            novel1Title: configuration.novel1?.title,
            novel2ID: configuration.novel2?.id,
            novel2Title: configuration.novel2?.title,
            isPreview: isPreview)
    }
}

struct PhoneActionGroupWidgetView: View {
    let entry: PhoneActionGroupEntry

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // 再生・停止
                Button(intent: PhoneSpeechToggleIntent()) {
                    PhoneActionGlyphView(badgeSystemName: "playpause.fill", badgeColor: .orange)
                }
                .buttonStyle(.plain)
                // アプリの起動
                Button(intent: PhoneOpenAppIntent()) {
                    PhoneBrandGlyph()
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                // 小説1・小説2(色で区別する。未選択の間は歯車で「要設定」を示す)
                novelSlot(novelID: entry.novel1ID, title: entry.novel1Title, tint: .blue)
                novelSlot(novelID: entry.novel2ID, title: entry.novel2Title, tint: .green)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func novelSlot(novelID: String?, title: String?, tint: Color) -> some View {
        if let novelID = novelID {
            Button(intent: PhonePlayNovelIntent(novelID: novelID)) {
                PhoneActionGlyphView(badgeSystemName: "play.fill", badgeColor: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title ?? "")
        } else {
            // 未選択。タップはボタンにせず通常のアプリ起動にしておく
            // (ギャラリーのプレビューでは機能の見本として再生アイコンを出す)
            PhoneActionGlyphView(badgeSystemName: entry.isPreview ? "play.fill" : "gearshape.fill", badgeColor: tint)
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
