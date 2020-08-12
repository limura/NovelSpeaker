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
    
    func testVoice() {
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            if voice.language != "ja-JP" { continue }
            print("voice", voice.name, voice.language, voice.identifier)
        }
        class SpeakerWait : SpeakRangeDelegate{
            let speaker:Speaker = Speaker()
            var isWaiting:Bool = false
            var expectation:XCTestExpectation = XCTestExpectation()
            
            init() {
                speaker.delegate = self
            }
            
            func willSpeakRange(range:NSRange) {}
            func finishSpeak() {
                print("finishSpeak: \(self.speaker.voice.name)")
                isWaiting = false
                expectation.fulfill()
            }
            func setVoiceWith(identifier:String, language:String){
                speaker.SetVoiceWith(identifier:identifier, language:language)
            }
            func Speech(text:String, expectation:XCTestExpectation){
                self.expectation = expectation
                speaker.Speech(text:text)
            }
        }
        
        func speakWithWait(speaker:SpeakerWait, text:String, expectationID: String) {
            let expectation = XCTestExpectation(description: expectationID)
            speaker.Speech(text: text, expectation: expectation)
            wait(for: [expectation], timeout: 10)
        }

        let speaker1 = SpeakerWait()
        let speaker2 = SpeakerWait()
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.siri_male_ja-JP_compact", language: "ja-JP")
        speaker2.setVoiceWith(identifier: "com.apple.ttsbundle.Otoya-compact", language: "ja-JP")

        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.siri_male_ja-JP_compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: " ", expectationID: "x")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.Otoya-compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: " ", expectationID: "y")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.siri_male_ja-JP_compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: "こんにちは。", expectationID: "1")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.Otoya-compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: "京子です。", expectationID: "2")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.siri_male_ja-JP_compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: "2回目の", expectationID: "3")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.Otoya-compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: "発話です", expectationID: "4")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.siri_male_ja-JP_compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: "3回目の", expectationID: "5")
        speaker1.setVoiceWith(identifier: "com.apple.ttsbundle.Otoya-compact", language: "ja-JP")
        speakWithWait(speaker: speaker1, text: "発話ですよ", expectationID: "6")
    }
    
    func testSkip() {
        let story = RealmStoryBulk.SearchStory(novelID: "https://ncode.syosetu.com/n6475db/", chapterNumber:431) ?? Story()
        let speaker = StorySpeaker.shared
        speaker.SetStory(story: story)
        print("location: \(speaker.readLocation)")
        speaker.SkipForward(length: 50)
        print("location: \(speaker.readLocation)")
        speaker.SkipBackward(length: 50)
        print("location: \(speaker.readLocation)")
    }
}
