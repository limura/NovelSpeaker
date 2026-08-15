//
//  SpeechWidgetIntent.swift
//  NovelSpeaker
//
//  iPhone側ウィジェット(ホーム画面/ロック画面/コントロールセンター)の「再生・停止」intent。
//  このファイルはアプリ本体とウィジェット拡張の両方のターゲットでコンパイルされる。
//
//  AudioPlaybackIntent の perform() は iOS ではアプリ本体プロセスで実行される
//  (PoC/WidgetSpeechPoC で実機実証済み。watchOS では拡張プロセスだったのと異なる)。
//  そのためアプリを開かずにその場で再生・停止できる。
//

import AppIntents

@available(iOS 17.0, *)
struct PhoneSpeechToggleIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "再生または停止"
    static var description = IntentDescription("ことせかい を開かずに、読み上げの再生・停止をします。")

    func perform() async throws -> some IntentResult {
        #if NOVELSPEAKER_WIDGET_EXTENSION
        // ウィジェット拡張バイナリ側はダミー。AudioPlaybackIntent はアプリ本体プロセスで
        // 実行されるためここは呼ばれず、拡張に StorySpeaker 等をリンクしないで済ませている
        return .result()
        #else
        await WidgetPlaybackHandler.togglePlayPauseFromWidget()
        return .result()
        #endif
    }
}

/// ロック画面下部の角やコントロールセンターの「アプリの起動」コントロール用。
/// openAppWhenRun でアプリを開くだけ(iOS では有効。watchOS では無視されたのと違う)
@available(iOS 17.0, *)
struct PhoneOpenAppIntent: AppIntent {
    static var title: LocalizedStringResource = "アプリの起動"
    static var description = IntentDescription("ことせかい を開きます。")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

/// 「指定小説の再生を開始」ウィジェットのタップ用 intent。
/// ウィジェットの設定(小説・アイコン・色)は別の WidgetConfigurationIntent が持ち、
/// こちらはタップされた時に対象の novelID を運ぶだけ。ユーザが Shortcuts から
/// novelID を手入力しても意味が無いので isDiscoverable は切っておく
@available(iOS 17.0, *)
struct PhonePlayNovelIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "指定小説の再生を開始"
    static var description = IntentDescription("指定した小説の読み上げを、ことせかい を開かずに開始します。")
    static var isDiscoverable: Bool = false

    @Parameter(title: "novelID")
    var novelID: String?

    init() {}
    init(novelID: String) {
        self.novelID = novelID
    }

    func perform() async throws -> some IntentResult {
        #if NOVELSPEAKER_WIDGET_EXTENSION
        // PhoneSpeechToggleIntent と同じ理由のダミー
        return .result()
        #else
        if let novelID = novelID, !novelID.isEmpty {
            await WidgetPlaybackHandler.playNovelFromWidget(novelID: novelID)
        }
        return .result()
        #endif
    }
}
