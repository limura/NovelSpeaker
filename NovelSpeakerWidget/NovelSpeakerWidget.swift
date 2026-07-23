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
        PhoneLauncherWidget()
        PhonePlayToggleWidget()
        PhonePlayNovelWidget()
        PhoneActionGroupWidget()
        // ControlWidget(コントロールセンター+ロック画面下部の角スロット)は iOS 18+
        if #available(iOSApplicationExtension 18.0, *) {
            PhonePlayToggleControl()
            PhoneLauncherControl()
            PhonePlayNovelControl()
        }
    }
}

/// コントロールセンター/ロック画面下部の角に置ける「アプリの起動」ボタン(iOS 18+)。
/// ロック画面下部の角スロットには ControlWidget しか置けないため、
/// ウィジェット版ランチャーとは別にこれを用意する
@available(iOSApplicationExtension 18.0, *)
struct PhoneLauncherControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // kind とシンボル名は v1(...control.launcher / LauncherSymbol)から改名している。
        // iOS がコントロールの見た目とシンボルを登録キー・アセット名でキャッシュするらしく、
        // 同名のまま中身を差し替えても端末側で反映されなかったため(再起動でも消えない。2026-07 実機)。
        // "2" はコントロール一覧の絵を作り直させるための世代バンプ(playToggle2 のコメント参照)
        StaticControlConfiguration(kind: "com.limuraproducts.novelspeaker.widget.control.openApp2") {
            ControlWidgetButton(action: PhoneOpenAppIntent()) {
                Label {
                    Text("アプリの起動")
                } icon: {
                    // コントロールのアイコンは SF Symbol しか描画されない(PNG は「？」になる)ため、
                    // 元 SVG から起こしたカスタムシンボルを使う。
                    // シンボルは端末側でアセット名キャッシュされるため、形を変えるたびに名前を
                    // バンプする(現行: NovelSpeakerGlyph3 = path単位の向き正規化+1.42倍)
                    Image("NovelSpeakerGlyph3")
                }
            }
        }
        .displayName("アプリの起動")
        .description("ことせかい を開きます。")
    }
}

/// ブランドのグリフ。フルカラー(ホーム画面等)ではアプリアイコン(橙背景+白グリフ)を
/// 円形にして出し、単色系(ロック画面の accented 等)では透過テンプレートの白グリフを出す
/// (Watch 版 BrandGlyph と同じ出し分け)
struct PhoneBrandGlyph: View {
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

/// ことせかいグリフ+機能アイコンの合成(Watch 版 ActionGlyphView の iOS 版。corner が無いぶん単純)。
/// ベースを左上に寄せ、バッジと重なる部分はくり抜いて、バッジが読めるようにする
struct PhoneActionGlyphView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let badgeSystemName: String
    var badgeColor: Color = .orange

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                PhoneBrandGlyph()
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

