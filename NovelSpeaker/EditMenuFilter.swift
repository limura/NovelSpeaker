//
//  EditMenuFilter.swift
//  NovelSpeaker
//
//  本文表示部(SpeechViewController の UITextView / WebSpeechViewController の WKWebView)で
//  長押しした時に出る編集メニューの項目を、「本文中の長押しメニュー項目を減らす」設定に従って選別する。
//
//  Created by 飯村卓司 on 2026/08/18.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import Foundation
import UIKit

/// 長押しメニュー(編集メニュー)の項目選別。
///
/// iOS 15 までは canPerformAction(_:withSender:) でセレクタ名を見て弾くしか無く、
/// 「こちらが知っているセレクタ名の項目しか制御できない」= OS が増やした項目を取りこぼす、
/// という問題があった。
///
/// iOS 16 以降は編集メニューが UIMenuElement のツリーとして取れるようになったので、
/// そのツリーを走査して「残すと指定された物以外を全部落とす」方式にできる。
/// こうすると将来 OS が項目を増やしても自動的に消えるため、取りこぼしが原理的に無くなる。
///
/// - UITextView: UITextViewDelegate.textView(_:editMenuForTextIn:suggestedActions:) の suggestedActions
/// - WKWebView : UIResponder.buildMenu(with:) に .context システムで渡ってくる UIMenuBuilder
///
/// どちらも末端は UICommand で、実行される Selector が取れるため、
/// MenuItemsNotRemovedType のセレクタ名一覧と突き合わせて選別できる。
enum EditMenuFilter {
    /// ことせかい が独自に追加しているメニュー項目のセレクタ名。
    /// 「長押しメニュー項目を減らす」は元々「読み替え辞書へ登録だけにする」設定なので、
    /// これらは削減設定に関わらず常に残す。
    /// (「全てを選択する」だけは MenuItemsNotRemovedType.selectAll で個別に制御する)
    static let novelSpeakerAlwaysKeepSelectorNames: Set<String> = [
        "setSpeechModSettingWithSender:",
        "setSpeechModForThisNovelSettingWithSender:",
        "checkSpeechTextWithSender:",
    ]

    /// 残す対象。セレクタ名で判別する物と、identifier で判別する物(UIAction)がある。
    struct KeepSet {
        let selectorNames: Set<String>
        let actionIdentifiers: Set<String>
    }

    /// 「本文中の長押しメニュー項目を減らす」が有効なら「残す対象」を返す。
    /// 無効なら nil を返す(= 何も削減しない)。
    static func keepSetIfReducing() -> KeepSet? {
        return RealmUtil.RealmBlock { (realm) -> KeepSet? in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
                , globalState.isMenuItemIsAddNovelSpeakerItemsOnly else { return nil }
            var result = novelSpeakerAlwaysKeepSelectorNames
            var actionIdentifiers = Set<String>()
            for typeName in globalState.menuItemsNotRemoved {
                guard let type = MenuItemsNotRemovedType(rawValue: typeName) else { continue }
                actionIdentifiers.formUnion(type.actionIdentifiers)
                result.formUnion(type.selectorNames)
            }
            return KeepSet(selectorNames: result, actionIdentifiers: actionIdentifiers)
        }
    }

    /// canPerformAction(_:withSender:) 用の判定。
    /// 削減設定が無効なら常に true、有効なら残す対象のセレクタ名に含まれる物だけ true。
    /// (UIAction は canPerformAction を通らないのでここでは関係しない)
    static func isAllowedForCanPerformAction(action: Selector) -> Bool {
        guard let keepSet = keepSetIfReducing() else { return true }
        return keepSet.selectorNames.contains(action.description)
    }

