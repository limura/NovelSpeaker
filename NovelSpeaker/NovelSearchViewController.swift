//
//  NovelSearchViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/05/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import Eureka
import AnyCodable
import Kanna

@objc protocol MultipleSelectorDoneEnabled {
    @objc func multipleSelectorDone(_ item:UIBarButtonItem);
}


protocol SearchQuery {
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow?
    func CreateQuery() -> String
}

extension SearchQuery {
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return LabelRow() {
            $0.title = "..."
        }
    }
    func CreateQuery() -> String { return "" }
}

class TextQuery: SearchQuery {
    let displayText:String
    let queryName:String
    var inputText:String = ""
    
    init(displayText:String, queryName:String) {
        self.displayText = displayText
        self.queryName = queryName
    }
    
    static func GenerateQuery(value:[String:Any]) -> TextQuery? {
        guard let type = value["queryType"] as? String, type == "text", let displayText = value["displayText"] as? String, let queryName = value["queryName"] as? String else { return nil }
        return TextQuery(displayText: displayText, queryName: queryName)
    }

    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return TextRow() {
            $0.title = displayText
            $0.cell.textLabel?.numberOfLines = 0
            $0.cell.textField.borderStyle = .roundedRect
        }.onChange { (row) in
            if let rowValue = row.cell?.textField?.text {
                self.inputText = rowValue
            }else{
                self.inputText = ""
            }
        }.cellUpdate { (cell, row) in
            cell.textField.clearButtonMode = .always
        }
    }
    func CreateQuery() -> String {
        return queryName + "=" + inputText
    }
}

class MultiSelectQuery: SearchQuery {
    let displayText:String
    let queryName:String
    let ganreList:[String:String]
    let separator:String
    var enableTargets:Set<String> = Set()
    init(displayText:String, queryName:String, genreList:[String:String], separator:String){
        self.displayText = displayText
        self.queryName = queryName
        self.ganreList = genreList
        self.separator = separator
    }
    static func GenerateQuery(value:[String:Any]) -> MultiSelectQuery? {
        guard let type = value["queryType"] as? String, type == "multiSelect", let displayText = value["displayText"] as? String, let queryName = value["queryName"] as? String, let genreArray = value["multiSelect"] as? [String:Any], let separator = value["separator"] as? String else { return nil }
        var genreList:[String:String] = [:]
        for (key,value) in genreArray {
            guard let value = value as? String else { continue }
            genreList[key] = value
        }
        return MultiSelectQuery(displayText: displayText, queryName: queryName, genreList: genreList, separator: separator)
    }
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return MultipleSelectorRow<String>() {
            $0.title = displayText
            $0.selectorTitle = displayText
            $0.options = ([String](self.ganreList.keys)).sorted()
            $0.value = self.enableTargets
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange { (row) in
            if let rowValue = row.value {
                self.enableTargets = rowValue
            }else{
                self.enableTargets = []
            }
        }.onPresent { from, to in
            to.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: from, action: #selector(parent.multipleSelectorDone(_:)))
        }
    }
    func CreateQuery() -> String {
        var queryArray:[String] = []
        for key in enableTargets {
            if let value = self.ganreList[key] {
                queryArray.append(value)
            }
        }
        return queryName + "=" + queryArray.joined(separator: separator)
    }
}

class RadioQuery: SearchQuery {
    let displayText:String
    let queryName:String
    let defaultValue:String
    let radioList:[String:String]
    var enableTarget:String? = nil
    init(displayText:String, queryName:String, defaultValue:String, radioList:[String:String]){
        self.displayText = displayText
        self.queryName = queryName
        self.radioList = radioList
        self.defaultValue = defaultValue
    }
    static func GenerateQuery(value:[String:Any]) -> RadioQuery? {
        guard let type = value["queryType"] as? String, type == "radio", let displayText = value["displayText"] as? String, let queryName = value["queryName"] as? String, let radioArray = value["radio"] as? [String:Any] else { return nil }
        var radioList:[String:String] = [:]
        for (key,value) in radioArray {
            guard let value = value as? String else { continue }
            radioList[key] = value
        }
        let defaultValue:String
        if let valueDefault = value["defaultValue"] as? String {
            defaultValue = valueDefault
        }else{
            defaultValue = ""
        }
        return RadioQuery(displayText: displayText, queryName: queryName, defaultValue: defaultValue, radioList: radioList)
    }
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return AlertRow<String>() {
            $0.title = displayText
            $0.selectorTitle = displayText
            $0.options = ([String](self.radioList.keys)).sorted()
            $0.value = nil
            if defaultValue.count > 0, let key = self.radioList.filter({$0.value == defaultValue}).first?.key {
                $0.value = key
                self.enableTarget = key
            }else{
                $0.options?.append(NSLocalizedString("NovelSearchViewController_RadioSelectTarget_None", comment: "選択しない"))
            }
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange { (row) in
            self.enableTarget = row.value
        }
    }
    func CreateQuery() -> String {
        let value:String
        if let target = enableTarget, let ganreValue = self.radioList[target] {
            value = ganreValue
        }else{
            value = ""
        }
        return queryName + "=" + value
    }
}

