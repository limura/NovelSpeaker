//
//  TextPageView.swift
//  NovelSpeakerWatch
//
//  ②本文ページ。転送済み本文の現在章を表示し、読み上げ位置に連動する。
//  - 発話ブロック(CombinedSpeechBlock)粒度のハイライト + 自動スクロール
//    - Watch 単体再生時: WatchSpeechPlayer のブロック境界イベント(ローカル)
//    - iPhone 再生時: 本文ページ表示中のみ購読(subscribeSpeechBlock)して 2秒毎の位置プッシュを受ける
//  - 自動スクロールはブロックが変わる毎に発火。scrollTo は「段落ビューの UnitPoint を画面の同じ
//    UnitPoint に揃える」仕様しかない(文字単位のスクロールAPIが無い)ので、ハイライト中の段落の
//    高さを実測し、段落内の文字位置の割合からアンカーを逆算して「ハイライト行が画面の40%の高さに
//    来る」ように寄せる(画面より背の高い段落でも読んでいる行が画面内に収まる)
//  - 「手動スクロールで自動追従を一時解除」は検知が実質機能していなかったため撤去した(2026-07-14)。
//    再生中の手動スクロールは次のブロック境界で読み上げ位置へ引き戻される
//  - 段落の長押しで読み上げ位置を指定(ハプティクスで応答。タップ+確認は試用の結果廃止)
//  - 本文の先頭/末尾に前後の章への移動ボタン
//
//  ナビゲーションバーのタイトルには小説名を出す(スクロール時に上段へ小さく残るのは小説名だけ)。
//  章タイトルと章番号は本文と一緒にスクロールで流れる。
//

import SwiftUI
import WatchKit

