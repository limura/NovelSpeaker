//
//  BookshelfView.swift
//  NovelSpeakerWatch
//
//  ③本棚。iPhone から送られた全小説のメタデータを一覧し、転送状態を表示する。
//  タップ時: 本文が Watch に揃っていれば再生画面へ。
//  未転送・章が足りない(iPhone側で更新された)場合は選択ダイアログを出す。
//

import SwiftUI

struct BookshelfView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    /// タップで再生ページへ移動するための親タブ selection
    @Binding var tabSelection: Int
    @State private var dialogNovel: WatchNovelSummary?

    var body: some View {
        List {
            if session.novels.isEmpty {
                Text(NSLocalizedString("Watch_Bookshelf_EmptyMessage", comment: "iPhoneの ことせかい を一度起動すると、本棚がここに表示されます。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(session.novels, id: \.novelID) { novel in
                Button {
                    if transferState(novel: novel) == .complete {
                        openNovel(novel)
                    } else {
                        dialogNovel = novel
                    }
                } label: {
                    HStack(spacing: 6) {
                        transferStateIcon(novel: novel)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(novel.title)
                                .font(.footnote)
                                .lineLimit(2)
                            Text(chapterText(novel: novel))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if novel.isLiked {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.pink)
                                .accessibilityLabel(NSLocalizedString("Watch_AX_Liked", comment: "お気に入り"))
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Watch_Bookshelf_Title", comment: "本棚"))
        .onAppear {
            // 本棚が空(再インストール直後など)なら iPhone に一覧を要求する。
            // iPhone 側は requestStatus を受けると重複抑止を飛ばして必ず送り返す
            if session.novels.isEmpty {
                session.send(.requestStatus, quiet: true)
            }
        }
        .confirmationDialog(
            dialogNovel?.title ?? "",
            isPresented: Binding(
                get: { dialogNovel != nil },
                set: { presented in
                    if !presented { dialogNovel = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: dialogNovel
        ) { novel in
            Button(transferButtonLabel(novel: novel)) {
                session.requestTransfer(novelID: novel.novelID)
            }
            Button(NSLocalizedString("Watch_Bookshelf_GoToPlayer", comment: "再生画面へ移動")) {
                openNovel(novel)
            }
            Button(NSLocalizedString("Watch_Cancel", comment: "キャンセル"), role: .cancel) {}
        } message: { novel in
            Text(dialogMessage(novel: novel))
        }
    }

    private func openNovel(_ novel: WatchNovelSummary) {
        // Watch 単体再生モード中で本文が転送済みなら、Watch 側のプレイヤーに開く
        // (未転送なら iPhone モードへ戻して従来どおり iPhone 側に開かせる)
        let player = WatchSpeechPlayer.shared
        if player.isSelectedAsSource {
            if player.open(novelID: novel.novelID, fallbackTitle: novel.title) {
                tabSelection = 1
                return
            }
            player.isSelectedAsSource = false
        }
        // iPhone に繋がっていない(ランニング中・別の Watch が接続中など)場合でも、
        // 本文が転送済みなら Watch 単体モードへ切り替えて開く(小説を替えられないと困る)
        if !session.isReachable, openAsWatchSourceFallback(novel) { return }
        session.send(.openNovel, args: [WatchMessage.Arg.novelID: novel.novelID]) { ok in
            if !ok, openAsWatchSourceFallback(novel) {
                // 単体モードで開けたのでエラーアラートは出さない
                // (エラー文言は completion の直前にセットされるため、ここで消せば表示前に消える)
                session.lastErrorMessage = nil
            }
        }
        tabSelection = 1
    }

    /// iPhone に開かせられない時のフォールバック。転送済みなら Watch 単体モードで開いて true
    private func openAsWatchSourceFallback(_ novel: WatchNovelSummary) -> Bool {
        let player = WatchSpeechPlayer.shared
        guard player.open(novelID: novel.novelID, fallbackTitle: novel.title) else { return false }
        player.isSelectedAsSource = true
        player.refreshComplication()
        tabSelection = 1
        return true
    }

    // MARK: - 転送状態

    private enum TransferState {
        case complete   // 全章が Watch にある
        case partial    // 転送済みだが iPhone 側の方が章が多い(更新された)
        case none       // 未転送
        case requested  // 特急転送を依頼中
    }

    private func transferState(novel: WatchNovelSummary) -> TransferState {
        if session.transferRequestedNovelIDs.contains(novel.novelID) { return .requested }
        guard let storedCount = session.storedChapterCounts[novel.novelID] else { return .none }
        if novel.chapterCount > 0 && storedCount < novel.chapterCount { return .partial }
        return .complete
    }

    @ViewBuilder private func transferStateIcon(novel: WatchNovelSummary) -> some View {
        // VoiceOver は行全体を読むので、アイコンには転送状態の説明を持たせる
        switch transferState(novel: novel) {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_Complete", comment: "転送済み"))
        case .partial:
            Image(systemName: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_Partial", comment: "iPhone側で更新あり"))
        case .requested:
            ProgressView()
                .frame(width: 12, height: 12)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_Requested", comment: "転送依頼中"))
        case .none:
            Image(systemName: "cloud")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityLabel(NSLocalizedString("Watch_AX_TransferState_None", comment: "未転送"))
        }
    }

    private func transferButtonLabel(novel: WatchNovelSummary) -> String {
        if let storedCount = session.storedChapterCounts[novel.novelID] {
            return String(format: NSLocalizedString("Watch_Bookshelf_TransferUpdates", comment: "更新分を転送 (%1$d→%2$d章)"), storedCount, novel.chapterCount)
        }
        return NSLocalizedString("Watch_Bookshelf_TransferBody", comment: "本文をWatchへ転送")
    }

    private func dialogMessage(novel: WatchNovelSummary) -> String {
        if session.storedChapterCounts[novel.novelID] != nil {
            return NSLocalizedString("Watch_Bookshelf_UpdatedOnPhone", comment: "この小説はiPhone側で更新されています。")
        }
        return NSLocalizedString("Watch_Bookshelf_NotTransferred", comment: "この小説の本文はまだWatchにありません。")
    }

    private func chapterText(novel: WatchNovelSummary) -> String {
        if novel.chapterCount > 0 {
            return String(format: NSLocalizedString("Watch_Bookshelf_ChapterProgress", comment: "%1$d/%2$d章"), novel.readingChapterNumber, novel.chapterCount)
        }
        return ""
    }
}