class HiddenQuery: SearchQuery {
    let queryName:String
    let value:String
    init(queryName:String, value:String){
        self.queryName = queryName
        self.value = value
    }
    static func GenerateQuery(value:[String:Any]) -> HiddenQuery? {
        guard let type = value["queryType"] as? String, type == "hidden", let queryName = value["queryName"] as? String, let queryValue = value["value"] as? String else { return nil }
        return HiddenQuery(queryName: queryName, value: queryValue)
    }
    
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return nil
    }
    func CreateQuery() -> String {
        return queryName + "=" + value
    }
}

class OnOffQuery: SearchQuery {
    let displayText:String
    let queryName:String
    let value:String
    var isOn:Bool = false
    init(displayText:String, queryName:String, value:String){
        self.displayText = displayText
        self.queryName = queryName
        self.value = value
    }
    static func GenerateQuery(value:[String:Any]) -> OnOffQuery? {
        guard let type = value["queryType"] as? String, type == "onOff", let displayText = value["displayText"] as? String, let queryName = value["queryName"] as? String, let queryValue = value["value"] as? String else { return nil }
        return OnOffQuery(displayText: displayText, queryName: queryName, value: queryValue)
    }
    
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return SwitchRow() {
            $0.title = self.displayText
            $0.value = self.isOn
        }.onChange { (row) in
            self.isOn = row.value ?? false
        }
    }
    func CreateQuery() -> String {
        if isOn {
            return queryName + "=" + value
        }
        return ""
    }
}

class SearchResultBlock {
    let title:String
    let url:URL
    let description:String?

    init(title:String, url:URL, description:String?){
        self.title = title
        self.url = url
        self.description = description
    }
    
    func CreateForm(parent:UIViewController) -> ButtonRow {
        return ButtonRow() {
            $0.title = title
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection { (buttonCellOf, row) in
            func download() {
                DispatchQueue.main.async {
                    NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: parent, url: self.url, cookieString: "")
                }
            }
            if let description = self.description, description.count > 0 {
                DispatchQueue.main.async {
                    NiftyUtilitySwift.EasyDialogBuilder(parent)
                        .title(title: self.title)
                        .textView(content: description, heightMultiplier: 0.6)
                        .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
                            dialog.dismiss(animated: false, completion: nil)
                        })
                        .addButton(title: NSLocalizedString("NovelSearchViewController_DescriptionDisplayedAndTryDownloadButtonTitle", comment: "仮読み込み"), callback: { (dialog) in
                            dialog.dismiss(animated: false) {
                                download()
                            }
                        })
                    .build().show()
                }
            }else{
                download()
            }
        }.cellUpdate({ (cell, button) in
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
            cell.textLabel?.textColor = nil
        })
    }
}

class SearchResult {
    let blockXpath:String
    let nextLinkXpath:String?
    let titleXpath:String?
    let urlXpath:String?
    var nextLink:URL? = nil
    
    init(blockXpath:String, nextLinkXpath:String? = nil, titleXpath:String? = nil, urlXpath:String? = nil) {
        self.blockXpath = blockXpath
        self.nextLinkXpath = nextLinkXpath
        self.titleXpath = titleXpath
        self.urlXpath = urlXpath
    }
    
