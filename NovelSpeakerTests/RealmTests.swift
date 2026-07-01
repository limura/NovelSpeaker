//
//  RealmTests.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2019/06/17.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import XCTest
@testable import NovelSpeaker

class RealmTests: XCTestCase {
    let targetNovelID = "_TestNovelID"
    let testNovelTitle = "novel title"
    let firstContent = "first content"
    
    func addNewNovel(title:String, content:String, novelID: String) -> String {
        return RealmUtil.RealmBlock { (realm) -> String in
            let novel = RealmNovel()
            novel.novelID = novelID
            novel.type = .UserCreated
            novel.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            novel.lastReadDate = Date(timeIntervalSince1970: 1)
            novel.lastDownloadDate = Date()
            var story = Story()
            story.novelID = novel.novelID
            story.chapterNumber = 1
            story.content = content
            RealmUtil.WriteWith(realm: realm) { (realm) in
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: 1)
                novel.AppendDownloadDate(realm: realm, date: novel.lastDownloadDate)
                realm.add(novel, update: .modified)
            }
            return novel.novelID
        }
    }

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        RealmUtil.Write { realm in
            if let targetNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: targetNovelID) {
                targetNovel.delete(realm: realm)
            }
        }
        _ = addNewNovel(title: testNovelTitle, content: firstContent, novelID: targetNovelID)
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    // MARK: - NFC正規化

    func testNormalizeNFCConvertsNFDToNFC() {
        let nfc = "\u{3073}"          // び (precomposed / NFC)
        let nfd = "\u{3072}\u{3099}"  // ひ + 濁点 (decomposed / NFD)
        // Swift の String 比較は正準等価なので == では区別できない(前提確認)。
        XCTAssertEqual(nfc, nfd, "Swift String としては正準等価で等しいはず")
        // しかし UTF-8 バイト列は異なる。これが Realm の CONTAINS(バイト比較)で一致しない原因。
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8), "NFC と NFD は UTF-8 バイト列が異なるはず")

        let normalized = NovelSpeakerUtility.NormalizeNFC(nfd)
        XCTAssertEqual(Array(normalized.utf8), Array(nfc.utf8), "NormalizeNFC で NFC のバイト列になるはず")
        // 既に NFC / ASCII のものは不変
        XCTAssertEqual(Array(NovelSpeakerUtility.NormalizeNFC(nfc).utf8), Array(nfc.utf8))
        XCTAssertEqual(NovelSpeakerUtility.NormalizeNFC("abc 123"), "abc 123")
    }

    func testNormalizeExistingNovelTitlesAndWritersToNFC() {
        let nfdNovelID = "_NFCMigrationTest_NFD"
        let nfcNovelID = "_NFCMigrationTest_NFC"
        // 花びら / ピーチ
        let nfcTitle = "\u{82B1}\u{3073}\u{3089}"            // 花 + び(NFC) + ら
        let nfdTitle = "\u{82B1}\u{3072}\u{3099}\u{3089}"    // 花 + ひ+濁点(NFD) + ら
        let nfcWriter = "\u{30D4}\u{30FC}\u{30C1}"           // ピ(NFC) + ー + チ
        let nfdWriter = "\u{30D2}\u{309A}\u{30FC}\u{30C1}"   // ヒ+半濁点(NFD) + ー + チ

        func cleanup() {
            RealmUtil.Write { realm in
                for id in [nfdNovelID, nfcNovelID] {
                    if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: id) {
                        novel.delete(realm: realm)
                    }
                }
            }
        }
        cleanup()
        defer { cleanup() }

        // production の正規化を通さず、NFD/NFC をそのまま保存する
        RealmUtil.Write { realm in
            let nfdNovel = RealmNovel()
            nfdNovel.novelID = nfdNovelID
            nfdNovel.type = .UserCreated
            nfdNovel.title = nfdTitle
            nfdNovel.writer = nfdWriter
            realm.add(nfdNovel, update: .modified)
            let nfcNovel = RealmNovel()
            nfcNovel.novelID = nfcNovelID
            nfcNovel.type = .UserCreated
            nfcNovel.title = nfcTitle
            nfcNovel.writer = nfcWriter
            realm.add(nfcNovel, update: .modified)
        }
        // 前提確認: NFD がそのままのバイト列で保存されている
        RealmUtil.RealmBlock { realm in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: nfdNovelID) else {
                XCTFail("NFD test novel not found")
                return
            }
            XCTAssertEqual(Array(novel.title.utf8), Array(nfdTitle.utf8), "前提: NFD title がそのまま保存されている")
            XCTAssertEqual(Array(novel.writer.utf8), Array(nfdWriter.utf8), "前提: NFD writer がそのまま保存されている")
        }

        NovelSpeakerUtility.NormalizeExistingNovelTitlesAndWritersToNFC()

        RealmUtil.RealmBlock { realm in
            guard let nfdNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: nfdNovelID),
                  let nfcNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: nfcNovelID) else {
                XCTFail("test novel not found after migration")
                return
            }
            XCTAssertEqual(Array(nfdNovel.title.utf8), Array(nfcTitle.utf8), "NFD title が NFC のバイト列に正規化されているはず")
            XCTAssertEqual(Array(nfdNovel.writer.utf8), Array(nfcWriter.utf8), "NFD writer が NFC のバイト列に正規化されているはず")
            XCTAssertEqual(Array(nfcNovel.title.utf8), Array(nfcTitle.utf8), "もともと NFC の title は不変のはず")
            XCTAssertEqual(Array(nfcNovel.writer.utf8), Array(nfcWriter.utf8), "もともと NFC の writer は不変のはず")
        }
    }
    
    func testBase64Test() {
        let okText = "aG9nZQ==" // "hoge"
        let ngTextList = [
        "*aG9nZQ==",
        "*aG9nZQ=",
        "aG9nZQ=",
        "?aG9nZQ=",
        "!aG9nZQ==",
        " aG9nZQ==",
        "http://aG9nZQ==",
        ]
        let okData = Data(base64Encoded: okText)
        XCTAssert(okData != nil, "okData is nil?")
        if let okData = okData {
            let okString = String(data: okData, encoding: .utf8)
            XCTAssert(okString == "hoge", "okData is not \"hoge\"")
        }
        for item in ngTextList {
            let ngData = Data(base64Encoded: item)
            XCTAssert(ngData == nil, "ngData(\(item)) is not nil?")
        }
    }

    func createDummyStoryArray(content:String, novelID:String, count:Int, startChapterNumber: Int) -> [NovelSpeaker.Story] {
        var result:[NovelSpeaker.Story] = []
        for index in 0..<count {
            var story = Story()
            story.content = "\(index + startChapterNumber): \(content)"
            story.novelID = novelID
            story.chapterNumber = index + startChapterNumber
            result.append(story)
        }
        return result
    }
    func addDummyDataToNovel(novelID:String, content:String, count:Int, startChapterNumber:Int) {
        RealmUtil.Write { (realm) in
            let storyArray = createDummyStoryArray(content: content, novelID: novelID, count: count, startChapterNumber: startChapterNumber)
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID), let lastStory = storyArray.last else { return }
            RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
            novel.m_lastChapterStoryID = lastStory.storyID
        }
    }

    func testInsertStory_under100() {
        let firstStoryCount = 50
        let insertStoryIndex = 25
        let beforeContent = "before content"
        let insertContent = "insert content"
        RealmUtil.RealmBlock { realm in
            if let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 1))?.LoadStoryArray() {
                XCTAssertEqual(storyArray.count, 1, "初期のStoryが入っていないぽい？")
                return
            }
            addDummyDataToNovel(novelID: targetNovelID, content: beforeContent, count: firstStoryCount - 1, startChapterNumber: 2)
            if let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 1))?.LoadStoryArray() {
                XCTAssertEqual(storyArray.count, 50, "追加のStoryが入っていないぽい？")
                return
            }
            let newStory = NovelSpeaker.Story(url: "", subtitle: "", content: insertContent, novelID: targetNovelID, chapterNumber: insertStoryIndex, downloadDate: Date())
            RealmUtil.WriteWith(realm: realm) { realm in
                let insertStoryResult = RealmStoryBulk.InsertStoryWith(realm: realm, story: newStory)
                XCTAssertTrue(insertStoryResult, "InsertStoryWith() が失敗した")
            }
            guard let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID:    newStory.storyID)?.LoadStoryArray() else {
                XCTAssertTrue(false, "SearchStoryBulk?.LoadStoryArray()が失敗した: \(newStory.storyID)")
                return
            }
            XCTAssertEqual(storyArray.count, firstStoryCount + 1, "追加された後の Story の数がおかしい: storyArray.count: \(storyArray.count) != (fisrtStoryCount: \(firstStoryCount)) + 1")
            var chapterNumber = 1
            for story in storyArray {
                XCTAssertEqual(chapterNumber, story.chapterNumber, "順番に並んでいるはずの chapterNumber が違う: \(chapterNumber) != \(story.chapterNumber)")
                chapterNumber += 1
                if story.chapterNumber == 1 {
                    XCTAssertEqual(story.content, firstContent, "最初の Story の .content が違う: \"\(story.content)\" <-> \"\(firstContent)\"")
                }else if story.chapterNumber == newStory.chapterNumber {
                    XCTAssertEqual(story.content, insertContent, "追加した Story の .content が違う: \"\(story.content)\" <-> \"\(insertContent)\"")
                }else{
                    XCTAssertEqual(story.content, beforeContent, "追加していない Story の .content が違う: \"\(story.content)\" <-> \"\(beforeContent)\"")
                }
            }
        }
    }
    func testInsertStory_150_insertTo_50() {
        let firstStoryCount = 150
        let insertStoryIndex = 50
        let beforeContent = "before content"
        let insertContent = "insert content"
        RealmUtil.RealmBlock { realm in
            if let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 1))?.LoadStoryArray() {
                XCTAssertEqual(storyArray.count, 1, "初期のStoryが入っていないぽい？")
                return
            }
            addDummyDataToNovel(novelID: targetNovelID, content: beforeContent, count: firstStoryCount - 1, startChapterNumber: 2)
            if let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 1))?.LoadStoryArray() {
                XCTAssertEqual(storyArray.count, 50, "追加のStoryが入っていないぽい？")
                return
            }
            let newStory = NovelSpeaker.Story(url: "", subtitle: "", content: insertContent, novelID: targetNovelID, chapterNumber: insertStoryIndex, downloadDate: Date())
            RealmUtil.WriteWith(realm: realm) { realm in
                let insertStoryResult = RealmStoryBulk.InsertStoryWith(realm: realm, story: newStory)
                XCTAssertTrue(insertStoryResult, "InsertStoryWith() が失敗した")
            }
            guard let storyArray1_100 = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: newStory.storyID)?.LoadStoryArray() else {
                XCTAssertTrue(false, "SearchStoryBulk?.LoadStoryArray()が失敗した: \(newStory.storyID)")
                return
            }
            XCTAssertEqual(storyArray1_100.count, 100, "追加された後の Story の数がおかしい: storyArray.count: \(storyArray1_100.count) != (fisrtStoryCount: \(firstStoryCount)) + 1")
            var chapterNumber = 1
            for story in storyArray1_100 {
                XCTAssertEqual(chapterNumber, story.chapterNumber, "順番に並んでいるはずの chapterNumber が違う: \(chapterNumber) != \(story.chapterNumber)")
                chapterNumber += 1
                if story.chapterNumber == 1 {
                    XCTAssertEqual(story.content, firstContent, "最初の Story の .content が違う: \"\(story.content)\" <-> \"\(firstContent)\"")
                }else if story.chapterNumber == newStory.chapterNumber {
                    XCTAssertEqual(story.content, insertContent, "追加した Story の .content が違う: \"\(story.content)\" <-> \"\(insertContent)\"")
                }else{
                    XCTAssertEqual(story.content, beforeContent, "追加していない Story の .content が違う: \"\(story.content)\" <-> \"\(beforeContent)\"")
                }
            }
            guard let storyArray101_151 = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: newStory.storyID)?.LoadStoryArray() else {
                XCTAssertTrue(false, "SearchStoryBulk?.LoadStoryArray()が失敗した: \(newStory.storyID)")
                return
            }
            XCTAssertEqual(storyArray101_151.count, 51, "追加された後の Story の数がおかしい")
            chapterNumber = 101
            for story in storyArray101_151 {
                XCTAssertEqual(chapterNumber, story.chapterNumber, "順番に並んでいるはずの chapterNumber が違う: \(chapterNumber) != \(story.chapterNumber)")
                chapterNumber += 1
                if story.chapterNumber == newStory.chapterNumber {
                    XCTAssertEqual(story.content, insertContent, "追加した Story の .content が違う: \"\(story.content)\" <-> \"\(insertContent)\"")
                }else{
                    XCTAssertEqual(story.content, beforeContent, "追加していない Story の .content が違う: \"\(story.content)\" <-> \"\(beforeContent)\"")
                }
            }
        }
    }
    func testInsertStory_100_insertTo_100() {
        let firstStoryCount = 100
        let insertStoryIndex = 100
        let beforeContent = "before content"
        let insertContent = "insert content"
        RealmUtil.RealmBlock { realm in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: targetNovelID) {
                XCTAssertEqual(novel.lastChapterNumber, 1, "m_lastChapterStoryID の初期値が ...:1 ではないぽい？: \(novel.m_lastChapterStoryID)")
            }
            if let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 1))?.LoadStoryArray() {
                XCTAssertEqual(storyArray.count, 1, "初期のStoryが入っていないぽい？")
                return
            }
            addDummyDataToNovel(novelID: targetNovelID, content: beforeContent, count: firstStoryCount - 1, startChapterNumber: 2)
            if let storyArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 1))?.LoadStoryArray() {
                XCTAssertEqual(storyArray.count, 100, "追加のStoryが入っていないぽい？")
                return
            }
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: targetNovelID) {
                XCTAssertEqual(novel.lastChapterNumber, 100, "100個追加した所で m_lastChapterStoryID の初期値が ...:100 ではないぽい？: \(novel.m_lastChapterStoryID)")
            }
            XCTAssertNil(RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 101))?.LoadStoryArray(), "既に 101 ページ目がある(´・ω・`)")
            let newStory = NovelSpeaker.Story(url: "", subtitle: "", content: insertContent, novelID: targetNovelID, chapterNumber: insertStoryIndex, downloadDate: Date())
            RealmUtil.WriteWith(realm: realm) { realm in
                let insertStoryResult = RealmStoryBulk.InsertStoryWith(realm: realm, story: newStory)
                XCTAssertTrue(insertStoryResult, "InsertStoryWith() が失敗した")
            }
            guard let storyArray1_100 = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: newStory.storyID)?.LoadStoryArray() else {
                XCTAssertTrue(false, "SearchStoryBulk?.LoadStoryArray()が失敗した: \(newStory.storyID)")
                return
            }
            XCTAssertEqual(storyArray1_100.count, 100, "追加された後の Story の数がおかしい: storyArray.count: \(storyArray1_100.count) != (fisrtStoryCount: \(firstStoryCount)) + 1")
            var chapterNumber = 1
            for story in storyArray1_100 {
                XCTAssertEqual(chapterNumber, story.chapterNumber, "順番に並んでいるはずの chapterNumber が違う: \(chapterNumber) != \(story.chapterNumber)")
                chapterNumber += 1
                if story.chapterNumber == 1 {
                    XCTAssertEqual(story.content, firstContent, "最初の Story の .content が違う: \"\(story.content)\" <-> \"\(firstContent)\"")
                }else if story.chapterNumber == newStory.chapterNumber {
                    XCTAssertEqual(story.content, insertContent, "追加した Story の .content が違う: \"\(story.content)\" <-> \"\(insertContent)\"")
                }else{
                    XCTAssertEqual(story.content, beforeContent, "追加していない Story の .content が違う: \"\(story.content)\" <-> \"\(beforeContent)\"")
                }
            }
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: targetNovelID) {
                XCTAssertEqual(novel.lastChapterNumber, 101, "101個目を追加した所で m_lastChapterStoryID の初期値が ...:101 ではないぽい？: \(novel.m_lastChapterStoryID)")
            }
            guard let storyArray101_101 = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: 101))?.LoadStoryArray() else {
                XCTAssertTrue(false, "SearchStoryBulk?.LoadStoryArray()が失敗した: \(newStory.storyID)")
                return
            }
            XCTAssertEqual(storyArray101_101.count, 1, "追加された後の Story の数がおかしい")
            chapterNumber = 101
            for story in storyArray101_101 {
                XCTAssertEqual(chapterNumber, story.chapterNumber, "順番に並んでいるはずの chapterNumber が違う: \(chapterNumber) != \(story.chapterNumber)")
                chapterNumber += 1
                if story.chapterNumber == newStory.chapterNumber {
                    XCTAssertEqual(story.content, insertContent, "追加した Story の .content が違う: \"\(story.content)\" <-> \"\(insertContent)\"")
                }else{
                    XCTAssertEqual(story.content, beforeContent, "追加していない Story の .content が違う: \"\(story.content)\" <-> \"\(beforeContent)\"")
                }
            }
        }
    }
}

