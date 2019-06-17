//
//  RealmTests.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2019/06/17.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import XCTest
import RealmSwift
@testable import NovelSpeaker

class RealmTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
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
    
    func testLeakTest() {
        let downloadQueue = NovelDownloadQueue.shared
        if let novels = RealmNovel.GetAllObjects() {
            for novel in novels {
                downloadQueue.addQueue(novelID: novel.novelID)
            }
        }
        while true {
            NiftyUtilitySwift.RunLoopSleep(deltaSecond: 1)
        }
    }

}
