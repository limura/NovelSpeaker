//
//  StoryFetcher.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/07/11.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import UIKit
import Kanna
#if !os(watchOS)
import Erik
#endif

struct StoryState : CustomStringConvertible {
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
    let previousContent:String?
    //let count:Int
    #if !os(watchOS)
    let document:Document?
    let nextButton: Element?
    let firstPageButton: Element?
    let forceClickButton: Element?
    #endif
    
    var IsNextAlive:Bool {
        get {
            // nextUrl や firstPageLink があったなら次のページがあると判定します。
            if nextUrl != nil { return true }
            if firstPageLink != nil { return true }
            // ヘッドレスブラウザが使える状況で、nextButton や firstPageButton がある場合も次のページがあると判定します。
            #if !os(watchOS)
            if nextButton != nil || firstPageButton  != nil{ return true }
            //print("IsNextAlive return false:", nextUrl?.absoluteString ?? "[nextUrl is nil]", firstPageLink?.absoluteString ?? "[firstPageLink is nil]", nextButton == nil ? "[nextButton is nil]" : "valid nextButton", firstPageButton == nil ? "[firstPageButton is nil]" : "valid firstPageButton")
            #endif
            return false
        }
    }
    
    func CreateNextState() -> StoryState {
        let previousContent:String?
        if let prevContent = self.content, prevContent.count > 0 {
            previousContent = prevContent
        }else{
            previousContent = nil
        }
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, document: document, nextButton: nextButton, firstPageButton: firstPageButton, forceClickButton: forceClickButton)
        #else
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent)
        #endif
    }
    
    func TitleChanged(title:String) -> StoryState {
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: self.previousContent, document: document, nextButton: nextButton, firstPageButton: firstPageButton, forceClickButton: forceClickButton)
        #else
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: self.previousContent)
        #endif
    }
    
    var description: String {
        get {
            let contentFirstSection:String
            if let contentPrefix = content?.prefix(300) {
                contentFirstSection = String(contentPrefix)
            }else{
                contentFirstSection = String((content ?? "").split(separator: "\n").first ?? "nil or no line")
            }
            let previousContentFirstSection:String
            if let previousContentPrefix = content?.prefix(300) {
                previousContentFirstSection = String(previousContentPrefix)
            }else{
                previousContentFirstSection = String((content ?? "").split(separator: "\n").first ?? "nil or no line")
            }
            var description = """
url: \(url.absoluteString)
cookieString: \(cookieString ?? "nil")
content: \(contentFirstSection)
nextUrl: \(nextUrl?.absoluteString ?? "nil")
firstPageLink: \(firstPageLink?.absoluteString ?? "nil")
title: \(title ?? "nil")
author: \(author ?? "nil")
subtitle: \(subtitle ?? "nil")
tagArray: \(tagArray.joined(separator: ", "))
siteInfoArray.count: \(siteInfoArray.count)
isNeedHeadless: \(isNeedHeadless)
waitSecondInHeadless: \(waitSecondInHeadless?.description ?? "nil")
previousContent: \(previousContentFirstSection)
"""
            #if !os(watchOS)
            description += """

document: \(document == nil ? "nil" : "not nil")
nextButton: \(nextButton == nil ? "nil" : "not nil")
firstPageButton: \(firstPageButton == nil ? "nil" : "not nil")
"""
            #endif
            return description
        }
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
    let forceClickButton:String?
    
    init(pageElement:String, url:String?, title:String?, subtitle:String?, firstPageLink:String?, nextLink:String?, tag:String?, author:String?, isNeedHeadless:String?, injectStyle:String?, nextButton: String?, firstPageButton: String?, waitSecondInHeadless: Double?, forceClickButton:String?) {
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
        self.forceClickButton = forceClickButton
    }
    
    func isMatchUrl(urlString:String) -> Bool {
        guard let urlRegex = self.url else { return false }
        if urlRegex.matches(in: urlString, options: [], range: NSMakeRange(0, urlString.count)).count > 0 {
            return true
        }
        return false
    }
    
    func decodePageElement(xmlDocument:XMLDocument) -> String {
        return NovelSpeakerUtility.NormalizeNewlineString(string: NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: pageElement, injectStyle: injectStyle).trimmingCharacters(in: .whitespacesAndNewlines) )
    }
    func decodeTitle(xmlDocument:XMLDocument) -> String? {
        guard let xpath = title else { return nil }
        return NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeSubtitle(xmlDocument:XMLDocument) -> String? {
        guard let xpath = subtitle else { return nil }
        return NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeFirstPageLink(xmlDocument:XMLDocument, baseURL: URL) -> URL? {
        guard let xpath = firstPageLink else { return nil }
        return NiftyUtility.FilterXpathWithExtructFirstHrefLink(xmlDocument: xmlDocument, xpath: xpath, baseURL: baseURL)
    }
    func decodeNextLink(xmlDocument:XMLDocument, baseURL: URL) -> URL? {
        guard let xpath = nextLink else { return nil }
        return NiftyUtility.FilterXpathWithExtructFirstHrefLink(xmlDocument: xmlDocument, xpath: xpath, baseURL: baseURL)
    }
    func decodeAuthor(xmlDocument:XMLDocument) -> String? {
        guard let xpath = author else { return nil }
        return NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeTag(xmlDocument:XMLDocument) -> [String] {
        guard let xpath = tag else { return [] }
        return Array(NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: xmlDocument, xpath: xpath))
    }
    
    // とりあえず pageElement と URL だけある感じの物を返します。
    func generatePageElementOnlySiteInfoString() -> String {
        // {"data":{url:".*", pageElement:"//body", title:"//title", nextLink:"", author:"", firstPageLink:"", tag:""}}
        struct SiteInfoBase: Encodable {
            let url:String
            let pageElement:String
        }
        struct SiteInfoJson: Encodable {
            let data:SiteInfoBase
        }
        let siteInfoTmp = SiteInfoJson(data: SiteInfoBase(url: self.url?.pattern ?? ".*", pageElement: pageElement))
        if let jsonData = try? JSONEncoder().encode(siteInfoTmp), let jsonStirng = String(data: jsonData, encoding: .utf8) {
            return jsonStirng
        }
        // JSON にするのに失敗したら自前でやってみます。(´・ω・`)
        let pageElementString:String
        if pageElement.contains("\"") {
            pageElementString = "'\(pageElement)'"
        }else{
            pageElementString = "\"\(pageElement)\""
        }
        return "{data:{url:'\(self.url?.pattern ?? ".*")', pageElement:\(pageElementString)}}"
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
        result += "\"\nforceClickButton: \"" + (forceClickButton ?? "nil")
        result += "\""
        return result
    }
}

extension StorySiteInfo : Decodable {
    enum CodingKeys: String, CodingKey {
        case data
    }
    private enum NestedKeys: String, CodingKey {
        case title
        case pageElement
        case subtitle
        case firstPageLink
        case nextLink
        case tag
        case url
        case author
        case isNeedHeadless
        case injectStyle
        case nextButton
        case firstPageButton
        case waitSecondInHeadless
        case forceClickButton
    }
    
    init(from decoder: Decoder) throws {
        let toplevelValue = try decoder.container(keyedBy: CodingKeys.self)

        let values = try toplevelValue.nestedContainer(keyedBy: NestedKeys.self, forKey: .data)
        title = try? values.decode(String.self, forKey: NestedKeys.title)
        pageElement = try values.decode(String.self, forKey: NestedKeys.pageElement)
        subtitle = try? values.decode(String.self, forKey: NestedKeys.subtitle)
        firstPageLink = try? values.decode(String.self, forKey: NestedKeys.firstPageLink)
        nextLink = try? values.decode(String.self, forKey: NestedKeys.nextLink)
        tag = try? values.decode(String.self, forKey: NestedKeys.tag)
        if let urlString = try? values.decode(String.self, forKey: NestedKeys.url) {
            url = try? NSRegularExpression(pattern: urlString, options: [])
        }else{
            url = nil
        }
        author = try? values.decode(String.self, forKey: NestedKeys.author)
        let isNeedHeadlessString = try? values.decode(String.self, forKey: NestedKeys.isNeedHeadless)
        if let isNeedHeadlessString = isNeedHeadlessString, isNeedHeadlessString.count > 0 {
            switch isNeedHeadlessString.lowercased() {
            case "false":
                isNeedHeadless = false
            case "nil":
                isNeedHeadless = false
            case "0":
                isNeedHeadless = false
            default:
                isNeedHeadless = true
            }
        }else{
            isNeedHeadless = false
        }
        injectStyle = try? values.decode(String.self, forKey: NestedKeys.injectStyle)
        nextButton = try? values.decode(String.self, forKey: NestedKeys.nextButton)
        firstPageButton = try? values.decode(String.self, forKey: NestedKeys.firstPageButton)
        #if !os(watchOS)
        if let waitSecondInHeadlessString = try? values.decode(String.self, forKey: NestedKeys.waitSecondInHeadless), let value = Double(string: waitSecondInHeadlessString) {
            waitSecondInHeadless = value
        }else{
            waitSecondInHeadless = 0
        }
        #else
        waitSecondInHeadless = 0
        #endif
        forceClickButton = try? values.decode(String.self, forKey: NestedKeys.forceClickButton)
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
    let cacheFileName = "AutopagerizeSiteInfoCache"
    let customCacheFileName = "NovelSpeakerSiteInfoCache"
    var siteInfoNowLoading:Bool = false
    
    static let AutopagerizeSiteInfoJSONURL = "http://wedata.net/databases/AutoPagerize/items.json"
    static let NovelSpeakerSiteInfoJSONURL = "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1/items.json"

    // シングルトンにしている。
    static let shared = StoryHtmlDecoder()
    private init(){
        fallbackSiteInfoArray = [
            StorySiteInfo(pageElement: "//*[contains(@class,'autopagerize_page_element') or contains(@itemprop,'articleBody') or contains(concat(' ', normalize-space(@class), ' '), ' hentry ') or contains(concat(' ', normalize-space(@class), ' '), ' h-entry ')]", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: "(//link|//a)[contains(concat(' ', translate(normalize-space(@rel),'NEXT','next'), ' '), ' next ')]", tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: nil),
            StorySiteInfo(pageElement: "//body", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: nil)
        ]
    }
    
    var IsSiteInfoReady: Bool {
        get {
            return customSiteInfoArray.count > 0
        }
    }
    
    func DecodeSiteInfoData(data:Data) -> [StorySiteInfo]? {
        guard let result = try? JSONDecoder().decode([StorySiteInfo].self, from: data) else { return nil }
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
        siteInfoArray.removeAll()
        customSiteInfoArray.removeAll()
        self.lock.unlock()
        NiftyUtility.FileCachedHttpGet_RemoveCacheFile(cacheFileName: cacheFileName)
        NiftyUtility.FileCachedHttpGet_RemoveCacheFile(cacheFileName: customCacheFileName)
        LoadSiteInfoIfNeeded()
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
        lock.lock()
        if IsSiteInfoReady == true && nextExpireDate > now && RealmGlobalState.GetIsForceSiteInfoReloadIsEnabled() == false {
            let handlerQueued = self.siteInfoLoadDoneHandlerArray
            self.siteInfoLoadDoneHandlerArray.removeAll()
            lock.unlock()
            for handler in handlerQueued {
                handler()
            }
            return
        }
        if siteInfoNowLoading {
            lock.unlock()
            return
        }
        nextExpireDate = now.addingTimeInterval(cacheFileExpireTimeinterval)
        siteInfoNowLoading = true
        lock.unlock()
        DispatchQueue.global(qos: .background).async {
            self.LoadSiteInfo()
        }
    }
    
    func WaitLoadSiteInfoReady(handler: @escaping ()->Void){
        lock.lock()
        siteInfoLoadDoneHandlerArray.append(handler)
        lock.unlock()
        LoadSiteInfoIfNeeded()
    }
    
    // 標準のSiteInfoを非同期で読み込みます。
    func LoadSiteInfo(completion:((Error?)->Void)? = nil) {
        var cacheFileExpireTimeinterval:Double = self.cacheFileExpireTimeinterval
        func announceLoadEnd() {
            lock.lock()
            siteInfoNowLoading = false
            let targetArray = siteInfoLoadDoneHandlerArray
            siteInfoLoadDoneHandlerArray.removeAll()
            lock.unlock()
            for handler in targetArray {
                handler()
            }
        }
        var userDefinedSiteInfoURL:URL? = nil
        var userDefinedCustomSiteInfoURL:URL? = nil
        if let realm = try? RealmUtil.GetRealm(), let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
            if globalState.autopagerizeSiteInfoURL.count > 0, let autopagerizeURL = URL(string: globalState.autopagerizeSiteInfoURL) {
                userDefinedSiteInfoURL = autopagerizeURL
            }
            if globalState.novelSpeakerSiteInfoURL.count > 0, let novelSpeakerURL = URL(string: globalState.novelSpeakerSiteInfoURL) {
                userDefinedCustomSiteInfoURL = novelSpeakerURL
            }
        }
        guard let siteInfoURL = userDefinedSiteInfoURL ?? URL(string: StoryHtmlDecoder.AutopagerizeSiteInfoJSONURL),
              let customSiteInfoURL = userDefinedCustomSiteInfoURL ?? URL(string: StoryHtmlDecoder.NovelSpeakerSiteInfoJSONURL) else {
                completion?(NovelSpeakerUtility.GenerateNSError(msg: "unknown error. default url decode error."))
                announceLoadEnd()
                return
        }
        if RealmGlobalState.GetIsForceSiteInfoReloadIsEnabled() {
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
                #if !os(watchOS)
                AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_FetchSiteInfoError_SiteInfo", comment: "次点のSiteInfoデータの読み込みに失敗しました。この失敗により、小説をダウンロードする時に、小説の本文部分を抽出できず、本文以外の文字列も取り込む事になる可能性が高まります。\nネットワーク状況を確認の上、「設定タブ」→「SiteInfoを取得し直す」を実行して再取得を試みてください。\nそれでも同様の問題が報告される場合には、「設定タブ」→「開発者に問い合わせる」よりこのエラーメッセージを添えてお問い合わせください。"), appendix: [
                        "siteInfoURL": siteInfoURL.absoluteString
                    ], isForDebug: false)
                #endif
            }
            if let data = customSiteInfoData, let siteInfoArray = DecodeSiteInfoData(data: data) {
                self.lock.lock()
                self.customSiteInfoArray = siteInfoArray
                self.lock.unlock()
            }else{
                isFail = true
                AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_FetchSiteInfoError_CustomSiteInfo", comment: "ことせかい 用のSiteInfoデータの読み込みに失敗しました。この失敗により、小説をダウンロードする時に、小説の本文部分を抽出できず、本文以外の文字列も取り込む事になる可能性が高まります。\nネットワーク状況を確認の上、「設定タブ」→「SiteInfoを取得し直す」を実行して再取得を試みてください。\nそれでも同様の問題が報告される場合には、「設定タブ」→「開発者に問い合わせる」よりこのエラーメッセージを添えてお問い合わせください。"), appendix: [
                        "customSiteInfoURL": customSiteInfoURL.absoluteString
                    ], isForDebug: false)
            }
            announceLoadEnd()
            if isFail {
                return NovelSpeakerUtility.GenerateNSError(msg: "siteInfo or customSiteInfo decode error.")
            }
            return nil
        }
        
        // Autopagerize の SiteInfo を読み込むと読み込むだけで 2MBytes 以上使ってしまうので
        // watchOS では Autopagerize の SiteInfo については読み込まないようにします
        // WARN: TODO: つまり、ことせかい用の SiteInfo が巨大になった場合同様に問題が発生しえます
        #if !os(watchOS)
        NiftyUtility.FileCachedHttpGet(url: siteInfoURL, cacheFileName: cacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, canRecoverOldFile: true, successAction: { (data) in
            siteInfoData = data
            NiftyUtility.FileCachedHttpGet(url: customSiteInfoURL, cacheFileName: self.customCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, canRecoverOldFile: true, successAction: { (data) in
                customSiteInfoData = data
                let result = updateSiteInfo(siteInfoData: siteInfoData, customSiteInfoData: customSiteInfoData)
                completion?(result)
            }) { (err) in
                let result = updateSiteInfo(siteInfoData: siteInfoData, customSiteInfoData: nil)
                completion?(result)
            }
        }) { (err) in
            NiftyUtility.FileCachedHttpGet(url: customSiteInfoURL, cacheFileName: self.customCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, canRecoverOldFile: true, successAction: { (data) in
                customSiteInfoData = data
                let result = updateSiteInfo(siteInfoData: nil, customSiteInfoData: customSiteInfoData)
                completion?(result)
            }) { (err) in
                AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_FetchSiteInfoError_FetchError", comment: "全てのSiteInfoデータの読み込みに失敗しました。この失敗により、小説をダウンロードする時に、小説の本文部分を抽出できず、本文以外の文字列も取り込む事になる可能性が高まります。\nネットワーク状況を確認の上、「設定タブ」→「SiteInfoを取得し直す」を実行して再取得を試みてください。\nそれでも同様の問題が報告される場合には、「設定タブ」→「開発者に問い合わせる」よりこのエラーメッセージを添えてお問い合わせください。"), appendix: [
                        "siteInfoURL": siteInfoURL.absoluteString,
                        "customSiteInfoURL": customSiteInfoURL.absoluteString,
                        "lastError": err?.localizedDescription ?? "nil"
                    ], isForDebug: false)
                announceLoadEnd()
                completion?(NovelSpeakerUtility.GenerateNSError(msg: "siteInfo and customSiteInfo fetch failed."))
            }
        }
        #else
        NiftyUtility.FileCachedHttpGet(url: customSiteInfoURL, cacheFileName: customCacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, canRecoverOldFile: true, successAction: { (data) in
            customSiteInfoData = data
            completion?(updateSiteInfo(siteInfoData: nil, customSiteInfoData: customSiteInfoData))
        }) { (err) in
            AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_FetchSiteInfoError_FetchError", comment: "全てのSiteInfoデータの読み込みに失敗しました。この失敗により、小説をダウンロードする時に、小説の本文部分を抽出できず、本文以外の文字列も取り込む事になる可能性が高まります。\nネットワーク状況を確認の上、「設定タブ」→「SiteInfoを取得し直す」を実行して再取得を試みてください。\nそれでも同様の問題が報告される場合には、「設定タブ」→「開発者に問い合わせる」よりこのエラーメッセージを添えてお問い合わせください。"), appendix: [
                    "customSiteInfoURL": customSiteInfoURL.absoluteString,
                    "lastError": err?.localizedDescription ?? "nil"
                ], isForDebug: false)
            announceLoadEnd()
            completion?(NovelSpeakerUtility.GenerateNSError(msg: "siteInfo and customSiteInfo fetch failed."))
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

    func LoadAboutPage() {
        #if !os(watchOS)
        self.httpClient.LoadAboutPage()
        #endif
    }
    
    func DecodeDocument(currentState:StoryState, html:String?, encoding:String.Encoding, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        // TODO: この辺りに取得したHTMLをlogに吐くような奴を作っておくと良さげ？
        guard let html = html, let htmlDocument = try? HTML(html: html, encoding: encoding) else {
            failedAction?(currentState.url, NSLocalizedString("UriLoader_HTMLParseFailed_Parse", comment: "HTMLの解析に失敗しました。(有効なHTMLまたはXHTML文書ではないようです。いまのところ、ことせかい はPDF等のHTMLやXHTMLではない文書は読み込む事ができません)"))
            return
        }
        func mergeTag(prevTagArray:[String], newTagArray:[String]) -> [String] {
            var tagSet = Set<String>(prevTagArray)
            tagSet.formUnion(Set<String>(newTagArray))
            return Array(tagSet)
        }
        
        for siteInfo in currentState.siteInfoArray {
            let pageElement = siteInfo.decodePageElement(xmlDocument: htmlDocument).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let nextUrl = siteInfo.decodeNextLink(xmlDocument: htmlDocument, baseURL: currentState.url)
            let firstPageLink = siteInfo.decodeFirstPageLink(xmlDocument: htmlDocument, baseURL: currentState.url)
            #if !os(watchOS)
            let nextButton:Element? = siteInfo.nextButton != nil ? currentState.document?.querySelectorAll(siteInfo.nextButton!).first : nil
            let firstPageButton:Element? = siteInfo.firstPageButton != nil ? currentState.document?.querySelectorAll(siteInfo.firstPageButton!).first : nil
            if pageElement.count <= 0 && nextUrl == nil && firstPageLink == nil && nextButton == nil && firstPageButton == nil {
                continue
            }
            let forceClickButton:Element? = siteInfo.forceClickButton != nil ? currentState.document?.querySelectorAll(siteInfo.forceClickButton!).first : nil
            #else
            if pageElement.count <= 0 && nextUrl == nil && firstPageLink == nil {
                continue
            }
            // pageElement が抽出できなくて、URL全般にマッチしそうな奴は信用しません。
            if pageElement.count <= 0 && ["^https?://...", "^https?://..+", "^https?://..", "^https?://.+", "^https?://."].contains(siteInfo.url?.pattern ?? "") {
                continue
            }
            #endif
            //print("match success: pageElement.count: \(pageElement.count), nextUrl: \(nextUrl?.absoluteString ?? "nil"), firstPageLink: \(firstPageLink?.absoluteString ?? "nil"), hitSiteInfo: \(siteInfo)")
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
                    tagArray: mergeTag(prevTagArray: currentState.tagArray, newTagArray: siteInfo.decodeTag(xmlDocument: htmlDocument)),
                    siteInfoArray: currentState.siteInfoArray,
                    isNeedHeadless: currentState.isNeedHeadless,
                    waitSecondInHeadless: currentState.waitSecondInHeadless,
                    previousContent: currentState.previousContent,
                    document: currentState.document,
                    nextButton: nextButton,
                    firstPageButton: firstPageButton,
                    forceClickButton: forceClickButton
                )
            )
            #else
            successAction?(StoryState(url: currentState.url, cookieString: currentState.cookieString, content: pageElement, nextUrl: siteInfo.decodeNextLink(xmlDocument: htmlDocument, baseURL: currentState.url), firstPageLink: siteInfo.decodeFirstPageLink(xmlDocument: htmlDocument, baseURL: currentState.url), title: siteInfo.decodeTitle(xmlDocument: htmlDocument), author: siteInfo.decodeAuthor(xmlDocument: htmlDocument), subtitle: siteInfo.decodeSubtitle(xmlDocument: htmlDocument), tagArray: mergeTag(prevTagArray: currentState.tagArray, newTagArray: siteInfo.decodeTag(xmlDocument: htmlDocument)), siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent))
            #endif
            return
        }
        //print("no match content. url: \(currentState.url), SiteInfoArray: \(currentState.siteInfoArray)")
        failedAction?(currentState.url, NSLocalizedString("UriLoader_HTMLParseFailed_ContentIsNil", comment: "HTMLの解析に失敗しました。(文書の中身を取り出せませんでした。ことせかい のサポートサイト側のご意見ご要望フォームや設定→開発者に問い合わせる等から、このエラーの起こったURLとエラーが起こるまでの手順を添えて報告して頂くことで解決できるかもしれません)"))
    }
    
    // 与えられた StoryState に示される「何をしたら次の本文が取得できるか」を実行して本文を取り出します。
    // 具体的には、
    // 本文の読み込みに成功するとその時の StoryState を引数として successAction を呼び出します。
    // successAction が呼び出されたら、
    func FetchNext(currentState:StoryState, fetchTimeToLive:Int = 5, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?){
        // 入力に有効な content があるならそこで探索は終わり
        if let content = currentState.content, content.count > 0 {
            // previousContent に何か入っているという事は、読み込み
            if let previousContent = currentState.previousContent, content == previousContent {
                failedAction?(currentState.url, NSLocalizedString("StoryFetcher_FetchNext_ErrorSameContent", comment: "同じ内容が読み込まれているようです。次のページの検出に失敗しているとみなして失敗とします。"))
                return
            }
            successAction?(currentState)
            return
        }
        
        if fetchTimeToLive <= 0 {
            failedAction?(currentState.url, NSLocalizedString("StoryFetcher_FetchFirstContent_ExceededCountToLive", comment: "本文を取り出せませんでした。(本文へのリンクが発見できないまま読み込み回数上限に達しました)"))
            return
        }
        
        var withWaitSecond:TimeInterval? = nil
        #if !os(watchOS)
        // waitSecondInHeadless が指定されていたらその秒だけ待ちます
        if let waitSecondInHeadless = currentState.waitSecondInHeadless {
            withWaitSecond = waitSecondInHeadless
        }
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
                                completionHandler?(nil, NovelSpeakerUtility.GenerateNSError(msg: "unknown error: (Erik document = nil)"))
                                return
                            }
                            guard let html = document.innerHTML else {
                                completionHandler?(nil, NovelSpeakerUtility.GenerateNSError(msg: "unknown error: (Erik document.innerHTML?.data() return nil)"))
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
                            let newState:StoryState = StoryState(url: currentUrl, cookieString: cookieString ?? currentState.cookieString, content: nil, nextUrl: nil, firstPageLink: nil, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: true, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, document: document, nextButton: nil, firstPageButton: nil, forceClickButton: nil)
                            self.DecodeDocument(currentState: newState, html: html, encoding: .utf8, successAction: { (state) in
                                completionHandler?(state, nil)
                            }) { (_, err) in
                                completionHandler?(nil, NovelSpeakerUtility.GenerateNSError(msg: err))
                            }
                        }
                    }
                }
            }
        }
        
        // 押さねばならないボタンがあるのなら押す
        if let element = currentState.forceClickButton {
            buttonClick(buttonElement: element, currentState: currentState) { (state, err) in
                if let state = state {
                    // TTL を減らして再取得したつもりになって評価しなおします。
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, successAction: successAction, failedAction: failedAction)
                    return
                }
                failedAction?(currentState.url, err?.localizedDescription ?? "unknown error: ForceClickButton")
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
        
        func fetchUrlWithRobotsCheck(url:URL, currentState:StoryState) {
            // TODO: 謎の固定値
            let novelSpeakerUserAgent = "NovelSpeaker/2"
            RobotsFileTool.shared.CheckRobotsTxt(url: url, userAgentString: novelSpeakerUserAgent) { (result) in
                if result {
                    fetchUrl(url: url, currentState: currentState)
                    return
                }
                failedAction?(url, NSLocalizedString("StoryFetcher_FetchError_RobotsText", comment: "Webサイト様側で機械的なアクセスを制限されているサイトであったため、ことせかい による取得ができません。"))
            }
        }
        
        // URL を GET した後に本文を取り出す時の挙動
        // 状態を更新してDecodeDocument()を呼び出すだけです
        func fetchUrl(url:URL, currentState:StoryState) {
            print("fetchUrl:", url.absoluteString, "isNeedHeadless:", currentState.isNeedHeadless ? "true" : "false")
            BehaviorLogger.AddLog(description: "Fetch URL", data: ["url": url.absoluteString, "isNeedHeadless": currentState.isNeedHeadless])
            #if !os(watchOS)
            if currentState.isNeedHeadless {
                NiftyUtility.httpHeadlessRequest(url: url, postData: nil, cookieString: currentState.cookieString, mainDocumentURL: url, httpClient: self.httpClient, withWaitSecond: withWaitSecond, successAction: { (doc) in
                    let html = doc.innerHTML
                    let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, document: doc, nextButton: currentState.nextButton, firstPageButton: currentState.firstPageButton, forceClickButton: currentState.forceClickButton)
                    self.DecodeDocument(currentState: newState, html: html, encoding: .utf8, successAction: { (state) in
                        self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, successAction: successAction, failedAction: failedAction)
                    }, failedAction: failedAction)
                }) { (error) in
                    failedAction?(currentState.url, error?.localizedDescription ?? "httpHeadlessRequest return unknown error(nil)")
                }
                return
            }
            #endif
            
            let isDisallowsCellularAccess:Bool = RealmUtil.RealmBlock { (realm) -> Bool in
                return RealmGlobalState.GetInstanceWith(realm: realm)?.IsDisallowsCellularAccess ?? false
            }
            
            NiftyUtility.httpRequest(url: url, postData: nil, cookieString: currentState.cookieString, isNeedHeadless: currentState.isNeedHeadless, mainDocumentURL: url, allowsCellularAccess: isDisallowsCellularAccess ? false : true, successAction: { (data, encoding) in
                #if !os(watchOS)
                let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, document: currentState.document, nextButton: currentState.nextButton, firstPageButton: currentState.firstPageButton, forceClickButton: currentState.forceClickButton)
                #else
                let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent)
                #endif
                let (html, guessedEncoding) = NiftyUtility.decodeHTMLStringFrom(data: data, headerEncoding: encoding)
                self.DecodeDocument(currentState: newState, html: html, encoding: guessedEncoding ?? encoding ?? .utf8, successAction: { (state) in
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, successAction: successAction, failedAction: failedAction)
                }, failedAction: failedAction)
            }) { (error) in
                failedAction?(currentState.url, error?.localizedDescription ?? "httpRequest return unknown error(nil)")
            }
        }
        
        if let firstPageLink = currentState.firstPageLink {
            // firstPageLink があるならそれを辿る
            fetchUrlWithRobotsCheck(url: firstPageLink, currentState: currentState)
            return
        }
        if let nextUrl = currentState.nextUrl {
            // nextUrl があるならそれを辿る
            fetchUrlWithRobotsCheck(url: nextUrl, currentState: currentState)
            return
        }

        failedAction?(currentState.url, NSLocalizedString("StoryFetcher_CanNotFindPageElementAndNextLink", comment: "指定されたURLからは本文や次ページを示すURLなどを取得できませんでした。"))
    }
    
    static func CreateFirstStoryStateWithoutCheckLoadSiteInfoWith(siteInfoArray:[StorySiteInfo], url:URL, cookieString:String?, previousContent:String?) -> StoryState {
        let isNeedHeadless:Bool = siteInfoArray.reduce(false) { (result, siteInfo) -> Bool in
            if result || siteInfo.isNeedHeadless { return true }
            return false
        }
        let waitSecondInHeadless:Double = siteInfoArray.reduce(0.0) { (result, siteInfo) -> Double in
            if let waitSecondInHeadless = siteInfo.waitSecondInHeadless, result < waitSecondInHeadless { return waitSecondInHeadless }
            return result
        }
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: url, firstPageLink: nil, title: nil, author: nil, subtitle: nil, tagArray: [], siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: false, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, document: nil, nextButton: nil, firstPageButton: nil, forceClickButton: nil)
        #else
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: url, firstPageLink: nil, title: nil, author: nil, subtitle: nil, tagArray: [], siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: false, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent)
        #endif
    }

    static func CreateFirstStoryStateWithoutCheckLoadSiteInfo(url:URL, cookieString:String?, previousContent:String?) -> StoryState {
        let siteInfoArray = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: url.absoluteString)
        return CreateFirstStoryStateWithoutCheckLoadSiteInfoWith(siteInfoArray: siteInfoArray, url: url, cookieString: cookieString, previousContent: previousContent)
    }
    
    static func CreateFirstStoryState(url:URL, cookieString:String?, previousContent:String?, completion:((StoryState)->Void)?) {
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady {
            completion?(CreateFirstStoryStateWithoutCheckLoadSiteInfo(url:url, cookieString: cookieString, previousContent: previousContent))
        }
    }
    
    func FetchFirst(url:URL, cookieString:String?, previousContent:String?, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, previousContent: previousContent, completion:{ (dummyState) in
            self.FetchNext(currentState: dummyState, successAction: successAction, failedAction: failedAction)
        })
    }
    
    private func FetchFirstContentRecurcive(currentState:StoryState, countToLive:Int = 10, nextFetchTime:Date = Date(timeIntervalSince1970: 0), successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        print("FetchFirstContentRecurcive in. \(currentState.url.absoluteString)")
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
                self.FetchFirstContentRecurcive(currentState: state, countToLive: countToLive - 1, nextFetchTime: Date(timeIntervalSinceNow: 1.05), successAction: successAction, failedAction: failedAction)
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
    func FetchFirstContent(url:URL, cookieString:String?, previousContent:String?, completion:((_ requestURL:URL, _ state:StoryState?, _ errorDescriptionString:String?)->Void)?) {
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, previousContent: previousContent, completion: { (state) in
            self.FetchFirstContentRecurcive(currentState: state, successAction: { (state) in
                completion?(url, state, nil)
            }, failedAction: { (url, errorString) in
                completion?(url, nil, errorString)
            })
        })
    }
}
