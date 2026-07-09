//
//  UtilityView.swift
//  NovelSpeakerWatch
//
//  ④便利機能リスト。①再生画面の右上メニューから開く。
//

import SwiftUI

struct UtilityView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackMessage: String?

    var body: some View {
        NavigationStack {
            utilityList
        }
    }

    private var utilityList: some View {
        List {
            NavigationLink {
                CacheManagementView()
            } label: {
                Label("Watch内の本文", systemImage: "internaldrive")
            }
            if let feedbackMessage = feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            Button {
                session.send(.checkUpdatesAll) { ok in
                    if ok { feedbackMessage = "全小説の更新確認を開始しました" }
                }
            } label: {
                Label("全小説の更新確認", systemImage: "arrow.triangle.2.circlepath")
            }
            if let state = session.playState, !state.novelID.isEmpty {
                Button {
                    session.send(.checkUpdates, args: [WatchMessage.Arg.novelID: state.novelID]) { ok in
                        if ok { feedbackMessage = "「\(state.title)」の更新確認を開始しました" }
                    }
                } label: {
                    Label("この小説を更新確認", systemImage: "arrow.down.circle")
                }
                Button {
                    let isLiked = session.novels.first(where: { $0.novelID == state.novelID })?.isLiked ?? false
                    session.send(.setLike, args: [
                        WatchMessage.Arg.novelID: state.novelID,
                        WatchMessage.Arg.enabled: !isLiked,
                    ]) { ok in
                        if ok { feedbackMessage = isLiked ? "お気に入りを解除しました" : "お気に入りにしました" }
                    }
                } label: {
                    Label(currentNovelIsLiked ? "お気に入りを解除" : "お気に入りにする",
                          systemImage: currentNovelIsLiked ? "heart.slash" : "heart")
                }
            }
            Section {
                Text("Watchへ転送する小説の選択は、本棚で小説を左にスワイプするか、iPhoneの ことせかい の設定から行えます。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("便利機能")
    }

    private var currentNovelIsLiked: Bool {
        guard let novelID = session.playState?.novelID else { return false }
        return session.novels.first(where: { $0.novelID == novelID })?.isLiked ?? false
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
                Text("転送済みの小説はありません。本棚から転送できます。")
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
                    Label("選択した\(selectedNovelIDs.count)件を削除", systemImage: "trash")
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
            }
        }
        .navigationTitle("Watch内の本文")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !session.storedNovelIDs.isEmpty {
                    Button(isSelecting ? "完了" : "選択") {
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
            Button("本文を転送し直す") {
                session.requestTransfer(novelID: novelID)
            }
            Button("Watchから削除", role: .destructive) {
                session.removeStoredNovel(novelID: novelID)
            }
            Button("キャンセル", role: .cancel) {}
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
        let chapters = "\(session.storedChapterCounts[novelID] ?? 0)章"
        guard let lastPlayed = session.lastPlayedDates[novelID] else {
            return "\(chapters) · Watchで未再生"
        }
        let days = Int(Date().timeIntervalSince(lastPlayed) / (24 * 60 * 60))
        if days <= 0 {
            return "\(chapters) · 今日再生"
        }
        return "\(chapters) · \(days)日前に再生"
    }
}
