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
    private static func CreateRealmGlobalStateFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {

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
        realmState.bookShelfSortType = globalDataSingleton.getBookSelfSortType()
        realmState.isPageTurningSoundEnabled = globalDataSingleton.isPageTurningSoundEnabled()

        defaultDisplaySetting.name = ""
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
        
        defaultSpeechOverrideSetting.name = ""
        defaultSpeechOverrideSetting.repeatSpeechType = globalDataSingleton.getRepeatSpeechType()
        defaultSpeechOverrideSetting.isOverrideRubyIsEnabled = globalDataSingleton.getOverrideRubyIsEnabled()
        defaultSpeechOverrideSetting.notRubyCharactorStringArray = globalDataSingleton.getNotRubyCharactorStringArray()
        defaultSpeechOverrideSetting.isIgnoreURIStringSpeechEnabled = globalDataSingleton.getIsIgnoreURIStringSpeechEnabled()
        
        realmState.defaultDisplaySettingID = defaultDisplaySetting.id
        realmState.defaultSpeakerID = defaultSpeaker.id
        realmState.defaultSpeechOverrideSettingID = defaultSpeechOverrideSetting.id

        realm.add([defaultSpeechOverrideSetting, defaultSpeaker, defaultDisplaySetting, realmState])
    }
    
    private static func CreateRealmSpeakerSettingFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {

        let globalState = globalDataSingleton.getGlobalState()
        if let pitchConfigArray = globalDataSingleton.getAllSpeakPitchConfig() {
            for pitchConfig in pitchConfigArray {
                if let pitchConfig = pitchConfig as? SpeakPitchConfigCacheData {
                    let speaker = RealmSpeakerSetting()

                    var name = pitchConfig.title ?? NSLocalizedString("SpeakerSetting_NewSpeakerSetting", comment: "新規話者設定")
                    var n = 0
                    while(true) {
                        if realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", name).first != nil {
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
                    section.speakerID = speaker.id
                    if let startText = pitchConfig.startText {
                        section.startText = startText
                    }
                    if let endText = pitchConfig.endText {
                        section.endText = endText
                    }

                    realm.add([speaker, section])
                }
            }
        }
    }
    
    private static func CreateRealmSpeechModSettingFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {
        guard let speechModArray = globalDataSingleton.getAllSpeechModSettings() else {
            return
        }
        for speechMod in speechModArray {
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

                realm.add(mod)
            }
        }
    }
    
    private static func CreateRealmSpeechWaitConfigFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {
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
            guard let storyCoreData = storyObj as? StoryCacheData else {
                continue
            }
            let story = RealmStory()
            story.novelID = novelID
            if let chapterNumber = storyCoreData.chapter_number as? Int {
                story.chapterNumber = chapterNumber
            }
            if let readLocation = storyCoreData.readLocation as? Int {
                story.readLocation = readLocation
            }
            story.content = storyCoreData.content
            if let ncode = content.ncode, let end = content.end as? Bool {
                story.url = NcodeToUrlString(ncode: ncode, no: story.chapterNumber, end: end)
            }
            story.id = RealmStory.CreateUniqueID(novelID: novelID, chapterNumber: story.chapterNumber)
            
            realm.add(story, update: true)
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
    
    private static func CreateRealmNovelFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton) {
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
            if novelCoreData.isURLContent() {
                novel.url = NarouContentToNovelID(content: novelCoreData)
                if let urlSecret = novelCoreData.keyword {
                    novel._urlSecret = urlSecret
                }
                novel.type = NovelType.URL
            }else if novelCoreData.isUserCreatedContent() {
                novel.type = NovelType.UserCreated
            }else{
                novel.url = NarouContentToNovelID(content: novelCoreData)
                novel.type = NovelType.URL
                if let keyword = novelCoreData.keyword {
                    for tag in keyword.components(separatedBy: " ") {
                        RealmNovelTag.AddTag(tagName: tag, novelID: novel.novelID, type: "keyword")
                    }
                }
            }
            if let writer = novelCoreData.writer {
                novel.writer = writer
            }
            if let title = novelCoreData.title {
                novel.title = title
            }

            // 読んでいる章が設定されていたらその章の読んだ日時を新しくすることで最後に読んだ章をそこにする
            if let currentReadingChapter = novelCoreData.currentReadingStory?.chapter_number as? Int {
                if let readingStory = novel.linkedStorys?.filter("chapterNumber = %@", currentReadingChapter).first {
                    readingStory.lastReadDate = Date(timeIntervalSinceNow: 1)
                    realm.add(readingStory, update: true)
                }
            }

            // chapterNumber が最後の章に関しては、
            if let lastStory = novel.linkedStorys?.sorted(byKeyPath: "chapterNumber", ascending: true).last {
                // type が URL のものであれば url を更新しておかないと再ダウンロードできなくなるので設定する
                if novelCoreData.isURLContent(), let lastDownloadURL = novelCoreData.userid {
                    lastStory.url = lastDownloadURL
                }
                // new flug が立っている場合は downloadDate を新しくしておくことでNEWフラグをつける
                if let newFlug = novelCoreData.is_new_flug as? Bool {
                    if newFlug {
                        lastStory.downloadDate = Date(timeIntervalSinceNow: 1.1)
                        realm.add(lastStory, update: true)
                    }
                }
            }
            //print("novel add: novelID: \(novel.novelID), url: \(novel.url), coredata.ncode: \(novelCoreData.ncode ?? "unknown"), coredata.userid: \(novelCoreData.userid ?? "unknown"), isURLContent: \(novelCoreData.isURLContent() ? "true" : "false"), isUserCreatedContent: \(novelCoreData.isUserCreatedContent() ? "true" : "false")")

            realm.add(novel, update: true)
        }
    }
    
    //
    @objc public static func ClearLocalRealmDataAndConvertFromCoreaData() throws {
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
            CreateRealmNovelFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton)
        }
    }
}
