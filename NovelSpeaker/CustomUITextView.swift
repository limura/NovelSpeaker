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
    // UITextView で長押しして出て来るメニューの項目を減らします
    // from http://qiita.com/watt1006/items/2425bfa1720d522d05fd
    //
    // iOS 16 以降は SpeechViewController の
    // textView(_:editMenuForTextIn:suggestedActions:) 側でメニューのツリーを走査して
    // 選別するため、こちらは主に iOS 15 用の経路になる。
    // (どちらも EditMenuFilter の同じ判定を使うので結果は一致する)
    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if StorySpeaker.shared.isPlayng {
            return false
        }
        if !EditMenuFilter.isAllowedForCanPerformAction(action: action) {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
