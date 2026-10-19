//
//  UIImageExtensionSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/19.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit

extension UIImage {
    func resize(newSize:CGSize) -> UIImage {
        guard newSize.width.isFinite, newSize.height.isFinite,
              newSize.width > 0, newSize.height > 0,
              size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return self }

        // 再生情報のアートワーク用。元画像より拡大せず、画面倍率にも依存させない。
        // OSから大きなサイズを要求されても、生成する画像は最大1024×1024ピクセルに抑える。
        let maximumDimension: CGFloat = 1024
        let ratio = min(1, newSize.width / size.width, newSize.height / size.height,
                        maximumDimension / max(size.width, size.height))
        let targetSize = CGSize(width: floor(size.width * ratio), height: floor(size.height * ratio))
        guard targetSize.width.isFinite, targetSize.height.isFinite,
              targetSize.width >= 1, targetSize.height >= 1 else { return self }
        if targetSize == size && scale == 1 { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
