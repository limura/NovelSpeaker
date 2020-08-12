//
//  StoryFetcher.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/07/11.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import UIKit
import Kanna
import AnyCodable
#if !os(watchOS)
import Erik
#endif

struct StoryState {
    let url:URL
    let cookieString:String?
    let content:String?
    let nextUrl:URL?
    let firstPageLink:URL?
    let title:String?
    let author:String?
    let subtitle:String?
    let tagArray:[String]
    let siteInfoArray:[StorySiteInfo]
    let isNeedHeadless:Bool
    var isCanFetchNextImmediately:Bool = false
    let waitSecondInHeadless:Double?
    //let count:Int
    #if !os(watchOS)
    let document:Document?
    let nextButton: Element?
    let firstPageButton: Element?
    #endif
    
    var IsNextAlive:Bool {
        get {
            if nextUrl != nil || firstPageLink != nil { return true }
            #if !os(watchOS)
            if nextButton != nil || firstPageButton  != nil{ return true }
            print("IsNextAlive return false:", nextUrl?.absoluteString ?? "[nextUrl is nil]", firstPageLink?.absoluteString ?? "[firstPageLink is nil]", nextButton == nil ? "[nextButton is nil]" : "valid nextButton", firstPageButton == nil ? "[firstPageButton is nil]" : "valid firstPageButton")
            #endif
            return false
        }
    }
    
    func CreateNextState() -> StoryState {
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, document: document, nextButton: nextButton, firstPageButton: firstPageButton)
        #else
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless)
        #endif
    }
    
    func TitleChanged(title:String) -> StoryState {
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, document: document, nextButton: nextButton, firstPageButton: firstPageButton)
        #else
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless)
        #endif
    }
}

struct StorySiteInfo {
    let title: String?
    let pageElement: String
    let subtitle: String?
    let firstPageLink: String?
    //let memo: String?
    let nextLink: String?
    let tag: String?
    let url: NSRegularExpression?
    //let exampleUrl: String?
    let author: String?
    let isNeedHeadless: Bool
    let injectStyle:String?
    let nextButton: String?
    let firstPageButton: String?
    let waitSecondInHeadless: Double?
    
    init(pageElement:String, url:String?, title:String?, subtitle:String?, firstPageLink:String?, nextLink:String?, tag:String?, author:String?, isNeedHeadless:String?, injectStyle:String?, nextButton: String?, firstPageButton: String?, waitSecondInHeadless: Double?) {
        self.pageElement = pageElement
        if let urlString = url, let urlRegex = try? NSRegularExpression(pattern: urlString, options: []) {
            self.url = urlRegex
        }else{
            self.url = nil
        }
        self.title = title
        self.subtitle = subtitle
        self.firstPageLink = firstPageLink
        self.nextLink = nextLink
        self.tag = tag
        self.author = author
        self.injectStyle = injectStyle
        self.nextButton = nextButton
        self.firstPageButton = firstPageButton
        let falseValues:[String] = ["false", "False", "nil", "0"]
        if let isNeedHeadlessString = isNeedHeadless, isNeedHeadlessString.count > 0 && !falseValues.contains(isNeedHeadlessString) {
            self.isNeedHeadless = true
        }else{
            self.isNeedHeadless = false
        }
        self.waitSecondInHeadless = waitSecondInHeadless
    }
    
    static func DecodeFrom(jsonDecodable:[String:Any]) -> StorySiteInfo? {
        guard let pageElement = jsonDecodable["pageElement"] as? String else {
            print("pageElement is not found. return nil.")
            return nil }
        return StorySiteInfo(
            pageElement: pageElement,
            url: jsonDecodable["url"] as? String,
            title: jsonDecodable["title"] as? String,
            subtitle: jsonDecodable["subtitle"] as? String,
            firstPageLink: jsonDecodable["firstPageLink"] as? String,
            nextLink: jsonDecodable["nextLink"] as? String,
            tag: jsonDecodable["tag"] as? String,
            author: jsonDecodable["author"] as? String,
            isNeedHeadless: jsonDecodable["isNeedHeadless"] as? String,
            injectStyle: jsonDecodable["injectStyle"] as? String,
            nextButton: jsonDecodable["nextButton"] as? String,
            firstPageButton: jsonDecodable["firstPageButton"] as? String,
            waitSecondInHeadless: Double(jsonDecodable["waitSecondInHeadless"] as? String ?? "0.0") ?? 0.0
            )
    }
    
