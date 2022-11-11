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
import Erik

@objc protocol MultipleSelectorDoneEnabled {
    @objc func multipleSelectorDone(_ item:UIBarButtonItem);
}


protocol SearchQuery {
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow?
    func CreateQuery(joinner:String) -> String
    func ReplaceURL(urlString:String) -> String
}

extension SearchQuery {
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return LabelRow() {
            $0.title = "..."
        }
    }
    func CreateQuery(joinner:String) -> String { return "" }
    func ReplaceURL(urlString:String) -> String { return urlString }
}

class TextQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    let urlReplaceTarget:String?
    var inputText:String = ""
    
    init(displayText:String, queryName:String, urlReplaceTarget:String?) {
        self.displayText = displayText
        self.queryName = queryName
        self.urlReplaceTarget = urlReplaceTarget
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
        if let urlReplaceTarget = self.urlReplaceTarget, urlReplaceTarget.count > 0 { return "" }
        if queryName.count == 0 && inputText.count == 0 { return "" }
        if queryName.count == 0 { return inputText }
        return queryName + joinner + inputText
    }
    func ReplaceURL(urlString:String) -> String {
        guard let urlReplaceTarget = self.urlReplaceTarget, urlReplaceTarget.count > 0, inputText.count > 0, let text = inputText.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) else { return urlString }
        return urlString.replacingOccurrences(of: urlReplaceTarget, with: text)
    }
}

class MultiSelectQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    let multiSelect:[String:String]
    let separator:String
    var enableTargets:Set<String> = Set()
    init(displayText:String, queryName:String, multiSelect:[String:String], separator:String, defaultTargets:[String]?){
        self.displayText = displayText
        self.queryName = queryName
        self.multiSelect = multiSelect
        self.separator = separator
        if let defaultTargets = defaultTargets?.filter({ str in
            return multiSelect.keys.contains(str)
        }) {
            for target in defaultTargets {
                enableTargets.insert(target)
            }
        }
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
    func ReplaceURL(urlString:String) -> String { return urlString }
}

class RadioQuery: SearchQuery, Decodable {
    let displayText:String
    let queryName:String
    let defaultValue:String?
    let radioList:[String:String]
    var enableTarget:String? = nil
    let urlReplaceTarget:String?
    init(displayText:String, queryName:String, defaultValue:String?, radioList:[String:String], urlReplaceTarget:String?){
        self.displayText = displayText
        self.queryName = queryName
        self.radioList = radioList
        self.defaultValue = defaultValue
        self.urlReplaceTarget = urlReplaceTarget
    }

    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return AlertRow<String>() {
            $0.title = displayText
            $0.selectorTitle = displayText
            $0.options = ([String](self.radioList.keys)).sorted()
            $0.value = nil
            if let defaultValue = defaultValue, let key = self.radioList.filter({$0.value == defaultValue}).first?.key {
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
        if let urlReplaceTarget = self.urlReplaceTarget, urlReplaceTarget.count > 0 { return "" }
        let value:String
        if let target = enableTarget, let ganreValue = self.radioList[target] {
            value = ganreValue
        }else{
            value = ""
        }
        if queryName.count == 0 && value.count == 0 { return "" }
        if queryName.count == 0 { return value }
        return queryName + joinner + value
    }
    func ReplaceURL(urlString:String) -> String {
        guard let urlReplaceTarget = self.urlReplaceTarget, urlReplaceTarget.count > 0 else { return urlString }
        guard let target = enableTarget, let ganreValue = self.radioList[target], ganreValue.count > 0, let text = ganreValue.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) else {
            return urlString
        }
        return urlString.replacingOccurrences(of: urlReplaceTarget, with: text)
    }
}

