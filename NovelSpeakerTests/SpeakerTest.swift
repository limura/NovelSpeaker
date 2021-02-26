//
//  SpeakerTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import XCTest
import AVFoundation
import RealmSwift
@testable import NovelSpeaker

class SpeakerTest: XCTestCase {
    var speaker = SpeechBlockSpeaker()

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        speaker = SpeechBlockSpeaker()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

}
