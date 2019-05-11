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
    static func CheckIsLocalRealmCreated() -> Bool {
        let filePath = RealmUtil.GetLocalRealmFilePath()
        if let path = filePath?.path {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    // realm.write {} の中で呼んでください
    static func CreateRealmGlobalStateFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {

        let realmState = RealmGlobalState()
        let defaultSpeechOverrideSetting = RealmSpeechOverrideSetting()
        let defaultSpeaker = RealmSpeakerSetting()
        let defaultDisplaySetting = RealmDisplaySetting()
        
        let globalState = globalDataSingleton.getGlobalState()

        realmState.maxSpeechTimeInSec = globalState?.maxSpeechTimeInSec as! Int
        realmState.isSpeechWaitSettingUseExperimentalWait = globalState?.speechWaitSettingUseExperimentalWait as! Bool
        if let bookmarkArray = globalDataSingleton.getWebImportBookmarks() {
            for bookmark in bookmarkArray {
                if let bookmark = bookmark as? String {
                    realmState.webImportBookmarkArray.append(bookmark)
                }
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
        realmState.isBackgroundNovelFetchEnabled = globalDataSingleton.getBackgroundNovelFetchEnabled()
        realmState.bookSelfSortType = Int32(globalDataSingleton.getBookSelfSortType().rawValue)

        defaultDisplaySetting.name = ""
        defaultDisplaySetting.textSizeValue = globalState?.textSizeValue as! Float
        defaultDisplaySetting.fontID = globalDataSingleton.getDisplayFontName()
        defaultDisplaySetting.isVertical = false
        
        defaultSpeaker.name = ""
        defaultSpeaker.pitch = globalState?.defaultPitch as! Float
        defaultSpeaker.rate = globalState?.defaultRate as! Float
        defaultSpeaker.voiceIdentifier = globalDataSingleton.getVoiceIdentifier()
        defaultSpeaker.type = "AVSpeechThinsesizer"
        defaultSpeaker.locale = "ja-JP"
        
        defaultSpeechOverrideSetting.name = ""
        defaultSpeechOverrideSetting.repeatSpeechType = Int32(globalDataSingleton.getRepeatSpeechType().rawValue)
        defaultSpeechOverrideSetting.isPageTurningSoundEnabled = globalDataSingleton.isPageTurningSoundEnabled()
        defaultSpeechOverrideSetting.isOverrideRubyIsEnabled = globalDataSingleton.getOverrideRubyIsEnabled()
        defaultSpeechOverrideSetting.notRubyCharactorStringArray = globalDataSingleton.getNotRubyCharactorStringArray()
        defaultSpeechOverrideSetting.isIgnoreURIStringSpeechEnabled = globalDataSingleton.getIsIgnoreURIStringSpeechEnabled()
        
        realmState.defaultDisplaySettingID = defaultDisplaySetting.id
        realmState.defaultSpeakerID = defaultSpeaker.id
        realmState.defaultSpeechOverrideSettingID = defaultSpeechOverrideSetting.id

        realm.add([defaultSpeechOverrideSetting, defaultSpeaker, defaultDisplaySetting, realmState])
    }
    
    static func CreateRealmSpeakerSettingFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {

        let globalState = globalDataSingleton.getGlobalState()
        if let pitchConfigArray = globalDataSingleton.getAllSpeakPitchConfig() {
            for pitchConfig in pitchConfigArray {
                if let pitchConfig = pitchConfig as? SpeakPitchConfigCacheData {
                    let speaker = RealmSpeakerSetting()

                    speaker.name = pitchConfig.title
                    speaker.pitch = pitchConfig.pitch as! Float
                    speaker.rate = globalState?.defaultRate as! Float
                    speaker.voiceIdentifier = globalDataSingleton.getVoiceIdentifier()
                    speaker.type = "AVSpeechThinsesizer"
                    speaker.locale = "ja-JP"
                    
                    let section = RealmSpeechSectionConfig()
                    section.speakerID = speaker.id
                    section.name = pitchConfig.title
                    section.startText = pitchConfig.startText
                    section.endText = pitchConfig.endText

                    realm.add([speaker, section])
                }
            }
        }
    }
    
    static func CreateRealmSpeechModSettingFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {
        guard let speechModArray = globalDataSingleton.getAllSpeechModSettings() else {
            return
        }
        for speechMod in speechModArray {
            if let speechMod = speechMod as? SpeechModSettingCacheData {
                let mod = RealmSpeechModSetting()

                mod.before = speechMod.beforeString
                mod.after = speechMod.afterString

                realm.add(mod)
            }
        }
    }
    
    static func CreateRealmSpeechWaitConfigFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {
        guard let speechWaitArray = globalDataSingleton.getAllSpeechWaitConfig() else {
            return
        }
        for speechWait in speechWaitArray {
            if let speechWait = speechWait as? SpeechWaitConfigCacheData {
                let wait = RealmSpeechWaitConfig()
                
                wait.delayTimeInSec = speechWait.delayTimeInSec as! Float
                wait.targetText = speechWait.targetText
                
                realm.add(wait)
            }
        }
    }
    
    static func CreateRealmStoryFromCoreDataWithNarouContent(realm: Realm,  globalDataSingleton:GlobalDataSingleton, content: NarouContentCacheData, novelID: String) {
        guard let storyArray = globalDataSingleton.geAllStory(forNcode: content.ncode) else {
            return
        }
        for storyObj in storyArray {
            guard let storyCoreData = storyObj as? StoryCacheData else {
                continue
            }
            let story = RealmStory()
            story.novelID = novelID
            story.chapterNumber = storyCoreData.chapter_number as! Int
            story.readLocation = storyCoreData.readLocation as! Int
            if let content = storyCoreData.content {
                // TODO: content を zip して contentZiped に入れる
            }
            // TODO: url を生成する。小説家になろうの場合は単発のだと最後が /1/ にならないので注意
            
            realm.add(story)
        }
    }
    
    static func NarouContentToNovelID(content:NarouContentCacheData) -> String {
        if content.isUserCreatedContent() {
            return content.ncode
        }else if content.isURLContent() {
            return content.ncode
        }
        guard let ncode = content.ncode else {
            return ""
        }
        return "https://ncode.syosetu.com/\(ncode)/"
    }
    
    static func CreateRealmNovelFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {
        guard let novelArray = globalDataSingleton.getAllNarouContent(.ncode) else {
            return
        }
        for novelObj in novelArray {
            guard let novelCoreData = novelObj as? NarouContentCacheData else {
                continue
            }
            let novel = RealmNovel()
            novel.novelID = NarouContentToNovelID(content: novelCoreData)
            CreateRealmStoryFromCoreDataWithNarouContent(realm: realm, globalDataSingleton: globalDataSingleton, content: novelCoreData, novelID: novel.novelID)
            
            // TODO: 入れてないものがいっぱいある
        }
    }
    
    //
    static func ClearLocalRealmDataAndConvertFromCoreaData() throws {
        RealmUtil.RemoveLocalRealmFile()
        guard let globalDataSingleton = GlobalDataSingleton.getInstance() else {
            return
        }
        let realm = try RealmUtil.GetLocalRealm()
        try realm.write {
            CreateRealmGlobalStateFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton)
            CreateRealmSpeakerSettingFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton)
            CreateRealmSpeechModSettingFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton)
            CreateRealmSpeechWaitConfigFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton)
        }
    }
}
