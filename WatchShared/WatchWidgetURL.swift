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

    /// 独自 URL スキーム(ウィジェット→アプリのディープリンク専用)
    static let scheme = "novelspeakerwatch"

    private var host: String {
        switch self {
        case .togglePlayPause: return "toggle"
        case .openTextPage:    return "textPage"
        case .checkUpdatesAll: return "checkUpdates"
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = WatchWidgetAction.scheme
        components.host = host
        // host だけの単純な URL なので生成に失敗することはない
        return components.url ?? URL(string: "\(WatchWidgetAction.scheme)://\(host)")!
    }

    init?(url: URL) {
        guard url.scheme == WatchWidgetAction.scheme else { return nil }
        switch url.host {
        case "toggle":       self = .togglePlayPause
        case "textPage":     self = .openTextPage
        case "checkUpdates": self = .checkUpdatesAll
        default:             return nil
        }
    }
}