    static func GenerateObject(value:[String:Any]) -> SearchResult? {
        guard let blockXpath = value["block"] as? String else { return nil }
        let nextLinkXpath = value["nextLink"] as? String
        let titleXpath = value["title"] as? String
        let urlXpath = value["url"] as? String
        return SearchResult(blockXpath: blockXpath, nextLinkXpath: nextLinkXpath, titleXpath: titleXpath, urlXpath: urlXpath)
    }
    
    func ConvertHTMLToSearchResultDataArray(data:Data, headerEncoding: String.Encoding?, baseURL: URL) -> ([SearchResultBlock], URL?) {
        var result:[SearchResultBlock] = []
        let doc:HTMLDocument
        let (htmlOptional, encoding) = NiftyUtilitySwift.decodeHTMLStringFrom(data: data, headerEncoding: headerEncoding)
        if let html = htmlOptional, let htmlDocument = try? HTML(html: html, url: baseURL.absoluteString, encoding: headerEncoding ?? .utf8) {
            doc = htmlDocument
        }else{
            guard let dataHtmlDocument = try? HTML(html: data, url: baseURL.absoluteString, encoding: encoding ?? headerEncoding ?? .utf8) else { return ([], nil) }
            doc = dataHtmlDocument
        }
        //print("ConvertHTMLToSearchResultDataArray: phase 1: baseURL: \(baseURL.absoluteString), data.count: \(data.count), \(String(bytes: data, encoding: .utf8) ?? "nil")")
        for blockHTML in doc.xpath(self.blockXpath) {
            //print("ConvertHTMLToSearchResultDataArray: phase 2 blockHTML.rowXML: \(blockHTML.rawXML)")
            // TODO: 何かうまい方法があれば書き直す
            // 何故か blockHTML.xpath() をすると doc(文章全体) に対して xpath が適用されてしまうので、
            // 仕方がないので blockHTML.rawXML(これは文字列を再生成しているみたいなので負荷が気になる)を
            // XMLDocumentとして再度読み込んでそれを使う事にします。
            guard let rawHtml = blockHTML.innerHTML, let block = try? HTML(html: rawHtml, url: baseURL.absoluteString, encoding: headerEncoding ?? .utf8) else { continue }
            let title:String
            if let titleXpath = self.titleXpath {
                title = NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: block, xpath: titleXpath).trimmingCharacters(in: .whitespacesAndNewlines)
            }else{
                title = ""
            }
            if title.count <= 0 {
                continue
            }
            guard let urlXpath = self.urlXpath, let url = NiftyUtilitySwift.FilterXpathWithExtructFirstHrefLink(xmlDocument: block, xpath: urlXpath, baseURL: baseURL) else {
                continue
            }
            let description = NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: block, xpath: "/html")
            let resultBlock = SearchResultBlock(title: title, url: url, description: description)
            result.append(resultBlock)
        }
        let nextURL:URL?
        if let nextLinkXpath = self.nextLinkXpath, let nextLinkURL = NiftyUtilitySwift.FilterXpathWithExtructFirstHrefLink(xmlDocument: doc, xpath: nextLinkXpath, baseURL: baseURL) {
            nextURL = nextLinkURL
        }else{
            nextURL = nil
        }
        return (result, nextURL)
    }
}

