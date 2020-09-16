//
//  RealmObserverHandler.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/09/16.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

protocol RealmObserverResetDelegate {
    func StopObservers()
    func RestartObservers()
}

class RealmObserverHandler {
    static let shared = RealmObserverHandler()
    
    let lock = NSLock()
    var delegateArray = NSHashTable<AnyObject>.weakObjects()
    
    func AddDelegate(delegate:RealmObserverResetDelegate){
        lock.lock()
        delegateArray.add(delegate as AnyObject)
        lock.unlock()
    }
    func RemoveDelegate(delegate:RealmObserverResetDelegate) {
        lock.lock()
        delegateArray.remove(delegate as AnyObject)
        lock.unlock()
    }
    
    func AnnounceStopObservers() {
        lock.lock()
        let objects = delegateArray.allObjects
        lock.unlock()
        for case let delegate as RealmObserverResetDelegate in objects {
            delegate.StopObservers()
        }
        RealmCloudVersionChecker.StopChecker()
    }
    func AnnounceRestartObservers() {
        lock.lock()
        let objects = delegateArray.allObjects
        lock.unlock()
        for case let delegate as RealmObserverResetDelegate in objects {
            delegate.RestartObservers()
        }
        RealmCloudVersionChecker.StopChecker()
    }
}
