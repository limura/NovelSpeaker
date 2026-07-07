//
//  TextPageView.swift
//  NovelSpeakerWatch
//
//  ②本文ページ。転送済み本文の現在章を表示する。
//  発話位置ハイライト・自動スクロール・購読制の位置同期は v1.5 で実装する。
//
//  ナビゲーションバーのタイトルには小説名を出す(スクロール時に上段へ小さく残るのは小説名だけ)。
//  章タイトルと章番号は本文と一緒にスクロールで流れる。
//

import SwiftUI

struct TextPageView: View {
    @ObservedObject private var session = PhoneSessionManager.shared
    @State private var isSettingsPresented = false

    @AppStorage(TextDisplayDefaults.fontSizeKey) private var fontSize: Double = 14
    @AppStorage(TextDisplayDefaults.textColorKey) private var textColorName: String = "white"
    @AppStorage(TextDisplayDefaults.backgroundColorKey) private var backgroundColorName: String = "black"

    var body: some View {
        let textColor = TextDisplayDefaults.textColor(named: textColorName)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let loaded = loadedNovel, let state = session.playState {
                    if let chapter = loaded.stories[state.chapterNumber] {
                        if !chapter.subtitle.isEmpty {
                            Text(chapter.subtitle)
                                .font(.system(size: max(fontSize - 2, 10), weight: .semibold))
                                .foregroundStyle(textColor)
                        }
                        Text(pageLabel(state: state))
                            .font(.system(size: 11))
                            .foregroundStyle(textColor.opacity(0.6))
                        Text(chapter.content)
                            .font(.system(size: fontSize))
                            .foregroundStyle(textColor)
                    } else {
                        Text("この章(\(state.chapterNumber)章)はまだWatchに転送されていません。本棚から転送し直せます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if let state = session.playState, !state.novelID.isEmpty {
                    Text("「\(state.title)」の本文はまだWatchに転送されていません。本棚から転送できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("小説が選ばれていません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .background(TextDisplayDefaults.backgroundColor(named: backgroundColorName).ignoresSafeArea())
        .navigationTitle(session.playState?.title.isEmpty == false ? session.playState!.title : "本文")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "textformat.size")
                }
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                TextSettingsView()
            }
        }
    }

    private var loadedNovel: (title: String, stories: [Int: NovelStorage.StoredChapter])? {
        guard let state = session.playState, !state.novelID.isEmpty,
              session.storedNovelIDs.contains(state.novelID) else { return nil }
        return NovelStorage.loadNovel(novelID: state.novelID)
    }

    private func pageLabel(state: WatchPlayState) -> String {
        if state.chapterCount > 0 {
            return "\(state.chapterNumber)/\(state.chapterCount)"
        }
        return "\(state.chapterNumber)"
    }
}
