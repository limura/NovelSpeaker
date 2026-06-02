//
//  StoryFetcherTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2020/07/11.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker
@testable import Kanna
#if !os(watchOS)
@testable import Erik
#endif

class StoryFetcherTest: XCTestCase {
    private let novelImportSettingTestURL = "https://example.com/siteinfo.csv"
    private let novelImportSettingTestSiteNumber = "999991"
    private var novelImportSettingTestSiteID:String {
        return "\(novelImportSettingTestSiteNumber):\(novelImportSettingTestURL)"
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        UserDefaults.standard.set(false, forKey: RealmUtil.UseCloudRealmKey)
        AppInformationLogger.ClearLogs()
        RealmUtil.Write { realm in
            for setting in realm.objects(RealmNovelImportSetting.self).filter("siteInfoId = %@", novelImportSettingTestSiteID) {
                setting.delete(realm: realm)
            }
        }
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        StoryHtmlDecoder.shared.ClearSiteInfo()
        AppInformationLogger.ClearLogs()
        RealmUtil.Write { realm in
            for setting in realm.objects(RealmNovelImportSetting.self).filter("siteInfoId = %@", novelImportSettingTestSiteID) {
                setting.delete(realm: realm)
            }
        }
    }

    private func createCSVSiteInfo(newPageElement:String, name:String = "テストサイト") throws -> StorySiteInfo {
        func csvEscape(_ value:String) -> String {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let headers = [
            "id",
            "name",
            "newPageElement",
            "url",
            "title",
            "subtitle",
            "firstPageLink",
            "nextLink",
            "tag",
            "author",
            "isNeedHeadless",
            "injectStyle",
            "nextButton",
            "firstPageButton",
            "waitSecondInHeadless",
            "forceClickButton",
            "resourceUrl",
            "overrideUserAgent",
            "forceErrorMessageAndElement",
            "scrollTo",
            "isNeedWhitespaceSplitForTag"
        ]
        let values = [
            novelImportSettingTestSiteNumber,
            name,
            newPageElement,
            "^https://example.com/novel/.*$",
            "//*[@id='title']",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            "0",
            "",
            "",
            "",
            "",
            "",
            ""
        ]
        let csv = headers.joined(separator: ",") + "\n" + values.map(csvEscape).joined(separator: ",")
        let siteInfoArray = try XCTUnwrap(StoryHtmlDecoder.DecodeCSVSiteInfoData(data: Data(csv.utf8), urlString: novelImportSettingTestURL))
        return try XCTUnwrap(siteInfoArray.first)
    }

    private func createSiteImportSetting(targets:[String], seenTargets:[String]) {
        RealmUtil.Write { realm in
            if let oldSetting = RealmNovelImportSetting.GetNovelImportSetting(realm: realm, scopeType: .site, siteInfoId: novelImportSettingTestSiteID, novelID: nil) {
                oldSetting.delete(realm: realm)
            }
            let setting = RealmNovelImportSetting.Create(scopeType: .site, siteInfoId: novelImportSettingTestSiteID, novelID: nil)
            setting.targets.append(objectsIn: targets)
            setting.seenTargets.append(objectsIn: seenTargets)
            realm.add(setting, update: .modified)
        }
    }

    func testNovelImportSettingSiteInfoReloadAddsNewPageElementToTargetsAndLogs() throws {
        createSiteImportSetting(targets: ["body"], seenTargets: ["body"])
        let siteInfo = try createCSVSiteInfo(newPageElement: """
        body:本文/Body=//*[@id='body']
        afterword:後書き/Afterword=//*[@id='afterword']
        """)
        StoryHtmlDecoder.shared.siteInfoArrayArray = [[siteInfo]]

        StoryHtmlDecoder.shared.checkNovelImportSettingChangesForLoadedSiteInfo()

        try RealmUtil.RealmBlock { realm in
            let setting = try XCTUnwrap(RealmNovelImportSetting.GetNovelImportSetting(realm: realm, scopeType: .site, siteInfoId: novelImportSettingTestSiteID, novelID: nil))
            XCTAssertEqual(Set(setting.targets), ["body", "afterword"])
            XCTAssertEqual(Set(setting.seenTargets), ["body", "afterword"])
        }
        let logs = AppInformationLogger.LoadLogObjectArray(isIncludeDebugLog: false)
        XCTAssertTrue(logs.contains { log in
            log.message == NSLocalizedString("StoryFetcher_NovelImportSettingNewElements_Message", comment: "") &&
            log.appendix[NSLocalizedString("StoryFetcher_NovelImportSettingLog_AddedElements", comment: "")]?.description.contains("後書き") == true
        })
    }

    func testResolveNovelImportSettingUsesAllCurrentElementsWhenSelectionBecomesEmpty() throws {
        createSiteImportSetting(targets: ["body"], seenTargets: ["body", "foreword", "afterword"])
        let siteInfo = try createCSVSiteInfo(newPageElement: """
        foreword:前書き/Foreword=//*[@id='foreword']
        afterword:後書き/Afterword=//*[@id='afterword']
        """)

        let resolvedTargets = StoryHtmlDecoder.shared.resolveNovelImportEnableSettings(siteInfo: siteInfo, novelID: nil)

        // 取り込み対象は全項目へフォールバックする(動作はそのまま)
        XCTAssertEqual(Set(try XCTUnwrap(resolvedTargets)), ["foreword", "afterword"])
        // resolve はページ取得ごとに呼ばれるホットパスなので、ユーザ通知は出さない
        let logsAfterResolve = AppInformationLogger.LoadLogObjectArray(isIncludeDebugLog: false)
        XCTAssertFalse(logsAfterResolve.contains { log in
            log.message == NSLocalizedString("StoryFetcher_NovelImportSettingEmptySelection_Message", comment: "")
        })

        // emptySelection のユーザ通知は SiteInfo 読み直し時に1回だけ出る
        StoryHtmlDecoder.shared.siteInfoArrayArray = [[siteInfo]]
        StoryHtmlDecoder.shared.checkNovelImportSettingChangesForLoadedSiteInfo()
        let logsAfterCheck = AppInformationLogger.LoadLogObjectArray(isIncludeDebugLog: false)
        XCTAssertTrue(logsAfterCheck.contains { log in
            log.message == NSLocalizedString("StoryFetcher_NovelImportSettingEmptySelection_Message", comment: "")
        })
    }

    func testEncoding() throws {
        let str = "<A href=\"001.htm\">１話</A>"
        let sjis = str.data(using: .shiftJIS)
        let utf8 = str.data(using: .utf8)
        func hexdump(data:Data?){
            guard let data = data else {
                print("data is nil")
                return
            }
            var index:Int = 0
            while index < data.count {
                if index % 8 == 0 && index != 0 { print(" ", separator: "", terminator: "") }
                if index % 16 == 0 && index != 0 { print("") }
                print(String(format: "%02x", data[index]), separator: "", terminator: "")
                index += 1
            }
            print("")
        }
        print("sjis:")
        hexdump(data: sjis)
        print("utf8:")
        hexdump(data: utf8)
    }

    #if false
    func testFuzi() throws {
        guard let path = Bundle.main.path(forResource: "hoge", ofType: "html") else { return }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return }
        guard let htmlString = String(data: data, encoding: .shiftJIS) else { return }
        let doc = try HTMLDocument(string: htmlString, encoding: .shiftJIS)
        let string = NiftyUtility.FilterXpathWithConvertString(xmlDocument: doc, xpath: "//body", injectStyle: nil).trimmingCharacters(in: .whitespacesAndNewlines)
        print(string)
    }
    #else
    func testKanna() throws {
        guard let path = Bundle.main.path(forResource: "hoge", ofType: "html") else { return }
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return }
        //guard let htmlString = String(data: data, encoding: .shiftJIS) else { return }
        guard let doc = try? HTML(html: data, url: nil, encoding: .shiftJIS) else { return }
        var result:String = ""
        for node in doc.xpath("//body") {
            if let innerHTML = node.innerHTML {
                result += innerHTML
            }
        }
        print(result)
    }
    #endif
    
    #if !os(watchOS)
    private func createTestDocument(html:String) throws -> Document {
        let rawDocument = try XCTUnwrap(HTML(html: html, encoding: .utf8))
        return Document(rawValue: rawDocument)
    }
    
    private func createTestSiteInfo(nextButton:String? = nil) -> StorySiteInfo {
        return StorySiteInfo(
            id: UUID().uuidString,
            name: "test",
            newPageElement: "//*[@id='content']",
            url: "^https://example.com/.*$",
            title: "//*[@id='title']",
            subtitle: nil,
            firstPageLink: nil,
            nextLink: nil,
            tag: nil,
            author: "//*[@id='author']",
            isNeedHeadless: nil,
            injectStyle: nil,
            nextButton: nextButton,
            firstPageButton: nil,
            waitSecondInHeadless: nil,
            forceClickButton: nil,
            resourceUrl: nil,
            overrideUserAgent: nil,
            forceErrorMessageAndElement: nil,
            scrollTo: nil,
            isNeedWhitespaceSplitForTag: nil
        )
    }
    
    func testCreateNextStateDropsTransientDOMReferences() throws {
        let document = try createTestDocument(html: "<html><body><div id='content'>本文</div><a class='next'>次へ</a></body></html>")
        let nextButton = try XCTUnwrap(document.querySelectorAll(".next").first)
        let currentState = StoryState(
            url: try XCTUnwrap(URL(string: "https://example.com/chapter1")),
            cookieString: "a=b",
            content: "本文",
            nextUrl: URL(string: "https://example.com/chapter2"),
            firstPageLink: nil,
            title: "title",
            author: "author",
            subtitle: nil,
            tagArray: [],
            siteInfoArray: [createTestSiteInfo(nextButton: ".next")],
            isNeedHeadless: true,
            isCanFetchNextImmediately: false,
            waitSecondInHeadless: nil,
            previousContent: nil,
            document: document,
            nextButton: nextButton,
            firstPageButton: nil,
            forceClickButton: nil,
            forceErrorMessage: nil
        )
        let nextState = currentState.CreateNextState()
        
        XCTAssertNil(nextState.document)
        XCTAssertNil(nextState.nextButton)
        XCTAssertNil(nextState.firstPageButton)
        XCTAssertNil(nextState.forceClickButton)
        XCTAssertEqual(nextState.previousContent, "本文")
        XCTAssertEqual(nextState.nextUrl?.absoluteString, "https://example.com/chapter2")
    }
    
    func testDecodeDocumentDropsDOMWhenButtonsAreNotNeeded() throws {
        let html = """
        <html><body><h1 id="title">題名</h1><div id="author">著者</div><div id="content">本文</div></body></html>
        """
        let document = try createTestDocument(html: html)
        let fetcher = StoryFetcher()
        let currentState = StoryState(
            url: try XCTUnwrap(URL(string: "https://example.com/chapter1")),
            cookieString: nil,
            content: nil,
            nextUrl: nil,
            firstPageLink: nil,
            title: nil,
            author: nil,
            subtitle: nil,
            tagArray: [],
            siteInfoArray: [createTestSiteInfo()],
            isNeedHeadless: true,
            isCanFetchNextImmediately: false,
            waitSecondInHeadless: nil,
            previousContent: nil,
            document: document,
            nextButton: nil,
            firstPageButton: nil,
            forceClickButton: nil,
            forceErrorMessage: nil
        )
        var resultState:StoryState?
        
        fetcher.DecodeDocument(currentState: currentState, html: html, encoding: .utf8) { state in
            resultState = state
        } failedAction: { _, error in
            XCTFail("DecodeDocument failed: \(error)")
        }
        
        let decodedState = try XCTUnwrap(resultState)
        XCTAssertEqual(decodedState.content, "本文")
        XCTAssertNil(decodedState.document)
        XCTAssertNil(decodedState.nextButton)
        XCTAssertNil(decodedState.firstPageButton)
    }
    
    func testDecodeDocumentRetainsDOMWhenNextButtonExists() throws {
        let html = """
        <html><body><h1 id="title">題名</h1><div id="author">著者</div><div id="content">本文</div><a class="next">次へ</a></body></html>
        """
        let document = try createTestDocument(html: html)
        let fetcher = StoryFetcher()
        let currentState = StoryState(
            url: try XCTUnwrap(URL(string: "https://example.com/chapter1")),
            cookieString: nil,
            content: nil,
            nextUrl: nil,
            firstPageLink: nil,
            title: nil,
            author: nil,
            subtitle: nil,
            tagArray: [],
            siteInfoArray: [createTestSiteInfo(nextButton: ".next")],
            isNeedHeadless: true,
            isCanFetchNextImmediately: false,
            waitSecondInHeadless: nil,
            previousContent: nil,
            document: document,
            nextButton: nil,
            firstPageButton: nil,
            forceClickButton: nil,
            forceErrorMessage: nil
        )
        var resultState:StoryState?
        
        fetcher.DecodeDocument(currentState: currentState, html: html, encoding: .utf8) { state in
            resultState = state
        } failedAction: { _, error in
            XCTFail("DecodeDocument failed: \(error)")
        }
        
        let decodedState = try XCTUnwrap(resultState)
        XCTAssertEqual(decodedState.content, "本文")
        XCTAssertNotNil(decodedState.document)
        XCTAssertNotNil(decodedState.nextButton)
    }
    
    func testNormalizeEvaluateJavaScriptResultReturnsStringOnce() throws {
        let (result, error) = HeadlessHttpClient.NormalizeEvaluateJavaScriptResult(data: "done", error: nil, javaScript: "return 1")
        
        XCTAssertEqual(result, "done")
        XCTAssertNil(error)
    }
    
    func testNormalizeEvaluateJavaScriptResultConvertsErikError() throws {
        let convertedError = NSError(domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "converted"])
        let (result, error) = HeadlessHttpClient.NormalizeEvaluateJavaScriptResult(data: nil, error: ErikError.timeOutError(time: 1.0), javaScript: "return 1") { _ in
            convertedError
        }
        
        XCTAssertNil(result)
        XCTAssertEqual((error as NSError?)?.domain, "test")
        XCTAssertEqual((error as NSError?)?.code, 123)
    }
    
    func testNormalizeEvaluateJavaScriptResultReturnsGeneratedErrorForUnexpectedValue() throws {
        let (result, error) = HeadlessHttpClient.NormalizeEvaluateJavaScriptResult(data: 1, error: nil, javaScript: "return 1")
        
        XCTAssertNil(result)
        XCTAssertEqual(error?.localizedDescription, "execute JavaScript(\"return 1\") error.")
    }
    #endif
    
    func disabled_testMultiErik() throws {
        let erik1 = HeadlessHttpClient()
        let erik2 = HeadlessHttpClient()
        let url1 = URL(string: "https://www.pixiv.net/")
        let url2 = URL(string: "https://www.pixiv.net/")
        let lockObject = NSObject()
        
        var count:Int = 0
        let expect = expectation(description: "testMultiErik")
        func checkCount(){
            objc_sync_enter(lockObject)
            count += 1
            objc_sync_exit(lockObject)
            if count >= 2 {
                expect.fulfill()
            }
        }
        
        func successFunc(id:String, document:String?){
            print(id, "request success")
            if let innerHTML = document, let firstLine = innerHTML.components(separatedBy: "\n").first {
                print(id, firstLine)
            }
            checkCount()
        }
        
        erik1.HttpRequest(url: url1!, postData: nil, timeoutInterval: 30, cookieString: nil, mainDocumentURL: url1!, allowsCellularAccess: true, successResultHandler: { (document) in
            successFunc(id: "url1", document: document.innerHTML)
        }) { (err) in
            print("url1 request failed.", err.localizedDescription)
            checkCount()
        }
        erik2.HttpRequest(url: url2!, postData: nil, timeoutInterval: 30, cookieString: nil, mainDocumentURL: url2!, allowsCellularAccess: true, successResultHandler: { (document) in
            successFunc(id: "url2", document: document.innerHTML)
        }) { (err) in
            print("url2 request failed.", err.localizedDescription)
            checkCount()
        }

        waitForExpectations(timeout: 60) { (error) in
            if let error = error {
                XCTAssert(false, String(format: "error: %@", error.localizedDescription))
                return
            }
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
