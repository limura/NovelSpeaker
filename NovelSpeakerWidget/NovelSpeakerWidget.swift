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

/// テーマカラー背景の試作フラグ(第9弾)。
/// true にすると、ホーム画面ウィジェット(フルカラー表示時)の背景をアプリアイコンと同じ
/// 橙→赤のグラデーションにし、前景(グリフ・文字・ゲージ)を白系に切り替える。
/// 見た目の判断用に1行で戻せるよう、分岐は全てこのフラグを参照する。
/// なお iOS 18 のティント(色合い調整)モードでは背景はシステムが暗い素材に
/// 置き換えるため、この背景が見えるのは通常モードのみ
enum PhoneWidgetTheme {
    static let brandBackgroundEnabled = true

    /// ライトテーマ: アプリアイコンの橙→赤を白側に寄せた淡いグラデーション。
    /// (アイコンの絵は白い部分の面積が大きく全体は白っぽく見えるので、
    /// 背景全面に元の色を敷くと濃く見えすぎる、という実機フィードバックによる)
    /// 淡い背景に白文字は読めないので、ライト時の前景は通常の黒系のまま使う
    static let gradientTop = Color(red: 254 / 255, green: 219 / 255, blue: 166 / 255)
    static let gradientBottom = Color(red: 254 / 255, green: 164 / 255, blue: 151 / 255)
    /// ダークテーマ: アイコンの色を暗く沈めたもの(前景は白系)
    static let gradientTopDark = Color(red: 118 / 255, green: 78 / 255, blue: 28 / 255)
    static let gradientBottomDark = Color(red: 116 / 255, green: 22 / 255, blue: 15 / 255)

    /// 前景を白系(白グリフ・白文字)に切り替えるか。
    /// テーマカラー背景が濃いのはダークテーマの時だけなので、ライトは通常の前景のまま
    static func usesWhiteForeground(renderingMode: WidgetRenderingMode, colorScheme: ColorScheme) -> Bool {
        return brandBackgroundEnabled && renderingMode == .fullColor && colorScheme == .dark
    }

}

/// ホーム画面ウィジェット共通の containerBackground。
/// テーマカラー背景が有効かつフルカラー表示の時だけグラデーションを敷く
/// (ロック画面等の単色系は renderingMode が accented/vibrant なので対象外)
private struct PhoneWidgetContainerBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if PhoneWidgetTheme.brandBackgroundEnabled && renderingMode == .fullColor {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [PhoneWidgetTheme.gradientTopDark, PhoneWidgetTheme.gradientBottomDark]
                        : [PhoneWidgetTheme.gradientTop, PhoneWidgetTheme.gradientBottom],
                    startPoint: .top, endPoint: .bottom)
            } else {
                Color.clear
            }
        }
    }
}