    // 機能アイコン。フルカラー: 地の丸=選択色×白記号。
    // 単色系(ロック画面の accented 等): iOS ではアクセントグループの塗り分けをしても
    // 全部白に潰れて「白い丸」になる(実機で確認。watchOS の corner と同じ現象)ので、
    // watch 版 corner と同じ「白リング+白記号」にして、暗い背景を地として読ませる
    @ViewBuilder
    private func badge(side: CGFloat) -> some View {
        ZStack {
            if renderingMode == .fullColor {
                Circle().fill(badgeColor)
            } else {
                Circle().stroke(.white, lineWidth: max(1, side * 0.035))
            }
            Image(systemName: badgeSystemName)
                .font(.system(size: side * 0.30, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: side * 0.48, height: side * 0.48)
    }
}

// MARK: - アプリの起動(ランチャー)

struct PhoneLauncherEntry: TimelineEntry {
    let date: Date
    let state: PhoneWidgetReadingState?
}

struct PhoneLauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhoneLauncherEntry {
        PhoneLauncherEntry(date: Date(), state: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (PhoneLauncherEntry) -> Void) {
        completion(PhoneLauncherEntry(date: Date(), state: PhoneWidgetDataStore.loadReadingState()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneLauncherEntry>) -> Void) {
        // 更新はアプリ側の WidgetCenter.reloadAllTimelines で駆動するので、固定1エントリ・自動更新なし
        completion(Timeline(entries: [PhoneLauncherEntry(date: Date(), state: PhoneWidgetDataStore.loadReadingState())], policy: .never))
    }
}

/// 「アプリの起動」。今読んでいる小説と進捗を表示し、タップで ことせかい を開く
/// (intent を持たないのでタップは普通にアプリ起動になる)
struct PhoneLauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.widget.launcher", provider: PhoneLauncherProvider()) { entry in
            PhoneLauncherWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Phone_Widget_Launcher_Name", comment: "アプリの起動"))
        .description(NSLocalizedString("Phone_Widget_Launcher_Desc", comment: "読んでいる小説の進捗を表示し、タップで ことせかい を開きます。"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct PhoneLauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhoneLauncherEntry

    private var reading: PhoneWidgetReadingState? {
        guard let state = entry.state, state.chapterCount > 0 else { return nil }
        return state
    }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            // 円形: 読了ゲージのリング + 中央にグリフ(Watch 版 circular と同じ見た目)
            if let reading = reading {
                ZStack {
                    Circle().stroke(.tertiary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.01, reading.overallProgress))
                        .stroke(.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    PhoneBrandGlyph().padding(7)
                }
                .padding(1)
            } else {
                PhoneBrandGlyph().padding(2)
            }
        case .accessoryRectangular:
            // 横長: 小説名 + 章/総章 + ゲージバー
            if let reading = reading {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(reading.chapterFraction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Gauge(value: reading.overallProgress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    PhoneBrandGlyph().frame(width: 28, height: 28)
                    Text(NSLocalizedString("Phone_Widget_AppName", comment: "ことせかい"))
                        .font(.headline)
                    Spacer(minLength: 0)
                }
            }
        default:
            // ホーム画面(systemSmall): アイコン + 小説名 + ゲージバー
            VStack(spacing: 8) {
                PhoneBrandGlyph().frame(width: 52, height: 52)
                if let reading = reading {
                    Text(reading.title)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    Gauge(value: reading.overallProgress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(.orange)
                } else {
                    Text(NSLocalizedString("Phone_Widget_AppName", comment: "ことせかい"))
                        .font(.caption)
                }
            }
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
        // どのファミリーも ことせかいグリフ+⏯の合成アイコン(「指定小説の再生を開始」と同じ流儀)
        switch family {
        case .accessoryCircular:
            // ロック画面(円形): 合成アイコンだけ
            PhoneActionGlyphView(badgeSystemName: "playpause.fill")
                .padding(2)
        case .accessoryRectangular:
            // ロック画面(横長): [合成アイコン] アプリ名 + 操作名
            HStack(spacing: 8) {
                PhoneActionGlyphView(badgeSystemName: "playpause.fill")
                    .frame(width: 30, height: 30)
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
            // ホーム画面(systemSmall): 合成アイコン + 操作名
            VStack(spacing: 8) {
                PhoneActionGlyphView(badgeSystemName: "playpause.fill")
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
        // kind の "2" は世代番号。コントロール一覧(カスタマイズUI)の絵は
        // 「kind が初めて登場した時」に一度だけ描画され、以後は再インストールや
        // 再起動でも更新されない(実機確認)ため、アイコンを変えたら kind をバンプする
        StaticControlConfiguration(kind: "com.limuraproducts.novelspeaker.widget.control.playToggle2") {
            ControlWidgetButton(action: PhoneSpeechToggleIntent()) {
                Label {
                    Text("再生または停止")
                } icon: {
                    // ことせかいグリフ+⏯の合成をカスタムシンボルとして生成したもの
                    // (くり抜きは SF Symbol の消去レイヤーで実現)
                    Image("NovelSpeakerGlyphPlayPause2")
                }
            }
        }
        .displayName("再生または停止")
        .description("ことせかい を開かずに、読み上げの再生・停止をします。")
    }
}
