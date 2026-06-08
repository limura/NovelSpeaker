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
    
    #if !os(watchOS)
    func transientDOMRetainedIfNeeded(document:Document?, nextButton: Element?, firstPageButton: Element?, forceClickButton: Element?, forceErrorMessage:String?) -> StoryState {
        let shouldRetainDOM = nextButton != nil || firstPageButton != nil || forceClickButton != nil
        return StoryState(url: url, cookieString: cookieString, content: content, nextUrl: nextUrl, firstPageLink: firstPageLink, title: title, author: author, subtitle: subtitle, tagArray: tagArray, siteInfoArray: siteInfoArray, isNeedHeadless: isNeedHeadless, isCanFetchNextImmediately: isCanFetchNextImmediately, waitSecondInHeadless: waitSecondInHeadless, previousContent: previousContent, document: shouldRetainDOM ? document : nil, nextButton: nextButton, firstPageButton: firstPageButton, forceClickButton: forceClickButton, forceErrorMessage: forceErrorMessage)
    }
    #endif
    
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

// MARK: - スクレイプ検査(checkTargets)用の型
// SiteInfo の checkTargets フィールド(新設)をパースして保持するための型群。
// 「今もそのサイトを正しくスクレイプできるか」を構造的(期待項目が非空か)に検査するために使う。
// 設計メモ: DESIGN_スクレイプ検査.md

// 検査で突合する期待項目。StoryState のどのフィールドを見るかに対応する。
enum ScrapeCheckToken : String, CaseIterable {
    case content          // StoryState.content が非空
    case title            // StoryState.title が非空
    case author           // StoryState.author が非空
    case subtitle         // StoryState.subtitle が非空
    case tag              // StoryState.tagArray が非空
    case firstPageLink    // StoryState.firstPageLink != nil
    case nextLink         // StoryState.nextUrl != nil (トークン名は nextLink だがフィールドは nextUrl)
    case nextButton       // StoryState.nextButton != nil (headless時のみ)
    case firstPageButton  // StoryState.firstPageButton != nil (headless時のみ)

    // 大文字小文字を無視して引く。未知トークンは nil(寛容にスキップする)。
    // エイリアス: SiteInfo シートの列名で書く人が多いので `pageElement`/`newPageElement`/`pageElementV2` を本文(content)として受ける。
    static func from(_ string:String) -> ScrapeCheckToken? {
        let key = string.lowercased()
        switch key {
        case "pageelement", "newpageelement", "pageelementv2", "body": return .content
        case "nexturl": return .nextLink
        default: break
        }
        return ScrapeCheckToken.allCases.first { $0.rawValue.lowercased() == key }
    }
}

// 1つの期待項目。`!token` 指定なら mustBeEmpty=true(「空であるべき」)。
struct ScrapeCheckExpectation : Equatable {
    let token: ScrapeCheckToken
    let mustBeEmpty: Bool
}

// 1つの検査対象(URL + 期待項目群 + 要認証フラグ)。
// checkTargets セル内の1エントリに相当する。
struct ScrapeCheckTarget : Equatable {
    let url: URL
    let expectations: [ScrapeCheckExpectation]
    let requireAuth: Bool // [auth] 前置タグ。未ログイン時に NG ではなく SKIP 扱いにするための印。
    var unknownTokens: [String] = [] // 語彙に無いトークン(typoの可能性)。黙って無視せず警告に使う。