class HiddenQuery: SearchQuery, Decodable {
    let queryName:String
    let value:String
    let urlReplaceTarget:String?
    init(queryName:String, value:String, urlReplaceTarget: String?){
        self.queryName = queryName
        self.value = value
        self.urlReplaceTarget = urlReplaceTarget
    }
    
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return nil
    }
    func CreateQuery(joinner:String) -> String {
        if self.urlReplaceTarget?.count ?? 0 > 0 { return "" }
        if queryName.count == 0 { return value }
        return queryName + joinner + value
    }
    func ReplaceURL(urlString:String) -> String {
        guard let urlReplaceTarget = self.urlReplaceTarget, urlReplaceTarget.count > 0, let text = self.value.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed)  else { return urlString }
        return urlString.replacingOccurrences(of: urlReplaceTarget, with: text)
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
            $0.cell.textLabel?.numberOfLines = 0
        }.onChange { (row) in
            self.isOn = row.value ?? false
        }
    }
    func CreateQuery(joinner:String) -> String {
        if isOn {
            if queryName.count == 0 { return value }
            return queryName + joinner + value
        }
        return ""
    }
    func ReplaceURL(urlString:String) -> String { return urlString }
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
                    NiftyUtility.checkUrlAndConifirmToUser(viewController: parent, url: self.url, cookieString: nil, isNeedFallbackImportFromWebPageTab: false)
                }
            }
            if let description = self.description, description.count > 0 {
                DispatchQueue.main.async {
                    NiftyUtility.EasyDialogBuilder(parent)
                    .title(title: self.title, numberOfLines: 1)
                    .textView(content: description, heightMultiplier: 0.6)
                    .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
                        dialog.dismiss(animated: false, completion: nil)
                    })
                    .addButton(title: NSLocalizedString("NovelSearchViewController_OpenWebImportButtonTitle", comment: "Web取込 タブで開いて確認する"), callback: { dialog in
                        dialog.dismiss(animated: false) {
                            BookShelfRATreeViewController.LoadWebPageOnWebImportTab(url: self.url)
                        }
                    })
                    .addButton(title: NSLocalizedString("NovelSearchViewController_DescriptionDisplayedAndTryDownloadButtonTitle", comment: "仮読み込み"), callback: { (dialog) in
                        dialog.dismiss(animated: false) {
                            download()
                        }
                    })
                    .build(isForMessageDialog: true).show()
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
    let nextLinkButton:String?
    var urlConvRegexpFrom:String?
    var urlConvRegexpTo:String?
    
    enum CodingKeys: String, CodingKey {
        case blockXpath = "block"
        case nextLinkXpath = "nextLink"
        case titleXpath = "title"
        case urlXpath = "url"
        case nextLinkButton = "nextLinkButton"
        case convRegexpFrom = "urlConvRegexpFrom"
        case convRegexpTo = "urlConvRegexpTo"
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        blockXpath = try values.decode(String.self, forKey: .blockXpath)
        nextLinkXpath = try? values.decode(String.self, forKey: .nextLinkXpath)
        titleXpath = try? values.decode(String.self, forKey: .titleXpath)
        urlXpath = try? values.decode(String.self, forKey: .urlXpath)
        nextLinkButton = try? values.decode(String.self, forKey: .nextLinkButton)
        urlConvRegexpFrom = try? values.decode(String.self, forKey: .convRegexpFrom)
        urlConvRegexpTo = try? values.decode(String.self, forKey: .convRegexpTo)
    }
    
    func ConvertHTMLToSearchResultDataArray(data:Data, headerEncoding: String.Encoding?, baseURL: URL, completion: @escaping (([SearchResultBlock], URL?, Element?)->Void)) {
        var result:[SearchResultBlock] = []
        let doc:HTMLDocument
        let (htmlOptional, encoding) = NiftyUtility.decodeHTMLStringFrom(data: data, headerEncoding: headerEncoding)
        if let html = htmlOptional, let htmlDocument = try? HTML(html: html, url: baseURL.absoluteString, encoding: headerEncoding ?? .utf8) {
            doc = htmlDocument
        }else{
            guard let dataHtmlDocument = try? HTML(html: data, url: baseURL.absoluteString, encoding: encoding ?? headerEncoding ?? .utf8) else {
                completion([], nil, nil)
                return
            }
            doc = dataHtmlDocument
        }
        //print("ConvertHTMLToSearchResultDataArray: phase 1: baseURL: \(baseURL.absoluteString), data.count: \(data.count), \(String(bytes: data, encoding: .utf8) ?? "nil")")
        //print("blockXpath: \(self.blockXpath), nextLinkXpath: \(nextLinkXpath ?? "nil"), titleXpath: \(titleXpath ?? "nil"), urlXpath: \(urlXpath ?? "nil"), nextLinkButton: \(nextLinkButton ?? "nil"), urlConvRegexpFrom: \(urlConvRegexpFrom ?? "nil"), urlConvRegexpTo: \(urlConvRegexpTo ?? "nil")")
        for blockHTMLElement in doc.xpath(self.blockXpath) {
            let blockHTML:XMLElement
            if let blockHTMLString = blockHTMLElement.toHTML, let blockHTMLData = blockHTMLString.data(using: .utf8, allowLossyConversion: true), let blockDocument = try? HTML(html: blockHTMLData, encoding: .utf8), let blockElement = blockDocument.body {
                blockHTML = blockElement
            }else{
                blockHTML = blockHTMLElement
            }
            //print("ConvertHTMLToSearchResultDataArray: phase 2 blockHTML.rowXML: \(blockHTML.toHTML ?? "nil")")
            let title:String
            if let titleXpath = self.titleXpath {
                title = NiftyUtility.FilterXpathWithConvertString(xmlElement: blockHTML, xpath: titleXpath).trimmingCharacters(in: .whitespacesAndNewlines)
            }else{
                title = ""
            }
            if title.count <= 0 {
                continue
            }
            guard let urlXpath = self.urlXpath else {
                continue
            }
            // convRegexpFrom が定義されているのなら、urlXpath で指定されている物からさらに convRegexpFrom のものを convRegexpTo に置き換える形で変形したものを URL の元ネタとして利用します。
            let url:URL
            if let convRegexpFrom = self.urlConvRegexpFrom {
                let urlTarget = NiftyUtility.FilterXpathToHtml(xmlElement: blockHTML, xpath: urlXpath)
                //print("conv: \(urlTarget.replacingOccurrences(of: convRegexpFrom, with: self.urlConvRegexpTo ?? "", options: .regularExpression)) + \(baseURL.absoluteString)")
                if urlTarget.count > 0, let target = URL(string: urlTarget.replacingOccurrences(of: convRegexpFrom, with: self.urlConvRegexpTo ?? "", options: .regularExpression), relativeTo: baseURL) {
                    url = target
                }else{
                    continue
                }
            }else{
                guard let urlTarget = NiftyUtility.FilterXpathWithExtructFirstHrefLink(xmlElement: blockHTML, xpath: urlXpath, baseURL: baseURL) else {
                    continue
                }
                url = urlTarget
            }
            let description = NiftyUtility.FilterXpathWithConvertString(xmlElement: blockHTML, xpath: "/*")
            let resultBlock = SearchResultBlock(title: title, url: url, description: description)
            result.append(resultBlock)
        }
        let nextURL:URL?
        if let nextLinkXpath = self.nextLinkXpath, let nextLinkURL = NiftyUtility.FilterXpathWithExtructFirstHrefLink(xmlDocument: doc, xpath: nextLinkXpath, baseURL: baseURL) {
            nextURL = nextLinkURL
        }else{
            nextURL = nil
        }
        if let nextLinkButton = self.nextLinkButton {
            NiftyUtility.QuerySelectorForHeadlessHTTPClient(key: NovelSearchViewController.HeadlessHTTPClientKey, selector: nextLinkButton) { element in
                guard let element = element else {
                    completion(result, nextURL, nil)
                    return
                }
                completion(result, nil, element)
            }
            return
        }
        completion(result, nextURL, nil)
    }
}

