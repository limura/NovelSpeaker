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
    static func CopyStorys(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmStory.self) {
            let newObj = RealmStory()
            newObj.id = obj.id
            newObj.novelID = obj.novelID
            newObj.chapterNumber = obj.chapterNumber
            newObj.isDeleted = obj.isDeleted
            newObj.contentZiped = obj.contentZiped
            newObj.readLocation = obj.readLocation
            newObj.url = obj.url
            newObj.lastReadDate = obj.lastReadDate
            newObj.downloadDate = obj.downloadDate
            newObj.subtitle = obj.subtitle
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }
    static func CopyNovels(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmNovel.self) {
            let newObj = RealmNovel()
            newObj.novelID = obj.novelID
            newObj.isDeleted = obj.isDeleted
            newObj._type = obj._type
            newObj.writer = obj.writer
            newObj.title = obj.title
            newObj.url = obj.url
            newObj._urlSecret = obj._urlSecret
            newObj.createdDate = obj.createdDate
            newObj.likeLevel = obj.likeLevel
            newObj.isNeedSpeechAfterDelete = obj.isNeedSpeechAfterDelete
            newObj.defaultSpeakerID = obj.defaultSpeakerID
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopySpeechModSetting(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmSpeechModSetting.self) {
            let newObj = RealmSpeechModSetting()
            newObj.isDeleted = obj.isDeleted
            newObj.before = obj.before
            newObj.after = obj.after
            newObj.createdDate = obj.createdDate
            newObj.isUseRegularExpression = obj.isUseRegularExpression
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopySpeechWaitConfig(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmSpeechWaitConfig.self) {
            let newObj = RealmSpeechWaitConfig()
            newObj.isDeleted = obj.isDeleted
            newObj.targetText = obj.targetText
            newObj.delayTimeInSec = obj.delayTimeInSec
            newObj.createdDate = obj.createdDate
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopySpeakerSetting(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmSpeakerSetting.self) {
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
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopySpeechSectionConfig(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmSpeechSectionConfig.self) {
            let newObj = RealmSpeechSectionConfig()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.startText = obj.startText
            newObj.endText = obj.endText
            newObj.createdDate = obj.createdDate
            newObj.speakerID = obj.speakerID
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopySpeechQueue(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmSpeechQueue.self) {
            let newObj = RealmSpeechQueue()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.createdDate = obj.createdDate
            newObj.targetStoryIDArray.removeAll()
            newObj.targetStoryIDArray.append(objectsIn: obj.targetStoryIDArray)
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopyGlobalState(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmGlobalState.self) {
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
            newObj.isMenuItemIsAddSpeechModSettingOnly = obj.isMenuItemIsAddSpeechModSettingOnly
            newObj.isPageTurningSoundEnabled = obj.isPageTurningSoundEnabled
            newObj._bookSelfSortType = obj._bookSelfSortType
            newObj.defaultDisplaySettingID = obj.defaultDisplaySettingID
            newObj.defaultSpeakerID = obj.defaultSpeakerID
            newObj.defaultSpeechOverrideSettingID = obj.defaultSpeechOverrideSettingID
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopyDisplaySetting(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmDisplaySetting.self) {
            let newObj = RealmDisplaySetting()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.textSizeValue = obj.textSizeValue
            newObj.fontID = obj.fontID
            newObj.isVertical = obj.isVertical
            newObj.createdDate = obj.createdDate
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }
    
    static func CopyNovelTag(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmNovelTag.self) {
            let newObj = RealmNovelTag()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.type = obj.type
            newObj.createdDate = obj.createdDate
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }

    static func CopySpeechOverrideSetting(from:Realm, to:Realm) {
        to.beginWrite()
        for obj in from.objects(RealmSpeechOverrideSetting.self) {
            let newObj = RealmSpeechOverrideSetting()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.createdDate = obj.createdDate
            newObj._repeatSpeechType = obj._repeatSpeechType
            newObj.isOverrideRubyIsEnabled = obj.isOverrideRubyIsEnabled
            newObj.notRubyCharactorStringArray = obj.notRubyCharactorStringArray
            newObj.isIgnoreURIStringSpeechEnabled = obj.isIgnoreURIStringSpeechEnabled
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: true)
        }
        do {
            try to.commitWrite()
        }catch{
            // write error を握りつぶしている('A`)
        }
    }
    
    static func DoCopy(from:Realm, to:Realm, progress:(String)->Void) {
        CopySpeechModSetting(from: from, to: to)
        CopySpeechWaitConfig(from: from, to: to)
        CopySpeakerSetting(from: from, to: to)
        CopySpeechSectionConfig(from: from, to: to)
        CopySpeechQueue(from: from, to: to)
        CopyGlobalState(from: from, to: to)
        CopyDisplaySetting(from: from, to: to)
        CopyNovelTag(from: from, to: to)
        CopySpeechOverrideSetting(from: from, to: to)
        CopyNovels(from: from, to: to)
        CopyStorys(from: from, to: to)
    }
}
