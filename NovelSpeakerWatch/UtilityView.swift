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
                Text("Watchへ転送する小説の選択は、本棚で小説を左にスワイプするか、iPhoneのことせかいの設定から行えます。")
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
struct CacheManagementView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @State private var dialogNovelID: String?

    var body: some View {
        List {
            if session.storedNovelIDs.isEmpty {
                Text("転送済みの小説はありません。本棚から転送できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(session.storedNovelIDs.sorted(), id: \.self) { novelID in
                Button {
                    dialogNovelID = novelID
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(storedTitle(novelID: novelID))
                            .font(.footnote)
                            .lineLimit(2)
                        Text("\(session.storedChapterCounts[novelID] ?? 0)章")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Watch内の本文")
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

    private func storedTitle(novelID: String) -> String {
        if let title = session.novels.first(where: { $0.novelID == novelID })?.title, !title.isEmpty {
            return title
        }
        return session.storedTitles[novelID] ?? novelID
    }
}
