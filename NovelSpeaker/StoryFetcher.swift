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
    let forceErrorMessage: String?
    
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
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, document: document, nextButton: nextButton, firstPageButton: firstPageButton, forceClickButton: forceClickButton, forceErrorMessage: forceErrorMessage)
        #else
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, forceErrorMessage: forceErrorMessage)
        #endif
    }
    
    func TitleChanged(title:String) -> StoryState {
        #if !os(watchOS)
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: self.previousContent, document: document, nextButton: nextButton, firstPageButton: firstPageButton, forceClickButton: forceClickButton, forceErrorMessage: forceErrorMessage)
        #else
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: self.previousContent, forceErrorMessage: forceErrorMessage)
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
            description += """
forceErrorElementIsAlive_ErrorMessage: \(forceErrorMessage ?? "nil")
"""
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
    let resourceUrl:String?
    let overrideUserAgent:String?
    let forceErrorMessageAndElement: String?
    let scrollTo: String?
    let isNeedWhitespaceSplitForTag: Bool
    
    init(pageElement:String, url:String?, title:String?, subtitle:String?, firstPageLink:String?, nextLink:String?, tag:String?, author:String?, isNeedHeadless:String?, injectStyle:String?, nextButton: String?, firstPageButton: String?, waitSecondInHeadless: Double?, forceClickButton:String?, resourceUrl:String?, overrideUserAgent:String?, forceErrorMessageAndElement:String?, scrollTo:String?, isNeedWhitespaceSplitForTag:String?) {
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
        self.resourceUrl = resourceUrl
        self.overrideUserAgent = overrideUserAgent
        self.forceErrorMessageAndElement = forceErrorMessageAndElement
        self.scrollTo = scrollTo
        if let isNeedWhitespaceSplitForTagString = isNeedWhitespaceSplitForTag, isNeedWhitespaceSplitForTagString.count > 0 && !falseValues.contains(isNeedWhitespaceSplitForTagString) {
            self.isNeedWhitespaceSplitForTag = true
        }else{
            self.isNeedWhitespaceSplitForTag = false
        }
    }
    
    var forceErrorMessage : String? {
        get {
            guard let forceErrorMessageAndElement = self.forceErrorMessageAndElement else { return nil }
            let components = forceErrorMessageAndElement.components(separatedBy: ":")
            if components.count >= 2 {
                return components[0]
            }
            return nil
        }
    }
    var forceErrorElement : String? {
        get {
            guard let forceErrorMessageAndElement = self.forceErrorMessageAndElement else { return nil }
            let components = forceErrorMessageAndElement.components(separatedBy: ":")
            if components.count >= 2 {
                return components[1...].joined(separator: ":")
            }
            return nil
        }
    }

    func isMatchUrl(urlString:String) -> Bool {
        guard let urlRegex = self.url else { return false }
        if urlRegex.matches(in: urlString, options: [], range: NSMakeRange(0, urlString.count)).count > 0 {
            return true
        }
        return false
    }
    
    func decodePageElement(xmlDocument:Kanna.XMLDocument) -> String {
        return NovelSpeakerUtility.NormalizeNewlineString(string: NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: pageElement, injectStyle: injectStyle).trimmingCharacters(in: .whitespacesAndNewlines) )
    }
    func decodeTitle(xmlDocument:Kanna.XMLDocument) -> String? {
        guard let xpath = title, xpath.count > 0 else { return nil }
        return NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeSubtitle(xmlDocument:Kanna.XMLDocument) -> String? {
        guard let xpath = subtitle, xpath.count > 0 else { return nil }
        return NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeFirstPageLink(xmlDocument:Kanna.XMLDocument, baseURL: URL) -> URL? {
        guard let xpath = firstPageLink, xpath.count > 0 else { return nil }
        return NiftyUtility.FilterXpathWithExtructFirstHrefLink(xmlDocument: xmlDocument, xpath: xpath, baseURL: baseURL)
    }
    func decodeNextLink(xmlDocument:Kanna.XMLDocument, baseURL: URL) -> URL? {
        guard let xpath = nextLink, xpath.count > 0 else { return nil }
        return NiftyUtility.FilterXpathWithExtructFirstHrefLink(xmlDocument: xmlDocument, xpath: xpath, baseURL: baseURL)
    }
    func decodeAuthor(xmlDocument:Kanna.XMLDocument) -> String? {
        guard let xpath = author, xpath.count > 0 else { return nil }
        return NiftyUtility.FilterXpathWithConvertString(xmlDocument: xmlDocument, xpath: xpath).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func decodeTag(xmlDocument:Kanna.XMLDocument) -> [String] {
        guard let xpath = tag, xpath.count > 0 else { return [] }
        return Array(NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: xmlDocument, xpath: xpath, isNeedWhitespaceSplitForTag: isNeedWhitespaceSplitForTag))
    }
    func decodeForceErrorElement(xmlDocument:Kanna.XMLDocument) -> Bool {
        guard let xpath = forceErrorElement, xpath.count > 0 else { return false }
        let ret = NiftyUtility.FilterXpathWithExtructTagString(xmlDocument: xmlDocument, xpath: xpath, isNeedWhitespaceSplitForTag: isNeedWhitespaceSplitForTag)
        return ret.count > 0
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
        result += "\"\nresourceUrl: \"" + (resourceUrl ?? "nil")
        result += "\"\noverrideUserAgent: \"" + (overrideUserAgent ?? "nil")
        result += "\"\nforceErrorMessageAndElement: \"" + (forceErrorMessageAndElement ?? "nil")
        result += "\"\nscrollTo: \"" + (scrollTo ?? "nil")
        result += "\"\nisNeedWhitespaceSplitForTag: \"" + (isNeedWhitespaceSplitForTag ? "true" : "false")
        result += "\""
        return result
    }
}

extension StorySiteInfo : Decodable {
    enum CodingKeys: String, CodingKey {
        case data
        case resource_url
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
        case overrideUserAgent
        case forceErrorMessageAndElement
        case scrollTo
        case isNeedWhitespaceSplitForTag
    }
    
    init(from decoder: Decoder) throws {
        let toplevelValue = try decoder.container(keyedBy: CodingKeys.self)

        resourceUrl = try? toplevelValue.decode(String.self, forKey: .resource_url)
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
            case "False":
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
        overrideUserAgent = try? values.decode(String.self, forKey: NestedKeys.overrideUserAgent)
        forceClickButton = try? values.decode(String.self, forKey: NestedKeys.forceClickButton)
        scrollTo = try? values.decode(String.self, forKey: NestedKeys.scrollTo)
        #else
        waitSecondInHeadless = 0
        overrideUserAgent = nil
        forceClickButton = nil
        scrollTo = nil
        #endif
        forceErrorMessageAndElement = try? values.decode(String.self, forKey: NestedKeys.forceErrorMessageAndElement)
        let isNeedWhitespaceSplitForTagString = try? values.decode(String.self, forKey: NestedKeys.isNeedWhitespaceSplitForTag)
        if let isNeedWhitespaceSplitForTagString = isNeedWhitespaceSplitForTagString, isNeedWhitespaceSplitForTagString.count > 0 {
            switch isNeedWhitespaceSplitForTagString.lowercased() {
            case "false":
                isNeedWhitespaceSplitForTag = false
            case "False":
                isNeedWhitespaceSplitForTag = false
            case "nil":
                isNeedWhitespaceSplitForTag = false
            case "0":
                isNeedWhitespaceSplitForTag = false
            default:
                isNeedWhitespaceSplitForTag = true
            }
        }else{
            isNeedWhitespaceSplitForTag = false
        }
    }
}

class StoryHtmlDecoder {
    var siteInfoArrayArray:[[StorySiteInfo]] = []
    let fallbackSiteInfoArray:[StorySiteInfo]
    let lock = NSLock()
    var siteInfoLoadDoneHandlerArray:[(_ errorString:String?)->Void] = []
    var cacheFileExpireTimeinterval:Double = 60*60*24
    var nextExpireDate:Date = Date(timeIntervalSince1970: 0)
    var siteInfoNowLoading:Bool = false
    
    static let AutopagerizeSiteInfoJSONURL = "http://wedata.net/databases/AutoPagerize/items.json"
    static let NovelSpeakerSiteInfoJSONURL = "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1/items.json"
    static let NovelSpeakerSiteInfoTSVURL = "https://docs.google.com/spreadsheets/d/1t2wFx8psbc4EZxlacCas6lknO1S_PW6wsR9Qxq7HEnM/pub?gid=0&single=true&output=tsv"

    // シングルトンにしている。
    static let shared = StoryHtmlDecoder()
    private init(){
        fallbackSiteInfoArray = [
            //StorySiteInfo(pageElement: "//*[contains(@class,'autopagerize_page_element') or contains(@itemprop,'articleBody') or contains(concat(' ', normalize-space(@class), ' '), ' hentry ') or contains(concat(' ', normalize-space(@class), ' '), ' h-entry ')]", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: "(//link|//a)[contains(concat(' ', translate(normalize-space(@rel),'NEXT','next'), ' '), ' next ')]", tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: nil, resourceUrl: "fallbackSiteInfoArray(@itemprop,'articleBody')"),
            StorySiteInfo(pageElement: "//body", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: nil, resourceUrl: "fallbackSiteInfoArray(//body)", overrideUserAgent: nil, forceErrorMessageAndElement: nil, scrollTo: nil, isNeedWhitespaceSplitForTag: nil)
        ]
    }
    
    var IsSiteInfoReady: Bool {
        get {
            // 設定されているSiteInfo URLのリスト分だけ正しくSiteInfoが読み込めていることを確認することにします
            let targetURLArray = getLoadTargetURLs()
            return targetURLArray.filter({$0 != nil}).count <= self.siteInfoArrayArray.filter({$0.count > 0}).count
        }
    }
    var readySiteInfoCount: Int {
        get {
            return siteInfoArrayArray.reduce(0, {$0 + $1.count})
        }
    }
    var readySiteInfoDescription: String {
        get {
            var resultArray:[String] = []
            let siteInfoURLArray = getLoadTargetURLs()
            for (index, siteInfoArray) in siteInfoArrayArray.enumerated() {
                var description = "\(index): count: \(siteInfoArray.count)"
                if siteInfoURLArray.count > index, let url = siteInfoURLArray[index] {
                    description += ", \(generateCacheFileName(url: url, index: index)) <- \(url.absoluteString)"
                }
                resultArray.append(description)
            }
            return resultArray.joined(separator: "\n")
        }
    }
    
    static func DecodeTSVSiteInfoData(data:Data) -> [StorySiteInfo]? {
        guard let tsvString = String(data: data, encoding: .utf8) else { return nil }
        // 行ごとにデータを分割
        var lines:[String] = []
        tsvString.enumerateLines { line, stop in
            lines.append(line)
        }
        //let lines = tsvString.split(separator: "\r\n").map { String($0) }
        
        // 1行目は表題として使用
        guard let headerLine = lines.first else { return nil }
        
        let headers = headerLine.components(separatedBy: "\t")
        
        var result: [StorySiteInfo] = []
        // 2行目以降はデータとして処理
        for line in lines.dropFirst() {
            let values = line.components(separatedBy: "\t").map({$0 == "" ? nil : $0})
            var dict = [String: String]()
            
            for (header, value) in zip(headers, values) {
                dict[header] = value
            }
            
            guard let pageElement = dict["pageElement"] else { continue }
            
            // StorySiteInfoの各プロパティにマッピング
            let storySiteInfo = StorySiteInfo(
                pageElement: pageElement,
                url: dict["url"],
                title: dict["title"],
                subtitle: dict["subtitle"],
                firstPageLink: dict["firstPageLink"],
                nextLink: dict["nextLink"],
                tag: dict["tag"],
                author: dict["author"],
                isNeedHeadless: dict["isNeedHeadless"],
                injectStyle: dict["injectStyle"],
                nextButton: dict["nextButton"],
                firstPageButton: dict["firstPageButton"],
                waitSecondInHeadless: Double(dict["waitSecondInHeadless"] ?? "0"),
                forceClickButton: dict["forceClickButton"],
                resourceUrl: dict["resourceUrl"],
                overrideUserAgent: dict["overrideUserAgent"],
                forceErrorMessageAndElement: dict["forceErrorMessageAndElement"],
                scrollTo: dict["scrollTo"],
                isNeedWhitespaceSplitForTag: dict["isNeedWhitespaceSplitForTag"]
            )
            //print("add StorySiteInfo: \(storySiteInfo)")
            result.append(storySiteInfo)
        }
        if result.count <= 0 {
            //print("result.count <= 0: \(result.count), lines: \(lines)")
            return nil
        }
        return result
    }
    
    static func DecodeSiteInfoData(data:Data) -> [StorySiteInfo]? {
        // とりあえずJSONとしてデコードしようとしてみます。
        if let result = try? JSONDecoder().decode([StorySiteInfo].self, from: data), result.count > 0 {
            return result
        }
        // 駄目ならTSVとしてデコードしようとしてみます。
        return DecodeTSVSiteInfoData(data: data)
    }
    
    static func testSiteInfoURLValid(urlString:String, completion: @escaping (_ errorString: String?, _ urlString: String)->Void) {
        guard let url = URL(string: urlString) else {
            completion(NSLocalizedString("StoryHtmlDecoder_testSiteInfoURLValid_Error_InvalidURL", comment: "有効なURL文字列ではないようです。"), urlString)
            return
        }
        NiftyUtility.httpGet(url: url) {
            content,
            headerCharset in
            guard DecodeSiteInfoData(data: content) != nil else {
                completion(
                    NSLocalizedString(
                        "StoryHtmlDecoder_testSiteInfoURLValid_Error_GetURLFailed",
                        comment: "指定されたURLからの読み出しには成功したようですが、期待されている内容ではなく、JSONからSiteInfoの読み出しに失敗しています。正しいデータであるかどうか確認してください。"
                    ), urlString
                )
                return
            }
            completion(nil, urlString)
        } failedAction: { err in
            completion(NSLocalizedString("StoryHtmlDecoder_testSiteInfoURLValid_Error_GetRequestError", comment: "指定されたURLからの読み出しに失敗しています。正しいURLを記入していることや、ネットワーク接続状態などを確認してください。"), urlString)
        }
    }
    
    func generateCacheFileName(url:URL, index:Int) -> String {
        switch(url.absoluteString) {
        case StoryHtmlDecoder.AutopagerizeSiteInfoJSONURL:
            return "AutopagerizeSiteInfoCache"
        case StoryHtmlDecoder.NovelSpeakerSiteInfoJSONURL:
            return "NovelSpeakerSiteInfoCache"
        case StoryHtmlDecoder.NovelSpeakerSiteInfoTSVURL:
            return "novelSpeakerSiteInfoTSVCache"
        default:
            break
        }
        return "SiteInfoCache_\(index)"
    }
    
    func getLoadTargetURLs() -> [URL?] {
        var loadTargetUrls:[URL?] = []
        RealmUtil.RealmBlock { realm in
            // 優先度の高いSiteInfoArrayを先に登録します。
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                for urlString in globalState.preferredSiteInfoURLList {
                    if let url = URL(string: urlString) {
                        loadTargetUrls.append(url)
                    }else{
                        AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_InvalidURLString_preferredSiteInfoURLList", comment: "「優先SiteInfoリスト」に含まれる文字列にWebのURLではない文字列があるようです。"), appendix: ["invalid URL String" : urlString], isForDebug: false)
                    }
                }
                if let novelSpeakerURL = URL(string: globalState.novelSpeakerSiteInfoURL) {
                    loadTargetUrls.append(novelSpeakerURL)
                }else{
                    loadTargetUrls.append(URL(string: StoryHtmlDecoder.NovelSpeakerSiteInfoTSVURL))
                    if globalState.novelSpeakerSiteInfoURL != "" {
                        AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_InvalidURLString_for_NovelSPeakerSiteInfoURL", comment: "ことせかい用SiteInfo として設定されていたURLの形式が不正(URLとして読み込めない文字列)であったため、無視して標準の物を使います。"), appendix: ["invalidURLText": globalState.novelSpeakerSiteInfoURL], isForDebug: false)
                    }
                }
                // Autopagerize の SiteInfo を読み込むと読み込むだけで 2MBytes 以上使ってしまうので
                // watchOS では Autopagerize の SiteInfo については読み込まないようにします
                // WARN: TODO: つまり、ことせかい用の SiteInfo が巨大になった場合同様に問題が発生しえます
                #if !os(watchOS)
                if let autopagerizeURL = URL(string: globalState.autopagerizeSiteInfoURL) {
                    loadTargetUrls.append(autopagerizeURL)
                }else{
                    loadTargetUrls.append(URL(string: StoryHtmlDecoder.AutopagerizeSiteInfoJSONURL))
                    if globalState.autopagerizeSiteInfoURL != "" {
                        AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_InvalidURLString_for_AutopagerizeSiteInfoURL", comment: "次点のSiteInfo として設定されていたURLの形式が不正(URLとして読み込めない文字列)であったため、無視して標準の物を使います。"), appendix: ["invalidURLText": globalState.autopagerizeSiteInfoURL], isForDebug: false)
                    }
                }
                #endif
            }
        }
        return loadTargetUrls
    }
    
    func ClearSiteInfo() {
        self.lock.lock()
        siteInfoArrayArray.removeAll()
        self.lock.unlock()
        let targetURLArray = getLoadTargetURLs()
        for (index, url) in targetURLArray.enumerated() {
            if let url = url {
                NiftyUtility.FileCachedHttpGet_RemoveCacheFile(cacheFileName: generateCacheFileName(url: url, index: index))
            }
        }
        URLCache.shared.removeAllCachedResponses()
        LoadSiteInfoIfNeeded()
    }
    
    func SearchSiteInfoArrayFrom(urlString: String) -> [StorySiteInfo] {
        var result:[StorySiteInfo] = []
        self.lock.lock()
        defer { self.lock.unlock() }
        for siteInfoArray in siteInfoArrayArray {
            for siteInfo in siteInfoArray {
                if siteInfo.isMatchUrl(urlString: urlString) {
                    result.append(siteInfo)
                }
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
                handler(nil)
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
    
    func WaitLoadSiteInfoReady(handler: @escaping (_ errorString:String?)->Void){
        lock.lock()
        siteInfoLoadDoneHandlerArray.append(handler)
        lock.unlock()
        LoadSiteInfoIfNeeded()
    }
    
    // 標準のSiteInfoを非同期で読み込みます。
    func LoadSiteInfo(completion:((Error?)->Void)? = nil) {
        var errorMessage:String? = nil
        func announceLoadEnd(errorString:String?) {
            lock.lock()
            siteInfoNowLoading = false
            let targetArray = siteInfoLoadDoneHandlerArray
            siteInfoLoadDoneHandlerArray.removeAll()
            lock.unlock()
            for handler in targetArray {
                handler(errorString)
            }
        }
        func addErrorMessage(message:String) {
            if let currentMessage = errorMessage {
                errorMessage = currentMessage + "\n" + message
            }else{
                errorMessage = message
            }
        }

        let loadTargetUrls = getLoadTargetURLs()
        func siteInfoFetchAndUpdate(index:Int, targetURLArray:[URL?], cacheFileExpireTimeinterval:Double) {
            if index >= targetURLArray.count {
                // INFO: LoadSiteInfo() の終了処理をここでやっています
                announceLoadEnd(errorString: errorMessage)
                if let errorMessage = errorMessage {
                    completion?(NovelSpeakerUtility.GenerateNSError(msg: errorMessage))
                }else{
                    completion?(nil)
                }
                return
            }
            if let targetURL = targetURLArray[index] {
                let cacheFileName = generateCacheFileName(url: targetURL, index: index)
                let cachedFileData = NiftyUtility.GetCachedHttpGetCachedData(url: targetURL, cacheFileName: cacheFileName, expireTimeinterval: nil)
                NiftyUtility.FileCachedHttpGet(url: targetURL, cacheFileName: cacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, canRecoverOldFile: true, isNeedHeadless: false /*targetURL.absoluteString.starts(with: "https://docs.google.com/spreadsheets/")*/, successAction: { (data) in
                    func decodeSiteInfoArrayData(data: Data, cachedData: Data?) -> ([StorySiteInfo]?, Bool) {
                        var isValidData = false
                        var siteInfoArray:[StorySiteInfo]
                        if let httpSiteInfoArray = StoryHtmlDecoder.DecodeSiteInfoData(data: data) {
                            siteInfoArray = httpSiteInfoArray
                            isValidData = true
                        } else {
                            guard let cachedData = cachedFileData, let cachedSiteInfoArray = StoryHtmlDecoder.DecodeSiteInfoData(data: cachedData) else {
                                let firstLine = String(data: data, encoding: .utf8)?.getFirstLines(lineCount: 3, maxCharacterCount: 100)
                                AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_FetchSiteInfoError_DecodeSiteInfoData", comment: "SiteInfoデータの取り込みに失敗しています。\n対象のURLのデータは読み出せましたが、期待されているJSONまたはTSV形式ではないようです。"), appendix: [
                                    "targetURL": targetURL.absoluteString,
                                    "first part": firstLine ?? "-",
                                    "data count": "\(data.count)",
                                ], isForDebug: false)
                                return (nil, false)
                            }
                            let firstLine = String(data: data, encoding: .utf8)?.getFirstLines(lineCount: 3, maxCharacterCount: 100)
                            AppInformationLogger.AddLog(message: NSLocalizedString("StoryFetcher_FetchSiteInfoError_DecodeSiteInfoData_Recoverd", comment: "SiteInfoデータの取り込みに失敗しています。\n対象のURLのデータは読み出せましたが、期待されているJSONまたはTSV形式ではないようです。\nなお、以前正常に取得できていたデータから内容を復元できたのでそれを利用して処理を続けます。"), appendix: [
                                "targetURL": targetURL.absoluteString,
                                "first part": firstLine ?? "-",
                                "data count": "\(data.count)",
                            ], isForDebug: false)
                            siteInfoArray = cachedSiteInfoArray
                        }
                        siteInfoArray.sort { (a, b) -> Bool in
                            guard let aPattern = a.url?.pattern else { return false }
                            guard let bPattern = b.url?.pattern else { return true }
                            return aPattern.count > bPattern.count
                        }
                        return (siteInfoArray, isValidData)
                    }
                    let (siteInfoArray, isValidData) = decodeSiteInfoArrayData(data: data, cachedData: cachedFileData)
                    if let siteInfoArray = siteInfoArray {
                        self.lock.lock()
                        if index < self.siteInfoArrayArray.count {
                            self.siteInfoArrayArray[index] = siteInfoArray
                        }else{
                            self.siteInfoArrayArray.append(siteInfoArray)
                        }
                        self.lock.unlock()
                    }
                    siteInfoFetchAndUpdate(index: index+1, targetURLArray: targetURLArray, cacheFileExpireTimeinterval: cacheFileExpireTimeinterval)
                    return isValidData
                }) { (err) in
                    guard let cachedFileData = cachedFileData, let cachedSiteInfoArray = StoryHtmlDecoder.DecodeSiteInfoData(data: cachedFileData) else {
                        let message = NSLocalizedString("StoryFetcher_FetchSiteInfoError_FetchError", comment: "SiteInfoデータの読み込みに失敗しました。この失敗により、小説をダウンロードする時に、小説の本文部分を抽出できず、本文以外の文字列も取り込む事になる可能性が高まります。\nネットワーク状況を確認の上、「設定タブ」→「SiteInfoを取得し直す」を実行して再取得を試みてください。\nもし、「設定タブ」→「内部データ参照用URLの設定」で設定値を書き換えている場合、それらの値が正しいものかどうかを再度確認してください。それでも同様の問題が報告される場合には、「設定タブ」→「開発者に問い合わせる」内の『「アプリ内エラーのお知らせ」の内容を添付する』をONにする事でこのエラーを添付した状態でお問い合わせください。")
                        AppInformationLogger.AddLog(message: message, appendix: [
                            "targetURL": targetURL.absoluteString,
                            "lastError": err?.localizedDescription ?? "nil"
                        ], isForDebug: false)
                        addErrorMessage(message: message)
                        siteInfoFetchAndUpdate(index: index+1, targetURLArray: targetURLArray, cacheFileExpireTimeinterval: cacheFileExpireTimeinterval)
                        return
                    }
                    let message = NSLocalizedString("StoryFetcher_FetchSiteInfoError_FetchError_Recoverd", comment: "SiteInfoデータの読み込みに失敗しました。この失敗により、小説をダウンロードする時に、小説の本文部分を抽出できず、本文以外の文字列も取り込む事になる可能性が高まります。\nネットワーク状況を確認の上、「設定タブ」→「SiteInfoを取得し直す」を実行して再取得を試みてください。\nもし、「設定タブ」→「内部データ参照用URLの設定」で設定値を書き換えている場合、それらの値が正しいものかどうかを再度確認してください。それでも同様の問題が報告される場合には、「設定タブ」→「開発者に問い合わせる」内の『「アプリ内エラーのお知らせ」の内容を添付する』をONにする事でこのエラーを添付した状態でお問い合わせください。\nなお、以前正常に取得できていたデータから内容を復元できたのでそれを利用して処理を続けます。")
                    AppInformationLogger.AddLog(message: message, appendix: [
                        "targetURL": targetURL.absoluteString,
                        "lastError": err?.localizedDescription ?? "nil"
                    ], isForDebug: false)
                    let siteInfoArray = cachedSiteInfoArray
                    self.lock.lock()
                    if index < self.siteInfoArrayArray.count {
                        self.siteInfoArrayArray[index] = siteInfoArray
                    }else{
                        self.siteInfoArrayArray.append(siteInfoArray)
                    }
                    self.lock.unlock()
                    siteInfoFetchAndUpdate(index: index+1, targetURLArray: targetURLArray, cacheFileExpireTimeinterval: cacheFileExpireTimeinterval)
                }
            }
        }
        var cacheFileExpireTimeinterval:Double
        if RealmGlobalState.GetIsForceSiteInfoReloadIsEnabled() {
            cacheFileExpireTimeinterval = 0
        }else{
            cacheFileExpireTimeinterval = self.cacheFileExpireTimeinterval
        }
        siteInfoFetchAndUpdate(index: 0, targetURLArray: loadTargetUrls, cacheFileExpireTimeinterval: cacheFileExpireTimeinterval)
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
        //print("-----\nsiteInfoArray.count: \(currentState.siteInfoArray.count)")
        //for (n, siteInfo) in currentState.siteInfoArray.enumerated() {
        //    print("\(n): \(siteInfo.resourceUrl ?? "nil")")
        //}
        //print("-----")
        
        var tryedResourceUrlArray:[String] = []
        for siteInfo in currentState.siteInfoArray {
            if let resourceUrl = siteInfo.resourceUrl {
                tryedResourceUrlArray.append(resourceUrl)
            }
            let pageElement = siteInfo.decodePageElement(xmlDocument: htmlDocument).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            //print("checking SiteInfo. pageElement.count: \(pageElement.count), siteInfo.pageElement: \(siteInfo.pageElement), siteInfoArray.count: \(currentState.siteInfoArray.count), siteInfo: \(siteInfo.description)")
            let nextUrl = siteInfo.decodeNextLink(xmlDocument: htmlDocument, baseURL: currentState.url)
            let firstPageLink = siteInfo.decodeFirstPageLink(xmlDocument: htmlDocument, baseURL: currentState.url)
            let forceErrorElementIsAlive_ErrorMessage:String?
            if siteInfo.decodeForceErrorElement(xmlDocument: htmlDocument) == true, let errMessage = siteInfo.forceErrorMessage {
                forceErrorElementIsAlive_ErrorMessage = errMessage
            }else{
                forceErrorElementIsAlive_ErrorMessage = nil
            }
            #if !os(watchOS)
            let nextButton:Element? = siteInfo.nextButton != nil ? currentState.document?.querySelectorAll(siteInfo.nextButton!).first : nil
            let firstPageButton:Element? = siteInfo.firstPageButton != nil ? currentState.document?.querySelectorAll(siteInfo.firstPageButton!).first : nil
            let forceClickButton:Element?
            if let forceClickButtonSelector = siteInfo.forceClickButton {
                forceClickButton = currentState.document?.querySelectorAll(forceClickButtonSelector).first
            }else{
                forceClickButton = nil
            }
            if pageElement.count <= 0 && nextUrl == nil && firstPageLink == nil && nextButton == nil && firstPageButton == nil && forceClickButton == nil && forceErrorElementIsAlive_ErrorMessage == nil {
                //print("continue: \(siteInfo.resourceUrl ?? "nil")")
                continue
            }
            #else
            if pageElement.count <= 0 && nextUrl == nil && firstPageLink == nil && forceErrorElementIsAlive_ErrorMessage == nil {
                continue
            }
            // pageElement が抽出できなくて、URL全般にマッチしそうな奴は信用しません。
            if pageElement.count <= 0 && ["^https?://...", "^https?://..+", "^https?://..", "^https?://.+", "^https?://."].contains(siteInfo.url?.pattern ?? "") {
                continue
            }
            #endif
            //print("match success: pageElement.count: \(pageElement.count), nextUrl: \(nextUrl?.absoluteString ?? "nil"), firstPageLink: \(firstPageLink?.absoluteString ?? "nil"), nextButton: \(nextButton != nil ? "has" : "nil"), firstPageButton: \(firstPageButton != nil ? "has" : "nil"), (forceClickButton: \(forceClickButton != nil ? "has" : "nil"), && siteInfo.isNeedHeadless: \(siteInfo.isNeedHeadless), && forceErrorElementIsAlive_ErrorMessage: \(forceErrorElementIsAlive_ErrorMessage ?? "nil"))")
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
                    forceClickButton: forceClickButton,
                    forceErrorMessage: forceErrorElementIsAlive_ErrorMessage
                )
            )
            #else
            successAction?(StoryState(url: currentState.url, cookieString: currentState.cookieString, content: pageElement, nextUrl: siteInfo.decodeNextLink(xmlDocument: htmlDocument, baseURL: currentState.url), firstPageLink: siteInfo.decodeFirstPageLink(xmlDocument: htmlDocument, baseURL: currentState.url), title: siteInfo.decodeTitle(xmlDocument: htmlDocument), author: siteInfo.decodeAuthor(xmlDocument: htmlDocument), subtitle: siteInfo.decodeSubtitle(xmlDocument: htmlDocument), tagArray: mergeTag(prevTagArray: currentState.tagArray, newTagArray: siteInfo.decodeTag(xmlDocument: htmlDocument)), siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, forceErrorMessage: forceErrorElementIsAlive_ErrorMessage))
            #endif
            return
        }
        //print("no match content. url: \(currentState.url), SiteInfoArray: \(currentState.siteInfoArray)")
        failedAction?(currentState.url, NSLocalizedString("UriLoader_HTMLParseFailed_ContentIsNil", comment: "HTMLの解析に失敗しました。(文書の中身を取り出せませんでした。ことせかい のサポートサイト側のご意見ご要望フォームや設定→開発者に問い合わせる等から、このエラーの起こったURLとエラーが起こるまでの手順を添えて報告して頂くことで解決できるかもしれません)")
            + """
            \nurl: \(currentState.url.absoluteString)
            SiteInfo resourceUrls(\(tryedResourceUrlArray.count)): [
              \(tryedResourceUrlArray.joined(separator: "\n  "))
            ]
            """)
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
                    print("error occurd at after button click:", err.localizedDescription, currentState.document?.innerHTML ?? "nil")
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
                            let newState:StoryState = StoryState(url: currentUrl, cookieString: cookieString ?? currentState.cookieString, content: nil, nextUrl: nil, firstPageLink: nil, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: true, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, document: document, nextButton: nil, firstPageButton: nil, forceClickButton: nil, forceErrorMessage: nil)
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
        
        // 失敗だと判定される文字列が設定されていたら失敗とする
        if let errorMessage = currentState.forceErrorMessage {
            AppInformationLogger.AddLog(message: errorMessage, isForDebug: false)
            failedAction?(currentState.url, errorMessage)
            return
        }
        
        // 押さねばならないボタンがあるのなら押す
        if let element = currentState.forceClickButton {
            print("force click: \(element)")
            buttonClick(buttonElement: element, currentState: currentState) { (state, err) in
                if let state = state {
                    // TTL を減らして再取得したつもりになって評価しなおします。
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, successAction: successAction, failedAction: failedAction)
                    return
                }
                failedAction?(currentState.url, err?.localizedDescription ?? "unknown error: ForceClickButton")
            }
            return
        }
        
        // 次ページへのボタンがあればそれを辿る
        if let element = currentState.nextButton {
            buttonClick(buttonElement: element, currentState: currentState) { (state, err) in
                if let state = state {
                    // TTL を減らして再取得したつもりになって評価しなおします。
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, successAction: successAction, failedAction: failedAction)
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
                    // TTL を減らして再取得したつもりになって評価しなおします。
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, successAction: successAction, failedAction: failedAction)
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
            let timeoutInterval:TimeInterval = 60*5 // TODO: 後で「正しい値(要定義)」をなんらかの方法で設定できるようにしたい。HeadlessHTTPClient 側にも同じ値が設定されている箇所がある
            #if !os(watchOS)
            if currentState.isNeedHeadless {
                // あまりよろしくない感じですが、siteInfoArray の中に overrideUserAgent が指定されているものがあれば、その最初の物を使うという事をしています。
                if let userAgentString = currentState.siteInfoArray.filter({ $0.overrideUserAgent?.count ?? 0 > 0 }).first?.overrideUserAgent {
                    //print("httpClient.overrideUserAgent: \"\(userAgentString)\"")
                    self.httpClient.overrideUserAgent(userAgentString: userAgentString)
                }else{
                    //print("httpClient.overrideUserAgent: nil")
                    self.httpClient.overrideUserAgent(userAgentString: nil)
                }
                let scrollToJavaScript:String?
                if let scrollTo = currentState.siteInfoArray.filter({$0.scrollTo != nil}).first?.scrollTo {
                    scrollToJavaScript = "document.evaluate(\"\(scrollTo)\", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null)?.singleNodeValue?.scrollIntoView({ behavior: 'auto' })"
                }else{
                    scrollToJavaScript = nil
                }
                NiftyUtility.httpHeadlessRequest(url: url, postData: nil, timeoutInterval: timeoutInterval, cookieString: currentState.cookieString, mainDocumentURL: url, httpClient: self.httpClient, withWaitSecond: withWaitSecond, injectJavaScript: scrollToJavaScript, successAction: { (doc) in
                    let html = doc.innerHTML
                    let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, document: doc, nextButton: currentState.nextButton, firstPageButton: currentState.firstPageButton, forceClickButton: currentState.forceClickButton, forceErrorMessage: currentState.forceErrorMessage)
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
            
            NiftyUtility.httpRequest(url: url, postData: nil, timeoutInterval: timeoutInterval, cookieString: currentState.cookieString, isNeedHeadless: currentState.isNeedHeadless, mainDocumentURL: url, allowsCellularAccess: isDisallowsCellularAccess ? false : true, successAction: { (data, encoding) in
                #if !os(watchOS)
                let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, document: currentState.document, nextButton: currentState.nextButton, firstPageButton: currentState.firstPageButton, forceClickButton: currentState.forceClickButton, forceErrorMessage: currentState.forceErrorMessage)
                #else
                let newState:StoryState = StoryState(url: url, cookieString: currentState.cookieString, content: currentState.content, nextUrl: nil, firstPageLink: currentState.firstPageLink, title: currentState.title, author: currentState.author, subtitle: currentState.subtitle, tagArray: currentState.tagArray, siteInfoArray: currentState.siteInfoArray, isNeedHeadless: currentState.isNeedHeadless, isCanFetchNextImmediately: currentState.isCanFetchNextImmediately, waitSecondInHeadless: currentState.waitSecondInHeadless, previousContent: currentState.previousContent, forceErrorMessage: currentState.forceErrorMessage)
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

        print("FetchNext() pageElement や nextUrl 等、なにも取り出せなかった: \(currentState.content ?? "currentState.content is nil")")
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
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: url, firstPageLink: nil, title: nil, author: nil, subtitle: nil, tagArray: [], siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: false, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, document: nil, nextButton: nil, firstPageButton: nil, forceClickButton: nil, forceErrorMessage: nil)
        #else
        return StoryState(url: url, cookieString: cookieString, content: nil, nextUrl: url, firstPageLink: nil, title: nil, author: nil, subtitle: nil, tagArray: [], siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: false, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, forceErrorMessage: nil)
        #endif
    }

    static func CreateFirstStoryStateWithoutCheckLoadSiteInfo(url:URL, cookieString:String?, previousContent:String?) -> StoryState {
        let siteInfoArray = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: url.absoluteString)
        print("\(url.absoluteString)\nsiteInfo.count: \(siteInfoArray.count) (最初のだけ表示します)")
        if let siteInfo = siteInfoArray.first {
            print("--\nurl:\(siteInfo.url?.pattern ?? "nil")\npageElement: \(siteInfo.pageElement)\nresourceUrl: \(siteInfo.resourceUrl ?? "nil")\nforceErrorMessageAndElement: \(siteInfo.forceErrorMessageAndElement ?? "nil")")
        }
        return CreateFirstStoryStateWithoutCheckLoadSiteInfoWith(siteInfoArray: siteInfoArray, url: url, cookieString: cookieString, previousContent: previousContent)
    }
    
    static func CreateFirstStoryState(url:URL, cookieString:String?, previousContent:String?, completion:((StoryState, _ errorString:String?)->Void)?) {
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady { error in
            completion?(CreateFirstStoryStateWithoutCheckLoadSiteInfo(url:url, cookieString: cookieString, previousContent: previousContent), error)
        }
    }
    
    func FetchFirst(url:URL, cookieString:String?, previousContent:String?, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, previousContent: previousContent, completion:{ (dummyState, errorString) in
            if let errorString = errorString, errorString.count > 0 {
                failedAction?(url, errorString)
            }else{
                self.FetchNext(currentState: dummyState, successAction: successAction, failedAction: failedAction)
            }
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
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, previousContent: previousContent, completion: { (state, errorString) in
            if let errorString = errorString, errorString.count > 0 {
                completion?(url, nil, errorString)
                return
            }
            self.FetchFirstContentRecurcive(currentState: state, successAction: { (state) in
                completion?(url, state, nil)
            }, failedAction: { (url, errorString) in
                completion?(url, nil, errorString)
            })
        })
    }
}
