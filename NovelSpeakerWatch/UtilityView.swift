//
//  UtilityView.swift
//  NovelSpeakerWatch
//
//  ④便利機能リスト。①再生画面の右上メニューから開く。
//

import SwiftUI
import AVFoundation
import WatchConnectivity

struct UtilityView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackMessage: String?
    /// 隠しデバッグメニューの表示フラグ。末尾の案内文を10回タップすると ON になり、以後永続する
    @AppStorage("WatchDebugMenuEnabled") private var isDebugMenuEnabled = false
    @State private var debugUnlockTapCount = 0

    var body: some View {
        NavigationStack {
            utilityList
        }
    }

    private var utilityList: some View {
        // 並びは「よく触る設定 → 一覧 → 現在の小説への操作 → 押し間違いのペナルティが大きい物」の順。
        // 「この小説の更新確認」は "どの小説が対象か" が画面から読み取れず混乱するため置かない
        List {
            NavigationLink {
                SpeechConfigView()
            } label: {
                Label(NSLocalizedString("Watch_SpeechConfig_Title", comment: "速度と音量"), systemImage: "speedometer")
            }
            NavigationLink {
                RepeatConfigView()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Label(NSLocalizedString("Watch_RepeatConfig_Title", comment: "連続再生"), systemImage: "repeat")
                    // 現在のモードをここで確認できるようにする(再生画面には表示を置かない)
                    Text(repeatTypeLocalizedName(WatchSpeechPlayer.effectiveRepeatConfig().repeatType))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                CacheManagementView()
            } label: {
                Label(NSLocalizedString("Watch_Utility_StoredTexts", comment: "Watchに転送済みの本文"), systemImage: "internaldrive")
            }
            if let state = session.playState, !state.novelID.isEmpty {
                Button {
                    let isLiked = session.novels.first(where: { $0.novelID == state.novelID })?.isLiked ?? false
                    session.send(.setLike, args: [
                        WatchMessage.Arg.novelID: state.novelID,
                        WatchMessage.Arg.enabled: !isLiked,
                    ]) { ok in
                        if ok {
                            feedbackMessage = isLiked
                                ? NSLocalizedString("Watch_Utility_LikeOffDone", comment: "お気に入りを解除しました")
                                : NSLocalizedString("Watch_Utility_LikeOnDone", comment: "お気に入りにしました")
                        }
                    }
                } label: {
                    Label(currentNovelIsLiked
                            ? NSLocalizedString("Watch_Utility_LikeOff", comment: "お気に入りを解除")
                            : NSLocalizedString("Watch_Utility_LikeOn", comment: "お気に入りにする"),
                          systemImage: currentNovelIsLiked ? "heart.slash" : "heart")
                }
            }
            if let feedbackMessage = feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            Button {
                session.send(.checkUpdatesAll) { ok in
                    if ok { feedbackMessage = NSLocalizedString("Watch_Utility_CheckUpdatesAllStarted", comment: "全小説の更新確認を開始しました") }
                }
            } label: {
                Label(NSLocalizedString("Watch_Utility_CheckUpdatesAll", comment: "全小説の更新確認"), systemImage: "arrow.triangle.2.circlepath")
            }
            Section {
                Text(NSLocalizedString("Watch_Utility_TransferHint", comment: "Watchへ転送する小説の選択は、本棚で小説を左にスワイプするか、iPhoneの ことせかい の設定から行えます。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    // この案内文を10回タップすると隠しデバッグメニューが出る
                    //(iPhone 側の「ルビはルビだけ読む」10回トグルと同じ作法)
                    .onTapGesture {
                        guard !isDebugMenuEnabled else { return }
                        debugUnlockTapCount += 1
                        if debugUnlockTapCount >= 10 {
                            isDebugMenuEnabled = true
                        }
                    }
            }
            if isDebugMenuEnabled {
                Section {
                    NavigationLink {
                        WatchConnectionDiagnosticsView()
                    } label: {
                        Label(NSLocalizedString("Watch_Utility_ConnectionDiagnostics", comment: "接続診断(デバッグ)"), systemImage: "stethoscope")
                    }
                    Button {
                        isDebugMenuEnabled = false
                        debugUnlockTapCount = 0
                    } label: {
                        Label(NSLocalizedString("Watch_Utility_HideDebugMenu", comment: "デバッグメニューを隠す"), systemImage: "eye.slash")
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Watch_Utility_Title", comment: "便利機能"))
    }

    private var currentNovelIsLiked: Bool {
        guard let novelID = session.playState?.novelID else { return false }
        return session.novels.first(where: { $0.novelID == novelID })?.isLiked ?? false
    }
}

/// WCSession の接続診断(隠しデバッグメニュー)。Series 4 で観測された「半接続」状態
/// (iPhone側 isWatchAppInstalled=false / WCErrorDomain 7006 等)の再現時は Xcode からも
/// 観測しづらいため、Watch 単体でセッション状態と最終送受信時刻を確認できるようにする。
/// デバッグ用画面なので行の文言はローカライズしない(ログ文字列と同じ扱い)
struct WatchConnectionDiagnosticsView: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        let session = WCSession.default
        List {
            Section("WCSession") {
                row("activationState", activationStateName(session.activationState))
                row("isReachable", "\(session.isReachable)")
                row("isCompanionAppInstalled", "\(session.isCompanionAppInstalled)")
                row("受信済みcontext", session.receivedApplicationContext.isEmpty ? "なし" : "あり")
            }
            Section("最終イベント") {
                row("context受信", dateText(PhoneSessionManager.shared.lastContextReceivedDate))
                row("ファイル受信", dateText(PhoneSessionManager.shared.lastFileReceivedDate),
                    detail: PhoneSessionManager.shared.lastFileReceivedDescription)
                row("コマンド送信", dateText(PhoneSessionManager.shared.lastCommandSentDate),
                    detail: PhoneSessionManager.shared.lastCommandSentDescription)
            }
            Section("データ") {
                row("本棚の冊数", "\(PhoneSessionManager.shared.novels.count)")
                row("転送済み小説", "\(PhoneSessionManager.shared.storedNovelIDs.count)")
            }
        }
        .navigationTitle(NSLocalizedString("Watch_Utility_ConnectionDiagnostics", comment: "接続診断"))
        .onReceive(timer) { now = $0 }
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote)
            if let detail = detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    /// 「HH:mm:ss (n秒前)」表記。タイマーで body が毎秒再評価されるので相対表記も進む
    private func dateText(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 {
            return "\(formatter.string(from: date)) (\(max(0, seconds))秒前)"
        }
        if seconds < 3600 {
            return "\(formatter.string(from: date)) (\(seconds / 60)分前)"
        }
        return formatter.string(from: date)
    }

    private func activationStateName(_ state: WCSessionActivationState) -> String {
        switch state {
        case .activated: return "activated"
        case .inactive: return "inactive"
        case .notActivated: return "notActivated"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
}

/// 「再生が末尾に達した時の動作」の種別名(iPhone の設定画面と同じ文言)
func repeatTypeLocalizedName(_ type: WatchRepeatSpeechType) -> String {
    switch type {
    case .noRepeat:
        return NSLocalizedString("Watch_RepeatType_NoRepeat", comment: "そのまま停止する")
    case .rewindToFirstStory:
        return NSLocalizedString("Watch_RepeatType_RewindToFirstStory", comment: "最初のページから再生し直す")
    case .rewindToThisStory:
        return NSLocalizedString("Watch_RepeatType_RewindToThisStory", comment: "現在のページを再生し直す")
    case .goToNextLikeNovel:
        return NSLocalizedString("Watch_RepeatType_GoToNextLikeNovel", comment: "別のお気に入り小説を再生")
    case .goToNextSameFolderdNovel:
        return NSLocalizedString("Watch_RepeatType_GoToNextSameFolderdNovel", comment: "同じフォルダの別の小説を再生")
    case .goToNextSelectedFolderdNovel:
        return NSLocalizedString("Watch_RepeatType_GoToNextSelectedFolderdNovel", comment: "指定フォルダの別の小説を再生")
    case .goToNextSameWriterNovel:
        return NSLocalizedString("Watch_RepeatType_GoToNextSameWriterNovel", comment: "同じ作者の別の小説を再生")
    case .goToNextSameWebsiteNovel:
        return NSLocalizedString("Watch_RepeatType_GoToNextSameWebsiteNovel", comment: "同じWebサイトの別の小説を再生")
    }
}

/// 「再生が末尾に達した時の動作」の設定。値は iPhone の RealmGlobalState が正本で、
/// ここでの変更は Watch の連続再生に即時効かせつつ iPhone へ書き戻される(速度・音量と同じ意味論)。
struct RepeatConfigView: View {
    @State private var repeatTypeRawValue: Int = WatchRepeatSpeechType.noRepeat.rawValue
    @State private var isLoopNoCheckReadingPoint = false

    private static let allTypes: [WatchRepeatSpeechType] = [
        .noRepeat, .rewindToFirstStory, .rewindToThisStory,
        .goToNextLikeNovel, .goToNextSameFolderdNovel, .goToNextSelectedFolderdNovel,
        .goToNextSameWriterNovel, .goToNextSameWebsiteNovel,
    ]
    /// 「次の小説の選択方式」が意味を持つ種別(iPhone の設定画面の表示条件と同じ)
    private static let loopTargetTypes: Set<Int> = Set([
        WatchRepeatSpeechType.goToNextLikeNovel, .goToNextSameFolderdNovel,
        .goToNextSelectedFolderdNovel, .goToNextSameWriterNovel, .goToNextSameWebsiteNovel,
    ].map { $0.rawValue })

    var body: some View {
        List {
            Section(NSLocalizedString("Watch_RepeatConfig_TypeTitle", comment: "再生が末尾に達した時の動作")) {
                ForEach(Self.allTypes, id: \.rawValue) { type in
                    selectionRow(title: repeatTypeLocalizedName(type), isSelected: repeatTypeRawValue == type.rawValue) {
                        repeatTypeRawValue = type.rawValue
                        apply()
                    }
                }
            }
            if Self.loopTargetTypes.contains(repeatTypeRawValue) {
                Section(NSLocalizedString("Watch_RepeatConfig_LoopTitle", comment: "次の小説の選択方式")) {
                    selectionRow(title: NSLocalizedString("Watch_RepeatLoop_Normal", comment: "未読分の続きから再生"), isSelected: !isLoopNoCheckReadingPoint) {
                        isLoopNoCheckReadingPoint = false
                        apply()
                    }
                    selectionRow(title: NSLocalizedString("Watch_RepeatLoop_NoCheckReadingPoint", comment: "順に1ページ目から再生"), isSelected: isLoopNoCheckReadingPoint) {
                        isLoopNoCheckReadingPoint = true
                        apply()
                    }
                }
            }
            Section {
                Text(NSLocalizedString("Watch_RepeatConfig_Note", comment: "Watch単体モードでの連続再生の対象になるのは、Watchに転送済みの小説だけです。変更は iPhone の設定に保存されます。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("Watch_RepeatConfig_Title", comment: "連続再生"))
        .onAppear {
            load()
        }
        // 画面を開いている間に iPhone から新しい設定が届いたら表示も追従させる
        .onReceive(NotificationCenter.default.publisher(for: WatchSpeechSettingsStorage.didUpdateNotification)) { _ in
            load()
        }
    }

    private func selectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.footnote)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func load() {
        let config = WatchSpeechPlayer.effectiveRepeatConfig()
        repeatTypeRawValue = config.repeatType.rawValue
        isLoopNoCheckReadingPoint = config.isLoopNoCheckReadingPoint
    }

    private func apply() {
        WatchSpeechPlayer.shared.setRepeatConfig(
            repeatType: WatchRepeatSpeechType(rawValue: repeatTypeRawValue) ?? .noRepeat,
            isLoopNoCheckReadingPoint: isLoopNoCheckReadingPoint)
    }
}

/// 発話の速度・音量の設定。値は iPhone の標準話者設定(RealmSpeakerSetting)が正本で、
/// ここでの変更は Watch の発話に即時(次のブロックから)効かせつつ iPhone へ書き戻される。
/// スライダーの範囲・クランプは iPhone の「発話設定」画面と同じ。
struct SpeechConfigView: View {
    @State private var rate: Double = Double(AVSpeechUtteranceDefaultSpeechRate)
    @State private var volume: Double = 1.0
    @State private var hasLoaded = false

    private let rateRange = Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(NSLocalizedString("Watch_SpeechConfig_Rate", comment: "速度")).font(.footnote)
                    Spacer()
                    Text(String(format: "%.2f", rate)).font(.footnote).foregroundStyle(.secondary)
                }
                Slider(value: $rate, in: rateRange, step: 0.05)
                    .accessibilityLabel(NSLocalizedString("Watch_SpeechConfig_Rate", comment: "速度"))
                    .accessibilityValue(String(format: "%.2f", rate))

                HStack {
                    Text(NSLocalizedString("Watch_SpeechConfig_Volume", comment: "音量")).font(.footnote)
                    Spacer()
                    Text("\(Int((volume * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary)
                }
                Slider(value: $volume, in: 0...1, step: 0.05)
                    .accessibilityLabel(NSLocalizedString("Watch_SpeechConfig_Volume", comment: "音量"))
                    .accessibilityValue("\(Int((volume * 100).rounded()))%")

                Text(NSLocalizedString("Watch_SpeechConfig_Note", comment: "変更は iPhone の標準の話者設定に保存されます。発話中の変更は次の文から反映されます。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(NSLocalizedString("Watch_SpeechConfig_Title", comment: "速度と音量"))
        .onAppear {
            let current = WatchSpeechPlayer.effectiveDefaultSpeakerConfig()
            rate = Double(current.rate)
            volume = Double(current.volume)
            // onAppear での初期値セットによる onChange 発火では書き込まないようにする
            DispatchQueue.main.async { hasLoaded = true }
        }
        .onChange(of: rate) { _ in apply() }
        .onChange(of: volume) { _ in apply() }
        // 画面を開いている間に iPhone から新しい発話設定が届いたら表示も追従させる
        // (値が同じなら何もしないので、自分の変更で apply とループすることはない)
        .onReceive(NotificationCenter.default.publisher(for: WatchSpeechSettingsStorage.didUpdateNotification)) { _ in
            guard hasLoaded else { return }
            let current = WatchSpeechPlayer.effectiveDefaultSpeakerConfig()
            if abs(Float(rate) - current.rate) >= 0.001 { rate = Double(current.rate) }
            if abs(Float(volume) - current.volume) >= 0.001 { volume = Double(current.volume) }
        }
    }

    private func apply() {
        guard hasLoaded else { return }
        let current = WatchSpeechPlayer.effectiveDefaultSpeakerConfig()
        if abs(current.rate - Float(rate)) < 0.001 && abs(current.volume - Float(volume)) < 0.001 { return }
        WatchSpeechPlayer.shared.setSpeechConfig(rate: Float(rate), volume: Float(volume))
    }
}

/// Watch に転送済みの本文の一覧。転送し直し(古いデータの更新)と削除ができる。
/// 転送済みの小説は iPhone 側で章が増えると自動で転送し直されるので、
/// ここでの削除は「自動同期をやめる」の意味も持つ。
/// 並び順は「Watchで最後に再生した日が古い順」= 削除候補が上に集まる。
struct CacheManagementView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @State private var dialogNovelID: String?
    @State private var isSelecting = false
    @State private var selectedNovelIDs: Set<String> = []

    var body: some View {
        List {
            if session.storedNovelIDs.isEmpty {
                Text(NSLocalizedString("Watch_Cache_Empty", comment: "転送済みの小説はありません。本棚から転送できます。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if isSelecting && !session.storedNovelIDs.isEmpty {
                Button(role: .destructive) {
                    for novelID in selectedNovelIDs {
                        session.removeStoredNovel(novelID: novelID)
                    }
                    selectedNovelIDs = []
                    isSelecting = false
                } label: {
                    Label(String(format: NSLocalizedString("Watch_Cache_DeleteSelected", comment: "選択した%d件を削除"), selectedNovelIDs.count), systemImage: "trash")
                }
                .disabled(selectedNovelIDs.isEmpty)
            }
            ForEach(sortedStoredNovelIDs, id: \.self) { novelID in
                Button {
                    if isSelecting {
                        if selectedNovelIDs.contains(novelID) {
                            selectedNovelIDs.remove(novelID)
                        } else {
                            selectedNovelIDs.insert(novelID)
                        }
                    } else {
                        dialogNovelID = novelID
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSelecting {
                            Image(systemName: selectedNovelIDs.contains(novelID) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(selectedNovelIDs.contains(novelID) ? .green : .secondary)
                                .accessibilityHidden(true) // 選択状態はボタンの isSelected トレイトで伝える
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(storedTitle(novelID: novelID))
                                .font(.footnote)
                                .lineLimit(2)
                            Text(detailText(novelID: novelID))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityAddTraits(isSelecting && selectedNovelIDs.contains(novelID) ? [.isSelected] : [])
            }
        }
        .navigationTitle(NSLocalizedString("Watch_Utility_StoredTexts", comment: "Watch内の本文"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !session.storedNovelIDs.isEmpty {
                    Button(isSelecting
                            ? NSLocalizedString("Watch_Cache_Done", comment: "完了")
                            : NSLocalizedString("Watch_Cache_Select", comment: "選択")) {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedNovelIDs = []
                        }
                    }
                    .font(.footnote)
                }
            }
        }
        .onAppear {
            // 本棚から削除された小説の孤児キャッシュを掃除
            session.verifyStoredNovelsAgainstBookshelf()
        }
        .confirmationDialog(
            storedTitle(novelID: dialogNovelID ?? ""),
            isPresented: Binding(
                get: { dialogNovelID != nil },
                set: { presented in
                    if !presented { dialogNovelID = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: dialogNovelID
        ) { novelID in
            Button(NSLocalizedString("Watch_Cache_Retransfer", comment: "本文を転送し直す")) {
                session.requestTransfer(novelID: novelID)
            }
            Button(NSLocalizedString("Watch_Cache_RemoveFromWatch", comment: "Watchから削除"), role: .destructive) {
                session.removeStoredNovel(novelID: novelID)
            }
            Button(NSLocalizedString("Watch_Cancel", comment: "キャンセル"), role: .cancel) {}
        }
    }

    /// Watchで最後に再生した日が古い順(未再生が先頭)
    private var sortedStoredNovelIDs: [String] {
        return session.storedNovelIDs.sorted { a, b in
            let dateA = session.lastPlayedDates[a] ?? Date(timeIntervalSince1970: 0)
            let dateB = session.lastPlayedDates[b] ?? Date(timeIntervalSince1970: 0)
            if dateA != dateB { return dateA < dateB }
            return a < b
        }
    }

    private func storedTitle(novelID: String) -> String {
        if let title = session.novels.first(where: { $0.novelID == novelID })?.title, !title.isEmpty {
            return title
        }
        return session.storedTitles[novelID] ?? novelID
    }

    private func detailText(novelID: String) -> String {
        let chapters = String(format: NSLocalizedString("Watch_Cache_ChapterCount", comment: "%dページ"), session.storedChapterCounts[novelID] ?? 0)
        guard let lastPlayed = session.lastPlayedDates[novelID] else {
            return String(format: NSLocalizedString("Watch_Cache_Detail_NeverPlayed", comment: "%@ · Watchで未再生"), chapters)
        }
        let days = Int(Date().timeIntervalSince(lastPlayed) / (24 * 60 * 60))
        if days <= 0 {
            return String(format: NSLocalizedString("Watch_Cache_Detail_PlayedToday", comment: "%@ · 今日再生"), chapters)
        }
        return String(format: NSLocalizedString("Watch_Cache_Detail_PlayedDaysAgo", comment: "%1$@ · %2$d日前に再生"), chapters, days)
    }
}
