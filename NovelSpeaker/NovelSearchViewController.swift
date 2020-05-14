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
import Fuzi

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
    let radioList:[String:String]
    var enableTarget:String? = nil
    init(displayText:String, queryName:String, radioList:[String:String]){
        self.displayText = displayText
        self.queryName = queryName
        self.radioList = radioList
    }
    static func GenerateQuery(value:[String:Any]) -> RadioQuery? {
        guard let type = value["queryType"] as? String, type == "radio", let displayText = value["displayText"] as? String, let queryName = value["queryName"] as? String, let radioArray = value["radio"] as? [String:Any] else { return nil }
        var radioList:[String:String] = [:]
        for (key,value) in radioArray {
            guard let value = value as? String else { continue }
            radioList[key] = value
        }
        return RadioQuery(displayText: displayText, queryName: queryName, radioList: radioList)
    }
    func CreateForm(parent:MultipleSelectorDoneEnabled) -> BaseRow? {
        return AlertRow<String>() {
            $0.title = displayText
            $0.selectorTitle = displayText
            $0.options = ([String](self.radioList.keys)).sorted()
            $0.value = nil
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

class SearchResultBlock {
    let title:String
    let url:URL

    init(title:String, url:URL){
        self.title = title
        self.url = url
    }
    
    func CreateForm(parent:UIViewController) -> ButtonRow {
        return ButtonRow() {
            $0.title = title
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection { (buttonCellOf, row) in
            DispatchQueue.main.async {
                NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: parent, url: self.url, cookieArray: [])
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
    
    func ConvertHTMLToSearchResultDataArray(data:Data, baseURL: URL) -> ([SearchResultBlock], URL?) {
        var result:[SearchResultBlock] = []
        guard let doc = try? HTMLDocument(data: data) else { return ([], nil) }
        for blockHTML in doc.xpath(self.blockXpath) {
            // TODO: 何かうまい方法があれば書き直す
            // 何故か blockHTML.xpath() をすると doc(文章全体) に対して xpath が適用されてしまうので、
            // 仕方がないので blockHTML.rawXML(これは文字列を再生成しているみたいなので負荷が気になる)を
            // XMLDocumentとして再度読み込んでそれを使う事にします。
            guard let block = try? HTMLDocument(string: blockHTML.rawXML) else { continue }
            let title:String
            if let titleXpath = self.titleXpath {
                title = NiftyUtilitySwift.FilterXpathWithConvertString(xmlDocument: block, xpath: titleXpath).trimmingCharacters(in: .whitespacesAndNewlines)
            }else{
                title = ""
            }
            print("ConvertHTMLToSearchResultDataArray phase 2, block checking: title: \(title), xpath: \(titleXpath ?? "nil")")
            guard let urlXpath = self.urlXpath, let url = NiftyUtilitySwift.FilterXpathWithExtructFirstHrefLink(xmlDocument: block, xpath: urlXpath, baseURL: baseURL) else { continue }
            print("ConvertHTMLToSearchResultDataArray phase 2, block checking: url: \(url.absoluteURL)")
            let resultBlock = SearchResultBlock(title: title, url: url)
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
            $0.title = NSLocalizedString("NovelSearchViewController_LoadNextPage", comment: "さらに検索する")
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
            row.title = NSLocalizedString("NovelSearchViewController_LoadingTitle", comment: "loading...")
            NiftyUtilitySwift.httpGet(url: nextURL, successAction: { (data) in
                DispatchQueue.main.async {
                    self.removeLoadingRow()
                    guard let searchResult = self.searchResult else { return }
                    let (resultBlockArray, nextURL) = searchResult.ConvertHTMLToSearchResultDataArray(data: data, baseURL: nextURL)
                    self.resultBlockArray.append(contentsOf: resultBlockArray)
                    self.nextURL = nextURL
                    for novel in resultBlockArray {
                        //print("form create about: \(novel.title)")
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
            //print("form create about: \(novel.title)")
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
    var httpMethod:String = "GET"
    var url:String = ""
    var values:[SearchQuery] = []
    var result:SearchResult? = nil
    var parentViewController:ParentViewController
    
    init(parent:ParentViewController) {
        parentViewController = parent
    }
    
    func SetSiteInfoJSON(jsonDecodable: [String:AnyDecodable]) -> Bool {
        if let title = jsonDecodable["title"]?.value as? String {
            self.title = title
        }
        if let httpMethod = jsonDecodable["httpMethod"]?.value as? String, httpMethod == "GET" || httpMethod == "POST" {
            self.httpMethod = httpMethod
        }
        if let url = jsonDecodable["url"]?.value as? String {
            self.url = url
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
                default:
                    // nothing to do!
                    break
                }
            }
            self.values = values
        }
        if let result = jsonDecodable["result"]?.value as? [String:Any] {
            self.result = SearchResult.GenerateObject(value: result)
        }
        return true
    }
    
    func GenerateQueryURL() -> URL? {
        if httpMethod == "POST" {
            return URL(string: self.url)
        }
        let query = values.map({$0.CreateQuery()}).joined(separator: "&")
        guard let queryEscaped = query.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) else { return nil }
        guard let url = URL(string: self.url + queryEscaped) else { return nil }
        return url
    }
    
    func GenerateQueryData() -> Data? {
        if httpMethod != "POST" {
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
                NiftyUtilitySwift.EasyDialogNoButton(viewController: self.parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchingMessage", comment: "検索中"), message: nil) { (dialog) in
                    NiftyUtilitySwift.httpRequest(url: url, isPostRequest: self.httpMethod == "POST", postData: self.GenerateQueryData(), timeoutInterval: 10, successAction: { (data) in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false) {
                                guard let result = self.result else {
                                    DispatchQueue.main.async {
                                        NiftyUtilitySwift.EasyDialogOneButton(viewController: self.parentViewController, title: NSLocalizedString("NovelSearchViewController_SearchFailed_Title", comment: "検索失敗"), message: NSLocalizedString("NovelSearchViewController_SearchField_Message", comment: "検索に失敗しました。\n恐らくは検索に利用されたWebサイト様側の仕様変更(HTML内容の変更)が影響していると思われます。「Web取込」側で取込を行うか、「Web検索」タブ用のデータが更新されるのをお待ち下さい。"), buttonTitle: nil, buttonAction: nil)
                                    }
                                    return
                                }
                                let (searchResultBlockArray, nextURL) = result.ConvertHTMLToSearchResultDataArray(data: data, baseURL: url)
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
    let SearchInfoArrayJSON = """
[
    {
        "title": "小説家になろう",
        "HTTPMethod": "GET",
        "url": "https://yomou.syosetu.com/search.php?",
        "values": [
            {"queryType": "text", "displayText": "検索ワード", "queryName": "word"},
            {"queryType": "text", "displayText": "除外ワード", "queryName": "notword"},
            {"queryType": "multiSelect", "displayText": "ジャンル", "queryName": "genre", "separator": "-",
                "multiSelect": {
                    "異世界": "101",
                    "現実世界": "102",
                    "ハイファンタジー": "201",
                    "ローファンタジー": "202",
                    "純文学": "301",
                    "ヒューマンドラマ": "302",
                    "歴史": "303",
                    "推理": "304",
                    "ホラー": "305",
                    "アクション": "306",
                    "コメディー": "307",
                    "VRゲーム": "401",
                    "宇宙": "402",
                    "空想科学": "403",
                    "パニック": "404",
                    "童話": "9901",
                    "詩": "9902",
                    "エッセイ": "9903",
                    "リプレイ": "9904",
                    "その他": "9999",
                    "ノンジャンル": "9801"
                }
            },
            {"queryType": "radio", "displayText": "検索結果の並び替え", "queryName": "order",
                "radio": {
                    "新着更新順": "new",
                    "ブックマーク数の多い順": "favnovelcnt",
                    "レビュー数の多い順": "reviewcnt",
                    "総合ポイントの高い順": "hyoka",
                    "総合ポイントの低い順": "hyokaasc",
                    "日間ポイントの高い順": "dailypoint",
                    "週間ポイントの高い順": "weeklypoint",
                    "月間ポイントの高い順": "monthlypoint",
                    "四半期ポイントの高い順": "quarterpoint",
                    "年間ポイントの高い順": "yearlypoint",
                    "感想の多い順": "impressioncnt",
                    "評価者数の多い順": "hyokacnt",
                    "評価者数の少ない順": "hyokacntasc",
                    "週間ユニークユーザの多い順": "weekly",
                    "小説本文の文字数が多い順": "lengthdesc",
                    "小説本文の文字数が少ない順": "lengthasc",
                    "新着投稿順": "ncodedesc",
                    "更新が古い順": "old"
                }
            }
        ],
        "result": {
            "block": "//div[@class='searchkekka_box']",
            "nextLink": "//div[@class='pager']/a[@class='nextlink']/@href",
            "title": "//div[@class='novel_h']/a",
            "url": "//div[@class='novel_h']/a/@href",
        }
    },
    {
        "title": "カクヨム",
        "HTTPMethod": "GET",
        "url": "https://kakuyomu.jp/search?",
        "values": [
            {"queryType": "text", "displayText": "次のキーワードを含む", "queryName": "q"},
            {"queryType": "text", "displayText": "次のキーワードを含まない", "queryName": "ex_q"},
            {"queryType": "radio", "displayText": "ジャンル", "queryName": "genre_name",
                "radio": {
                    "異世界ファンタジー": "fantasy",
                    "現代ファンタジー": "action",
                    "SF": "sf",
                    "恋愛": "love_story",
                    "ラブコメ": "romance",
                    "現代ドラマ": "drama",
                    "ホラー": "horror",
                    "ミステリー": "mystery",
                    "エッセイ・ノンフィクション": "nonfiction",
                    "歴史・時代・伝奇": "history",
                    "創作論・評論": "criticism",
                    "詩・童話・その他": "others"
                }
            },
            {"queryType": "radio", "displayText": "検索結果の並び替え", "queryName": "order",
                "radio": {
                    "更新順": "last_episode_published_at",
                    "新作順": "published_at",
                    "人気順": "popular"
                }
            }
        ],
        "result": {
            "block": "//section[@id='searchResult-works']/div[contains(@class,'widget-work')]",
            "nextLink": "//p[@class='widget-pagerNext']/a/@href",
            "title": "//h3[@class='widget-workCard-title']/a[contains(@class,'widget-workCard-titleLabel')]",
            "url": "//h3[@class='widget-workCard-title']/a[contains(@class,'widget-workCard-titleLabel')]/@href",
        }
    },
    {
        "title": "黑岩阅读",
        "HTTPMethod": "POST",
        "url": "https://w.heiyan.com/search/",
        "values": [
            {"queryType": "text", "displayText": "书名 作者名 关键字", "queryName": "queryString"}
        ],
        "result": {
            "block": "//ul[@id='list-container']",
            "title": "//h5/a[@class='name']",
            "url": "//h5/a[@class='name']/@href",
        }
    },
    {
        "title": "ナゾロジー",
        "HTTPMethod": "GET",
        "url": "https://nazology.net/?",
        "values": [
            {"queryType": "text", "displayText": "検索文字列", "queryName": "s"}
        ],
        "result": {
            "block": "//div[@id='main']/div[@class='container']/article[@class='post-article']",
            "nextLink": "//div[@class='pageination']//li[@class='paging-last']/a/@href",
            "title": "//a[contains(@href,'/archives/')]//h2",
            "url": "//a[contains(@href,'/archives/')]/@href"
        }
    },
    {
        "title": "ポケモン小説スクウェア",
        "HTTPMethod": "GET",
        "url": "https://pokemon.sorakaze.info/novels?",
        "values": [
            {"queryType": "hidden", "queryName": "type", "value": "0"},
            {"queryType": "hidden", "queryName": "state", "value": "0"},
            {"queryType": "hidden", "queryName": "grotesque", "value": "0"},
            {"queryType": "hidden", "queryName": "event", "value": "0"},
            {"queryType": "radio", "displayText": "カテゴリ", "queryName": "category",
                "radio": {
                    "なし": "1",
                    "冒険": "2",
                    "文学": "3",
                    "生態": "4",
                    "ポケダン": "5",
                    "コメディ": "7",
                    "レンジャー": "8",
                    "ポケスペ": "9",
                    "学園": "10",
                    "推理・ホラー": "11",
                    "アニポケ": "12",
                    "ファンタジー": "13",
                    "SF": "14"
                }
            }
        ],
        "result": {
            "block": "//section/div[@class='novel-list']/div[@class='item']",
            "nextLink": "//ul[@id='paginate']/li[@class='next']/a[@rel='next']",
            "title": "//section/div[@class='novel-list']/div[@class='item']//div[@class='subject']/a",
            "url": "//section/div[@class='novel-list']/div[@class='item']//div[@class='subject']/a/@href"
        }
    }
]
"""
    var searchInfoArray:[WebSiteSection] = []
    var currentSelectedSite:WebSiteSection? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("NovelSearchViewController_Title", comment: "小説を検索")
        loadSearchInfo()
    }
    
    func fetchSearchInfoJSON(urlString: String, successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        guard let url = URL(string: urlString) else {
            failedAction?(nil)
            return
        }
        NiftyUtilitySwift.FileCachedHttpGet(url: url, cacheFileName: "SearchInfoData.json", expireTimeinterval: 60*60*1, successAction: { (data) in
            successAction?(data)
        }) { (err) in
            failedAction?(err)
        }
    }
    
    func fetchSearchInfo(successAction: ((Data) -> Void)?, failedAction:((Error?) -> Void)? ) {
        let fallbackUrlString = "https://limuraproducts.ddns.net/NovelSpeaker/SearchInfoData/ja-JP.json"
        let urlString = NSLocalizedString("https://limuraproducts.ddns.net/NovelSpeaker/SearchInfoData/ja-JP.json", comment: "適切にURLを返すように Localizable.strings に設定しておく。言語とか地域とかOS側の言語とかアプリ側の言語とかもうわけわからんので NSLocalizedString() 側で設定された言語の設定ファイルを読み込む、というイメージにする。")
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
        searchInfoArray = self.extractSearchInfoArray(jsonData: SearchInfoArrayJSON.data(using: .utf8) ?? Data())
        currentSelectedSite = searchInfoArray.first
        reloadCells()

        /*
        fetchSearchInfo(successAction: { (searchInfoArrayJsonData) in
            self.searchInfoArray = self.extractSearchInfoArray(jsonData: searchInfoArrayJsonData)
            self.currentSelectedSite = self.searchInfoArray.first
            self.reloadCells()
        }) { (err) in
            DispatchQueue.main.async {
                self.form.removeAll()
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
         */
    }
    
    func reloadCells() {
        DispatchQueue.main.async {
            self.form.removeAll()
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