    func isMatchUrl(urlString:String) -> Bool {
        guard let urlRegex = self.url else { return false }
        if urlRegex.matches(in: urlString, options: [], range: NSMakeRange(0, urlString.count)).count > 0 {
            return true
        }
        return false
    }
    
    func decodePageElement(xmlDocument:XMLDocument) -> String {
        return NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: pageElement, injectStyle: injectStyle).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeTitle(xmlDocument:XMLDocument) -> String? {
        guard let xpath = title else { return nil }
        return NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeSubtitle(xmlDocument:XMLDocument) -> String? {
        guard let xpath = subtitle else { return nil }
        return NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeFirstPageLink(xmlDocument:XMLDocument, baseURL: URL) -> URL? {
        guard let xpath = firstPageLink else { return nil }
        return NiftyUtilitySwift.FilterXpathWithExtructFirstHrefLink(xmlDocument: xmlDocument, xpath: xpath, baseURL: baseURL)
    }
    func decodeNextLink(xmlDocument:XMLDocument, baseURL: URL) -> URL? {
        guard let xpath = nextLink else { return nil }
        return NiftyUtilitySwift.FilterXpathWithExtructFirstHrefLink(xmlDocument: xmlDocument, xpath: xpath, baseURL: baseURL)
    }
    func decodeAuthor(xmlDocument:XMLDocument) -> String? {
        guard let xpath = author else { return nil }
        return NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeTag(xmlDocument:XMLDocument) -> [String] {
        guard let xpath = tag else { return [] }
        let tagStringArray = NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath)
        var tagSet = Set<String>()
        for tagCandidate in tagStringArray.components(separatedBy: CharacterSet.whitespacesAndNewlines) {
            let tag = tagCandidate.trimmingCharacters(in: CharacterSet(charactersIn: "#＃♯"))
            if tag.count > 0 {
                tagSet.insert(tag)
            }
        }
        return Array(tagSet)
    }
}

extension StorySiteInfo: CustomStringConvertible {
    var description: String {
        var result:String = ""
        result += "url: \"" + (url?.pattern ?? "nil")
        result += "\"\npageElement: \"" + pageElement
        result += "\"\ntitle: \"" + (title ?? "nil")
        result += "\"\nsubtitle: \"" + (subtitle ?? "nil")
        result += "\"\nnextLink: \"" + (nextLink ?? "nil")
        result += "\"\nfirstPageLink: \"" + (firstPageLink ?? "nil")
        result += "\"\nauthor: \"" + (author ?? "nil")
        result += "\"\ntag: \"" + (tag ?? "nil")
        result += "\"\nisNeedHeadless: " + (isNeedHeadless ? "true" : "false")
        result += "\ninjectStyle: \"" + (injectStyle ?? "nil")
        result += "\"\nnextButton: \"" + (nextButton ?? "nil")
        result += "\"\nfirstPageButton: \"" + (firstPageButton ?? "nil")
        result += "\"\nwaitSecondInHeadless: \(waitSecondInHeadless ?? 0.0)"
        result += ""
        return result
    }
}

class StoryHtmlDecoder {
    var siteInfoArray:[StorySiteInfo] = []
    var customSiteInfoArray:[StorySiteInfo] = []
    let fallbackSiteInfoArray:[StorySiteInfo]
    let lock = NSLock()
    var siteInfoLoadDoneHandlerArray:[()->Void] = []
    var cacheFileExpireTimeinterval:Double = 60*60*24
    var nextExpireDate:Date = Date(timeIntervalSince1970: 0)

    // シングルトンにしている。
    static let shared = StoryHtmlDecoder()
    private init(){
        fallbackSiteInfoArray = [
            StorySiteInfo(pageElement: "//*[contains(@class,'autopagerize_page_element') or contains(@itemprop,'articleBody') or contains(concat(' ', normalize-space(@class), ' '), ' hentry ') or contains(concat(' ', normalize-space(@class), ' '), ' h-entry ')]", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: "(//link|//a)[contains(concat(' ', translate(normalize-space(@rel),'NEXT','next'), ' '), ' next ')]", tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil),
            StorySiteInfo(pageElement: "//body", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil)
        ]
        LoadSiteInfoIfNeeded()
    }
    
    var IsSiteInfoReady: Bool {
        get {
            return customSiteInfoArray.count > 0
        }
    }
    
    func DecodeSiteInfoData(data:Data) -> [StorySiteInfo]? {
        guard let weDataDataArray = try? JSONDecoder().decode([[String:AnyDecodable]].self, from: data) else { return nil }
        var result:[StorySiteInfo] = []
        for weData in weDataDataArray {
            guard let data = weData["data"]?.value as? [String:Any], let siteInfo = StorySiteInfo.DecodeFrom(jsonDecodable: data) else { continue }
            result.append(siteInfo)
        }
        return result
    }
    
    @discardableResult
    func AddSiteInfoFromData(data:Data) -> Bool {
        guard let infoArray = DecodeSiteInfoData(data: data) else { return false }
        self.lock.lock()
        defer { self.lock.unlock() }
        siteInfoArray.append(contentsOf: infoArray)
        siteInfoArray.sort { (a, b) -> Bool in
            guard let aPattern = a.url?.pattern else { return false }
            guard let bPattern = b.url?.pattern else { return true }
            return aPattern.count > bPattern.count
        }
        return true
    }
    @discardableResult
    func AddCustomSiteInfoFromData(data:Data) -> Bool {
        guard let siteInfoArray = DecodeSiteInfoData(data: data) else { return false}
        self.lock.lock()
        defer { self.lock.unlock() }
        customSiteInfoArray.append(contentsOf: siteInfoArray)
        customSiteInfoArray.sort { (a, b) -> Bool in
            guard let aPattern = a.url?.pattern else { return false }
            guard let bPattern = b.url?.pattern else { return true }
            return aPattern.count > bPattern.count
        }
        return true
    }
    
    func ClearSiteInfo() {
        self.lock.lock()
        defer { self.lock.unlock() }
        siteInfoArray.removeAll()
        customSiteInfoArray.removeAll()
    }
    
    func SearchSiteInfoArrayFrom(urlString: String) -> [StorySiteInfo] {
        var result:[StorySiteInfo] = []
        self.lock.lock()
        defer { self.lock.unlock() }
        for siteInfo in customSiteInfoArray {
            if siteInfo.isMatchUrl(urlString: urlString) {
                result.append(siteInfo)
            }
        }
        for siteInfo in siteInfoArray {
            if siteInfo.isMatchUrl(urlString: urlString) {
                result.append(siteInfo)
            }
        }
        for siteInfo in fallbackSiteInfoArray {
            if siteInfo.isMatchUrl(urlString: urlString) {
                result.append(siteInfo)
            }
        }
        return result
    }
    
    func LoadSiteInfoIfNeeded() {
        let now = Date()
        if IsSiteInfoReady == true && nextExpireDate > now {
            return
        }
        nextExpireDate = now.addingTimeInterval(cacheFileExpireTimeinterval)
        DispatchQueue.global(qos: .background).async {
            self.LoadSiteInfo()
        }
    }
    
    func WaitLoadSiteInfoReady(handler: @escaping ()->Void){
        defer { LoadSiteInfoIfNeeded() }
        if IsSiteInfoReady {
            handler()
            return
        }
        lock.lock()
        siteInfoLoadDoneHandlerArray.append(handler)
        lock.unlock()
    }
    
    // 標準のSiteInfoを非同期で読み込みます。
    func LoadSiteInfo(completion:((Error?)->Void)? = nil) {
        var cacheFileExpireTimeinterval:Double = self.cacheFileExpireTimeinterval
        let cacheFileName = "AutopagerizeSiteInfoCache"
        let customCacheFileName = "NovelSpeakerSiteInfoCache"
        func announceLoadEnd() {
            lock.lock()
            let targetArray = siteInfoLoadDoneHandlerArray
            siteInfoLoadDoneHandlerArray.removeAll()
            lock.unlock()

            for handler in targetArray {
                handler()
            }
        }
        guard let siteInfoURL = URL(string: "http://wedata.net/databases/AutoPagerize/items.json"),
            let customSiteInfoURL = URL(string: "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1/items.json") else {
                completion?(SloppyError(msg: "unknown error. default url decode error."))
                announceLoadEnd()
                return
        }
        if let instance = RealmGlobalState.GetInstance(), instance.isForceSiteInfoReloadIsEnabled {
            cacheFileExpireTimeinterval = 0
        }
        var siteInfoData:Data? = nil
        var customSiteInfoData:Data? = nil
        
        // SiteInfoのデータを受け取って新しい物に置き換えます。
        // その際、デコードに失敗するなどした場合にはエラーを返しますが、
        // エラーを返したにしても、利用可能なデータが残るように努力します。
        // 例えば与えられたデータ全てが壊れていた場合、エラーを返し、
        // 既存のデータが残ります。
        func updateSiteInfo(siteInfoData:Data?, customSiteInfoData:Data?) -> Error? {
            var isFail:Bool = false
            if let data = siteInfoData, let siteInfoArray = DecodeSiteInfoData(data: data) {
                self.lock.lock()
                self.siteInfoArray = siteInfoArray
                self.lock.unlock()
            }else{
                isFail = true
            }
            if let data = customSiteInfoData, let siteInfoArray = DecodeSiteInfoData(data: data) {
                
                // デバグ用。wedata の情報をここに書かれている物で上書きする
                let injectedSiteInfoArray = siteInfoArray.map { (info) -> StorySiteInfo in
                    if let pattern = info.url?.pattern {
                        switch pattern {
                        case "^https://(www|touch)\\.pixiv\\.net/novel/show\\.php":
                            return StorySiteInfo(pageElement: "//div[contains(@class,'novel-pages')]|//div[@id='novel_text_noscript']|//section[@id='novel-text-container']", url: "^https://(www|touch)\\.pixiv\\.net/novel/show\\.php", title: "//div[contains(@class,'user-works-nav')]/a[contains(@href,'/novel/show.php')]/h1[contains(@class,'work-title')]", subtitle: nil, firstPageLink: nil, nextLink: "//div[@class='user-works-nav']/div[@class='nav-buttons']/a[contains(@class,'nav-next') and contains(@class,'router-link-active') and contains(@href,'/novel/show.php?id=')]", tag: "//ul[contains(@class,'tags')]/li[contains(@class,'tag')]/a[contains(@class,'text')]|//a[contains(@class,'tag-value')]|//div[@class='novel-details-content']//div[contains(@class,'display-tags')]//a[contains(@href,'/tags/')]", author: "//a[contains(@class,'user-name')]|//div[contains(@class,'top-card')]/a[contains(@href,'/users/') and @class='user-details-name']", isNeedHeadless: "true", injectStyle: "#novel-text-container{white-space:pre-wrap;}; .novel-paragraph.horizontal{padding: 0 16px}", nextButton: "nav.novel-pager-container span:not(.invisible):not(.current-page):last-child", firstPageButton: ".segment-bottom .action-button-container button, .gtm-series-next-work-button-in-illust-detail,a.series-link.router-link-active:first-child", waitSecondInHeadless: 1.5)
                        default:
                            return info
                        }
                    }
                    return info
                }
                self.lock.lock()
                //self.customSiteInfoArray = siteInfoArray
                self.customSiteInfoArray = injectedSiteInfoArray
                self.lock.unlock()
            }else{
                isFail = true
            }
            announceLoadEnd()
            if isFail {
                return SloppyError(msg: "siteInfo or customSiteInfo decode error.")
            }
            return nil
        }
        
        // Autopagerize の SiteInfo を読み込むと読み込むだけで 2MBytes 以上使ってしまうので
        // watchOS では Autopagerize の SiteInfo については読み込まないようにします
        // WARN: TODO: つまり、ことせかい用の SiteInfo が巨大になった場合同様に問題が発生しえます
        #if !os(watchOS)
        NiftyUtilitySwift.FileCachedHttpGet(url: siteInfoURL, cacheFileName: cacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: { (data) in
            siteInfoData = data
            NiftyUtilitySwift.FileCachedHttpGet(url: customSiteInfoURL, cacheFileName: customCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: { (data) in
                customSiteInfoData = data
                completion?(updateSiteInfo(siteInfoData: siteInfoData, customSiteInfoData: customSiteInfoData))
            }) { (err) in
                completion?(updateSiteInfo(siteInfoData: siteInfoData, customSiteInfoData: nil))
            }
        }) { (err) in
            NiftyUtilitySwift.FileCachedHttpGet(url: customSiteInfoURL, cacheFileName: customCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: { (data) in
                customSiteInfoData = data
                completion?(updateSiteInfo(siteInfoData: nil, customSiteInfoData: customSiteInfoData))
            }) { (err) in
                // nothing to do!
                completion?(SloppyError(msg: "siteInfo and customSiteInfo fetch failed."))
            }
        }
        #else
        NiftyUtilitySwift.FileCachedHttpGet(url: customSiteInfoURL, cacheFileName: customCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: { (data) in
            customSiteInfoData = data
            completion?(updateSiteInfo(siteInfoData: nil, customSiteInfoData: customSiteInfoData))
        }) { (err) in
            // nothing to do!
            completion?(SloppyError(msg: "siteInfo and customSiteInfo fetch failed."))
        }
        #endif
    }
}

class StoryFetcher {
    #if !os(watchOS)
    let httpClient:HeadlessHttpClient
    #endif
    
    init() {
        #if !os(watchOS)
        self.httpClient = HeadlessHttpClient()
        #endif
    }
    
    func DecodeDocument(currentState:StoryState, html:String?, encoding:String.Encoding, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        guard let html = html, let htmlDocument = try? HTML(html: html, encoding: encoding) else {
            failedAction?(currentState.url, NSLocalizedString("UriLoader_HTMLParseFailed_Parse", comment: "HTMLの解析に失敗しました。(有効なHTMLまたはXHTML文書ではないようです。いまのところ、ことせかい はPDF等のHTMLやXHTMLではない文書は読み込む事ができません)"))
            return
        }
        for siteInfo in currentState.siteInfoArray {
            let pageElement = siteInfo.decodePageElement(xmlDocument: htmlDocument).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let nextUrl = siteInfo.decodeNextLink(xmlDocument: htmlDocument, baseURL: currentState.url)
            let firstPageLink = siteInfo.decodeFirstPageLink(xmlDocument: htmlDocument, baseURL: currentState.url)
            #if !os(watchOS)
            let nextButton:Element? = siteInfo.nextButton != nil ? currentState.document?.querySelectorAll(siteInfo.nextButton!).first : nil
            let firstPageButton:Element? = siteInfo.firstPageButton != nil ? currentState.document?.querySelectorAll(siteInfo.firstPageButton!).first : nil
            if pageElement.count <= 0 && nextUrl == nil && firstPageLink == nil && nextButton == nil && firstPageButton == nil {
                print("no content or nextUrl and other:", siteInfo.pageElement)
                continue
            }
            #else
            if pageElement.count <= 0 && nextUrl == nil && firstPageLink == nil {
                continue
            }
            #endif
            #if !os(watchOS)
            successAction?(
                StoryState(
                    url: currentState.url,
                    cookieString: currentState.cookieString,
                    content: pageElement,
                    nextUrl: nextUrl,
                    firstPageLink: firstPageLink,
                    title: siteInfo.decodeTitle(xmlDocument: htmlDocument),
                    author: siteInfo.decodeAuthor(xmlDocument: htmlDocument),
                    subtitle: siteInfo.decodeSubtitle(xmlDocument: htmlDocument),
                    tagArray: siteInfo.decodeTag(xmlDocument: htmlDocument),
                    siteInfoArray: currentState.siteInfoArray,
                    isNeedHeadless: currentState.isNeedHeadless,
                    waitSecondInHeadless: currentState.waitSecondInHeadless,
                    document: currentState.document,
                    nextButton: nextButton,
                    firstPageButton: firstPageButton
                )
            )
            #else
            successAction?(StoryState(url: currentState.url, cookieString: currentState.cookieString, content: pageElement, nextUrl: siteInfo.decodeNextLink(xmlDocument: htmlDocument, baseURL: currentState.url), firstPageLink: siteInfo.decodeFirstPageLink(xmlDocument: htmlDocument, baseURL: currentState.url), title: siteInfo.decodeTitle(xmlDocument: htmlDocument), author: siteInfo.decodeAuthor(xmlDocument: htmlDocument), subtitle: siteInfo.decodeSubtitle(xmlDocument: htmlDocument), tagArray: siteInfo.decodeTag(xmlDocument: htmlDocument), siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, waitSecondInHeadless: currentState.waitSecondInHeadless))
            #endif
            return
        }
        failedAction?(currentState.url, NSLocalizedString("UriLoader_HTMLParseFailed_ContentIsNil", comment: "HTMLの解析に失敗しました。(文書の中身を取り出せませんでした。ことせかい のサポートサイト側のご意見ご要望フォームや設定→開発者に問い合わせる等から、このエラーの起こったURLとエラーが起こるまでの手順を添えて報告して頂くことで解決できるかもしれません)"))
    }
    
    // 与えられた StoryState に示される「何をしたら次の本文が取得できるか」を実行して本文を取り出します。
    // 具体的には、
    // 本文の読み込みに成功するとその時の StoryState を引数として successAction を呼び出します。
    // successAction が呼び出されたら、
    func FetchNext(currentState:StoryState, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?){
        // 入力に有効な content があるならそこで探索は終わり
        if let content = currentState.content, content.count > 0 {
            successAction?(currentState)
            return
        }
        
        #if !os(watchOS)
        // Erik の機能を使ってボタンをクリックして、その後本文を取り出します。
        // TODO: この関数内部でのエラーを返す手段が(nil を返す以外に)ありません
        func buttonClick(buttonElement:Element, currentState:StoryState, completionHandler:((StoryState?, Error?)->Void)?) {
            print("buttonClick:", currentState.url.absoluteString, "element.text:", buttonElement.text ?? "nil")
            buttonElement.click { (_, err) in
                if let err = err {
                    print("error occurd at after button click:", err.localizedDescription)
                    completionHandler?(nil, err)
                    return
                }
                self.httpClient.GetCurrentCookieString { (cookieString, err) in
                    let delayTime:TimeInterval
                    // waitSecondInHeadless が指定されていたらその秒だけ待ちます
                    if let waitSecondInHeadless = currentState.waitSecondInHeadless {
                        delayTime = waitSecondInHeadless
                    }else{
                        delayTime = -1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delayTime) {
                        self.httpClient.GetCurrentContent { (document, error) in
                            if let err = error {
                                completionHandler?(nil, err)
                                return
                            }
                            guard let document = document else {
                                completionHandler?(nil, SloppyError(msg: "unknown error: (Erik document = nil)"))
                                return
                            }
                            guard let html = document.innerHTML else {
                                completionHandler?(nil, SloppyError(msg: "unknown error: (Erik document.innerHTML?.data() return nil)"))
                                return
                            }
                            let currentUrl:URL
                            if let erikUrl = self.httpClient.GetCurrentURL() {
                                currentUrl = erikUrl
                            }else{
                                currentUrl = currentState.url
                            }
                            print("HeadlessHttpClient.shared.GetCurrentContent currentUrl:", currentUrl.absoluteString)
                            print("HeadlessHttpClient.shared.GetCurrentContent html.count:", html.count)
                            let newState:StoryState = StoryState(url: currentUrl, cookieString: cookieString ?? currentState.cookieString, content: nil, nextUrl: nil, firstPageLink: nil, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: true, waitSecondInHeadless: currentState.waitSecondInHeadless, document: document, nextButton: nil, firstPageButton: nil)
                            self.DecodeDocument(currentState: newState, html: html, encoding: .utf8, successAction: { (state) in
                                completionHandler?(state, nil)
                            }) { (_, err) in
                                completionHandler?(nil, SloppyError(msg: err))
                            }
                        }

                    }
                }
            }
        }
        
        // 次ページへのボタンがあればそれを辿る
        if let element = currentState.nextButton {
            buttonClick(buttonElement: element, currentState: currentState) { (state, err) in
                if let state = state {
                    successAction?(state)
                    return
                }
                failedAction?(currentState.url, err?.localizedDescription ?? NSLocalizedString("StoryFetcher_CanNotFindPageElementAndNextLink", comment: "指定されたURLからは本文や次ページを示すURLなどを取得できませんでした。") + "(nextButtonClick)")
            }
            return
        }

        // 本文へのボタンがあればそれを辿る
        if let element = currentState.firstPageButton {
            buttonClick(buttonElement: element, currentState: currentState) { (state, err) in
                if let state = state {
                    successAction?(state)
                    return
                }
                failedAction?(currentState.url, err?.localizedDescription ?? NSLocalizedString("StoryFetcher_CanNotFindPageElementAndNextLink", comment: "指定されたURLからは本文や次ページを示すURLなどを取得できませんでした。") + "(firstPageClick)")
            }
            return
        }
        #endif
        
        // URL を GET した後に本文を取り出す時の挙動
        // 状態を更新してDecodeDocument()を呼び出すだけです
        func fetchUrl(url:URL, currentState:StoryState) {
            print("fetchUrl:", url.absoluteString, "isNeedHeadless:", currentState.isNeedHeadless ? "true" : "false")
            #if !os(watchOS)
            if currentState.isNeedHeadless {
                NiftyUtilitySwift.httpHeadlessRequest(url: url, postData: nil, cookieString: currentState.cookieString, mainDocumentURL: url, httpClient: self.httpClient, successAction: { (doc) in
                    let html = doc.innerHTML
                    let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, document: doc, nextButton: currentState.nextButton, firstPageButton: currentState.firstPageButton)
                    self.DecodeDocument(currentState: newState, html: html, encoding: .utf8, successAction: { (state) in
                        self.FetchNext(currentState: state, successAction: successAction, failedAction: failedAction)
                    }, failedAction: failedAction)
                }) { (error) in
                    failedAction?(currentState.url, error?.localizedDescription ?? "httpHeadlessRequest return unknown error(nil)")
                }
                return
            }
            #endif
            
            NiftyUtilitySwift.httpRequest(url: url, postData: nil, cookieString: currentState.cookieString, isNeedHeadless: currentState.isNeedHeadless, mainDocumentURL: url, allowsCellularAccess: (RealmGlobalState.GetInstance()?.IsDisallowsCellularAccess ?? false) ? false : true, successAction: { (data, encoding) in
                #if !os(watchOS)
                let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, document: currentState.document, nextButton: currentState.nextButton, firstPageButton: currentState.firstPageButton)
                #else
                let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless)
                #endif
                let (html, guessedEncoding) = NiftyUtilitySwift.decodeHTMLStringFrom(data: data, headerEncoding: encoding)
                self.DecodeDocument(currentState: newState, html: html, encoding: guessedEncoding ?? encoding ?? .utf8, successAction: { (state) in
                    self.FetchNext(currentState: state, successAction: successAction, failedAction: failedAction)
                }, failedAction: failedAction)
            }) { (error) in
                failedAction?(currentState.url, error?.localizedDescription ?? "httpRequest return unknown error(nil)")
            }
        }
        
