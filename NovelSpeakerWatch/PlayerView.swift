//
//  PlayerView.swift
//  NovelSpeakerWatch
//
//  ①再生画面(ルート)。再生中アプリ準拠 + 章移動ボタンを章ラベルの左右に常設。
//  時計は OS が右上に描画するため、メニューボタンは空いている左上に置く。
//  タイトル下のソースバッジをタップすると「iPhoneで聴く/Watchで聴く(単体再生)」を切り替えられる。
//

import SwiftUI

struct PlayerView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @ObservedObject private var player = WatchSpeechPlayer.shared
    @State private var isUtilityPresented = false
    @State private var isSourceDialogPresented = false

    /// 発話元として Watch 単体再生が選ばれているか
    private var isWatchSource: Bool { player.isSelectedAsSource }

    var body: some View {
        VStack(spacing: 4) {
            Text(titleLabel)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // ソースバッジ = 発話元セレクタ。タップで iPhone/Watch を切り替える
            Button {
                isSourceDialogPresented = true
            } label: {
                statusBadge
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                chapterButton(systemName: "backward.end") {
                    if isWatchSource {
                        player.moveChapter(offset: -1)
                    } else {
                        session.send(.previousChapter)
                    }
                }
                Text(chapterLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                chapterButton(systemName: "forward.end") {
                    if isWatchSource {
                        player.moveChapter(offset: 1)
                    } else {
                        session.send(.nextChapter)
                    }
                }
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 2)

            // 少し戻る/進むは誤タップ防止のため再生停止ボタンから左右いっぱいに離す
            HStack(spacing: 0) {
                Button {
                    if isWatchSource {
                        player.skip(by: -WatchSpeechPlayer.skipLength)
                    } else {
                        session.send(.skipBackward)
                    }
                } label: {
                    Image(systemName: "gobackward")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    if isWatchSource {
                        player.togglePlayPause()
                    } else {
                        session.send(.togglePlayPause)
                    }
                } label: {
                    Image(systemName: isPlayingNow ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    if isWatchSource {
                        player.skip(by: WatchSpeechPlayer.skipLength)
                    } else {
                        session.send(.skipForward)
                    }
                } label: {
                    Image(systemName: "goforward")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)
        }
        // 上段は右側に OS の時計が出るので、その左側の空きにメニューを置く
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isUtilityPresented = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
            }
        }
        .sheet(isPresented: $isUtilityPresented) {
            UtilityView()
        }
        .confirmationDialog("どこで読み上げますか？", isPresented: $isSourceDialogPresented) {
            Button {
                selectPhoneSource()
            } label: {
                Label("iPhoneで聴く", systemImage: isWatchSource ? "iphone" : "checkmark")
            }
            Button {
                selectWatchSource()
            } label: {
                Label("Watchで聴く(単体再生)", systemImage: isWatchSource ? "checkmark" : "applewatch")
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("Watch単体再生は、転送済みの本文をWatchのスピーカーやイヤホンで読み上げます(iPhoneが無くても動きます)")
        }
        // エラーのアラート表示はルート(WatchRootView)で行う
        .onAppear {
            if !isWatchSource {
                session.send(.requestStatus)
            }
        }
    }

    // MARK: - 発話元の切り替え

    private func selectWatchSource() {
        if isWatchSource { return }
        let targetNovelID = session.playState?.novelID ?? ""
        guard !targetNovelID.isEmpty else {
            session.lastErrorMessage = "小説が選ばれていません。本棚から小説を選んでください。"
            return
        }
        guard player.open(novelID: targetNovelID, fallbackTitle: session.playState?.title ?? "") else {
            session.lastErrorMessage = "この小説の本文がWatchに転送されていません。本棚の小説をタップして転送してから、もう一度お試しください。"
            return
        }
        // iPhone 側で再生中なら止めてから引き継ぐ(二重読み上げ防止)
        if session.playState?.isPlaying == true {
            session.send(.togglePlayPause, quiet: true)
        }
        player.isSelectedAsSource = true
    }

    private func selectPhoneSource() {
        if !isWatchSource { return }
        if player.isPlaying {
            player.stop()
        }
        player.isSelectedAsSource = false
        session.send(.requestStatus, quiet: true)
    }

    // MARK: - 表示

    private var isPlayingNow: Bool {
        return isWatchSource ? player.isPlaying : (session.playState?.isPlaying == true)
    }

    private var titleLabel: String {
        if isWatchSource {
            return player.title.isEmpty ? "小説が選ばれていません" : player.title
        }
        return session.playState?.title.isEmpty == false ? session.playState!.title : "小説が選ばれていません"
    }

    private func chapterButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .frame(width: 30, height: 22)
                .background(.white.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chapterLabel: String {
        if isWatchSource {
            guard !player.novelID.isEmpty else { return "-" }
            return "\(player.chapterNumber)/\(player.chapterCount)章 · \(Int(player.progress * 100))%"
        }
        guard let state = session.playState, !state.novelID.isEmpty else { return "-" }
        if state.chapterCount > 0 {
            return "\(state.chapterNumber)/\(state.chapterCount)章 · \(Int(state.progress * 100))%"
        }
        return "第\(state.chapterNumber)章"
    }

    @ViewBuilder private var statusBadge: some View {
        if isWatchSource {
            if player.isPlaying {
                badge(text: "Watchで再生中", color: .purple)
            } else {
                badge(text: "Watch単体モード", color: .purple)
            }
        } else if session.isSending {
            HStack(spacing: 4) {
                ProgressView()
                    .frame(width: 12, height: 12)
                Text("接続中…")
                    .font(.system(size: 11))
            }
            .frame(height: 16)
        } else if session.playState?.isPlaying == true {
            badge(text: "iPhoneで再生中", color: .green)
        } else if session.isReachable {
            badge(text: "iPhone接続中", color: .teal)
        } else {
            badge(text: "iPhone未接続", color: .orange)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(.system(size: 11))
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(color.opacity(0.25))
        .clipShape(Capsule())
        .frame(height: 16)
    }
}
