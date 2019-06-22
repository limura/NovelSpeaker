//
//  LocalRealmToCloudRealmCopyTool.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/31.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class RealmToRealmCopyTool: NSObject {
    static func CopyStorys(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmStory.self) {
            to.beginWrite()
            let newObj = RealmStory.CreateNewStory(novelID: obj.novelID, chapterNumber: obj.chapterNumber)
            newObj.isDeleted = obj.isDeleted
            newObj.contentZiped = obj.contentZiped
            newObj.readLocation = obj.readLocation
            newObj.url = obj.url
            //newObj.lastReadDate = obj.lastReadDate
            //newObj.downloadDate = obj.downloadDate
            newObj.subtitle = obj.subtitle
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }
    static func CopyNovels(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmNovel.self) {
            to.beginWrite()
            let newObj = RealmNovel()
            newObj.novelID = obj.novelID
            newObj.isDeleted = obj.isDeleted
            newObj.m_type = obj.m_type
            newObj.writer = obj.writer
            newObj.title = obj.title
            newObj.url = obj.url
            newObj.m_urlSecret = obj.m_urlSecret
            newObj.createdDate = obj.createdDate
            newObj.likeLevel = obj.likeLevel
            newObj.isNeedSpeechAfterDelete = obj.isNeedSpeechAfterDelete
            newObj.defaultSpeakerID = obj.defaultSpeakerID
            newObj.m_lastChapterStoryID = obj.m_lastChapterStoryID
            newObj.lastDownloadDate = obj.lastDownloadDate
            newObj.m_readingChapterStoryID = obj.m_readingChapterStoryID
            newObj.lastReadDate = obj.lastReadDate
            newObj.downloadDateArray.removeAll()
            newObj.downloadDateArray.append(objectsIn: obj.downloadDateArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeechModSetting(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmSpeechModSetting.self) {
            to.beginWrite()
            let newObj = RealmSpeechModSetting()
            newObj.isDeleted = obj.isDeleted
            newObj.before = obj.before
            newObj.after = obj.after
            newObj.createdDate = obj.createdDate
            newObj.isUseRegularExpression = obj.isUseRegularExpression
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeechWaitConfig(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmSpeechWaitConfig.self) {
            to.beginWrite()
            let newObj = RealmSpeechWaitConfig()
            newObj.isDeleted = obj.isDeleted
            newObj.targetText = obj.targetText
            newObj.delayTimeInSec = obj.delayTimeInSec
            newObj.createdDate = obj.createdDate
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeakerSetting(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmSpeakerSetting.self) {
            to.beginWrite()
            let newObj = RealmSpeakerSetting()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.pitch = obj.pitch
            newObj.rate = obj.rate
            newObj.lmd = obj.lmd
            newObj.acc = obj.acc
            newObj.base = obj.base
            newObj.volume = obj.volume
            newObj.type = obj.type
            newObj.voiceIdentifier = obj.voiceIdentifier
            newObj.locale = obj.locale
            newObj.createdDate = obj.createdDate
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeechSectionConfig(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmSpeechSectionConfig.self) {
            to.beginWrite()
            let newObj = RealmSpeechSectionConfig()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.startText = obj.startText
            newObj.endText = obj.endText
            newObj.createdDate = obj.createdDate
            newObj.speakerID = obj.speakerID
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeechQueue(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmSpeechQueue.self) {
            to.beginWrite()
            let newObj = RealmSpeechQueue()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.createdDate = obj.createdDate
            newObj.targetStoryIDArray.removeAll()
            newObj.targetStoryIDArray.append(objectsIn: obj.targetStoryIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopyGlobalState(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmGlobalState.self) {
            to.beginWrite()
            let newObj = RealmGlobalState()
            newObj.isDeleted = obj.isDeleted
            newObj.id = obj.id
            newObj.maxSpeechTimeInSec = obj.maxSpeechTimeInSec
            newObj.isSpeechWaitSettingUseExperimentalWait = obj.isSpeechWaitSettingUseExperimentalWait
            newObj.webImportBookmarkArray.removeAll()
            newObj.webImportBookmarkArray.append(objectsIn: obj.webImportBookmarkArray)
            newObj.readedPrivacyPolicy = obj.readedPrivacyPolicy
            newObj.isOpenRecentNovelInStartTime = obj.isOpenRecentNovelInStartTime
            newObj.isLicenseReaded = obj.isLicenseReaded
            newObj.isDuckOthersEnabled = obj.isDuckOthersEnabled
            newObj.isMixWithOthersEnabled = obj.isMixWithOthersEnabled
            newObj.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = obj.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled
            newObj.isDarkThemeEnabled = obj.isDarkThemeEnabled
            newObj.isPlaybackDurationEnabled = obj.isPlaybackDurationEnabled
            newObj.isShortSkipEnabled = obj.isShortSkipEnabled
            newObj.isReadingProgressDisplayEnabled = obj.isReadingProgressDisplayEnabled
            newObj.isForceSiteInfoReloadIsEnabled = obj.isForceSiteInfoReloadIsEnabled
            newObj.isMenuItemIsAddNovelSpeakerItemsOnly = obj.isMenuItemIsAddNovelSpeakerItemsOnly
            newObj.isPageTurningSoundEnabled = obj.isPageTurningSoundEnabled
            newObj.m_bookSelfSortType = obj.m_bookSelfSortType
            newObj.defaultDisplaySettingID = obj.defaultDisplaySettingID
            newObj.defaultSpeakerID = obj.defaultSpeakerID
            newObj.defaultSpeechOverrideSettingID = obj.defaultSpeechOverrideSettingID
            newObj.currentReadingNovelID = obj.currentReadingNovelID
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopyDisplaySetting(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmDisplaySetting.self) {
            to.beginWrite()
            let newObj = RealmDisplaySetting()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.textSizeValue = obj.textSizeValue
            newObj.fontID = obj.fontID
            newObj.isVertical = obj.isVertical
            newObj.createdDate = obj.createdDate
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }
    
    static func CopyNovelTag(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmNovelTag.self) {
            to.beginWrite()
            let newObj = RealmNovelTag.CreateNewTag(name: obj.name, type: obj.type)
            newObj.isDeleted = obj.isDeleted
            newObj.createdDate = obj.createdDate
            newObj.hint = obj.hint
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeechOverrideSetting(from:Realm, to:Realm) throws {
        for obj in from.objects(RealmSpeechOverrideSetting.self) {
            to.beginWrite()
            let newObj = RealmSpeechOverrideSetting()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.createdDate = obj.createdDate
            newObj.m_repeatSpeechType = obj.m_repeatSpeechType
            newObj.isOverrideRubyIsEnabled = obj.isOverrideRubyIsEnabled
            newObj.notRubyCharactorStringArray = obj.notRubyCharactorStringArray
            newObj.isIgnoreURIStringSpeechEnabled = obj.isIgnoreURIStringSpeechEnabled
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }
    
    static func DoCopy(from:Realm, to:Realm, progress:(String)->Void) throws {
        try CopySpeechModSetting(from: from, to: to)
        try CopySpeechWaitConfig(from: from, to: to)
        try CopySpeakerSetting(from: from, to: to)
        try CopySpeechSectionConfig(from: from, to: to)
        try CopySpeechQueue(from: from, to: to)
        try CopyGlobalState(from: from, to: to)
        try CopyDisplaySetting(from: from, to: to)
        try CopyNovelTag(from: from, to: to)
        try CopySpeechOverrideSetting(from: from, to: to)
        try CopyNovels(from: from, to: to)
        //try CopyStorys(from: from, to: to)
    }
}