        if let nextUrl = currentState.nextUrl {
            // nextUrl があるならそれを辿る
            fetchUrl(url: nextUrl, currentState: currentState)
            return
        }
        if let firstPageLink = currentState.firstPageLink {
            // firstPageLink があるならそれを辿る
            fetchUrl(url: firstPageLink, currentState: currentState)
            return
        }

        failedAction?(currentState.url, NSLocalizedString("StoryFetcher_CanNotFindPageElementAndNextLink", comment: "指定されたURLからは本文や次ページを示すURLなどを取得できませんでした。"))
    }

    static func CreateFirstStoryStateWithoutCheckLoadSiteInfo(url:URL, cookieString:String?) -> StoryState {
        let siteInfoArray = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: url.absoluteString)
        let isNeedHeadless:Bool = siteInfoArray.reduce(false) { (result, siteInfo) -> Bool in
            if result || siteInfo.isNeedHeadless { return true }
            return false
        }
        let waitSecondInHeadless:Double = siteInfoArray.reduce(0.0) { (result, siteInfo) -> Double in
            if let waitSecondInHeadless = siteInfo.waitSecondInHeadless, result < waitSecondInHeadless { return waitSecondInHeadless }
            return result
        }
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: url, firstPageLink: nil, title: nil, author: nil, subtitle: nil, tagArray: [], siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: false, waitSecondInHeadless: waitSecondInHeadless, document: nil, nextButton: nil, firstPageButton: nil)
        #else
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: url, firstPageLink: nil, title: nil, author: nil, subtitle: nil, tagArray: [], siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: false, waitSecondInHeadless: waitSecondInHeadless)
        #endif
    }
    
    static func CreateFirstStoryState(url:URL, cookieString:String?, completion:((StoryState)->Void)?) {
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady {
            completion?(CreateFirstStoryStateWithoutCheckLoadSiteInfo(url:url, cookieString: cookieString))
        }
    }
    
    func FetchFirst(url:URL, cookieString:String?, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, completion:{ (dummyState) in
            self.FetchNext(currentState: dummyState, successAction: successAction, failedAction: failedAction)
        })
    }
    
    private func FetchFirstContentRecurcive(currentState:StoryState, countToLive:Int = 10, nextFetchTime:Date = Date(timeIntervalSince1970: 0), successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        if let content = currentState.content, content.count > 0 {
            successAction?(currentState)
            return
        }
        if currentState.IsNextAlive == false {
            failedAction?(currentState.url, NSLocalizedString("StoryFetcher_FetchFirstContent_NoNextUrlAlive", comment: "本文を取り出せませんでした。(本文が掲載されている部分へのリンクが発見できませんでした)"))
            return
        }
        if countToLive <= 0 {
            failedAction?(currentState.url, NSLocalizedString("StoryFetcher_FetchFirstContent_ExceededCountToLive", comment: "本文を取り出せませんでした。(本文へのリンクが発見できないまま読み込み回数上限に達しました)"))
            return
        }
        func doNext() {
            FetchNext(currentState: currentState, successAction: { (state) in
                self.FetchFirstContentRecurcive(currentState: state, countToLive: countToLive - 1, nextFetchTime: Date(timeIntervalSinceNow: 1.5), successAction: successAction, failedAction: failedAction)
            }, failedAction: failedAction)
        }
        let delay = nextFetchTime.timeIntervalSince(Date())
        if delay <= 0 {
            doNext()
        }else{
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                doNext()
            }
        }
    }
    
    // 指定されたURLから最初の本文と思われるものまで読み込んでその値を返します。
    func FetchFirstContent(url:URL, cookieString:String?, completion:((_ requestURL:URL, _ state:StoryState?, _ errorDescriptionString:String?)->Void)?) {
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, completion: { (state) in
            self.FetchFirstContentRecurcive(currentState: state, successAction: { (state) in
                completion?(url, state, nil)
            }, failedAction: { (url, errorString) in
                completion?(url, nil, errorString)
            })
        })
    }
}
