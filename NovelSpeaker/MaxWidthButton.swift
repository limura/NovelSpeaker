//
//  MaxWidthButton.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2026/03/02.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

final class MaxWidthButton: UIButton {
    var maxWidth: CGFloat = .greatestFiniteMagnitude {
        didSet {
            if oldValue != maxWidth { invalidateIntrinsicContentSize() }
        }
    }

    var unconstrainedIntrinsicContentSize: CGSize { super.intrinsicContentSize }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: min(size.width, maxWidth),
                      height: size.height)
    }
}