    // 1行から `#` 行コメントを除去する。
    // URL の fragment(`...#frag`)を壊さないよう、コメント開始の `#` は『行頭 もしくは 空白の直後』に限る。
    //   "# まるごとコメント"           -> ""
    //   "URL => tok  # メモ"           -> "URL => tok  "
    //   "https://x/p#frag => content"  -> そのまま(# の直前が空白でないため非コメント)
    private static func stripInlineComment(_ line:String) -> String {
        var prevWasWhitespaceOrStart = true
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == "#" && prevWasWhitespaceOrStart {
                return String(line[..<idx])
            }
            prevWasWhitespaceOrStart = ch.isWhitespace
            idx = line.index(after: idx)
        }
        return line
    }

    // checkTargets フィールド文字列をパースして検査対象配列にする。
    // フォーマット(1セル内):
    //   - エントリ区切りは 改行 または `|`
    //   - `#` 以降は行コメント(行頭 or 空白直後の `#` から行末まで)。各行に説明メモを書ける。
    //   - 各エントリ: `[auth] URL => tok,tok,!tok`
    //     - 先頭の `[auth]`(または `[login]`) は任意。要認証マーク。
    //     - URL と トークン群の区切りは `=>`(前後スペースは任意、trimする)。
    //       `>` はURL中に生で出現しない(%3E になる)ため `=>` は衝突しない。
    //     - トークンは `,` 区切り。先頭 `!` は「空であるべき」。未知トークンはスキップ。
    //   - `=>` の無いエントリ(URLのみ)は期待項目なしの対象として保持する。
    static func parse(_ raw:String?) -> [ScrapeCheckTarget] {
        guard let raw = raw, raw.contains(where: { !$0.isWhitespace }) else { return [] }
        // 先に『行単位』で # コメントを除去してから、各行を `|` で分割する。
        // (# は物理行末までをコメントにする。`|` より先に行コメントを処理しないと、
        //  同一行で `#` 以降に `|` 区切りの別エントリが続く場合に誤って残ってしまうため。)
        var entries:[Substring] = []
        for lineSub in raw.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = stripInlineComment(String(lineSub))
            entries.append(contentsOf: line.split(separator: "|"))
        }
        var result:[ScrapeCheckTarget] = []
        for entryRaw in entries {
            var entry = entryRaw.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty { continue }
            // 先頭の [tag] を読む(複数可)。auth/login を要認証マークとして扱う。
            var requireAuth = false
            while entry.hasPrefix("["), let close = entry.firstIndex(of: "]") {
                let tag = entry[entry.index(after: entry.startIndex)..<close].trimmingCharacters(in: .whitespaces).lowercased()
                if tag == "auth" || tag == "login" { requireAuth = true }
                entry = String(entry[entry.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            // URL => tokens を最初の `=>` で分割。`=>` が無ければURLのみとみなす。
            let urlPart:String
            let tokenPart:String
            if let range = entry.range(of: "=>") {
                urlPart = String(entry[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                tokenPart = String(entry[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                urlPart = entry
                tokenPart = ""
            }
            guard let url = URL(string: urlPart) else { continue }
            var expectations:[ScrapeCheckExpectation] = []
            var unknownTokens:[String] = []
            for tokenRaw in tokenPart.split(separator: ",") {
                var token = tokenRaw.trimmingCharacters(in: .whitespaces)
                if token.isEmpty { continue }
                var mustBeEmpty = false
                if token.hasPrefix("!") {
                    mustBeEmpty = true
                    token = String(token.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                guard let parsed = ScrapeCheckToken.from(token) else {
                    // 黙ってスキップせず記録する(typo を後で警告するため)。
                    unknownTokens.append(token)
                    continue
                }
                expectations.append(ScrapeCheckExpectation(token: parsed, mustBeEmpty: mustBeEmpty))
            }
            result.append(ScrapeCheckTarget(url: url, expectations: expectations, requireAuth: requireAuth, unknownTokens: unknownTokens))
        }
        return result
    }

    // checkTargets のフォーマット検証。問題があれば人間可読な警告の配列を返す(空ならOK)。
    // parse は壊れたエントリ(URL不正・未知トークン)を黙って捨てるため、エディタの「テスト」時に気づけるよう明示する。
    // 分割ロジックは parse と完全に揃える(検査と実装の食い違いを防ぐ)。設計メモ: DESIGN_SiteInfoエディタ.md
    static func validateFormat(_ raw:String?) -> [String] {
        guard let raw = raw, raw.contains(where: { !$0.isWhitespace }) else { return [] }
        var warnings:[String] = []
        var entries:[Substring] = []
        for lineSub in raw.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let line = stripInlineComment(String(lineSub))
            entries.append(contentsOf: line.split(separator: "|"))
        }
        for entryRaw in entries {
            var entry = entryRaw.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty { continue }
            while entry.hasPrefix("["), let close = entry.firstIndex(of: "]") {
                entry = String(entry[entry.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            let urlPart:String
            let tokenPart:String
            if let range = entry.range(of: "=>") {
                urlPart = String(entry[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                tokenPart = String(entry[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                urlPart = entry
                tokenPart = ""
            }
            if urlPart.isEmpty {
                warnings.append(NSLocalizedString("SiteInfoEditor_Validate_CheckTargets_EmptyURL", comment: "checkTargets: URL が空のエントリがあります"))
                continue
            }
            if URL(string: urlPart) == nil {
                warnings.append(String(format: NSLocalizedString("SiteInfoEditor_Validate_CheckTargets_InvalidURL", comment: "checkTargets: URL として解釈できません(このエントリは無視されます): %@"), urlPart))
            }
            for tokenRaw in tokenPart.split(separator: ",") {
                var token = tokenRaw.trimmingCharacters(in: .whitespaces)
                if token.isEmpty { continue }
                if token.hasPrefix("!") { token = String(token.dropFirst()).trimmingCharacters(in: .whitespaces) }
                if token.isEmpty { continue }
                if ScrapeCheckToken.from(token) == nil {
                    warnings.append(String(format: NSLocalizedString("SiteInfoEditor_Validate_CheckTargets_UnknownToken", comment: "checkTargets: 未知のトークン(typo?): %@"), token))
                }
            }
        }
        return warnings
    }

    // 期待トークンが抽出後の StoryState 上で「非空/存在」しているかを判定する。
    private static func isPresent(_ token:ScrapeCheckToken, in state:StoryState) -> Bool {
        switch token {
        case .content: return (state.content?.isEmpty == false)
        case .title: return (state.title?.isEmpty == false)
        case .author: return (state.author?.isEmpty == false)
        case .subtitle: return (state.subtitle?.isEmpty == false)
        case .tag: return !state.tagArray.isEmpty
        case .firstPageLink: return state.firstPageLink != nil
        case .nextLink: return state.nextUrl != nil
        case .nextButton:
            #if !os(watchOS)
            return state.nextButton != nil
            #else
            return false
            #endif
        case .firstPageButton:
            #if !os(watchOS)
            return state.firstPageButton != nil
            #else
            return false
            #endif
        }
    }

    // 単ページモードで取得した StoryState を期待項目群と突合する。
    // 戻り値: 満たせなかった期待の説明配列。空なら全て満たした(=OK)。
    func evaluate(state:StoryState) -> [String] {
        var failures:[String] = []
        for expectation in expectations {
            let present = ScrapeCheckTarget.isPresent(expectation.token, in: state)
            if expectation.mustBeEmpty {
                if present { failures.append(String(format: NSLocalizedString("ScrapeInspector_Reason_MustBeEmptyButPresent", comment: "!%@ (空であるべきだが抽出された)"), expectation.token.rawValue)) }
            } else {
                if !present { failures.append(String(format: NSLocalizedString("ScrapeInspector_Reason_NotExtracted", comment: "%@ (抽出できなかった)"), expectation.token.rawValue)) }
            }
        }
        return failures
    }
}

struct StorySiteInfo : Identifiable {
    let id: String
    
    enum Language : Int {
        case Japanse = 0
        case English = 1
    }
    let name: String?
    let title: String?
    let pageElement: String
    let pageElementDict: [String: ([(lang:Language, title:String)], xpath:String)] // 辞書のkeyはIDとする。IDはSiteInfo側に書いてあるはず
    let subtitle: String?
    let firstPageLink: String?
    //let memo: String?
    let nextLink: String?
    let tag: String?
    let url: NSRegularExpression?
    //let exampleUrl: String?
    let author: String?
    let isNeedHeadless: Bool
    // headless 取得時、固定の waitSecondInHeadless を「ready要素が出たら即進む smart-wait」に切り替えてよいか。
    // 既定 false(=従来どおり必ず waitSecondInHeadless 待つ。レート制限回避目的の wait を壊さないための安全側)。
    // true のサイトだけ新アプリが描画待ちを短縮する。旧アプリはこの列を知らず常に固定待ち=後方互換。
    let allowSmartWait: Bool
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
    var novelImportEnableSettings: [String]
    // スクレイプ検査(checkTargets)用。SiteInfo に新設した checkTargets フィールドをパースして保持する。
    // 設計メモ: DESIGN_スクレイプ検査.md
    let checkTargets: [ScrapeCheckTarget]
    // SiteInfo エディタの読込(逆マッピング)用に、派生前の元文字列を保持する。
    // pageElement は pageElementV2 からの派生、checkTargets はパース済み配列しか持たないため、
    // エディタで「既存SiteInfoを読み込む→編集」する往復で情報が落ちないよう原文を残しておく。
    // 設計メモ: DESIGN_SiteInfoエディタ.md
    let originalPageElementV2: String
    let originalCheckTargets: String?

    static func pageElementV2ToPageElementDict(pageElementV2:String) -> [String: ([(lang:Language, title:String)], xpath:String)] {
        if !pageElementV2.contains(where: \.isNewline) {
            return ["1": ([(.Japanse,"本文"), (.English, "main content")], pageElementV2)]
        }
        var result:[String: ([(lang:Language, title:String)], xpath:String)] = [:]
        for line in pageElementV2.split(whereSeparator: \.isNewline) {
            // "id:日本語/英語=xpath" という感じで入っているものとして、分割してタブルにする
            let idAndNext = line.split(separator: ":", maxSplits: 1)
            guard idAndNext.count == 2 else { continue }
            let (id, next) = (String(idAndNext[0]), String(idAndNext[1]))
            let langTitlesAndXPath = next.split(separator: "=", maxSplits: 1)
            guard langTitlesAndXPath.count == 2 else { continue }
            let (langTitles, xpath) = (String(langTitlesAndXPath[0]), String(langTitlesAndXPath[1]))
            // langTitles は残念なことに languages の示す「順番」で入っていると仮定されている
            let languages = [StorySiteInfo.Language.Japanse, StorySiteInfo.Language.English]
            var langResult:[(lang:Language, title:String)] = []
            for (index, value) in langTitles.split(separator: "/").enumerated() {
                if index > languages.count - 1 {
                    break
                }
                langResult.append((languages[index], String(value)))
            }
            result[id] = (langResult, xpath)
        }
        return result
    }

    init(id: String, name: String?, pageElementV2:String, url:String?, title:String?, subtitle:String?, firstPageLink:String?, nextLink:String?, tag:String?, author:String?, isNeedHeadless:String?, injectStyle:String?, nextButton: String?, firstPageButton: String?, waitSecondInHeadless: Double?, forceClickButton:String?, resourceUrl:String?, overrideUserAgent:String?, forceErrorMessageAndElement:String?, scrollTo:String?, isNeedWhitespaceSplitForTag:String?, checkTargets:String? = nil, allowSmartWait:String? = nil, novelImportEnableSettings:[String] = []) {

        func pageElementV2ToPageElement(pageElementV2:String) -> String {
            // 複数要素(取り込み対象を選べる)形式は改行区切り。
            // 判定は dict 側(pageElementV2ToPageElementDict)と揃え、「文中に改行を含むか」で見る。
            // (行頭の改行有無では判定しない。単一行なら従来通りの pageElement そのもの)
            if !pageElementV2.contains(where: \.isNewline) {
                return pageElementV2
            }
            var pageElementArray:[String] = []
            for line in pageElementV2.split(whereSeparator: \.isNewline) {
                // "id:タイトル=Xpath" の最初の "=" より後ろが Xpath。
                // Xpath 自体に "=" を含む場合があるので maxSplits:1 で分割する。
                let lineSeparated = line.split(separator: "=", maxSplits: 1)
                if lineSeparated.count < 2 {
                    pageElementArray.append(String(line))
                    continue
                }
                pageElementArray.append(String(lineSeparated[1]))
            }
            return pageElementArray.joined(separator: "|")
        }
        self.id = id
        self.name = name
        self.pageElement = pageElementV2ToPageElement(pageElementV2: pageElementV2)
        self.pageElementDict = StorySiteInfo.pageElementV2ToPageElementDict(pageElementV2: pageElementV2)
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
        // 空文字列のセレクタは nil として扱う。
        // SiteInfo の CSV/TSV では未設定セルが "" になり、そのままだと
        //   ・querySelectorAll("") が Erik(内部Kanna)経由で libxml2 "XPath error : Invalid expression" を出す
        //   ・IsNextAlive() の `nextButton != nil` 判定が空""でも真になり「次ページあり」と誤判定する
        // ため、ここで空→nil に正規化する。
        func emptyToNil(_ s:String?) -> String? { (s?.isEmpty == false) ? s : nil }
        self.nextButton = emptyToNil(nextButton)
        self.firstPageButton = emptyToNil(firstPageButton)
        let falseValues:[String] = ["false", "False", "nil", "0"]
        if let isNeedHeadlessString = isNeedHeadless, isNeedHeadlessString.count > 0 && !falseValues.contains(isNeedHeadlessString) {
            self.isNeedHeadless = true
        }else{
            self.isNeedHeadless = false
        }
        if let allowSmartWaitString = allowSmartWait, allowSmartWaitString.count > 0 && !falseValues.contains(allowSmartWaitString) {
            self.allowSmartWait = true
        }else{
            self.allowSmartWait = false
        }
        self.waitSecondInHeadless = waitSecondInHeadless
        self.forceClickButton = emptyToNil(forceClickButton)
        self.resourceUrl = resourceUrl
        self.overrideUserAgent = overrideUserAgent
        self.forceErrorMessageAndElement = forceErrorMessageAndElement
        self.scrollTo = emptyToNil(scrollTo)
        if let isNeedWhitespaceSplitForTagString = isNeedWhitespaceSplitForTag, isNeedWhitespaceSplitForTagString.count > 0 && !falseValues.contains(isNeedWhitespaceSplitForTagString) {
            self.isNeedWhitespaceSplitForTag = true
        }else{
            self.isNeedWhitespaceSplitForTag = false
        }
        self.novelImportEnableSettings = novelImportEnableSettings
        self.checkTargets = ScrapeCheckTarget.parse(checkTargets)
        self.originalPageElementV2 = pageElementV2
        self.originalCheckTargets = checkTargets
    }

    // 生セル辞書(列名→値)から StorySiteInfo を生成する共有ファクトリ。
    // CSV デコーダ(DecodeCSVSiteInfoData)と SiteInfo エディタで「列→プロパティ」のマッピングを
    // 完全一致させるために切り出した(エディタの生セル編集とデコード経路の解釈差を無くす)。
    // - urlString は id の源情報(`<sheetId>:<urlString>`)に使う。RealmNovelImportSetting(サイト毎取込設定)の紐付けキー。
    // - importTargetsForSettingId を渡すと、その settingId→取込対象 解決を使い回す(CSVループで Realm を行毎に引かないため)。
    //   nil の場合は内部で1回 Realm を引く(エディタの単発生成用)。RealmSwift 型(Results 等)をこの API 表面に出さないため closure で受ける。
    // - `pageElementV2` 列が無い行は nil を返す(= デコード対象外。既存 DecodeCSVSiteInfoData の挙動を踏襲)。
    // 設計メモ: DESIGN_SiteInfoエディタ.md
    // useStoredId=true のとき、dict["id"] をそのまま id に使う(urlString の suffix を付けない)。
    //   ローカル最優先SiteInfo(LocalSiteInfoStore.entries)で使う。これにより「シート版を編集して保存した最優先SiteInfo」の id が
    //   元のシート版 id と一致し、取込対象設定(RealmNovelImportSetting・id 紐付け)や id 重複除去で同一サイトとして扱える。
    static func makeFromCellDict(_ dict:[String:String], urlString:String, importTargetsForSettingId:((String) -> [String])? = nil, useStoredId:Bool = false) -> StorySiteInfo? {
        guard let pageElementV2 = dict["pageElementV2"] else { return nil }
        let siteInfoId = dict["id"]
        let storySiteInfoId = useStoredId ? (siteInfoId ?? UUID.init().uuidString) : ((siteInfoId ?? UUID.init().uuidString) + ":" + urlString)
        let settingId = RealmNovelImportSetting.CreateUniqueID(scopeType: .site, siteInfoId: storySiteInfoId, novelID: nil)
        let importTargets:[String]
        if let resolver = importTargetsForSettingId {
            importTargets = resolver(settingId)
        } else {
            importTargets = RealmUtil.RealmBlock { realm in
                if let setting = RealmNovelImportSetting.GetAllObjectsWith(realm: realm)?.first(where: { $0.id == settingId }) {
                    return Array(setting.targets)
                }
                return []
            }
        }
        return StorySiteInfo(
            id: storySiteInfoId,
            name: dict["name"],
            pageElementV2: pageElementV2,
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
            isNeedWhitespaceSplitForTag: dict["isNeedWhitespaceSplitForTag"],
            checkTargets: dict["checkTargets"],
            allowSmartWait: dict["allowSmartWait"],
            novelImportEnableSettings: importTargets
        )
    }

    // makeFromCellDict の逆。StorySiteInfo を生セル辞書(列名→値)に戻す。
    // SiteInfo エディタが「公開SiteInfo等を読み込んで編集する」時の逆マッピングに使う(派生前の原文を使うので往復ロスが無い)。
    // ローカル保存(LocalSiteInfoStore)の直列化には使わない(あちらは生セル行 rows が正本)。
    // 設計メモ: DESIGN_SiteInfoエディタ.md
    func toCellDict() -> [String:String] {
        var d: [String:String] = [:]
        d["id"] = self.id
        d["name"] = self.name
        d["pageElementV2"] = self.originalPageElementV2
        d["url"] = self.url?.pattern
        d["title"] = self.title
        d["subtitle"] = self.subtitle
        d["firstPageLink"] = self.firstPageLink
        d["nextLink"] = self.nextLink
        d["tag"] = self.tag
        d["author"] = self.author
        d["isNeedHeadless"] = self.isNeedHeadless ? "true" : "false"
        d["allowSmartWait"] = self.allowSmartWait ? "true" : "false"
        d["injectStyle"] = self.injectStyle
        d["nextButton"] = self.nextButton
        d["firstPageButton"] = self.firstPageButton
        d["waitSecondInHeadless"] = self.waitSecondInHeadless.map { String($0) }
        d["forceClickButton"] = self.forceClickButton
        d["resourceUrl"] = self.resourceUrl
        d["overrideUserAgent"] = self.overrideUserAgent
        d["forceErrorMessageAndElement"] = self.forceErrorMessageAndElement
        d["scrollTo"] = self.scrollTo
        d["isNeedWhitespaceSplitForTag"] = self.isNeedWhitespaceSplitForTag ? "true" : "false"
        d["checkTargets"] = self.originalCheckTargets
        return d.compactMapValues { $0 }
    }

    // pageElementV2 のフォーマット検証(エディタの「テスト」用)。問題があれば人間可読な警告配列(空ならOK)。
    // 単一行は本文xpathそのものなので検証しない。複数行は『ID:タイトル/title=xpath』形式
    // (pageElementV2ToPageElementDict が最初の ':' で id、その後の最初の '=' で xpath を分ける)を要求する。
    static func validatePageElementV2Format(_ s: String?) -> [String] {
        guard let s = s, !s.isEmpty else { return [] }
        if !s.contains(where: \.isNewline) { return [] }
        var warnings:[String] = []
        for (i, lineSub) in s.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = lineSub.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lineNo = i + 1
            guard let colon = line.firstIndex(of: ":") else {
                warnings.append(String(format: NSLocalizedString("SiteInfoEditor_Validate_NPE_NoColon", comment: "pageElementV2 %d行目: ':' がありません(複数行では『ID:タイトル/title=xpath』形式が必要)"), lineNo))
                continue
            }
            if line[..<colon].trimmingCharacters(in: .whitespaces).isEmpty {
                warnings.append(String(format: NSLocalizedString("SiteInfoEditor_Validate_NPE_EmptyID", comment: "pageElementV2 %d行目: 行頭の ID(':' より前)が空です"), lineNo))
            }
            let afterColon = line[line.index(after: colon)...]
            guard let eq = afterColon.firstIndex(of: "=") else {
                warnings.append(String(format: NSLocalizedString("SiteInfoEditor_Validate_NPE_NoEqual", comment: "pageElementV2 %d行目: '=' がありません(『ID:タイトル/title=xpath』形式が必要)"), lineNo))
                continue
            }
            if afterColon[afterColon.index(after: eq)...].trimmingCharacters(in: .whitespaces).isEmpty {
                warnings.append(String(format: NSLocalizedString("SiteInfoEditor_Validate_NPE_EmptyXpath", comment: "pageElementV2 %d行目: '=' の右の xpath が空です"), lineNo))
            }
        }
        return warnings
    }

    // forceErrorMessageAndElement のフォーマット検証。『メッセージ:xpath』形式(最初の ':' で分割。forceErrorMessage/Element と同じ規則)。
    static func validateForceErrorMessageAndElementFormat(_ s: String?) -> [String] {
        guard let s = s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let components = s.components(separatedBy: ":")
        if components.count < 2 {
            return [NSLocalizedString("SiteInfoEditor_Validate_ForceError_NoColon", comment: "forceErrorMessageAndElement: ':' がありません(『メッセージ:xpath』形式が必要。最初の ':' でメッセージと xpath を分けます)")]
        }
        var warnings:[String] = []
        if components[0].trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append(NSLocalizedString("SiteInfoEditor_Validate_ForceError_EmptyMessage", comment: "forceErrorMessageAndElement: ':' より前のメッセージが空です"))
        }
        if components[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces).isEmpty {
            warnings.append(NSLocalizedString("SiteInfoEditor_Validate_ForceError_EmptyXpath", comment: "forceErrorMessageAndElement: ':' より後の xpath が空です"))
        }
        return warnings
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
    func createPageElementXpath(pageElementDict:[String: ([(lang:Language, title:String)], xpath:String)], novelImportEnableSettings:[String]?) -> String {
        //print("createPageElementXpath: \(novelImportEnableSettings), id: \(self.id), \(pageElementDict), pageElement: \(self.pageElement)")
        guard let novelImportEnableSettings = novelImportEnableSettings else { return self.pageElement }
        let result = pageElementDict.filter({ (key, value) -> Bool in
            novelImportEnableSettings.contains(key)
        }).map { (key: String, value: ([(lang: Language, title: String)], xpath: String)) in
            value.xpath
        }
        //print("result: \(result)")
        return result.joined(separator: "|")
    }
    func displayTitleForPageElement(key: String) -> String {
        guard let element = pageElementDict[key] else { return key }
        let currentLang: StorySiteInfo.Language = Locale.current.languageCode == "ja" ? .Japanse : .English
        return element.0.first(where: { $0.lang == currentLang })?.title ?? element.0.first?.title ?? key
    }
    func decodePageElement(xmlDocument:Kanna.XMLDocument, enabledTargets:[String]? = nil) -> String {
        let fallbackTargets = self.novelImportEnableSettings.isEmpty ? nil : self.novelImportEnableSettings
        let pageElement = createPageElementXpath(pageElementDict: self.pageElementDict, novelImportEnableSettings: enabledTargets ?? fallbackTargets)
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
        result += "\nid: \"" + id
        result += "\nurl: \"" + (url?.pattern ?? "nil")
        result += "\"\npageElement: \"" + pageElement
        result += "\"\npageElementV2: \"" + pageElementDict.map { "\($0.0): \($0.1)" }.joined(separator: ",")
        result += "\"\ntitle: \"" + (title ?? "nil")
        result += "\"\nsubtitle: \"" + (subtitle ?? "nil")
        result += "\"\nnextLink: \"" + (nextLink ?? "nil")
        result += "\"\nfirstPageLink: \"" + (firstPageLink ?? "nil")
        result += "\"\nauthor: \"" + (author ?? "nil")
        result += "\"\ntag: \"" + (tag ?? "nil")
        result += "\"\nisNeedHeadless: " + (isNeedHeadless ? "true" : "false")
        result += "\nallowSmartWait: " + (allowSmartWait ? "true" : "false")
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
    // WARN: AppInformationLogger で定義されている AnyCodable を利用しています
    var JSONdescription: [String:AnyCodable] {
        var result:[String:AnyCodable] = [:]
        result["pageElement"] = AnyCodable(pageElement)
        if let title = title {
            result["title"] = AnyCodable(title)
        }
        if let subtitle = subtitle {
            result["subtitle"] = AnyCodable(subtitle)
        }
        if let nextLink = nextLink {
            result["nextLink"] = AnyCodable(nextLink)
        }
        if let firstPageLink = firstPageLink {
            result["firstPageLink"] = AnyCodable(firstPageLink)
        }
        if let author = author {
            result["author"] = AnyCodable(author)
        }
        if let tag = tag {
            result["tag"] = AnyCodable(tag)
        }
        result["isNeedHeadless"] = AnyCodable(isNeedHeadless ? "true" : "false")
        result["allowSmartWait"] = AnyCodable(allowSmartWait ? "true" : "false")
        if let injectStyle = injectStyle {
            result["injectStyle"] = AnyCodable(injectStyle)
        }
        if let nextButton = nextButton {
            result["nextButton"] = AnyCodable(nextButton)
        }
        if let firstPageButton = firstPageButton {
            result["firstPageButton"] = AnyCodable(firstPageButton)
        }
        if let waitSecondInHeadless = waitSecondInHeadless {
            result["waitSecondInHeadless"] = AnyCodable(waitSecondInHeadless)
        }
        if let forceClickButton = forceClickButton {
            result["forceClickButton"] = AnyCodable(forceClickButton)
        }
        if let resourceUrl = resourceUrl {
            result["resourceUrl"] = AnyCodable(resourceUrl)
        }
        if let overrideUserAgent = overrideUserAgent {
            result["overrideUserAgent"] = AnyCodable(overrideUserAgent)
        }
        if let forceErrorMessageAndElement = forceErrorMessageAndElement {
            result["forceErrorMessageAndElement"] = AnyCodable(forceErrorMessageAndElement)
        }
        if let scrollTo = scrollTo {
            result["scrollTo"] = AnyCodable(scrollTo)
        }
        result["isNeedWhitespaceSplitForTag"] = AnyCodable(isNeedWhitespaceSplitForTag)
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
        case allowSmartWait
        case injectStyle
        case nextButton
        case firstPageButton
        case waitSecondInHeadless
        case forceClickButton
        case overrideUserAgent
        case forceErrorMessageAndElement
        case scrollTo
        case isNeedWhitespaceSplitForTag
        case checkTargets
    }

    init(from decoder: Decoder) throws {
        let toplevelValue = try decoder.container(keyedBy: CodingKeys.self)

        id = UUID.init().uuidString
        name = "-"
        resourceUrl = try? toplevelValue.decode(String.self, forKey: .resource_url)
        let values = try toplevelValue.nestedContainer(keyedBy: NestedKeys.self, forKey: .data)
        title = try? values.decode(String.self, forKey: NestedKeys.title)
        pageElement = try values.decode(String.self, forKey: NestedKeys.pageElement)
        pageElementDict = StorySiteInfo.pageElementV2ToPageElementDict(pageElementV2: pageElement)
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
        let allowSmartWaitString = try? values.decode(String.self, forKey: NestedKeys.allowSmartWait)
        if let allowSmartWaitString = allowSmartWaitString, allowSmartWaitString.count > 0 {
            switch allowSmartWaitString.lowercased() {
            case "false", "nil", "0":
                allowSmartWait = false
            default:
                allowSmartWait = true
            }
        }else{
            allowSmartWait = false
        }
        injectStyle = try? values.decode(String.self, forKey: NestedKeys.injectStyle)
        // 空文字列のセレクタは nil 扱い(memberwise init と揃える。理由はそちらのコメント参照)
        nextButton = (try? values.decode(String.self, forKey: NestedKeys.nextButton)).flatMap { $0.isEmpty ? nil : $0 }
        firstPageButton = (try? values.decode(String.self, forKey: NestedKeys.firstPageButton)).flatMap { $0.isEmpty ? nil : $0 }
        #if !os(watchOS)
        if let waitSecondInHeadlessString = try? values.decode(String.self, forKey: NestedKeys.waitSecondInHeadless), let value = Double(string: waitSecondInHeadlessString) {
            waitSecondInHeadless = value
        }else{
            waitSecondInHeadless = 0
        }
        overrideUserAgent = try? values.decode(String.self, forKey: NestedKeys.overrideUserAgent)
        forceClickButton = (try? values.decode(String.self, forKey: NestedKeys.forceClickButton)).flatMap { $0.isEmpty ? nil : $0 }
        scrollTo = (try? values.decode(String.self, forKey: NestedKeys.scrollTo)).flatMap { $0.isEmpty ? nil : $0 }
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
        self.novelImportEnableSettings = []
        let checkTargetsString = try? values.decode(String.self, forKey: NestedKeys.checkTargets)
        self.checkTargets = ScrapeCheckTarget.parse(checkTargetsString)
        // この経路は pageElementV2 の元文字列を持たない(pageElement のみ)ため、原文は pageElement で代用する。
        self.originalPageElementV2 = pageElement
        self.originalCheckTargets = checkTargetsString
    }
}

class StoryHtmlDecoder {
    var siteInfoArrayArray:[[StorySiteInfo]] = []
    // SiteInfo エディタで保存した「最優先SiteInfo」(ローカルCSV由来)。常に siteInfoArrayArray より優先する。
    // 空なら何も注入されない(= 自然に「最優先SiteInfo無し」相当)。設計メモ: DESIGN_SiteInfoエディタ.md
    var localPreferredSiteInfoArray:[StorySiteInfo] = []
    let fallbackSiteInfoArray:[StorySiteInfo]
    let lock = NSLock()
    var siteInfoLoadDoneHandlerArray:[(_ errorString:String?)->Void] = []
    var cacheFileExpireTimeinterval:Double = 60*60*24
    var nextExpireDate:Date = Date(timeIntervalSince1970: 0)
    var siteInfoNowLoading:Bool = false
    
    static let AutopagerizeSiteInfoJSONURL = "https://docs.google.com/spreadsheets/d/1t2wFx8psbc4EZxlacCas6lknO1S_PW6wsR9Qxq7HEnM/pub?gid=0&single=true&output=csv" // "http://wedata.net/databases/AutoPagerize/items.json"
    static let NovelSpeakerSiteInfoJSONURL = "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1/items.json"
    static let NovelSpeakerSiteInfoTSVURL = "https://docs.google.com/spreadsheets/d/1t2wFx8psbc4EZxlacCas6lknO1S_PW6wsR9Qxq7HEnM/pub?gid=0&single=true&output=csv"

    // シングルトンにしている。
    static let shared = StoryHtmlDecoder()
    private init(){
        fallbackSiteInfoArray = [
            //StorySiteInfo(pageElement: "//*[contains(@class,'autopagerize_page_element') or contains(@itemprop,'articleBody') or contains(concat(' ', normalize-space(@class), ' '), ' hentry ') or contains(concat(' ', normalize-space(@class), ' '), ' h-entry ')]", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: "(//link|//a)[contains(concat(' ', translate(normalize-space(@rel),'NEXT','next'), ' '), ' next ')]", tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: nil, resourceUrl: "fallbackSiteInfoArray(@itemprop,'articleBody')"),
            StorySiteInfo(id: UUID.init().uuidString, name: "default", pageElementV2: "//body", url: ".*", title: "//title", subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil, isNeedHeadless: nil, injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: nil, resourceUrl: "fallbackSiteInfoArray(//body)", overrideUserAgent: nil, forceErrorMessageAndElement: nil, scrollTo: nil, isNeedWhitespaceSplitForTag: nil)
        ]
    }
    
    func getIsSiteInfoReady(completion: @escaping (Bool)->Void) {
        NovelSpeakerUtility.GetNovelSpeakerRemoteConfig { config in
            // 設定されているSiteInfo URLのリスト分だけ正しくSiteInfoが読み込めていることを確認することにします
            let targetURLArray = self.getLoadTargetURLs(config: config)
            let result = targetURLArray.filter({$0 != nil}).count <= self.siteInfoArrayArray.filter({$0.count > 0}).count
            completion(result)
        }
    }
    
    var readySiteInfoCount: Int {
        get {
            return siteInfoArrayArray.reduce(0, {$0 + $1.count})
        }
    }
    func getReadySiteInfoDescription(completion: @escaping (String)->Void) {
        NovelSpeakerUtility.GetNovelSpeakerRemoteConfig { config in
            let siteInfoURLArray = self.getLoadTargetURLs(config: config)
            var resultArray:[String] = []
            for (index, siteInfoArray) in self.siteInfoArrayArray.enumerated() {
                var description = "\(index): count: \(siteInfoArray.count)"
                if siteInfoURLArray.count > index, let url = siteInfoURLArray[index] {
                    description += ", \(self.generateCacheFileName(url: url, index: index)) <- \(url.absoluteString)"
                }
                resultArray.append(description)
            }
            completion(resultArray.joined(separator: "\n"))
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
                id: UUID.init().uuidString,
                name: dict["name"],
                pageElementV2: pageElement,
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
                isNeedWhitespaceSplitForTag: dict["isNeedWhitespaceSplitForTag"],
                checkTargets: dict["checkTargets"],
                allowSmartWait: dict["allowSmartWait"]
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
    // CSV テキストを行×列に分解する。`""` で括って改行/カンマを含むフィールドに対応。
    // 元は DecodeCSVSiteInfoData 内のネスト関数だったものを、LocalSiteInfoStore(ローカル最優先SiteInfo)と
    // 共有するために static へ切り出した(挙動は不変)。設計メモ: DESIGN_SiteInfoエディタ.md
    static func ParseCSVRows(_ csvText: String) -> [[String]] {
        var result: [[String]] = []
        var currentField = ""
        var currentRow: [String] = []
        var inQuotes = false

        let characters = Array(csvText)
        var i = 0

        while i < characters.count {
            let char = characters[i]

            if inQuotes {
                if char == "\"" {
                    // エスケープされた引用符("")か、閉じ引用符かチェック
                    if i + 1 < characters.count && characters[i+1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n", "\r", "\r\n":
                    // 改行コード（\r\n または \n）を処理
                    if char == "\r" && i + 1 < characters.count && characters[i+1] == "\n" {
                        i += 1
                    }
                    currentRow.append(currentField)
                    result.append(currentRow)
                    currentRow = []
                    currentField = ""
                default:
                    currentField.append(char)
                }
            }
            i += 1
        }

        // 最後の行を追加
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            result.append(currentRow)
        }

        return result
    }

    static func DecodeCSVSiteInfoData(data:Data, urlString:String) -> [StorySiteInfo]? {
        // CSV には、"" で括って改行がくる場合を想定しないといけないです
        let rows = StoryHtmlDecoder.ParseCSVRows(String(decoding: data, as: UTF8.self))

        // 1行目は表題として使用
        guard let headers = rows.first else { return nil }
        
        let novelImportSettings = RealmUtil.RealmBlock { realm in
            return RealmNovelImportSetting.GetAllObjectsWith(realm: realm)
        }
        // settingId → 取込対象 を1回引いた結果から解決する(makeFromCellDict に行毎の Realm 再取得をさせない)。
        let importTargetsForSettingId: (String) -> [String] = { settingId in
            if let setting = novelImportSettings?.first(where: { $0.id == settingId }) {
                return Array(setting.targets)
            }
            return []
        }

        var result: [StorySiteInfo] = []
        // 2行目以降はデータとして処理
        for values in rows.dropFirst() {
            var dict = [String: String]()
            for (header, value) in zip(headers, values) {
                dict[header] = value
            }
            // 列→プロパティのマッピングは makeFromCellDict に集約(SiteInfo エディタと共通化)。
            // novelImportSettings は1回引いた結果を全行で使い回す(per-row の Realm 再取得を避ける)。
            guard let storySiteInfo = StorySiteInfo.makeFromCellDict(dict, urlString: urlString, importTargetsForSettingId: importTargetsForSettingId) else { continue }
            //print("add StorySiteInfo: \(storySiteInfo)")
            result.append(storySiteInfo)
        }
        if result.count <= 0 {
            //print("result.count <= 0: \(result.count), lines: \(lines)")
            return nil
        }
        return result
    }
    
    static func DecodeSiteInfoData(data:Data, urlString:String) -> [StorySiteInfo]? {
        // とりあえずJSONとしてデコードしようとしてみます。
        if let result = try? JSONDecoder().decode([StorySiteInfo].self, from: data), result.count > 0 {
            return result
        }
        // 末尾が csv なら CSV とみなします
        if urlString.lowercased().hasSuffix("csv") {
            return DecodeCSVSiteInfoData(data: data, urlString:urlString)
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
            guard DecodeSiteInfoData(data: content, urlString: urlString) != nil else {
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
    
    func getLoadTargetURLs(config: NovelSpeakerUtility.NovelSpeakerRemoteConfig? = nil) -> [URL?] {
        var loadTargetUrls:[URL?] = []
        let novelSpeakerSiteInfoTSVURL:String
        let autopagerizeSiteInfoJSONURL:String
        if let tsvURL = config?.novelSpeakerSiteInfoTSVURL {
            novelSpeakerSiteInfoTSVURL = tsvURL
        }else{
            novelSpeakerSiteInfoTSVURL = StoryHtmlDecoder.NovelSpeakerSiteInfoTSVURL
        }
        if let siteInfoURL = config?.autopagerizeSiteInfoURL {
            autopagerizeSiteInfoJSONURL = siteInfoURL
        }else{
            autopagerizeSiteInfoJSONURL = StoryHtmlDecoder.AutopagerizeSiteInfoJSONURL
        }
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
                    loadTargetUrls.append(URL(string: novelSpeakerSiteInfoTSVURL))
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
                    loadTargetUrls.append(URL(string: autopagerizeSiteInfoJSONURL))
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
        NovelSpeakerUtility.GetNovelSpeakerRemoteConfig { config in
            let targetURLArray = self.getLoadTargetURLs(config: config)
            for (index, url) in targetURLArray.enumerated() {
                if let url = url {
                    NiftyUtility.FileCachedHttpGet_RemoveCacheFile(cacheFileName: self.generateCacheFileName(url: url, index: index))
                }
            }
            URLCache.shared.removeAllCachedResponses()
            self.LoadSiteInfoIfNeeded()
        }
    }
    
    // ローカル最優先SiteInfo を先頭に置いた合成ビュー(= 優先順位順)。lock は呼び出し側が管理する。
    // 空の localPreferredSiteInfoArray は何も足さない。設計メモ: DESIGN_SiteInfoエディタ.md
    var effectiveSiteInfoArrayArray:[[StorySiteInfo]] {
        return (localPreferredSiteInfoArray.isEmpty ? [] : [localPreferredSiteInfoArray]) + siteInfoArrayArray
    }

    // ローカルCSV(LocalSiteInfoStore)から最優先SiteInfo を読み直して localPreferredSiteInfoArray を作り直す。
    // SiteInfo 読込完了時・エディタの保存/削除直後に呼ぶ。
    func ReloadLocalPreferredSiteInfo() {
        let entries = LocalSiteInfoStore.shared.entries()
        self.lock.lock()
        self.localPreferredSiteInfoArray = entries
        self.lock.unlock()
    }

    // 標準データ(公開SiteInfo等)の id に一致するキャッシュ済み SiteInfo を生セル辞書で返す。
    // SiteInfo エディタの「差分(標準データと違うカラム)」表示の基準として使う。ローカル最優先分は含めない。
    func standardSiteInfoCellsById(_ id: String) -> [String:String]? {
        guard !id.isEmpty else { return nil }
        self.lock.lock()
        defer { self.lock.unlock() }
        for array in siteInfoArrayArray {
            for siteInfo in array where siteInfo.id == id {
                return siteInfo.toCellDict()
            }
        }
        return nil
    }

    // 標準データ(公開SiteInfo等)のキャッシュファイル更新時刻のうち最新を「取得分」の目安として返す。
    // SiteInfo エディタのリストで「標準データ(YYYY年M月D日 取得分)」と表示するため。
    func standardDataFetchedDate() -> Date? {
        let urls = getLoadTargetURLs()
        var newest: Date? = nil
        for (index, url) in urls.enumerated() {
            guard let url = url else { continue }
            let name = generateCacheFileName(url: url, index: index)
            guard let path = NiftyUtility.GetCacheFilePath(fileName: name),
                  let attr = try? FileManager.default.attributesOfItem(atPath: path.path),
                  let date = attr[.modificationDate] as? Date else { continue }
            if newest == nil || date > newest! { newest = date }
        }
        return newest
    }

    func SearchSiteInfoArrayFrom(urlString: String) -> [StorySiteInfo] {
        var result:[StorySiteInfo] = []
        self.lock.lock()
        defer { self.lock.unlock() }
        for siteInfoArray in effectiveSiteInfoArrayArray {
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
    
    func resolveNovelImportEnableSettings(siteInfo: StorySiteInfo, novelID: String?) -> [String]? {
        guard siteInfo.pageElementDict.count > 1 else { return nil }
        return RealmUtil.RealmBlock { realm -> [String]? in
            let setting:RealmNovelImportSetting?
            if let novelID = novelID, novelID.count > 0, let novelSetting = RealmNovelImportSetting.GetNovelImportSetting(realm: realm, scopeType: .novel, siteInfoId: siteInfo.id, novelID: novelID), !novelSetting.isDeleted {
                setting = novelSetting
            }else if let siteSetting = RealmNovelImportSetting.GetNovelImportSetting(realm: realm, scopeType: .site, siteInfoId: siteInfo.id, novelID: nil), !siteSetting.isDeleted {
                setting = siteSetting
            }else{
                setting = nil
            }
            guard let setting = setting else { return nil }

            let currentIds = Set(siteInfo.pageElementDict.keys)
            let enabledIds = Set(setting.targets).intersection(currentIds)
            var seenIds = Set(setting.seenTargets)
            if seenIds.isEmpty && !enabledIds.isEmpty {
                RealmUtil.WriteWith(realm: realm) { realm in
                    setting.seenTargets.append(objectsIn: currentIds.sorted())
                    realm.add(setting, update: .modified)
                }
                seenIds = currentIds
            }
            let newIds = currentIds.subtracting(seenIds)
            var resolvedIds = enabledIds.union(newIds)

            // newElements / emptySelection のユーザ通知は SiteInfo 読み直し時に
            // checkNovelImportSettingChangesForLoadedSiteInfo() が1回だけ出します。
            // ここ(resolve)はページ取得ごとに呼ばれるホットパスなので、通知は出さず
            // 取り込み対象の解決(空ならば全項目へのフォールバック)だけを行います。
            if resolvedIds.isEmpty {
                resolvedIds = currentIds
            }
            return resolvedIds.sorted()
        }
    }

    private func addNovelImportSettingLog(message:String, dedupeSuffix:String, scopeType:RealmNovelImportSetting.ScopeType, settingId:String, settingNovelID:String, siteInfo:StorySiteInfo, novelID:String?, appendix:[String:AnyCodable]) {
        var appendix = appendix
        RealmUtil.RealmBlock { realm in
            if let novelID = novelID, novelID.count > 0, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID), novel.title.count > 0 {
                appendix[NSLocalizedString("StoryFetcher_NovelImportSettingLog_TargetNovel", comment: "対象の小説")] = AnyCodable(novel.title)
            }
            let action = AppInformationLogAction(
                title: NSLocalizedString("StoryFetcher_NovelImportSettingLog_OpenSettingAction", comment: "取り込み設定を確認する"),
                actionType: "openNovelImportSetting",
                payload: [
                    "scopeType": AnyCodable(scopeType == .novel ? "novel" : "site"),
                    "siteInfoId": AnyCodable(siteInfo.id),
                    "novelID": AnyCodable(novelID ?? settingNovelID)
                ]
            )
            AppInformationLogger.AddLogWithStruct(
                message: message,
                appendix: appendix,
                isForDebug: false,
                category: "novelImportSetting",
                dedupeKey: "novelImportSetting.\(dedupeSuffix):\(settingId)",
                actions: [action]
            )
        }
    }

    func LoadSiteInfoIfNeeded() {
        let now = Date()
        self.getIsSiteInfoReady() { (isSiteInfoReady) in
            self.lock.lock()
            if isSiteInfoReady == true && self.nextExpireDate > now && RealmGlobalState.GetIsForceSiteInfoReloadIsEnabled() == false {
                let handlerQueued = self.siteInfoLoadDoneHandlerArray
                self.siteInfoLoadDoneHandlerArray.removeAll()
                self.lock.unlock()
                for handler in handlerQueued {
                    handler(nil)
                }
                return
            }
            if self.siteInfoNowLoading {
                self.lock.unlock()
                return
            }
            self.nextExpireDate = now.addingTimeInterval(self.cacheFileExpireTimeinterval)
            self.siteInfoNowLoading = true
            self.lock.unlock()
            DispatchQueue.global(qos: .background).async {
                self.LoadSiteInfo()
            }
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

        func siteInfoFetchAndUpdate(index:Int, targetURLArray:[URL?], cacheFileExpireTimeinterval:Double) {
                if index >= targetURLArray.count {
                    // INFO: LoadSiteInfo() の終了処理をここでやっています
                    // ローカル最優先SiteInfo(エディタ保存分)もこのタイミングで読み直して反映する。
                    ReloadLocalPreferredSiteInfo()
                    checkNovelImportSettingChangesForLoadedSiteInfo()
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
                        if let httpSiteInfoArray = StoryHtmlDecoder.DecodeSiteInfoData(data: data, urlString: targetURL.absoluteString) {
                            siteInfoArray = httpSiteInfoArray
                            isValidData = true
                        } else {
                            guard let cachedData = cachedFileData, let cachedSiteInfoArray = StoryHtmlDecoder.DecodeSiteInfoData(data: cachedData, urlString: targetURL.absoluteString) else {
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
                    guard let cachedFileData = cachedFileData, let cachedSiteInfoArray = StoryHtmlDecoder.DecodeSiteInfoData(data: cachedFileData, urlString: targetURL.absoluteString) else {
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
        NovelSpeakerUtility.GetNovelSpeakerRemoteConfig() { remoteConfig in
            let loadTargetUrls = self.getLoadTargetURLs(config: remoteConfig)
            siteInfoFetchAndUpdate(index: 0, targetURLArray: loadTargetUrls, cacheFileExpireTimeinterval: cacheFileExpireTimeinterval)
        }
    }

    func checkNovelImportSettingChangesForLoadedSiteInfo() {
        let siteInfoArray = effectiveSiteInfoArrayArray.flatMap { $0 }
        let siteInfoById = Dictionary(siteInfoArray.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard siteInfoById.count > 0 else { return }
        RealmUtil.RealmBlock { realm in
            guard let settings = RealmNovelImportSetting.GetAllObjectsWith(realm: realm) else { return }
            for setting in settings where !setting.isDeleted {
                guard let siteInfo = siteInfoById[setting.siteInfoId], siteInfo.pageElementDict.count > 1 else { continue }
                let currentIds = Set(siteInfo.pageElementDict.keys)
                let enabledIds = Set(setting.targets).intersection(currentIds)
                var seenIds = Set(setting.seenTargets)
                if seenIds.isEmpty && !enabledIds.isEmpty {
                    RealmUtil.WriteWith(realm: realm) { _ in
                        setting.seenTargets.append(objectsIn: currentIds.sorted())
                    }
                    seenIds = currentIds
                }
                let newIds = currentIds.subtracting(seenIds)
                let resolvedIds = enabledIds.union(newIds)
                if !newIds.isEmpty {
                    addNovelImportSettingLog(
                        message: NSLocalizedString("StoryFetcher_NovelImportSettingNewElements_Message", comment: "SiteInfo に新しい取り込み項目が追加されていたため、確認されるまではその項目も取り込み対象として扱います。"),
                        dedupeSuffix: "newElements",
                        scopeType: setting.scopeType,
                        settingId: setting.id,
                        settingNovelID: setting.novelID,
                        siteInfo: siteInfo,
                        novelID: setting.scopeType == .novel ? setting.novelID : nil,
                        appendix: [
                            NSLocalizedString("StoryFetcher_NovelImportSettingLog_TargetSite", comment: "対象のWebサイト"): AnyCodable(siteInfo.name ?? siteInfo.id),
                            NSLocalizedString("StoryFetcher_NovelImportSettingLog_AddedElements", comment: "追加された項目"): AnyCodable(newIds.sorted().map { siteInfo.displayTitleForPageElement(key: $0) })
                        ]
                    )
                    RealmUtil.WriteWith(realm: realm) { _ in
                        for key in newIds.sorted() {
                            if !setting.targets.contains(key) {
                                setting.targets.append(key)
                            }
                        }
                        setting.seenTargets.removeAll()
                        setting.seenTargets.append(objectsIn: currentIds.sorted())
                    }
                }else if resolvedIds.isEmpty {
                    addNovelImportSettingLog(
                        message: NSLocalizedString("StoryFetcher_NovelImportSettingEmptySelection_Message", comment: "取り込み設定の対象項目が SiteInfo 更新により見つからなくなったため、このページでは全ての取り込み項目を使用しました。"),
                        dedupeSuffix: "emptySelection",
                        scopeType: setting.scopeType,
                        settingId: setting.id,
                        settingNovelID: setting.novelID,
                        siteInfo: siteInfo,
                        novelID: setting.scopeType == .novel ? setting.novelID : nil,
                        appendix: [
                            NSLocalizedString("StoryFetcher_NovelImportSettingLog_TargetSite", comment: "対象のWebサイト"): AnyCodable(siteInfo.name ?? siteInfo.id),
                            NSLocalizedString("StoryFetcher_NovelImportSettingLog_CurrentElements", comment: "現在利用できる項目"): AnyCodable(currentIds.sorted().map { siteInfo.displayTitleForPageElement(key: $0) })
                        ]
                    )
                }
            }
        }
    }
    
    // 特定 ID の StorySiteInfo.novelImportEnableSettings を書き換えます
    // (最優先SiteInfo(ローカル保存分)も対象にする。これを忘れるとローカル編集サイトの取込対象選択が即時反映されない)
    func updateNovelImportEnableSettings(id: String, targetKeys: [String]) {
        for i in self.siteInfoArrayArray.indices {
            for j in self.siteInfoArrayArray[i].indices {
                if self.siteInfoArrayArray[i][j].id == id {
                    self.siteInfoArrayArray[i][j].novelImportEnableSettings = targetKeys
                    break
                }
            }
        }
        for i in self.localPreferredSiteInfoArray.indices {
            if self.localPreferredSiteInfoArray[i].id == id {
                self.localPreferredSiteInfoArray[i].novelImportEnableSettings = targetKeys
            }
        }
    }
}

class StoryFetcher {
    var novelIDForImportSetting:String? = nil

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
        //print("DecodeDocument: html:\n-----\n\(html ?? "nil")\n-----")
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
        //    print("\(n): \(siteInfo.id), \(siteInfo.pageElementDict.count), \(siteInfo.novelImportEnableSettings), \(siteInfo.url?.pattern ?? "nil"), \(siteInfo.url?.pattern.count ?? -1)")
        //}
        //print("-----")
        
        var tryedResourceUrlArray:[String] = []
        for siteInfo in currentState.siteInfoArray {
            if let resourceUrl = siteInfo.resourceUrl {
                tryedResourceUrlArray.append(resourceUrl)
            }
            let enabledTargets = StoryHtmlDecoder.shared.resolveNovelImportEnableSettings(siteInfo: siteInfo, novelID: novelIDForImportSetting)
            let pageElement = siteInfo.decodePageElement(xmlDocument: htmlDocument, enabledTargets: enabledTargets).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
                //print("this siteInfo not match. continue. siteInfo: \(siteInfo.description)\n  pageElement.count: \(pageElement.count)\n  nextUrl: \(nextUrl?.absoluteString ?? "nil") \n  firstPageLink: \(firstPageLink?.absoluteString ?? "nil")\n  firstPageButton: \(firstPageButton == nil ? "nil" : "not nil")\n  forceClickButton: \(forceClickButton == nil ? "nil" : "not nil")\n  forceErrorElementIsAlive_ErrorMessage: \(forceErrorElementIsAlive_ErrorMessage ?? "nil")")
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
            #if false // 詳細なログが必要な場合は true にします
            AppInformationLogger.AddLogWithStruct(
                message: "取り込み動作ログ",
                appendix: [
                    "how": AnyCodable("1ページ読み込み中"),
                    "URL": AnyCodable(currentState.url.absoluteString),
                    "適用されたSiteInfo": AnyCodable(siteInfo.JSONdescription),
                    "抽出された本文": AnyCodable(pageElement),
                    "nextUrl": AnyCodable(nextUrl?.absoluteString ?? "nil"),
                    "firstPageLink": AnyCodable(firstPageLink?.absoluteString ?? "nil"),
                    "nextButton": AnyCodable(nextButton?.text ?? "nil"),
                    "firstPageButton": AnyCodable(firstPageButton?.text ?? "nil"),
                    "forceClickButton": AnyCodable(forceClickButton?.text ?? "nil"),
                ],
                isForDebug: true
            )
            #endif
            //print("match success: pageElement.count: \(pageElement.count), nextUrl: \(nextUrl?.absoluteString ?? "nil"), firstPageLink: \(firstPageLink?.absoluteString ?? "nil"), nextButton: \(nextButton != nil ? "has" : "nil"), firstPageButton: \(firstPageButton != nil ? "has" : "nil"), (forceClickButton: \(forceClickButton != nil ? "has" : "nil"), && siteInfo.isNeedHeadless: \(siteInfo.isNeedHeadless), && forceErrorElementIsAlive_ErrorMessage: \(forceErrorElementIsAlive_ErrorMessage ?? "nil")), siteInfo.description: \(siteInfo.description), siteInfo.pageElement: \"\(siteInfo.pageElement)\", siteInfo.nextLink: \(siteInfo.nextLink ?? "-")")
            //print("match success: pageElement.count: \(pageElement.count), nextUrl: \(nextUrl?.absoluteString ?? "nil"), firstPageLink: \(firstPageLink?.absoluteString ?? "nil"), hitSiteInfo: \(siteInfo)")
            #if !os(watchOS)
            let nextState = StoryState(
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
            ).transientDOMRetainedIfNeeded(document: currentState.document, nextButton: nextButton, firstPageButton: firstPageButton, forceClickButton: forceClickButton, forceErrorMessage: forceErrorElementIsAlive_ErrorMessage)
            successAction?(nextState)
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
    // inspectionTargetURL: スクレイプ検査(checkTargets)用の単ページモード。
    //   非nilのとき「初回GET(nextUrl == inspectionTargetURL の経路)と forceClickButton(広告/ダイアログ消し)・scrollTo 等は
    //   通常通り実行するが、firstPageLink / 2回目以降の nextUrl / nextButton / firstPageButton への『ページ遷移』はしない」。
    //   遷移する代わりに、その時点で抽出済みの StoryState を successAction で返し、呼び出し側(検査)が期待項目と突合する。
    //   通常の取り込みは nil のままなので影響しない。設計メモ: DESIGN_スクレイプ検査.md
    func FetchNext(currentState:StoryState, fetchTimeToLive:Int = 5, inspectionTargetURL:URL? = nil, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?){
        // 入力に有効な content があるならそこで探索は終わり。
        // ただし forceErrorMessage(gate/壁ページ検出)が立っている場合は本文が取れていても失敗にする。
        // (pixiv 未ログイン等、壁ページが og:description 由来の teaser 本文を持つケースでは
        //  content と forceErrorMessage が同時に立つ。ここで content を優先すると壁を素通りして
        //  下の forceErrorMessage→failedAction(:1546付近) に到達しないため、gate検出が無効化されてしまう。)
        if let content = currentState.content, content.count > 0, currentState.forceErrorMessage == nil {
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
        // (検査モードでも実行する。全画面広告/ダイアログを消さないと本文が出ないサイトがあるため。)
        if let element = currentState.forceClickButton {
            print("force click: \(element)")
            buttonClick(buttonElement: element, currentState: currentState) { (state, err) in
                if let state = state {
                    // TTL を減らして再取得したつもりになって評価しなおします。
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, inspectionTargetURL: inspectionTargetURL, successAction: successAction, failedAction: failedAction)
                    return
                }
                failedAction?(currentState.url, err?.localizedDescription ?? "unknown error: ForceClickButton")
            }
            return
        }

        // 次ページへのボタンがあればそれを辿る
        if let element = currentState.nextButton {
            // 検査モードではボタン送り(ページ遷移)はせず、ボタンが存在する状態のまま検査側へ返す。
            if inspectionTargetURL != nil {
                successAction?(currentState)
                return
            }
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
            // 検査モードではボタン送り(ページ遷移)はせず、ボタンが存在する状態のまま検査側へ返す。
            if inspectionTargetURL != nil {
                successAction?(currentState)
                return
            }
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
                        self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, inspectionTargetURL: inspectionTargetURL, successAction: successAction, failedAction: failedAction)
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
                    self.FetchNext(currentState: state, fetchTimeToLive: fetchTimeToLive - 1, inspectionTargetURL: inspectionTargetURL, successAction: successAction, failedAction: failedAction)
                }, failedAction: failedAction)
            }) { (error) in
                failedAction?(currentState.url, error?.localizedDescription ?? "httpRequest return unknown error(nil)")
            }
        }

        if let firstPageLink = currentState.firstPageLink {
            // 検査モードでは firstPageLink への遷移はしない(検査対象ページから離れてしまうため)。
            // firstPageLink が抽出できている状態のまま検査側へ返す。
            // (初回GETは必ず nextUrl 経路なので、firstPageLink は常にデコード後=遷移対象であり、ここで止めて良い。)
            if inspectionTargetURL != nil {
                successAction?(currentState)
                return
            }
            // firstPageLink があるならそれを辿る
            fetchUrlWithRobotsCheck(url: firstPageLink, currentState: currentState)
            return
        }
        if let nextUrl = currentState.nextUrl {
            // 検査モードでは「初回GET(nextUrl == 検査対象URL)」だけ実行し、
            // それ以外の nextUrl(=デコード後に得た次ページリンク)への遷移はしない。
            if let inspectionTargetURL = inspectionTargetURL, nextUrl != inspectionTargetURL {
                successAction?(currentState)
                return
            }
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
        /*
        print("\(url.absoluteString)\nsiteInfo.count: \(siteInfoArray.count) (最初のだけ表示します)")
        if let siteInfo = siteInfoArray.first {
            print("--\n\(siteInfo.description)")
        }
        */
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
    
    // スクレイプ検査(checkTargets)用：指定URLを「単ページモード」で読み込み、抽出結果の StoryState を返す。
    // 初回GET・forceClickButton(広告/ダイアログ消し)・scrollTo(遅延ロード誘発)・waitSecond 等は通常の取り込みと同じく実行するが、
    // firstPageLink / nextLink(次ページ) / nextButton / firstPageButton への『ページ遷移』はせず、
    // 検査対象ページから抽出できた内容のまま返す(FetchNext の inspectionTargetURL モード)。
    // successAction で受けた state を ScrapeCheckTarget.evaluate(state:) に渡して期待項目と突合する。
    // 設計メモ: DESIGN_スクレイプ検査.md
    func InspectFetchSinglePage(url:URL, cookieString:String?, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        StoryFetcher.CreateFirstStoryState(url: url, cookieString: cookieString, previousContent: nil, completion: { (state, errorString) in
            if let errorString = errorString, errorString.count > 0 {
                failedAction?(url, errorString)
                return
            }
            self.FetchNext(currentState: state, inspectionTargetURL: url, successAction: successAction, failedAction: failedAction)
        })
    }

    // InspectFetchSinglePage のキャッシュ非依存版。
    // 通常経路(InspectFetchSinglePage)は CreateFirstStoryState → SearchSiteInfoArrayFrom でキャッシュから SiteInfo を探すが、
    // こちらは外から渡した [StorySiteInfo] で直接 state を作って単ページモード取得する(キャッシュにも本番にも触れない)。
    // SiteInfo エディタの「この値で今すぐテスト」用。SiteInfo を自前で渡すため WaitLoadSiteInfoReady も不要。
    // 設計メモ: DESIGN_SiteInfoエディタ.md
    func InspectFetchSinglePageWith(siteInfoArray:[StorySiteInfo], url:URL, cookieString:String?, successAction:((StoryState)->Void)?, failedAction:((URL, String)->Void)?) {
        let state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfoWith(siteInfoArray: siteInfoArray, url: url, cookieString: cookieString, previousContent: nil)
        self.FetchNext(currentState: state, inspectionTargetURL: url, successAction: successAction, failedAction: failedAction)
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

#if !os(watchOS)
// MARK: - スクレイプ検査(checkTargets)ランナー
// SiteInfo に登録された checkTargets を全件、1日1回程度の頻度で検査して
// 「ちゃんとスクレイプできているか(期待フィールドが取れているか)」を OK/NG/SKIP/ROBOTS/ERROR で集計する。
// 共有 headless httpClient(WKWebView 単一インスタンス)を使うため『逐次実行』。設計メモ: DESIGN_スクレイプ検査.md(着手順3)。
class ScrapeInspector {
    enum Status : String {
        case ok = "OK"
        case ng = "NG"
        case warn = "WARN"            // [auth]で取れないが未ログインの確証(gate/別ホスト)が無い=故障の可能性。要確認。
        case skip = "SKIP"
        case robotsBlocked = "ROBOTS"
        case error = "ERROR"
    }
    struct Result {
        let siteName: String
        let url: URL
        let requireAuth: Bool
        let status: Status
        let reasons: [String]
        var description: String {
            let head = "[\(status.rawValue)]\(requireAuth ? "[auth]" : "")  \(siteName)  \(url.absoluteString)"
            if reasons.isEmpty { return head }
            return head + "\n    - " + reasons.joined(separator: "\n    - ")
        }
    }

    // 検査対象(SiteInfo表示名 + ターゲット)の組。
    private struct WorkItem {
        let siteName: String
        let target: ScrapeCheckTarget
    }

    private let fetcher = StoryFetcher()
    private var results: [Result] = []
    private let perTargetTimeout: TimeInterval
    private let intervalBetweenTargets: TimeInterval

    // perTargetTimeout: 1ターゲットの応答待ち上限(保険)。intervalBetweenTargets: 連続アクセスの間隔。
    init(perTargetTimeout: TimeInterval = 90, intervalBetweenTargets: TimeInterval = 1.0) {
        self.perTargetTimeout = perTargetTimeout
        self.intervalBetweenTargets = intervalBetweenTargets
    }

    // robots ブロックのローカライズ文言(failedAction の message と一致させて robots を判別する)。
    static var robotsBlockMessage: String {
        return NSLocalizedString("StoryFetcher_FetchError_RobotsText", comment: "Webサイト様側で機械的なアクセスを制限されているサイトであったため、ことせかい による取得ができません。")
    }

    // 判定理由のローカライズ文言。本体(judge)とテストで同じ文字列を共有するため、ここに集約する。
    static var reasonHostRedirect: String {
        return NSLocalizedString("ScrapeInspector_Reason_HostRedirect", comment: "別ホストへリダイレクト(未ログイン/年齢確認の可能性)")
    }
    static var reasonAuthNoEvidence: String {
        return NSLocalizedString("ScrapeInspector_Reason_AuthNoEvidence", comment: "要確認: 未ログインの確証(gate/別ホスト)が無いのに取得できず。ログイン状態か取り込み設定の破損を確認")
    }
    static func reasonUnknownTokens(_ tokens: [String]) -> String {
        return String(format: NSLocalizedString("ScrapeInspector_Reason_UnknownTokens", comment: "設定の無効トークン(typo?): %@"), tokens.joined(separator: ", "))
    }
    static func reasonTimeout(seconds: Int) -> String {
        return String(format: NSLocalizedString("ScrapeInspector_Reason_Timeout", comment: "タイムアウト(%d秒以内に応答なし)"), seconds)
    }

    // 実遷移後URL(headless の現在URL)のホストが要求と変わったか。
    // 注意: state.url はリダイレクト後も要求URLのまま(ステイル)なので、ホスト比較には httpClient.GetCurrentURL() を使う。
    // novel18 等は未ログイン時 別ホスト(nl.syosetu.com の年齢確認)へ飛ぶ。これを「未ログイン確定」の信号にする。
    // www↔m 等の同サイト別サブドメインも host文字列は変わるが、判定は [auth] かつ『取れなかった時』に限るので実害は小さい
    // (取れていれば OK のまま)。なお登録ドメイン(eTLD+1)比較だと novel18.syosetu.com と nl.syosetu.com が同一になり
    // novel18 を検出できないため、ホスト完全一致で比較する。
    static func isHostChanged(requested: URL, final: URL?) -> Bool {
        guard let finalHost = final?.host, let reqHost = requested.host else { return false }
        return finalHost != reqHost
    }

    // 検査1件の判定(純粋関数・テスト可能)。
    //   failMessage: failedAction のメッセージ(nil なら success)。
    //   evaluateFailures: success 時の ScrapeCheckTarget.evaluate(state:) の結果(空なら全て満たした)。
    //   hostChanged: 実遷移後URLのホストが要求と変わったか(別ホストの壁へ飛ばされた=未ログイン確定の信号)。
    // 思想: 『誤NGより検知漏れ』。未ログインの"確証"(別ホスト/robots)があるものは静かに SKIP、
    //       gate(forceError) も別ホストも無いのに [auth] で取れないものは『故障の可能性』として WARN で目立たせる。
    static func judge(requireAuth: Bool, failMessage: String?, evaluateFailures: [String], hostChanged: Bool = false, unknownTokens: [String] = []) -> (status: Status, reasons: [String]) {
        let base = judgeCore(requireAuth: requireAuth, failMessage: failMessage, evaluateFailures: evaluateFailures, hostChanged: hostChanged)
        // checkTargets に語彙外トークン(typoの可能性)があれば、黙って無視せず警告する。
        // 期待として効いていない＝検査が意図より弱い状態なので、OK でも WARN に格上げして気づけるようにする。
        guard !unknownTokens.isEmpty else { return base }
        let note = reasonUnknownTokens(unknownTokens)
        let status: Status = (base.status == .ok) ? .warn : base.status
        return (status, [note] + base.reasons)
    }

    private static func judgeCore(requireAuth: Bool, failMessage: String?, evaluateFailures: [String], hostChanged: Bool) -> (status: Status, reasons: [String]) {
        if let message = failMessage {
            if message == robotsBlockMessage { return (.robotsBlocked, [message]) }
            // 別ホストへ飛ばされた [auth] は未ログイン確定として SKIP。
            if requireAuth && hostChanged { return (.skip, [reasonHostRedirect, message]) }
            // gate(forceError) 等。要認証マークなら未ログイン/年齢未確認の可能性として SKIP。
            if requireAuth { return (.skip, [message]) }
            return (.ng, [message])
        }
        // 別ホストへ飛ばされた = 要求ページを取得できていない。[auth] なら未ログイン確定 SKIP(content等が取れても信用しない)。
        if requireAuth && hostChanged { return (.skip, [reasonHostRedirect]) }
        if evaluateFailures.isEmpty { return (.ok, []) }
        // gate も別ホストも無いのに [auth] で取れない = 未ログインの確証が無い = スクレイプ故障の可能性。要確認(WARN)。
        if requireAuth { return (.warn, [reasonAuthNoEvidence] + evaluateFailures) }
        return (.ng, evaluateFailures)
    }

    // SiteInfo をロードしてから全 checkTargets を逐次検査する。
    // progress: (完了数, 総数, 直近の結果)。completion: 全結果。
    func InspectAll(progress: ((Int, Int, Result) -> Void)? = nil, completion: @escaping ([Result]) -> Void) {
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady { [weak self] _ in
            guard let self = self else { return }
            // SiteInfo は複数ソースURLから二重ロードされる(siteInfoArrayArray が同内容を複数持つ)ため、
            // 同一(サイト名+URL+期待トークン)の重複を除いて、各検査対象を1回だけ実行する。
            var items: [WorkItem] = []
            var seen = Set<String>()
            for siteInfoArray in StoryHtmlDecoder.shared.effectiveSiteInfoArrayArray {
                for siteInfo in siteInfoArray {
                    if siteInfo.checkTargets.isEmpty { continue }
                    let siteName = siteInfo.name ?? siteInfo.resourceUrl ?? "(no name)"
                    for target in siteInfo.checkTargets {
                        let tokenSig = target.expectations.map { "\($0.mustBeEmpty ? "!" : "")\($0.token.rawValue)" }.joined(separator: ",")
                        let key = "\(siteName)|\(target.requireAuth ? "A" : "-")|\(target.url.absoluteString)|\(tokenSig)"
                        if seen.contains(key) { continue }
                        seen.insert(key)
                        items.append(WorkItem(siteName: siteName, target: target))
                    }
                }
            }
            DispatchQueue.main.async {
                self.results = []
                // 通常の全件検査はキャッシュ由来 SiteInfo で取得する(InspectFetchSinglePage)。
                self.runSequential(items: items, index: 0, fetch: { target, success, failed in
                    self.fetcher.InspectFetchSinglePage(url: target.url, cookieString: "", successAction: success, failedAction: failed)
                }, progress: progress, completion: completion)
            }
        }
    }

    // SiteInfo エディタ用：与えた1件の StorySiteInfo の checkTargets を、キャッシュではなくその1件で逐次検査する。
    // 各ターゲットの取得を InspectFetchSinglePageWith([siteInfo]) に差し替えるだけで、判定(judge)以降は全件検査と共通。
    // checkTargets が空なら items も空になり、即 completion([]) を返す(呼び出し側で「未設定」注記を出す)。
    // 設計メモ: DESIGN_SiteInfoエディタ.md
    func InspectSingleSiteInfo(siteInfo: StorySiteInfo, progress: ((Int, Int, Result) -> Void)? = nil, completion: @escaping ([Result]) -> Void) {
        let siteName = siteInfo.name ?? siteInfo.resourceUrl ?? "(no name)"
        let items = siteInfo.checkTargets.map { WorkItem(siteName: siteName, target: $0) }
        DispatchQueue.main.async {
            self.results = []
            self.runSequential(items: items, index: 0, fetch: { target, success, failed in
                self.fetcher.InspectFetchSinglePageWith(siteInfoArray: [siteInfo], url: target.url, cookieString: "", successAction: success, failedAction: failed)
            }, progress: progress, completion: completion)
        }
    }

    // items を逐次検査する。各ターゲットの「取得」だけ fetch クロージャに委譲し(キャッシュ版/単一SiteInfo版で差し替える)、
    // 取得後の judge・集計・インターバル・ウォッチドッグは共通化する。
    private func runSequential(items: [WorkItem], index: Int, fetch: @escaping (_ target: ScrapeCheckTarget, _ success: @escaping (StoryState) -> Void, _ failed: @escaping (URL, String) -> Void) -> Void, progress: ((Int, Int, Result) -> Void)?, completion: @escaping ([Result]) -> Void) {
        if index >= items.count {
            completion(results)
            return
        }
        let item = items[index]
        let target = item.target
        var finished = false
        func finish(_ status: Status, _ reasons: [String]) {
            DispatchQueue.main.async {
                if finished { return }
                finished = true
                let result = Result(siteName: item.siteName, url: target.url, requireAuth: target.requireAuth, status: status, reasons: reasons)
                self.results.append(result)
                progress?(self.results.count, items.count, result)
                DispatchQueue.main.asyncAfter(deadline: .now() + self.intervalBetweenTargets) {
                    self.runSequential(items: items, index: index + 1, fetch: fetch, progress: progress, completion: completion)
                }
            }
        }
        // success/failed のどちらも来ない場合に詰まらないようウォッチドッグ。
        DispatchQueue.main.asyncAfter(deadline: .now() + perTargetTimeout) {
            finish(.error, [ScrapeInspector.reasonTimeout(seconds: Int(self.perTargetTimeout))])
        }
        fetch(target, { state in
            // state.url はリダイレクト後もステイルなので、実遷移後URLは httpClient.GetCurrentURL() で取る。
            let hostChanged = ScrapeInspector.isHostChanged(requested: target.url, final: self.fetcher.httpClient.GetCurrentURL())
            let (status, reasons) = ScrapeInspector.judge(requireAuth: target.requireAuth, failMessage: nil, evaluateFailures: target.evaluate(state: state), hostChanged: hostChanged, unknownTokens: target.unknownTokens)
            finish(status, reasons)
        }, { _, message in
            let hostChanged = ScrapeInspector.isHostChanged(requested: target.url, final: self.fetcher.httpClient.GetCurrentURL())
            let (status, reasons) = ScrapeInspector.judge(requireAuth: target.requireAuth, failMessage: message, evaluateFailures: [], hostChanged: hostChanged, unknownTokens: target.unknownTokens)
            finish(status, reasons)
        })
    }

    // レポート文字列(サマリ + 明細)。明細は NG→WARN→ROBOTS→ERROR→SKIP→OK の重要度順。
    static func report(results: [Result]) -> String {
        let order: [Status] = [.ng, .warn, .robotsBlocked, .error, .skip, .ok]
        var counts: [Status: Int] = [:]
        for r in results { counts[r.status, default: 0] += 1 }
        let summary = order.compactMap { s -> String? in
            guard let c = counts[s], c > 0 else { return nil }
            return "\(s.rawValue):\(c)"
        }.joined(separator: " / ")
        let sorted = results.sorted { (order.firstIndex(of: $0.status) ?? 0) < (order.firstIndex(of: $1.status) ?? 0) }
        let header = String(format: NSLocalizedString("ScrapeInspector_ReportHeader", comment: "===== 検査結果 (%d件) ====="), results.count)
        return header + "\n" + summary + "\n\n" + sorted.map { $0.description }.joined(separator: "\n")
    }
}

#endif

// MARK: - ローカル最優先SiteInfo の永続化(CSVファイル)
// SiteInfo エディタで保存した SiteInfo をローカルCSVに持ち、StoryHtmlDecoder が「常に最優先ソース」として
// siteInfoArrayArray の先頭へ注入する。中身が空なら何も注入されない(= 自然に「最優先SiteInfo無し」相当)。
// Realm/iCloud は使わない(普段は作者しか使わない機能のため。継承シナリオでは保存するだけで最優先が効く)。
// 正本は生セル行 rows:[[String:String]](設計の「生セルが正本」に一致)。設計メモ: DESIGN_SiteInfoエディタ.md
class LocalSiteInfoStore {
    static let shared = LocalSiteInfoStore()

    // id 復元時に付与する固定の源URL。makeFromCellDict は id を `<base>:<sourceURL>` で作るので、
    // ここを定数にすることで復元のたびに同じ in-memory id になる(rows 側 base id は不変=肥大化しない)。
    static let sourceURLString = "local://preferred-siteinfo"
    // CSV のヘッダ列順(makeFromCellDict が読む列)。
    static let columns = ["id","name","pageElementV2","url","title","subtitle","firstPageLink","nextLink","tag","author","isNeedHeadless","injectStyle","nextButton","firstPageButton","waitSecondInHeadless","forceClickButton","resourceUrl","overrideUserAgent","forceErrorMessageAndElement","scrollTo","isNeedWhitespaceSplitForTag","checkTargets","allowSmartWait"]

    private let fileURL: URL
    // テストから保存先ファイルURLを参照するための口(同じファイルを別インスタンスで読み直す検証用)。
    var fileURLForTest: URL { return fileURL }
    private(set) var rows: [[String:String]] = []

    // 既定は Application Support(.cachesDirectory はOSにパージされ得るので使わない)。テストは init(fileURL:) で一時ディレクトリへ。
    init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = dir.appendingPathComponent("LocalPreferredSiteInfo.csv")
        }
        load()
    }

    func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { rows = []; return }
        let parsed = StoryHtmlDecoder.ParseCSVRows(text)
        guard let headers = parsed.first else { rows = []; return }
        var result: [[String:String]] = []
        for values in parsed.dropFirst() {
            var dict = [String:String]()
            for (h, v) in zip(headers, values) { dict[h] = v }
            // url も pageElementV2 も無い空行はスキップ(末尾の空行など)
            if (dict["url"]?.isEmpty ?? true) && (dict["pageElementV2"]?.isEmpty ?? true) { continue }
            result.append(dict)
        }
        rows = result
    }

    private func csvEscape(_ value: String) -> String {
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // 現在の rows を CSV 文字列に直列化する(Export とファイル保存で共有)。
    func csvString() -> String {
        var lines: [String] = []
        lines.append(LocalSiteInfoStore.columns.map { csvEscape($0) }.joined(separator: ","))
        for row in rows {
            lines.append(LocalSiteInfoStore.columns.map { csvEscape(row[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func save() -> Bool {
        let text = csvString()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // CSV テキストを取り込んで rows へ upsert(Import)。
    // SiteInfo 用CSVの判定: ヘッダに pageElementV2 か url が無ければ別物とみなし nil を返す(取り込まない)。
    // 戻り値: (追加件数, 更新件数)。url が空の行はスキップ。呼び出し側で save()+ReloadLocalPreferredSiteInfo() する。
    @discardableResult
    func importCSVText(_ text: String) -> (added: Int, updated: Int)? {
        let parsed = StoryHtmlDecoder.ParseCSVRows(text)
        guard let headers = parsed.first else { return nil }
        // SiteInfo 用CSVの判定: 固有の列 pageElementV2 を持つことを必須にする(汎用CSVの誤判定を避ける)。
        guard headers.contains("pageElementV2") else { return nil }
        var added = 0
        var updated = 0
        for values in parsed.dropFirst() {
            var dict = [String:String]()
            for (h, v) in zip(headers, values) { dict[h] = v }
            let urlPattern = dict["url"] ?? ""
            if urlPattern.isEmpty { continue }
            // makeFromCellDict が読む列だけに絞る(pageElement 等の余計な列は持ち込まない)。
            var cells = [String:String]()
            for col in LocalSiteInfoStore.columns where dict[col] != nil { cells[col] = dict[col] }
            let exists = rows.contains { ($0["url"] ?? "") == urlPattern }
            upsert(cells)
            if exists { updated += 1 } else { added += 1 }
        }
        return (added, updated)
    }

    // url(マッチ正規表現文字列)をキーに upsert(設計§4 同一性キー=url)。
    // 新規(id 空)は url から決定的な id を採番して行に保存 → 再保存・再読込で id 不変(取込設定の紐付けが安定)。
    func upsert(_ cells: [String:String]) {
        var entry = cells
        let urlPattern = entry["url"] ?? ""
        if (entry["id"]?.isEmpty ?? true) {
            entry["id"] = LocalSiteInfoStore.deterministicId(urlPattern: urlPattern)
        }
        if let idx = rows.firstIndex(where: { ($0["url"] ?? "") == urlPattern }) {
            rows[idx] = entry
        } else {
            rows.append(entry)
        }
    }

    func delete(urlPattern: String) {
        rows.removeAll { ($0["url"] ?? "") == urlPattern }
    }

    // 注入用に [StorySiteInfo] へ復元する。
    // id は行に保存された値をそのまま使う(useStoredId)。これにより、シート版を編集して保存した最優先SiteInfo の id が
    // 元のシート版 id と一致し、取込対象設定(RealmNovelImportSetting)や id 重複除去で同一サイトとして扱える。
    func entries() -> [StorySiteInfo] {
        return rows.compactMap { StorySiteInfo.makeFromCellDict($0, urlString: LocalSiteInfoStore.sourceURLString, useStoredId: true) }
    }

    // url から決定的な base id。String.hashValue は実行毎に変わる(プロセス毎の seed)ため使えない。
    // url そのものを使えば決定的かつ一意(同一url=同一エントリ)。
    static func deterministicId(urlPattern: String) -> String {
        return "localpref:" + urlPattern
    }

    // スプレッドシート貼付け用 TSV の列順。**アプリが管理する列だけ**(pageElement/memo/exampleUrl 等は含めない)。
    // 作者はシート側でアプリ非管理列を先頭に寄せ、この順のアプリ管理列ブロックをその後ろに置き、id 列から貼り付ける運用。
    // → pageElement(数式)は触られず再計算され、memo 等の消失も起きない。最終的なシート列順に合わせてここを調整する。
    // 設計メモ: DESIGN_SiteInfoエディタ.md
    static let spreadsheetColumnOrder = ["id","name","url","pageElementV2","nextLink","title","subtitle","tag","author","firstPageLink","isNeedHeadless","nextButton","firstPageButton","waitSecondInHeadless","forceClickButton","injectStyle","forceErrorMessageAndElement","scrollTo","isNeedWhitespaceSplitForTag","overrideUserAgent","checkTargets","allowSmartWait"]

    // アプリ内 id(`<シートid>:<取得元URL>`)から元のシート id を取り出す(最初の `:` より前)。
    // 例: `5:https://docs.google.com/...csv` → `5`。スプレッドシートへ貼り戻す時に二重 suffix で id が伸び続けるのを防ぐ。
    static func sheetIdValue(from id: String) -> String {
        return String(id.prefix(while: { $0 != ":" }))
    }

    // 1サイト分の生セルを、スプレッドシート貼付け用の1行 TSV にする。
    // 区切りはタブ。タブ/改行/`"` を含むフィールドのみ `"…"` で括り内部の `"` は `""` にエスケープ(Sheets は CSV と同じ規則で1セル扱いにする)。
    // id 列はシート元の値(suffix除去)にする。
    static func spreadsheetTSVRow(_ cells: [String:String]) -> String {
        func tsvEscape(_ value: String) -> String {
            if value.contains("\t") || value.contains("\n") || value.contains("\r") || value.contains("\"") {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }
        return spreadsheetColumnOrder.map { col -> String in
            let raw = (col == "id") ? sheetIdValue(from: cells["id"] ?? "") : (cells[col] ?? "")
            return tsvEscape(raw)
        }.joined(separator: "\t")
    }
}