struct TextPageView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @ObservedObject private var player = WatchSpeechPlayer.shared
    @StateObject private var model = TextPageModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSettingsPresented = false
    /// ツールバー(ScrollViewReader の外)から「一番上へ」スクロールするための橋渡し
    @State private var scrollProxy: ScrollViewProxy?

    @AppStorage(TextDisplayDefaults.fontSizeKey) private var fontSize: Double = 14
    @AppStorage(TextDisplayDefaults.textColorKey) private var textColorName: String = "white"
    @AppStorage(TextDisplayDefaults.backgroundColorKey) private var backgroundColorName: String = "black"

    /// ハイライト行を画面のどの高さに寄せるか(0=最上部, 1=最下部)。
    /// 上部はナビゲーションバーに隠れるので中央よりやや上の 0.4 にする
    private static let scrollTargetHeightFraction = 0.4

    /// 「一番上へ」ボタンのスクロール先の id
    private static let topAnchorID = "TextPageTopAnchor"

    /// 表示対象の小説と章。Watch 単体再生が発話元ならそちらを、そうでなければ iPhone の状態を表示する
    private var displayTarget: (novelID: String, title: String, chapter: Int)? {
        if player.isSelectedAsSource && !player.novelID.isEmpty {
            return (player.novelID, player.title, player.chapterNumber)
        }
        if let state = session.playState, !state.novelID.isEmpty {
            return (state.novelID, state.title, state.chapterNumber)
        }
        return nil
    }

    /// 表示対象の変化検知用(章移動・発話元切替で本文を差し替える)
    private var targetKey: String {
        guard let target = displayTarget else { return "" }
        return "\(target.novelID)#\(target.chapter)#\(player.isSelectedAsSource)"
    }

    private var isPlayingNow: Bool {
        if player.isSelectedAsSource { return player.isPlaying }
        return session.playState?.isPlaying == true
    }

    /// 現在の読み上げ位置(表示中の章の unicodeScalar オフセット)。章が違うなら nil
    private var highlightLocation: Int? {
        guard let target = displayTarget, model.hasChapter else { return nil }
        if player.isSelectedAsSource {
            guard player.novelID == target.novelID, player.chapterNumber == target.chapter else { return nil }
            return player.speakingLocation
        }
        if let point = session.phoneReadingPoint,
           point.novelID == target.novelID, point.chapter == target.chapter {
            return point.location
        }
        // 購読の初回プッシュがまだ届いていない間は playState の進捗(0.0-1.0)から概算する
        if let state = session.playState,
           state.novelID == target.novelID, state.chapterNumber == target.chapter,
           model.contentScalarCount > 0 {
            return min(Int(state.progress * Double(model.contentScalarCount)), model.contentScalarCount - 1)
        }
        return nil
    }

    /// ハイライトする発話ブロックの表示文字範囲
    private var highlightScalarRange: Range<Int>? {
        guard let location = highlightLocation else { return nil }
        return model.blockRange(containing: location)
    }

    var body: some View {
        let textColor = TextDisplayDefaults.textColor(named: textColorName)
        let highlightColor = TextDisplayDefaults.highlightColor(backgroundName: backgroundColorName)
        let highlight = highlightScalarRange
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        // 「一番上へ」ボタンのスクロール先(高さ0の目印)
                        Color.clear
                            .frame(height: 0)
                            .id(Self.topAnchorID)
                        contentBody(textColor: textColor, highlightColor: highlightColor, highlight: highlight)
                    }
                    .padding(.horizontal, 2)
                }
                .onPreferenceChange(ParagraphHeightsKey.self) { heights in
                    model.storeParagraphHeights(heights)
                    // 高さ未計測のまま寄せた段落の実測が届いたら、正しい位置に寄せ直す
                    if let pending = model.pendingHeightScrollParagraphID, heights[pending] != nil {
                        model.pendingHeightScrollParagraphID = nil
                        scrollToHighlight(proxy: proxy, viewportHeight: outer.size.height)
                    }
                }
                .onChange(of: highlight?.lowerBound) { _ in
                    // ブロックが変わる毎に発火する(段落単位ではなく)
                    scrollToHighlight(proxy: proxy, viewportHeight: outer.size.height)
                }
                .onChange(of: targetKey) { _ in
                    prepareAndScroll(proxy: proxy, viewportHeight: outer.size.height)
                    updateSubscription()
                }
                .onChange(of: session.storedChapterCounts) { _ in
                    // 本文転送の完了(新規・章の追加)で表示できるようになったら読み直す
                    prepareAndScroll(proxy: proxy, viewportHeight: outer.size.height)
                }
                .onChange(of: fontSize) { _ in
                    // 文字サイズが変わると段落の高さが全部変わる
                    model.clearParagraphHeights()
                }
                .onAppear {
                    scrollProxy = proxy
                    prepareAndScroll(proxy: proxy, viewportHeight: outer.size.height)
                    updateSubscription()
                }
            }
        }
        .background(TextDisplayDefaults.backgroundColor(named: backgroundColorName).ignoresSafeArea())
        .navigationTitle(displayTarget?.title.isEmpty == false ? displayTarget!.title : NSLocalizedString("Watch_TextPage_Title", comment: "本文"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel(NSLocalizedString("Watch_AX_TextSettings", comment: "本文の表示設定"))
            }
            // iPhone 版の本文画面右上の再生ボタンに相当。watchOS は右上を時計が占有するので下端の隅に置く。
            // 左下は「一番上へ」(iPhone の「画面上部タップで先頭へ」に相当。watchOS にはその仕組みが無い)
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button {
                        // 再生中は次のブロック境界で読み上げ位置へ戻る(自動追従の一時解除は撤去済み)
                        scrollProxy?.scrollTo(Self.topAnchorID, anchor: .top)
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                    }
                    .accessibilityLabel(NSLocalizedString("Watch_AX_ScrollToTop", comment: "一番上へ"))
                    Spacer()
                    Button {
                        if player.isSelectedAsSource {
                            player.togglePlayPause()
                        } else {
                            session.send(.togglePlayPause)
                        }
                    } label: {
                        if player.isSelectedAsSource && player.isStartingPlayback {
                            // 単体再生の開始処理中。再生画面のボタンと同じくスピナー表示にする
                            ProgressView()
                        } else {
                            Image(systemName: isPlayingNow ? "pause.fill" : "play.fill")
                        }
                    }
                    .disabled(player.isSelectedAsSource && player.isStartingPlayback)
                    .accessibilityLabel(isPlayingNow
                        ? NSLocalizedString("Watch_AX_Pause", comment: "一時停止")
                        : NSLocalizedString("Watch_AX_Play", comment: "再生"))
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                TextSettingsView()
            }
        }
        .onChange(of: player.isSelectedAsSource) { _ in
            updateSubscription()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                prepareTarget()
                updateSubscription()
            } else {
                session.setReadingPointSubscription(false)
            }
        }
        .onDisappear {
            session.setReadingPointSubscription(false)
        }
    }

    // MARK: - 本文の描画

    @ViewBuilder
    private func contentBody(textColor: Color, highlightColor: Color, highlight: Range<Int>?) -> some View {
        if let target = displayTarget {
            if !session.storedNovelIDs.contains(target.novelID) {
                Text(String(format: NSLocalizedString("Watch_TextPage_NovelNotTransferred", comment: "「%@」の本文はまだWatchに転送されていません。本棚から転送できます。"), target.title))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.hasChapter {
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .font(.system(size: max(fontSize - 2, 10), weight: .semibold))
                        .foregroundStyle(textColor)
                }
                Text(pageLabel(target: target))
                    .font(.system(size: 11))
                    .foregroundStyle(textColor.opacity(0.6))
                if hasPreviousChapter {
                    chapterMoveButton(label: NSLocalizedString("Watch_TextPage_PrevChapter", comment: "◀ 前の章"),
                                      accessibilityLabel: NSLocalizedString("Watch_AX_PrevChapter", comment: "前の章へ"),
                                      offset: -1)
                }
                paragraphList(textColor: textColor, highlightColor: highlightColor, highlight: highlight)
                if hasNextChapter {
                    chapterMoveButton(label: NSLocalizedString("Watch_TextPage_NextChapter", comment: "次の章へ ▶"),
                                      accessibilityLabel: NSLocalizedString("Watch_AX_NextChapter", comment: "次の章へ"),
                                      offset: 1)
                }
            } else {
                Text(String(format: NSLocalizedString("Watch_TextPage_ChapterNotTransferred", comment: "この章(%d章)はまだWatchに転送されていません。本棚から転送し直せます。"), target.chapter))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(NSLocalizedString("Watch_NoNovelSelected", comment: "小説が選ばれていません"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func paragraphList(textColor: Color, highlightColor: Color, highlight: Range<Int>?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.paragraphs) { paragraph in
                let local = localHighlight(paragraph: paragraph, highlight: highlight)
                ParagraphTextView(
                    text: paragraph.text,
                    localHighlight: local,
                    fontSize: fontSize,
                    textColor: textColor,
                    highlightColor: highlightColor
                )
                .equatable()
                .background {
                    // スクロール位置の逆算用に、ハイライト中の段落だけ高さを実測する
                    if local != nil {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ParagraphHeightsKey.self,
                                                   value: [paragraph.id: geometry.size.height])
                        }
                    }
                }
                .id(paragraph.id)
                // watchOS 10 (Series 4 で確認) では段落への onLongPressGesture がスクロールの
                // タッチを食ってしまい、段落上での上下スクロール・左右ページ移動が効かなくなる。
                // 空のタップジェスチャを長押しより先に置くとスクロールが優先される(定番の回避策)
                .onTapGesture {}
                .onLongPressGesture {
                    performSeek(toLocation: paragraph.scalarRange.lowerBound)
                }
                // VoiceOver では長押しジェスチャが使えないので、同じ操作をカスタムアクションで提供する
                .accessibilityAction(named: Text(NSLocalizedString("Watch_AX_SeekHere", comment: "ここから読み上げ"))) {
                    performSeek(toLocation: paragraph.scalarRange.lowerBound)
                }
            }
        }
    }

    /// ハイライト範囲をこの段落内の相対範囲(unicodeScalar)へ変換する。重ならないなら nil
    private func localHighlight(paragraph: TextPageModel.Paragraph, highlight: Range<Int>?) -> Range<Int>? {
        guard let highlight = highlight else { return nil }
        let lower = max(highlight.lowerBound, paragraph.scalarRange.lowerBound)
        let upper = min(highlight.upperBound, paragraph.scalarRange.upperBound)
        guard lower < upper else { return nil }
        return (lower - paragraph.scalarRange.lowerBound)..<(upper - paragraph.scalarRange.lowerBound)
    }

    private func pageLabel(target: (novelID: String, title: String, chapter: Int)) -> String {
        let chapterCount = player.isSelectedAsSource ? player.chapterCount : (session.playState?.chapterCount ?? 0)
        if chapterCount > 0 {
            return "\(target.chapter)/\(chapterCount)"
        }
        return "\(target.chapter)"
    }

    // MARK: - 章移動

    private var hasPreviousChapter: Bool {
        guard let target = displayTarget else { return false }
        if player.isSelectedAsSource { return model.isChapterAvailable(target.chapter - 1) }
        return target.chapter > 1
    }

    private var hasNextChapter: Bool {
        guard let target = displayTarget else { return false }
        if player.isSelectedAsSource { return model.isChapterAvailable(target.chapter + 1) }
        if let count = session.playState?.chapterCount, count > 0 { return target.chapter < count }
        return false
    }

    private func chapterMoveButton(label: String, accessibilityLabel: String, offset: Int) -> some View {
        Button {
            if player.isSelectedAsSource {
                player.moveChapter(offset: offset)
            } else {
                session.send(offset < 0 ? .previousChapter : .nextChapter)
            }
        } label: {
            Text(label)
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
        // VoiceOver では「◀」が「左向き黒三角」と読まれてしまうので、記号抜きのラベルを与える
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - 読み上げ位置の指定(段落の長押し)

    private func performSeek(toLocation location: Int) {
        guard let target = displayTarget else { return }
        if player.isSelectedAsSource {
            player.seek(toLocation: location)
            WKInterfaceDevice.current().play(.click)
            return
        }
        // iPhone が発話元の場合は Watch の栞として送り、iPhone 側の「新しい方優先」で反映してもらう
        // (発話中は iPhone 側が採用しない作りなので、こちらでも弾いて理由を出す)
        if session.playState?.isPlaying == true {
            session.lastErrorMessage = NSLocalizedString("Watch_TextPage_CannotSeekWhilePhonePlaying", comment: "iPhoneで再生中は位置を指定できません。一時停止してからやり直してください。")
            return
        }
        WatchReadingPositionStore.save(novelID: target.novelID, chapter: target.chapter, location: location)
        session.pushWatchContext()
        // ハイライトの表示もすぐ追従させる(iPhone からの再送を待たない)
        session.phoneReadingPoint = PhoneSessionManager.PhoneReadingPoint(
            novelID: target.novelID, chapter: target.chapter, location: location)
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - 自動スクロールと購読

    /// ハイライト行が画面の scrollTargetHeightFraction の高さに来るようにスクロールする。
    /// scrollTo(id:anchor:) は「段落のアンカー点を画面の同じアンカー点に揃える」ことしかできないので、
    /// 段落の実測高さと段落内の文字位置の割合からアンカーを逆算する
    private func scrollToHighlight(proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        guard let highlight = highlightScalarRange,
              let paragraph = model.paragraphs.first(where: { $0.scalarRange.upperBound > highlight.lowerBound }) else { return }
        let anchor: UnitPoint
        if let paragraphHeight = model.paragraphHeights[paragraph.id], viewportHeight > 0 {
            let fraction: Double
            if paragraph.scalarRange.isEmpty {
                fraction = 0
            } else {
                let offset = highlight.lowerBound - paragraph.scalarRange.lowerBound
                fraction = min(max(Double(offset) / Double(paragraph.scalarRange.count), 0), 1)
            }
            anchor = UnitPoint(x: 0.5, y: Self.anchorY(highlightFraction: fraction,
                                                       paragraphHeight: paragraphHeight,
                                                       viewportHeight: viewportHeight))
        } else {
            // この段落の高さが未計測(ハイライトが初めて入った直後)。ひとまず中央狙いで寄せておき、
            // 実測が届いたら onPreferenceChange(ParagraphHeightsKey) から寄せ直す
            anchor = .center
            model.pendingHeightScrollParagraphID = paragraph.id
        }
        proxy.scrollTo(paragraph.id, anchor: anchor)
    }

    /// 段落内の位置 fraction(0-1、文字数比からの近似)にあるハイライト行が
    /// 画面の scrollTargetHeightFraction の高さに来るアンカー y を逆算する。
    /// scrollTo は「段落の a 点を画面の a 点に揃える」ので、ハイライト行の画面上の位置は
    /// a*H + (f-a)*hp。これを t*H にしたい → a = (t*H - f*hp) / (H - hp)。
    /// クランプされる(画面より高い段落の先頭/末尾など)場合も、可能な範囲で一番近い位置になる
    private static func anchorY(highlightFraction f: Double, paragraphHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let t = scrollTargetHeightFraction
        let hp = Double(paragraphHeight)
        let H = Double(viewportHeight)
        guard abs(H - hp) > 1 else { return CGFloat(t) }
        let a = (t * H - f * hp) / (H - hp)
        return CGFloat(min(max(a, 0), 1))
    }

    private func prepareTarget() {
        guard let target = displayTarget, session.storedNovelIDs.contains(target.novelID) else { return }
        model.prepare(novelID: target.novelID, chapter: target.chapter)
    }

    private func prepareAndScroll(proxy: ScrollViewProxy, viewportHeight: CGFloat) {
        prepareTarget()
        // 本文の差し替え直後はレイアウトが済んでから現在位置へ寄せる
        DispatchQueue.main.async {
            scrollToHighlight(proxy: proxy, viewportHeight: viewportHeight)
        }
    }

    private func updateSubscription() {
        // iPhone が発話元の時だけ、このページの表示中に限って位置の購読を頼む
        session.setReadingPointSubscription(
            !player.isSelectedAsSource && session.playState?.novelID.isEmpty == false)
    }
}

// MARK: - 段落1つ分の表示(ハイライトが変わった段落だけ再描画されるよう Equatable にする)

private struct ParagraphTextView: View, Equatable {
    let text: String
    /// この段落内の相対ハイライト範囲(unicodeScalar オフセット)。大半の段落は nil
    let localHighlight: Range<Int>?
    let fontSize: Double
    let textColor: Color
    let highlightColor: Color

    var body: some View {
        Text(attributedText)
            .font(.system(size: fontSize))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: AttributedString {
        // 空行も行として高さを持たせる(1つの Text で描画していた頃の見た目に合わせる)
        if text.isEmpty { return AttributedString(" ") }
        var attributed = AttributedString(text)
        guard let localHighlight = localHighlight else { return attributed }
        let scalars = attributed.unicodeScalars
        guard let start = scalars.index(scalars.startIndex, offsetBy: localHighlight.lowerBound, limitedBy: scalars.endIndex),
              let end = scalars.index(start, offsetBy: localHighlight.count, limitedBy: scalars.endIndex) else { return attributed }
        attributed[start..<end].backgroundColor = highlightColor
        return attributed
    }
}

// MARK: - 本文データと自動スクロール状態

final class TextPageModel: ObservableObject {
    struct Paragraph: Identifiable {
        let id: Int
        let text: String
        /// 章本文全体の中でこの段落が占める unicodeScalar 範囲(区切りの改行は含まない)
        let scalarRange: Range<Int>
    }

    @Published private(set) var paragraphs: [Paragraph] = []
    /// 発話ブロックの表示文字範囲一覧(ハイライトの粒度)。非同期に埋まることがある
    @Published private(set) var blockRanges: [Range<Int>] = []
    @Published private(set) var hasChapter = false

    private(set) var contentScalarCount = 0
    private(set) var subtitle = ""
    /// 転送済みバルクで読める章の上限(1〜この値)。0 なら本文未転送
    private(set) var storedChapterCount = 0
    private var contentKey = ""

    func isChapterAvailable(_ chapter: Int) -> Bool {
        return chapter >= 1 && chapter <= storedChapterCount
    }

    /// ハイライト中(だった)段落の実測高さ。スクロール位置の逆算に使う
    private(set) var paragraphHeights: [Int: CGFloat] = [:]
    /// 高さ未計測のまま暫定スクロールした段落(実測が届いたら寄せ直す)
    var pendingHeightScrollParagraphID: Int?

    func storeParagraphHeights(_ heights: [Int: CGFloat]) {
        paragraphHeights.merge(heights) { $1 }
    }

    func clearParagraphHeights() {
        paragraphHeights = [:]
        pendingHeightScrollParagraphID = nil
    }

    /// 表示対象の章の本文を読み込み、段落と発話ブロック範囲を作る(同じ章なら何もしない)。
    /// 本文はバルク単位のオンデマンド展開なので、章切替時に読むのは該当バルクだけ
    func prepare(novelID: String, chapter: Int) {
        let key = "\(novelID)#\(chapter)"
        guard key != contentKey else { return }
        contentKey = key
        clearParagraphHeights()
        storedChapterCount = NovelStorage.storedChapterCount(novelID: novelID)
        guard storedChapterCount > 0 else {
            applyEmptyChapter()
            contentKey = ""  // 後から本文が転送されてきた時に読み直せるように
            return
        }
        guard let story = NovelStorage.chapter(novelID: novelID, chapter: chapter) else {
            applyEmptyChapter()
            contentKey = ""  // 後から本文が転送されてきた時に読み直せるように
            return
        }
        hasChapter = true
        subtitle = story.subtitle
        let content = story.content
        contentScalarCount = content.unicodeScalars.count
        var result: [Paragraph] = []
        var offset = 0
        for (index, line) in content.components(separatedBy: "\n").enumerated() {
            let length = line.unicodeScalars.count
            result.append(Paragraph(id: index, text: line, scalarRange: offset..<(offset + length)))
            offset += length + 1
        }
        paragraphs = result
        blockRanges = []
        // Watch 単体再生でこの章を発話中(または開いている)なら、実際の発話ブロックをそのまま使う
        if let ranges = WatchSpeechPlayer.shared.displayBlockScalarRanges(novelID: novelID, chapter: chapter) {
            blockRanges = ranges
            return
        }
        // そうでなければ(iPhone 発話元など)同じ設定でローカルに分割して近似する。
        // 分割は章切替時の一度きりだが本文が長いと時間を食うのでバックグラウンドで行う
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let blocks = WatchSpeechPlayer.buildBlocks(content: content)
            var ranges: [Range<Int>] = []
            var position = 0
            for block in blocks {
                let length = block.displayText.unicodeScalars.count
                ranges.append(position..<(position + length))
                position += length
            }
            DispatchQueue.main.async {
                guard let self = self, self.contentKey == key else { return }
                self.blockRanges = ranges
            }
        }
    }

    private func applyEmptyChapter() {
        hasChapter = false
        subtitle = ""
        paragraphs = []
        blockRanges = []
        contentScalarCount = 0
    }

    func blockRange(containing location: Int) -> Range<Int>? {
        guard !blockRanges.isEmpty else { return nil }
        if let range = blockRanges.first(where: { $0.contains(location) }) { return range }
        // 章末(最終ブロックの終端)を指している場合は最終ブロック扱い
        if let last = blockRanges.last, location >= last.upperBound { return last }
        return nil
    }

}

/// ハイライト中の段落の実測高さ(段落ID → 高さ)。ハイライトが乗っている段落だけが emit する
private struct ParagraphHeightsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
