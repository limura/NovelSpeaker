//
//  LocalRealmToCloudRealmCopyTool.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/31.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift
import IceCream

class RealmToRealmCopyTool: NSObject {
    static func CopyStorys(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmStoryBulk.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_Story", comment: "小説本文を移行中") + " (\(index)/\(maxCount))")
            to.beginWrite()
            let newObj = RealmStoryBulk()
            newObj.novelID = obj.novelID
            newObj.id = obj.id
            newObj.chapterNumber = obj.chapterNumber
            newObj.isDeleted = obj.isDeleted
            if let zipedData = obj.storyListAsset?.storedData(), let storyListAsset = CreamAsset.create(object: newObj, propName: "", data: zipedData) {
                newObj.storyListAsset = storyListAsset
            }
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }
    static func CopyNovels(from:Realm, to:Realm, progress: (String)->Void) throws {
        let objects = from.objects(RealmNovel.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_Novel", comment: "小説情報を移行中") + " (\(index)/\(maxCount))")
            to.beginWrite()
            let newObj = RealmNovel()
            newObj.novelID = obj.novelID
            newObj.isDeleted = obj.isDeleted
            newObj.m_type = obj.m_type
            newObj.writer = obj.writer
            newObj.title = obj.title
            newObj.url = obj.url
            newObj.createdDate = obj.createdDate
            newObj.isNeedSpeechAfterDelete = obj.isNeedSpeechAfterDelete
            newObj.defaultSpeakerID = obj.defaultSpeakerID
            newObj.isNotNeedUpdateCheck = obj.isNotNeedUpdateCheck
            newObj.m_lastChapterStoryID = obj.m_lastChapterStoryID
            newObj.lastDownloadDate = obj.lastDownloadDate
            newObj.m_readingChapterStoryID = obj.m_readingChapterStoryID
            newObj.lastReadDate = obj.lastReadDate
            newObj.downloadDateArray.removeAll()
            for date in obj.downloadDateArray {
                newObj.AppendDownloadDate(realm: to, date: date)
            }
            newObj.m_readingChapterReadingPoint = obj.m_readingChapterReadingPoint
            newObj.m_readingChapterContentCount = obj.m_readingChapterContentCount
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopySpeechModSetting(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmSpeechModSetting.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_SpeechModSetting", comment: "読み替え辞書を移行中") + " (\(index)/\(maxCount))")
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

    static func CopySpeechWaitConfig(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmSpeechWaitConfig.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_SpeechWaitConfig", comment: "読み上げ時の間の設定を移行中") + " (\(index)/\(maxCount))")
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

    static func CopySpeakerSetting(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmSpeakerSetting.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_SpeakerSetting", comment: "話者設定を移行中") + " (\(index)/\(maxCount))")
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

    static func CopySpeechSectionConfig(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmSpeechSectionConfig.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_SpeechSectionConfig", comment: "話者変更設定を移行中") + " (\(index)/\(maxCount))")
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

    static func CopyGlobalState(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmGlobalState.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_GlobalState", comment: "全体設定を移行中") + " (\(index)/\(maxCount))")
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
            newObj.IsDisallowsCellularAccess = obj.IsDisallowsCellularAccess
            newObj.IsNeedConfirmDeleteBook = obj.IsNeedConfirmDeleteBook
            newObj.isLicenseReaded = obj.isLicenseReaded
            newObj.isDuckOthersEnabled = obj.isDuckOthersEnabled
            newObj.isMixWithOthersEnabled = obj.isMixWithOthersEnabled
            newObj.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = obj.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled
            newObj.fgColor = obj.fgColor
            newObj.bgColor = obj.bgColor
            newObj.isPlaybackDurationEnabled = obj.isPlaybackDurationEnabled
            newObj.isShortSkipEnabled = obj.isShortSkipEnabled
            newObj.isReadingProgressDisplayEnabled = obj.isReadingProgressDisplayEnabled
            //newObj.isForceSiteInfoReloadIsEnabled = obj.isForceSiteInfoReloadIsEnabled
            newObj.isMenuItemIsAddNovelSpeakerItemsOnly = obj.isMenuItemIsAddNovelSpeakerItemsOnly
            newObj.isPageTurningSoundEnabled = obj.isPageTurningSoundEnabled
            newObj.m_bookSelfSortType = obj.m_bookSelfSortType
            newObj.defaultDisplaySettingID = obj.defaultDisplaySettingID
            newObj.defaultSpeakerID = obj.defaultSpeakerID
            newObj.currentReadingNovelID = obj.currentReadingNovelID
            newObj.currentWebSearchSite = obj.currentWebSearchSite
            newObj.autoSplitStringList.removeAll()
            newObj.autoSplitStringList.append(objectsIn: obj.autoSplitStringList)
            newObj.novelSpeakerSiteInfoURL = obj.novelSpeakerSiteInfoURL
            newObj.autopagerizeSiteInfoURL = obj.autopagerizeSiteInfoURL
            newObj.defaultSpeechModURL = obj.defaultSpeechModURL
            newObj.searchInfoURL = obj.searchInfoURL
            newObj.speechViewButtonSettingArrayData = obj.speechViewButtonSettingArrayData
            newObj.cookieArrayData = obj.cookieArrayData
            newObj.m_DisplayType = obj.m_DisplayType
            newObj.bookshelfViewButtonSettingArrayData = obj.bookshelfViewButtonSettingArrayData
            newObj.m_repeatSpeechType = obj.m_repeatSpeechType
            newObj.isAnnounceAtRepatSpeechTime = obj.isAnnounceAtRepatSpeechTime
            newObj.isOverrideRubyIsEnabled = obj.isOverrideRubyIsEnabled
            newObj.notRubyCharactorStringArray = obj.notRubyCharactorStringArray
            newObj.isIgnoreURIStringSpeechEnabled = obj.isIgnoreURIStringSpeechEnabled
            newObj.isEnableSwipeOnStoryView = obj.isEnableSwipeOnStoryView
            newObj.novelLikeOrder.removeAll()
            newObj.novelLikeOrder.append(objectsIn: obj.novelLikeOrder)

            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func CopyDisplaySetting(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmDisplaySetting.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_DisplaySetting", comment: "表示文字等の設定を移行中") + " (\(index)/\(maxCount))")
            to.beginWrite()
            let newObj = RealmDisplaySetting()
            newObj.isDeleted = obj.isDeleted
            newObj.name = obj.name
            newObj.textSizeValue = obj.textSizeValue
            newObj.lineSpacing = obj.lineSpacing
            newObj.fontID = obj.fontID
            newObj.isVertical = obj.isVertical
            newObj.createdDate = obj.createdDate
            newObj.targetNovelIDArray.removeAll()
            newObj.targetNovelIDArray.append(objectsIn: obj.targetNovelIDArray)
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }
    
    static func CopyNovelTag(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmNovelTag.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_NovelTag", comment: "タグを移行中") + " (\(index)/\(maxCount))")
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

    static func CopyBookmark(from:Realm, to:Realm, progress:(String)->Void) throws {
        let objects = from.objects(RealmBookmark.self)
        let maxCount = objects.count
        for (index, obj) in objects.enumerated() {
            progress(NSLocalizedString("RealmToRealmCopyTool_Progress_Bookmark", comment: "栞を移行中") + " (\(index)/\(maxCount))")
            to.beginWrite()
            let newObj = RealmBookmark()
            newObj.id = obj.id
            newObj.isDeleted = obj.isDeleted
            newObj.createdDate = obj.createdDate
            newObj.novelID = obj.novelID
            newObj.chapterNumber = obj.chapterNumber
            newObj.location = obj.location
            to.add(newObj, update: .modified)
            try to.commitWrite()
        }
    }

    static func DoCopy(from:Realm, to:Realm, progress:(String)->Void) throws {
        try CopySpeechModSetting(from: from, to: to, progress: progress)
        try CopySpeechWaitConfig(from: from, to: to, progress: progress)
        try CopySpeakerSetting(from: from, to: to, progress: progress)
        try CopySpeechSectionConfig(from: from, to: to, progress: progress)
        try CopyGlobalState(from: from, to: to, progress: progress)
        try CopyDisplaySetting(from: from, to: to, progress: progress)
        try CopyNovelTag(from: from, to: to, progress: progress)
        try CopyBookmark(from: from, to: to, progress: progress)
        try CopyNovels(from: from, to: to, progress: progress)
        try CopyStorys(from: from, to: to, progress: progress)
    }
}
