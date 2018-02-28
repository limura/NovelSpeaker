//
//  UIDeviceModelNameExtension.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/02/28.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit

extension UIDevice {
    class var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        
        return Mirror(reflecting: systemInfo.machine).children.flatMap { (child) -> String? in
            if let value = child.value as? Int8, value != 0 {
                return String(UnicodeScalar(UInt8(value)))
            } else {
                return nil
            }
            }.reduce(""){ $0 + $1 }
    }
}
