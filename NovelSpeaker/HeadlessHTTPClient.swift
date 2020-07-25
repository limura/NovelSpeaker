//
//  HeadlessHTTPClient.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/05/14.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import WebKit
import Erik

class HeadlessHttpClient {
    var webView : WKWebView!
    var erik:Erik!
    
    static let shared = HeadlessHttpClient()

    private init(config:WKWebViewConfiguration? = nil) {
        ReloadWebView(config: config)
    }
    deinit {
        dispatch_sync_on_main_thread {
            self.webView.removeFromSuperview()
        }
    }
    
    func ReloadWebView(config:WKWebViewConfiguration?){
        dispatch_sync_on_main_thread {
            let wkConfig:WKWebViewConfiguration
            if let config = config {
                wkConfig = config
            }else{
                wkConfig = WKWebViewConfiguration()
            }
            let frame = CGRect(x: 0, y: 0, width: 1024, height: 1366)
            self.webView = WKWebView(frame: frame, configuration: wkConfig)
            erik = Erik(webView: self.webView)
            if let window = UIApplication.shared.keyWindow {
                self.webView.alpha = 0.0001
                window.insertSubview(self.webView, at: 0)
            } else {
                print("Erik initialize failed.")
            }
        }
    }
    
    func dispatch_sync_on_main_thread(_ block: ()->()) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync(execute: block)
        }
    }
    
    func generateUrlRequest(url:URL, postData:Data? = nil, timeoutInterval:TimeInterval = 10, cookieString:String? = nil, mainDocumentURL:URL? = nil, allowsCellularAccess:Bool = true) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeoutInterval)
        if let cookieString = cookieString {
            request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }
        request.allowsCellularAccess = allowsCellularAccess
        request.mainDocumentURL = mainDocumentURL
        if let postData = postData {
            request.httpMethod = "POST"
            request.httpBody = postData
        }
        return request
    }
    
    public func HttpRequest(url:URL, postData:Data? = nil, timeoutInterval:TimeInterval = 10, cookieString:String? = nil, mainDocumentURL:URL? = nil, allowsCellularAccess:Bool = true, successResultHandler:((Document) -> Void)? = nil, errorResultHandler:((Error) -> Void)? = nil) {
        DispatchQueue.main.async {
            let request = self.generateUrlRequest(url: url, postData: postData, timeoutInterval: timeoutInterval, cookieString: cookieString, mainDocumentURL: mainDocumentURL)
            self.erik.load(urlRequest: request) { (document, err) in
                if let err = err {
                    errorResultHandler?(err)
                    return
                }
                guard let doc = document else {
                    let err = NSError(domain: "com.limuraproducts.headlesshttpclient", code: 0, userInfo: [NSLocalizedDescriptionKey: "doc = nil"])
                    errorResultHandler?(err)
                    return
                }
                successResultHandler?(doc)
            }
        }
    }
    
    public func GetCurrentContent(completionHandler:((Document?, Error?)->Void)?) {
        self.erik.currentContent(completionHandler: { (doc, err) in
            completionHandler?(doc, err)
        })
    }
    
    public func GetCurrentURL() -> URL? {
        return self.erik.url
    }
    
    public func GetCurrentCookieString(resultHandler:((String?, Error?)->Void)?) {
        self.erik.evaluate(javaScript: "document.cookie") { (data, error) in
            if let error = error {
                resultHandler?(nil, error)
            }else if let resultString = data as? String {
                resultHandler?(resultString, nil)
            }
            resultHandler?(nil, SloppyError(msg: "cookie not found."))
        }
    }
}
