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
    static let instance = StorySpeaker()
    
    let speaker = NiftySpeaker()
    let dummySoundLooper = DummySoundLooper()
    let pageTurningSoundPlayer = DuplicateSoundPlayer()
    let announceSpeakerHolder = AnnounceSpeakerHolder()
    var delegateArray = NSHashTable<AnyObject>.weakObjects()

    var storyID:String = ""
    var globalStateObserveToken:NotificationToken? = nil
    var storyObserverToken:NotificationToken? = nil
    var defaultSpeakerSettingObserverToken:NotificationToken? = nil
    var speechSectionConfigArrayObserverToken:NotificationToken? = nil
    var defaultSpeechOverrideSettingObserverToken:NotificationToken? = nil
    var novelIDSpeechOverrideSettingArrayObserverToken:NotificationToken? = nil
    var speechModSettingArrayObserverToken:NotificationToken? = nil
    var maxSpeechInSecTimer:Timer? = nil
    var isMaxSpeechTimeExceeded = false
    var isNeedApplySpeechConfigs = false

    private override init() {
        super.init()
        EnableMPRemoteCommandCenterEvents()
        speaker.add(self)
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
    
    func ApplySpeakConfigs(novelID:String, content:String, location:Int) {
        speaker.clearSpeakSettings()
        applySpeechConfig(novelID: novelID)
        applySpeechModSetting(novelID: novelID, targetText: content)
        speaker.setText(ForceOverrideHungSpeakString(text: content))
        speaker.updateCurrentReadingPoint(NSRange(location: location, length: 0))
        self.isNeedApplySpeechConfigs = false
    }

    // 読み上げに用いられる小説の章を設定します。
    // 読み上げが行われていた場合、読み上げは停止します。
    func SetStory(story:RealmStory) {
        speaker.stopSpeech()
        guard let content = story.content else { return }
        self.storyID = story.id
        updateReadDate(story: story)
        ApplySpeakConfigs(novelID: story.novelID, content: content, location: story.readLocation)
        updatePlayngInfo(story: story)
        observeStory(storyID: self.storyID)
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
                        if property.name == "isPlaybackDurationEnabled" && self.speaker.isSpeaking(), let story = RealmStory.SearchStoryFrom(storyID: self.storyID) {
                            self.updatePlayngInfo(story: story)
                        }
                    }
                }
            default:
                break
            }
        })
    }
    func observeStory(storyID:String) {
        guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else { return }
        self.storyObserverToken = story.observe({ (change) in
            switch change {
            case .error(_):
                break
            case .change(let properties):
                for property in properties {
                    if property.name == "readLocation", let location = property.newValue as? Int {
                        self.speaker.updateCurrentReadingPoint(NSRange(location: location, length: 0))
                    }else if property.name == "contentZiped", let contentZiped = property.newValue as? Data, let newContent = NiftyUtility.stringInflate(contentZiped) {
                        self.speaker.setText(self.ForceOverrideHungSpeakString(text: newContent))
                    }
                }
            case .deleted:
                break
            }
        })
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
                self.readLocation = speaker.getCurrentReadingPoint().location
            }
        }
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
        guard let allSpeechSectionConfigArray = RealmSpeechSectionConfig.GetAllObjects() else { return }
        let speechSectionConfigArray = allSpeechSectionConfigArray.filter({ (sectionConfig) -> Bool in
            return sectionConfig.targetNovelIDArray.count <= 0 || sectionConfig.targetNovelIDArray.contains(novelID)
        })
        for sectionConfig in speechSectionConfigArray {
            guard let speakerSetting = sectionConfig.speaker else { continue }
            speaker.addBlockStartSeparator(sectionConfig.startText, end: sectionConfig.endText, speechConfig: speakerSetting.speechConfig)
        }
        
        self.defaultSpeakerSettingObserverToken = defaultSpeakerSetting.observe { (change) in
            self.isNeedApplySpeechConfigs = true
        }
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
    
    func applySpeechModSetting(novelID:String, targetText:String) {
        var isOverrideRubyEnabled = false
        var notRubyCharactorStringArray = ""
        var isIgnoreURIStringSpeechEnabled = false
        
        if let globalState = RealmGlobalState.GetInstance() {
            if let speechOverrideSetting = globalState.defaultSpeechOverrideSetting {
                isOverrideRubyEnabled = speechOverrideSetting.isOverrideRubyIsEnabled
                notRubyCharactorStringArray = speechOverrideSetting.notRubyCharactorStringArray
                isIgnoreURIStringSpeechEnabled = speechOverrideSetting.isIgnoreURIStringSpeechEnabled
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
        if let settingArray = RealmSpeechOverrideSetting.SearchObjectFrom(novelID: novelID) {
            for speechOverrideSetting in settingArray {
                isOverrideRubyEnabled = speechOverrideSetting.isOverrideRubyIsEnabled
                notRubyCharactorStringArray = speechOverrideSetting.notRubyCharactorStringArray
                isIgnoreURIStringSpeechEnabled = speechOverrideSetting.isIgnoreURIStringSpeechEnabled
            }
        }
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
        self.speechModSettingArrayObserverToken = RealmSpeechModSetting.GetAllObjects()?.observe({ (change) in
            switch change {
            case .initial(_):
                break
            case .update(let speechModSettingArray, let deletions, _, _):
                if deletions.count > 0 {
                    self.isNeedApplySpeechConfigs = true
                    return
                }
                for setting in speechModSettingArray {
                    if setting.targetNovelIDArray.count <= 0 || setting.targetNovelIDArray.contains(novelID) {
                        self.isNeedApplySpeechConfigs = true
                        return
                    }
                }
            case .error(_):
                break
            }
        })
    }
    
    func audioSessionInit(isActive:Bool) {
        guard let globalState = RealmGlobalState.GetInstance() else { return }

        var option:UInt = 0
        if globalState.isMixWithOthersEnabled {
            option = AVAudioSession.CategoryOptions.mixWithOthers.rawValue
            if globalState.isDuckOthersEnabled {
                option |= AVAudioSession.CategoryOptions.duckOthers.rawValue
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
    
    func StartSpeech(withMaxSpeechTimeReset:Bool) {
        if (self.isMaxSpeechTimeExceeded && (!withMaxSpeechTimeReset)) {
            return
        }
        if let story = RealmStory.SearchStoryFrom(storyID: self.storyID) {
            updatePlayngInfo(story: story)
            // story をここでも参照するので怪しくこの if の中に入れます
            if self.isNeedApplySpeechConfigs, let content = story.content {
                self.ApplySpeakConfigs(novelID: story.novelID, content: content, location: story.readLocation)
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
        speaker.startSpeech()
    }
    // 読み上げを停止します。読み上げ位置が更新されます。
    func StopSpeech() {
        speaker.stopSpeech()
        dummySoundLooper.stopPlay()
        stopMaxSpeechInSecTimer()
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation])
        }catch{
            print("audioSession.setActive(false) failed.")
        }
        // 自分に通知されてしまうと readLocation がさらに上書きされてしまう。
        if let token = self.storyObserverToken {
            if let realm = try? RealmUtil.GetRealm(), let story = RealmStory.SearchStoryFrom(storyID: self.storyID) {
                realm.beginWrite()
                story.readLocation = speaker.getCurrentReadingPoint().location
                try! realm.commitWrite(withoutNotifying: [token])
            }
        }else{
            self.readLocation = speaker.getCurrentReadingPoint().location
        }
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
            if !LoadNextChapter() {
                if let realm = try? RealmUtil.GetRealm() {
                    try! realm.write {
                        story.readLocation = contentLength
                    }
                }
            }
        }else{
            speaker.updateCurrentReadingPoint(NSRange(location: nextReadingPoint, length: 0))
        }
    }
    func SkipBackward(length:Int){
        let readingPoint = speaker.getCurrentReadingPoint().location
        if readingPoint >= length {
            speaker.updateCurrentReadingPoint(NSRange(location: readingPoint - length, length: 0))
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
                ringPageTurningSound()
                SetStory(story: story)
                return
            }
            targetStory = SearchPreviousChapter(storyID: story.id)
            targetLength -= contentLength
        }
        // 抜けてきたということは先頭まで行ってしまった。
        if let firstStory = RealmStory.SearchStoryFrom(storyID: RealmStory.CreateUniqueID(novelID: RealmStory.StoryIDToNovelID(storyID: self.storyID), chapterNumber: 1)) {
            if let realm = try? RealmUtil.GetRealm() {
                try! realm.write {
                    firstStory.readLocation = 0
                }
            }
            if firstStory.id != self.storyID {
                ringPageTurningSound()
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
            ringPageTurningSound()
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
            ringPageTurningSound()
            SetStory(story: previousStory)
            return true
        }
        return false
    }
    
    func ringPageTurningSound() {
        guard let globalState = RealmGlobalState.GetInstance(), globalState.isPageTurningSoundEnabled == true else { return }
        self.pageTurningSoundPlayer.startPlay()
    }
    
    func startMaxSpeechInSecTimer() {
        guard let globalState = RealmGlobalState.GetInstance() else { return }
        stopMaxSpeechInSecTimer()
        self.isMaxSpeechTimeExceeded = false
        self.maxSpeechInSecTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(integerLiteral:     Int64(globalState.maxSpeechTimeInSec)), repeats: false) { (timer) in
            self.isMaxSpeechTimeExceeded = true
            self.StopSpeech()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
                self.announceSpeakerHolder.Speech(text: NSLocalizedString("GlobalDataSingleton_AnnounceStopedByTimer", comment: "最大連続再生時間を超えたので、読み上げを停止します。"))
            })
        }
    }
    func stopMaxSpeechInSecTimer() {
        if let timer = self.maxSpeechInSecTimer, timer.isValid {
            timer.invalidate()
        }
        self.maxSpeechInSecTimer = nil
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
        print("MPCommandCenter: playEvent")
        StartSpeech(withMaxSpeechTimeReset: true)
    }
    @objc func stopEvent(_ sendor:MPRemoteCommandCenter) {
        print("MPCommandCenter: stopEvent")
        StopSpeech()
    }
    @objc func togglePlayPauseEvent(_ sendor:MPRemoteCommandCenter) {
        print("MPCommandCenter: togglePlayPauseEvent")
        if speaker.isSpeaking() {
            print("togglePlayPause stopSpeech")
            StopSpeech()
        }else{
            StartSpeech(withMaxSpeechTimeReset: true)
        }
    }
    @objc func nextTrackEvent(_ sendor:MPRemoteCommandCenter) {
        print("MPCommandCenter: nextTrackEvent")
        self.isSeeking = false
        StopSpeech()
        if LoadNextChapter() {
            StartSpeech(withMaxSpeechTimeReset: true)
        }
    }
    @objc func previousTrackEvent(_ sendor:MPRemoteCommandCenter) {
        print("MPCommandCenter: previousTrackEvent")
        self.isSeeking = false
        StopSpeech()
        if LoadPreviousChapter() {
            StartSpeech(withMaxSpeechTimeReset: true)
        }
    }
    @objc func skipForwardEvent(_ sendor:MPRemoteCommandCenter) {
        print("MPCommandCenter: skipForwardEvent")
        StopSpeech()
        SkipForward(length: 100)
        StartSpeech(withMaxSpeechTimeReset: true)
    }
    @objc func skipBackwardEvent(_ sendor:MPRemoteCommandCenter) {
        print("MPCommandCenter: skipBackwardEvent")
        StopSpeech()
        SkipBackward(length: 100)
        StartSpeech(withMaxSpeechTimeReset: true)
    }
    
    var isSeeking = false
    @objc func seekForwardEvent(event:MPSeekCommandEvent?) {
        print("MPCommandCenter: seekForwardEvent")
        if event?.type == MPSeekCommandEventType.endSeeking {
            print("MPCommandCenter: seekForwardEvent endSeeking")
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            print("MPCommandCenter: seekForwardEvent beginSeeking")
            announceSpeakerHolder.Speech(text: NSLocalizedString("SpeechViewController_AnnounceSeekForward", comment: "早送り"))
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
    }
    @objc func seekBackwardEvent(event:MPSeekCommandEvent?) {
        print("MPCommandCenter: seekBackwardEvent")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
                    self.StartSpeech(withMaxSpeechTimeReset: true)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: {
            self.StartSpeech(withMaxSpeechTimeReset: true)
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
                self.StartSpeech(withMaxSpeechTimeReset: false)
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
        if let nextStory = SearchNextChapter(storyID: self.storyID) {
            self.ringPageTurningSound()
            if let realm = try? RealmUtil.GetRealm() {
                try! realm.write {
                    nextStory.readLocation = 0
                }
            }
            self.SetStory(story: nextStory)
            self.StartSpeech(withMaxSpeechTimeReset: false)
        }else{
            self.StopSpeech()
            self.announceSpeakerHolder.Speech(text: NSLocalizedString("SpeechViewController_SpeechStopedByEnd", comment: "読み上げが最後に達しました。"))
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
            if let realm = try? RealmUtil.GetRealm(), let story = RealmStory.SearchStoryFrom(storyID: self.storyID), let contentLength = story.content?.count, contentLength > newValue && newValue >= 0 {
                speaker.updateCurrentReadingPoint(NSRange(location: newValue, length: 0))
                try! realm.write {
                    story.readLocation = newValue
                }
            }
        }
    }
}
