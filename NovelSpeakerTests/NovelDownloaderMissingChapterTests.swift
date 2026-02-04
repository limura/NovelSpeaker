//
//  NovelDownloaderMissingChapterTests.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2026/01/14.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//


import XCTest
import RealmSwift
@testable import NovelSpeaker

final class NovelDownloaderMissingChapterTests: XCTestCase {
    /// 用意していただく「1〜15 まで連番で本文を返す URL」
    private let testNovelURLString = "https://limura.github.io/NovelSpeaker/topics/jp/00001.html"
    private var testNovelID: String { return testNovelURLString }
    private let testChapterRange = 1...15

    private func chapterUrl(_ chapterNumber: Int) -> String {
        return "https://limura.github.io/NovelSpeaker/topics/jp/\(String(format: "%05d", chapterNumber)).html"
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        // ローカル Realm を使う前提（iCloud は使わない）
        UserDefaults.standard.set(false, forKey: RealmUtil.UseCloudRealmKey)

        // 該当小説のデータを全消し
        RealmUtil.Write { realm in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: testNovelID) {
                realm.delete(novel)
            }
            RealmStoryBulk.RemoveAllStoryWith(realm: realm, novelID: testNovelID)
        }

        // Novel エントリだけは毎回作っておく
        RealmUtil.Write { realm in
            let novel = RealmNovel()
            novel.novelID = testNovelID
            novel.url = testNovelURLString
            novel.title = "Test Novel 1-15"
            realm.add(novel, update: .modified)
        }

        // ダウンロードを止めないようにする
        NovelDownloadQueue.shared.isDownloadStop = false
        // 書き込みバッファもクリアしておく
        NovelDownloader.FlushAllWritePool()
    }

    override func tearDownWithError() throws {
        NiftyUtility.httpRequestObserver = nil
        NovelDownloadQueue.shared.isDownloadStop = true
        NovelDownloader.FlushAllWritePool()
        try super.tearDownWithError()
    }

    // 1. まっさらな状態から 1〜15 を取り込めること
    func testDownloadFromEmptyCreates1to15() throws {
        let exp = expectation(description: "download completes")

        let fetcher = StoryFetcher()
        NovelDownloader.startDownload(
            novelID: testNovelID,
            fetcher: fetcher,
            currentState: nil,
            chapterNumber: 0,
            downloadCount: 0,
            successAction: { novelID, _ in
                XCTAssertEqual(novelID, self.testNovelID)
                exp.fulfill()
            },
            failedAction: { _, _, errorDescription in
                //XCTFail("download failed: \(errorDescription)")
                exp.fulfill()
            }
        )

        wait(for: [exp], timeout: 60.0)

        // 1〜15 が揃っているかチェック
        RealmUtil.RealmBlock { realm in
            let matrix = RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: self.testNovelID)
            let all = Array(matrix.joined())
            XCTAssertEqual(all.sorted(), Array(self.testChapterRange))
        }
    }

    // 2. 途中が歯抜け(1,2,3,6,7)の状態から再ダウンロードすると 1〜15 が揃い、
    //    既存の章の内容は上書きされないこと
    func testDownloadFromMissingMiddleFills4and5WithoutOverwriting() throws {
        // 事前に 1,2,3,6,7 だけ入れておく（ユーザが編集済みの内容を想定）
        RealmUtil.Write { realm in
            var stories: [NovelSpeaker.Story] = []
            for ch in [1, 2, 3, 6, 7] {
                var s = Story()
                s.novelID = self.testNovelID
                s.chapterNumber = ch
                s.content = "edited \(ch)"
                s.subtitle = "ch \(ch)"
                s.url = self.chapterUrl(ch)
                s.downloadDate = Date()
                stories.append(s)
            }
            _ = RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: self.testNovelID, storyArray: stories)
        }

        var accessedUrls:[String] = []
        NiftyUtility.httpRequestObserver = { url in
            let urlString = url.absoluteString
            if urlString.hasPrefix("https://limura.github.io/NovelSpeaker/topics/jp/"),
               urlString.hasSuffix(".html") {
                accessedUrls.append(urlString)
            }
        }

        let exp = expectation(description: "download completes")

        RealmUtil.RealmBlock { realm in
            print("NDMCT: before:", RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: self.testNovelID))
        }
        
        let fetcher = StoryFetcher()
        NovelDownloader.startDownload(
            novelID: testNovelID,
            fetcher: fetcher,
            currentState: nil,
            chapterNumber: 0,
            downloadCount: 0,
            successAction: { novelID, _ in
                XCTAssertEqual(novelID, self.testNovelID)
                exp.fulfill()
            },
            failedAction: { _, _, errorDescription in
                //XCTFail("download failed: \(errorDescription)")
                exp.fulfill()
            }
        )

        wait(for: [exp], timeout: 60.0)

        RealmUtil.RealmBlock { realm in
            print("NDMCT: after:", RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: self.testNovelID))
        }

        RealmUtil.RealmBlock { realm in
            let matrix = RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: self.testNovelID)
            let all = Array(matrix.joined())
            XCTAssertEqual(all.sorted(), Array(self.testChapterRange))
        }

        // 既存章(1,2,3,6,7)が上書きされていないこと
        RealmUtil.RealmBlock { realm in
            for ch in [1, 2, 3, 6, 7] {
                let story = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: self.testNovelID, chapterNumber: ch)
                XCTAssertEqual(story?.content, "edited \(ch)")
            }
        }

        // アクセスされたURLが期待範囲内であることを確認
        let expectedChapterSet = Set(([3, 4, 5] + Array(7...16)).map({ self.chapterUrl($0) }))
        let accessedSet = Set(accessedUrls)
        let unexpected = accessedSet.subtracting(expectedChapterSet).sorted()
        let missing = expectedChapterSet.subtracting(accessedSet).sorted()
        XCTAssertTrue(unexpected.isEmpty, "unexpected accesses: \(unexpected)")
        XCTAssertTrue(missing.isEmpty, "missing accesses: \(missing)")
    }

    // 3. すでに 1〜15 が揃っている状態で再ダウンロードしても 1〜15 のまま変わらないこと
    func testDownloadWhenAlreadyCompleteDoesNotDuplicate() throws {
        // 事前に 1〜15 を全部入れておく
        RealmUtil.Write { realm in
            var stories: [NovelSpeaker.Story] = []
            for ch in self.testChapterRange {
                var s = Story()
                s.novelID = self.testNovelID
                s.chapterNumber = ch
                s.content = "dummy \(ch)"
                s.subtitle = "ch \(ch)"
                s.url = self.chapterUrl(ch)
                s.downloadDate = Date()
                stories.append(s)
            }
            _ = RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: self.testNovelID, storyArray: stories)
        }

        let exp = expectation(description: "download completes")

        let fetcher = StoryFetcher()
        NovelDownloader.startDownload(
            novelID: testNovelID,
            fetcher: fetcher,
            currentState: nil,
            chapterNumber: 0,
            downloadCount: 0,
            successAction: { novelID, _ in
                XCTAssertEqual(novelID, self.testNovelID)
                exp.fulfill()
            },
            failedAction: { _, _, errorDescription in
                //XCTFail("download failed: \(errorDescription)")
                exp.fulfill()
            }
        )

        wait(for: [exp], timeout: 60.0)

        RealmUtil.RealmBlock { realm in
            let matrix = RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: self.testNovelID)
            let all = Array(matrix.joined())
            // 件数と内容が 1〜15 のままか
            XCTAssertEqual(all.count, self.testChapterRange.count)
            XCTAssertEqual(all.sorted(), Array(self.testChapterRange))
        }
    }
}