    /// UIMenuElement を再帰的に選別する。残す物が無くなった UIMenu は nil を返す(= その階層ごと消す)。
    /// UICommand 以外(UIAction / UIDeferredMenuElement 等)はセレクタで判別できない
    /// = こちらが知らない項目なので落とす。
    static func filter(element: UIMenuElement, keepSet: KeepSet) -> UIMenuElement? {
        if let menu = element as? UIMenu {
            let children = menu.children.compactMap { filter(element: $0, keepSet: keepSet) }
            if children.isEmpty { return nil }
            return menu.replacingChildren(children)
        }
        // UIAction は UICommand の仲間ではなく、セレクタを持たない別物なので identifier で判別する。
        if let action = element as? UIAction {
            return keepSet.actionIdentifiers.contains(action.identifier.rawValue) ? action : nil
        }
        if let command = element as? UICommand {
            return keepSet.selectorNames.contains(NSStringFromSelector(command.action)) ? command : nil
        }
        return nil
    }

    /// 指定したセレクタ名の項目だけを取り除く(削減設定が無効な時に使う)。
    /// 残す物が無くなった UIMenu は nil を返す(= その階層ごと消す)。
    @available(iOS 16.0, *)
    static func removing(selectorNames: Set<String>, from element: UIMenuElement) -> UIMenuElement? {
        if let menu = element as? UIMenu {
            let children = menu.children.compactMap { removing(selectorNames: selectorNames, from: $0) }
            if children.isEmpty { return nil }
            return menu.replacingChildren(children)
        }
        // UIAction はセレクタを持たないので対象外(そのまま残す)。
        if let command = element as? UICommand, (element as? UIAction) == nil {
            return selectorNames.contains(NSStringFromSelector(command.action)) ? nil : command
        }
        return element
    }

    /// UITextViewDelegate.textView(_:editMenuForTextIn:suggestedActions:) 用。
    /// 削減設定が無効な場合でも、「ここから発話開始」だけは必ず取り除く。
    /// この項目は発話中に(メニューごと差し替える形で)出す物で、
    /// 発話していない時に選ばれても何も起こらないため、出してはいけない。
    /// (UIMenuController.shared.menuItems には常に登録してあるので、
    ///  何もしないと suggestedActions に混ざって出てきてしまう)
    @available(iOS 16.0, *)
    static func filteredSuggestedActions(_ suggestedActions: [UIMenuElement]) -> [UIMenuElement] {
        guard let keepSet = keepSetIfReducing() else {
            return suggestedActions.compactMap { removing(selectorNames: novelSpeakerOtherSelectorNames, from: $0) }
        }
        return suggestedActions.compactMap { filter(element: $0, keepSet: keepSet) }
    }

    // MARK: 実機で実際のメニューを集めるためのダンプ

