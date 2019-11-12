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
    public required init?(coder: NSCoder) {
        if #available(iOS 13.2, *) {
            super.init(coder: coder)
        }
        else {
            super.init(frame: .zero, textContainer: nil)
            self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.contentMode = .scaleToFill

            self.isScrollEnabled = false   // causes expanding height

            // Auto Layout
            self.translatesAutoresizingMaskIntoConstraints = false
            self.font = UIFont(name: "HelveticaNeue", size: 18)

            // custom setting.
            self.isEditable = false
        }
    }
    
    // UITextView で長押しして出て来るメニューの項目を減らします
    // from http://qiita.com/watt1006/items/2425bfa1720d522d05fd
    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return autoreleasepool {
            if StorySpeaker.shared.isPlayng {
                return false
            }
            if RealmGlobalState.GetInstance()?.isMenuItemIsAddNovelSpeakerItemsOnly ?? false {
                return false
            }
            return super.canPerformAction(action, withSender: sender);
        }
    }
}