class SearchResultViewController: FormViewController {
    public var resultBlockArray:[SearchResultBlock] = []
    public var searchResult:SearchResult? = nil
    public var nextURL:URL? = nil
    public var siteName:String? = nil
    public var isNeedHeadless:Bool = false
    public var waitSecondInHeadless:Double? = nil
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
    
    func generateLoadNextLinkRow(nextURL:URL, section:Section) -> ButtonRow {
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
    func generateLoadNextButtonRow(nextButtonElement:Element, section:Section, baseURL: URL) -> ButtonRow {
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
            NiftyUtility.EasyDialogNoButton(viewController: self, title: NSLocalizedString("NovelSearchViewController_LoadingNextLink_Title", comment: "読込中……"), message: nil) { (dialog) in
                self.removeLoadingRow()
                NiftyUtility.ClickOnHeadlessHTTPClient(key: NovelSearchViewController.HeadlessHTTPClientKey, element: nextButtonElement) { html in
                    guard let html = html, let data = html.data(using: .utf8, allowLossyConversion: true) else {
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false)
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self.loadNextLinkCore(dialog: dialog, section: section, data: data, encoding: .utf8, baseURL: baseURL)
                    }
                }
            }
        }
    }
    
    func removeLoadingRow(){
        guard var section = self.form.allSections.first else { return }
        section.removeLast()
    }
    
    func loadNextLinkCore(dialog:EasyDialog, section:Eureka.Section, data:Data, encoding:String.Encoding?, baseURL: URL) {
        //DispatchQueue.main.async {
            guard let searchResult = self.searchResult else {
                self.removeLoadingRow()
                dialog.dismiss(animated: false, completion: nil)
                return
            }
        searchResult.ConvertHTMLToSearchResultDataArray(data: data, headerEncoding: encoding, baseURL: baseURL) { (resultBlockArray, nextURL, nextButton) in
            self.removeLoadingRow()
            self.resultBlockArray.append(contentsOf: resultBlockArray)
            if resultBlockArray.count > 0 {
                self.nextURL = nextURL
                for novel in resultBlockArray {
                    section <<< novel.CreateForm(parent: self)
                }
                if let nextButton = nextButton {
                    section <<< self.generateLoadNextButtonRow(nextButtonElement: nextButton, section: section, baseURL: baseURL)
                } else if let nextURL = nextURL {
                    section <<< self.generateLoadNextLinkRow(nextURL: nextURL, section: section)
                }
            }
            dialog.dismiss(animated: false, completion: nil)
        }
        //}
    }
    
    func loadNextLink(nextURL:URL, section:Section, row:ButtonRow) {
        DispatchQueue.main.async {
            let allowsCellularAccess:Bool = RealmUtil.RealmBlock { (realm) -> Bool in
                if let globalData = RealmGlobalState.GetInstanceWith(realm: realm), globalData.IsDisallowsCellularAccess {
                    return false
                }
                return true
            }
            NiftyUtility.EasyDialogNoButton(viewController: self, title: NSLocalizedString("NovelSearchViewController_LoadingNextLink_Title", comment: "読込中……"), message: nil) { (dialog) in
                NiftyUtility.httpRequest(url: nextURL, isNeedHeadless: self.isNeedHeadless, mainDocumentURL: nextURL, allowsCellularAccess: allowsCellularAccess, headlessClientKey: NovelSearchViewController.HeadlessHTTPClientKey, withWaitSecond: self.waitSecondInHeadless, successAction: { (data, encoding) in
                    DispatchQueue.main.async {
                        self.loadNextLinkCore(dialog: dialog, section: section, data: data, encoding: encoding, baseURL: nextURL)
                    }
                }) { (err) in
                    DispatchQueue.main.async {
                        self.removeLoadingRow()
                        dialog.dismiss(animated: false, completion: nil)
                    }
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
            section <<< self.generateLoadNextLinkRow(nextURL: nextURL, section: section)
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
    var isDisabled:Bool? = false
    var waitSecondInHeadless:Double? = nil
    var announce:String? = nil
    var webSiteURL:URL? = nil
    var allowDataVersion:Int = 0
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
        case isDisabled
        case waitSecondInHeadless
        case announce
        case webSiteURL
        case allowDataVersion
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
        isDisabled = (try? values.decodeIfPresent(Bool.self, forKey: .isDisabled)) ?? false
        waitSecondInHeadless = try? values.decode(Double.self, forKey: .waitSecondInHeadless)
        announce = try? values.decode(String.self, forKey: .announce)
        if let webSiteURLString = try? values.decode(String.self, forKey: .webSiteURL) {
            webSiteURL = URL(string: webSiteURLString)
        }
        allowDataVersion = (try? values.decode(Int.self, forKey: .allowDataVersion)) ?? 0

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
            let multiSelectDefaultTargets:[String]?
            let urlReplaceTarget:String?
        }
        var generatedValues:[SearchQuery] = []
        if let queryArray = try? values.decode([DummySearchQuery].self, forKey: .values) {
            for query in queryArray {
                switch query.queryType {
                case "text":
                    if let displayText = query.displayText {
                        generatedValues.append(TextQuery(displayText: displayText, queryName: query.queryName, urlReplaceTarget: query.urlReplaceTarget))
                    }
                case "multiSelect":
                    if let displayText = query.displayText, let multiSelect = query.multiSelect, let separator = query.separator {
                        generatedValues.append(MultiSelectQuery(displayText: displayText, queryName: query.queryName, multiSelect: multiSelect, separator: separator, defaultTargets:query.multiSelectDefaultTargets))
                    }
                case "radio":
                    if let displayText = query.displayText, let radio = query.radio {
                        generatedValues.append(RadioQuery(displayText: displayText, queryName: query.queryName, defaultValue: query.defaultValue, radioList: radio, urlReplaceTarget: query.urlReplaceTarget))
                    }
                case "hidden":
                    if let value = query.value {
                        generatedValues.append(HiddenQuery(queryName: query.queryName, value: value, urlReplaceTarget: query.urlReplaceTarget))
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
        var url = self.url
        var query = ""
        for value in values {
            url = value.ReplaceURL(urlString: url)
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
        // この URL 生成は失敗して nil が返る可能性があります。(呼び出し元はそれを考慮しているはずです)
        return URL(string: url + queryEscaped)
    }
    
    func GenerateQueryData() -> Data? {
        if HTTPMethod != "POST" {
            return nil
        }
        var queryArray:[String] = []
        for value in values {
            let q = value.CreateQuery(joinner: queryJoinner)
            if q.count > 0 {
                queryArray.append(q)
            }
        }
        let query = queryArray.joined(separator: querySeparator)
        return query.data(using: .utf8)
    }
    
    func GenerateSection(parentViewController:ParentViewController) -> Section {
        let section = Section()
        /*section <<< LabelRow() {
            $0.title = title
        }*/
        if let announce = self.announce, announce.count > 0 {
            section <<< LabelRow(){
                $0.title = announce
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
            }
        }
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
                NiftyUtility.EasyDialogNoButton(viewController: parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchingMessage", comment: "検索中"), message: nil) { (dialog) in
                    print("query: \(url.absoluteString)")
                    NiftyUtility.httpRequest(url: url, postData: self.GenerateQueryData(), timeoutInterval: 10, isNeedHeadless: self.isNeedHeadless, mainDocumentURL: URL(string: self.mainDocumentURL), allowsCellularAccess: allowsCellularAccess, headlessClientKey: NovelSearchViewController.HeadlessHTTPClientKey, withWaitSecond: self.waitSecondInHeadless, successAction: { (data, encoding) in
                        guard let result = self.result else {
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false) {
                                    NiftyUtility.EasyDialogOneButton(viewController: parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailed_Title", comment: "検索失敗"), message: NSLocalizedString("NovelSearchViewController_SearchField_Message", comment: "検索に失敗しました。\n恐らくは検索に利用されたWebサイト様側の仕様変更(HTML内容の変更)が影響していると思われます。「Web取込」側で取込を行うか、「Web検索」タブ用のデータが更新されるのをお待ち下さい。"), buttonTitle: nil, buttonAction: nil)
                                }
                            }
                            return
                        }
                        DispatchQueue.global(qos: .utility).async {
                            result.ConvertHTMLToSearchResultDataArray(data: data, headerEncoding: encoding, baseURL: url) { (searchResultBlockArray, nextURL, element) in
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false) {
                                        let nextViewController = SearchResultViewController()
                                        nextViewController.resultBlockArray = searchResultBlockArray
                                        nextViewController.nextURL = nextURL
                                        nextViewController.searchResult = result
                                        nextViewController.siteName = self.title
                                        nextViewController.isNeedHeadless = self.isNeedHeadless
                                        nextViewController.waitSecondInHeadless = self.waitSecondInHeadless
                                        parentViewController.navigationController?.pushViewController(nextViewController, animated: true)
                                    }
                                }
                            }
                        }
                    }) { (err) in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false) {
                                DispatchQueue.main.async {
                                    NiftyUtility.EasyDialogOneButton(viewController: parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailedTitle", comment: "検索に失敗しました"), message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                            }
                        }
                    }
                }
            }
        })
        if let webSiteURL = self.webSiteURL {
            section <<< LabelRow() {
                $0.title = " "
                $0.cell.textLabel?.numberOfLines = 0
                $0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
            }.cellUpdate({ cell, row in
                cell.backgroundColor = .systemGroupedBackground
            })
            section <<< ButtonRow() {
                $0.title = NSLocalizedString("NovelSearchViewController_OpenWebSiteButtonText", comment: "Web取込タブで開く")
            }.onCellSelection({ (buttonCellOf, buttonRow) in
                BookShelfRATreeViewController.LoadWebPageOnWebImportTab(url: webSiteURL)
            })
        }
        return section
    }
}

class NovelSearchViewController: FormViewController,ParentViewController {
    var searchInfoArray:[WebSiteSection] = []
    var currentSelectedSite:WebSiteSection? = nil
    static var lastSearchInfoLoadDate:Date = Date(timeIntervalSince1970: 0)
    static let SearchInfoCacheFileName = "SearchInfoData.json"
    static let HeadlessHTTPClientKey = "NovelSearchViewControllerHeadlessHTTPClientKey"
    let searchInfoExpireTimeInterval:TimeInterval = 60*60*6 // 6時間
    static let CURRENT_ALLOW_DATA_VERSION = 1
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("NovelSearchViewController_Title", comment: "Web検索")
        self.form +++ Section()
        <<< LabelRow() {
            $0.title = NSLocalizedString("NovelSearchViewController_LoadingSearchInfoTitle", comment: "Web検索用の情報を読み込んでいます……")
            $0.cell.textLabel?.numberOfLines = 0
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        checkAndReloadSearchInfoIfNeeded()
        super.viewDidAppear(animated)
    }
    
    static func SearchInfoCacheClear() {
        lastSearchInfoLoadDate = Date(timeIntervalSince1970: 0)
        URLCache.shared.removeAllCachedResponses()
        NiftyUtility.FileCachedHttpGet_RemoveCacheFile(cacheFileName: SearchInfoCacheFileName)
    }
    
    func checkAndReloadSearchInfoIfNeeded() {
        if NovelSearchViewController.lastSearchInfoLoadDate < Date(timeIntervalSinceNow: -searchInfoExpireTimeInterval) {
            loadSearchInfo()
        }
    }
    
    func fetchSearchInfoJSON(url: URL, successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        NiftyUtility.FileCachedHttpGet(url: url, cacheFileName: NovelSearchViewController.SearchInfoCacheFileName, expireTimeinterval: searchInfoExpireTimeInterval, canRecoverOldFile: true, successAction: { (data) in
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
        if let url = URL(string: NSLocalizedString("https://limura.github.io/NovelSpeaker/data/WebSearchInfo-ja_JP.json", comment: "適切にURLを返すように Localizable.strings に設定しておく。言語とか地域とかOS側の言語とかアプリ側の言語とかもうわけわからんので NSLocalizedString() 側で設定された言語の設定ファイルを読み込む、というイメージにする。")) {
            urlQueue.append(url)
        }
        if let url = URL(string: "https://limura.github.io/NovelSpeaker/data/WebSearchInfo-ja_JP.json") {
            urlQueue.append(url)
        }
        var lastError:Error? = nil
        func fetchOne(queue:[URL], index:Int) {
            if queue.count <= index {
                failedAction?(lastError)
                return
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
        if NovelSpeakerUtility.isUseWebSearchTabDisabledSite { return result }
        return result.filter {
            guard $0.allowDataVersion >= NovelSearchViewController.CURRENT_ALLOW_DATA_VERSION else {return false}
            guard let isDisabled = $0.isDisabled else {return true}
            return isDisabled == false
        }
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
            NiftyUtility.headlessClientLoadAboutPage()
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
                RealmUtil.Write { (realm) in
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
