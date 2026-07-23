//
//  NovelSpeakerWidget.swift
//  NovelSpeakerWidgetExtension
//
//  iPhone側のウィジェット(ホーム画面/ロック画面/コントロールセンター)。
//  「再生・停止」は AudioPlaybackIntent 経由でアプリ本体プロセスの StorySpeaker を叩くので、
//  アプリを開かずにその場で再生・停止できる(PoC/WidgetSpeechPoC で実機実証済み)。
//

import WidgetKit
import SwiftUI
import AppIntents

@main
struct NovelSpeakerPhoneWidgetBundle: WidgetBundle {
    var body: some Widget {
        PhonePlayToggleWidget()
        // コントロールセンターの ControlWidget は iOS 18+
        if #available(iOSApplicationExtension 18.0, *) {
            PhonePlayToggleControl()
        }
    }
}

struct PhoneWidgetEntry: TimelineEntry {
    let date: Date
}

/// 表示は静的(再生中かどうかは表示しない)なので、固定1エントリ・自動更新なし
struct PhoneWidgetStaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhoneWidgetEntry { PhoneWidgetEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (PhoneWidgetEntry) -> Void) {
        completion(PhoneWidgetEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneWidgetEntry>) -> Void) {
        completion(Timeline(entries: [PhoneWidgetEntry(date: Date())], policy: .never))
    }
}

/// 「再生・停止」(ホーム画面 systemSmall + ロック画面 accessoryCircular/Rectangular)。
/// ボタン全面が intent なので、タップしてもアプリは開かない
struct PhonePlayToggleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.widget.playToggle", provider: PhoneWidgetStaticProvider()) { _ in
            PhonePlayToggleWidgetView()
        }
        .configurationDisplayName(NSLocalizedString("Phone_Widget_PlayToggle_Name", comment: "再生または停止"))
        .description(NSLocalizedString("Phone_Widget_PlayToggle_Desc", comment: "ことせかい を開かずに、読み上げの再生・停止をします。"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct PhonePlayToggleWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Button(intent: PhoneSpeechToggleIntent()) {
            content
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            // ロック画面(円形): 記号だけ
            ZStack {
                Circle().fill(.quaternary)
                Image(systemName: "playpause.fill")
                    .font(.title3)
            }
        case .accessoryRectangular:
            // ロック画面(横長): アプリ名 + 操作名
            HStack(spacing: 8) {
                Image(systemName: "playpause.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Phone_Widget_AppName", comment: "ことせかい"))
                        .font(.headline)
                    Text(NSLocalizedString("Phone_Widget_PlayToggle_Short", comment: "再生・停止"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            // ホーム画面(systemSmall): 橙の円 + 白の再生・停止記号(Watch の操作系と同じ配色)
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.orange)
                    Image(systemName: "playpause.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                Text(NSLocalizedString("Phone_Widget_PlayToggle_Short", comment: "再生・停止"))
                    .font(.caption)
            }
        }
    }
}

/// コントロールセンター(iOS 18+)の「再生・停止」ボタン
@available(iOSApplicationExtension 18.0, *)
struct PhonePlayToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.limuraproducts.novelspeaker.widget.control.playToggle") {
            ControlWidgetButton(action: PhoneSpeechToggleIntent()) {
                Label {
                    Text("再生または停止")
                } icon: {
                    Image(systemName: "playpause.fill")
                }
            }
        }
        .displayName("再生または停止")
        .description("ことせかい を開かずに、読み上げの再生・停止をします。")
    }
}
