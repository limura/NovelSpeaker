//
//  SyncHttpSession.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/12/18.
//  Copyright © 2018 IIMURA Takuji. All rights reserved.
//

import UIKit

@objc(SyncHTTPSessionResult)
class SyncHTTPSessionResult: NSObject {
    var response:HTTPURLResponse? = nil
    var data:Data? = nil
    
    public func setResponse(response:HTTPURLResponse?) {
        self.response = response
    }
    public func setData(data:Data?) {
        self.data = data
    }
    
    @objc public func getResponse() -> HTTPURLResponse? {
        return self.response
    }
    @objc public func getData() -> Data? {
        return self.data
    }
}

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
    
    @objc public func GetBinary(urlString:String, headerDictionary:[String:String]?) -> (SyncHTTPSessionResult?) {
        let url = URL(string: urlString)
        let result = SyncHTTPSessionResult()
        if let url = url {
            let semaphore = DispatchSemaphore.init(value: 0)
            var resultResponse:HTTPURLResponse? = nil
            var request = URLRequest(url: url)
            if let headerDictionary = headerDictionary {
                for (key, value) in headerDictionary {
                    request.addValue(value, forHTTPHeaderField: key)
                }
            }
            let task = session.dataTask(with: request) { (data, response, err) in
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
                result.setResponse(response: response)
                if response.statusCode != 200 {
                    print("SyncHttpSession.GetBinary() error. HTTP status code != 200. ", response.statusCode.description)
                    return
                }
                result.setData(data: data)
            }
            task.resume()
            semaphore.wait()
            return result
        }else{
            return nil
        }
    }
    
    @objc public func GetBinary(urlString:String) -> (Data?) {
        if let result = GetBinary(urlString: urlString, headerDictionary: nil) {
            return result.getData()
        }
        return nil
    }
    
    @objc public func GetString(urlString:String, headerDictionary:[String:String]?) -> (String?) {
        guard let result = GetBinary(urlString: urlString, headerDictionary: headerDictionary) else {
            return nil
        }
        guard let data = result.getData() else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    @objc public func GetString(urlString:String) -> (String?) {
        return self.GetString(urlString: urlString, headerDictionary: nil)
    }
}
