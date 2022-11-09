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
    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if StorySpeaker.shared.isPlayng {
            return false
        }
        #if false
        print("\"\(action.description)\",")
        let passTarget = [
            "cut:",
            "copy:",
            "paste:",
            "delete:",
            "select:",
            "selectAll:",
            "_promptForReplace:",
            "_transliterateChinese:",
            "_insertDrawing:",
            "captureTextFromCamera:",
            "toggleBoldface:",
            "toggleItalics:",
            "toggleUnderline:",
            "makeTextWritingDirectionRightToLeft:",
            "makeTextWritingDirectionLeftToRight:",
            "_findSelected:",
            "_define:",
            "_translate:",
            "_addShortcut:", // Webを検索
            "_accessibilitySpeak:", // 読み上げ
            "_accessibilitySpeakSpellOut:", // スペル
            "_share:",
            "setSpeechModSettingWithSender:",
            "setSpeechModForThisNovelSettingWithSender:",
            "checkSpeechTextWithSender:",
        ]
        if passTarget.contains(action.description) {
            return super.canPerformAction(action, withSender: sender)
        }
        return false
        #endif
        
        return RealmUtil.RealmBlock { (realm) -> Bool in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if globalState.isMenuItemIsAddNovelSpeakerItemsOnly {
                    for typeName in globalState.menuItemsNotRemoved {
                        if let type = MenuItemsNotRemovedType(rawValue: typeName), type.isTargetSelector(selector: action) {
                            return super.canPerformAction(action, withSender: sender)
                        }
                    }
                    return false
                }
            }
            return super.canPerformAction(action, withSender: sender);
        }
    }
}
