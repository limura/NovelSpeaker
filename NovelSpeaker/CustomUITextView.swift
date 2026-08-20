//
//  CustomUITextView.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2017/05/10.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import Foundation
import UIKit
import RealmSwift

public class CustomUITextView: UITextView {
    // 発話位置への自動スクロール(と強制範囲選択)が一時停止している間だけ true になります。
    // 一時停止中はアプリ側が selectedRange を代入しないので、
    // 「selectedRange を代入するとメニューのバルーンが勝手に出て消費電力が激増する」という
    // 過去にOSのメジャーバージョンアップで踏んだ問題の発火条件がそもそも成立しません。
    // (だからこそ、長押しメニューを通すのはこの間だけに限定しています)
    public var isScrollFollowSuspended: Bool = false
    // 一時停止中にだけ表示する「ここから発話開始」の selector。
    public var speakFromHereSelector: Selector? = nil
    // canPerformAction で true を返すと、UIKit は「この UITextView 自身が action を実行できる」と
    // 判断して action をこちらへ送ってくる。実装は ViewController 側にあるので、
    // 送り先を明示しておかないと unrecognized selector で落ちる。
    public weak var speakFromHereTarget: AnyObject? = nil

    override public func target(forAction action: Selector, withSender sender: Any?) -> Any? {
        if let speakFromHereSelector = self.speakFromHereSelector, action == speakFromHereSelector {
            return self.speakFromHereTarget
        }
        return super.target(forAction: action, withSender: sender)
    }

    // UITextView で長押しして出て来るメニューの項目を減らします
    // from http://qiita.com/watt1006/items/2425bfa1720d522d05fd
    //
    // iOS 16 以降は SpeechViewController の
    // textView(_:editMenuForTextIn:suggestedActions:) 側でメニューのツリーを走査して
    // 選別するため、こちらは主に iOS 15 用の経路になる。
    // (どちらも EditMenuFilter の同じ判定を使うので結果は一致する)
    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 「ここから発話開始」は「発話中 かつ 自動スクロールが一時停止中」の時だけ出します。
        // 発話中の長押しメニューは(上記の理由で)全部潰しているので、ここを通した1項目だけが表示され、
        // 結果として狭い端末でもページ送り(">")の奥に沈まずそのまま押せます。
        if let speakFromHereSelector = self.speakFromHereSelector, action == speakFromHereSelector {
            return StorySpeaker.shared.isPlayng && self.isScrollFollowSuspended
        }
        if StorySpeaker.shared.isPlayng {
            return false
        }
        if !EditMenuFilter.isAllowedForCanPerformAction(action: action) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
