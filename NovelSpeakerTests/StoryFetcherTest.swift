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

    // MARK: - スクレイプ検査(checkTargets)パーサ
    // 設計メモ: DESIGN_スクレイプ検査.md

    func testParseCheckTargetsBasic() throws {
        let targets = ScrapeCheckTarget.parse("https://example.com/show/456 => content,nextLink,!firstPageLink")
        XCTAssertEqual(targets.count, 1)
        let target = try XCTUnwrap(targets.first)
        XCTAssertEqual(target.url, URL(string: "https://example.com/show/456"))
        XCTAssertFalse(target.requireAuth)
        XCTAssertEqual(target.expectations, [
            ScrapeCheckExpectation(token: .content, mustBeEmpty: false),
            ScrapeCheckExpectation(token: .nextLink, mustBeEmpty: false),
            ScrapeCheckExpectation(token: .firstPageLink, mustBeEmpty: true),
        ])
    }

    func testParseCheckTargetsMultipleEntriesWithBothSeparators() throws {
        // エントリ区切りは 改行 と `|` のどちらでも、混在しても良い。
        let raw = """
        https://example.com/series/123 => firstPageButton
        https://example.com/show/1 => content | https://example.com/show/2 => content,nextLink
        """
        let targets = ScrapeCheckTarget.parse(raw)
        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(targets[0].url, URL(string: "https://example.com/series/123"))
        XCTAssertEqual(targets[0].expectations, [ScrapeCheckExpectation(token: .firstPageButton, mustBeEmpty: false)])
        XCTAssertEqual(targets[1].url, URL(string: "https://example.com/show/1"))
        XCTAssertEqual(targets[2].url, URL(string: "https://example.com/show/2"))
        XCTAssertEqual(targets[2].expectations.count, 2)
    }

    func testParseCheckTargetsAuthTagAndSpacingTolerance() throws {
        // [auth] 前置タグで要認証マーク。`=>` 前後スペースは任意(無くても可)。
        let withSpace = try XCTUnwrap(ScrapeCheckTarget.parse("[auth] https://site/secret => content").first)
        XCTAssertTrue(withSpace.requireAuth)
        XCTAssertEqual(withSpace.url, URL(string: "https://site/secret"))
        XCTAssertEqual(withSpace.expectations, [ScrapeCheckExpectation(token: .content, mustBeEmpty: false)])

        let noSpace = try XCTUnwrap(ScrapeCheckTarget.parse("https://site/x=>content,nextLink").first)
        XCTAssertFalse(noSpace.requireAuth)
        XCTAssertEqual(noSpace.url, URL(string: "https://site/x"))
        XCTAssertEqual(noSpace.expectations.count, 2)
    }

    func testParseCheckTargetsTokenToleranceAndBareURL() throws {
        // 未知トークンはスキップし、有効なものだけ残す。大文字小文字は無視。
        let tolerant = try XCTUnwrap(ScrapeCheckTarget.parse("https://site/y => Content, bogus, NEXTLINK").first)
        XCTAssertEqual(tolerant.expectations, [
            ScrapeCheckExpectation(token: .content, mustBeEmpty: false),
            ScrapeCheckExpectation(token: .nextLink, mustBeEmpty: false),
        ])

        // `=>` の無い(URLのみ)エントリは期待項目なしの対象として保持する。
        let bare = try XCTUnwrap(ScrapeCheckTarget.parse("https://site/z").first)
        XCTAssertEqual(bare.url, URL(string: "https://site/z"))
        XCTAssertTrue(bare.expectations.isEmpty)
    }

    func testParseCheckTargetsPageElementAlias() throws {
        // シート列名 pageElement / newPageElement / body は本文(content)のエイリアス。nexturl は nextLink。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://s/x => pageElement,!newPageElement,nexturl,body").first)
        XCTAssertEqual(target.expectations, [
            ScrapeCheckExpectation(token: .content, mustBeEmpty: false),
            ScrapeCheckExpectation(token: .content, mustBeEmpty: true),
            ScrapeCheckExpectation(token: .nextLink, mustBeEmpty: false),
            ScrapeCheckExpectation(token: .content, mustBeEmpty: false),
        ])
    }

    func testParseCheckTargetsEmptyOrWhitespaceReturnsEmpty() throws {
        XCTAssertTrue(ScrapeCheckTarget.parse(nil).isEmpty)
        XCTAssertTrue(ScrapeCheckTarget.parse("").isEmpty)
        XCTAssertTrue(ScrapeCheckTarget.parse("   \n  |  \n").isEmpty)
    }

    func testParseCheckTargetsHashComment() throws {
        let raw = """
        # この行はまるごとコメント
        [auth] https://example.com/show/1 => content,author   # pixiv本文: ログイン時は author まで取れる想定
        https://example.com/series/9 => firstPageLink # シリーズ概要ページ
        """
        let targets = ScrapeCheckTarget.parse(raw)
        // まるごとコメント行は対象にならない → 2件。
        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].url, URL(string: "https://example.com/show/1"))
        XCTAssertTrue(targets[0].requireAuth)
        XCTAssertEqual(targets[0].expectations, [
            ScrapeCheckExpectation(token: .content, mustBeEmpty: false),
            ScrapeCheckExpectation(token: .author, mustBeEmpty: false),
        ])
        // 行末コメントを除去しても期待トークンは正しく残る。
        XCTAssertEqual(targets[1].url, URL(string: "https://example.com/series/9"))
        XCTAssertEqual(targets[1].expectations, [ScrapeCheckExpectation(token: .firstPageLink, mustBeEmpty: false)])
    }

    func testParseCheckTargetsHashDoesNotBreakURLFragment() throws {
        // URL の fragment(#...) は # の直前が空白でないため保持される。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://example.com/p#frag => content").first)
        XCTAssertEqual(target.url, URL(string: "https://example.com/p#frag"))
        XCTAssertEqual(target.expectations, [ScrapeCheckExpectation(token: .content, mustBeEmpty: false)])
    }

    func testParseCheckTargetsInlineCommentBeforePipeOnSameLine() throws {
        // 同一行で `#` 以降に `|` 区切りの別エントリが続く場合、# 以降は行末までコメント(別エントリも消える)。
        let targets = ScrapeCheckTarget.parse("https://a/1 => content # メモ | https://b/2 => author")
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].url, URL(string: "https://a/1"))
    }

    // MARK: - スクレイプ検査(checkTargets)の突合 evaluate(state:)

    #if !os(watchOS)
    // 検査の突合テスト用に、抽出後を模した StoryState を組み立てる。
    private func makeInspectionState(url:String = "https://example.com/show/456",
                                     content:String? = nil,
                                     nextUrl:String? = nil,
                                     firstPageLink:String? = nil,
                                     title:String? = nil,
                                     author:String? = nil,
                                     subtitle:String? = nil,
                                     tagArray:[String] = []) throws -> StoryState {
        return StoryState(
            url: try XCTUnwrap(URL(string: url)),
            cookieString: nil,
            content: content,
            nextUrl: nextUrl.flatMap { URL(string: $0) },
            firstPageLink: firstPageLink.flatMap { URL(string: $0) },
            title: title,
            author: author,
            subtitle: subtitle,
            tagArray: tagArray,
            siteInfoArray: [],
            isNeedHeadless: false,
            isCanFetchNextImmediately: false,
            waitSecondInHeadless: nil,
            previousContent: nil,
            document: nil,
            nextButton: nil,
            firstPageButton: nil,
            forceClickButton: nil,
            forceErrorMessage: nil
        )
    }

    func testEvaluateAllExpectationsSatisfiedReturnsNoFailures() throws {
        // 本文ページ: content,nextLink を期待し、firstPageLink は空であるべき(!firstPageLink)。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://example.com/show/456 => content,nextLink,!firstPageLink").first)
        let state = try makeInspectionState(content: "本文がここにある", nextUrl: "https://example.com/show/457", firstPageLink: nil)
        XCTAssertEqual(target.evaluate(state: state), [])
    }

    func testEvaluateReportsMissingExpectation() throws {
        // content を期待しているのに抽出できていない → 失敗として報告される。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://example.com/show/456 => content,nextLink").first)
        let state = try makeInspectionState(content: nil, nextUrl: "https://example.com/show/457")
        let failures = target.evaluate(state: state)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(try XCTUnwrap(failures.first).contains("content"))
    }

    func testEvaluateNegationFailsWhenPresent() throws {
        // !firstPageLink を期待しているのに firstPageLink が抽出された → 失敗。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://example.com/show/456 => content,!firstPageLink").first)
        let state = try makeInspectionState(content: "本文", firstPageLink: "https://example.com/series/1")
        let failures = target.evaluate(state: state)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(try XCTUnwrap(failures.first).hasPrefix("!firstPageLink"))
    }

    func testEvaluateNextLinkTokenMapsToNextUrlField() throws {
        // nextLink トークンは StoryState.nextUrl の有無に対応する。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://example.com/show/456 => nextLink").first)
        XCTAssertEqual(try target.evaluate(state: makeInspectionState(nextUrl: "https://example.com/next")), [])
        XCTAssertEqual(try target.evaluate(state: makeInspectionState(nextUrl: nil)).count, 1)
    }

    func testEvaluateSeriesPageExpectsOnlyFirstPageLink() throws {
        // シリーズ概要ページ: firstPageLink だけ期待。content が無くても OK。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://example.com/series/123 => firstPageLink").first)
        let state = try makeInspectionState(url: "https://example.com/series/123", content: nil, firstPageLink: "https://example.com/show/1")
        XCTAssertEqual(target.evaluate(state: state), [])
    }

    // MARK: - ScrapeInspector.judge(着手順3の判定ロジック・純粋関数)

    func testJudgeSuccessNoFailureIsOK() throws {
        let (status, reasons) = ScrapeInspector.judge(requireAuth: false, failMessage: nil, evaluateFailures: [])
        XCTAssertEqual(status, .ok)
        XCTAssertTrue(reasons.isEmpty)
    }

    func testJudgeSuccessWithFailureIsNG() throws {
        let (status, reasons) = ScrapeInspector.judge(requireAuth: false, failMessage: nil, evaluateFailures: ["content (抽出できなかった)"])
        XCTAssertEqual(status, .ng)
        XCTAssertEqual(reasons, ["content (抽出できなかった)"])
    }

    func testJudgeAuthSuccessFailureSameHostNoGateIsWarn() throws {
        // [auth] で期待が外れたが gate も別ホストも無い = 未ログインの確証なし = 故障の可能性 → WARN(要確認)。
        let (status, reasons) = ScrapeInspector.judge(requireAuth: true, failMessage: nil, evaluateFailures: ["nextLink (抽出できなかった)"], hostChanged: false)
        XCTAssertEqual(status, .warn)
        XCTAssertTrue(reasons.contains("nextLink (抽出できなかった)"))
    }

    func testJudgeAuthSuccessFailureHostChangedIsSkip() throws {
        // [auth] で別ホストへ飛ばされた(novel18→nl.syosetu.com 等) = 未ログイン確定 → SKIP。
        let (status, reasons) = ScrapeInspector.judge(requireAuth: true, failMessage: nil, evaluateFailures: ["nextLink (抽出できなかった)"], hostChanged: true)
        XCTAssertEqual(status, .skip)
        XCTAssertEqual(reasons.first, "別ホストへリダイレクト(未ログイン/年齢確認の可能性)")
    }

    func testJudgeAuthSuccessHostChangedEvenWithContentIsSkip() throws {
        // 別ホストの年齢確認ページは //body で content が取れてしまうが、別ホスト=要求ページではないので SKIP(偽OKにしない)。
        let (status, _) = ScrapeInspector.judge(requireAuth: true, failMessage: nil, evaluateFailures: [], hostChanged: true)
        XCTAssertEqual(status, .skip)
    }

    func testIsHostChangedDetectsNovel18Redirect() throws {
        let requested = try XCTUnwrap(URL(string: "https://novel18.syosetu.com/n8956gi/1/"))
        let redirected = try XCTUnwrap(URL(string: "https://nl.syosetu.com/redirect/ageauth/?url=x"))
        let same = try XCTUnwrap(URL(string: "https://novel18.syosetu.com/n8956gi/1/?foo=bar"))
        XCTAssertTrue(ScrapeInspector.isHostChanged(requested: requested, final: redirected))
        XCTAssertFalse(ScrapeInspector.isHostChanged(requested: requested, final: same))
        XCTAssertFalse(ScrapeInspector.isHostChanged(requested: requested, final: nil))
    }

    func testParseCheckTargetsCollectsUnknownTokens() throws {
        // 語彙外トークン(typo)は黙って捨てず unknownTokens に記録する。
        let target = try XCTUnwrap(ScrapeCheckTarget.parse("https://s/x => titel,content,authr").first)
        XCTAssertEqual(target.expectations, [ScrapeCheckExpectation(token: .content, mustBeEmpty: false)])
        XCTAssertEqual(target.unknownTokens, ["titel", "authr"])
    }

    func testJudgeUnknownTokenEscalatesOKtoWarn() throws {
        // typo があると、たとえ評価が成功(OK相当)でも WARN に格上げして気づけるようにする。
        let (status, reasons) = ScrapeInspector.judge(requireAuth: false, failMessage: nil, evaluateFailures: [], hostChanged: false, unknownTokens: ["titel"])
        XCTAssertEqual(status, .warn)
        XCTAssertTrue(reasons.first?.contains("titel") == true)
    }

    func testJudgeUnknownTokenKeepsNGButAnnotates() throws {
        // 既に NG のものは NG のまま、typo 注記を足す。
        let (status, reasons) = ScrapeInspector.judge(requireAuth: false, failMessage: nil, evaluateFailures: ["content (抽出できなかった)"], hostChanged: false, unknownTokens: ["authr"])
        XCTAssertEqual(status, .ng)
        XCTAssertTrue(reasons.contains(where: { $0.contains("authr") }))
        XCTAssertTrue(reasons.contains("content (抽出できなかった)"))
    }

    func testJudgeForceErrorWithoutAuthIsNG() throws {
        // forceError(gate) が出たが [auth] でないなら NG(壊れている)。
        let (status, reasons) = ScrapeInspector.judge(requireAuth: false, failMessage: "ログインを促す画面が出ています。", evaluateFailures: [])
        XCTAssertEqual(status, .ng)
        XCTAssertEqual(reasons, ["ログインを促す画面が出ています。"])
    }

    func testJudgeForceErrorWithAuthIsSkip() throws {
        // forceError(gate) で [auth] なら未ログインとみなして SKIP。
        let (status, _) = ScrapeInspector.judge(requireAuth: true, failMessage: "ログインを促す画面が出ています。", evaluateFailures: [])
        XCTAssertEqual(status, .skip)
    }

    func testJudgeRobotsBlockIsRobotsLabelEvenWithAuth() throws {
        // robots ブロックは [auth] の有無に関わらず別ラベル(ROBOTS)。
        let (status, _) = ScrapeInspector.judge(requireAuth: true, failMessage: ScrapeInspector.robotsBlockMessage, evaluateFailures: [])
        XCTAssertEqual(status, .robotsBlocked)
        let (status2, _) = ScrapeInspector.judge(requireAuth: false, failMessage: ScrapeInspector.robotsBlockMessage, evaluateFailures: [])
        XCTAssertEqual(status2, .robotsBlocked)
    }

    func testReportCountsAndOrder() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/x"))
        let results = [
            ScrapeInspector.Result(siteName: "A", url: url, requireAuth: false, status: .ok, reasons: []),
            ScrapeInspector.Result(siteName: "B", url: url, requireAuth: false, status: .ng, reasons: ["content (抽出できなかった)"]),
            ScrapeInspector.Result(siteName: "C", url: url, requireAuth: true, status: .skip, reasons: ["要ログイン/年齢確認の可能性"]),
        ]
        let report = ScrapeInspector.report(results: results)
        XCTAssertTrue(report.contains("NG:1"))
        XCTAssertTrue(report.contains("SKIP:1"))
        XCTAssertTrue(report.contains("OK:1"))
        // 明細は NG が OK より前(重要度順)。
        let ngIndex = try XCTUnwrap(report.range(of: "[NG]"))
        let okIndex = try XCTUnwrap(report.range(of: "[OK]"))
        XCTAssertTrue(ngIndex.lowerBound < okIndex.lowerBound)
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
    
    func testCreateNextStateKeepsTransientDOMForButtonNavigation() throws {
        // CreateNextState() は次ページ取得用の状態を作る。
        // content は一旦クリアして previousContent に退避するが、
        // ボタン送り(nextButton 等のクリックで次ページへ進む)サイトのために
        // document / 各ボタンは引き継ぐ必要がある。
        // (commit 4494851「ボタンを押さないと次のページに行けない場合などに取り込み失敗」対応。
        //  URL送りのサイトではデコード時に transientDOMRetainedIfNeeded が既に document を捨てているため、
        //  ここで引き継ぐ document は実質的に nil になる。)
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

        // content はクリアされ、直前の内容は previousContent に退避される
        XCTAssertNil(nextState.content)
        XCTAssertEqual(nextState.previousContent, "本文")
        XCTAssertEqual(nextState.nextUrl?.absoluteString, "https://example.com/chapter2")
        // ボタン送りのために document / nextButton を引き継いでいること
        XCTAssertNotNil(nextState.document)
        XCTAssertNotNil(nextState.nextButton)
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
