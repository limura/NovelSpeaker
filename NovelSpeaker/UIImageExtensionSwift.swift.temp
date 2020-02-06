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
        let wRatio:CGFloat = newSize.width / self.size.width;
        let hRatio:CGFloat = newSize.height / self.size.height;
        let ratio:CGFloat = wRatio < hRatio ? wRatio : hRatio;
        let targetSize = CGSize(width: self.size.width * ratio, height: self.size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0);
        draw(in: CGRect(x: 0.0, y: 0.0, width: targetSize.width, height: targetSize.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
}