extension View {
    func phoneWidgetContainerBackground() -> some View { modifier(PhoneWidgetContainerBackground()) }
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
        StaticControlConfiguration(kind: "com.limuraproducts.novelspeaker.widget.control.openApp3") {
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
    /// テーマカラー背景の上ではアイコン円盤(橙背景)が背景に溶けるので、
    /// フルカラーでも白のテンプレートグリフを使う
    var forceTemplate: Bool = false

    var body: some View {
        if renderingMode == .fullColor && !forceTemplate {
            Image("LauncherIconColor")
                .resizable()
                .scaledToFit()
                .clipShape(Circle())
        } else if renderingMode == .fullColor {
            Image("LauncherGlyph")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
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
    /// 濃いテーマカラー背景(ダーク)の上に置く時 true。グリフを白テンプレートにする
    /// (橙円盤だと背景に溶けるため)。バッジは常に色付き丸+白記号
    /// (当初はダーク時に白丸+色記号にしたが、「色が抜けて見える」との実機
    /// フィードバックで、ライトと同じ塗りつぶしに統一した)
    var brandStyle: Bool = false

    // ⏯は他の記号より横に広く、0.30倍だとバッジの円をはみ出すのでこの記号だけ小さく描く
    private var badgeFontScale: CGFloat { badgeSystemName == "playpause.fill" ? 0.24 : 0.30 }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                PhoneBrandGlyph(forceTemplate: brandStyle)
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
                .font(.system(size: side * badgeFontScale, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: side * 0.48, height: side * 0.48)
    }
}

// MARK: - アプリの起動(ランチャー)

struct PhoneLauncherEntry: TimelineEntry {
    let date: Date
    let state: PhoneWidgetReadingState?
    var stats: PhoneWidgetBookshelfStats? = nil
}

struct PhoneLauncherProvider: TimelineProvider {
    private func currentEntry() -> PhoneLauncherEntry {
        PhoneLauncherEntry(date: Date(),
                           state: PhoneWidgetDataStore.loadReadingState(),
                           stats: PhoneWidgetDataStore.loadBookshelfStats())
    }
    func placeholder(in context: Context) -> PhoneLauncherEntry {
        PhoneLauncherEntry(date: Date(), state: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (PhoneLauncherEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PhoneLauncherEntry>) -> Void) {
        // 更新はアプリ側の WidgetCenter.reloadAllTimelines で駆動するので、固定1エントリ・自動更新なし
        completion(Timeline(entries: [currentEntry()], policy: .never))
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
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    let entry: PhoneLauncherEntry

    private var reading: PhoneWidgetReadingState? {
        guard let state = entry.state, state.chapterCount > 0 else { return nil }
        return state
    }

    // 濃いテーマカラー背景(ダーク)の上に描いているか。ライトの淡い背景では通常の前景を使う
    private var whiteFG: Bool { PhoneWidgetTheme.usesWhiteForeground(renderingMode: renderingMode, colorScheme: colorScheme) }
    private var primaryStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white) : AnyShapeStyle(.primary) }
    private var subtleStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary) }

    var body: some View {
        content
            .phoneWidgetContainerBackground()
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
            // ホーム画面(systemSmall): アイコン + 小説名 + ゲージバー + 本棚統計 + 「アプリを開く」。
            // アイコンタップと違って「開いた後に見えるもの」が先に見えているのが存在価値なので、
            // 空きスペースには本棚の統計を出し、末尾に開く動作であることを明示する
            VStack(spacing: 5) {
                PhoneBrandGlyph(forceTemplate: whiteFG).frame(width: 40, height: 40)
                if let reading = reading {
                    Text(reading.title)
                        .font(.caption)
                        .foregroundStyle(primaryStyle)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    Gauge(value: reading.overallProgress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(whiteFG ? .white : .orange)
                } else {
                    Text(NSLocalizedString("Phone_Widget_AppName", comment: "ことせかい"))
                        .font(.caption)
                        .foregroundStyle(primaryStyle)
                }
                Spacer(minLength: 0)
                if let stats = entry.stats {
                    Text(String(format: NSLocalizedString("Phone_Widget_Launcher_Stats_Format", comment: "本棚 %1$d冊・更新あり %2$d冊"), stats.novelCount, stats.newArrivalCount))
                        .font(.caption2)
                        .foregroundStyle(subtleStyle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(spacing: 3) {
                    Text(NSLocalizedString("Phone_Widget_Launcher_OpenApp", comment: "アプリを開く"))
                    Image(systemName: "arrow.up.forward.app")
                        .accessibilityHidden(true) // 隣の文字と同じ事しか言わない飾り
                }
                .font(.caption2)
                .foregroundStyle(subtleStyle)
            }
        }
    }
}

/// 「再生・停止」(ホーム画面 systemSmall + ロック画面 accessoryCircular/Rectangular)。
/// ボタン全面が intent なので、タップしてもアプリは開かない。
/// 「何が再生・停止されるのか」が見えるよう、対象の小説(=今読んでいる小説)を
/// ランチャーと同じ共有ストア経由で表示する
struct PhonePlayToggleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.limuraproducts.novelspeaker.widget.playToggle", provider: PhoneLauncherProvider()) { entry in
            PhonePlayToggleWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("Phone_Widget_PlayToggle_Name", comment: "再生または停止"))
        .description(NSLocalizedString("Phone_Widget_PlayToggle_Desc", comment: "ことせかい を開かずに、読み上げの再生・停止をします。"))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct PhonePlayToggleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    let entry: PhoneLauncherEntry

    private var reading: PhoneWidgetReadingState? {
        guard let state = entry.state, state.chapterCount > 0 else { return nil }
        return state
    }

    private var whiteFG: Bool { PhoneWidgetTheme.usesWhiteForeground(renderingMode: renderingMode, colorScheme: colorScheme) }
    private var primaryStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white) : AnyShapeStyle(.primary) }
    private var subtleStyle: AnyShapeStyle { whiteFG ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary) }

    var body: some View {
        Button(intent: PhoneSpeechToggleIntent()) {
            content
        }
        .buttonStyle(.plain)
        .phoneWidgetContainerBackground()
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
            // ロック画面(横長): [合成アイコン] 対象の小説名(無ければアプリ名) + 操作名
            HStack(spacing: 8) {
                PhoneActionGlyphView(badgeSystemName: "playpause.fill")
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading?.title ?? NSLocalizedString("Phone_Widget_AppName", comment: "ことせかい"))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(NSLocalizedString("Phone_Widget_PlayToggle_Short", comment: "再生・停止"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        default:
            // ホーム画面(systemSmall): 合成アイコン + 対象の小説名 + ゲージ + 操作名
            VStack(spacing: 5) {
                PhoneActionGlyphView(badgeSystemName: "playpause.fill", brandStyle: whiteFG)
                    .frame(width: 46, height: 46)
                if let reading = reading {
                    Text(reading.title)
                        .font(.caption)
                        .foregroundStyle(primaryStyle)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    Gauge(value: reading.overallProgress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(whiteFG ? .white : .orange)
                    Spacer(minLength: 0)
                }
                Text(NSLocalizedString("Phone_Widget_PlayToggle_Short", comment: "再生・停止"))
                    .font(.caption2)
                    .foregroundStyle(subtleStyle)
            }
        }
    }
}

/// コントロールセンター(iOS 18+)の「再生・停止」ボタン
@available(iOSApplicationExtension 18.0, *)
struct PhonePlayToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        // kind の数字は世代番号。コントロール一覧(カスタマイズUI)の絵は
        // 「kind が初めて登場した時」に一度だけ描画され、以後は再インストールや
        // 再起動でも更新されない(実機確認)ため、アイコンを変えたら kind をバンプする。
        // 世代4 = ⏯バッジを0.8倍に縮小(円からのはみ出し対策)
        StaticControlConfiguration(kind: "com.limuraproducts.novelspeaker.widget.control.playToggle4") {
            ControlWidgetButton(action: PhoneSpeechToggleIntent()) {
                Label {
                    Text("再生または停止")
                } icon: {
                    // ことせかいグリフ+⏯の合成をカスタムシンボルとして生成したもの
                    // (くり抜きは SF Symbol の消去レイヤーで実現)
                    Image("NovelSpeakerGlyphPlayPause4")
                }
            }
        }
        .displayName("再生または停止")
        .description("ことせかい を開かずに、読み上げの再生・停止をします。")
    }
}
