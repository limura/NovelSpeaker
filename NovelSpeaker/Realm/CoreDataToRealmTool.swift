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
                    if bookmark == "アルファポリス(Web取込 非対応サイトになりました。詳細はサポートサイト下部にありますQ&Aを御覧ください)\nhttps://www.alphapolis.co.jp/novel/" {
                        realmState.webImportBookmarkArray.append("アルファポリス\nhttps://www.alphapolis.co.jp/novel/")
                    }else{
                        realmState.webImportBookmarkArray.append(bookmark)
                    }
                }
            }
        }
        if let content = globalDataSingleton.getCurrentReadingContent() {
            if content.isURLContent(), let url = content.ncode {
                realmState.currentReadingNovelID = url
            }else if content.isUserCreatedContent(), let ncode = content.ncode, ncode.hasPrefix("_u") {
                realmState.currentReadingNovelID = NovelSpeakerUtility.UserCreatedContentPrefix + ncode
            }else if let ncode = content.ncode{
                realmState.currentReadingNovelID = CoreDataToRealmTool.NcodeToUrlString(ncode: ncode, no: 1, end: false)
            }
        }
        realmState.readedPrivacyPolicy = globalDataSingleton.getReadedPrivacyPolicy()
        realmState.isOpenRecentNovelInStartTime = globalDataSingleton.isOpenRecentNovelInStartTime()
        realmState.IsDisallowsCellularAccess = globalDataSingleton.isDisallowsCellularAccess()
        realmState.IsNeedConfirmDeleteBook = globalDataSingleton.isNeedConfirmDeleteBook()
        realmState.isLicenseReaded = globalDataSingleton.isLicenseReaded()
        realmState.isDuckOthersEnabled = globalDataSingleton.isDuckOthersEnabled()
        realmState.isMixWithOthersEnabled = globalDataSingleton.isMixWithOthersEnabled()
        realmState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = false
        realmState.isPlaybackDurationEnabled = globalDataSingleton.isPlaybackDurationEnabled()
        realmState.isShortSkipEnabled = globalDataSingleton.isShortSkipEnabled()
        realmState.isReadingProgressDisplayEnabled = globalDataSingleton.isReadingProgressDisplayEnabled()
        RealmGlobalState.SetIsForceSiteInfoReloadIsEnabled(newValue: globalDataSingleton.getForceSiteInfoReloadIsEnabled())
        realmState.isMenuItemIsAddNovelSpeakerItemsOnly = globalDataSingleton.getMenuItemIsAddSpeechModSettingOnly()
        //realmState.isBackgroundNovelFetchEnabled = globalDataSingleton.getBackgroundNovelFetchEnabled()
        realmState.bookShelfSortType = NarouContentSortType(rawValue: Int(globalDataSingleton.getBookSelfSortType())) ?? .Title
        realmState.isPageTurningSoundEnabled = globalDataSingleton.isPageTurningSoundEnabled()
        realmState.backgroundColor = globalDataSingleton.getReadingColorSettingForBackgroundColor()
        realmState.foregroundColor = globalDataSingleton.getReadingColorSettingForForegroundColor()
        realmState.repeatSpeechType = RepeatSpeechType(rawValue: Int(globalDataSingleton.getRepeatSpeechType())) ?? RepeatSpeechType.NoRepeat
        realmState.isOverrideRubyIsEnabled = globalDataSingleton.getOverrideRubyIsEnabled()
        realmState.notRubyCharactorStringArray = globalDataSingleton.getNotRubyCharactorStringArray()
        realmState.isIgnoreURIStringSpeechEnabled = globalDataSingleton.getIsIgnoreURIStringSpeechEnabled()

        defaultDisplaySetting.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
        if let textSizeValue = globalState?.textSizeValue as? Float, textSizeValue >= 1.0 && textSizeValue <= 100 {
            defaultDisplaySetting.textSizeValue = textSizeValue
        }else{
            defaultDisplaySetting.textSizeValue = 58.0
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

        realmState.defaultDisplaySettingID = defaultDisplaySetting.name
        realmState.defaultSpeakerID = defaultSpeaker.name

        realm.add([defaultSpeaker, defaultDisplaySetting, realmState], update: .modified)
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
                        if RealmSpeakerSetting.SearchFromWith(realm: realm, name: name) != nil {
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
                    return
                }
                if let after = speechMod.afterString {
                    mod.after = after
                }else{
                    return
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
                    wait.targetText = NovelSpeakerUtility.NormalizeNewlineString(string: targetText)
                }
                
                realm.add(wait, update: .modified)
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
    
    // 保存されているStoryを移行するついでに、最後の chapterNumber の物を返します
    private static func CreateRealmStoryFromCoreDataWithNarouContent(realm: Realm,  globalDataSingleton:GlobalDataSingleton, content: NarouContentCacheData, novelID: String) -> Story? {
        var chapterNumber = 0
        var newStoryArray:[Story] = []
        var lastStory:Story? = nil
        globalDataSingleton.getAllStoryTextForNcode(withBlock: content.ncode) { (storyText) in
            guard let storyText = storyText else { return }
            autoreleasepool {
                chapterNumber += 1
                var story = Story()
                story.novelID = novelID
                story.chapterNumber = chapterNumber
                story.content = NovelSpeakerUtility.NormalizeNewlineString(string: storyText)
                if content.isURLContent() == false, content.isUserCreatedContent() == false, let ncode = content.ncode, let end = content.end as? Bool {
                    story.url = NcodeToUrlString(ncode: ncode, no: story.chapterNumber, end: end)
                }
                lastStory = story
                newStoryArray.append(story)
                if newStoryArray.count >= RealmStoryBulk.bulkCount {
                    RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: newStoryArray)
                    newStoryArray.removeAll()
                }
            }
        }
        RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: newStoryArray)
        return lastStory
    }
    
    private static func NarouContentToNovelID(content:NarouContentCacheData) -> String {
        if content.isURLContent() {
            return content.ncode
        }else if content.isUserCreatedContent() {
            // 自作小説については ID を新しい形式に一新します。
            // ただし、過去のバックアップファイルからの書き戻しが発生した時にその ID を追跡できるようにするために
            // 謎の ID 埋め込みを行います
            return NovelSpeakerUtility.UserCreatedContentPrefix + (content.ncode ?? "\(NSUUID().uuidString)")
        }
        guard let ncode = content.ncode else {
            return ""
        }
        return "https://ncode.syosetu.com/\(ncode.lowercased())/"
    }
    
    private static func CreateRealmNovelFromCoreData(realm: Realm, globalDataSingleton:GlobalDataSingleton, progress:(String)->Void) -> [HTTPCookie] {
        guard let novelArray = globalDataSingleton.getAllNarouContent(Int32(NarouContentSortType.Ncode.rawValue)) else {
            return []
        }
        var count = 0
        var cookieArray:[HTTPCookie] = []
        func addURLSecret(urlSecret:String, novelID:String, lastUpdateDate:Date) {
            // 元のcookieでは path や expire date がどう指定されていたかを推測できないため、
            // とりあえず path は '/' 固定で、最終ダウンロード日時から1日後まで有効、という事にします。
            guard let fullPathURL = URL(string: novelID), let host = fullPathURL.host, let scheme = fullPathURL.scheme, let url = URL(string: "\(scheme)://\(host)") else { return }
            let expireDate = lastUpdateDate.addingTimeInterval(60*60*24)
            let newCookieArray = NiftyUtility.ConvertJavaScriptCookieStringToHTTPCookieArray(javaScriptCookieString: urlSecret, targetURL: url, expireDate: expireDate)
            cookieArray = NiftyUtility.RemoveExpiredCookie(cookieArray: NiftyUtility.MergeCookieArray(currentCookieArray: cookieArray, newCookieArray: newCookieArray))
        }
        
        for novelObj in novelArray {
            count += 1
            progress(NSLocalizedString("CoreDataToRealmTool_ProgressNovel", comment: "小説データを変換中") + " (\(count)/\(novelArray.count))")
            guard let novelCoreData = novelObj as? NarouContentCacheData else {
                continue
            }
            let novel = RealmNovel()
            novel.novelID = NarouContentToNovelID(content: novelCoreData)
            let lastStory = CreateRealmStoryFromCoreDataWithNarouContent(realm: realm, globalDataSingleton: globalDataSingleton, content: novelCoreData, novelID: novel.novelID)
            if novelCoreData.isURLContent() {
                novel.url = NarouContentToNovelID(content: novelCoreData)
                if let urlSecret = novelCoreData.keyword {
                    addURLSecret(urlSecret: urlSecret, novelID: novel.novelID, lastUpdateDate: novelCoreData.novelupdated_at)
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
            if let currentReadingStory = novelCoreData.currentReadingStory {
                if let chapterNumber = currentReadingStory.chapter_number as? Int {
                    novel.m_readingChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: chapterNumber)
                    if let readLocation = currentReadingStory.readLocation as? Int {
                        Story.SetReadLocationWith(realm: realm, novelID: novel.novelID, chapterNumber: chapterNumber, location: readLocation)
                        novel.m_readingChapterReadingPoint = readLocation
                    }
                    let normalizedContent = NovelSpeakerUtility.NormalizeNewlineString(string: currentReadingStory.content)
                    novel.m_readingChapterContentCount = normalizedContent.count
                }
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

            // chapterNumber が最後の章に関しては、
            if var lastStory = lastStory {
                // type が URL のものであれば url を更新しておかないと再ダウンロードできなくなるので設定する
                if novelCoreData.isURLContent(), let lastDownloadURL = novelCoreData.userid {
                    lastStory.url = lastDownloadURL
                    RealmStoryBulk.SetStoryWith(realm: realm, story: lastStory)
                }
                novel.m_lastChapterStoryID = lastStory.storyID
            }else{
                BehaviorLogger.AddLog(description: "WARN: m_lastChapterStoryID not set.", data: ["novelID":novel.novelID])
            }
            //print("novel add: novelID: \(novel.novelID), url: \(novel.url), coredata.ncode: \(novelCoreData.ncode ?? "unknown"), coredata.userid: \(novelCoreData.userid ?? "unknown"), isURLContent: \(novelCoreData.isURLContent() ? "true" : "false"), isUserCreatedContent: \(novelCoreData.isUserCreatedContent() ? "true" : "false")")

            realm.add(novel, update: .modified)
        }
        return cookieArray
    }
    
    //
    @objc public static func ConvertFromCoreData(progress:(String)->Void) {
        guard let globalDataSingleton = GlobalDataSingleton.getInstance() else {
            return
        }
        UnregisterConvertFromCoreDataFinished()
        RealmUtil.Write { (realm) in
            CreateRealmGlobalStateFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmSpeakerSettingFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmSpeechModSettingFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            CreateRealmSpeechWaitConfigFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            let newCookieArray = CreateRealmNovelFromCoreData(realm: realm, globalDataSingleton: globalDataSingleton, progress: progress)
            HTTPCookieSyncTool.shared.SaveCookiesFromCookieArrayWith(realm: realm, cookieArray: newCookieArray)
            HTTPCookieSyncTool.shared.LoadCookiesFromRealmWith(realm: realm)
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
        return RealmUtil.RealmBlock { (realm) -> Bool in
            if RealmUtil.IsUseCloudRealm() {
                do {
                    try RealmUtil.EnableSyncEngine()
                }catch{
                    // TODO: exception を握りつぶしている
                }
                
                if NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm){
                    return false
                }
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