    // 長押しメニューに出てくる項目は、選択している文字列や端末の状況で変わる。
    //   ・Apple Intelligence の有無(作文ツール)
    //   ・選択した文字列の言語(简⇄繁、書字方向)や、置き換え候補の有無
    //   ・データ検出(URL/電話番号/日付など。WebView 側で起こり得る)
    //   ・iOS のバージョン
    // 手元のシミュレータでは再現できない項目があり(作文ツールは Apple Intelligence が
    // 無い端末では出てこない)、机上では網羅できない。
    // そこで、実機で実際のツリーを集められるようにしておく。
    //
    // 「設定タブ」の隠しデバッグ欄で有効にすると、長押しのたびに
    // 「設定タブ」→「アプリ内エラーのお知らせ」へツリーを書き出す。
    // そこからコピーして持ち出せる。
    static let isDumpEditMenuEnabledKey = "NovelSpeaker_IsDumpEditMenuEnabled"
    static func IsDumpEditMenuEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: isDumpEditMenuEnabledKey)
    }
    static func SetIsDumpEditMenuEnabled(_ newValue:Bool) {
        UserDefaults.standard.set(newValue, forKey: isDumpEditMenuEnabledKey)
    }

    /// 削減設定とは別枠で ことせかい が出している項目。
    /// 「ここから発話開始」は発話中にメニューごと差し替えて出しているので削減設定の対象外。
    /// ダンプで「未知」と誤って印字しないためだけに使う。
    static let novelSpeakerOtherSelectorNames: Set<String> = [
        "speakFromHereWithSender:",
    ]

    /// MenuItemsNotRemovedType が知っているセレクタ名の全集合。
    /// ここに無い物は「残される長押しメニュー項目」で選べない = 取りこぼしなので、
    /// ダンプで目立つように印を付ける。
    static var knownSelectorNames: Set<String> {
        var result = novelSpeakerAlwaysKeepSelectorNames
        result.formUnion(novelSpeakerOtherSelectorNames)
        for type in MenuItemsNotRemovedType.allCases {
            result.formUnion(type.selectorNames)
        }
        return result
    }

    /// MenuItemsNotRemovedType が知っている UIAction の identifier の全集合。
    static var knownActionIdentifiers: Set<String> {
        var result = Set<String>()
        for type in MenuItemsNotRemovedType.allCases {
            result.formUnion(type.actionIdentifiers)
        }
        return result
    }

    /// 長押しメニューのツリーを「アプリ内エラーのお知らせ」へ書き出す。
    /// - Parameters:
    ///   - elements: 選別する前のツリー(suggestedActions や builder.menu(for: .root)?.children)
    ///   - sourceName: どちらの本文表示から来たか
    ///   - selectedText: 選択されていた文字列(条件を後から見分けるため。先頭だけ記録する)
    @available(iOS 16.0, *)
    static func DumpEditMenuIfNeeded(elements: [UIMenuElement], sourceName: String, selectedText: String?) {
        if IsDumpEditMenuEnabled() == false { return }
        let knownSelectorNames = self.knownSelectorNames
        var lines:[String] = []
        func walk(_ element: UIMenuElement, indent: String) {
            if let menu = element as? UIMenu {
                lines.append("\(indent)UIMenu \(menu.identifier.rawValue) \"\(menu.title)\"")
                for child in menu.children {
                    walk(child, indent: indent + "  ")
                }
                return
            }
            if let command = element as? UICommand {
                let selectorName = NSStringFromSelector(command.action)
                let mark = knownSelectorNames.contains(selectorName) ? "" : "   ★未知"
                lines.append("\(indent)UICommand \(selectorName) \"\(command.title)\"\(mark)")
                return
            }
            // UIAction はセレクタを持たない(ハンドラ直結)ので、新方式では落とされる。
            // WebKit がリンク選択時に足してくる「強調表示部分のリンクをコピー」等がこれに当たる。
            // identifier で見分けられる可能性があるので記録しておく。
            if let action = element as? UIAction {
                let mark = knownActionIdentifiers.contains(action.identifier.rawValue) ? "" : "   ★未知(セレクタが取れない)"
                lines.append("\(indent)UIAction identifier=\"\(action.identifier.rawValue)\" \"\(action.title)\"\(mark)")
                return
            }
            // UIDeferredMenuElement 等。何が来ているのかを見るために記録しておく。
            lines.append("\(indent)\(type(of: element)) \"\(element.title)\"   ★未知(セレクタが取れない)")
        }
        for element in elements {
            walk(element, indent: "")
        }
        if lines.isEmpty { return }
        var appendix:[String:String] = ["source": sourceName]
        if let selectedText = selectedText, selectedText.count > 0 {
            appendix["selected"] = String(selectedText.prefix(32))
        }
        AppInformationLogger.AddLog(message: "長押しメニューの内容(デバッグ):\n" + lines.joined(separator: "\n"), appendix: appendix, isForDebug: false)
    }

    /// UIResponder.buildMenu(with:) 用(WKWebView 側にはこちらしか手段が無い)。
    /// .context システム(長押しで出る編集メニュー)以外は触らない。
    @available(iOS 16.0, *)
    static func apply(builder: UIMenuBuilder) {
        guard builder.system == .context else { return }
        guard let keepSet = keepSetIfReducing() else { return }
        // 個々のメニュー識別子を決め打ちで並べるのではなく .root から辿る。
        // こうしておけば OS が新しいトップレベルメニューを増やしても取りこぼさない。
        guard let root = builder.menu(for: .root) else { return }
        for child in root.children {
            guard let menu = child as? UIMenu else { continue }
            let children = menu.children.compactMap { filter(element: $0, keepSet: keepSet) }
            if children.isEmpty {
                builder.remove(menu: menu.identifier)
            } else {
                builder.replaceChildren(ofMenu: menu.identifier) { _ in children }
            }
        }
    }
}
