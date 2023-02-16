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
import IceCream

protocol StorySpeakerDeletgate {
    func storySpeakerStartSpeechEvent(storyID:String)
    func storySpeakerStopSpeechEvent(storyID:String)
    func storySpeakerUpdateReadingPoint(storyID:String, range:NSRange)
    func storySpeakerStoryChanged(story:Story)
}

class AnnounceSpeaker : SpeakRangeDelegate {
    let speaker = Speaker_WithoutWillSpeakRange()
    var handler:(()->Void)? = nil
    var isWillSpeakRangeCalled:Bool = false
    
    init() {
        speaker.delegate = self
    }
    
    func willSpeakRange(range:NSRange) { isWillSpeakRangeCalled = true }
    func finishSpeak(isCancel: Bool, speechString: String) {
        if isCancel == false {
            self.handler?()
        }
    }
    
    func SetVoiceSettings(voiceIdentifier:String, language:String, pitch:Float, rate:Float, volume:Float) {
        speaker.SetVoiceWith(identifier: voiceIdentifier, language: language)
        speaker.pitch = pitch
        speaker.rate = rate
        speaker.volume = volume
        speaker.Speech(text: " ")
    }
    
    func StartAnnounce(text:String, completion: (()->Void)?) {
        if text.count <= 0 {
            handler?()
            self.handler = nil
            return
        }
        self.handler = completion
        isWillSpeakRangeCalled = false
        if speaker.isSpeaking() {
            speaker.Stop()
        }
        speaker.Speech(text: text)
    }
    func StopAnnounce() {
        self.handler = nil
        if speaker.isSpeaking() {
            speaker.Stop()
        }
    }
}

class StorySpeaker: NSObject, SpeakRangeDelegate, RealmObserverResetDelegate {
    public static let shared = StorySpeaker()
    
    let speaker = SpeechBlockSpeaker()
    let announceSpeaker = AnnounceSpeaker()
    let dummySoundLooper = DummySoundLooper()
    let pageTurningSoundPlayer = DuplicateSoundPlayer()
    var delegateArray = NSHashTable<AnyObject>.weakObjects()

    var storyID:String = ""
    var globalStateObserverToken:NotificationToken? = nil
    var storyObserverToken:NotificationToken? = nil
    var storyObserverStoryID:String = ""
    var storyObserverStoryBulkID:String = ""
    var defaultSpeakerSettingObserverToken:NotificationToken? = nil
    var speechSectionConfigArrayObserverToken:NotificationToken? = nil
    var speechModSettingArrayObserverToken:NotificationToken? = nil
    var bookmarkObserverToken:NotificationToken? = nil
    var speakerSettingObserverToken:NotificationToken? = nil
    var speechWaitSettingNotificationToken:NotificationToken? = nil
    var bookmarkObserverNovelID:String = ""
    var maxSpeechInSecTimer:Timer? = nil
    var isMaxSpeechTimeExceeded = false
    var isNeedApplySpeechConfigs = true
    
    // SpeechBlockSpeaker 内部で分割されているblockの大きさを制御する値なのだけれど、
    // 残念なことに StorySpeaker は次の Story を自動で読み込んで SpeechBlockSpeakr に渡す事をするため、
    // この制御値を保存しておく必要があります。
    var withMoreSplitTargets:[String] = []
    var moreSplitMinimumLetterCount:Int = Int.max
    
    var targetFolderNameForGoToNextSelectedFolderdNovel:String? = nil

    private override init() {
        super.init()
        UpdateMoreSplitMinimumLetterCount()
        EnableMPRemoteCommandCenterEvents()
        speaker.delegate = self
        audioSessionInit(isActive: false)
        observeGlobalState()
        observeSpeakerSetting()
        observeSpeechModSetting()
        observeSpeechWaitSetting()
        dummySoundLooper.setMediaFile(forResource: "Silent3sec", ofType: "mp3")
        registerAudioNotifications()
        if !pageTurningSoundPlayer.setMediaFile(forResource: "nc48625", ofType: "m4a", maxDuplicateCount: 1) {
            print("pageTurningSoundPlayer load media failed.")
        }
        ApplyDefaultSpeakerSettingToAnnounceSpeaker()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        DisableMPRemoteCommandCenterEvents()
        unregistAudioNotifications()
    }
    
    public func UpdateMoreSplitMinimumLetterCount() {
        let moreSplitTargetsMinimumCount = NovelSpeakerUtility.GetMoreSplitTargetsMinimumCount()
        if NovelSpeakerUtility.GetIsDisableWillSpeakRange() && moreSplitTargetsMinimumCount <= 10000 {
            // willSpeakRange が呼ばれない場合、読み上げが終了するまでは読み上げ位置が更新されないため、
            // 強引に withMoreSplitTargets の文字で区切らせて、最小 moreSplitMinimumLetterCount の長さの単位までで区切らせて
            // その区切りで発話をやり直させる事で読み上げ位置を強引に更新させます。
            // ただ、発話が止まってから再開する時に一旦空白が開くので
            // moreSplitMinimumLetterCount を小さい値にしてしまうとぶつ切れしてしまうので
            // そこそこの長さに設定します。
            // ……まぁアレです。地味にぶつ切れになるけれど我慢しておくんなまし(´・ω・`)
            self.moreSplitMinimumLetterCount = moreSplitTargetsMinimumCount
            self.withMoreSplitTargets = ["。", "、", ".", " ", "　", "\n"]
        }else{
            self.moreSplitMinimumLetterCount = Int.max
            self.withMoreSplitTargets = []
        }
    }
    
    func StopObservers() {
        globalStateObserverToken = nil
        storyObserverToken = nil
        defaultSpeakerSettingObserverToken = nil
        speechSectionConfigArrayObserverToken = nil
        speechModSettingArrayObserverToken = nil
        bookmarkObserverToken = nil
        speakerSettingObserverToken = nil
        speechWaitSettingNotificationToken = nil
    }
    func RestartObservers() {
        StopObservers()
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        observeGlobalState()
        observeSpeechConfig(novelID: novelID)
        observeBookmark(novelID: novelID)
        observeStory(storyID: storyID)
        observeSpeakerSetting()
        observeSpeechModSetting()
        observeSpeechWaitSetting()
    }
    
    func ApplyStoryToSpeaker(story:Story, withMoreSplitTargets:[String], moreSplitMinimumLetterCount:Int, readLocation:Int) {
        speaker.SetStory(story: story, withMoreSplitTargets:withMoreSplitTargets, moreSplitMinimumLetterCount:moreSplitMinimumLetterCount)
        observeSpeechConfig(novelID: story.novelID)
        speaker.SetSpeechLocation(location: readLocation)
        self.isNeedApplySpeechConfigs = false
    }
    
