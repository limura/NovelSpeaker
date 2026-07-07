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
    @ObservedObject private var session = PhoneSessionManager.shared

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
        // エラーはページ遷移に巻き込まれないようルートで表示する
        // (ページ内に置くと遷移中に出ようとして即座に消えることがある)
        .alert("操作できませんでした", isPresented: isErrorPresented) {
            Button("OK") {
                session.lastErrorMessage = nil
            }
        } message: {
            Text(session.lastErrorMessage ?? "")
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { session.lastErrorMessage != nil },
            set: { presented in
                if !presented {
                    session.lastErrorMessage = nil
                }
            }
        )
    }
}
