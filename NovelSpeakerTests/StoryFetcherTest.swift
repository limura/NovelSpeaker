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

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
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
            pageElement: "//*[@id='content']",
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
