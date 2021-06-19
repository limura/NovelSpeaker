//
//  WebSpeechView.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/05/17.
//  Copyright © 2021 飯村卓司. All rights reserved.
//
// WKWebView 上に指定された文字列またはHTMLを表示しつつ、
// 読み上げ箇所更新イベントを受け取るとその読み上げ位置を表示する
//

/*
 TODO:
 - 横書きの時に読み上げ位置の自動スクロールがうまくいかない
 - 読み上げ位置の表示のための選択範囲表示がされていない場合に表示されない問題
 - 読み上げ位置がズレる問題
   - 上記の問題に関連して選択範囲から取得される読み上げ位置がズレているかもしれない
 - 読み替え辞書に登録のみにする、や、読み替え辞書に登録するが追加されていない
 
 正しいJavaScriptの注入方法ぽいのとか、JavaScript側のイベントハンドラをObjective-c側で受ける方法が書いてある
 https://stackoverflow.com/questions/50846404/how-do-i-get-the-selected-text-from-a-wkwebview-from-objective-c
 */

import UIKit
import WebKit

/// adding "console.log" support
/// from https://banrai-works.net/2019/01/13/%E3%80%90swift%E3%80%91wkwebview%E3%81%A7javascript%E3%81%AEconsole-log%E3%82%92%E4%BD%BF%E3%81%88%E3%82%8B%E3%82%88%E3%81%86%E3%81%AB%E3%81%99%E3%82%8B/
extension WKWebView: WKScriptMessageHandler {

    /// enabling console.log
    public func enableConsoleLog() {

        //    set message handler
        configuration.userContentController.add(self, name: "logging")

        //    override console.log
        let _override = WKUserScript(source: "var console = { log: function(msg){window.webkit.messageHandlers.logging.postMessage(msg) }};", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(_override)
    }
    
    func JavaScriptAnyToString(body:Any) -> String {
        if let number = body as? NSNumber {
            return "\(number)"
        }
        if let string = body as? String {
            return "\"\(string)\""
        }
        if let date = body as? NSDate {
            return "\(date)"
        }
        if let array = body as? NSArray {
            return array.reduce("[") { current, body in
                return current + ", " + JavaScriptAnyToString(body: body)
            } + "]"
        }
        if let dictionary = body as? NSDictionary {
            return dictionary.reduce("{\n") { current, element in
                return current + "\n" + "  \(JavaScriptAnyToString(body: element.key)): \(JavaScriptAnyToString(body: element.value))"
            } + "\n}\n"
        }
        if body is NSNull {
            return "null"
        }
        return "undefined"
    }

    /// message handler
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {

        print("WebViewConsole:", JavaScriptAnyToString(body: message.body))
    }
}

class WebSpeechViewTool: NSObject, WKNavigationDelegate {
    var wkWebView:WKWebView? = nil
    var loadCompletionHandler:(() -> Void)? = nil
    var siteInfoArray:[StorySiteInfo] = []
    
    func removeDelegate(){
        if let webView = self.wkWebView {
            webView.navigationDelegate = nil;
        }
    }
    
    public func loadHtmlString(webView:WKWebView, html:String, baseURL: URL?, siteInfoArray:[StorySiteInfo] = [], completionHandler:(() -> Void)?){
        removeDelegate()
        loadCompletionHandler = completionHandler
        self.wkWebView = webView
        self.siteInfoArray = siteInfoArray
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
    }
    
    public func loadUrl(webView:WKWebView, request:URLRequest, siteInfoArray:[StorySiteInfo] = [], completionHandler:(() -> Void)?){
        removeDelegate()
        loadCompletionHandler = completionHandler
        self.wkWebView = webView
        self.siteInfoArray = siteInfoArray
        webView.navigationDelegate = self
        webView.load(request)
    }
    
    func loadInjectScript() -> String? {
        guard let path = Bundle.main.path(forResource: "WebSpeechViewTool_Inject", ofType: "js") else { return nil }
        return try? String.init(contentsOfFile: path)
    }
    
    // WKWebView の読み込み完了ハンドラ
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.canBecomeFirstResponder {
            print("can become first responder")
            webView.becomeFirstResponder()
            webView.window?.makeKeyAndVisible()
        }else{
            print("can NOT become first responder")
        }
        let siteInfoJSONString:String
        if self.siteInfoArray.count > 0 {
            siteInfoJSONString = "[\(self.siteInfoArray.map({$0.generatePageElementOnlySiteInfoString()}).joined(separator: ","))]"
        }else{
            siteInfoJSONString = ""
        }
        let jsFunctions = loadInjectScript() ?? "";
        let jsString = jsFunctions.replacingOccurrences(of: "var elementArray = CreateElementArray();", with: "var elementArray = CreateElementArray(\(siteInfoJSONString));")
        // JavaScript関数群を色々注入しておく
        evaluateJsToString(jsString: jsString) { (result) in
            if let completionHandler = self.loadCompletionHandler {
                completionHandler()
            }
        }
    }
    
