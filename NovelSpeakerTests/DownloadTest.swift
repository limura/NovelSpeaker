//
//  File.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2021/01/16.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker
#if !os(watchOS)
@testable import Erik
#endif

class DownloadTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let semaphore = DispatchSemaphore(value: 0)
        StoryHtmlDecoder.shared.WaitLoadSiteInfoReady {
            semaphore.signal()
        }
        semaphore.wait()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func StoryStateChecker(state:StoryState, url:URL? = nil, cookieString:String? = nil, content:String? = nil, contentFirstLine:String? = nil, nextUrl:URL? = nil, firstPageLink:URL? = nil, title:String? = nil, author:String? = nil, subtitle:String? = nil, tagArray:[String]? = nil, isNeedHeadless:Bool? = nil, isCanFetchNextImmediately:Bool? = nil, waitSecondInHeadless:Double? = nil, checkDocument:Bool = false, checkNextButton:Bool = false, checkFirstPageButton:Bool = false) {
        if let url = url {
            XCTAssertEqual(state.url.absoluteString, url.absoluteString, "urlが違う\n\(state.description)")
        }
        if let cookieString = cookieString {
            XCTAssertNotNil(state.cookieString, "cookieString が nil")
            if let stateCookieString = state.cookieString {
                XCTAssertEqual(stateCookieString, cookieString, "cookieが違う\n\(state.description)")
            }
        }
        if let content = content {
            XCTAssertNotNil(state.content, "content が nil")
            if let stateContent = state.content {
                XCTAssertEqual(stateContent, content, "contentが違う\n\(state.description)")
            }
        }
        if let contentFirstLine = contentFirstLine {
            XCTAssertNotNil(state.content, "content が nil")
            if let stateContentFirstLine = state.content?.split(separator: "\n").first {
                XCTAssertEqual(String(stateContentFirstLine), contentFirstLine, "contentの最初の行が違う\n\(state.description)")
            }
        }
        if let nextUrl = nextUrl {
            XCTAssertNotNil(state.nextUrl, "nextUrl が nil")
            if let stateNextUrl = state.nextUrl {
                XCTAssertEqual(stateNextUrl.absoluteString, nextUrl.absoluteString, "nextUrlが違う\n\(state.description)")
            }
        }
        if let firstPageLink = firstPageLink {
            XCTAssertNotNil(state.firstPageLink, "firstPageLink が nil")
            if let stateFirstPageLink = state.firstPageLink {
                XCTAssertEqual(stateFirstPageLink, firstPageLink, "firstPageLinkが違う\n\(state.description)")
            }
        }
        if let title = title {
            XCTAssertNotNil(state.title, "title が nil")
            if let stateTitle = state.title {
                XCTAssertEqual(stateTitle, title, "title が違う\n\(state.description)")
            }
        }
        if let author = author {
            XCTAssertNotNil(state.author, "author が nil")
            if let stateAuthor = state.author {
                XCTAssertEqual(stateAuthor, author, "author が違う\n\(state.description)")
            }
        }
        if let subtitle = subtitle {
            XCTAssertNotNil(state.subtitle, "subtitle が nil")
            if let stateSubtitle = state.subtitle {
                XCTAssertEqual(stateSubtitle, subtitle, "subtitle が違う\n\(state.description)")
            }
        }
        if let tagArray = tagArray {
            XCTAssertEqual(state.tagArray, tagArray, "tagArray が違う")
        }
        if let isNeedHeadless = isNeedHeadless {
            XCTAssertEqual(state.isNeedHeadless, isNeedHeadless, "isNeedHeadless が違う\n\(state.description)")
        }
        if let isCanFetchNextImmediately = isCanFetchNextImmediately {
            XCTAssertEqual(state.isCanFetchNextImmediately, isCanFetchNextImmediately, "isCanFetchNextImmediately が違う\n\(state.description)")
        }
        if let waitSecondInHeadless = waitSecondInHeadless {
            XCTAssertNotNil(state.waitSecondInHeadless, "waitSecondInHeadless が nil")
            if let stateWaitSecondInHeadless = state.waitSecondInHeadless {
                XCTAssertEqual(stateWaitSecondInHeadless, waitSecondInHeadless, "waitSecondInHeadless が違う\n\(state.description)")
            }
        }
        #if !os(watchOS)
        if checkDocument {
            XCTAssertNotNil(state.document, "document が nil\n\(state.description)")
        }
        if checkNextButton {
            XCTAssertNotNil(state.nextButton, "nextButton が nil\n\(state.description)")
        }
        if checkFirstPageButton  {
            XCTAssertNotNil(state.firstPageButton, "firstPageButton が nil\n\(state.description)")
        }
        #endif
    }
    
    
    /*
     pixiv 小説は以下のような next link target 構成になっている。
     
     firstPageLink: シリーズのリストページにおける最初のシリーズへのリンク
       https://www.pixiv.net/novel/series/1146446
     nextButton: 一つのシリーズの一つのページにおける、次のページへめくるボタン(「>」みたいな奴)
       https://www.pixiv.net/novel/show.php?id=11377902#3
     firstPageButton: 一つのシリーズの最初のページへのボタン (表示させかたがわからん。一つのシリーズのページを開いた時に時々出てくる本文がなくて「読む」というボタンだけがある奴)
       https://www.pixiv.net/novel/show.php?id=11377902
     nextLink: 一つのシリーズの一つのページにおける、次のシリーズへのリンク (「#2 強くてニューゲームは都市伝説。3度目の保護者はとても優しい方でした。」みたいなリンク)
       https://www.pixiv.net/novel/show.php?id=11377902#11
     */
    /// pixiv 小説の firstPageLink を確認するには、
    /// シリーズ物のリストを表示しているページを開く必要があります。
    /// FetchNext() は小説の最初のページを拾い出してそこの内容を取り出すため、
    /// FirstPageLink を取り出した後に「最初のページの内容, nextLink, nextButton」についても取り出せているはずなので、
    /// それもついでに確認してしまいます。
    func testPixiv_FirstPageLink() throws {
        let targetUrlString = "https://www.pixiv.net/novel/series/1146446?p=1"
        //let targetUrlString = "https://limura.github.io/NovelSpeaker/topics/jp/00001.html"
        guard let targetUrl = URL(string: targetUrlString) else {
            XCTFail("targetUrl == nil")
            return
        }
        let expectation = self.expectation(description: "FirstPageButton expectation")
        let fetcher = StoryFetcher()
        let state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfo(url: targetUrl, cookieString: nil)
        fetcher.FetchNext(currentState: state) { (state) in
            print(state.description)
            // firstPageButton が反応していれば、最初のページが表示され、その値が取れているはずです。
            self.StoryStateChecker(state: state,
               url: URL(string: "https://www.pixiv.net/novel/show.php?id=11377902"),
               contentFirstLine: "注意書き",
               nextUrl: URL(string: "https://www.pixiv.net/novel/show.php?id=11383477"),
               title: "強くてニューゲームは都市伝説。3度目の人生は毒入り食事から始まりました。",
               author: "キノト",
               checkNextButton: true)
            expectation.fulfill()
        } failedAction: { (url, str) in
            XCTFail("FetchNext error: \(url.absoluteString), \(str)")
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 10.0)
    }
    /// pixiv 小説の nextLink は「次のシリーズ」であり、一つ前のシリーズへのリンクを取り出してしまう可能性があります。
    /// 正常に取り出せる物は testPixiv_FirstPageLink() で確認しているので、
    /// こちらはシリーズの最後の物を取り出そうとした時に、シリーズ前の物を取り出さない事を確認します。
    func testPixiv_nextLink_for_LastSeries() throws {
        let targetUrlString = "https://www.pixiv.net/novel/show.php?id=14182597#6"
        //let targetUrlString = "https://limura.github.io/NovelSpeaker/topics/jp/00001.html"
        guard let targetUrl = URL(string: targetUrlString) else {
            XCTFail("targetUrl == nil")
            return
        }
        let expectation = self.expectation(description: "FirstPageButton expectation")
        let fetcher = StoryFetcher()
        let state = StoryFetcher.CreateFirstStoryStateWithoutCheckLoadSiteInfo(url: targetUrl, cookieString: nil)
        fetcher.FetchNext(currentState: state) { (state) in
            print(state.description)
            // firstPageButton が反応していれば、最初のページが表示され、その値が取れているはずです。
            self.StoryStateChecker(state: state,
               url: URL(string: "https://www.pixiv.net/novel/show.php?id=14182597#6"),
               contentFirstLine: "やっと書けました！！！！！",
               nextUrl: nil, // nil であるかどうかを判定できないので別途判定します
               title: "強くてニューゲームは都市伝説。ラッフェルを育てよう",
               author: "キノト",
               checkNextButton: false // nextButton が nil であるかどうかも判定できないので別途判定します
            )
            XCTAssertNil(state.nextUrl, "nextUrl が nil ではありませんでした。\(state.nextUrl?.absoluteString ?? "nil")")
            XCTAssertNil(state.nextButton, "nextButton が nil ではありませんでした。")
            expectation.fulfill()
        } failedAction: { (url, str) in
            XCTFail("FetchNext error: \(url.absoluteString), \(str)")
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 10.0)
    }
}

