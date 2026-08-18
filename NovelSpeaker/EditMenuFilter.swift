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

    /// 「本文中の長押しメニュー項目を減らす」が有効なら「残す対象のセレクタ名」の集合を返す。
    /// 無効なら nil を返す(= 何も削減しない)。
    static func keepSelectorNamesIfReducing() -> Set<String>? {
        return RealmUtil.RealmBlock { (realm) -> Set<String>? in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
                , globalState.isMenuItemIsAddNovelSpeakerItemsOnly else { return nil }
            var result = novelSpeakerAlwaysKeepSelectorNames
            for typeName in globalState.menuItemsNotRemoved {
                guard let type = MenuItemsNotRemovedType(rawValue: typeName) else { continue }
                result.formUnion(type.selectorNames)
            }
            return result
        }
    }

    /// canPerformAction(_:withSender:) 用の判定。
    /// 削減設定が無効なら常に true、有効なら keepSelectorNames に含まれる物だけ true。
    static func isAllowedForCanPerformAction(action: Selector) -> Bool {
        guard let keepSelectorNames = keepSelectorNamesIfReducing() else { return true }
        return keepSelectorNames.contains(action.description)
    }

    /// UIMenuElement を再帰的に選別する。残す物が無くなった UIMenu は nil を返す(= その階層ごと消す)。
    /// UICommand 以外(UIAction / UIDeferredMenuElement 等)はセレクタで判別できない
    /// = こちらが知らない項目なので落とす。
    static func filter(element: UIMenuElement, keepSelectorNames: Set<String>) -> UIMenuElement? {
        if let menu = element as? UIMenu {
            let children = menu.children.compactMap { filter(element: $0, keepSelectorNames: keepSelectorNames) }
            if children.isEmpty { return nil }
            return menu.replacingChildren(children)
        }
        if let command = element as? UICommand {
            return keepSelectorNames.contains(NSStringFromSelector(command.action)) ? command : nil
        }
        return nil
    }

    /// UITextViewDelegate.textView(_:editMenuForTextIn:suggestedActions:) 用。
    /// 削減設定が無効な場合は suggestedActions をそのまま返す。
    @available(iOS 16.0, *)
    static func filteredSuggestedActions(_ suggestedActions: [UIMenuElement]) -> [UIMenuElement] {
        guard let keepSelectorNames = keepSelectorNamesIfReducing() else { return suggestedActions }
        return suggestedActions.compactMap { filter(element: $0, keepSelectorNames: keepSelectorNames) }
    }

    /// UIResponder.buildMenu(with:) 用(WKWebView 側にはこちらしか手段が無い)。
    /// .context システム(長押しで出る編集メニュー)以外は触らない。
    @available(iOS 16.0, *)
    static func apply(builder: UIMenuBuilder) {
        guard builder.system == .context else { return }
        guard let keepSelectorNames = keepSelectorNamesIfReducing() else { return }
        // 個々のメニュー識別子を決め打ちで並べるのではなく .root から辿る。
        // こうしておけば OS が新しいトップレベルメニューを増やしても取りこぼさない。
        guard let root = builder.menu(for: .root) else { return }
        for child in root.children {
            guard let menu = child as? UIMenu else { continue }
            let children = menu.children.compactMap { filter(element: $0, keepSelectorNames: keepSelectorNames) }
            if children.isEmpty {
                builder.remove(menu: menu.identifier)
            } else {
                builder.replaceChildren(ofMenu: menu.identifier) { _ in children }
            }
        }
    }
}
