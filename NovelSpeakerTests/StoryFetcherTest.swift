//
//  StoryFetcherTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2020/07/11.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker

class StoryFetcherTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFetch() throws {
        // JavaScriptが必要な奴
        //let urlString = "https://www.pixiv.net/novel/show.php?id=13217440#1"
        // JavaScriptが要らない奴
        //let urlString = "https://www.pixiv.net/novel/show.php?id=13124696#1"
        // ログインが必要な奴
        //let urlString = "https://www.pixiv.net/novel/show.php?id=6030734#7"
        // ログインが必要でタイトルページの奴(本文が無くてfirstPageButtonがある奴)
        let urlString = "https://www.pixiv.net/novel/show.php?id=6468828"
        // エブリスタ(stylesheet で white-space: pre-wrap にされてる奴
        //let urlString = "https://estar.jp/novels/25642960/viewer?page=2"
        let urlString2 = "https://ncode.syosetu.com/n4647gh/"
        func nowDateString() -> String {
            let formatter = DateFormatter()
            formatter.timeStyle = .full
            formatter.dateStyle = .full
            formatter.locale = Locale(identifier: "ja_JP")
            let now = Date()
            return formatter.string(from: now)
        }
        let siteInfoData = """
[
{
  "resource_url": "http://wedata.net/items/81627",
  "data": {
    "pageElement": "//div[contains(@class,'novel-pages')]|//div[@id='novel_text_noscript']|//section[@id='novel-text-container']",
    "injectStyle": "#novel-text-container{white-space:pre-wrap;}",
    "title": "//title",
    "memo": "nextLink が無いのは、全部が一つのHTMLに入っていてページ切り替えはJavaScriptでやってるだけっぽいので。",
    "url": "^https://(www|touch)\\\\.pixiv\\\\.net/novel/show\\\\.php",
    "tag": "//ul[contains(@class,'tags')]/li[contains(@class,'tag')]/a[contains(@class,'text')]|//a[contains(@class,'tag-value')]|//div[@class='novel-details-content']//div[contains(@class,'display-tags')]//a[contains(@href,'/tags/')]",
    "author": "//a[contains(@class,'user-name')]|//div[contains(@class,'top-card')]/a[contains(@href,'/users/') and @class='user-details-name']",
    "isNeedHeadless": "true",
    "nextButton": "nav.novel-pager-container span:not(.invisible):not(.current-page):last-child",
    "firstPageButton": ".segment-bottom .action-button-container button, .gtm-series-next-work-button-in-illust-detail,a.series-link.router-link-active:first-child",
    "nextLink": "//div[@class='user-works-nav']/div[@class='nav-buttons']/a[contains(@class,'nav-next') and contains(@class,'router-link-active') and contains(@href,'/novel/show.php?id=')]",
    "exampleUrl": "https://www.pixiv.net/novel/show.php?id=8919908#1"
  },
  "database_resource_url": "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1",
  "created_by": "limura",
  "name": "pixiv小説",
  "created_at": "2017-11-20T16:19:11+09:00",
  "updated_at": "2019-06-12T15:15:28+09:00"
},
{
    "data": {
        "pageElement": "//div",
        "url": "^https://www.example.com"
    }
},
{
  "resource_url": "http://wedata.net/items/82176",
  "data": {
    "pageElement": "//div[@class='body']/div[not(contains(@class,'marquee')) and not(contains(@class,'noComment'))]|//div[@class='body']/h1[@class='subject']",
    "title": "//title",
    "subtitle": "//header//div[@class='info']",
    "firstPageLink": "//div[contains(@class,'episodeList')]/div[contains(@class,'item')]/a",
    "nextLink": "//link[@rel='next']",
    "url": "^https://estar\\\\.jp/novels/",
    "tag": "//div[contains(@class,'tags')]/a",
    "exampleUrl": "https://estar.jp/novels/25330938/viewer?page=2",
    "injectStyle": "div.content{white-space:pre-wrap;}"
  },
  "database_resource_url": "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1",
  "created_by": "limura",
  "name": "エブリスタ",
  "created_at": "2019-06-03T01:34:44+09:00",
  "updated_at": "2020-07-15T01:00:22+09:00"
},
{
  "resource_url": "http://wedata.net/items/81619",
  "data": {
    "title": "//div[@class='contents1']/a[1]|//div[@id='novel_contents']//p[contains(@class,'novel_title')]",
    "pageElement": "//div[@id='novel_honbun']|//p[contains(@class,'novel_subtitle')]|//div[@id='novel_p']|//div[@id='novel_a']",
    "subtitle": "//p[contains(@class,'novel_subtitle')]",
    "firstPageLink": "//div[@class='index_box']/dl[1]//a|//a[text()='1部分目を読む']",
    "nextLink": "//div[@class='novel_bn'][1]/a[contains(., '次へ')]",
    "url": "^https?://ncode\\\\.syosetu\\\\.com/",
    "tag": "//th[text()='キーワード']/following-sibling::td",
    "exampleUrl": "https://ncode.syosetu.com/n2251cd/29/ https://ncode.syosetu.com/n2251cd/",
    "author": "//div[@class=\\"contents1\\"]/a[last()]",
    "isNeedHeadless": "true"
  },
  "database_resource_url": "http://wedata.net/databases/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84Web%E3%83%9A%E3%83%BC%E3%82%B8%E8%AA%AD%E3%81%BF%E8%BE%BC%E3%81%BF%E7%94%A8%E6%83%85%E5%A0%B1",
  "created_by": "limura",
  "name": "小説家になろう",
  "created_at": "2017-11-20T11:27:02+09:00",
  "updated_at": "2020-05-22T00:14:15+09:00"
}
]
""".data(using: .utf8)
        let cookieString = "__utma=235335808.1532005711.1593867794.1594570108.1594753557.12; __utmb=235335808.6.9.1594753572018; __utmc=235335808; __utmv=235335808.|2=login%20ever=yes=1^3=plan=normal=1^5=gender=male=1^6=user_id=623723=1^9=p_ab_id=3=1^10=p_ab_id_2=0=1^11=lang=ja=1^20=webp_available=no=1; __utmz=235335808.1594570108.11.2.utmcsr=accounts.pixiv.net|utmccn=(referral)|utmcmd=referral|utmcct=/login; __gads=ID=4b90396bdf3e0310-22d3f8f35dc20059:T=1593867914:RT=1594753562:S=ALNI_Mb4ePwqrc99QDDYNTSMWR5BM-wLmA; categorized_tags=6sZKldb07K~DN6RDM1CuJ~GicGiNfh63~OT-C6ubi9i~pvU1D1orJa; tags_sended=1; __utmt=1; PHPSESSID=623723_JwWg4Mr7gHcLpkaUKuhPz5WvzkFg4mwu; a_type=0; b_type=1; c_type=45; __adpon_uid=bfc774f8-a6ac-4169-bcc2-33115dda1bc2; privacy_policy_agreement=2; device_token=df624cdb7dd7ccd870470e7cb87d2711; first_visit_datetime_pc=2020-07-04+22%3A43%3A16; __cfduid=dc5aecfa7efebcbcc95809b25bc044c671592825082; first_visit_datetime=2020-06-22+20%3A24%3A42; p_ab_id=3; tag_view_ranking=GicGiNfh63~j2Cs25NHKk~_hSAdpN9rx~WcvcsFewRV~UEqwxade59~BtXd1-LPRH~U24MZboSrp~Nh6_S-Mi8B~wRWLit0493~wHu5OXnGd1~uusOs0ipBx~jhuUT0OJva~RTJMXD26Ak~t2ErccCFR9~gnTtYdDB_b~AdHuyJ9D0T~nQRrj5c6w_; p_ab_d_id=986394981; yuid_b=EBgYRSY; p_ab_id_2=0"
        guard let data = siteInfoData, let url = URL(string: urlString) else { return }
        guard let url2 = URL(string: urlString2) else { return }
        XCTAssert(StoryHtmlDecoder.shared.AddCustomSiteInfoFromData(data: data), "AddCustomSiteInfoFromData failed.")
        let storyFetcher2 = StoryFetcher()
        let storyFetcher1 = StoryFetcher()
        func oneTry(state:StoryState, tryCount:Int, storyFetcher:StoryFetcher) -> StoryState?{
            var story:StoryState? = nil
            let expect = expectation(description: String(format: "StoryFetcher.Fetch count: %d", tryCount))
            storyFetcher.FetchNext(currentState: state.CreateNextState(), successAction: { (resultStory) in
                story = resultStory
                expect.fulfill()
            }, failedAction: { (url, msg) in
                print(nowDateString(), "oneTry failedAction:", url.absoluteString, msg)
                XCTFail(String(format: "fetch error: '%@' %@", url.absoluteString, msg))
                expect.fulfill()
            })
            waitForExpectations(timeout: 60) { (error) in
                if let error = error {
                    XCTAssert(false, String(format: "error: %@", error.localizedDescription))
                    return
                }
            }
            return story
        }
        func fetchLoop(state:StoryState, fetcher:StoryFetcher, id:String) {
            fetcher.FetchNext(currentState:state, successAction: { (resultStory) in
                print(nowDateString(), id, "FetchNext success.")
                if let content = resultStory.content {
                    print(nowDateString(), id, "content.count:", content.count)
                    if let firstLine = content.components(separatedBy: "\n").first {
                        print(nowDateString(), id, "content:", firstLine)
                    }
                }
                if resultStory.IsNextAlive != true {
                    print(nowDateString(), id, "IsNextAlive != ture. exit.")
                    return
                }
                fetchLoop(state: resultStory.CreateNextState(), fetcher: fetcher, id: id)
            }, failedAction: { (url, msg) in
                print(nowDateString(), id, "failedAction", url.absoluteString, msg)
            })
        }
        
        if true {
            let state = StoryFetcher.CreateFirstStoryState(url: url2, cookieString:cookieString)
            fetchLoop(state: state, fetcher: storyFetcher2, id: "fetcher #2")
        }

        var tryCount:Int = 1
        var currentState:StoryState? = StoryFetcher.CreateFirstStoryState(url:url, cookieString:cookieString)
        while let state = currentState {
            if tryCount > 20 {
                print(nowDateString(), "tryCount > 20. done.")
                break
            }
            print(nowDateString(), "try:", state.nextUrl?.absoluteString ?? "unknown url")
            currentState = oneTry(state: state, tryCount: tryCount, storyFetcher: storyFetcher1)
            if let content = currentState?.content {
                print(nowDateString(), "content.count:", content.count)
                if let firstLine = content.components(separatedBy: "\n").first {
                    print(nowDateString(), "content:", firstLine)
                }
            }
            if currentState?.IsNextAlive != true {
                print(nowDateString(), "IsNextAlive == false. done.")
                break
            }
            tryCount += 1
        }
    }
    
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
