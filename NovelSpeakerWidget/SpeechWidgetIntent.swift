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
