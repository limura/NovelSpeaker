//
//  ActivityIndicatorManager.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/10.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import Foundation
import FTLinearActivityIndicator

class ActivityIndicatorManager {
    private static var enableIDSet = Set<String>()
    
    private static func apply() {
        DispatchQueue.main.async {
            if enableIDSet.count > 0 {
                UIApplication.shared.isNetworkActivityIndicatorVisible = true
            }else{
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
        }
    }
    
    static func enable(id:String) {
        if enableIDSet.contains(id) {
            return
        }
        enableIDSet.insert(id)
        apply()
    }
    
    static func disable(id:String) {
        if enableIDSet.contains(id) {
            enableIDSet.remove(id)
            apply()
        }
    }
}
