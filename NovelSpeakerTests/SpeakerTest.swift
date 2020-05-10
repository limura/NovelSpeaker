//
//  SpeakerTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import XCTest
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

    func testSpeechBlockSpeaker() {
        var story = Story()
        story.content = """
        吾輩は猫である。名前はまだ無い。
        　どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。吾輩はここで始めて人間というものを見た。しかもあとで聞くとそれは書生という人間中で一番獰悪な種族であったそうだ。
        """
        speaker.SetStory(story: story)
        speaker.StartSpeech()
        
        let exp = expectation(description: "wait")
        wait(for: [exp], timeout: 10.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
            exp.fulfill()
        }
    }
    
    func testSpeechLocation() {
        let speaker = StorySpeaker.shared
        var story = Story()
        story.content = """
        「ふぁ……」
         
        　まだ日も昇らないうちから、バルトロメイは目を覚まし、寝台から体を起こす。
        　軍に所属している者の朝は早い。少なくとも新兵訓練を受けた者は、日が昇る前から教官に叩き起こされるのが常である。そして、その後も部隊に入ってから何度も訓練を重ね、実戦においては満足に睡眠を取ることも難しい場合もあるため、このように早起きが習慣となってしまうのだ。
        　昨日は酒を飲んだためか、やや頭に鈍痛が残っているのが分かる。しかし、かといってこれ以上眠ることはできないだろう。軍人としての性もそうだが、四十を迎えた体ではなかなか二度寝も難しいのだ。
        """
        speaker.withMoreSplitTargets = ["。", ".", "\n"]
        speaker.moreSplitMinimumLetterCount = 30
        speaker.SetStory(story: story)
        let blockArray = speaker.speechBlockArray
        print("currentBlockIndex: \(speaker.currentBlockIndex)")
        speaker.speaker.SetSpeechLocation(location: 30)
        print("currentBlockIndex: \(speaker.currentBlockIndex)")
        for block in blockArray {
            print("---\n\(block.displayText)\n")
        }
    }
}
