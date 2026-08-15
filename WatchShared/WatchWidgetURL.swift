//
//  WatchWidgetURL.swift
//  NovelSpeaker
//
//  文字盤コンプリケーション(ウィジェット)のタップで ことせかい アプリを起動し、
//  アプリ側で実行させたい操作を表す。widgetURL のディープリンクとして URL に往復させる。
//
//  watchOS のウィジェット拡張プロセスでは「アプリの機能を使う操作」が完結できない
//  (WCSession は activate できず、発話しても音が出ない)。そのため操作系のウィジェットは
//  Button(intent:) ではなく widgetURL でアプリを起動し、アプリ本体のプロセスで実行する。
//  詳細は調査メモ(TODO_AppleWatch_調査メモ.md)と watchos-interactive-widget-gotchas 参照。
//
//  Foundation 以外に依存しないこと(WatchShared の他ファイルと同様。ウィジェット拡張と
//  アプリ本体の両ターゲットでコンパイルされる)。
//

import Foundation

/// ウィジェットのタップでアプリに実行させる操作
enum WatchWidgetAction: Equatable {
    /// 再生/一時停止のトグル(現在の発話元 iPhone/Watch 単体 に対して)
    case togglePlayPause
    /// 本文ページを開く
    case openTextPage
    /// すべての小説の更新を確認する(iPhone 側で更新チェック)
    case checkUpdatesAll
    /// 指定した小説を再生する(設定可能ウィジェット「この小説を再生」)。現在の発話元で再生する
    case playNovel(novelID: String)
    /// Watch 単体再生モードに切り替えて再生を開始する
    case playOnWatch
    /// iPhone での再生に切り替えて再生を開始する
    case playOnPhone

    /// 独自 URL スキーム(ウィジェット→アプリのディープリンク専用)
    static let scheme = "novelspeakerwatch"
    private static let novelIDQueryName = "novelID"

    private var host: String {
        switch self {
        case .togglePlayPause: return "toggle"
        case .openTextPage:    return "textPage"
        case .checkUpdatesAll: return "checkUpdates"
        case .playNovel:       return "play"
        case .playOnWatch:     return "playWatch"
        case .playOnPhone:     return "playPhone"
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = WatchWidgetAction.scheme
        components.host = host
        if case .playNovel(let novelID) = self {
            components.queryItems = [URLQueryItem(name: WatchWidgetAction.novelIDQueryName, value: novelID)]
        }
        // host だけ(または host+novelID)の単純な URL なので生成に失敗することはない
        return components.url ?? URL(string: "\(WatchWidgetAction.scheme)://\(host)")!
    }

    init?(url: URL) {
        guard url.scheme == WatchWidgetAction.scheme else { return nil }
        switch url.host {
        case "toggle":       self = .togglePlayPause
        case "textPage":     self = .openTextPage
        case "checkUpdates": self = .checkUpdatesAll
        case "play":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let novelID = components.queryItems?
                    .first(where: { $0.name == WatchWidgetAction.novelIDQueryName })?.value,
                  !novelID.isEmpty else { return nil }
            self = .playNovel(novelID: novelID)
        case "playWatch":    self = .playOnWatch
        case "playPhone":    self = .playOnPhone
        default:             return nil
        }
    }
}
