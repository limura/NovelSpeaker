//
//  StorySpeaker.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/19.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift
import MediaPlayer

protocol StorySpeakerDeletgate {
    func storySpeakerStartSpeechEvent(storyID:String)
    func storySpeakerStopSpeechEvent(storyID:String)
    func storySpeakerUpdateReadingPoint(storyID:String, range:NSRange)
    func storySpeakerStoryChanged(story:RealmStory)
}

class AnnounceSpeakerHolder: NSObject {
    let speaker = Speaker()
    func Speech(text:String) {
        guard let defaultSpeechConfig = RealmGlobalState.GetInstance()?.defaultSpeaker else {
            speaker.speech(text)
            return
        }
        defaultSpeechConfig.applyTo(speaker: speaker)
        speaker.speech(text)
    }
}

class StorySpeaker: NSObject, SpeakRangeDelegate {
    
    let speaker = NiftySpeaker()
    let announceSpeakerHolder = AnnounceSpeakerHolder()
    var delegateArray = NSHashTable<AnyObject>.weakObjects()

    var storyID:String = ""
    
    
    override init() {
        super.init()
        EnableMPRemoteCommandCenterEvents()
        speaker.add(self)
    }
    
    deinit {
        DisableMPRemoteCommandCenterEvents()
    }

