//
//  PlayerView.swift
//  NovelSpeakerWatch
//
//  ①再生画面(ルート)。再生中アプリ準拠 + 章移動ボタンを章ラベルの左右に常設。
//  時計は OS が右上に描画するため、メニューボタンは空いている左上に置く。
//

import SwiftUI

struct PlayerView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @State private var isUtilityPresented = false

    var body: some View {
        VStack(spacing: 4) {
            Text(session.playState?.title.isEmpty == false ? session.playState!.title : "小説が選ばれていません")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // ソースバッジ。将来ここが「iPhoneで聴く/Watchで聴く」の切替ボタンになる予定なので
            // 再生停止ボタンから離れたこの位置に置いておく
            statusBadge

            HStack(spacing: 8) {
                chapterButton(systemName: "backward.end") {
                    session.send(.previousChapter)
                }
                Text(chapterLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                chapterButton(systemName: "forward.end") {
                    session.send(.nextChapter)
                }
            }
            .padding(.horizontal, 6)

            Spacer(minLength: 2)

            // 30字戻る/進むは誤タップ防止のため再生停止ボタンから左右いっぱいに離す
            HStack(spacing: 0) {
                Button {
                    session.send(.skipBackward)
                } label: {
                    Image(systemName: "gobackward")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    session.send(.togglePlayPause)
                } label: {
                    Image(systemName: session.playState?.isPlaying == true ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Button {
                    session.send(.skipForward)
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
        // エラーのアラート表示はルート(WatchRootView)で行う
        .onAppear {
            session.send(.requestStatus)
        }
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
        guard let state = session.playState, !state.novelID.isEmpty else { return "-" }
        if state.chapterCount > 0 {
            return "\(state.chapterNumber)/\(state.chapterCount)章 · \(Int(state.progress * 100))%"
        }
        return "第\(state.chapterNumber)章"
    }

    @ViewBuilder private var statusBadge: some View {
        if session.isSending {
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
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(color.opacity(0.25))
            .clipShape(Capsule())
            .frame(height: 16)
    }
}
