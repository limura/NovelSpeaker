//
//  MaxWidthButton.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2026/03/02.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

final class MaxWidthButton: UIButton {
    var maxWidth: CGFloat = .greatestFiniteMagnitude

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: min(size.width, maxWidth),
                      height: size.height)
    }
}
