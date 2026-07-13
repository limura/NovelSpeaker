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
    @ObservedObject private var player = WatchSpeechPlayer.shared

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
        .alert(NSLocalizedString("Watch_ErrorAlert_Title", comment: "操作できませんでした"), isPresented: isErrorPresented) {
            Button("OK") {
                session.lastErrorMessage = nil
            }
        } message: {
            Text(session.lastErrorMessage ?? "")
        }
        // Bluetooth 未接続の注意(「Watchで聴く」を選んだ時)。「今後表示しない」を選べる
        // (Watch のスピーカーで聴くことを主とする人には毎回出ると邪魔なため)
        .alert(NSLocalizedString("Watch_InfoAlert_Title", comment: "お知らせ"), isPresented: $player.isNoBluetoothWarningPresented) {
            Button("OK") {}
            Button(NSLocalizedString("Watch_Player_NoBluetoothWarning_DontShowAgain", comment: "今後表示しない")) {
                UserDefaults.standard.set(true, forKey: WatchSpeechPlayer.suppressNoBluetoothWarningKey)
            }
        } message: {
            Text(NSLocalizedString("Watch_Player_NoBluetoothWarning", comment: "Bluetoothのイヤホン等が接続されていません。"))
        }
        // 「指定フォルダの小説を再生」で対象フォルダの選択が必要な時に出す(iPhone 側の選択UIと同等)。
        // 再生ボタンは再生画面にも本文ページにもあるので、ダイアログはルートに置く
        .confirmationDialog(
            NSLocalizedString("Watch_Player_SelectFolder_Title", comment: "続けて再生するフォルダを選択"),
            isPresented: isFolderSelectionPresented,
            titleVisibility: .visible
        ) {
            ForEach(player.folderSelectionRequest ?? [], id: \.self) { folderName in
                Button(folderName) {
                    player.selectFolderForRepeatAndPlay(name: folderName)
                }
            }
            Button(NSLocalizedString("Watch_Cancel", comment: "キャンセル"), role: .cancel) {}
        }
        // コンプリケーション(ウィジェット)のタップで届くディープリンクを処理する。
        // ウィジェット拡張ではアプリの機能を実行できないので、操作はここ(アプリ本体)で行う
        .onOpenURL { url in
            handleWidgetURL(url)
        }
    }

    /// ウィジェットからのディープリンク(WatchWidgetAction)を実行する
    private func handleWidgetURL(_ url: URL) {
        guard let action = WatchWidgetAction(url: url) else { return }
        switch action {
        case .togglePlayPause:
            // 再生コントロール画面を出して、現在の発話元(iPhone/Watch単体)の再生をトグルする
            tabSelection = 1
            player.toggleForWidgetLaunch()
        case .openTextPage:
            tabSelection = 2
        case .checkUpdatesAll:
            // 更新確認は本棚に「同期中…」等が出るので本棚を表示してから依頼する
            tabSelection = 0
            session.send(.checkUpdatesAll)
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

    private var isFolderSelectionPresented: Binding<Bool> {
        Binding(
            get: { player.folderSelectionRequest != nil },
            set: { presented in
                if !presented {
                    player.folderSelectionRequest = nil
                }
            }
        )
    }
}