class SearchResultViewController: FormViewController {
    public var resultBlockArray:[SearchResultBlock] = []
    public var searchResult:SearchResult? = nil
    public var nextURL:URL? = nil
    public var siteName:String? = nil
    let loadingCellTag = "loadingCell"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if let siteName = self.siteName {
            self.title = NSLocalizedString("NovelSearchViewController_SearchResultView_Title", comment: "検索結果") + "(" + siteName + ")"
        }else{
            self.title = NSLocalizedString("NovelSearchViewController_SearchResultView_Title", comment: "検索結果")
        }
        createCells()
    }
    
    func generateLoadNextButton(nextURL:URL, section:Section) -> ButtonRow {
        return ButtonRow(self.loadingCellTag) {
            $0.title = NSLocalizedString("NovelSearchViewController_LoadNextPage", comment: "続きを検索しています……")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection { (buttonCellOf, row) in
            //self.loadNextLink(nextURL: nextURL, section: section, row: row)
        }.cellUpdate({ (cell, button) in
            cell.textLabel?.textAlignment = .left
            cell.accessoryType = .disclosureIndicator
            cell.editingAccessoryType = cell.accessoryType
            cell.textLabel?.textColor = nil
        }).cellUpdate { (buttonCellOf, row) in
            self.loadNextLink(nextURL: nextURL, section: section, row: row)
        }
    }
    
    func removeLoadingRow(){
        guard var section = self.form.allSections.first else { return }
        section.removeLast()
    }
    
    func loadNextLink(nextURL:URL, section:Section, row:ButtonRow) {
        DispatchQueue.main.async {
            let allowsCellularAccess:Bool = RealmUtil.RealmBlock { (realm) -> Bool in
                if let globalData = RealmGlobalState.GetInstanceWith(realm: realm), globalData.IsDisallowsCellularAccess {
                    return false
                }
                return true
            }
            NiftyUtilitySwift.httpRequest(url: nextURL, mainDocumentURL: nextURL, allowsCellularAccess: allowsCellularAccess, successAction: { (data, encoding) in
                DispatchQueue.main.async {
                    guard let searchResult = self.searchResult else {
                        self.removeLoadingRow()
                        return
                    }
                    let (resultBlockArray, nextURL) = searchResult.ConvertHTMLToSearchResultDataArray(data: data, headerEncoding: encoding, baseURL: nextURL)
                    self.removeLoadingRow()
                    self.resultBlockArray.append(contentsOf: resultBlockArray)
                    self.nextURL = nextURL
                    for novel in resultBlockArray {
                        section <<< novel.CreateForm(parent: self)
                    }
                    if let nextURL = nextURL {
                        section <<< self.generateLoadNextButton(nextURL: nextURL, section: section)
                    }
                }
            }) { (err) in
                DispatchQueue.main.async {
                    self.removeLoadingRow()
                }
            }
        }

    }
    
    func createCells() {
        let section = Section()
        self.form +++ section
        if resultBlockArray.count <= 0 {
            section <<< LabelRow() {
                $0.title = NSLocalizedString("NovelSearchViewController_SearchResultZero", comment: "検索結果はありませんでした")
            }
            return
        }
        for novel in resultBlockArray {
            section <<< novel.CreateForm(parent: self)
        }
        if let nextURL = self.nextURL {
            section <<< self.generateLoadNextButton(nextURL: nextURL, section: section)
        }
    }
}

protocol ParentViewController:UIViewController,MultipleSelectorDoneEnabled {
}

class WebSiteSection {
    var title:String = ""
    var HTTPMethod:String = "GET"
    var url:String = ""
    var isNeedHeadless:Bool = false
    var mainDocumentURL:String = ""
    var values:[SearchQuery] = []
    var result:SearchResult? = nil
    var parentViewController:ParentViewController
    
    init(parent:ParentViewController) {
        parentViewController = parent
    }
    
    func SetSiteInfoJSON(jsonDecodable: [String:AnyDecodable]) -> Bool {
        if let title = jsonDecodable["title"]?.value as? String {
            self.title = title
        }else{ return false }
        if let HTTPMethod = jsonDecodable["HTTPMethod"]?.value as? String, HTTPMethod == "GET" || HTTPMethod == "POST" {
            self.HTTPMethod = HTTPMethod
        }else{ return false }
        if let url = jsonDecodable["url"]?.value as? String {
            self.url = url
        }else{ return false }
        if let isNeedHeadless = jsonDecodable["isNeedHeadless"]?.value as? Bool {
            self.isNeedHeadless = isNeedHeadless
        }
        if let mainDocumentURL = jsonDecodable["mainDocumentURL"]?.value as? String {
            self.mainDocumentURL = mainDocumentURL
        }
        if let valueArray = jsonDecodable["values"]?.value as? [Any] {
            var values:[SearchQuery] = []
            for value in valueArray {
                guard let value = value as? [String:Any] else { continue }
                guard let type = value["queryType"] as? String else { continue }
                switch type {
                case "text":
                    if let query = TextQuery.GenerateQuery(value: value) {
                        values.append(query)
                    }
                case "multiSelect":
                    if let query = MultiSelectQuery.GenerateQuery(value: value) {
                        values.append(query)
                    }
                case "radio":
                    if let query = RadioQuery.GenerateQuery(value: value) {
                        values.append(query)
                    }
                case "hidden":
                    if let query = HiddenQuery.GenerateQuery(value: value) {
                        values.append(query)
                    }
                case "onOff":
                    if let query = OnOffQuery.GenerateQuery(value: value) {
                        values.append(query)
                    }
                default:
                    // nothing to do!
                    break
                }
            }
            self.values = values
        }
        if let result = jsonDecodable["result"]?.value as? [String:Any] {
            self.result = SearchResult.GenerateObject(value: result)
        }else{ return false }
        return true
    }
    
