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
    func storySpeakerStoryChanged(story:Story)
}

class StorySpeaker: NSObject, SpeakRangeDelegate {
    static let shared = StorySpeaker()
    
    let speaker = SpeechBlockSpeaker()
    let dummySoundLooper = DummySoundLooper()
    let pageTurningSoundPlayer = DuplicateSoundPlayer()
    var delegateArray = NSHashTable<AnyObject>.weakObjects()

    var storyID:String = ""
    var globalStateObserveToken:NotificationToken? = nil
    var storyObserverToken:NotificationToken? = nil
    var storyObserverStoryID:String = ""
    var storyObserverStoryBulkID:String = ""
    var defaultSpeakerSettingObserverToken:NotificationToken? = nil
    var speechSectionConfigArrayObserverToken:NotificationToken? = nil
    var defaultSpeechOverrideSettingObserverToken:NotificationToken? = nil
    var novelIDSpeechOverrideSettingArrayObserverToken:NotificationToken? = nil
    var speechModSettingArrayObserverToken:NotificationToken? = nil
    var bookmarkObserverToken:NotificationToken? = nil
    var bookmarkObserverNovelID:String = ""
    var maxSpeechInSecTimer:Timer? = nil
    var isMaxSpeechTimeExceeded = false
    var isNeedApplySpeechConfigs = true
    
    // SpeechBlockSpeaker 内部で分割されているblockの大きさを制御する値なのだけれど、
    // 残念なことに StorySpeaker は次の Story を自動で読み込んで SpeechBlockSpeakr に渡す事をするため、
    // この制御値を保存しておく必要があります。
    var withMoreSplitTargets:[String] = []
    var moreSplitMinimumLetterCount:Int = Int.max

    private override init() {
        super.init()
        EnableMPRemoteCommandCenterEvents()
        speaker.delegate = self
        audioSessionInit(isActive: false)
        observeGlobalState()
        dummySoundLooper.setMediaFile(forResource: "Silent3sec", ofType: "mp3")
        if !pageTurningSoundPlayer.setMediaFile(forResource: "nc48625", ofType: "m4a", maxDuplicateCount: 1) {
            print("pageTurningSoundPlayer load media failed.")
        }
    }
    
    deinit {
        DisableMPRemoteCommandCenterEvents()
        unregistAudioNotifications()
    }
    
    func ApplyStoryToSpeaker(story:Story, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int) {
        speaker.SetStory(story: story, withMoreSplitTargets:withMoreSplitTargets, moreSplitMinimumLetterCount:moreSplitMinimumLetterCount)
        observeSpeechConfig(novelID: story.novelID)
        observeSpeechModSetting(novelID: story.novelID)
        speaker.SetSpeechLocation(location: story.readLocation)
        self.isNeedApplySpeechConfigs = false
    }

