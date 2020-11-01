//
//  NovelSearchViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/05/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import Eureka
import Kanna

@objc protocol MultipleSelectorDoneEnabled {
    @objc func multipleSelectorDone(_ item:UIBarButtonItem);
}


protocol SearchQuery {
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow?
    func CreateQuery(joinner:String) -> String
}

extension SearchQuery {
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return LabelRow() {
            $0.title = "..."
        }
    }
    func CreateQuery(joinner:String) -> String { return "" }
}

class TextQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    var inputText:String = ""
    
    init(displayText:String, queryName:String) {
        self.displayText = displayText
        self.queryName = queryName
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
    func CreateQuery(joinner:String) -> String {
        return queryName + joinner + inputText
    }
}

class MultiSelectQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    let multiSelect:[String:String]
    let separator:String
    var enableTargets:Set<String> = Set()
    init(displayText:String, queryName:String, multiSelect:[String:String], separator:String){
        self.displayText = displayText
        self.queryName = queryName
        self.multiSelect = multiSelect
        self.separator = separator
    }

    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return MultipleSelectorRow<String>() {
            $0.title = displayText
            $0.selectorTitle = displayText
            $0.options = ([String](self.multiSelect.keys)).sorted()
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
    func CreateQuery(joinner:String) -> String {
        var queryArray:[String] = []
        for key in enableTargets {
            if let value = self.multiSelect[key] {
                queryArray.append(value)
            }
        }
        // queryName が空であれば、separator で join しただけの物を返します。
        // つまり、separator を "&" にして、multiSelect の value に "hoge=1" 的な物を入れておけば、
        // hoge=1&hage=1&hige=1 のような query を生成して返す事ができます。
        if queryName == "" {
            return queryArray.joined(separator: separator)
        }
        return queryName + joinner + queryArray.joined(separator: separator)
    }
}

class RadioQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    let defaultValue:String
    let radioList:[String:String]
    var enableTarget:String? = nil
    init(displayText:String, queryName:String, defaultValue:String?, radioList:[String:String]){
        self.displayText = displayText
        self.queryName = queryName
        self.radioList = radioList
        self.defaultValue = defaultValue ?? ""
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
    func CreateQuery(joinner:String) -> String {
        let value:String
        if let target = enableTarget, let ganreValue = self.radioList[target] {
            value = ganreValue
        }else{
            value = ""
        }
        return queryName + joinner + value
    }
}

class HiddenQuery: SearchQuery, Decodable {
    let queryName:String
    let value:String
    init(queryName:String, value:String){
        self.queryName = queryName
        self.value = value
    }
    
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return nil
    }
    func CreateQuery(joinner:String) -> String {
        return queryName + joinner + value
    }
}

class OnOffQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    let value:String
    var isOn:Bool = false
    init(displayText:String, queryName:String, value:String){
        self.displayText = displayText
        self.queryName = queryName
        self.value = value
    }
    
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return SwitchRow() {
            $0.title = self.displayText
            $0.value = self.isOn
        }.onChange { (row) in
            self.isOn = row.value ?? false
        }
    }
    func CreateQuery(joinner:String) -> String {
        if isOn {
            return queryName + joinner + value
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
                    NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: parent, url: self.url, cookieString: "", isNeedFallbackImportFromWebPageTab: false)
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

struct SearchResult : Decodable {
    let blockXpath:String
    let nextLinkXpath:String?
    let titleXpath:String?
    let urlXpath:String?
    var nextLink:URL? = nil
    
    enum CodingKeys: String, CodingKey {
        case blockXpath = "block"
        case nextLinkXpath = "nextLink"
        case titleXpath = "title"
        case urlXpath = "url"
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        blockXpath = try values.decode(String.self, forKey: .blockXpath)
        nextLinkXpath = try? values.decode(String.self, forKey: .nextLinkXpath)
        titleXpath = try? values.decode(String.self, forKey: .titleXpath)
        urlXpath = try? values.decode(String.self, forKey: .urlXpath)
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
            //print("ConvertHTMLToSearchResultDataArray: phase 2 blockHTML.rowXML: \(blockHTML.toHTML ?? "nil")")
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

class WebSiteSection : Decodable {
    var title:String = ""
    var HTTPMethod:String = "GET"
    var url:String = ""
    var isNeedHeadless:Bool = false
    var querySeparator:String = "&"
    var queryJoinner:String = "="
    var mainDocumentURL:String = ""
    var values:[SearchQuery] = []
    var result:SearchResult? = nil
    //var parentViewController:ParentViewController
    
    enum CodingKeys: String, CodingKey {
        case title
        case HTTPMethod
        case url
        case isNeedHeadless
        case querySeparator
        case queryJoinner
        case mainDocumentURL
        case values
        case result
    }
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        title = try values.decode(String.self, forKey: .title)
        HTTPMethod = (try? values.decode(String.self, forKey: .HTTPMethod)) ?? "GET"
        url = try values.decode(String.self, forKey: .url)
        isNeedHeadless = (try? values.decode(Bool.self, forKey: .isNeedHeadless)) ?? false
        querySeparator = (try? values.decode(String.self, forKey: .querySeparator)) ?? "&"
        queryJoinner = (try? values.decode(String.self, forKey: .queryJoinner)) ?? "="
        mainDocumentURL = (try? values.decode(String.self, forKey: .mainDocumentURL)) ?? ""

        // 怪しく全てを読み込める struct を作って一旦読み込みます(´・ω・`)
        struct DummySearchQuery: Decodable {
            let queryType:String
            let queryName:String
            let displayText:String?
            let separator:String?
            let multiSelect:[String:String]?
            let radio:[String:String]?
            let value:String?
            let defaultValue:String?
        }
        var generatedValues:[SearchQuery] = []
        if let queryArray = try? values.decode([DummySearchQuery].self, forKey: .values) {
            for query in queryArray {
                switch query.queryType {
                case "text":
                    if let displayText = query.displayText {
                        generatedValues.append(TextQuery(displayText: displayText, queryName: query.queryName))
                    }
                case "multiSelect":
                    if let displayText = query.displayText, let multiSelect = query.multiSelect, let separator = query.separator {
                        generatedValues.append(MultiSelectQuery(displayText: displayText, queryName: query.queryName, multiSelect: multiSelect, separator: separator))
                    }
                case "radio":
                    if let displayText = query.displayText, let radio = query.radio {
                        generatedValues.append(RadioQuery(displayText: displayText, queryName: query.queryName, defaultValue: query.defaultValue, radioList: radio))
                    }
                case "hidden":
                    if let value = query.value {
                        generatedValues.append(HiddenQuery(queryName: query.queryName, value: value))
                    }
                case "onOff":
                    if let displayText = query.displayText, let value = query.value {
                        generatedValues.append(OnOffQuery(displayText: displayText, queryName: query.queryName, value: value))
                    }
                default:
                    break
                }
            }
            self.values = generatedValues
        }
        result = try? values.decode(SearchResult.self, forKey: .result)
    }
    
    func GenerateQueryURL() -> URL? {
        if HTTPMethod == "POST" {
            return URL(string: self.url)
        }
        var query = ""
        for value in values {
            let v = value.CreateQuery(joinner: queryJoinner)
            if v.count <= 0 {
                continue
            }
            if query.count > 0 {
                query += querySeparator
            }
            query += v
        }
        guard let queryEscaped = query.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) else { return nil }
        guard let url = URL(string: self.url + queryEscaped) else { return nil }
        return url
    }
    
    func GenerateQueryData() -> Data? {
        if HTTPMethod != "POST" {
            return nil
        }
        let query = values.map({$0.CreateQuery(joinner: queryJoinner)}).joined(separator: querySeparator)
        return query.data(using: .utf8)
    }
    
    func GenerateSection(parentViewController:ParentViewController) -> Section {
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
                NiftyUtilitySwift.EasyDialogNoButton(viewController: parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchingMessage", comment: "検索中"), message: nil) { (dialog) in
                    print("query: \(url.absoluteString)")
                    NiftyUtilitySwift.httpRequest(url: url, postData: self.GenerateQueryData(), timeoutInterval: 10, isNeedHeadless: self.isNeedHeadless, mainDocumentURL: URL(string: self.mainDocumentURL), allowsCellularAccess: allowsCellularAccess, successAction: { (data, encoding) in
                        DispatchQueue.main.async {
                            guard let result = self.result else {
                                dialog.dismiss(animated: false) {
                                    DispatchQueue.main.async {
                                        NiftyUtilitySwift.EasyDialogOneButton(viewController: parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailed_Title", comment: "検索失敗"), message: NSLocalizedString("NovelSearchViewController_SearchField_Message", comment: "検索に失敗しました。\n恐らくは検索に利用されたWebサイト様側の仕様変更(HTML内容の変更)が影響していると思われます。「Web取込」側で取込を行うか、「Web検索」タブ用のデータが更新されるのをお待ち下さい。"), buttonTitle: nil, buttonAction: nil)
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
                                    parentViewController.navigationController?.pushViewController(nextViewController, animated: true)
                                }
                            }
                        }
                    }) { (err) in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false) {
                                DispatchQueue.main.async {
                                    NiftyUtilitySwift.EasyDialogOneButton(viewController: parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailedTitle", comment: "検索に失敗しました"), message: nil, buttonTitle: nil, buttonAction: nil)
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
    static var lastSearchInfoLoadDate:Date = Date(timeIntervalSince1970: 0)
    static let SearchInfoCacheFileName = "SearchInfoData.json"
    let searchInfoExpireTimeInterval:TimeInterval = 60*60*6 // 6時間
    
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
    
    override func viewDidAppear(_ animated: Bool) {
        checkAndReloadSearchInfoIfNeeded()
        super.viewDidAppear(animated)
    }
    
    static func SearchInfoCacheClear() {
        lastSearchInfoLoadDate = Date(timeIntervalSince1970: 0)
        NiftyUtilitySwift.FileCachedHttpGet_RemoveCacheFile(cacheFileName: SearchInfoCacheFileName)
    }
    
    func checkAndReloadSearchInfoIfNeeded() {
        if NovelSearchViewController.lastSearchInfoLoadDate < Date(timeIntervalSinceNow: -searchInfoExpireTimeInterval) {
            loadSearchInfo()
        }
    }
    
    func fetchSearchInfoJSON(url: URL, successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: NovelSearchViewController.SearchInfoCacheFileName, expireTimeinterval: searchInfoExpireTimeInterval, canRecoverOldFile: true, successAction: { (data) in
            successAction?(data)
        }) { (err) in
            failedAction?(err)
        }
    }
    
    func fetchSearchInfo(successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        var urlQueue:[URL] = []
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let userDefinedURL = RealmGlobalState.GetInstanceWith(realm: realm)?.searchInfoURL, let url = URL(string: userDefinedURL) else { return }
            urlQueue.append(url)
        }
        if let url = URL(string: NSLocalizedString("https://raw.githubusercontent.com/limura/NovelSpeaker/gh-pages/data/WebSearchInfo-ja_JP.json", comment: "適切にURLを返すように Localizable.strings に設定しておく。言語とか地域とかOS側の言語とかアプリ側の言語とかもうわけわからんので NSLocalizedString() 側で設定された言語の設定ファイルを読み込む、というイメージにする。")) {
            urlQueue.append(url)
        }
        if let url = URL(string: "https://raw.githubusercontent.com/limura/NovelSpeaker/gh-pages/data/WebSearchInfo-ja_JP.json") {
            urlQueue.append(url)
        }
        var lastError:Error? = nil
        func fetchOne(queue:[URL], index:Int) {
            if queue.count <= index {
                failedAction?(lastError)
            }
            let url = queue[index]
            fetchSearchInfoJSON(url: url, successAction: { (data) in
                successAction?(data)
                return
            }, failedAction: { (err) in
                lastError = err
                fetchOne(queue: queue, index: index + 1)
            })
        }
        fetchOne(queue: urlQueue, index: 0)
    }
    
    func extractSearchInfoArray(jsonData:Data) -> [WebSiteSection] {
        let decorder = JSONDecoder()
        guard let result = try? decorder.decode([WebSiteSection].self, from: jsonData) else { return [] }
        return result
    }
    
    func loadSearchInfo() {
        fetchSearchInfo(successAction: { (searchInfoArrayJsonData) in
            self.searchInfoArray = self.extractSearchInfoArray(jsonData: searchInfoArrayJsonData)
            NovelSearchViewController.lastSearchInfoLoadDate = Date()
            RealmUtil.RealmBlock { (realm) -> Void in
                if let siteString = RealmGlobalState.GetInstanceWith(realm: realm)?.currentWebSearchSite, let section = self.searchInfoArray.filter({ $0.title == siteString }).first {
                    self.currentSelectedSite = section
                }else{
                    self.currentSelectedSite = self.searchInfoArray.first
                }
            }
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
                <<< ButtonRow() {
                    $0.title = NSLocalizedString("NovelSearchViewController_ForceReloadSearchInfoButton_Title", comment: "検索設定の読み込みを試みる")
                    $0.cell.textLabel?.numberOfLines = 0
                }.onCellSelection({ (cellOf, row) in
                    self.loadSearchInfo()
                })
            }
        }
    }
    
    func reloadCells() {
        DispatchQueue.main.async {
            NiftyUtilitySwift.headlessClientLoadAboutPage()
            self.form.removeAll()
            self.form +++ Section()
            <<< LabelRow() {
                $0.title = NSLocalizedString("NovelSearchViewController_NoticeLabelText", comment: "ご注意: 本ページの「Web検索」機能については、リストされているWebサイト様側の仕様が少しでも変わると途端に動作しなくなるような仕組みを用いておりますため、うまく利用できなくなる可能性がとても高い物となっております。\nうまく利用できなくなっている場合でも、Web取込機能側で取り込む事で回避できる場合もございますのでそちらをご利用頂くような形で回避していただけますと幸いです。")
                $0.cell.textLabel?.font = .preferredFont(forTextStyle: .caption2)
                $0.cell.textLabel?.numberOfLines = 0
            }
            +++ Section()
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
                if let currentSelectedSiteTitle = self.currentSelectedSite?.title, currentSelectedSiteTitle == selectedTitle { return }
                self.currentSelectedSite = selectedSite
                RealmUtil.RealmBlockWrite { (realm) in
                    if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                        globalState.currentWebSearchSite = selectedSite.title
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.reloadCells()
                }
            }
            if let currentSite = self.currentSelectedSite {
                self.form +++ currentSite.GenerateSection(parentViewController: self)
            }
        }
    }

    @objc func multipleSelectorDone(_ item:UIBarButtonItem) {
        _ = navigationController?.popViewController(animated: true)
    }
}
