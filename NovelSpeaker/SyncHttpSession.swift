//
//  SyncHttpSession.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/12/18.
//  Copyright © 2018 IIMURA Takuji. All rights reserved.
//

import UIKit

@objc(SyncHttpSession)
class SyncHttpSession: NSObject {
    var sessionConfig = URLSessionConfiguration()
    var session:URLSession = URLSession()

    override init(){
        super.init()
        Initialize()
    }
    
    @objc public func Initialize(){
        sessionConfig = URLSessionConfiguration.default
        session = URLSession(configuration: sessionConfig)
    }
    
    @objc public func GetBinary(urlString:String) -> (Data?) {
        let url = URL(string: urlString)
        if let url = url {
            let semaphore = DispatchSemaphore.init(value: 1)
            var result:Data? = nil
            let task = session.dataTask(with: url, completionHandler: { (data, response, err) in
                defer {
                    semaphore.signal()
                }
                if let err = err {
                    print("SyncHttpSession.GetBinary() err: ", err.localizedDescription)
                    return
                }
                guard let data = data, let response = response as? HTTPURLResponse else {
                    print("SyncHttpSession.GetBinary() data == nil or response type != HTTPURLResponse")
                    return
                }
                if response.statusCode != 200 {
                    print("SyncHttpSession.GetBinary() error. HTTP status code != 200. ", response.statusCode.description)
                    return
                }
                result = data
            })
            task.resume()
            semaphore.wait()
            return result
        }else{
            return nil
        }
    }
    
    @objc public func GetString(urlString:String) -> (String?) {
        guard let data = GetBinary(urlString: urlString) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