// NovelSpeakerUtility.AppendAllPagesToNovelTail(sourceNovelID:targetNovelID:) のテスト。
// (コピー元の全ページを追加先の末尾へ bulk 単位でまとめて追記する処理)
final class AppendAllPagesToNovelTailTests: XCTestCase {
    private let sourceNovelID = "_AppendTest_Source"
    private let targetNovelID = "_AppendTest_Target"

    override func setUpWithError() throws {
        try super.setUpWithError()
        // ローカル Realm を使う(iCloud は使わない)。
        UserDefaults.standard.set(false, forKey: RealmUtil.UseCloudRealmKey)
        cleanup()
    }

    override func tearDownWithError() throws {
        cleanup()
        try super.tearDownWithError()
    }

    private func cleanup() {
        RealmUtil.Write { realm in
            for novelID in [sourceNovelID, targetNovelID] {
                if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                    novel.delete(realm: realm)
                }
                RealmStoryBulk.RemoveAllStoryWith(realm: realm, novelID: novelID)
            }
        }
    }

    // 指定の novelID に、1..pageCount のページを持つ小説を作る。
    // 各ページの content/subtitle は "<prefix>-content-<ch>" / "<prefix>-subtitle-<ch>"。
    // urlPrefix があれば url は "<urlPrefix><ch>"。pageCount が 0 ならページ無し(空の小説)。
    private func makeNovel(novelID: String, type: NovelType, prefix: String, pageCount: Int, urlPrefix: String?) {
        RealmUtil.Write { realm in
            let novel = RealmNovel()
            novel.novelID = novelID
            novel.type = type
            novel.title = "\(prefix) title"
            var stories: [NovelSpeaker.Story] = []
            if pageCount > 0 {
                for ch in 1...pageCount {
                    var story = Story()
                    story.novelID = novelID
                    story.chapterNumber = ch
                    story.content = "\(prefix)-content-\(ch)"
                    story.subtitle = "\(prefix)-subtitle-\(ch)"
                    if let urlPrefix = urlPrefix {
                        story.url = "\(urlPrefix)\(ch)"
                    }
                    stories.append(story)
                }
                RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: stories)
                if let last = stories.last {
                    novel.m_lastChapterStoryID = last.storyID
                }
            }
            realm.add(novel, update: .modified)
        }
    }

    private func story(_ novelID: String, _ chapterNumber: Int) -> NovelSpeaker.Story? {
        return RealmUtil.RealmBlock { realm in
            return RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber)
        }
    }

    private func lastChapterNumber(_ novelID: String) -> Int? {
        return RealmUtil.RealmBlock { realm in
            return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.lastChapterNumber
        }
    }

    // 空の追加先(ユーザ作成型)へ全ページを追加できること。
    func testAppendToEmptyTarget() {
        makeNovel(novelID: sourceNovelID, type: .UserCreated, prefix: "src", pageCount: 3, urlPrefix: nil)
        makeNovel(novelID: targetNovelID, type: .UserCreated, prefix: "tgt", pageCount: 0, urlPrefix: nil)

        let result = NovelSpeakerUtility.AppendAllPagesToNovelTail(sourceNovelID: sourceNovelID, targetNovelID: targetNovelID)
        XCTAssertTrue(result, "AppendAllPagesToNovelTail が失敗した")

        XCTAssertEqual(lastChapterNumber(targetNovelID), 3, "追加先の末尾章番号が 3 になっていない")
        for ch in 1...3 {
            let story = self.story(targetNovelID, ch)
            XCTAssertEqual(story?.content, "src-content-\(ch)", "ch\(ch) の content がコピーされていない")
            XCTAssertEqual(story?.subtitle, "src-subtitle-\(ch)", "ch\(ch) の subtitle がコピーされていない")
        }
        // 4ページ目は存在しないこと。
        XCTAssertNil(story(targetNovelID, 4), "余計なページが増えている")
    }

    // 既存ページを持つ追加先(ユーザ作成型)の末尾へ、正しい章番号・内容で連結されること。
    func testAppendToNonEmptyTargetKeepsExistingAndNumbersContiguously() {
        makeNovel(novelID: sourceNovelID, type: .UserCreated, prefix: "src", pageCount: 3, urlPrefix: nil)
        makeNovel(novelID: targetNovelID, type: .UserCreated, prefix: "tgt", pageCount: 2, urlPrefix: nil)

        let result = NovelSpeakerUtility.AppendAllPagesToNovelTail(sourceNovelID: sourceNovelID, targetNovelID: targetNovelID)
        XCTAssertTrue(result, "AppendAllPagesToNovelTail が失敗した")

        XCTAssertEqual(lastChapterNumber(targetNovelID), 5, "追加先の末尾章番号が 5 になっていない")
        // 既存 1,2 は不変。
        XCTAssertEqual(story(targetNovelID, 1)?.content, "tgt-content-1", "既存 ch1 が変わってしまった")
        XCTAssertEqual(story(targetNovelID, 2)?.content, "tgt-content-2", "既存 ch2 が変わってしまった")
        // 3,4,5 はコピー元 1,2,3。
        for (offset, ch) in [3, 4, 5].enumerated() {
            XCTAssertEqual(story(targetNovelID, ch)?.content, "src-content-\(offset + 1)", "ch\(ch) の content がコピー元とずれている")
            XCTAssertEqual(story(targetNovelID, ch)?.subtitle, "src-subtitle-\(offset + 1)", "ch\(ch) の subtitle がコピー元とずれている")
        }
    }

    // URL 型の追加先では、追加される全ページの url が「追加先の末尾ページの url」になり、
    // コピー元の url は一切引き継がれないこと。既存ページの url は不変であること。
    func testAppendToURLTargetInheritsTargetLastURL() {
        makeNovel(novelID: sourceNovelID, type: .URL, prefix: "src", pageCount: 3, urlPrefix: "https://src.example/")
        makeNovel(novelID: targetNovelID, type: .URL, prefix: "tgt", pageCount: 2, urlPrefix: "https://tgt.example/")

        let result = NovelSpeakerUtility.AppendAllPagesToNovelTail(sourceNovelID: sourceNovelID, targetNovelID: targetNovelID)
        XCTAssertTrue(result, "AppendAllPagesToNovelTail が失敗した")

        // 追加先の末尾ページ url は "https://tgt.example/2"。
        let expectedURL = "https://tgt.example/2"
        // 既存ページの url は不変。
        XCTAssertEqual(story(targetNovelID, 1)?.url, "https://tgt.example/1", "既存 ch1 の url が変わってしまった")
        XCTAssertEqual(story(targetNovelID, 2)?.url, "https://tgt.example/2", "既存 ch2 の url が変わってしまった")
        // 追加された 3,4,5 は全て追加先の末尾 url。コピー元 url は入っていない。
        for ch in 3...5 {
            XCTAssertEqual(story(targetNovelID, ch)?.url, expectedURL, "追加された ch\(ch) の url が追加先の末尾 url になっていない")
        }
    }

    // 100章境界を跨ぐ追加でも、全ページの内容・章番号が正しく、bulk が正しく分割されること。
    func testAppendCrossesBulkBoundary() {
        // 追加先を 98 ページにしておき、5 ページ追加して 103 ページ(2 つ目の bulk に跨る)にする。
        makeNovel(novelID: sourceNovelID, type: .UserCreated, prefix: "src", pageCount: 5, urlPrefix: nil)
        makeNovel(novelID: targetNovelID, type: .UserCreated, prefix: "tgt", pageCount: 98, urlPrefix: nil)

        let result = NovelSpeakerUtility.AppendAllPagesToNovelTail(sourceNovelID: sourceNovelID, targetNovelID: targetNovelID)
        XCTAssertTrue(result, "AppendAllPagesToNovelTail が失敗した")

        XCTAssertEqual(lastChapterNumber(targetNovelID), 103, "追加先の末尾章番号が 103 になっていない")

        // 99..103 がコピー元 1..5 になっていること(境界を跨ぐ)。
        for (offset, ch) in Array(99...103).enumerated() {
            XCTAssertEqual(story(targetNovelID, ch)?.content, "src-content-\(offset + 1)", "ch\(ch) の content がコピー元とずれている")
        }
        // 既存の 98 ページ目は不変。
        XCTAssertEqual(story(targetNovelID, 98)?.content, "tgt-content-98", "既存 ch98 が変わってしまった")

        // bulk が正しく分割されていること(1 つ目=100章, 2 つ目=3章)。
        RealmUtil.RealmBlock { realm in
            let firstBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: self.targetNovelID, chapterNumber: 1))?.LoadStoryArray()
            XCTAssertEqual(firstBulk?.count, 100, "1 つ目の bulk が 100 章になっていない")
            let secondBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: self.targetNovelID, chapterNumber: 101))?.LoadStoryArray()
            XCTAssertEqual(secondBulk?.count, 3, "2 つ目の bulk が 3 章になっていない")
        }
    }

    // 全ページの合計数が「追加先の元の数 + コピー元の数」になること。
    func testAppendTotalPageCount() {
        makeNovel(novelID: sourceNovelID, type: .UserCreated, prefix: "src", pageCount: 7, urlPrefix: nil)
        makeNovel(novelID: targetNovelID, type: .UserCreated, prefix: "tgt", pageCount: 4, urlPrefix: nil)

        let result = NovelSpeakerUtility.AppendAllPagesToNovelTail(sourceNovelID: sourceNovelID, targetNovelID: targetNovelID)
        XCTAssertTrue(result, "AppendAllPagesToNovelTail が失敗した")

        let total = RealmUtil.RealmBlock { realm -> Int in
            var count = 0
            RealmStoryBulk.SearchAllStoryFor(realm: realm, novelID: self.targetNovelID) { _ in count += 1 }
            return count
        }
        XCTAssertEqual(total, 11, "追加後の総ページ数が 4 + 7 = 11 になっていない")
    }
}
