import SwiftUI

@main
struct NovelSpeakerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

struct WatchRootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title2)
            Text("ことせかい")
                .font(.headline)
            Text("Apple Watch 対応 開発中")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
