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
    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testStorySpeakerBlock() {
        let targetText = """
あいうえお「あいうえお。あいうえお」あいうえお。あいうえお！あいうえお、あいうえお。
あいうえお。あいうえお！あいうえお あいうえお！あいうえお あいうえお！あいうえお あいうえお！あいうえお、あいうえお。
「俺様『は』負けない」「と思う「んだわ。」』です。
ルビを|降ってみる(ふってみる)のテスト(ルビ)、ああ播磨灘(はりまなだ)、|ルビにはならない何か(・・・・・・・・)。終了！
"""
        let defaultSpeakerSetting = RealmSpeakerSetting()
        defaultSpeakerSetting.name = "defaultSpeakerConfig"
        let sectionConfig1 = SpeechSectionConfig(startText: "「", endText: "」", speakerSetting: RealmSpeakerSetting())
        sectionConfig1.speakerSetting.name = "sectionConfig1"
        let sectionConfig2 = SpeechSectionConfig(startText: "『", endText: "』", speakerSetting: RealmSpeakerSetting())
        sectionConfig2.speakerSetting.name = "sectionConfig2"
        let sectionConfigArray = [sectionConfig1, sectionConfig2]
        
        let waitConfig1 = RealmSpeechWaitConfig()
        waitConfig1.targetText = "。"
        waitConfig1.delayTimeInSec = 0.2
        let waitConfig2 = RealmSpeechWaitConfig()
        waitConfig2.targetText = "、"
        waitConfig2.delayTimeInSec = 0.1
        let waitConfigArray = [waitConfig1, waitConfig2]
        
        let modSetting1 = RealmSpeechModSetting()
        modSetting1.before = "うえお"
        modSetting1.after = "植尾"
        let modSetting2 = RealmSpeechModSetting()
        modSetting2.before = "あい"
        modSetting2.after = "愛"
        let modSetting3 = RealmSpeechModSetting()
        modSetting3.before = "！"
        modSetting3.after = "_。_。"
        var modSettingArray =  [modSetting1, modSetting2, modSetting3]
        modSettingArray.append(contentsOf: StoryTextClassifier.GenerateRubyModString(text:targetText, notRubyString:"・、 　！!"))

        let result = StoryTextClassifier.CategorizeStoryText(content:targetText,    withMoreSplitTargets:["。", "、", "！"], moreSplitMinimumLetterCount:20, defaultSpeaker:defaultSpeakerSetting, sectionConfigList:sectionConfigArray, waitConfigList:waitConfigArray, sortedSpeechModArray:modSettingArray)
        for item in result {
            print("\(item.voice?.identifier ?? "unknown or nil"), \(item.delay): \(item.displayText) -> \(item.speechText)")
            print("---")
        }
    }
    
    let speaker = SpeechBlockSpeaker()
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
}