    func GenerateQueryURL() -> URL? {
        if HTTPMethod == "POST" {
            return URL(string: self.url)
        }
        let query = values.map({$0.CreateQuery()}).joined(separator: "&")
        guard let queryEscaped = query.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) else { return nil }
        guard let url = URL(string: self.url + queryEscaped) else { return nil }
        return url
    }
    
    func GenerateQueryData() -> Data? {
        if HTTPMethod != "POST" {
            return nil
        }
        let query = values.map({$0.CreateQuery()}).joined(separator: "&")
        return query.data(using: .utf8)
    }
    
    func GenerateSection() -> Section {
        let section = Section()
        /*section <<< LabelRow() {
            $0.title = title
        }*/
        for value in values {
            if let form = value.CreateForm(parent: parentViewController) {
                section <<< form
            }
        }
        section <<< ButtonRow() {
            $0.title = NSLocalizedString("NovelSearchViewController_SearchButtonText", comment: "検索")
        }.onCellSelection({ (buttonCellOf, buttonRow) in
            guard let url = self.GenerateQueryURL() else { return }
            DispatchQueue.main.async {
                let allowsCellularAccess:Bool = RealmUtil.RealmBlock {(realm) -> Bool in
                    if let globalData = RealmGlobalState.GetInstanceWith(realm: realm), globalData.IsDisallowsCellularAccess {
                        return false
                    }
                    return true
                }
                NiftyUtilitySwift.EasyDialogNoButton(viewController: self.parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchingMessage", comment: "検索中"), message: nil) { (dialog) in
                    print("query: \(url.absoluteString)")
                    NiftyUtilitySwift.httpRequest(url: url, postData: self.GenerateQueryData(), timeoutInterval: 10, isNeedHeadless: self.isNeedHeadless, mainDocumentURL: URL(string: self.mainDocumentURL), allowsCellularAccess: allowsCellularAccess, successAction: { (data, encoding) in
                        DispatchQueue.main.async {
                            guard let result = self.result else {
                                dialog.dismiss(animated: false) {
                                    DispatchQueue.main.async {
                                        NiftyUtilitySwift.EasyDialogOneButton(viewController: self.parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailed_Title", comment: "検索失敗"), message: NSLocalizedString("NovelSearchViewController_SearchField_Message", comment: "検索に失敗しました。\n恐らくは検索に利用されたWebサイト様側の仕様変更(HTML内容の変更)が影響していると思われます。「Web取込」側で取込を行うか、「Web検索」タブ用のデータが更新されるのをお待ち下さい。"), buttonTitle: nil, buttonAction: nil)
                                    }
                                }
                                return
                            }
                            let (searchResultBlockArray, nextURL) = result.ConvertHTMLToSearchResultDataArray(data: data, headerEncoding: encoding, baseURL: url)
                            dialog.dismiss(animated: false) {
                                DispatchQueue.main.async {
                                    let nextViewController = SearchResultViewController()
                                    nextViewController.resultBlockArray = searchResultBlockArray
                                    nextViewController.nextURL = nextURL
                                    nextViewController.searchResult = result
                                    nextViewController.siteName = self.title
                                    self.parentViewController.navigationController?.pushViewController(nextViewController, animated: true)
                                }
                            }
                        }
                    }) { (err) in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false) {
                                DispatchQueue.main.async {
                                    NiftyUtilitySwift.EasyDialogOneButton(viewController: self.parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailedTitle", comment: "検索に失敗しました"), message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                            }
                        }
                    }
                }
            }
        })
        return section
    }
}

class NovelSearchViewController: FormViewController,ParentViewController {
    var searchInfoArray:[WebSiteSection] = []
    var currentSelectedSite:WebSiteSection? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("NovelSearchViewController_Title", comment: "Web検索")
        self.form +++ Section()
        <<< LabelRow() {
            $0.title = NSLocalizedString("NovelSearchViewController_LoadingSearchInfoTitle", comment: "Web検索用の情報を読み込んでいます……")
            $0.cell.textLabel?.numberOfLines = 0
        }
        loadSearchInfo()
    }
    
    func fetchSearchInfoJSON(urlString: String, successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        guard let url = URL(string: urlString) else {
            failedAction?(nil)
            return
        }
        NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: "SearchInfoData.json", expireTimeinterval: /*60*60*/1, successAction: { (data) in
            successAction?(data)
        }) { (err) in
            failedAction?(err)
        }
    }
    
    func fetchSearchInfo(successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        let fallbackUrlString = "https://raw.githubusercontent.com/limura/NovelSpeaker/gh-pages/data/WebSearchInfo-ja_JP.json"
        let urlString = NSLocalizedString("https://raw.githubusercontent.com/limura/NovelSpeaker/gh-pages/data/WebSearchInfo-ja_JP.json", comment: "適切にURLを返すように Localizable.strings に設定しておく。言語とか地域とかOS側の言語とかアプリ側の言語とかもうわけわからんので NSLocalizedString() 側で設定された言語の設定ファイルを読み込む、というイメージにする。")
        fetchSearchInfoJSON(urlString: urlString, successAction: { (data) in
            successAction?(data)
        }) { (err) in
            if urlString == fallbackUrlString {
                failedAction?(err)
                return
            }
            self.fetchSearchInfoJSON(urlString: fallbackUrlString, successAction: { (data) in
                successAction?(data)
            }) { (err) in
                failedAction?(err)
            }
        }
    }
    
    func extractSearchInfoArray(jsonData:Data) -> [WebSiteSection] {
        let decorder = JSONDecoder()
        guard let searchInfoArray = try? decorder.decode([[String:AnyDecodable]].self, from: jsonData) else { return [] }
        var result:[WebSiteSection] = []
        for searchInfoJSON in searchInfoArray {
            let site = WebSiteSection(parent: self)
            if site.SetSiteInfoJSON(jsonDecodable: searchInfoJSON) {
                result.append(site)
            }
        }
        return result
    }
    
    func loadSearchInfo() {
        fetchSearchInfo(successAction: { (searchInfoArrayJsonData) in
            self.searchInfoArray = self.extractSearchInfoArray(jsonData: searchInfoArrayJsonData)
            self.currentSelectedSite = self.searchInfoArray.first
            self.reloadCells()
        }) { (err) in
            DispatchQueue.main.async {
                if self.form.count > 0 {
                    self.form.removeAll()
                }
                self.form +++ Section()
                <<< TextRow() {
                    $0.title = NSLocalizedString("NovelSearchViewController_SearchInfoLoadError_Title", comment: "検索設定の読み込みに失敗")
                    $0.cell.textLabel?.numberOfLines = 0
                }
                <<< TextRow() {
                    $0.title = NSLocalizedString("NovelSearchViewController_SearchInfoLoadError_Message", comment: "検索設定の読み込みに失敗しました。ネットワーク接続がうまくいっていない場合にこの問題が生じる可能性があります。通信状況を確認してみてください。")
                    $0.cell.textLabel?.numberOfLines = 0
                }
            }
        }
    }
    
    func reloadCells() {
        DispatchQueue.main.async {
            if self.form.count > 0 {
                self.form.removeAll()
            }
            self.form +++ Section()
            <<< AlertRow<String>() {
                $0.title = NSLocalizedString("NovelSearchViewController_SearchWebSiteTitle", comment: "検索先のWebサイト")
                $0.selectorTitle = $0.title
                let titleArray = ([String](self.searchInfoArray.map({$0.title}))).sorted()
                $0.options = titleArray
                $0.value = self.currentSelectedSite?.title
                $0.cell.textLabel?.numberOfLines = 0
            }.onChange { (row) in
                guard let selectedTitle = row.value else { return }
                guard let selectedSite = self.searchInfoArray.filter({$0.title == selectedTitle}).first else { return }
                self.currentSelectedSite = selectedSite
                self.reloadCells()
            }
            if let currentSite = self.currentSelectedSite {
                self.form +++ currentSite.GenerateSection()
            }
        }
    }

    @objc func multipleSelectorDone(_ item:UIBarButtonItem) {
        _ = navigationController?.popViewController(animated: true)
    }
}
