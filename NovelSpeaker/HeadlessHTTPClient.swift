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
import Kanna

class HeadlessHttpClient {
    var webView : WKWebView!
    var erik:Erik!
    var config:WKWebViewConfiguration
    
    //static let shared = HeadlessHttpClient()

    init(config:WKWebViewConfiguration? = nil) {
        let wkConfig:WKWebViewConfiguration
        if let config = config {
            wkConfig = config
        }else{
            wkConfig = WKWebViewConfiguration()
        }
        self.config = wkConfig
        ReloadWebView(config: wkConfig)
    }
    deinit {
        dispatch_sync_on_main_thread {
            self.webView.removeFromSuperview()
        }
    }
    
    func ReloadWebView(config:WKWebViewConfiguration){
        dispatch_sync_on_main_thread {
            let frame = CGRect(x: 0, y: 0, width: 1024, height: 1366)
            self.webView = WKWebView(frame: frame, configuration: config)
            erik = Erik(webView: self.webView)
            if let window = UIApplication.shared.keyWindow {
                self.webView.alpha = 0.0001
                window.insertSubview(self.webView, at: 0)
                //print("Erik initialize done.")
            } else {
                //print("Erik initialize failed.")
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
            let requestID = "HTTPRequest" + url.absoluteString
            ActivityIndicatorManager.enable(id: requestID)
            let request = self.generateUrlRequest(url: url, postData: postData, timeoutInterval: timeoutInterval, cookieString: cookieString, mainDocumentURL: mainDocumentURL)
            self.erik.load(urlRequest: request) { (document, err) in
                ActivityIndicatorManager.disable(id: requestID)
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
        ExecuteJavaScript(javaScript: "document.cookie", resultHandler: resultHandler)
    }
    // 怪しく末尾までスクロールさせます
    public func ScrollToButtom(resultHandler:((String?, Error?)->Void)?){
        ExecuteJavaScript(javaScript: "window.scroll(0, document.documentElement.scrollHeight)", resultHandler: resultHandler)
    }
    public func ExecuteJavaScript(javaScript:String, resultHandler:((String?, Error?)->Void)?){
        self.erik.evaluate(javaScript: javaScript) { (data, error) in
            if let error = error {
                resultHandler?(nil, error)
            }else if let resultString = data as? String {
                resultHandler?(resultString, nil)
            }
            resultHandler?(nil, SloppyError(msg: "execute JavaScript(\"\(javaScript)\") error."))
        }
    }
    
    public func LoadAboutPage() {
        self.erik.visit(urlString: "about:blank", completionHandler: nil)
    }
    
    // ErikのUserAgentを取得します。
    // WARN: 一回取得したら起動している間は無闇にJavaScriptを呼び出さないようにしています。
    // そのため、WKWebViewConfiguration で UserAgent を上書きしたりする運用をしている場合には誤動作します。
    static var userAgentCache:String? = nil
    public func GetUserAgent(resultHandler:((String?, Error?)->Void)?) {
        if let userAgent = HeadlessHttpClient.userAgentCache {
            resultHandler?(userAgent, nil)
            return
        }
        ExecuteJavaScript(javaScript: "navigator.userAgent", resultHandler: { (userAgent, err) in
            if let userAgent = userAgent {
                HeadlessHttpClient.userAgentCache = userAgent
            }
            resultHandler?(userAgent, err)
        })
    }
    
    func getAllCookies(completionHandler:@escaping (([HTTPCookie]?)->Void)) {
        if #available(iOS 11.0, *) {
            self.config.websiteDataStore.httpCookieStore.getAllCookies(completionHandler)
        } else {
            completionHandler(nil)
        }
    }
    
    func injectCookie(cookie:HTTPCookie, completionHandler:(()->Void)? = nil) -> Bool {
        if #available(iOS 11.0, *) {
            let cookieStore = self.config.websiteDataStore.httpCookieStore
            cookieStore.setCookie(cookie, completionHandler: completionHandler)
            return true
        } else {
            return false
        }
    }
    
    func AssignCookieArray(cookieArray:[HTTPCookie], completionHandler:(()->Void)? = nil) {
        if cookieArray.count <= 0 {
            completionHandler?()
            return
        }
        DispatchQueue.main.async {
            let semaphore = DispatchSemaphore(value: cookieArray.count)
            for cookie in cookieArray {
                DispatchQueue.main.async {
                    if self.injectCookie(cookie: cookie, completionHandler: {semaphore.signal()}) == false {
                        semaphore.signal()
                    }
                }
            }
            semaphore.wait()
            completionHandler?()
        }
    }
    
    func dumpAllCookies() {
        getAllCookies { (cookieArray) in
            guard let cookieArray = cookieArray else {
                print("getAllCookies return error.")
                return
            }
            for cookie in cookieArray {
                print(cookie.description)
            }
        }
    }
    
    func removeAllCookies(completionHandler:(()->Void)? = nil) {
        self.getAllCookies { (cookieArray) in
            guard let cookieArray = cookieArray else {
                print("removeAllCookies getAllCookies failed.")
                completionHandler?()
                return
            }
            if cookieArray.count <= 0 {
                print("removeAllCookies cookieArray.count <= 0")
                completionHandler?()
                return
            }
            if #available(iOS 11.0, *) {
                let cookieStore = self.config.websiteDataStore.httpCookieStore
                DispatchQueue.main.async {
                    let semaphore = DispatchSemaphore(value: cookieArray.count)
                    for cookie in cookieArray {
                        cookieStore.delete(cookie, completionHandler: { semaphore.signal()})
                    }
                    semaphore.wait()
                    completionHandler?()
                }
            }else{
                print("removeAllCookies error. iOS 11.0 >= self")
                completionHandler?()
            }
        }
    }
}
