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
    private static let lock = NSLock()
    private static var enableIDSet = Set<String>()
    
    private static func apply() {
        DispatchQueue.main.async {
            lock.lock()
            defer { lock.unlock() }
            // TODO: isNetworkActivityIndicatorVisible は deprecated なんだけども、FTLinearActivityIndicator を使うにはこいつを使わないと駄目な感じな気がするのでそのまま使っています。
            if enableIDSet.count > 0 {
                UIApplication.shared.isNetworkActivityIndicatorVisible = true
            }else{
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
        }
    }
    
    static func enable(id:String) {
        lock.lock()
        if enableIDSet.contains(id) {
            lock.unlock()
            return
        }
        enableIDSet.insert(id)
        lock.unlock()
        apply()
    }
    
    static func disable(id:String) {
        lock.lock()
        if enableIDSet.contains(id) {
            enableIDSet.remove(id)
            lock.unlock()
            apply()
            return
        }
        lock.unlock()
    }
    
    static func isEnable(id:String) ->Bool {
        return enableIDSet.contains(id)
    }
}
