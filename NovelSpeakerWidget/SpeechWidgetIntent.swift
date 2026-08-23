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

//  文言は WidgetLocalizable.strings に置いてある(Localizable.strings ではない)。
//
//  この場所の AppIntents はアプリ本体とウィジェット拡張の**両方**にコンパイルされ、
//  LocalizedStringResource は実行時に Bundle.main を見る。
//  拡張側の Localizable.strings に置くと、アプリ本体プロセス(ショートカット等)からは
//  鍵がそのまま表示されてしまう。かといって同じ文字列をアプリ側にも複製すると、
//  今度は片方だけ直る事故が起きる。
//  そこで **1つの .strings を両方のターゲットに入れて**、表の名前で参照している。
//
//  以前は日本語のリテラルをそのまま鍵にしていた(英語側だけ対訳表を持っていた)。
//  日本語を直すと鍵が変わって英語が黙って外れるうえ、同じ文言が
//  Localizable.strings とリテラルに散らばって、実際にずれ始めていた。

@available(iOS 17.0, *)
struct PhoneSpeechToggleIntent: AudioPlaybackIntent {
    static var title = LocalizedStringResource("Phone_Widget_PlayToggle_Name", table: "WidgetLocalizable")
    static var description = IntentDescription(LocalizedStringResource("Phone_Widget_PlayToggle_Desc", table: "WidgetLocalizable"))

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
    static var title = LocalizedStringResource("Phone_Widget_Launcher_Name", table: "WidgetLocalizable")
    static var description = IntentDescription(LocalizedStringResource("Phone_Widget_Launcher_ControlDesc", table: "WidgetLocalizable"))
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
    static var title = LocalizedStringResource("Phone_Widget_PlayNovel_Name", table: "WidgetLocalizable")
    static var description = IntentDescription(LocalizedStringResource("Phone_Widget_PlayNovel_ControlDesc", table: "WidgetLocalizable"))
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
