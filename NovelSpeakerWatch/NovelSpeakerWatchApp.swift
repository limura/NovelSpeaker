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
    /// 0=本棚 1=再生(ルート) 2=本文
    @State private var tabSelection = 1

    var body: some View {
        TabView(selection: $tabSelection) {
            NavigationStack {
                BookshelfView(tabSelection: $tabSelection)
            }
            .tag(0)
            NavigationStack {
                PlayerView()
            }
            .tag(1)
            NavigationStack {
                TextPageView()
            }
            .tag(2)
        }
        .tabViewStyle(.page)
    }
}
