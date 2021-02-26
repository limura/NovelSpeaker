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
    
    func testMultiErik() throws {
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