    // 読み上げに用いられる小説の章を設定します。
    // 読み上げが行われていた場合、読み上げは停止します。
    func SetStory(story:Story) {
        speaker.StopSpeech()
        let storyID = story.storyID
        autoreleasepool {
            self.storyID = storyID
            updateReadDate(storyID: storyID)
            ApplyStoryToSpeaker(story: story, withMoreSplitTargets: withMoreSplitTargets, moreSplitMinimumLetterCount: moreSplitMinimumLetterCount)
            //updatePlayngInfo(story: story)
            observeStory(storyID: self.storyID)
            observeBookmark(novelID: story.novelID)
            for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
                delegate.storySpeakerStoryChanged(story: story)
            }
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
    
    func registerAudioNotifications() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(audioSessionDidInterrupt(notification:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(didChangeAudioSessionRoute(notification:)), name:    AVAudioSession.routeChangeNotification, object: nil)
    }
    func unregistAudioNotifications() {
        let center = NotificationCenter.default
        center.removeObserver(self)
    }
    func observeGlobalState() {
        DispatchQueue.main.async {
            guard let globalState = RealmGlobalState.GetInstance() else {
                return
            }
            self.globalStateObserveToken = globalState.observe({ (change) in
                switch change {
                case .change(let propertys):
                    for property in propertys {
                        if property.name == "isMixWithOthersEnabled" || property.name == "isDuckOthersEnabled" {
                            guard let oldValue = property.oldValue as? Bool, let newValue = property.newValue as? Bool else { continue }
                            if oldValue != newValue {
                                self.audioSessionInit(isActive: false)
                                break
                            }
                        }else if property.name == "isPlaybackDurationEnabled" || property.name == "isShortSkipEnabled" {
                            self.DisableMPRemoteCommandCenterEvents()
                            self.EnableMPRemoteCommandCenterEvents()
                            autoreleasepool {
                                if property.name == "isPlaybackDurationEnabled" && self.speaker.isSpeaking, let story = RealmStoryBulk.SearchStory(storyID: self.storyID) {
                                    self.updatePlayngInfo(story: story)
                                }
                            }
                        }
                    }
                default:
                    break
                }
            })
        }
    }
    func observeBookmark(novelID:String) {
        DispatchQueue.main.async {
            if self.bookmarkObserverNovelID == novelID { return }
            self.bookmarkObserverNovelID = novelID
            guard let bookmark = RealmBookmark.SearchObjectFrom(type: .novelSpeechLocation, hint: novelID) else { return }
            self.bookmarkObserverToken = bookmark.observe { (change) in
                switch change {
                case .change(let properties):
                    for property in properties {
                        if property.name == "location", let newObj = property.newValue as? RealmBookmark, newObj.chapterNumber == RealmStoryBulk.StoryIDToChapterNumber(storyID: self.storyID), self.speaker.currentLocation != newObj.location {
                            self.speaker.SetSpeechLocation(location: newObj.location)
                        }
                    }
                default:
                    break
                }
            }
        }
    }
    
    func observeStory(storyID:String) {
        DispatchQueue.main.async {
            if self.storyObserverStoryID == storyID { return }
            let targetBulkID = RealmStoryBulk.CreateUniqueBulkID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), chapterNumber: RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID))
            if self.storyObserverStoryBulkID == targetBulkID { return }
            self.storyObserverStoryID = storyID
            self.storyObserverStoryBulkID = targetBulkID
            autoreleasepool {
            guard let storyBulk = RealmStoryBulk.SearchStoryBulk(storyID: storyID) else { return }
                let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
                self.storyObserverToken = storyBulk.observe({ (change) in
                    switch change {
                    case .error(_):
                        break
                    case .change(let properties):
                        for property in properties {
                            if property.name == "contentArray", let newValue = property.newValue as? List<Data>, let story = RealmStoryBulk.BulkToStory(bulk: newValue, chapterNumber: chapterNumber) {
                                let text = self.speaker.displayText
                                if text != story.content {
                                    DispatchQueue.global(qos: .background).async {
                                        self.speaker.SetStory(story: story)
                                    }
                                }
                            }
                        }
                    case .deleted:
                        break
                    }
                })
            }
        }
    }
    
    @objc func audioSessionDidInterrupt(notification:Notification) {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            return
        }
        if type.intValue == Int(AVAudioSession.InterruptionType.began.rawValue) {
            self.dummySoundLooper.stopPlay()
        }else if type.intValue == Int(AVAudioSession.InterruptionType.ended.rawValue) {
            self.dummySoundLooper.startPlay()
        }
    }
    @objc func didChangeAudioSessionRoute(notification:Notification) {
        func isJointHeadphone(outputs:[AVAudioSessionPortDescription]) -> Bool {
            for desc in outputs {
                if desc.portType == AVAudioSession.Port.headphones
                    || desc.portType == AVAudioSession.Port.bluetoothA2DP
                    || desc.portType == AVAudioSession.Port.bluetoothHFP {
                    return true
                }
            }
            return false
        }
        guard let previousDesc = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else {
            return
        }
        if isJointHeadphone(outputs: AVAudioSession.sharedInstance().currentRoute.outputs) {
            if !isJointHeadphone(outputs: previousDesc.outputs) {
                // ヘッドフォンが刺さった
            }
        }else{
            if !isJointHeadphone(outputs: previousDesc.outputs) {
                // ヘッドフォンが抜けた
                StopSpeech()
                SkipBackward(length: 25)
                self.readLocation = speaker.currentLocation
            }
        }
    }
    
    func updateReadDate(storyID:String) {
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        DispatchQueue.main.async {
            RealmUtil.Write { (realm) in
                if let novel = RealmNovel.SearchNovelFrom(novelID: novelID) {
                    novel.lastReadDate = Date()
                    novel.m_readingChapterStoryID = storyID
                }
                autoreleasepool {
                    if let globalState = RealmGlobalState.GetInstance() {
                        if globalState.currentReadingNovelID != novelID {
                            globalState.currentReadingNovelID = novelID
                        }
                    }
                }
            }
        }
    }
    
    func observeSpeechConfig(novelID:String) {
        DispatchQueue.main.async {
            autoreleasepool {
                guard let defaultSpeakerSetting = RealmGlobalState.GetInstance()?.defaultSpeaker else { return }
                self.defaultSpeakerSettingObserverToken = defaultSpeakerSetting.observe { (change) in
                    self.isNeedApplySpeechConfigs = true
                }
            }
            autoreleasepool {
                guard let allSpeechSectionConfigArray = RealmSpeechSectionConfig.GetAllObjects() else { return }
                self.speechSectionConfigArrayObserverToken = allSpeechSectionConfigArray.observe({ (change) in
                    switch change {
                    case .initial(_):
                        break
                    case .update(let sectionConfigArray, let deletions, _, _):
                        if deletions.count > 0 {
                            self.isNeedApplySpeechConfigs = true
                            return
                        }
                        for sectionConfig in sectionConfigArray {
                            if sectionConfig.targetNovelIDArray.count <= 0 || sectionConfig.targetNovelIDArray.contains(novelID) {
                                self.isNeedApplySpeechConfigs = true
                                return
                            }
                        }
                    case .error(_):
                        break
                    }
                })
            }
        }
    }
    
    func observeSpeechModSetting(novelID:String) {
        DispatchQueue.main.async {
            if let globalState = RealmGlobalState.GetInstance(), let speechOverrideSetting = globalState.defaultSpeechOverrideSetting {
                self.defaultSpeechOverrideSettingObserverToken = speechOverrideSetting.observe({ (change) in
                    switch change {
                    case .error(_):
                        break
                    case .change(let properties):
                        for property in properties {
                            if ["isOverrideRubyIsEnabled", "notRubyCharactorStringArray", "isIgnoreURIStringSpeechEnabled"].contains(property.name) {
                                self.isNeedApplySpeechConfigs = true
                                return
                            }
                        }
                    case .deleted:
                        break
                    }
                })
            }
        }
        DispatchQueue.main.async {
            self.novelIDSpeechOverrideSettingArrayObserverToken = RealmSpeechOverrideSetting.GetAllObjects()?.observe({ (change) in
                switch change {
                case .initial(_):
                    break
                case .update(let speechOverrideSettingArray, let deletions, _, _):
                    if deletions.count > 0 {
                        self.isNeedApplySpeechConfigs = true
                        return
                    }
                    for setting in speechOverrideSettingArray {
                        if setting.targetNovelIDArray.contains(novelID) {
                            self.isNeedApplySpeechConfigs = true
                            return
                        }
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    func audioSessionInit(isActive:Bool) {
        var option:UInt = 0
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else { return }
            if globalState.isMixWithOthersEnabled {
                option = AVAudioSession.CategoryOptions.mixWithOthers.rawValue
                if globalState.isDuckOthersEnabled {
                    option |= AVAudioSession.CategoryOptions.duckOthers.rawValue
                }
            }
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(AVAudioSession.Category.playback, options: AVAudioSession.CategoryOptions(rawValue: option))
        }catch{
            print("AVAudioSession setCategory(playback) failed.")
        }
        do {
            try session.setMode(AVAudioSession.Mode.default)
        }catch{
            print("AVAudioSession setMode(default) failed.")
        }
        do {
            let options:AVAudioSession.SetActiveOptions
            if isActive {
                options = []
            }else{
                options = [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation]
            }
            try session.setActive(isActive, options: options)
        }catch{
            print("AVAudioSession setActive(\(isActive ? "true" : "false")) failed.")
        }
    }
    
    func AnnounceSpeech(text:String) {
        speaker.StopSpeech()
        speaker.AnnounceText(text: text)
    }
    
    func StartSpeech(withMaxSpeechTimeReset:Bool) {
        if (self.isMaxSpeechTimeExceeded && (!withMaxSpeechTimeReset)) {
            return
        }
        autoreleasepool {
            if let story = RealmStoryBulk.SearchStory(storyID: self.storyID) {
                updatePlayngInfo(story: story)
                // story をここでも参照するので怪しくこの if の中に入れます
                if self.isNeedApplySpeechConfigs {
                    self.ApplyStoryToSpeaker(story: story, withMoreSplitTargets: self.withMoreSplitTargets, moreSplitMinimumLetterCount: self.moreSplitMinimumLetterCount)
                }
            }
        }
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStartSpeechEvent(storyID: self.storyID)
        }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true, options: [])
        }catch{
            print("audioSession.setActive(true) failed")
        }
        if withMaxSpeechTimeReset {
            startMaxSpeechInSecTimer()
        }
        dummySoundLooper.startPlay()
        speaker.StartSpeech()
    }
    // 読み上げを停止します。読み上げ位置が更新されます。
    func StopSpeech() {
        speaker.StopSpeech()
        dummySoundLooper.stopPlay()
        stopMaxSpeechInSecTimer()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation])
        }catch{
            print("audioSession.setActive(false) failed.")
        }
        // 自分に通知されてしまうと readLocation がさらに上書きされてしまう。
        NiftyUtilitySwift.DispatchSyncMainQueue {
            if let story = RealmStoryBulk.SearchStory(storyID: self.storyID) {
                let newLocation = self.speaker.currentLocation
                if story.readLocation != newLocation {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        story.SetCurrentReadLocationWith(realm: realm, location: newLocation)
                    }
                }
            }
        }
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStopSpeechEvent(storyID: self.storyID)
        }
    }
    
    func SkipForward(length:Int) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            guard let story = RealmStoryBulk.SearchStory(storyID: self.storyID) else {
                return
            }
            let readingPoint = self.speaker.currentLocation
            let nextReadingPoint = readingPoint + length
            let contentLength = story.content.count
            if nextReadingPoint > contentLength {
                if !self.LoadNextChapter() && story.readLocation != contentLength {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        story.SetCurrentReadLocationWith(realm: realm, location: contentLength)
                    }
                }
            }else{
                self.speaker.SetSpeechLocation(location: nextReadingPoint)
            }
        }
    }
    func SkipBackward(length:Int){
        let readingPoint = speaker.currentLocation
        if readingPoint >= length {
            speaker.SetSpeechLocation(location: readingPoint - length)
            return
        }
        var targetLength = length - readingPoint
        var targetStory:Story? = nil
        NiftyUtilitySwift.DispatchSyncMainQueue {
            targetStory = self.SearchPreviousChapter(storyID: self.storyID)
            while let story = targetStory {
                let contentLength = story.content.count
                if targetLength <= contentLength {
                    let newLocation = contentLength - targetLength
                    if story.readLocation != newLocation {
                        RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                            story.SetCurrentReadLocationWith(realm: realm, location: newLocation)
                        }
                    }
                    self.ringPageTurningSound()
                    self.SetStory(story: story)
                    return
                }
                targetStory = self.SearchPreviousChapter(storyID: story.storyID)
                targetLength -= contentLength
            }
        }
        // 抜けてきたということは先頭まで行ってしまった。
        NiftyUtilitySwift.DispatchSyncMainQueue {
            if let firstStory = RealmStoryBulk.SearchStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: self.storyID), chapterNumber: 1)) {
                if firstStory.readLocation != 0 {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        firstStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }
                if firstStory.storyID != self.storyID {
                    self.ringPageTurningSound()
                }
                self.SetStory(story: firstStory)
            }
        }
    }
    
    func SearchNextChapter(storyID:String) -> Story? {
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        let nextChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID) + 1
        return RealmStoryBulk.SearchStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: nextChapterNumber))
    }
    @discardableResult
    func LoadNextChapter() -> Bool{
        var result:Bool = false
        NiftyUtilitySwift.DispatchSyncMainQueue {
            if let nextStory = self.SearchNextChapter(storyID: self.storyID) {
                if nextStory.readLocation != 0 {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        nextStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }
                self.ringPageTurningSound()
                self.SetStory(story: nextStory)
                result = true
            }else{
                result = false
            }
        }
        return result
    }

    func SearchPreviousChapter(storyID:String) -> Story? {
        let previousChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID) - 1
        if previousChapterNumber <= 0 {
            return nil
        }
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        return RealmStoryBulk.SearchStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: previousChapterNumber))
    }
    @discardableResult
    func LoadPreviousChapter() -> Bool{
        var result = false
        NiftyUtilitySwift.DispatchSyncMainQueue {
            if let previousStory = self.SearchPreviousChapter(storyID: self.storyID) {
                if previousStory.readLocation != 0 {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        previousStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }
                self.ringPageTurningSound()
                self.SetStory(story: previousStory)
                result = true
            }else{
                result = false
            }
        }
        return result
    }
    
    func ringPageTurningSound() {
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance(), globalState.isPageTurningSoundEnabled == true else { return }
            self.pageTurningSoundPlayer.startPlay()
        }
    }
    
    func startMaxSpeechInSecTimer() {
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else { return }
            stopMaxSpeechInSecTimer()
            self.isMaxSpeechTimeExceeded = false
            self.maxSpeechInSecTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(integerLiteral:     Int64(globalState.maxSpeechTimeInSec)), repeats: false) { (timer) in
                self.isMaxSpeechTimeExceeded = true
                self.StopSpeech()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
                    self.AnnounceSpeech(text: NSLocalizedString("GlobalDataSingleton_AnnounceStopedByTimer", comment: "最大連続再生時間を超えたので、読み上げを停止します。"))
                })
            }
        }
    }
    func stopMaxSpeechInSecTimer() {
        if let timer = self.maxSpeechInSecTimer, timer.isValid {
            timer.invalidate()
        }
        self.maxSpeechInSecTimer = nil
    }
    
    func updatePlayngInfo(story:Story) {
        let titleName:String
        let writer:String
        if let novel = story.ownerNovel {
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
        autoreleasepool {
            if RealmGlobalState.GetInstance()?.isPlaybackDurationEnabled ?? false {
                let textLength = story.content.count
                autoreleasepool {
                    if let speakerSetting = RealmGlobalState.GetInstance()?.defaultSpeaker {
                        let duration = GuessSpeakDuration(textLength: textLength, speechConfig: speakerSetting)
                        let position = GuessSpeakDuration(textLength: story.readLocation, speechConfig: speakerSetting)
                        songInfo[MPMediaItemPropertyPlaybackDuration] = duration
                        songInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
                        songInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
                    }
                }
            }
        }
        if let image = UIImage.init(named: "NovelSpeakerIcon-167px.png") {
            let artWork = MPMediaItemArtwork.init(boundsSize: image.size) { (size) -> UIImage in
                #if !os(watchOS)
                return image.resize(newSize: size)
                #else
                return image.resize(size)
                #endif
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
        autoreleasepool {
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
    @objc func playEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: playEvent")
        StartSpeech(withMaxSpeechTimeReset: true)
        return .success
    }
    @objc func stopEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: stopEvent")
        StopSpeech()
        return .success
    }
    @objc func togglePlayPauseEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: togglePlayPauseEvent")
        if speaker.isSpeaking {
            print("togglePlayPause stopSpeech")
            StopSpeech()
        }else{
            StartSpeech(withMaxSpeechTimeReset: true)
        }
        return .success
    }
    @objc func nextTrackEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: nextTrackEvent")
        self.isSeeking = false
        StopSpeech()
        if LoadNextChapter() {
            StartSpeech(withMaxSpeechTimeReset: true)
        }
        return .success
    }
    @objc func previousTrackEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: previousTrackEvent")
        self.isSeeking = false
        StopSpeech()
        if LoadPreviousChapter() {
            StartSpeech(withMaxSpeechTimeReset: true)
        }
        return .success
    }
    @objc func skipForwardEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: skipForwardEvent")
        StopSpeech()
        SkipForward(length: 100)
        StartSpeech(withMaxSpeechTimeReset: true)
        return .success
    }
    @objc func skipBackwardEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: skipBackwardEvent")
        StopSpeech()
        SkipBackward(length: 100)
        StartSpeech(withMaxSpeechTimeReset: true)
        return .success
    }
    
    var isSeeking = false
    @objc func seekForwardEvent(event:MPSeekCommandEvent?) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: seekForwardEvent")
        if event?.type == MPSeekCommandEventType.endSeeking {
            print("MPCommandCenter: seekForwardEvent endSeeking")
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            print("MPCommandCenter: seekForwardEvent beginSeeking")
            AnnounceSpeech(text: NSLocalizedString("SpeechViewController_AnnounceSeekForward", comment: "早送り"))
            self.isSeeking = true
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
                if !self.isSeeking {
                    timer.invalidate()
                    return
                }
                self.StopSpeech()
                self.SkipForward(length: 50)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
                    self.StartSpeech(withMaxSpeechTimeReset: true)
                })
            }
        }
        return .success
    }
    @objc func seekBackwardEvent(event:MPSeekCommandEvent?) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: seekBackwardEvent")
        if event?.type == MPSeekCommandEventType.endSeeking {
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            AnnounceSpeech(text: NSLocalizedString("SpeechViewController_AnnounceSeekBackward", comment: "巻き戻し"))
            self.isSeeking = true
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
                if !self.isSeeking {
                    timer.invalidate()
                    return
                }
                self.StopSpeech()
                self.SkipBackward(length: 50)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
                    self.StartSpeech(withMaxSpeechTimeReset: true)
                })
            }
        }
        return .success
    }
    @objc func changePlaybackPositionEvent(event:MPChangePlaybackPositionCommandEvent?) -> MPRemoteCommandHandlerStatus {
        return autoreleasepool {
            guard let event = event, let defaultSpeakerSetting = RealmGlobalState.GetInstance()?.defaultSpeaker, let story = RealmStoryBulk.SearchStory(storyID: self.storyID) else {
                return MPRemoteCommandHandlerStatus.commandFailed
            }
             let contentLength = story.content.count
            
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: {
                self.StartSpeech(withMaxSpeechTimeReset: true)
            })
            return .success
        }
    }
    
    func GenerateSpeechTextFrom(displayTextRange:NSRange) -> String {
        return speaker.GenerateSpeechTextFrom(displayTextRange: displayTextRange)
    }

    // MARK: SpeakRangeProtocl implement
    func willSpeakRange(range:NSRange) {
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerUpdateReadingPoint(storyID: self.storyID, range: range)
        }
    }
    
    // MARK: SpeakRangeDeleate implement
    func willSpeak(_ range: NSRange, speakText text: String!) {
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerUpdateReadingPoint(storyID: self.storyID, range: range)
        }
    }
    
    func finishSpeak() {
        self.readLocation = speaker.currentLocation
        let repeatSpeechType:RepeatSpeechType? =
            autoreleasepool { () -> RepeatSpeechType? in
            return RealmGlobalState.GetInstance()?.defaultSpeechOverrideSetting?.repeatSpeechType
        }
        if let repeatSpeechType = repeatSpeechType {
            switch repeatSpeechType {
            case .rewindToFirstStory:
                let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: self.storyID)
                let processSuccess = autoreleasepool { () -> Bool in
                    if let novel = RealmNovel.SearchNovelFrom(novelID: novelID), let lastChapterNumber = novel.lastChapterNumber, let currentStory = RealmStoryBulk.SearchStory(storyID: self.storyID), lastChapterNumber == currentStory.chapterNumber, let firstStory = RealmStoryBulk.SearchStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 1)) {
                        self.SetStory(story: firstStory)
                        self.StartSpeech(withMaxSpeechTimeReset: false)
                        return true
                    }
                    return false
                }
                if processSuccess {
                    return
                }
            case .rewindToThisStory:
                self.readLocation = 0
                self.StartSpeech(withMaxSpeechTimeReset: false)
                return
            case .noRepeat:
                break
            @unknown default:
                break
            }
        }
        NiftyUtilitySwift.DispatchSyncMainQueue {
            if let nextStory = self.SearchNextChapter(storyID: self.storyID) {
                self.ringPageTurningSound()
                if nextStory.readLocation != 0 {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        nextStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }
                self.SetStory(story: nextStory)
                self.StartSpeech(withMaxSpeechTimeReset: false)
            }else{
                self.StopSpeech()
                self.AnnounceSpeech(text: NSLocalizedString("SpeechViewController_SpeechStopedByEnd", comment: "読み上げが最後に達しました。"))
            }
        }
    }
    
    var isPlayng : Bool {
        get {
            return speaker.isSpeaking
        }
    }
    
    var readLocation : Int {
        get {
            return speaker.currentLocation
        }
        set {
            NiftyUtilitySwift.DispatchSyncMainQueue {
                if let story = RealmStoryBulk.SearchStory(storyID: self.storyID), story.content.count > newValue && newValue >= 0 {
                    self.speaker.SetSpeechLocation(location: newValue)
                    if story.readLocation != newValue {
                        RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                            story.SetCurrentReadLocationWith(realm: realm, location: newValue)
                        }
                    }
                }
            }
        }
    }
    
    var speechBlockArray : [CombinedSpeechBlock] {
        get {
            return speaker.speechBlockArray
        }
    }
    
    var currentBlock:CombinedSpeechBlock {
        get { return speaker.currentBlock }
    }
    
    var currentBlockIndex:Int {
        get { return speaker.currentBlockIndex }
    }
}