    // 読み上げに用いられる小説の章を設定します。
    // 読み上げが行われていた場合、読み上げは停止します。
    func SetStory(story:RealmStory) {
        speaker.stopSpeech()
        guard let content = story.content else { return }
        self.storyID = story.id
        updateReadDate(story: story)
        speaker.clearSpeakSettings()
        applySpeechConfig(novelID: story.novelID)
        applySpeechModSetting(novelID: story.novelID, targetText: content)
        speaker.setText(ForceOverrideHungSpeakString(text: content))
        speaker.updateCurrentReadingPoint(NSRange(location: story.readLocation, length: 0))
        updatePlayngInfo(story: story)
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStoryChanged(story: story)
        }
    }
    
    func ForceOverrideHungSpeakString(text:String) -> String {
        return text.replacingOccurrences(of: "*", with: " ")
    }
    
    func AddDelegate(delegate:StorySpeakerDeletgate) {
        self.delegateArray.add(delegate as AnyObject)
    }
    func RemoveDelegate(delegate:StorySpeakerDeletgate) {
        self.delegateArray.remove(delegate as AnyObject)
    }
    
    func updateReadDate(story:RealmStory) {
        if let realm = try? RealmUtil.GetRealm(), let story = realm.object(ofType: RealmStory.self, forPrimaryKey: story.id) {
            try! realm.write {
                story.lastReadDate = Date()
            }
        }
    }
    
    func applySpeechConfig(novelID:String) {
        guard let defaultSpeakerSetting = RealmGlobalState.GetInstance()?.defaultSpeaker else { return }
        speaker.setDefaultSpeechConfig(defaultSpeakerSetting.speechConfig)
        guard let speechSectionConfigArray = RealmSpeechSectionConfig.GetAllObjects()?.filter({ (sectionConfig) -> Bool in
            return sectionConfig.targetNovelIDArray.count <= 0 || sectionConfig.targetNovelIDArray.contains(novelID)
        }) else { return }
        for sectionConfig in speechSectionConfigArray {
            guard let speakerSetting = sectionConfig.speaker else { continue }
            speaker.addBlockStartSeparator(sectionConfig.startText, end: sectionConfig.endText, speechConfig: speakerSetting.speechConfig)
        }
    }
    
    func applySpeechModSetting(novelID:String, targetText:String) {
        var isOverrideRubyEnabled = false
        var notRubyCharactorStringArray = ""
        var isIgnoreURIStringSpeechEnabled = false
        
        if let globalState = RealmGlobalState.GetInstance() {
            if let speechOverrideSetting = globalState.defaultSpeechOverrideSetting {
                isOverrideRubyEnabled = speechOverrideSetting.isOverrideRubyIsEnabled
                notRubyCharactorStringArray = speechOverrideSetting.notRubyCharactorStringArray
                isIgnoreURIStringSpeechEnabled = speechOverrideSetting.isIgnoreURIStringSpeechEnabled
            }
        }
        if let settingArray = RealmSpeechOverrideSetting.SearchObjectFrom(novelID: novelID) {
            for speechOverrideSetting in settingArray {
                isOverrideRubyEnabled = speechOverrideSetting.isOverrideRubyIsEnabled
                notRubyCharactorStringArray = speechOverrideSetting.notRubyCharactorStringArray
                isIgnoreURIStringSpeechEnabled = speechOverrideSetting.isIgnoreURIStringSpeechEnabled
            }
        }
        
        if isOverrideRubyEnabled {
            if let rubyDictionary = StringSubstituter.findNarouRubyNotation(targetText, notRubyString: notRubyCharactorStringArray) {
                for key in rubyDictionary.keys {
                    if let from = key as? String, let to = rubyDictionary[key] as? String {
                        speaker.addSpeechModText(from, to: to)
                    }
                }
            }
        }
        
        if isIgnoreURIStringSpeechEnabled {
            if let uriStringArray = StringSubstituter.findURIStrings(targetText) {
                for uriString in uriStringArray {
                    if let uriString = uriString as? String {
                        speaker.addSpeechModText(uriString, to: " ")
                    }
                }
            }
        }
        
        if let speechModSettingArray = RealmSpeechModSetting.GetAllObjects()?.filter({ (setting) -> Bool in
            return setting.targetNovelIDArray.count <= 0 || setting.targetNovelIDArray.contains(novelID)
        }) {
            for setting in speechModSettingArray {
                if setting.isUseRegularExpression {
                    guard let modSettingArray = StringSubstituter.findRegexpSpeechModConfigs(targetText, pattern: setting.before, to: setting.after) else { continue }
                    for modSetting in modSettingArray {
                        guard let modSetting = modSetting as? SpeechModSetting else { continue }
                        speaker.addSpeechModText(modSetting.beforeString, to: modSetting.afterString)
                    }
                }else{
                    speaker.addSpeechModText(setting.before, to: setting.after)
                }
            }
        }
    }
    
    func StartSpeech() {
        if let story = RealmStory.SearchStoryFrom(storyID: self.storyID) {
            updatePlayngInfo(story: story)
        }
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStartSpeechEvent(storyID: self.storyID)
        }
        speaker.startSpeech()
    }
    // 読み上げを停止します。読み上げ位置が更新されます。
    func StopSpeech() {
        speaker.stopSpeech()
        self.readLocation = speaker.getCurrentReadingPoint().location
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStopSpeechEvent(storyID: self.storyID)
        }
    }
    
    func SkipForward(length:Int) {
        guard let story = RealmStory.SearchStoryFrom(storyID: self.storyID) else {
            return
        }
        let readingPoint = speaker.getCurrentReadingPoint().location
        let nextReadingPoint = readingPoint + length
        let contentLength = story.content?.count ?? 0
        if nextReadingPoint > contentLength {
            LoadNextChapter()
        }else{
            speaker.updateCurrentReadingPoint(NSRange(location: nextReadingPoint, length: 0))
        }
    }
    func SkipBackward(length:Int){
        let readingPoint = speaker.getCurrentReadingPoint().location
        if readingPoint >= length {
            speaker.updateCurrentReadingPoint(NSRange(location: length - readingPoint, length: 0))
            return
        }
        var targetLength = length - readingPoint
        var targetStory = SearchPreviousChapter(storyID: self.storyID)
        while let story = targetStory {
            let contentLength = story.content?.count ?? 0
            if targetLength <= contentLength {
                if let realm = try? RealmUtil.GetRealm() {
                    try! realm.write {
                        story.readLocation = contentLength - targetLength
                    }
                }
                SetStory(story: story)
                return
            }
            targetStory = SearchPreviousChapter(storyID: story.id)
            targetLength -= contentLength
        }
        // 抜けてきたということは先頭まで行ってしまった。
        if let firstStory = RealmStory.GetAllObjects()?.filter("chapterNumber = 1 AND novelID = %@", RealmStory.StoryIDToNovelID(storyID: self.storyID)).first {
            if let realm = try? RealmUtil.GetRealm() {
                try! realm.write {
                    firstStory.readLocation = 0
                }
            }
            SetStory(story: firstStory)
        }
    }
    
    func SearchNextChapter(storyID:String) -> RealmStory? {
        guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else {
            return nil
        }
        let nextChapterNumber = story.chapterNumber + 1
        if let nextStory = RealmStory.GetAllObjects()?.filter("novelID = %@ AND chapterNumber = %@", story.novelID, nextChapterNumber).first {
            return nextStory
        }
        return nil
    }
    @discardableResult
    func LoadNextChapter() -> Bool{
        if let nextStory = SearchNextChapter(storyID: self.storyID) {
            if let realm = try? RealmUtil.GetRealm() {
                try! realm.write {
                    nextStory.readLocation = 0
                }
            }
            SetStory(story: nextStory)
            return true
        }
        return false
    }

    func SearchPreviousChapter(storyID:String) -> RealmStory? {
        guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else {
            return nil
        }
        let previousChapterNumber = story.chapterNumber - 1
        if previousChapterNumber <= 0 {
            return nil
        }
        if let previousStory = RealmStory.GetAllObjects()?.filter("novelID = %@ AND chapterNumber = %@", story.novelID, previousChapterNumber).first {
            return previousStory
        }
        return nil
    }
    @discardableResult
    func LoadPreviousChapter() -> Bool{
        if let previousStory = SearchPreviousChapter(storyID: storyID) {
            if let realm = try? RealmUtil.GetRealm() {
                try! realm.write {
                    previousStory.readLocation = 0
                }
            }
            SetStory(story: previousStory)
            return true
        }
        return false
    }
    
    func updatePlayngInfo(story:RealmStory) {
        let titleName:String
        let writer:String
        if let novel = story.owner {
            let lastChapterNumber:Int
            if let n = novel.lastChapterNumber {
                lastChapterNumber = n
            }else{
                lastChapterNumber = 0
            }
            titleName = "\(novel.title) (\(story.chapterNumber)/\(lastChapterNumber))"
            writer = novel.writer
        }else{
            titleName = NSLocalizedString("GlobalDataSingleton_NoPlaing", comment: "再生していません")
            writer = "-"
        }
        var songInfo:[String:Any] = [
            MPMediaItemPropertyTitle: titleName,
            MPMediaItemPropertyArtist: writer
        ]
        if RealmGlobalState.GetInstance()?.isPlaybackDurationEnabled ?? false {
            let textLength:Int
            if let content = story.content {
                textLength = content.count
            }else{
                textLength = 0
            }
            if let speakerSetting = RealmGlobalState.GetInstance()?.defaultSpeaker {
                let duration = GuessSpeakDuration(textLength: textLength, speechConfig: speakerSetting)
                let position = GuessSpeakDuration(textLength: story.readLocation, speechConfig: speakerSetting)
                songInfo[MPMediaItemPropertyPlaybackDuration] = duration
                songInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
                songInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
            }
        }
        if let image = UIImage.init(named: "NovelSpeakerIcon-167px.png") {
            let artWork = MPMediaItemArtwork.init(boundsSize: image.size) { (size) -> UIImage in
                return image.resize(newSize: size)
            }
            songInfo[MPMediaItemPropertyArtwork] = artWork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = songInfo
    }
    
    func GuessSpeakDuration(textLength:Int, speechConfig:RealmSpeakerSetting?) -> Float {
        guard let speechConfig = speechConfig else { return 0.0 }
        let charCount = self.SpeechRateToCharCountInSecond(rate: speechConfig.rate)
        return Float(textLength) / charCount;
    }
    
    func GuessSpeakLocationFromDulation(dulation:Float, speechConfig:RealmSpeakerSetting) -> Int {
        let rate = speechConfig.rate
        let charCount = self.SpeechRateToCharCountInSecond(rate: rate)
        return Int(dulation * charCount)
    }
    
    
    func SpeechRateToCharCountInSecond(rate:Float) -> Float {
        let rateNormalized = (rate - AVSpeechUtteranceMinimumSpeechRate) / (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate);
        
        // 下に膨らんでる感じの補正をかける
        let rateCurved = powf(rateNormalized, 2.8);
        //NSLog(@"rateNormalized: %f -> %f", rateNormalized, rateCurved);
        // XXXX: ここ書かれている謎の値は
        // 単に rate を AVSpeechUtteranceMinimumSpeechRate(0.0) にした時と
        // AVSpeechUtteranceMaximumSpeechRate(1.0) にした時のそれぞれである程度の文字数を読み上げさせてみて、時間を測って出した値なのでまぁぶっちゃけ駄目。
        let charCount = rateCurved * 20.72 + 2.96;
        return charCount
    }
    
    func EnableMPRemoteCommandCenterEvents() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.addTarget(self, action: #selector(togglePlayPauseEvent(_:)))
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.playCommand.addTarget(self, action: #selector(playEvent(_:)))
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget(self, action: #selector(stopEvent(_:)))
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.stopCommand.addTarget(self, action: #selector(stopEvent(_:)))
        commandCenter.stopCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget(self, action: #selector(nextTrackEvent(_:)))
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget(self, action: #selector(previousTrackEvent(_:)))
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.seekForwardCommand.addTarget(self, action: #selector(seekForwardEvent(event:)))
        commandCenter.seekForwardCommand.isEnabled = true
        commandCenter.seekBackwardCommand.addTarget(self, action: #selector(seekBackwardEvent(event:)))
        commandCenter.seekBackwardCommand.isEnabled = true
        if let globalState = RealmGlobalState.GetInstance() {
            if globalState.isShortSkipEnabled {
                commandCenter.skipForwardCommand.addTarget(self, action: #selector(skipForwardEvent(_:)))
                commandCenter.skipForwardCommand.isEnabled = true
                commandCenter.skipBackwardCommand.addTarget(self, action: #selector(skipBackwardEvent(_:)))
                commandCenter.skipBackwardCommand.isEnabled = true
            }
            if globalState.isPlaybackDurationEnabled {
                commandCenter.changePlaybackPositionCommand.addTarget(self, action: #selector(changePlaybackPositionEvent(event:)))
                commandCenter.changePlaybackPositionCommand.isEnabled = true
            }
        }
    }
    
    func DisableMPRemoteCommandCenterEvents() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.removeTarget(self)
        commandCenter.togglePlayPauseCommand.isEnabled = false
        commandCenter.playCommand.removeTarget(self)
        commandCenter.playCommand.isEnabled = false
        commandCenter.pauseCommand.removeTarget(self)
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.stopCommand.removeTarget(self)
        commandCenter.stopCommand.isEnabled = false
        commandCenter.nextTrackCommand.removeTarget(self)
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.removeTarget(self)
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.removeTarget(self)
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.removeTarget(self)
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.skipForwardCommand.removeTarget(self)
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.removeTarget(self)
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.removeTarget(self)
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }
    
    // MARK: MPCommandCenter commands
    @objc func playEvent(_ sendor:MPRemoteCommandCenter) {
        StartSpeech()
    }
    @objc func stopEvent(_ sendor:MPRemoteCommandCenter) {
        StopSpeech()
    }
    @objc func togglePlayPauseEvent(_ sendor:MPRemoteCommandCenter) {
        if speaker.isSpeaking() {
            StopSpeech()
        }else{
            StartSpeech()
        }
    }
    @objc func nextTrackEvent(_ sendor:MPRemoteCommandCenter) {
        StopSpeech()
        if LoadNextChapter() {
            StartSpeech()
        }
    }
    @objc func previousTrackEvent(_ sendor:MPRemoteCommandCenter) {
        StopSpeech()
        if LoadPreviousChapter() {
            StartSpeech()
        }
    }
    @objc func skipForwardEvent(_ sendor:MPRemoteCommandCenter) {
        StopSpeech()
        SkipForward(length: 100)
        StartSpeech()
    }
    @objc func skipBackwardEvent(_ sendor:MPRemoteCommandCenter) {
        StopSpeech()
        SkipBackward(length: 100)
        StartSpeech()
    }
    
    var isSeeking = false
    @objc func seekForwardEvent(event:MPSeekCommandEvent?) {
        if event?.type == MPSeekCommandEventType.endSeeking {
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            announceSpeakerHolder.Speech(text: NSLocalizedString("SpeechViewController_AnnounceSeekForward", comment: "早送り"))
            self.isSeeking = true
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
                if !self.isSeeking {
                    timer.invalidate()
                    return
                }
                self.StopSpeech()
                self.SkipForward(length: 50)
                DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: 200), execute: {
                    self.StartSpeech()
                })
            }
        }
    }
    @objc func seekBackwardEvent(event:MPSeekCommandEvent?) {
        if event?.type == MPSeekCommandEventType.endSeeking {
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            announceSpeakerHolder.Speech(text: NSLocalizedString("SpeechViewController_AnnounceSeekBackward", comment: "巻き戻し"))
            self.isSeeking = true
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
                if !self.isSeeking {
                    timer.invalidate()
                    return
                }
                self.StopSpeech()
                self.SkipBackward(length: 50)
                DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: 200), execute: {
                    self.StartSpeech()
                })
            }
        }
    }
    @objc func changePlaybackPositionEvent(event:MPChangePlaybackPositionCommandEvent?) -> MPRemoteCommandHandlerStatus {
        guard let event = event, let defaultSpeakerSetting = RealmGlobalState.GetInstance()?.defaultSpeaker, let story = RealmStory.SearchStoryFrom(storyID: self.storyID), let contentLength = story.content?.count else {
            return MPRemoteCommandHandlerStatus.commandFailed
        }
        
        print("MPChangePlaybackPositionCommandEvent in: \(event.positionTime)")
        var newLocation = self.GuessSpeakLocationFromDulation(dulation: Float(event.positionTime), speechConfig: defaultSpeakerSetting)
        let textLength = contentLength
        if newLocation > textLength {
            newLocation = textLength
        }
        if newLocation <= 0 {
            newLocation = 0
        }
        
        StopSpeech()
        self.readLocation = newLocation
        DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: 200), execute: {
            self.StartSpeech()
        })
        return MPRemoteCommandHandlerStatus.success
    }
    
    // MARK: SpeakRangeDeleate implement
    func willSpeak(_ range: NSRange, speakText text: String!) {
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerUpdateReadingPoint(storyID: self.storyID, range: range)
        }
    }
    
    func finishSpeak() {
        self.readLocation = speaker.getCurrentReadingPoint().location
        guard let globalState = RealmGlobalState.GetInstance(), let speechOverrideSetting = globalState.defaultSpeechOverrideSetting else {
            return
        }
        switch speechOverrideSetting.repeatSpeechType {
        case .rewindToFirstStory:
            let novelID = RealmStory.StoryIDToNovelID(storyID: self.storyID)
            if let novel = RealmNovel.SearchNovelFrom(novelID: novelID), let lastChapterNumber = novel.lastChapterNumber, let currentChapterNumber = RealmStory.SearchStoryFrom(storyID: self.storyID)?.chapterNumber, lastChapterNumber == currentChapterNumber, let targetStory = RealmStory.SearchStoryFrom(storyID: RealmStory.CreateUniqueID(novelID: novelID, chapterNumber: 1)) {
                self.SetStory(story: targetStory)
                self.StartSpeech()
                return
            }
        case .rewindToThisStory:
            self.readLocation = 0
            self.StartSpeech()
            return
        case .noRepeat:
            break
        @unknown default:
            break
        }
        if let nextStory = SearchNextChapter(storyID: self.storyID) {
            self.SetStory(story: nextStory)
            self.StartSpeech()
        }
    }
    
    var isPlayng : Bool {
        get {
            return speaker.isSpeaking()
        }
    }
    
    var readLocation : Int {
        get {
            return speaker.getCurrentReadingPoint().location
        }
        set {
            if let realm = try? RealmUtil.GetRealm(), let story = RealmStory.SearchStoryFrom(storyID: self.storyID), let contentLength = story.content?.count, contentLength >= newValue && newValue > 0 {
                try! realm.write {
                    story.readLocation = newValue
                }
            }
        }
    }
}