    func ApplyDefaultSpeakerSettingToAnnounceSpeaker() {
        RealmUtil.RealmBlock { (realm) -> Void in
            let defaultSpeaker:RealmSpeakerSetting
            if let globalStateDefaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) {
                defaultSpeaker = globalStateDefaultSpeaker
            }else{
                defaultSpeaker = RealmSpeakerSetting()
            }
            announceSpeaker.SetVoiceSettings(voiceIdentifier: defaultSpeaker.voiceIdentifier, language: defaultSpeaker.locale, pitch: defaultSpeaker.pitch, rate: defaultSpeaker.rate, volume: defaultSpeaker.volume)
        }
    }

    let queuedSetStoryStoryLock = NSLock()
    var queuedSetStoryStory:Story? = nil
    var queuedSetStoryCompletionArray:[((_ story:Story)->Void)] = []

    func SetStoryAsync(story:Story, withUpdateReadDate:Bool) {
        RealmUtil.RealmDispatchQueueAsyncBlock(queue: DispatchQueue.main) { (realm) in
            self.speaker.StopSpeech()
            let storyID = story.storyID
            let readLocation = story.readLocation(realm: realm)
            self.ApplyStoryToSpeaker(story: story, withMoreSplitTargets: self.withMoreSplitTargets, moreSplitMinimumLetterCount: self.moreSplitMinimumLetterCount, readLocation: readLocation)
            // self.ApplyStoryToSpeaker() はやたら重いので
            // この時点でqueueが入っているならやり直します。
            self.queuedSetStoryStoryLock.lock()
            if let queuedStory = self.queuedSetStoryStory, queuedStory.storyID != story.storyID {
                self.queuedSetStoryStoryLock.unlock()
                self.SetStoryAsync(story: queuedStory, withUpdateReadDate: withUpdateReadDate)
                return
            }
            self.queuedSetStoryStoryLock.unlock()

            self.storyID = storyID
            if withUpdateReadDate {
                self.updateReadDate(realm: realm, storyID: storyID, contentCount: story.content.unicodeScalars.count, readLocation: readLocation)
            }
            self.observeStory(storyID: self.storyID)
            self.observeBookmark(novelID: story.novelID)

            // queueに入っていたらしょうがないので再度自分を呼び出す(´・ω・`)
            self.queuedSetStoryStoryLock.lock()
            defer { self.queuedSetStoryStoryLock.unlock() }
            if let queuedStory = self.queuedSetStoryStory, queuedStory.storyID != story.storyID {
                self.SetStoryAsync(story: queuedStory, withUpdateReadDate: withUpdateReadDate)
                return
            }
            self.queuedSetStoryStory = nil
            for completion in self.queuedSetStoryCompletionArray {
                completion(story)
            }
            self.queuedSetStoryCompletionArray.removeAll()
            self.AnnounceSetStory(story: story)
        }
    }
    
    func AnnounceSetStory(story:Story) {
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStoryChanged(story: story)
        }
    }

    func EnqueueSetStory(story:Story, withUpdateReadDate:Bool, completion:((_ story:Story)->Void)?) {
        queuedSetStoryStoryLock.lock()
        let currentQueuedStory = queuedSetStoryStory
        queuedSetStoryStory = story
        if let completion = completion {
            queuedSetStoryCompletionArray.append(completion)
        }
        queuedSetStoryStoryLock.unlock()
        if currentQueuedStory == nil {
            SetStoryAsync(story: story, withUpdateReadDate: withUpdateReadDate)
        }
        self.AnnounceSetStory(story: story)
    }

    // 読み上げに用いられる小説の章を設定します。
    // 読み上げが行われていた場合、読み上げは停止します。
    func SetStory(story:Story, withUpdateReadDate:Bool, completion:((_ story:Story)->Void)? = nil) {
        EnqueueSetStory(story: story, withUpdateReadDate: withUpdateReadDate, completion: completion)
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
    
    func observeSpeechWaitSetting() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let speechWaitSettings = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm) else { return }
                self.speechWaitSettingNotificationToken = speechWaitSettings.observe({ (changes) in
                    switch changes {
                    case .error(_):
                        break
                    case .initial(_):
                        break
                    case .update(_, _, _, _):
                        self.isNeedApplySpeechConfigs = true
                    }
                })
            }
        }
    }
    
    func observeSpeechModSetting() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let modSettings = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return }
                self.speechModSettingArrayObserverToken = modSettings.observe({ [weak self] (change) in
                    guard let self = self else { return }
                    switch change {
                    case .update(_, _, _, _):
                        self.isNeedApplySpeechConfigs = true
                    case .initial(_):
                        break
                    case .error(_):
                        break
                    }
                })
            }
        }
    }
    
    func observeGlobalState() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                    return
                }
                self.globalStateObserverToken = globalState.observe({ [weak self] (change) in
                    guard let self = self else { return }
                    switch change {
                    case .change(_, let propertys):
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
                                RealmUtil.RealmBlock { (realm) -> Void in
                                    if property.name == "isPlaybackDurationEnabled" && self.speaker.isSpeaking, let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) {
                                        self.updatePlayngInfo(realm: realm, story: story)
                                    }
                                }
                            }else if property.name == "isSpeechWaitSettingUseExperimentalWait" {
                                self.isNeedApplySpeechConfigs = true
                            }else if ["isOverrideRubyIsEnabled", "notRubyCharactorStringArray", "isIgnoreURIStringSpeechEnabled", "isDisableNarouRuby"].contains(property.name) {
                                self.isNeedApplySpeechConfigs = true
                                return
                            }
                        }
                    default:
                        break
                    }
                })
            }
        }
    }
    func observeBookmark(novelID:String) {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                if self.bookmarkObserverNovelID == novelID { return }
                self.bookmarkObserverNovelID = novelID
                guard let bookmark = RealmBookmark.SearchObjectFromWith(realm: realm, type: .novelSpeechLocation, hint: novelID) else { return }
                self.bookmarkObserverToken = bookmark.observe { [weak self] (change) in
                    guard let self = self else { return }
                    switch change {
                    case .change(let value, let properties):
                        for property in properties {
                            if property.name == "location", let newLocation = property.newValue as? Int, let newObj = value as? RealmBookmark, newObj.chapterNumber == RealmStoryBulk.StoryIDToChapterNumber(storyID: self.storyID) {
                                self.speaker.SetSpeechLocation(location: newLocation)
                                self.willSpeakRange(range: NSMakeRange(newLocation, 0))
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }
    }
    
    func observeStory(storyID:String) {
        DispatchQueue.main.async {
            if self.storyObserverStoryID == storyID { return }
            self.storyObserverStoryID = storyID
            let targetBulkID = RealmStoryBulk.CreateUniqueBulkID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), chapterNumber: RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID))
            if self.storyObserverStoryBulkID == targetBulkID { return }
            self.storyObserverStoryBulkID = targetBulkID
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let storyBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: storyID) else { return }
                self.storyObserverToken = storyBulk.observe({ [weak self] (change) in
                    guard let self = self else { return }
                    let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: self.storyObserverStoryID)
                    switch change {
                    case .error(_):
                        break
                    case .change(_, let properties):
                        for property in properties {
                            if property.name == "storyListAsset", let newValue = property.newValue as? CreamAsset, let storyArray = RealmStoryBulk.StoryCreamAssetToStoryArray(asset: newValue), let story = RealmStoryBulk.StoryBulkArrayToStory(storyArray: storyArray, chapterNumber: chapterNumber), story.chapterNumber == chapterNumber, story.content != self.speaker.displayText {
                                DispatchQueue.global(qos: .userInitiated).async {
                                    self.speaker.SetStory(story: story)
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
    
    func observeSpeakerSetting() {
        RealmUtil.RealmBlock { (realm) -> Void in
            self.speakerSettingObserverToken = RealmSpeakerSetting.GetAllObjectsWith(realm: realm)?.observe({ (change) in
                switch change {
                case .update(_, deletions: _, insertions: _, modifications: _):
                    self.isNeedApplySpeechConfigs = true
                case .error(_):
                    break
                case .initial(_):
                    break
                }
            })
        }
    }
    
    @objc func audioSessionDidInterrupt(notification:Notification) {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            return
        }
        let typeIntValue = type.intValue
        let beganType = Int(AVAudioSession.InterruptionType.began.rawValue)
        let endedType = Int(AVAudioSession.InterruptionType.ended.rawValue)
        if typeIntValue == beganType {
            self.dummySoundLooper.stopPlay()
        }else if typeIntValue == endedType {
            self.dummySoundLooper.startPlay()
        }
    }
    @objc func didChangeAudioSessionRoute(notification:Notification) {
        func isJointHeadphone(outputs:[AVAudioSessionPortDescription]) -> Bool {
            for desc in outputs {
                if desc.portType == .headphones
                    || desc.portType == .bluetoothA2DP
                    || desc.portType == .bluetoothHFP {
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
            if isJointHeadphone(outputs: previousDesc.outputs) {
                // ヘッドフォンが抜けた
                if self.isPlayng == false { return }
                NiftyUtility.DispatchSyncMainQueue {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        self.StopSpeech(realm: realm, stopAudioSession:true) {
                            self.SkipBackward(realm: realm, length: 25) {
                                self.setReadLocationWith(realm: realm, location: self.speaker.currentLocation)
                                self.willSpeakRange(range: NSMakeRange(self.speaker.currentLocation, 0))
                            }
                        }
                    }
                }
            }
        }
    }
    
    func updateReadDate(realm: Realm, storyID:String, contentCount:Int, readLocation:Int) {
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        RealmUtil.WriteWith(realm: realm) { (realm) in
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                novel.lastReadDate = Date()
                novel.m_readingChapterStoryID = storyID
                novel.m_readingChapterContentCount = contentCount
                novel.m_readingChapterReadingPoint = readLocation
            }
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm), globalState.currentReadingNovelID != novelID {
                globalState.currentReadingNovelID = novelID
            }
        }
    }
    
    var prevObserveSpeechConfigNovelID = ""
    func observeSpeechConfig(novelID:String) {
        if prevObserveSpeechConfigNovelID == novelID { return }
        DispatchQueue.main.async {
            self.prevObserveSpeechConfigNovelID = novelID
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let defaultSpeakerSetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) else { return }
                self.defaultSpeakerSettingObserverToken = defaultSpeakerSetting.observe { [weak self] (change) in
                    guard let self = self else { return }
                    self.isNeedApplySpeechConfigs = true
                }
            }
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let allSpeechSectionConfigArray = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) else { return }
                self.speechSectionConfigArrayObserverToken = allSpeechSectionConfigArray.observe({ [weak self] (change) in
                    guard let self = self else { return }
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
    
    func audioSessionInit(isActive:Bool) {
        var option:UInt = 0
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
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
    
    func AnnounceSpeech(text:String, completion:(()->Void)? = nil) {
        announceSpeaker.StartAnnounce(text: text, completion: completion)
    }
    
    var isNeedRepeatSpeech:Bool = false
    func StartSpeech(realm: Realm, withMaxSpeechTimeReset:Bool, callerInfo:String?, isNeedRepeatSpeech:Bool) {
        self.isNeedRepeatSpeech = isNeedRepeatSpeech
        if (self.isMaxSpeechTimeExceeded && (!withMaxSpeechTimeReset)) {
            return
        }
        if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) {
            updatePlayngInfo(realm: realm, story: story)
            // story をここでも参照するので怪しくこの if の中に入れます
            if self.isNeedApplySpeechConfigs {
                self.ApplyStoryToSpeaker(story: story, withMoreSplitTargets: self.withMoreSplitTargets, moreSplitMinimumLetterCount: self.moreSplitMinimumLetterCount, readLocation: story.readLocation(realm: realm))
                self.isNeedApplySpeechConfigs = false
            }
            if withMaxSpeechTimeReset == true {
                // withMaxSpeechTimeReset == true なら、ユーザからの手動操作であるという事として
                // 読み上げ位置を更新します。
                self.updateReadDate(realm: realm, storyID: story.storyID, contentCount: story.content.unicodeScalars.count, readLocation: story.readLocation(realm: realm))
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
        #if !os(watchOS)
        if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
            UIApplication.shared.isIdleTimerDisabled = globalState.isNeedDisableIdleTimerWhenSpeechTime
        }
        #endif
        if withMaxSpeechTimeReset {
            startMaxSpeechInSecTimer(realm: realm)
        }
        BehaviorLogger.AddLog(description: "StartSpeech()", data: [
            "page" : RealmStoryBulk.StoryIDToChapterNumber(storyID: self.storyID),
            "novelUrl" : RealmStoryBulk.StoryIDToNovelID(storyID: self.storyID),
            "location" : self.speaker.currentLocation,
            "呼び出し元" : callerInfo ?? "不明",
            "連続再生時間のリセット": withMaxSpeechTimeReset ? "true" : "false",
        ])
        dummySoundLooper.startPlay()
        speaker.StartSpeech()
    }
    
    func StopAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: [AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation])
        }catch(let err){
            print("audioSession.setActive(false) failed: \(err.localizedDescription)")
            // このエラーが発生した後、読み上げが失敗し続けてしまう場合があります。
            // そのような場合、AVSpeechSynthesizer を作り直さないと問題は解消しないようです。
            // ただ、このエラーは上記の問題を踏まなかった場合でも発生する場合があります(というか、上記の問題以外の問題で発生する場合の方が多いようです)。
            // その場合、下記の reloadSynthesizer() をする必要は無いので回避したいのですが、
            // 回避する方法が思いつかない……
            // err を参照しても同じエラーみたい(localizedDescription で出てくるエラーが「操作を完了できませんでした。（OSStatusエラー560030580）」の固定値みたいなのでそれぞれの違いが判断できない)ので頼れないので詰んだ感じ。(´・ω・`)
            self.speaker.reloadSynthesizer()
            // で、作り直した後に一度でも発話しておかないと、最初の発話時に時間がかかるんじゃないかな？
            // と、思ったんですがどうやらそういう小細工は必要なさそうでした。どういう事なんだ。(´・ω・`)
            //self.speaker.resetRegisterdVoices()
        }
    }
    
    // 読み上げを停止します。読み上げ位置が更新されます。
    func StopSpeech(realm: Realm, stopAudioSession:Bool, stopSpeechHandler:(()->Void)? = nil) {
        speaker.StopSpeech(stopSpeechHandler: stopSpeechHandler)
        announceSpeaker.StopAnnounce()
        dummySoundLooper.stopPlay()
        stopMaxSpeechInSecTimer()
        BehaviorLogger.AddLog(description: "StopSpeech()", data: [
            "page" : RealmStoryBulk.StoryIDToChapterNumber(storyID: self.storyID),
            "novelUrl" : RealmStoryBulk.StoryIDToNovelID(storyID: self.storyID),
            "location" : self.speaker.currentLocation,
        ])
        #if !os(watchOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        if stopAudioSession {
            self.StopAudioSession()
        }
        // 自分に通知されてしまうと readLocation がさらに上書きされてしまう。
        if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) {
            let newLocation = self.speaker.currentLocation
            if story.readLocation(realm: realm) != newLocation {
                self.speaker.SetSpeechLocation(location: newLocation)
                NiftyUtility.DispatchSyncMainQueue {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        story.SetCurrentReadLocationWith(realm: realm, location: newLocation)
                    }
                }
            }
        }
        self.willSpeakRange(range: NSMakeRange(self.speaker.currentLocation, 0))
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerStopSpeechEvent(storyID: self.storyID)
        }
    }
    
    func SkipForward(realm: Realm, length:Int, completion: @escaping (()->Void)) {
        DispatchQueue.main.async {
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) else {
                return
            }
            let readingPoint = self.speaker.currentLocation
            let nextReadingPoint = readingPoint + length
            let contentLength = story.content.unicodeScalars.count
            if nextReadingPoint > contentLength {
                self.LoadNextChapter(realm: realm) { (result) in
                    if result == true, story.readLocation(realm: realm) != contentLength {
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                            story.SetCurrentReadLocationWith(realm: realm, location: contentLength)
                        }
                    }
                    completion()
                }
            }else{
                self.speaker.SetSpeechLocation(location: nextReadingPoint)
                let newLocation = self.speaker.currentLocation
                if story.readLocation(realm: realm) != newLocation {
                    RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        story.SetCurrentReadLocationWith(realm: realm, location: newLocation)
                    }
                }
                completion()
            }
        }
    }
    func SkipBackward(realm: Realm, length:Int, completion: @escaping (()->Void)){
        let readingPoint = self.speaker.currentLocation
        if readingPoint >= length {
            self.speaker.SetSpeechLocation(location: readingPoint - length)
            DispatchQueue.main.async {
                if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) {
                    let newLocation = self.speaker.currentLocation
                    if story.readLocation(realm: realm) != newLocation {
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                            story.SetCurrentReadLocationWith(realm: realm, location: newLocation)
                        }
                    }
                }
                completion()
            }
            return
        }
        var targetLength = length - readingPoint
        var targetStory:Story? = nil
        DispatchQueue.main.async {
            targetStory = self.SearchPreviousChapterWith(realm: realm, storyID: self.storyID)
            while let story = targetStory {
                let contentLength = story.content.unicodeScalars.count
                if targetLength <= contentLength {
                    let newLocation = contentLength - targetLength
                    if story.readLocation(realm: realm) != newLocation {
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                            story.SetCurrentReadLocationWith(realm: realm, location: newLocation)
                        }
                    }
                    self.ringPageTurningSound()
                    self.SetStory(story: story, withUpdateReadDate: true) { (story) in
                        completion()
                    }
                    return
                }
                targetStory = self.SearchPreviousChapterWith(realm: realm, storyID: story.storyID)
                targetLength -= contentLength
            }
            // 抜けてきたということは先頭まで行ってしまった。
            if let firstStory = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: self.storyID), chapterNumber: 1)) {
                if firstStory.readLocation(realm: realm) != 0 {
                    RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        firstStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }
                if firstStory.storyID != self.storyID {
                    self.ringPageTurningSound()
                }
                self.SetStory(story: firstStory, withUpdateReadDate: true) { (story) in
                    completion()
                }
                return
            }
            completion()
        }
    }
    
    func SearchNextChapterWith(realm:Realm, storyID:String, isEnd:Bool = false) -> Story? {
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        let nextChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID) + 1
        let nextStory = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: nextChapterNumber)
        if isEnd == false, let nextStory = nextStory, nextStory.chapterNumber != nextChapterNumber {
            let chapterNumberArrayString = RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: novelID).description
            AppInformationLogger.AddLog(message: "次の章を検索したところ、次の章ではない物が出てきました。リカバリを試みます。", appendix: [
                "現在の StoryID": self.storyID,
                "取得された章の StoryID": nextStory.storyID,
                "全ての章の chapterNumber": chapterNumberArrayString,
            ], isForDebug: true)
            NovelSpeakerUtility.CleanInvalidStory(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))
            return SearchNextChapterWith(realm: realm, storyID: storyID, isEnd: true)
        }
        return nextStory
    }

    func LoadNextChapter(realm: Realm, completion: ((Bool)->Void)? = nil){
        DispatchQueue.main.async {
            if let nextStory = self.SearchNextChapterWith(realm: realm, storyID: self.storyID) {
                if nextStory.readLocation(realm: realm) != 0 {
                    RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        nextStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }
                self.ringPageTurningSound()
                self.SetStory(story: nextStory, withUpdateReadDate: true) { (story) in
                    completion?(true)
                }
            }else{
                completion?(false)
            }
        }
    }

    func SearchPreviousChapterWith(realm: Realm, storyID:String) -> Story? {
        let previousChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID) - 1
        if previousChapterNumber <= 0 {
            return nil
        }
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        return RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: previousChapterNumber))
    }
    func LoadPreviousChapter(realm: Realm, moveReadingPointToLast:Bool = false, completion: ((Bool)->Void)? = nil){
        DispatchQueue.main.async {
            if let previousStory = self.SearchPreviousChapterWith(realm: realm, storyID: self.storyID) {
                if moveReadingPointToLast == false || previousStory.content.count <= 2, previousStory.readLocation(realm: realm) != 0 {
                    RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        previousStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                    }
                }else if moveReadingPointToLast {
                    RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        previousStory.SetCurrentReadLocationWith(realm: realm, location: max(0, previousStory.content.count - 2))
                    }
                }
                self.ringPageTurningSound()
                self.SetStory(story: previousStory, withUpdateReadDate: true) { (story) in
                    completion?(true)
                }
            }else{
                completion?(false)
            }
        }
    }

    /// ページめくりの音を鳴らす場合はtrueを返します
    @discardableResult
    func ringPageTurningSound() -> Bool {
        return RealmUtil.RealmBlock { (realm) -> Bool in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm), globalState.isPageTurningSoundEnabled == true else { return false }
            self.pageTurningSoundPlayer.startPlay()
            return true
        }
    }
    
    func startMaxSpeechInSecTimer(realm: Realm) {
        guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
        stopMaxSpeechInSecTimer()
        self.isMaxSpeechTimeExceeded = false
        self.maxSpeechInSecTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(integerLiteral:     Int64(globalState.maxSpeechTimeInSec)), repeats: false) { (timer) in
            self.isMaxSpeechTimeExceeded = true
            if self.speaker.isPausedBySynthesizerState == true || self.speaker.isSpeakingBySynthesizerState == false {
                // 既に発話が停止している場合はわざわざアナウンスはしません。
                // けれども、Pause しているだけの場合は Stop を明示的に呼ばないとおかしなことになるはずなので
                // StopSpeech() は呼び出します
                self.StopSpeech(realm: realm, stopAudioSession:true)
                return
            }
            self.StopSpeech(realm: realm, stopAudioSession:false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: {
                self.AnnounceSpeech(text: NSLocalizedString("GlobalDataSingleton_AnnounceStopedByTimer", comment: "最大連続再生時間を超えたので、読み上げを停止します。")) {
                    self.StopAudioSession()
                }
            })
        }
    }
    func stopMaxSpeechInSecTimer() {
        if let timer = self.maxSpeechInSecTimer, timer.isValid {
            timer.invalidate()
        }
        self.maxSpeechInSecTimer = nil
    }
    
    func updatePlayngInfo(realm: Realm, story:Story) {
        let titleName:String
        let writer:String
        if let novel = story.ownerNovel(realm: realm) {
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
        if let globalState = RealmGlobalState.GetInstanceWith(realm: realm), globalState.isPlaybackDurationEnabled == true, let speakerSetting = globalState.defaultSpeakerWith(realm: realm) {
            let textLength = story.content.unicodeScalars.count
            let duration = GuessSpeakDuration(textLength: textLength, speechConfig: speakerSetting)
            let position = GuessSpeakDuration(textLength: story.readLocation(realm: realm), speechConfig: speakerSetting)
            songInfo[MPMediaItemPropertyPlaybackDuration] = duration
            songInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
            songInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        }
        if let image = UIImage.init(named: "NovelSpeakerIcon-color-1024x1024.png") {
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
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
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
        RealmUtil.RealmBlock { (realm) -> Void in
            StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "コントロールセンターからの操作(再生).\(#function)", isNeedRepeatSpeech: isNeedRepeatSpeech)
        }
        return .success
    }
    @objc func stopEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: stopEvent")
        RealmUtil.RealmBlock { (realm) -> Void in
            StopSpeech(realm: realm, stopAudioSession: true)
        }
        return .success
    }
    @discardableResult
    func togglePlayPauseEvent() -> Bool {
        RealmUtil.RealmBlock { (realm) -> Void in
            if speaker.isSpeaking {
                StopSpeech(realm: realm, stopAudioSession: true)
            }else{
                StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "再生・停止イベント.\(#function)", isNeedRepeatSpeech: isNeedRepeatSpeech)
            }
        }
        return true
    }
    @objc func togglePlayPauseEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: togglePlayPauseEvent")
        self.togglePlayPauseEvent()
        return .success
    }
    @discardableResult
    func nextTrackEvent() -> Bool {
        self.isSeeking = false
        RealmUtil.RealmBlock { (realm) -> Void in
            StopSpeech(realm: realm, stopAudioSession:false)
            LoadNextChapter(realm: realm) { (result) in
                if result == true {
                    self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "次の章の読み上げ.\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                }
            }
        }
        return true
    }
    @objc func nextTrackEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: nextTrackEvent")
        self.nextTrackEvent()
        return .success
    }
    @discardableResult
    func previousTrackEvent() -> Bool {
        self.isSeeking = false
        RealmUtil.RealmBlock { (realm) -> Void in
            StopSpeech(realm: realm, stopAudioSession:false)
            LoadPreviousChapter(realm: realm, completion: { (result) in
                if result == true {
                    self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "前の章の読み上げ.\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                }
            })
        }
        return true
    }
    @objc func previousTrackEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: previousTrackEvent")
        self.previousTrackEvent()
        return .success
    }
    var skipForwardCount = 0
    var isNowSkipping = false
    @discardableResult
    func skipForwardEvent() -> Bool {
        skipForwardCount += 100
        if isNowSkipping == true { return true }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
               self.StopSpeech(realm: realm, stopAudioSession:false) {
                    let count = self.skipForwardCount
                    self.skipForwardCount = 0
                    self.isNowSkipping = true
                    self.SkipForward(realm: realm, length: count) {
                        self.isNowSkipping = false
                        self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "早送り(単発呼び出し).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                    }
                }
            }
        }
        return true
    }
    @objc func skipForwardEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: skipForwardEvent")
        
        return self.skipForwardEvent() ? .success : .commandFailed
    }
    @discardableResult
    func skipBackwardEvent() -> Bool {
        skipForwardCount += 100
        if isNowSkipping == true { return true }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                self.StopSpeech(realm: realm, stopAudioSession:false) {
                    let count = self.skipForwardCount
                    self.skipForwardCount = 0
                    self.SkipBackward(realm: realm, length: count) {
                        self.isNowSkipping = false
                        self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "巻き戻し(単発呼び出し).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                    }
                }
            }
        }
        return true
    }
    @objc func skipBackwardEvent(_ sendor:MPRemoteCommandCenter) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: skipBackwardEvent")
        return self.skipBackwardEvent() ? .success : .commandFailed
    }
    
    var isSeeking = false
    func seekForwardInterval(){
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                self.StopSpeech(realm: realm, stopAudioSession:false) {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        self.SkipForward(realm: realm, length: 50) {
                            NiftyUtility.DispatchSyncMainQueue {
                                self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "早送り(連続呼び出し).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                            }
                            if self.isSeeking == false { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                if self.isSeeking == false { return }
                                self.seekForwardInterval()
                            }
                        }
                    }
                }
            }
        }
    }
    @objc func seekForwardEvent(event:MPSeekCommandEvent?) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: seekForwardEvent")
        if event?.type == MPSeekCommandEventType.endSeeking {
            print("MPCommandCenter: seekForwardEvent endSeeking")
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            self.isSeeking = true
            self.seekForwardInterval()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.AnnounceSpeech(text: NSLocalizedString("SpeechViewController_AnnounceSeekForward", comment: "早送り"))
            }
        }
        return .success
    }
    
    func seekBackwardInterval(){
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                self.StopSpeech(realm: realm, stopAudioSession:false) {
                    RealmUtil.RealmBlock { (realm) -> Void in
                        self.SkipBackward(realm: realm, length: 60) {
                            NiftyUtility.DispatchSyncMainQueue {
                                self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "巻き戻し(連続呼び出し).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                            }
                            if self.isSeeking == false { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                if self.isSeeking == false { return }
                                self.seekBackwardInterval()
                            }
                        }
                    }
                }
            }
        }
    }
    @objc func seekBackwardEvent(event:MPSeekCommandEvent?) -> MPRemoteCommandHandlerStatus {
        print("MPCommandCenter: seekBackwardEvent")
        if event?.type == MPSeekCommandEventType.endSeeking {
            self.isSeeking = false
        }
        if event?.type == MPSeekCommandEventType.beginSeeking {
            self.isSeeking = true
            self.seekBackwardInterval()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.AnnounceSpeech(text: NSLocalizedString("SpeechViewController_AnnounceSeekBackward", comment: "巻き戻し"))
            }
        }
        return .success
    }
    @objc func changePlaybackPositionEvent(event:MPChangePlaybackPositionCommandEvent?) -> MPRemoteCommandHandlerStatus {
        return RealmUtil.RealmBlock { (realm) -> MPRemoteCommandHandlerStatus in
            guard let event = event, let defaultSpeakerSetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm), let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) else {
                return MPRemoteCommandHandlerStatus.commandFailed
            }
            let contentLength = story.content.unicodeScalars.count
            
            print("MPChangePlaybackPositionCommandEvent in: \(event.positionTime)")
            var newLocation = self.GuessSpeakLocationFromDulation(dulation: Float(event.positionTime), speechConfig: defaultSpeakerSetting)
            let textLength = contentLength
            if newLocation > textLength {
                newLocation = textLength
            }
            if newLocation <= 0 {
                newLocation = 0
            }
            
            StopSpeech(realm: realm, stopAudioSession:false)
            NiftyUtility.DispatchSyncMainQueue {
                RealmUtil.RealmBlock { (realm) -> Void in
                    self.setReadLocationWith(realm: realm, location: newLocation)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: {
                RealmUtil.RealmBlock { (realm) -> Void in
                    self.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "コントロールセンターからの操作(PlaybackPosition).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                }
            })
            return .success
        }
    }
    
    func GenerateSpeechTextFrom(displayTextRange:NSRange) -> String {
        if self.isNeedApplySpeechConfigs {
            RealmUtil.RealmBlock { (realm) -> Void in
                if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) {
                    self.ApplyStoryToSpeaker(story: story, withMoreSplitTargets: self.withMoreSplitTargets, moreSplitMinimumLetterCount: self.moreSplitMinimumLetterCount, readLocation: story.readLocation(realm: realm))
                    self.isNeedApplySpeechConfigs = false
                }
            }
        }
        return speaker.GenerateSpeechTextFrom(displayTextRange: displayTextRange)
    }

    // MARK: SpeakRangeProtocl implement
    func willSpeakRange(range:NSRange) {
        for case let delegate as StorySpeakerDeletgate in self.delegateArray.allObjects {
            delegate.storySpeakerUpdateReadingPoint(storyID: self.storyID, range: range)
        }
    }
    
    func InterruptByiOS16_3MemoryLeak() {
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { realm in
                self.StopSpeech(realm: realm, stopAudioSession: false)
                self.AnnounceSpeech(text: NSLocalizedString("StorySpeaker_StartSpeechCountExceeded_in_iOS16.3_Announce", comment: "iOS 16.3 で発話回数が多くなると強制終了する場合がある事に対応して発話を停止します。このまま再生を再開させても良いですが、一旦アプリを終了してから再度再生を開始する事をお勧めします。")) {
                    self.StopAudioSession()
                }
            }
        }
    }
    
    func finishSpeak(isCancel: Bool, speechString: String) {
        let nextStorySpeechWaitSecond = 0.5
        func AnnounceAndDoNext(realm:Realm, announceText: String, block: @escaping (()->Void)) {
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm), globalState.isAnnounceAtRepatSpeechTime == true else {
                block()
                return
            }
            self.AnnounceSpeech(text: announceText, completion: block)
        }
        
        func speechNextNovelWith(realm:Realm, title:String, story:Story) {
            self.StopSpeech(realm: realm, stopAudioSession:false)
            AnnounceAndDoNext(realm: realm, announceText: String(format: NSLocalizedString("StorySpeaker_SpeechStopedAndSpeechNextStory_Format", comment: "読み上げが最後に達したため、次に %@ を再生します。"), title)) {
                DispatchQueue.main.async {
                    self.ringPageTurningSound()
                    self.SetStory(story: story, withUpdateReadDate: true) { (story) in
                        DispatchQueue.main.asyncAfter(deadline: .now() + nextStorySpeechWaitSecond) {
                            RealmUtil.RealmBlock { (realm) -> Void in
                                self.StartSpeech(realm: realm, withMaxSpeechTimeReset: false, callerInfo: "次の(別の)小説の読み上げを開始(「再生が末尾に達した時の動作」が 別の小説を再生 する設定になっている).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                            }
                        }
                    }
                }
            }
        }
        
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                let globalState = RealmGlobalState.GetInstanceWith(realm: realm)
                let repeatSpeechType = globalState?.repeatSpeechType
                if self.isNeedRepeatSpeech, let repeatSpeechType = repeatSpeechType, repeatSpeechType == .RewindToThisStory {
                    self.setReadLocationWith(realm: realm, location: 0)
                    self.StartSpeech(realm: realm, withMaxSpeechTimeReset: false, callerInfo: "同じ章を再生(「再生が末尾に達した時の動作」が「現在の章を再生し直す」になっている).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                    return
                }
                self.setReadLocationWith(realm: realm, location: self.speaker.currentLocation)

                if self.isNeedRepeatSpeech, let nextStory = self.SearchNextChapterWith(realm: realm, storyID: self.storyID) {
                    self.ringPageTurningSound()
                    if nextStory.readLocation(realm: realm) != 0 {
                        RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                            nextStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                        }
                    }
                    self.SetStory(story: nextStory, withUpdateReadDate: true, completion: { (story) in
                        DispatchQueue.main.asyncAfter(deadline: .now() + nextStorySpeechWaitSecond) {
                            self.StartSpeech(realm: realm, withMaxSpeechTimeReset: false, callerInfo: "次の章へ移行.\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                        }
                    })
                }else{
                    let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: self.storyID)
                    if self.isNeedRepeatSpeech, let repeatSpeechType = repeatSpeechType {
                        if globalState?.repeatSpeechLoopType == .noCheckReadingPoint && NovelSpeakerUtility.GetAllRepeatSpeechLoopTargetRepeatSpeechType().contains(repeatSpeechType) {
                            func runNextSpeechLoop(novelIDArray:[String]) -> Bool {
                                if let currentIndex = novelIDArray.firstIndex(of: novelID), let nextNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelIDArray[(currentIndex + 1) % novelIDArray.count]), let firstStory = nextNovel.firstChapterWith(realm: realm) {
                                    RealmUtil.WriteWith(realm: realm) { (realm) in
                                        firstStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                                    }
                                    speechNextNovelWith(realm: realm, title: nextNovel.title, story: firstStory)
                                    return true
                                }
                                return false
                            }
                            if repeatSpeechType == .GoToNextLikeNovel
                               , let novelLikeOrder = RealmGlobalState.GetInstanceWith(realm: realm)?.novelLikeOrder, runNextSpeechLoop(novelIDArray: Array(novelLikeOrder)) {
                                return
                            }else if repeatSpeechType == .GoToNextSelectedFolderdNovel, let nextFolderName = self.targetFolderNameForGoToNextSelectedFolderdNovel, let nextNovelIDArray = RealmNovelTag.SearchWith(realm: realm, name: nextFolderName, type: RealmNovelTag.TagType.Folder)?.targetNovelIDArray, runNextSpeechLoop(novelIDArray: Array(nextNovelIDArray)) {
                                return
                            }else if repeatSpeechType == .GoToNextSameWriterNovel, let currentNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID),
                                     let nextNovelIDArray = RealmNovel.GetAllObjectsWith(realm: realm)?.sorted(by: { $0.title < $1.title })
                                        .filter({$0.writer == currentNovel.writer}).map({$0.novelID}), runNextSpeechLoop(novelIDArray: Array(nextNovelIDArray)) {
                                return
                            }else if repeatSpeechType == .GoToNextSameWebsiteNovel, let currentNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID), let currentWebSite = currentNovel.type == .UserCreated ? "" : URL(string: novelID)?.host,
                                     let nextNovelIDArray = RealmNovel.GetAllObjectsWith(realm: realm)?.sorted(by: { $0.title < $1.title })
                                        .filter({
                                            guard let webSite = $0.type == .UserCreated ? "" : URL(string: $0.novelID)?.host else { return false }
                                            return webSite == currentWebSite
                                        }).map({$0.novelID}), runNextSpeechLoop(novelIDArray: Array(nextNovelIDArray)) {
                                return
                            }
                            self.StopSpeech(realm: realm, stopAudioSession: false)
                            self.AnnounceSpeech(text: NSLocalizedString("SpeechViewController_SpeechStopedByEnd", comment: "読み上げが最後に達しました。")) {
                                self.StopAudioSession()
                            }
                            return
                        }
                        if repeatSpeechType == .RewindToFirstStory {
                            if let firstStory = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 1)) {
                                // 何故か self.SetStory() した後に
                                // self.readLocation = 0
                                // とした場合はうまく反映されないぽいので
                                // SetStory()する前に読み上げ位置を最初に戻します。
                                RealmUtil.WriteWith(realm: realm) { (realm) in
                                    firstStory.SetCurrentReadLocationWith(realm: realm, location: 0)
                                }
                                AnnounceAndDoNext(realm: realm, announceText: NSLocalizedString("StorySpeaker_SpeechStopedAndRewindFirstStory", comment: "読み上げが最後に達したため、最初の章に戻って再生を繰り返します。")) {
                                    DispatchQueue.main.async {
                                        self.ringPageTurningSound()
                                        self.SetStory(story: firstStory, withUpdateReadDate: true) { (story) in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + nextStorySpeechWaitSecond) {
                                                RealmUtil.RealmBlock { (realm) -> Void in
                                                    self.StartSpeech(realm: realm, withMaxSpeechTimeReset: false, callerInfo: "最初の章から再生をやりなおす(「再生が末尾に達した時の動作」が「最初の章から再生し直す」になっている).\(#function)", isNeedRepeatSpeech: self.isNeedRepeatSpeech)
                                                }
                                            }
                                        }
                                    }
                                }
                                return
                            }
                        }else if repeatSpeechType == .GoToNextLikeNovel,
                             let novelLikeOrder = RealmGlobalState.GetInstanceWith(realm: realm)?.novelLikeOrder,
                             let filterdNovelArray = RealmNovel.GetAllObjectsWith(realm: realm)?.sorted(by: {novelLikeOrder.index(of: $0.novelID) ?? 0 < novelLikeOrder.index(of: $1.novelID) ?? 0})
                             .filter({novelLikeOrder.contains($0.novelID) && $0.novelID != novelID && ((($0.m_readingChapterReadingPoint + 5) < $0.m_readingChapterContentCount) || $0.m_readingChapterStoryID != $0.m_lastChapterStoryID)}),
                             let novel = filterdNovelArray.first,
                             let story = novel.m_readingChapterStoryID != "" ? RealmStoryBulk.SearchStoryWith(realm: realm, storyID: novel.m_readingChapterStoryID) : RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novel.novelID, chapterNumber: 1) {
                            speechNextNovelWith(realm: realm, title: novel.title, story: story)
                            return
                        }else if repeatSpeechType == .GoToNextSameFolderdNovel, let folderArray = RealmNovelTag.SearchWith(realm: realm, novelID: novelID, type: RealmNovelTag.TagType.Folder) {
                            for folder in folderArray {
                                if let novelDictionary = RealmNovel.SearchNovelWith(realm: realm, novelIDArray: Array(folder.targetNovelIDArray))?.filter({ (novel) in
                                    if novel.novelID == novelID { return false }
                                    if novel.m_readingChapterStoryID != novel.m_lastChapterStoryID { return true }
                                    if novel.m_readingChapterReadingPoint + 5 >= novel.m_readingChapterContentCount { return false }
                                    return true
                                }).reduce([:] as [String:RealmNovel], { (result, novel) -> [String:RealmNovel] in
                                    var result = result
                                    result[novel.novelID] = novel
                                    return result
                                }) {
                                    for novelID in folder.targetNovelIDArray {
                                        print(novelID)
                                        guard let novel = novelDictionary[novelID], let story = novel.m_readingChapterStoryID != "" ? RealmStoryBulk.SearchStoryWith(realm: realm, storyID: novel.m_readingChapterStoryID) : RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novel.novelID, chapterNumber: 1) else { continue }
                                        speechNextNovelWith(realm: realm, title: novel.title, story: story)
                                        return
                                    }
                                }
                            }
                        }else if repeatSpeechType == .GoToNextSelectedFolderdNovel, let targetFolderName = self.targetFolderNameForGoToNextSelectedFolderdNovel, let folder = RealmNovelTag.SearchWith(realm: realm, name: targetFolderName, type: RealmNovelTag.TagType.Folder) {
                            if let novelDictionary = RealmNovel.SearchNovelWith(realm: realm, novelIDArray: Array(folder.targetNovelIDArray))?.filter({ (novel) in
                                if novel.novelID == novelID { return false }
                                if novel.m_readingChapterStoryID != novel.m_lastChapterStoryID { return true }
                                if novel.m_readingChapterReadingPoint + 5 >= novel.m_readingChapterContentCount { return false }
                                return true
                            }).reduce([:] as [String:RealmNovel], { (result, novel) -> [String:RealmNovel] in
                                var result = result
                                result[novel.novelID] = novel
                                return result
                            }) {
                                for novelID in folder.targetNovelIDArray {
                                    print(novelID)
                                    guard let novel = novelDictionary[novelID], let story = novel.m_readingChapterStoryID != "" ? RealmStoryBulk.SearchStoryWith(realm: realm, storyID: novel.m_readingChapterStoryID) : RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novel.novelID, chapterNumber: 1) else { continue }
                                    speechNextNovelWith(realm: realm, title: novel.title, story: story)
                                    return
                                }
                            }
                        }else if repeatSpeechType == .GoToNextSameWriterNovel, let currentNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID),
                                 let filterdNovelArray = RealmNovel.GetAllObjectsWith(realm: realm)?.sorted(by: { $0.title < $1.title })
                                    .filter({$0.novelID != novelID && $0.writer == currentNovel.writer && ((($0.m_readingChapterReadingPoint + 5) < $0.m_readingChapterContentCount) || $0.m_readingChapterStoryID != $0.m_lastChapterStoryID)}),
                             let novel = filterdNovelArray.first,
                             let story = novel.m_readingChapterStoryID != "" ? RealmStoryBulk.SearchStoryWith(realm: realm, storyID: novel.m_readingChapterStoryID) : RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novel.novelID, chapterNumber: 1) {
                            speechNextNovelWith(realm: realm, title: novel.title, story: story)
                            return
                        }else if repeatSpeechType == .GoToNextSameWebsiteNovel, let currentNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID), let currentWebSite = currentNovel.type == .UserCreated ? "" : URL(string: novelID)?.host,
                                 let filterdNovelArray = RealmNovel.GetAllObjectsWith(realm: realm)?.sorted(by: { $0.title < $1.title })
                                    .filter({
                                        guard let webSite = $0.type == .UserCreated ? "" : URL(string: $0.novelID)?.host else { return false }
                                        return $0.novelID != novelID &&
                                        webSite == currentWebSite &&
                                        ((($0.m_readingChapterReadingPoint + 5) < $0.m_readingChapterContentCount) || $0.m_readingChapterStoryID != $0.m_lastChapterStoryID)
                                    }),
                             let novel = filterdNovelArray.first,
                             let story = novel.m_readingChapterStoryID != "" ? RealmStoryBulk.SearchStoryWith(realm: realm, storyID: novel.m_readingChapterStoryID) : RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novel.novelID, chapterNumber: 1) {
                            speechNextNovelWith(realm: realm, title: novel.title, story: story)
                            return
                        }
                    }
                    
                    self.StopSpeech(realm: realm, stopAudioSession: false)
                    self.AnnounceSpeech(text: NSLocalizedString("SpeechViewController_SpeechStopedByEnd", comment: "読み上げが最後に達しました。")) {
                        self.StopAudioSession()
                    }
                }
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
    }
    func setReadLocationWith(realm:Realm, location:Int) {
        if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID), story.content.unicodeScalars.count >= location && location >= 0 {
            self.speaker.SetSpeechLocation(location: location)
            if story.readLocation(realm: realm) != location {
                NiftyUtility.DispatchSyncMainQueue {
                    RealmUtil.Write(withoutNotifying: [self.bookmarkObserverToken]) { (realm) in
                        story.SetCurrentReadLocationWith(realm: realm, location: location)
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
    
    var currentBlock:CombinedSpeechBlock? {
        get { return speaker.currentBlock }
    }
    
    var currentBlockIndex:Int {
        get { return speaker.currentBlockIndex }
    }
    
    func isDummySpeechAlive() -> Bool {
        return speaker.isDummySpeechAlive()
    }
    
    @objc static func becomeActiveHandle() {
        /* // becomeActive のタイミングでこの判定をすべきかどうかがいまいちよくわからないので一旦ここでは判定しないことにします。
        let speaker = StorySpeaker.shared
        // 自分は発話しているつもりだけれど、
        // AVSpeechSynthesizer 的には発話が中断(Pause)しているということは、
        // 恐らく別アプリによって再生が停止するなどしていると判断する
        if speaker.isPlayng == true && speaker.speaker.isPausedBySynthesizerState == true {
            RealmUtil.RealmDispatchQueueAsyncBlock { (realm) in
                StorySpeaker.shared.StopSpeech(realm: realm)
            }
        }
         */
    }
    
    func GenerateWholeDisplayText() -> String {
        return speaker.speechBlockArray.reduce("") { $0 + $1.displayText }
    }
    
    func ChangeSpeakerWillSpeakRangeType() {
        RealmUtil.RealmBlock { realm in
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.storyID) else { return }
            self.SetStory(story: story, withUpdateReadDate: false)
        }
    }
}
