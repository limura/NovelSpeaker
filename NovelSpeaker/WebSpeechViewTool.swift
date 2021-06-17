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

class WebSpeechViewTool: NSObject, WKNavigationDelegate {
    var wkWebView:WKWebView? = nil
    var loadCompletionHandler:(() -> Void)? = nil
    var siteInfoArray:[StorySiteInfo] = []
    
    let jsFunctions = """
function GetPageElementArray(SiteInfo){
  if("data" in SiteInfo && "pageElement" in SiteInfo.data){
    return document.evaluate(SiteInfo.data.pageElement, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  }
  return undefined;
}

function GetNextLink(SiteInfo){
  if("data" in SiteInfo && "nextLink" in SiteInfo.data){
    return document.evaluate(SiteInfo.data.pageElement, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  }
  return undefined;
}

function ScrollToElement(element, index, margin) {
  let range = new Range();
  range.selectNode(element);
  if(index > 0){
    range.setStart(element, index);
  }
  rect = range.getBoundingClientRect();
  //let x = window.pageXOffset + rect.x + rect.width;
  let x = window.pageXOffset + rect.right + margin;
  let y = window.pageYOffset + rect.bottom - window.innerHeight + margin;
  window.scroll(x, y);
}

function ScrollToIndex(index, margin){
  let elementData = SearchElementFromIndex(elementArray, index);
  if(elementData){
    ScrollToElement(elementData.element, elementData.index, 0);
  }
}

function HighlightSpeechSentence(element, index, length){
  //element.parentNode.scrollIntoView(true); // TEXT_NODE には scrollIntoView が無いっぽい(´・ω・`)
  let range = new Range();
  //range.selectNodeContents(element); // selectNodeContents() では子要素が無いと駄目
  range.selectNode(element);
  if(index > 0){
    range.setStart(element, index);
  }
  if(length <= 0){
    length = 1;
  }
  range.setEnd(element, index + length);

  let selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
}
function isNotSpeechElement(element){
  if(element instanceof HTMLElement){
    switch(element.tagName){
    case "SCRIPT":
    case "STYLE":
    case "NOSCRIPT":
    case "IFRAME":
    case "META":
    case "IMG":
      return true;
      break;
    default:
      break;
    }
  }
  return false;
}

function extractElement(element){
  if(isNotSpeechElement(element)){
    return [];
  }
  if(element.childNodes.length <= 0){
    var text = "";
    if(element.nodeType == Node.TEXT_NODE){
      text = element.textContent;
    }else{
      text = element.innerText;
    }
    if(!text || text.trim().length <= 0){
      return [];
    }
    return [{"element": element, "text": text}];
  }
  var elementArray = [];
  for(var i = 0; i < element.childNodes.length; i++){
    let childNode = element.childNodes[i];
    elementArray = elementArray.concat(extractElement(childNode))
  }
  return elementArray;
}

function extractElementForPageElementArray(pageElementArray){
  var elementArray = [];
  for(var i = 0; i < pageElementArray.snapshotLength; i++){
    let element = pageElementArray.snapshotItem(i);
    elementArray = elementArray.concat(extractElement(element));
  }
  return elementArray;
}

// [{"element":, "text":}, ...] の配列の text の文字を index として、
// index (0 起点) で示される element の何文字目であるかを返す({"element":, "text":, "index":})
// 見つからなければ undefined が返ります
function SearchElementFromIndex(elementArray, index){
  var i = 0;
  for(var i = 0; i < elementArray.length && index >= 0; i++){
    let data = elementArray[i];
    let element = data["element"];
    let text = data["text"];
    let textLength = text.length;
    if(index < textLength){
      return {"element": element, "text": text, "index": index}
    }
    index -= textLength;
  }
  return undefined
}

// elementArray から range で示された範囲を先頭とする elementArray と、その先頭の index を返す
// 返されるのは {"elementArray": , "index": } の形式で、発見できなかった場合は undefined が返る
function SplitElementFromSelection(elementArray, range){
  var resultArray = [];
  var prevArray = [];
  var isHit = false;
  var index = 0;
  for(var i = 0; i < elementArray.length; i++){
    let data = elementArray[i];
    let element = data["element"];
    let text = data["text"];
    if(isHit){
      resultArray.push(data);
      continue;
    }
    let elementRange = new Range();
    elementRange.selectNode(element);
    if(!elementRange){
      //console.log("elementRange", elementRange, element);
      prevArray.push(data);
      continue;
    }
    //console.log("compare", elementRange.compareBoundaryPoints(Range.START_TO_START, range), elementRange.compareBoundaryPoints(Range.START_TO_END, range));
    if(elementRange.compareBoundaryPoints(Range.START_TO_START, range) <= 0 &&
      elementRange.compareBoundaryPoints(Range.START_TO_END, range) >= 0){
      isHit = true;
      resultArray.push(data);

      // TODO: ちゃんとやるなら range.startContainer が
      // element と同じかどうかを確認して、startOffset を使う必要がある
      index = range.startOffset;
      if(text.length < index){
        index = 0;
      }
    }else{
      prevArray.push(data);
    }
  }
  if(resultArray.length <= 0){
    return undefined;
  }
  return {elementArray: resultArray, index: index, prevElementArray:prevArray};
}

// [{"element":, "text":}, ...] の配列の text の文字を、全部組み合わせた文字列を取得します
// index は最初のelementでのオフセットになります
function GenerateWholeText(elementArray, index){
  var text = "";
  elementArray.forEach(function(data){
    console.log("text += ", data["text"], index);
    if(data["text"].length >= index){
      text += data["text"].slice(index);
      index = 0;
    }else{
      index -= data["text"].length;
    }
  });
  return text;
}

function GetSelectedIndex(){
  let selection = window.getSelection();
  var index = -1;
  if(selection.rangeCount > 0){
    let speechTarget = SplitElementFromSelection(elementArray, selection.getRangeAt(0));
    //console.log("speechTarget", speechTarget);
    if(speechTarget){
      elementArray = speechTarget.elementArray;
      prevElementArray = speechTarget.prevElementArray;
      index = speechTarget.index;
      for(var i = 0; i < prevElementArray.length; i++){
        let element = prevElementArray[i];
        index += element.text.length;
      }
    }
  }else{
    index = 0;
  }
  return index;
}

function HighlightFromIndex(index, length){
    console.log("elementArray", elementArray);
    let elementData = SearchElementFromIndex(elementArray, index);
    if(elementData){
      HighlightSpeechSentence(elementData.element, elementData.index, length);
    }
}

function EnableSelection(){
  let input = document.getElementById("focusInput");
  input.selectionStart = 0;
  input.selectionEnd = 1;
  //document.getElementById("focusInput").focus();
  if(elementArray.length >= 1) {
    let element = elementArray[0].element;
    let range = document.createRange();
    range.selectNode(element);
    let selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    return "OK";
  }
  return "NG";
}

function CreateElementArray(SiteInfoArray){
    if(SiteInfoArray === undefined) {
        SiteInfoArray = [{"data":{url:".*", pageElement:"//body", title:"//title", nextLink:"", author:"", firstPageLink:"", tag:""}}];
    }
    for(let i = 0; i < SiteInfoArray.length; i++){
        let siteInfo = SiteInfoArray[i];
        let pageElementArray = GetPageElementArray(siteInfo);
        if(pageElementArray){
            return extractElementForPageElementArray(pageElementArray);
        }
    }
    return undefined;
}
var elementArray = CreateElementArray();
"OK";
"""
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
    func highlightSpeechLocation(location:Int, length:Int) {
        //evaluateJsToString(jsString: "HighlightFromIndex(\(location), \(length));\"OK\";", completionHandler: nil)
        evaluateJsToString(jsString: "HighlightFromIndex(\(location), \(length)); ScrollToIndex(\(location) + \(length), 200); \"OK\";", completionHandler: nil)
    }
    func getSelectedLocation(completionHandler:((Int)->Void)?){
        evaluateJsToDouble(jsString: "GetSelectedIndex();") { (result) in
            guard let completionHandler = completionHandler else {
                return
            }
            if let result = result {
                completionHandler(Int(result))
            }else{
                completionHandler(-1)
            }
        }
    }
}
