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
            RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
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
