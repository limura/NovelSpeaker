//
//  CoreDataToRealmTool.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/12.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class CoreDataToRealmTool: NSObject {
    @objc static func CheckIsLocalRealmCreated() -> Bool {
        let filePath = RealmUtil.GetLocalRealmFilePath()
        if let path = filePath?.path {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }
    @objc static func CheckIsCloudRealmCreated() -> Bool {
        let filePath = RealmUtil.GetCloudRealmFilePath()
        if let path = filePath?.path {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }
    
    // realm.write {} の中で呼んでください
    private static func CreateRealmGlobalStateFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton, progress:(String)->Void) {
        progress(NSLocalizedString("CoreDataToRealmTool_ProgressGLobalState", comment: "設定項目を変換中"))
        let realmState = RealmGlobalState()
        let defaultSpeechOverrideSetting = RealmSpeechOverrideSetting()
        let defaultSpeaker = RealmSpeakerSetting()
        let defaultDisplaySetting = RealmDisplaySetting()
        
        let globalState = globalDataSingleton.getGlobalState()

        if let maxSpeechTimeInSec = globalState?.maxSpeechTimeInSec as? Int {
            realmState.maxSpeechTimeInSec = maxSpeechTimeInSec
        }
        if let isSpeechWaitSettingUseExperimentalWait = globalState?.speechWaitSettingUseExperimentalWait as? Bool {
            realmState.isSpeechWaitSettingUseExperimentalWait = isSpeechWaitSettingUseExperimentalWait
        }
        if let bookmarkArray = globalDataSingleton.getWebImportBookmarks() {
            for bookmark in bookmarkArray {
                if let bookmark = bookmark as? String {
                    realmState.webImportBookmarkArray.append(bookmark)
                }
            }
        }
        if let content = globalDataSingleton.getCurrentReadingContent() {
            if content.isURLContent(), let url = content.ncode {
                realmState.currentReadingNovelID = url
            }else if content.isUserCreatedContent(), let ncode = content.ncode, ncode.hasPrefix("_u") {
                realmState.currentReadingNovelID = "https://example.com/" + ncode
            }else if let ncode = content.ncode{
                realmState.currentReadingNovelID = CoreDataToRealmTool.NcodeToUrlString(ncode: ncode, no: 1, end: false)
            }
        }
        realmState.readedPrivacyPolicy = globalDataSingleton.getReadedPrivacyPolicy()
        realmState.isOpenRecentNovelInStartTime = globalDataSingleton.isOpenRecentNovelInStartTime()
        realmState.isLicenseReaded = globalDataSingleton.isLicenseReaded()
        realmState.isDuckOthersEnabled = globalDataSingleton.isDuckOthersEnabled()
        realmState.isMixWithOthersEnabled = globalDataSingleton.isMixWithOthersEnabled()
        realmState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = globalDataSingleton.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled()
        realmState.isDarkThemeEnabled = globalDataSingleton.isDarkThemeEnabled()
        realmState.isPlaybackDurationEnabled = globalDataSingleton.isPlaybackDurationEnabled()
        realmState.isShortSkipEnabled = globalDataSingleton.isShortSkipEnabled()
        realmState.isReadingProgressDisplayEnabled = globalDataSingleton.isReadingProgressDisplayEnabled()
        realmState.isForceSiteInfoReloadIsEnabled = globalDataSingleton.getForceSiteInfoReloadIsEnabled()
        realmState.isMenuItemIsAddSpeechModSettingOnly = globalDataSingleton.getMenuItemIsAddSpeechModSettingOnly()
        //realmState.isBackgroundNovelFetchEnabled = globalDataSingleton.getBackgroundNovelFetchEnabled()
        realmState.bookShelfSortType = globalDataSingleton.getBookSelfSortType()
        realmState.isPageTurningSoundEnabled = globalDataSingleton.isPageTurningSoundEnabled()

        defaultDisplaySetting.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
        if let textSizeValue = globalState?.textSizeValue as? Float {
            defaultDisplaySetting.textSizeValue = textSizeValue
        }
        if let fontID = globalDataSingleton.getDisplayFontName() {
            defaultDisplaySetting.fontID = fontID
        }
        defaultDisplaySetting.isVertical = false
        
        defaultSpeaker.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
        if let pitch = globalState?.defaultPitch as? Float {
            defaultSpeaker.pitch = pitch
        }
        if let rate = globalState?.defaultRate as? Float {
            defaultSpeaker.rate = rate
        }
        if let voiceIdentifier = globalDataSingleton.getVoiceIdentifier() {
            defaultSpeaker.voiceIdentifier = voiceIdentifier
        }
        defaultSpeaker.type = "AVSpeechThinsesizer"
        defaultSpeaker.locale = "ja-JP"
        
        defaultSpeechOverrideSetting.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
        defaultSpeechOverrideSetting.repeatSpeechType = globalDataSingleton.getRepeatSpeechType()
        defaultSpeechOverrideSetting.isOverrideRubyIsEnabled = globalDataSingleton.getOverrideRubyIsEnabled()
        defaultSpeechOverrideSetting.notRubyCharactorStringArray = globalDataSingleton.getNotRubyCharactorStringArray()
        defaultSpeechOverrideSetting.isIgnoreURIStringSpeechEnabled = globalDataSingleton.getIsIgnoreURIStringSpeechEnabled()
        
        realmState.defaultDisplaySettingID = defaultDisplaySetting.name
        realmState.defaultSpeakerID = defaultSpeaker.name
        realmState.defaultSpeechOverrideSettingID = defaultSpeechOverrideSetting.name

        realm.add([defaultSpeechOverrideSetting, defaultSpeaker, defaultDisplaySetting, realmState], update: .modified)
    }
    
    private static func CreateRealmSpeakerSettingFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton, progress:(String)->Void) {

        let globalState = globalDataSingleton.getGlobalState()
        if let pitchConfigArray = globalDataSingleton.getAllSpeakPitchConfig() {
            for pitchConfig in pitchConfigArray {
                if let pitchConfig = pitchConfig as? SpeakPitchConfigCacheData {
                    let speaker = RealmSpeakerSetting()

                    var name = pitchConfig.title ?? NSLocalizedString("SpeakerSetting_NewSpeakerSetting", comment: "新規話者設定")
                    var n = 0
                    while(true) {
                        if RealmSpeakerSetting.SearchFrom(name: name) != nil {
                            n += 1
                            name = "\(pitchConfig.title ?? NSLocalizedString("SpeakerSetting_NewSpeakerSetting", comment: "新規話者設定"))(\(n))"
                        }else{
                            break
                        }
                    }
                    speaker.name = name
                    if let pitch = pitchConfig.pitch as? Float {
                        speaker.pitch = pitch
                    }
                    if let rate = globalState?.defaultRate as? Float {
                        speaker.rate = rate
                    }
                    if let voiceIdentifier = globalDataSingleton.getVoiceIdentifier() {
                        speaker.voiceIdentifier = voiceIdentifier
                    }
                    speaker.type = "AVSpeechThinsesizer"
                    speaker.locale = "ja-JP"
                    
                    let section = RealmSpeechSectionConfig()
                    section.speakerID = speaker.name
                    section.name = speaker.name
                    if let startText = pitchConfig.startText {
                        section.startText = startText
                    }
                    if let endText = pitchConfig.endText {
                        section.endText = endText
                    }
                    section.targetNovelIDArray.append(RealmSpeechSectionConfig.anyTarget)

                    realm.add([speaker, section])
                }
            }
        }
    }
    
    private static func CreateRealmSpeechModSettingFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton, progress:(String)->Void) {
        guard let speechModArray = globalDataSingleton.getAllSpeechModSettings() else {
            return
        }
        var count = 0
        for speechMod in speechModArray {
            count += 1
            progress(NSLocalizedString("CoreDataToRealmTool_ProgressSpeechMod", comment: "読み替え辞書を変換中") + " (\(count)/\(speechModArray.count))")
            if let speechMod = speechMod as? SpeechModSettingCacheData {
                let mod = RealmSpeechModSetting()

                if let before = speechMod.beforeString {
                    mod.before = before
                }else{
                    continue
                }
                if let after = speechMod.afterString {
                    mod.after = after
                }else{
                    continue
                }
                mod.isUseRegularExpression = speechMod.isRegexpType()
                mod.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)

                realm.add(mod, update: .modified)
            }
        }
    }
    
    private static func CreateRealmSpeechWaitConfigFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton, progress:(String)->Void) {
        guard let speechWaitArray = globalDataSingleton.getAllSpeechWaitConfig() else {
            return
        }
        for speechWait in speechWaitArray {
            if let speechWait = speechWait as? SpeechWaitConfigCacheData {
                let wait = RealmSpeechWaitConfig()
                
                if let delayTimeInSec = speechWait.delayTimeInSec as? Float {
                    wait.delayTimeInSec = delayTimeInSec
                }
                if let targetText = speechWait.targetText {
                    wait.targetText = targetText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                }
                
                realm.add(wait)
            }
        }
    }
    
    static func NcodeToUrlString(ncode:String, no:Int, end:Bool) -> String {
        let lcaseNcode = ncode.lowercased()
        if no == 1 && end == false {
            return "https://ncode.syosetu.com/\(lcaseNcode)/"
        }
        return "https://ncode.syosetu.com/\(lcaseNcode)/\(no)/"
    }
    
    private static func CreateRealmStoryFromCoreDataWithNarouContent(realm: Realm,  globalDataSingleton:GlobalDataSingleton, content: NarouContentCacheData, novelID: String) {
        guard let storyArray = globalDataSingleton.geAllStory(forNcode: content.ncode) else {
            return
        }
        for storyObj in storyArray {
            guard let storyCoreData = storyObj as? StoryCacheData, let chapterNumber = storyCoreData.chapter_number as? Int else {
                continue
            }
            let story = RealmStory.CreateNewStory(novelID: novelID, chapterNumber: chapterNumber)
            RealmUtil.RealmStoryWrite { (realm) in
                if let readLocation = storyCoreData.readLocation as? Int {
                    story.readLocation = readLocation
                }
                story.content = storyCoreData.content
                if let ncode = content.ncode, let end = content.end as? Bool {
                    story.url = NcodeToUrlString(ncode: ncode, no: story.chapterNumber, end: end)
                }
                
                realm.add(story, update: .modified)
            }
        }
    }
    
    private static func NarouContentToNovelID(content:NarouContentCacheData) -> String {
        if content.isURLContent() {
            return content.ncode
        }else if content.isUserCreatedContent() {
            // 自作小説については ID を新しい形式に一新します。
            // ただし、過去のバックアップファイルからの書き戻しが発生した時にその ID を追跡できるようにするために
            // 謎の ID 埋め込みを行います
            return "https://example.com/" + (content.ncode ?? "\(NSUUID().uuidString)")
        }
        guard let ncode = content.ncode else {
            return ""
        }
        return "https://ncode.syosetu.com/\(ncode.lowercased())/"
    }
    
    private static func CreateRealmNovelFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton, progress:(String)->Void) {
        guard let novelArray = globalDataSingleton.getAllNarouContent(.ncode) else {
            return
        }
        var count = 0
        for novelObj in novelArray {
            count += 1
            progress(NSLocalizedString("CoreDataToRealmTool_ProgressNovel", comment: "小説データを変換中") + " (\(count)/\(novelArray.count))")
            guard let novelCoreData = novelObj as? NarouContentCacheData else {
                continue
            }
            let novel = RealmNovel()
            novel.novelID = NarouContentToNovelID(content: novelCoreData)
            CreateRealmStoryFromCoreDataWithNarouContent(realm: realm, globalDataSingleton: globalDataSingleton, content: novelCoreData, novelID: novel.novelID)
            if novelCoreData.isURLContent() {
                novel.url = NarouContentToNovelID(content: novelCoreData)
                if let urlSecret = novelCoreData.keyword {
                    novel.m_urlSecret = urlSecret
                }
                novel.type = NovelType.URL
            }else if novelCoreData.isUserCreatedContent() {
                novel.type = NovelType.UserCreated
            }else{
                novel.url = NarouContentToNovelID(content: novelCoreData)
                novel.type = NovelType.URL
                if let keyword = novelCoreData.keyword {
                    for tag in keyword.components(separatedBy: " ") {
                        RealmNovelTag.AddTag(realm: realm, name: tag, novelID: novel.novelID, type: RealmNovelTag.TagType.Keyword)
                    }
                }
            }
            if let writer = novelCoreData.writer {
                novel.writer = writer
            }
            if let title = novelCoreData.title {
                novel.title = title
            }
            if let currentReadingChapter = novelCoreData.currentReadingStory?.chapter_number as? Int {
                novel.m_readingChapterStoryID = RealmStory.CreateUniqueID(novelID: novel.novelID, chapterNumber: currentReadingChapter)
            }
            // new flug が立っている場合は downloadDate を新しくしておくことでNEWフラグをつける
            if let newFlug = novelCoreData.is_new_flug as? Bool {
                if newFlug {
                    //lastStory.downloadDate = Date(timeIntervalSinceNow: 1.1)
                    //realm.add(lastStory, update: .modified)
                    novel.lastDownloadDate = Date(timeIntervalSinceNow: 1)
                    novel.lastReadDate = Date(timeIntervalSinceNow: 0)
                }else{
                    novel.lastDownloadDate = Date(timeIntervalSinceNow: 0)
                    novel.lastReadDate = Date(timeIntervalSinceNow: 1)
                }
            }

            RealmUtil.RealmStoryWrite { (realm) in
                // chapterNumber が最後の章に関しては、
                if let lastStory = novel.linkedStorys?.sorted(byKeyPath: "chapterNumber", ascending: true).last {
                    // type が URL のものであれば url を更新しておかないと再ダウンロードできなくなるので設定する
                    if novelCoreData.isURLContent(), let lastDownloadURL = novelCoreData.userid {
                        lastStory.url = lastDownloadURL
                    }
                    novel.m_lastChapterStoryID = lastStory.id
                }
            }
            //print("novel add: novelID: \(novel.novelID), url: \(novel.url), coredata.ncode: \(novelCoreData.ncode ?? "unknown"), coredata.userid: \(novelCoreData.userid ?? "unknown"), isURLContent: \(novelCoreData.isURLContent() ? "true" : "false"), isUserCreatedContent: \(novelCoreData.isUserCreatedContent() ? "true" : "false")")

            realm.add(novel, update: .modified)
        }
    }
    
    //
    @objc public static func ConvertFromCoreaData(progress:(String)->Void) {
        guard let globalDataSingleton = GlobalDataSingleton.getInstance() else {
            return
        }
        UnregisterConvertFromCoreDataFinished()
        RealmUtil.Write { (realm) in
            CreateRealmGlobalStateFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmSpeakerSettingFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmSpeechModSettingFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmSpeechWaitConfigFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmNovelFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
        }
        RegisterConvertFromCoreDataFinished()
    }
    
    static let IsConvertFromCoreDataFinishedKey = "NovelSpeaker_CoreDataToRealmTool_IsConvertFromCoreDataFinished"
    static func IsConvertFromCoreDataFinished() -> Bool {
        let userDefaults = UserDefaults.standard
        userDefaults.register(defaults: [IsConvertFromCoreDataFinishedKey: false])
        return userDefaults.bool(forKey: IsConvertFromCoreDataFinishedKey)
    }
    @objc static func UnregisterConvertFromCoreDataFinished() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(false, forKey: IsConvertFromCoreDataFinishedKey)
    }
    static func RegisterConvertFromCoreDataFinished() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(true, forKey: IsConvertFromCoreDataFinishedKey)
    }
    
    @objc static func IsNeedMigration() -> Bool {
        return autoreleasepool {
            if RealmUtil.IsUseCloudRealm() {
                do {
                    try RealmUtil.EnableSyncEngine()
                }catch{
                    // TODO: exception を握りつぶしている
                }
                if let realm = try? RealmUtil.GetRealm(), NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm) {
                    return false
                }
                print("CheckDefaultSettingsAlive() to cloudRealm failed.")
            }else{
                if RealmUtil.CheckIsLocalRealmCreated() {
                    if CoreDataToRealmTool.IsConvertFromCoreDataFinished() {
                        return false
                    }
                }
            }
            return true
        }
    }
}