    func evaluateJsToString(jsString:String, completionHandler:((String?) -> Void)?){
        guard let wkWebView = self.wkWebView else {
            return
        }
        wkWebView.evaluateJavaScript(jsString) { (node, err) in
            var result:String? = nil;
            defer {
                if let completionHandler = completionHandler {
                    completionHandler(result)
                }
            }
            if let err = err {
                print("js err:", err.localizedDescription)
                print(jsString)
                return
            }
            guard let nodeString = node as? String else {
                print("js node == nil")
                return
            }
            result = nodeString
        }
    }
    func evaluateJsToDouble(jsString:String, completionHandler:((Double?) -> Void)?){
        guard let wkWebView = self.wkWebView else {
            return
        }
        wkWebView.evaluateJavaScript(jsString) { (node, err) in
            var result:Double? = nil;
            defer {
                if let completionHandler = completionHandler {
                    completionHandler(result)
                }
            }
            if let err = err {
                print("js err:", err.localizedDescription)
                print(jsString)
                return
            }
            guard let resultDouble = node as? Double else {
                print("js node == nil")
                return
            }
            result = resultDouble
        }
    }
    func evaluateJsToStringDoubleDictionary(jsString:String, completionHandler:(([String:Double]?) -> Void)?){
        guard let wkWebView = self.wkWebView else {
            return
        }
        wkWebView.evaluateJavaScript(jsString) { (node, err) in
            var result:[String:Double]? = nil;
            defer {
                completionHandler?(result)
            }
            if let err = err {
                print("js err:", err.localizedDescription)
                print(jsString)
                return
            }
            guard let resultDouble = node as? [String:Double] else {
                print("js node == nil")
                return
            }
            result = resultDouble
        }
    }

    
    func assignCSS(cssString:String){
        let oneLineCssString = cssString.replacingOccurrences(of: "\n|\r\n", with: "", options: .regularExpression, range: nil)
        let js = "var styleNode = document.createElement('style');styleNode.innerHTML = \"\(oneLineCssString)\";document.head.appendChild(styleNode); 'OK';"
        evaluateJsToString(jsString: js, completionHandler: nil)
    }
    
    func injectJS(jsString:String) {
        evaluateJsToString(jsString: jsString, completionHandler: nil)
    }
    
    func getSpeechText(completionHandler:((String?) -> Void)?) {
        evaluateJsToString(jsString: "GenerateWholeText(elementArray,0);", completionHandler: completionHandler)
    }
    func highlightSpeechLocation(location:Int, length:Int, scrollRatio: Double) {
        //evaluateJsToString(jsString: "HighlightFromIndex(\(location), \(length));\"OK\";", completionHandler: nil)
        evaluateJsToString(jsString: "HighlightFromIndex(\(location), \(length)); ScrollToIndex(\(location) + \(length), \(scrollRatio)); \"OK\";", completionHandler: nil)
    }
    func getSelectedLocation(completionHandler:((Int?)->Void)?){
        evaluateJsToDouble(jsString: "GetSelectedIndex();") { (result) in
            if let result = result, result.isNaN == false, result.isInfinite == false {
                completionHandler?(Int(result))
            }else{
                completionHandler?(nil)
            }
        }
    }
    func getSelectedString(completionHandler:((String?)->Void)?){
        evaluateJsToString(jsString: "GetSelectedString();") { result in
            completionHandler?(result)
        }
    }
    func getSelectedRange(completionHandler:@escaping ((Int?,Int?)->Void)){
        evaluateJsToStringDoubleDictionary(jsString: "GetSelectedRange();") { result in
            guard let result = result, let startIndex = result["startIndex"], let endIndex = result["endIndex"] else {
                completionHandler(nil, nil)
                return
            }
            completionHandler(NiftyUtility.DoubleToInt(value: startIndex), NiftyUtility.DoubleToInt(value: endIndex))
        }
    }
    func hideNotPageElement(completionHandler: (()->Void)?){
        evaluateJsToString(jsString: "HideOtherElements(document.body, elementArray);\"OK\";", completionHandler: { _ in
            completionHandler?()
        })
    }
}
