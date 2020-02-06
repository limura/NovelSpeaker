//
//  NovelSpeakerUtility.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/24.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Zip
import RealmSwift
import AVFoundation

class NovelSpeakerUtility: NSObject {
    static let privacyPolicyURL = URL(string: "https://raw.githubusercontent.com/limura/NovelSpeaker/master/PrivacyPolicy.txt")
    static let privacyPolicyKey = "NovelSpeaker_ReadedPrivacyPolicy"
    static func GetReadedPrivacyPolicy() -> String {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [privacyPolicyKey : ""])
        return defaults.string(forKey: privacyPolicyKey) ?? ""
    }
    static func SetPrivacyPolicyIsReaded(readedText:String) {
        UserDefaults.standard.set(readedText, forKey: privacyPolicyKey)
    }
    
    static func defaultSpeechModSettings() -> [String:String] {
        // static let defaultSpeechModSettings:[String:Sring] = ["hoge": "hoge", ... ] というので作ったんだけど
        // 実行時にそれを参照すると落ちるのでリソースファイルから読み込むように変更した。heap でも食い尽くしてるん？(´・ω・`)
        guard let path = Bundle.main.path(forResource: "DefaultSpeechModList", ofType: "json"), let handle = FileHandle(forReadingAtPath: path) else { return [:] }
        let data = handle.readDataToEndOfFile()
        let json:Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
        }catch{
            return [:]
        }
        guard let result = json as? [String:String] else { return [:] }
        return result
    }
    static let defaultRegexpSpeechModSettings:[String:String] = [
        "([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)\\s*[〜]\\s*([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)": "$1から$2", // 100〜200 → 100から200
        "([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)\\s*話": "$1は"
    ]

    /// 読み上げ時にハングするような文字を読み上げ時にハングしない文字に変換するようにする読み替え辞書を強制的に登録します
    @objc static func ForceOverrideHungSpeakStringToSpeechModSettings() {
        let targets = ["*": " "]
        autoreleasepool {
            RealmUtil.Write { (realm) in
                for (before, after) in targets {
                    if let setting = RealmSpeechModSetting.SearchFrom(beforeString: before) {
                        setting.after = after
                        setting.isUseRegularExpression = false
                        continue
                    }
                    let speechModSetting = RealmSpeechModSetting()
                    speechModSetting.before = before
                    speechModSetting.after = after
                    speechModSetting.isUseRegularExpression = false
                    speechModSetting.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                    realm.add(speechModSetting, update: .modified)
                }
            }
        }
    }

    // 標準の読み替え辞書を上書き登録します。
    static func OverrideDefaultSpeechModSettings() {
        autoreleasepool {
            RealmUtil.Write { (realm) in
                for (before, after) in defaultSpeechModSettings() {
                    if let setting = RealmSpeechModSetting.SearchFrom(beforeString: before) {
                        setting.after = after
                        setting.isUseRegularExpression = false
                        continue
                    }
                    let speechModSetting = RealmSpeechModSetting()
                    speechModSetting.before = before
                    speechModSetting.after = after
                    speechModSetting.isUseRegularExpression = false
                    speechModSetting.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                    realm.add(speechModSetting, update: .modified)
                }
                for (before, after) in defaultRegexpSpeechModSettings {
                    if let setting = RealmSpeechModSetting.SearchFrom(beforeString: before) {
                        setting.after = after
                        setting.isUseRegularExpression = true
                        continue
                    }
                    let speechModSetting = RealmSpeechModSetting()
                    speechModSetting.before = before
                    speechModSetting.after = after
                    speechModSetting.isUseRegularExpression = true
                    speechModSetting.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                    realm.add(speechModSetting, update: .modified)
                }
            }
        }
    }

    // 保存されている読み替え辞書の中から、標準の読み替え辞書を全て削除します
    static func RemoveAllDefaultSpeechModSettings() {
        autoreleasepool {
            guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjects() else { return }
            var removeTargetArray:[RealmSpeechModSetting] = []
            for targetSpeechModSetting in allSpeechModSettings {
                var hit = false
                for (before, after) in defaultSpeechModSettings() {
                    if targetSpeechModSetting.before == before && targetSpeechModSetting.after == after && targetSpeechModSetting.isUseRegularExpression != true {
                        removeTargetArray.append(targetSpeechModSetting)
                        hit = true
                        break
                    }
                }
                if hit { continue }
                for (before, after) in defaultRegexpSpeechModSettings {
                    if targetSpeechModSetting.before == before && targetSpeechModSetting.after == after && targetSpeechModSetting.isUseRegularExpression == true {
                        removeTargetArray.append(targetSpeechModSetting)
                        break
                    }
                }
            }
            RealmUtil.Write { (realm) in
                for targetSpeechModSetting in removeTargetArray {
                    targetSpeechModSetting.delete(realm: realm)
                }
            }
        }
    }
    
    // 保存されている全ての読み替え辞書を削除します
    static func RemoveAllSpeechModSettings() {
        autoreleasepool {
            guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjects() else { return }
            RealmUtil.Write { (realm) in
                for targetSpeechModSetting in allSpeechModSettings {
                    targetSpeechModSetting.delete(realm: realm)
                }
            }
        }
    }
    
    // 指定された realm に、必須データが入っているか否かを判定します。
    static func CheckDefaultSettingsAlive(realm:Realm) -> Bool {
        guard let globalState = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID) else { return false }
        if globalState.defaultSpeakerID.count <= 0
            || globalState.defaultDisplaySettingID.count <= 0
            || globalState.defaultSpeechOverrideSettingID.count <= 0
            || globalState.webImportBookmarkArray.count <= 0 {
            return false
        }
        if realm.objects(RealmSpeakerSetting.self).count <= 0 { return false }
        if realm.objects(RealmSpeechSectionConfig.self).count <= 0 { return false }
        if realm.objects(RealmSpeechWaitConfig.self).count <= 0 { return false }
        if realm.objects(RealmSpeechModSetting.self).count <= 0 { return false }
        return true
    }
    // 標準設定を入れます。結構時間かかるのでバックグラウンドで行われます
    @objc static func InsertDefaultSettingsIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            autoreleasepool {
                let globalState:RealmGlobalState
                if let tmpGlobalState = RealmGlobalState.GetInstance() {
                    globalState = tmpGlobalState
                }else{
                    globalState = RealmGlobalState()
                    RealmUtil.Write(block: { (realm) in
                        realm.add(globalState, update: .modified)
                    })
                }
                RealmUtil.Write(block: { (realm) in
                    if globalState.defaultDisplaySetting == nil {
                        let defaultDisplaySetting = RealmDisplaySetting()
                        defaultDisplaySetting.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
                        globalState.defaultDisplaySettingID = defaultDisplaySetting.name
                        realm.add(defaultDisplaySetting, update: .modified)
                    }
                    if globalState.defaultSpeaker == nil {
                        let defaultSpeaker = RealmSpeakerSetting()
                        defaultSpeaker.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
                        globalState.defaultSpeakerID = defaultSpeaker.name
                        realm.add(defaultSpeaker, update: .modified)
                    }
                    if globalState.defaultSpeechOverrideSetting == nil {
                        let defaultSpeechOverrideSetting = RealmSpeechOverrideSetting()
                        defaultSpeechOverrideSetting.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
                        globalState.defaultSpeechOverrideSettingID = defaultSpeechOverrideSetting.name
                        realm.add(defaultSpeechOverrideSetting, update: .modified)
                    }
                    if globalState.webImportBookmarkArray.count <= 0 {
                        let defaultBookmarks = [
                            "小説家になろう\nhttps://syosetu.com/",
                            "青空文庫\nhttp://www.aozora.gr.jp/",
                            "ハーメルン\nhttps://syosetu.org/",
                            "暁\nhttps://www.akatsuki-novels.com/",
                            "カクヨム\nhttps://kakuyomu.jp/",
                            //"アルファポリス\nhttps://www.alphapolis.co.jp/novel/",
                            //"pixiv/ノベル\nhttps://www.pixiv.net/novel/",
                            "星空文庫\nhttps://slib.net/",
                            //"ノベルアップ＋\nhttps://novelup.plus/"
                        ]
                        for bookmark in defaultBookmarks {
                            globalState.webImportBookmarkArray.append(bookmark)
                        }
                    }
                })
            }
            autoreleasepool {
                if RealmSpeechSectionConfig.GetAllObjects()?.count ?? 0 <= 0 {
                    RealmUtil.Write(block: { (realm) in
                        let talk1Speaker = RealmSpeakerSetting()
                        let talk2Speaker = RealmSpeakerSetting()
                        let talk1SectionConfig = RealmSpeechSectionConfig()
                        let talk2SectionConfig = RealmSpeechSectionConfig()
                        
                        talk1Speaker.pitch = 1.5
                        talk1Speaker.name = NSLocalizedString("GlobalDataSingleton_Conversation1", comment: "会話文")
                        talk1SectionConfig.name = NSLocalizedString("GlobalDataSingleton_Conversation1", comment: "会話文")
                        talk1SectionConfig.startText = "「"
                        talk1SectionConfig.endText = "」"
                        talk1SectionConfig.speakerID = talk1Speaker.name
                        talk1SectionConfig.targetNovelIDArray.append(RealmSpeechSectionConfig.anyTarget)

                        talk2Speaker.pitch = 1.2
                        talk2Speaker.name = NSLocalizedString("GlobalDataSingleton_Conversation2", comment: "会話文2")
                        talk2SectionConfig.name = NSLocalizedString("GlobalDataSingleton_Conversation2", comment: "会話文2")
                        talk2SectionConfig.startText = "『"
                        talk2SectionConfig.endText = "』"
                        talk2SectionConfig.speakerID = talk2Speaker.name
                        talk2SectionConfig.targetNovelIDArray.append(RealmSpeechSectionConfig.anyTarget)

                        realm.add(talk1Speaker, update: .modified)
                        realm.add(talk2Speaker, update: .modified)
                        realm.add(talk1SectionConfig, update: .modified)
                        realm.add(talk2SectionConfig, update: .modified)
                    })
                }
            }
            autoreleasepool {
                if RealmSpeechWaitConfig.GetAllObjects()?.count ?? 0 <= 0 {
                    RealmUtil.Write(block: { (realm) in
                        let waitConfig1 = RealmSpeechWaitConfig()
                        waitConfig1.targetText = "\n\n"
                        waitConfig1.delayTimeInSec = 0.5
                        realm.add(waitConfig1, update: .modified)
                        for target in ["……", "。", "、", "・"] {
                            let waitConfig = RealmSpeechWaitConfig()
                            waitConfig.targetText = target
                            waitConfig.delayTimeInSec = 0.0
                            realm.add(waitConfig, update: .modified)
                        }
                    })
                }
            }
            autoreleasepool {
                if RealmSpeechModSetting.GetAllObjects()?.count ?? 0 <= 0 {
                    OverrideDefaultSpeechModSettings()
                }
            }
        }
    }
    
    // タグとして使われる文字として混ざってると変かなという文字を削除します。
    // TODO: String.applyingTransform() で全角から半角にできるみたいなのだけれど、カタカナまで半角にされてしまうのでどうしたもんか
    static func CleanTagString(tag:String) -> String {
        return tag.replacingOccurrences(of: "「", with: "").replacingOccurrences(of: "」", with: "").replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "”", with: "").replacingOccurrences(of: "#", with: "").replacingOccurrences(of: "＃", with: "")
    }
    
    #if !os(watchOS)
    static func ProcessNovelSpeakerURLScheme(url:URL) -> Bool {
        guard let host = url.host else { return false }
        var cookieArray:[String]? = nil
        let targetUrlString:String
        if host == "downloadncode" {
            DispatchQueue.global(qos: .utility).async {
                let ncodeArray = url.path.components(separatedBy: "-")
                for ncode in ncodeArray {
                    guard let targetURL = URL(string: "https://ncode.syosetu.com/\(ncode.lowercased())/") else { continue }
                    let novelID = targetURL.absoluteString
                    autoreleasepool {
                        let novel = RealmNovel.SearchNovelFrom(novelID: novelID) ?? RealmNovel()
                        if novel.novelID != novelID {
                            novel.novelID = novelID
                            novel.url = novelID
                            novel.type = .URL
                            RealmUtil.Write { (realm) in
                                realm.add(novel, update: .modified)
                            }
                        }
                    }
                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                }
            }
            return true
        }else if host == "downloadurl" {
            guard let absoluteString = url.absoluteString.removingPercentEncoding else { return false }
            guard let regex = try? NSRegularExpression(pattern: "^novelspeaker://downloadurl/([^#]*)#?(.*)$", options: []) else { return false }
            let matches = regex.matches(in: absoluteString, options: [], range: NSRange(location: 0, length: absoluteString.count))
            guard matches.count >= 1 else { return false }
            let match = matches[0]
            guard let urlRange = Range(match.range(at: 1), in: absoluteString) else { return false }
            targetUrlString = String(absoluteString[urlRange])
            if let cookieRange = Range(match.range(at: 2), in: absoluteString), let cookieString =    String(absoluteString[cookieRange]).removingPercentEncoding {
                cookieArray = cookieString.components(separatedBy: ";")
            }
        }else{
            return false
        }
        DispatchQueue.main.async {
            guard let targetURL = URL(string: targetUrlString), let rootViewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
            NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: rootViewController, url: targetURL, cookieArray: cookieArray ?? [])
        }
        return true
    }
    #endif
    
    #if !os(watchOS)
    static func ProcessPDFFile(url:URL) -> Bool {
        guard let text = NiftyUtilitySwift.FilePDFToString(url: url) else {
            DispatchQueue.main.async {
                guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: viewController,
                    title: NSLocalizedString("GlobalDataSingleton_PDFToStringFailed_Title", comment: "PDFのテキスト読み込みに失敗"),
                    message: NSLocalizedString("GlobalDataSingleton_PDFToStringFailed_Body", comment: "PDFファイルからの文字列読み込みに失敗しました。\nPDFファイルによっては文字列を読み込めない場合があります。また、iOS11より前のiOSではPDF読み込み機能は動作しません。"),
                    buttonTitle: nil, buttonAction: nil)
            }
            return false
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
            NiftyUtilitySwift.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil)
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessRTFFile(url:URL) -> Bool {
        guard let text = NiftyUtilitySwift.FileRTFToAttributedString(url: url)?.string else {
            DispatchQueue.main.async {
                guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: viewController,
                    title: nil,
                    message: NSLocalizedString("GlobalDataSingleton_RTFToStringFailed_Title", comment: "RTFのテキスト読み込みに失敗"),
                    buttonTitle: nil, buttonAction: nil)
            }
            return false
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
            NiftyUtilitySwift.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil)
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessRTFDFile(url:URL) -> Bool {
        guard let text = NiftyUtilitySwift.FileRTFDToAttributedString(url: url)?.string else {
            DispatchQueue.main.async {
                guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: viewController,
                    title: nil,
                    message: NSLocalizedString("GlobalDataSingleton_RTFToStringFailed_Title", comment: "RTFのテキスト読み込みに失敗"),
                    buttonTitle: nil, buttonAction: nil)
            }
            return false
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
            NiftyUtilitySwift.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil)
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessTextFile(url:URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: NiftyUtilitySwift.DetectEncoding(data: data)) else { return false }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
            NiftyUtilitySwift.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil)
        }
        return true
    }
    #endif

    #if !os(watchOS)
    @objc public static func ProcessURL(url:URL?) -> Bool {
        guard let url = url else { return false }
        let isSecurityScopedURL = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource()}

        if let scheme = url.scheme, scheme == "novelspeaker" || scheme == "limuraproducts.novelspeaker" {
            return ProcessNovelSpeakerURLScheme(url: url)
        }
        if ["novelspeaker-backup-json", "novelspeaker-backup+json", "novelspeaker-backup+zip"].contains(url.pathExtension) {
            return ProcessNovelSpeakerBackupFile(url:url)
        }
        if url.pathExtension == "pdf" {
            return ProcessPDFFile(url:url)
        }
        if url.pathExtension == "rtf" {
            return ProcessRTFFile(url:url)
        }
        if url.pathExtension == "rtfd" {
            return ProcessRTFDFile(url:url)
        }
        return ProcessTextFile(url:url)
    }
    #endif
    
    #if !os(watchOS)
    static func RestoreSpeechMod_V_1_0_0(dic:NSDictionary){
        autoreleasepool {
            guard let speechModArray = RealmSpeechModSetting.GetAllObjects() else { return }
            for (key, value) in dic {
                guard let before = key as? String, let after = value as? String else { continue }
                var hit = false
                for speechMod in speechModArray {
                    if before == speechMod.before {
                        hit = true
                        if speechMod.after != after {
                            RealmUtil.Write { (realm) in
                                speechMod.after = after
                            }
                        }
                        break
                    }
                }
                if !hit {
                    RealmUtil.Write { (realm) in
                        let speechMod = RealmSpeechModSetting()
                        speechMod.before = before
                        speechMod.after = after
                        speechMod.isUseRegularExpression = false
                        speechMod.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                        realm.add(speechMod)
                    }
                }
            }
        }
    }
    static func RestoreSpeechMod_V_1_1_0(dic: NSDictionary) {
        autoreleasepool {
            guard let speechModArray = RealmSpeechModSetting.GetAllObjects() else { return }
            for (key, value) in dic {
                guard let valueDic = value as? NSDictionary, let before = key as? String, let after = valueDic.object(forKey: "afterString") as? String, let type = (valueDic.object(forKey: "type") as? NSNumber)?.intValue else { continue }
                var hit = false
                for speechMod in speechModArray {
                    if before == speechMod.before {
                        hit = true
                        if speechMod.after != after || speechMod.isUseRegularExpression != true {
                            RealmUtil.Write { (realm) in
                                speechMod.after = after
                                speechMod.isUseRegularExpression = type == Int(SpeechModSettingConvertType.regexp.rawValue)
                            }
                        }
                        break
                    }
                }
                if !hit {
                    RealmUtil.Write { (realm) in
                        let speechMod = RealmSpeechModSetting()
                        speechMod.before = before
                        speechMod.after = after
                        speechMod.isUseRegularExpression = type == Int(SpeechModSettingConvertType.regexp.rawValue)
                        speechMod.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                        realm.add(speechMod, update: .modified)
                    }
                }
            }
        }
    }

    static func RestoreWebImportBookmarks_V_1_0_0(array: NSArray) {
        autoreleasepool {
            guard let globalStatus = RealmGlobalState.GetInstance() else { return }
            RealmUtil.Write { (realm) in
                for target in array {
                    guard let target = target as? NSDictionary else { continue }
                    for (key, value) in target {
                        guard let name = key as? String, let url = value as? String else { continue }
                        let bookmark = "\(name)\n\(url)"
                        if globalStatus.webImportBookmarkArray.contains(bookmark) { continue }
                        globalStatus.webImportBookmarkArray.append(bookmark)
                    }
                }
            }
        }
    }
    
    static func RestoreSpeakPitch_V_1_0_0(dic:NSDictionary) {
        autoreleasepool {
            guard let defaultSpeaker = RealmGlobalState.GetInstance()?.defaultSpeaker else { return }
            if let defaultDictionary = dic.object(forKey: "default") as? NSDictionary, let pitch = defaultDictionary.object(forKey: "pitch") as? NSNumber, let rate = defaultDictionary.object(forKey: "rate") as? NSNumber {
                RealmUtil.Write { (realm) in
                    let pitchValue = pitch.floatValue
                    let rateValue = rate.floatValue
                    if pitchValue >= 0.5 && pitchValue <= 2.0 {
                        defaultSpeaker.pitch = pitch.floatValue
                    }
                    if rateValue >= AVSpeechUtteranceMinimumSpeechRate && rateValue <= AVSpeechUtteranceMaximumSpeechRate {
                        defaultSpeaker.rate = rate.floatValue
                    }
                }
            }
            autoreleasepool {
                guard let othersArray = dic.object(forKey: "others") as? NSArray, let speechSectionArray = RealmSpeechSectionConfig.GetAllObjects() else { return }
                for obj in othersArray {
                    guard let dic = obj as? NSDictionary,
                        let title = dic.object(forKey: "title") as? String,
                        let start_text = dic.object(forKey: "start_text") as? String,
                        let end_text = dic.object(forKey: "end_text") as? String,
                        let pitch = dic.object(forKey: "pitch") as? NSNumber else { continue }
                    let pitchValue = pitch.floatValue
                    if pitchValue < 0.5 || pitchValue > 2.0 { continue }
                    autoreleasepool {
                        if let speaker = RealmSpeakerSetting.SearchFrom(name: title) {
                            RealmUtil.Write { (realm) in
                                speaker.pitch = pitchValue
                            }
                            if let section = speechSectionArray.filter("startText = %@ AND endText = %@", start_text, end_text).first {
                                RealmUtil.Write { (realm) in
                                    section.speakerID = speaker.name
                                }
                            }else{
                                RealmUtil.Write { (realm) in
                                    let section = RealmSpeechSectionConfig()
                                    section.speakerID = speaker.name
                                    section.name = speaker.name
                                    section.startText = start_text
                                    section.endText = end_text
                                    section.targetNovelIDArray.append(RealmSpeechSectionConfig.anyTarget)
                                    realm.add(section, update: .modified)
                                }
                            }
                        }else{
                            let speaker = RealmSpeakerSetting()
                            speaker.pitch = pitchValue
                            speaker.name = title
                            speaker.voiceIdentifier = defaultSpeaker.voiceIdentifier
                            speaker.rate = defaultSpeaker.rate
                            RealmUtil.Write { (realm) in
                                realm.add(speaker)
                            }
                            if let section = speechSectionArray.filter("startText = %@ AND endText = %@", start_text, end_text).first {
                                RealmUtil.Write { (realm) in
                                    section.speakerID = speaker.name
                                }
                            }else{
                                RealmUtil.Write { (realm) in
                                    let section = RealmSpeechSectionConfig()
                                    section.speakerID = speaker.name
                                    section.name = speaker.name
                                    section.startText = start_text
                                    section.endText = end_text
                                    section.targetNovelIDArray.append(RealmSpeechSectionConfig.anyTarget)
                                    realm.add(section, update: .modified)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    static func RestoreSpeechWaitConfig_V_1_0_0(waitArray:NSArray) {
        for dic in waitArray {
            if let dic = dic as? NSDictionary, let target_text = dic.object(forKey: "target_text") as? String, let delay_time_in_sec = dic.object(forKey: "delay_time_in_sec") as? NSNumber, target_text.count > 0 && delay_time_in_sec.floatValue >= 0 {
                let delayTimeInSec = delay_time_in_sec.floatValue
                // 改行の保存形式は \r\n から \n に変更されました。
                let targetText = target_text.replacingOccurrences(of: "\r", with: "")
                autoreleasepool {
                    if let speechWaitConfig = RealmSpeechWaitConfig.GetAllObjects()?.filter("targetText = %@", targetText).first {
                        RealmUtil.Write { (realm) in
                            speechWaitConfig.delayTimeInSec = delayTimeInSec
                        }
                    }else{
                        let speechWaitConfig = RealmSpeechWaitConfig()
                        speechWaitConfig.delayTimeInSec = delayTimeInSec
                        speechWaitConfig.targetText = targetText
                        RealmUtil.Write { (realm) in
                            realm.add(speechWaitConfig)
                        }
                    }
                }
            }
        }
    }
    
    static func RestoreMiscSettings_V_1_0_0(dic:NSDictionary) -> String? {
        return autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance(), let defaultSpeaker = globalState.defaultSpeaker, let speechOverrideSetting = globalState.defaultSpeechOverrideSetting, let defaultDisplaySetting = globalState.defaultDisplaySetting else { return nil }
            var currentReadingContent:String? = nil
            RealmUtil.Write { (realm) in
                if let max_speech_time_in_sec = dic.value(forKey: "max_speech_time_in_sec") as? NSNumber {
                    globalState.maxSpeechTimeInSec = max_speech_time_in_sec.intValue
                }
                if let text_size_value = dic.value(forKey: "text_size_value") as? NSNumber {
                    let value = text_size_value.floatValue
                    if value >= 1.0 || value <= 100 {
                        defaultDisplaySetting.textSizeValue = value
                    }
                }
                if let speech_wait_setting_use_experimental_wait = dic.value(forKey: "speech_wait_setting_use_experimental_wait") as? NSNumber {
                    globalState.isSpeechWaitSettingUseExperimentalWait = speech_wait_setting_use_experimental_wait.boolValue
                }
                if let default_voice_identifier = dic.value(forKey: "default_voice_identifier") as? String {
                    defaultSpeaker.voiceIdentifier = default_voice_identifier
                }
                if let content_sort_type = dic.value(forKey: "content_sort_type") as? NSNumber {
                    globalState.bookShelfSortType = NarouContentSortType(rawValue: content_sort_type.uintValue) ?? NarouContentSortType.title
                }
                if let menuitem_is_add_speech_mod_setting_only = dic.value(forKey: "menuitem_is_add_speech_mod_setting_only") as? NSNumber {
                    globalState.isMenuItemIsAddNovelSpeakerItemsOnly = menuitem_is_add_speech_mod_setting_only.boolValue
                }
                if let override_ruby_is_enabled = dic.value(forKey: "override_ruby_is_enabled") as? NSNumber {
                    speechOverrideSetting.isOverrideRubyIsEnabled = override_ruby_is_enabled.boolValue
                }
                if let is_ignore_url_speech_enabled = dic.value(forKey: "is_ignore_url_speech_enabled") as? NSNumber {
                    speechOverrideSetting.isIgnoreURIStringSpeechEnabled = is_ignore_url_speech_enabled.boolValue
                }
                if let not_ruby_charactor_array = dic.value(forKey: "not_ruby_charactor_array") as? String {
                    speechOverrideSetting.notRubyCharactorStringArray = not_ruby_charactor_array
                }
                if let force_siteinfo_reload_is_enabled = dic.value(forKey: "force_siteinfo_reload_is_enabled") as? NSNumber {
                    globalState.isForceSiteInfoReloadIsEnabled = force_siteinfo_reload_is_enabled.boolValue
                }
                if let is_reading_progress_display_enabled = dic.value(forKey: "is_reading_progress_display_enabled") as? NSNumber {
                    globalState.isReadingProgressDisplayEnabled = is_reading_progress_display_enabled.boolValue
                }
                if let is_short_skip_enabled = dic.value(forKey: "is_short_skip_enabled") as? NSNumber {
                    globalState.isShortSkipEnabled = is_short_skip_enabled.boolValue
                }
                if let is_playback_duration_enabled = dic.value(forKey: "is_playback_duration_enabled") as? NSNumber {
                    globalState.isPlaybackDurationEnabled = is_playback_duration_enabled.boolValue
                }
                if let is_page_turning_sound_enabled = dic.value(forKey: "is_page_turning_sound_enabled") as? NSNumber {
                    globalState.isPageTurningSoundEnabled = is_page_turning_sound_enabled.boolValue
                }
                if let display_font_name = dic.value(forKey: "display_font_name") as? String {
                    defaultDisplaySetting.fontID = display_font_name
                }
                if let repeat_speech_type = dic.value(forKey: "repeat_speech_type") as? NSNumber {
                    speechOverrideSetting.repeatSpeechType = RepeatSpeechType(rawValue: repeat_speech_type.uintValue) ?? RepeatSpeechType.noRepeat
                }
                /* /// この設定はバックアップデータからの読み込みを停止します
                if let is_escape_about_speech_position_display_bug_on_ios12_enabled = dic.value(forKey: "is_escape_about_speech_position_display_bug_on_ios12_enabled") as? NSNumber {
                    globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = is_escape_about_speech_position_display_bug_on_ios12_enabled.boolValue
                }
                 */
                if let is_mix_with_others_enabled = dic.value(forKey: "is_mix_with_others_enabled") as? NSNumber {
                    globalState.isMixWithOthersEnabled = is_mix_with_others_enabled.boolValue
                }
                if let is_duck_others_enabled = dic.value(forKey: "is_duck_others_enabled") as? NSNumber {
                    globalState.isDuckOthersEnabled = is_duck_others_enabled.boolValue
                }
                if let is_open_recent_novel_in_start_time_enabled = dic.value(forKey: "is_open_recent_novel_in_start_time_enabled") as? NSNumber {
                    globalState.isOpenRecentNovelInStartTime = is_open_recent_novel_in_start_time_enabled.boolValue
                }
                if let is_disallows_cellular_access = dic.value(forKey: "is_disallows_cellular_access") as? NSNumber {
                    globalState.IsDisallowsCellularAccess = is_disallows_cellular_access.boolValue
                }
                if let is_need_confirm_delete_book = dic.value(forKey: "is_need_confirm_delete_book") as? NSNumber {
                    globalState.IsNeedConfirmDeleteBook = is_need_confirm_delete_book.boolValue
                }
                if let display_color_settings = dic.value(forKey: "display_color_settings") as? NSDictionary {
                    if let background = display_color_settings.value(forKey: "background") as? NSDictionary, let red = background.value(forKey: "red") as? NSNumber, let green = background.value(forKey: "green") as? NSNumber, let blue = background.value(forKey: "blue") as? NSNumber, let alpha = background.value(forKey: "alpha") as? NSNumber {
                        globalState.backgroundColor = UIColor(red: CGFloat(red.floatValue), green: CGFloat(green.floatValue), blue: CGFloat(blue.floatValue), alpha: CGFloat(alpha.floatValue))
                    }
                    if let foreground = display_color_settings.value(forKey: "background") as? NSDictionary, let red = foreground.value(forKey: "red") as? NSNumber, let green = foreground.value(forKey: "green") as? NSNumber, let blue = foreground.value(forKey: "blue") as? NSNumber, let alpha = foreground.value(forKey: "alpha") as? NSNumber {
                        globalState.backgroundColor = UIColor(red: CGFloat(red.floatValue), green: CGFloat(green.floatValue), blue: CGFloat(blue.floatValue), alpha: CGFloat(alpha.floatValue))
                    }
                }
                if let current_reading_content = dic.value(forKey: "current_reading_content") as? String {
                    currentReadingContent = current_reading_content
                }
            }
            return currentReadingContent
        }
    }
    
    static func RestoreBookshelf_ncode_V_1_0_0(novel:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        autoreleasepool {
            guard let ncode = novel.object(forKey: "ncode") as? String else { return }
            RealmUtil.Write { (realm) in
                let urlString = CoreDataToRealmTool.NcodeToUrlString(ncode: ncode, no: 1, end: false)
                let realmNovel = RealmNovel.SearchNovelFrom(novelID: urlString) ?? RealmNovel()
                if realmNovel.novelID != urlString {
                    realmNovel.novelID = urlString
                }
                let novelID = realmNovel.novelID
                let currentReadingChapterNumber:Int
                if let current_reading_chapter_number = novel.object(forKey: "current_reading_chapter_number") as? NSNumber {
                    currentReadingChapterNumber = current_reading_chapter_number.intValue
                    realmNovel.m_readingChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: currentReadingChapterNumber)
                    if let currentReadLocation = novel.object(forKey: "current_reading_chapter_read_location") as? NSNumber {
                        Story.SetReadLocationWith(realm: realm, novelID: novelID, chapterNumber: currentReadingChapterNumber, location: currentReadLocation.intValue)
                    }
                }else{
                    currentReadingChapterNumber = 0
                }
                let isNewFlug:Bool
                if let is_new_flug = novel.object(forKey: "is_new_flug") as? NSNumber {
                    isNewFlug = is_new_flug.boolValue
                }else{
                    isNewFlug = false
                }
                if let novelupdated_at = novel.object(forKey: "novelupdated_at") as? String, let lastDownloadDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: novelupdated_at) {
                    realmNovel.lastDownloadDate = lastDownloadDate
                    if isNewFlug {
                        realmNovel.lastReadDate = lastDownloadDate.addingTimeInterval(-1)
                    }else{
                        realmNovel.lastReadDate = lastDownloadDate.addingTimeInterval(1)
                    }
                }else{
                    if isNewFlug {
                        realmNovel.lastDownloadDate = Date(timeIntervalSinceNow: 0)
                        realmNovel.lastReadDate = Date(timeIntervalSinceNow: -1)
                    }else{
                        realmNovel.lastDownloadDate = Date(timeIntervalSinceNow: -1)
                        realmNovel.lastReadDate = Date(timeIntervalSinceNow: 0)
                    }
                }
                realmNovel.url = urlString
                realmNovel.type = .URL
                if let writer = novel.object(forKey: "writer") as? String {
                    realmNovel.writer = writer
                }
                if let title = novel.object(forKey: "title") as? String {
                    realmNovel.title = title
                }
                realm.add(realmNovel, update: .modified)
                if let keyword = novel.object(forKey: "keyword") as? String {
                    for tag in keyword.components(separatedBy: CharacterSet.whitespacesAndNewlines) {
                        let tagName = CleanTagString(tag: tag)
                        RealmNovelTag.AddTag(realm: realm, name: tagName, novelID: novelID, type: RealmNovelTag.TagType.Keyword)
                    }
                }

                if let content_directory = novel.object(forKey: "content_directory") as? String, let contentDirectory = extractedDirectory?.appendingPathComponent(content_directory, isDirectory: true), let end = novel.object(forKey: "end") as? NSNumber {
                    var no = 0
                    var storyArray:[Story] = []
                    repeat {
                        no += 1
                        let targetFilePath = contentDirectory.appendingPathComponent("\(no).txt")
                        guard let data = try? Data(contentsOf: targetFilePath), let content = String(data: data, encoding: NiftyUtilitySwift.DetectEncoding(data: data))  else { break }
                        var story = Story()
                        story.novelID = novelID
                        story.chapterNumber = no
                        story.content = content
                        story.url = CoreDataToRealmTool.NcodeToUrlString(ncode: ncode, no: no, end: end.boolValue)
                        storyArray.append(story)
                        if storyArray.count >= RealmStoryBulk.bulkCount {
                            RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                            storyArray.removeAll()
                        }
                    }while(true)
                    if storyArray.count > 0 {
                        RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                        storyArray.removeAll()
                    }
                    for _ in 0..<no {
                        realmNovel.AppendDownloadDate(date: realmNovel.lastDownloadDate, realm: realm)
                    }
                }else{
                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                }
            }
        }
    }

    static func RestoreBookshelf_url_V_1_0_0(novel:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        autoreleasepool {
            guard let url = novel.object(forKey: "url") as? String else { return }
            RealmUtil.Write { (realm) in
                let realmNovel = RealmNovel.SearchNovelFrom(novelID: url) ?? RealmNovel()
                if realmNovel.novelID != url {
                    realmNovel.novelID = url
                    realmNovel.url = url
                    realmNovel.type = .URL
                }
                let novelID = realmNovel.novelID
                let currentReadingChapterNumber:Int
                if let current_reading_chapter_number = (novel.object(forKey: "current_reading_chapter_number") as? NSNumber)?.intValue {
                    currentReadingChapterNumber = current_reading_chapter_number
                    if let currentReadLocation = novel.object(forKey: "current_reading_chapter_read_location") as? NSNumber {
                        Story.SetReadLocationWith(realm: realm, novelID: novelID, chapterNumber: currentReadingChapterNumber, location: currentReadLocation.intValue)
                    }
                }else{
                    currentReadingChapterNumber = 0
                }
                let isNewFlug:Bool
                if let is_new_flug = novel.object(forKey: "is_new_flug") as? NSNumber {
                    isNewFlug = is_new_flug.boolValue
                }else{
                    isNewFlug = false
                }
                if let novelupdated_at = novel.object(forKey: "novelupdated_at") as? String, let lastDownloadDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: novelupdated_at) {
                    realmNovel.lastDownloadDate = lastDownloadDate
                    if isNewFlug {
                        realmNovel.lastReadDate = lastDownloadDate.addingTimeInterval(-1)
                    }else{
                        realmNovel.lastReadDate = lastDownloadDate.addingTimeInterval(1)
                    }
                }else{
                    if isNewFlug {
                        realmNovel.lastDownloadDate = Date(timeIntervalSinceNow: 0)
                        realmNovel.lastReadDate = Date(timeIntervalSinceNow: -1)
                    }else{
                        realmNovel.lastDownloadDate = Date(timeIntervalSinceNow: -1)
                        realmNovel.lastReadDate = Date(timeIntervalSinceNow: 0)
                    }
                }
                if let title = novel.object(forKey: "title") as? String {
                    realmNovel.title = title
                }
                if let secret = novel.object(forKey: "secret") as? String, let urlSecret = NiftyUtility.stringDecrypt(secret, key: url) {
                    realmNovel.m_urlSecret = urlSecret
                }
                if let author = novel.object(forKey: "author") as? String {
                    realmNovel.writer = author
                }
                if currentReadingChapterNumber > 0 {
                    realmNovel.m_readingChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: currentReadingChapterNumber)
                }
                realm.add(realmNovel, update: .modified)
                if let content_directory = novel.object(forKey: "content_directory") as? String, let contentDirectory = extractedDirectory?.appendingPathComponent(content_directory, isDirectory: true) {
                    var no = 0
                    var storyArray:[Story] = []
                    repeat {
                        no += 1
                        let targetFilePath = contentDirectory.appendingPathComponent("\(no).txt")
                        guard let data = try? Data(contentsOf: targetFilePath), let content = String(data: data, encoding: NiftyUtilitySwift.DetectEncoding(data: data))  else { break }
                        var story = Story()
                        story.novelID = novelID
                        story.chapterNumber = no
                        story.content = content
                        storyArray.append(story)
                        if storyArray.count >= RealmStoryBulk.bulkCount {
                            RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                            storyArray.removeAll()
                        }
                    }while(true)
                    if storyArray.count > 0 {
                        RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                        storyArray.removeAll()
                    }
                    for _ in 0..<no {
                        realmNovel.AppendDownloadDate(date: realmNovel.lastDownloadDate, realm: realm)
                    }
                    no -= 1
                    if no > 0, var story = RealmStoryBulk.SearchStory(novelID: novelID, chapterNumber: no), let last_download_url = novel.object(forKey: "last_download_url") as? String {
                        story.url = last_download_url
                        RealmStoryBulk.SetStory(story: story)
                    }
                }else{
                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                }
            }
        }
    }

    static func RestoreBookshelf_user_V_1_0_0(novel:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        autoreleasepool {
            guard let id = novel.object(forKey: "id") as? String, let title = novel.object(forKey: "title") as? String, let storys = novel.object(forKey: "storys") as? NSArray else { return }
            let novelID = "https://example.com/" + id
            let realmNovel = RealmNovel.SearchNovelFrom(novelID: novelID) ?? RealmNovel()
            if realmNovel.novelID != novelID {
                realmNovel.novelID = novelID
                realmNovel.type = .UserCreated
            }
            RealmUtil.Write { (realm) in
                realmNovel.title = title
                realm.add(realmNovel, update: .modified)

                var no = 0
                var storyArray:[Story] = []
                for storyText in storys {
                    guard let storyText = storyText as? String else { continue }
                    no += 1
                    var story = Story()
                    story.novelID = novelID
                    story.chapterNumber = no
                    story.content = storyText
                    storyArray.append(story)
                    if storyArray.count >= RealmStoryBulk.bulkCount {
                        RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                        storyArray.removeAll()
                    }
                }
                if storyArray.count > 0 {
                    RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                    storyArray.removeAll()
                }
            }
        }
    }
    
    static func RestoreBookshelf_V_1_0_0(novelArray:NSArray, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        // 一旦ダウンロードは止めておきます。
        NovelDownloadQueue.shared.downloadStop()
        defer { NovelDownloadQueue.shared.downloadStart() }
        var count = 0
        for novel in novelArray {
            count += 1
            progressUpdate(NSLocalizedString("GlobalDataSingleton_RestoreingBookProgress", comment: "小説の復元中") + "(\(count)/\(novelArray.count))")
            guard let novel = novel as? NSDictionary, let type = novel.value(forKey: "type") as? String else { continue }
            switch type {
            case "ncode":
                RestoreBookshelf_ncode_V_1_0_0(novel:novel, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
            case "url":
                RestoreBookshelf_url_V_1_0_0(novel:novel, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
            case "user":
                RestoreBookshelf_user_V_1_0_0(novel:novel, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
            default:
                continue
            }
        }
    }
    
    static func ProcessNovelSpeakerBackupJSONData_V_1_0_0(toplevelDictionary:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
        if let speechModDictionary = toplevelDictionary.object(forKey: "word_replacement_dictionary") as? NSDictionary {
            RestoreSpeechMod_V_1_0_0(dic: speechModDictionary)
        }
        if let webImportBookmarks = toplevelDictionary.object(forKey: "web_import_bookmarks") as? NSArray {
            RestoreWebImportBookmarks_V_1_0_0(array: webImportBookmarks)
        }
        if let speakPitchDictionary = toplevelDictionary.object(forKey: "speak_pitch_config") as? NSDictionary {
            RestoreSpeakPitch_V_1_0_0(dic: speakPitchDictionary)
        }
        if let waitArray = toplevelDictionary.object(forKey: "speech_wait_config") as? NSArray {
            RestoreSpeechWaitConfig_V_1_0_0(waitArray:waitArray)
        }
        let currentReadingNovelID:String?
        if let miscDictionary = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            currentReadingNovelID = RestoreMiscSettings_V_1_0_0(dic:miscDictionary)
        }else{
            currentReadingNovelID = nil
        }
        if let novelArray = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            RestoreBookshelf_V_1_0_0(novelArray:novelArray, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
        }
        autoreleasepool {
            if let targetNovelID = currentReadingNovelID, let globalState = RealmGlobalState.GetInstance() {
                let coreDataNarouContent = NarouContentCacheData()
                coreDataNarouContent.ncode = targetNovelID
                RealmUtil.Write { (realm) in
                    if coreDataNarouContent.isURLContent() {
                        globalState.currentReadingNovelID = targetNovelID
                    }else if targetNovelID.hasPrefix("_u") {
                        globalState.currentReadingNovelID = "https://example.com/" + targetNovelID
                    }else{
                        globalState.currentReadingNovelID = CoreDataToRealmTool.NcodeToUrlString(ncode: targetNovelID, no: 1, end: false)
                    }
                }
            }
        }
        return true
    }
    static func ProcessNovelSpeakerBackupJSONData_V_1_1_0(toplevelDictionary:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
        if let speechModDictionary = toplevelDictionary.object(forKey: "word_replacement_dictionary") as? NSDictionary {
            RestoreSpeechMod_V_1_1_0(dic: speechModDictionary)
        }
        if let webImportBookmarks = toplevelDictionary.object(forKey: "web_import_bookmarks") as? NSArray {
            RestoreWebImportBookmarks_V_1_0_0(array: webImportBookmarks)
        }
        if let speakPitchDictionary = toplevelDictionary.object(forKey: "speak_pitch_config") as? NSDictionary {
            RestoreSpeakPitch_V_1_0_0(dic: speakPitchDictionary)
        }
        if let waitArray = toplevelDictionary.object(forKey: "speech_wait_config") as? NSArray {
            RestoreSpeechWaitConfig_V_1_0_0(waitArray:waitArray)
        }
        let currentReadingNovelID:String?
        if let miscDictionary = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            currentReadingNovelID = RestoreMiscSettings_V_1_0_0(dic:miscDictionary)
        }else{
            currentReadingNovelID = nil
        }
        if let novelArray = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            RestoreBookshelf_V_1_0_0(novelArray:novelArray, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
        }
        autoreleasepool {
            if let targetNovelID = currentReadingNovelID, let globalState = RealmGlobalState.GetInstance() {
                let coreDataNarouContent = NarouContentCacheData()
                coreDataNarouContent.ncode = targetNovelID
                RealmUtil.Write { (realm) in
                    if coreDataNarouContent.isURLContent() {
                        globalState.currentReadingNovelID = targetNovelID
                    }else if targetNovelID.hasPrefix("_u") {
                        globalState.currentReadingNovelID = "https://example.com/" + targetNovelID
                    }else{
                        globalState.currentReadingNovelID = CoreDataToRealmTool.NcodeToUrlString(ncode: targetNovelID, no: 1, end: false)
                    }
                }
            }
        }
        return true
    }
    static func RestoreSpeechMod_V_2_0_0(dic:NSDictionary, progressUpdate:@escaping(String)->Void){
        RealmUtil.Write { (realm) in
            for (before, speechModDic) in dic {
                guard let speechMod = speechModDic as? NSDictionary,
                    let before = before as? String,
                    let after = speechMod.object(forKey: "afterString") as? String,
                    let isUseRegularExpression = speechMod.object(forKey: "isUseRegularExpression") as? NSNumber else { continue }
                let mod = RealmSpeechModSetting.SearchFrom(beforeString: before) ?? RealmSpeechModSetting()
                if mod.before != before {
                    mod.before = before
                }
                mod.after = after
                if let createdDateString = speechMod.object(forKey: "createdDate") as? String, let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                    mod.createdDate = createdDate
                }
                mod.isUseRegularExpression = isUseRegularExpression.boolValue
                mod.targetNovelIDArray.removeAll()
                if let targetNovelIDArray = speechMod.object(forKey: "targetNovelIDArray") as? NSArray {
                    for novelID in targetNovelIDArray {
                        if let novelID = novelID as? String, novelID.count > 0 {
                            mod.targetNovelIDArray.append(novelID)
                        }
                    }
                }
            }
        }
    }
    
    static func RestoreSpeechWaitConfig_V_2_0_0(waitArray:NSArray, progressUpdate:@escaping(String)->Void) {
        for speechWaitDic in waitArray {
            guard let speechWait = speechWaitDic as? NSDictionary,
                let delayTimeInSec = speechWait.object(forKey: "delayTimeInSec") as? NSNumber,
                let targetText = speechWait.object(forKey: "targetText") as? String else { return }
            autoreleasepool {
                let speechWaitConfig = RealmSpeechWaitConfig.SearchFrom(targetText: targetText) ?? RealmSpeechWaitConfig()
                if speechWaitConfig.targetText != targetText {
                    speechWaitConfig.targetText = targetText
                }
                RealmUtil.Write { (realm) in
                    speechWaitConfig.delayTimeInSec = delayTimeInSec.floatValue
                    if let createdDateString = speechWait.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                        speechWaitConfig.createdDate = createdDate
                    }
                    realm.add(speechWaitConfig, update: .modified)
                }
            }
        }
    }
    
    static func RestoreSpeakerSettings_V_2_0_0(speakerArray:NSArray, defaultSpeakerSettingID:String, progressUpdate:@escaping(String)->Void) {
        for speaker in speakerArray {
            guard let speaker = speaker as? NSDictionary,
                let name = speaker.object(forKey: "name") as? String,
                let type = speaker.object(forKey: "type") as? String,
                let voiceIdentifier = speaker.object(forKey: "voiceIdentifier") as? String,
                let locale = speaker.object(forKey: "locale") as? String else { continue }
            autoreleasepool {
                let speakerSetting:RealmSpeakerSetting
                if name == defaultSpeakerSettingID {
                    guard let defaultSpeaker = RealmGlobalState.GetInstance()?.defaultSpeaker else { return }
                    speakerSetting = defaultSpeaker
                }else{
                    speakerSetting = RealmSpeakerSetting.SearchFrom(name: name) ?? RealmSpeakerSetting()
                    if speakerSetting.name != name {
                        speakerSetting.name = name
                    }
                }
                RealmUtil.Write { (realm) in
                    if let pitch = speaker.object(forKey: "pitch") as? NSNumber {
                        speakerSetting.pitch = pitch.floatValue
                    }
                    if let rate = speaker.object(forKey: "rate") as? NSNumber {
                        speakerSetting.rate = rate.floatValue
                    }
                    if let lmd = speaker.object(forKey: "lmd") as? NSNumber {
                        speakerSetting.lmd = lmd.floatValue
                    }
                    if let acc = speaker.object(forKey: "acc") as? NSNumber {
                        speakerSetting.acc = acc.floatValue
                    }
                    if let base = speaker.object(forKey: "base") as? NSNumber {
                        speakerSetting.base = base.int32Value
                    }
                    if let volume = speaker.object(forKey: "volume") as? NSNumber {
                        speakerSetting.volume = volume.floatValue
                    }
                    speakerSetting.type = type
                    speakerSetting.voiceIdentifier = voiceIdentifier
                    speakerSetting.locale = locale
                    if let createdDateString = speaker.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                        speakerSetting.createdDate = createdDate
                    }
                    realm.add(speakerSetting, update: .modified)
                }
            }
        }
    }
    static func RestoreSpeechSectionConfig_V_2_0_0(sectionConfigArray:NSArray, progressUpdate:@escaping(String)->Void){
        for sectionConfig in sectionConfigArray {
            guard
                let sectionConfigDic = sectionConfig as? NSDictionary,
                let name = sectionConfigDic.object(forKey: "name") as? String,
                let startText = sectionConfigDic.object(forKey: "startText") as? String,
                let endText = sectionConfigDic.object(forKey: "endText") as? String,
                let speakerID = sectionConfigDic.object(forKey: "speakerID") as? String
                else { continue }
            autoreleasepool {
                let sectionConfig = RealmSpeechSectionConfig.SearchFrom(name: name) ?? RealmSpeechSectionConfig()
                if sectionConfig.name != name {
                    sectionConfig.name = name
                }
                RealmUtil.Write { (realm) in
                    sectionConfig.startText = startText
                    sectionConfig.endText = endText
                    if let createdDateString = sectionConfigDic.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                        sectionConfig.createdDate = createdDate
                    }
                    sectionConfig.speakerID = speakerID
                    sectionConfig.targetNovelIDArray.removeAll()
                    if let targetNovelIDArray = sectionConfigDic.object(forKey: "targetNovelIDArray") as? NSArray {
                        for novel in targetNovelIDArray {
                            guard let novel = novel as? String else { continue }
                            sectionConfig.targetNovelIDArray.append(novel)
                        }
                    }
                }
            }
        }
    }
    static func RestoreDisplaySettings_V_2_0_0(displaySettingArray:NSArray,  defaultSpeakerSettingID:String, progressUpdate:@escaping(String)->Void) {
        for displaySettingObj in displaySettingArray {
            guard let displaySettingDic = displaySettingObj as? NSDictionary,
                let name = displaySettingDic.object(forKey: "name") as? String else { continue }
            autoreleasepool {
                let setting:RealmDisplaySetting
                if name == defaultSpeakerSettingID {
                    guard let defaultSetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting else { return }
                    setting = defaultSetting
                }else{
                    setting = RealmDisplaySetting.SearchFrom(name: name) ?? RealmDisplaySetting()
                    if setting.name != name {
                        setting.name = name
                    }
                }
                RealmUtil.Write { (realm) in
                    if let textSizeValue = displaySettingDic.object(forKey: "textSizeValue") as? NSNumber {
                        setting.textSizeValue = textSizeValue.floatValue
                    }
                    if let fontID = displaySettingDic.object(forKey: "fontID") as? String {
                        setting.fontID = fontID
                    }
                    if let isVertical = displaySettingDic.object(forKey: "isVertical") as? NSNumber {
                        setting.isVertical = isVertical.boolValue
                    }
                    if let createdDateString = displaySettingDic.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                        setting.createdDate = createdDate
                    }
                    setting.targetNovelIDArray.removeAll()
                    if let targetNovelIDArray = displaySettingDic.object(forKey: "targetNovelIDArray") as? NSArray  {
                        for novelID in targetNovelIDArray {
                            guard let novelID = novelID as? String else { continue }
                            setting.targetNovelIDArray.append(novelID)
                        }
                    }
                    realm.add(setting, update: .modified)
                }
            }
        }
    }
    static func RestoreNovelTag_V_2_0_0(novelTagArray:NSArray, progressUpdate:@escaping(String)->Void) {
        RealmUtil.Write { (realm) in
            for tagDic in novelTagArray {
                guard let tagDic = tagDic as? NSDictionary,
                    let name = tagDic.object(forKey: "name") as? String,
                    let type = tagDic.object(forKey: "type") as? String else { continue }
                let tag = RealmNovelTag.SearchWith(name: name, type: type) ?? RealmNovelTag.CreateNewTag(name: name, type: type)
                if let createdDateString = tagDic.object(forKey: "createdDate") as? String,
                    let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString){
                    tag.createdDate = createdDate
                }
                if let hint = tagDic.object(forKey: "hint") as? String {
                    tag.hint = hint
                }
                tag.targetNovelIDArray.removeAll()
                if let targetNovelIDArray = tagDic.object(forKey: "targetNovelIDArray") as? NSArray {
                    for novelID in targetNovelIDArray {
                        guard let novelID = novelID as? String else { continue }
                        tag.targetNovelIDArray.append(novelID)
                    }
                }
                realm.add(tag, update: .modified)
            }
        }
    }
    static func RestoreBookmark_V_2_0_0(bookmarkArray:NSArray, progressUpdate:@escaping(String)->Void) {
        RealmUtil.Write { (realm) in
            for bookmark in bookmarkArray {
                guard let bookmarkDic = bookmark as? NSDictionary, let id = bookmarkDic.object(forKey: "id") as? String, let createdDateString = bookmarkDic.object(forKey: "createdDate") as? String, let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString), let novelID = bookmarkDic.object(forKey: "novelID") as? String, let chapterNumber = (bookmarkDic.object(forKey: "chapterNumber") as? NSNumber)?.intValue, chapterNumber > 0, let location = (bookmarkDic.object(forKey: "location") as? NSNumber)?.intValue else { continue }
                let realmBookmark = RealmBookmark()
                realmBookmark.id = id
                realmBookmark.createdDate = createdDate
                realmBookmark.chapterNumber = chapterNumber
                realmBookmark.novelID = novelID
                realmBookmark.location = location
                realm.add(realmBookmark, update: .modified)
            }
        }
    }

    static func RestoreSpeechOverrideSettings_V_2_0_0(speechOverrideSettingArray:NSArray, defaultSpeechOverrideSettingID:String, progressUpdate:@escaping(String)->Void) {
        for overrideSettingDic in speechOverrideSettingArray {
            guard let overrideSettingDic = overrideSettingDic as? NSDictionary,
                let name = overrideSettingDic.object(forKey: "name") as? String else { continue }
            autoreleasepool {
                let setting = RealmSpeechOverrideSetting.SearchObjectFrom(name: name) ?? RealmSpeechOverrideSetting()
                if setting.name != name {
                    setting.name = name
                }
                RealmUtil.Write { (realm) in
                    if let createdDateString = overrideSettingDic.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                        setting.createdDate = createdDate
                    }
                    if let repeatSpeechType = overrideSettingDic.object(forKey: "repeatSpeechType") as? NSNumber {
                        setting.repeatSpeechType = RepeatSpeechType(rawValue: repeatSpeechType.uintValue) ?? RepeatSpeechType.noRepeat
                    }
                    if let isOverrideRubyIsEnabled = overrideSettingDic.object(forKey: "isOverrideRubyIsEnabled") as?   NSNumber {
                        setting.isOverrideRubyIsEnabled = isOverrideRubyIsEnabled.boolValue
                    }
                    if let notRubyCharactorStringArray = overrideSettingDic.object(forKey:  "notRubyCharactorStringArray") as? String {
                        setting.notRubyCharactorStringArray = notRubyCharactorStringArray
                    }
                    if let isIgnoreURIStringSpeechEnabled = overrideSettingDic.object(forKey:   "isIgnoreURIStringSpeechEnabled") as? NSNumber {
                        setting.isIgnoreURIStringSpeechEnabled = isIgnoreURIStringSpeechEnabled.boolValue
                    }
                    setting.targetNovelIDArray.removeAll()
                    if let targetNovelIDArray = overrideSettingDic.object(forKey: "targetNovelIDArray") as? NSArray {
                        for novelID in targetNovelIDArray {
                            guard let novelID = novelID as? String else { continue }
                            setting.targetNovelIDArray.append(novelID)
                        }
                    }
                    realm.add(setting, update: .modified)
                }
            }
        }
    }


    static func RestoreGlobalState_V_2_0_0(dic:NSDictionary, progressUpdate:@escaping(String)->Void) {
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else { return }
            RealmUtil.Write { (realm) in
                if let maxSpeechTimeInSec = dic.object(forKey: "maxSpeechTimeInSec") as? NSNumber {
                    globalState.maxSpeechTimeInSec = maxSpeechTimeInSec.intValue
                }
                if let webImportBookmarkArray = dic.object(forKey: "webImportBookmarkArray") as? NSArray {
                    for bookmark in webImportBookmarkArray {
                        guard let bookmark = bookmark as? String, !globalState.webImportBookmarkArray.contains(bookmark) else { continue }
                        globalState.webImportBookmarkArray.append(bookmark)
                    }
                }
                if let readedPrivacyPolicy = dic.object(forKey: "readedPrivacyPolicy") as? String {
                    globalState.readedPrivacyPolicy = readedPrivacyPolicy
                }
                if let isOpenRecentNovelInStartTime = dic.object(forKey: "isOpenRecentNovelInStartTime") as? NSNumber {
                    globalState.isOpenRecentNovelInStartTime = isOpenRecentNovelInStartTime.boolValue
                }
                if let isDisallowsCellularAccess = dic.object(forKey: "isDisallowsCellularAccess") as? NSNumber {
                    globalState.IsDisallowsCellularAccess = isDisallowsCellularAccess.boolValue
                }
                if let isNeedConfirmDeleteBook = dic.object(forKey: "isNeedConfirmDeleteBook") as? NSNumber {
                    globalState.IsNeedConfirmDeleteBook = isNeedConfirmDeleteBook.boolValue
                }
                if let isLicenseReaded = dic.object(forKey: "isLicenseReaded") as? NSNumber {
                    globalState.isLicenseReaded = isLicenseReaded.boolValue
                }
                if let isDuckOthersEnabled = dic.object(forKey: "isDuckOthersEnabled") as? NSNumber {
                    globalState.isDuckOthersEnabled = isDuckOthersEnabled.boolValue
                }
                if let isMixWithOthersEnabled = dic.object(forKey: "isMixWithOthersEnabled") as? NSNumber {
                    globalState.isMixWithOthersEnabled = isMixWithOthersEnabled.boolValue
                }
                /* /// この設定はバックアップファイルからの読み込みを停止します
                if let isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = dic.object(forKey: "isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled") as? NSNumber {
                    globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled = isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled.boolValue
                }
                */
                if let isPlaybackDurationEnabled = dic.object(forKey: "isPlaybackDurationEnabled") as? NSNumber {
                    globalState.isPlaybackDurationEnabled = isPlaybackDurationEnabled.boolValue
                }
                if let isShortSkipEnabled = dic.object(forKey: "isShortSkipEnabled") as? NSNumber {
                    globalState.isShortSkipEnabled = isShortSkipEnabled.boolValue
                }
                if let isReadingProgressDisplayEnabled = dic.object(forKey: "isReadingProgressDisplayEnabled") as? NSNumber {
                    globalState.isReadingProgressDisplayEnabled = isReadingProgressDisplayEnabled.boolValue
                }
                if let isForceSiteInfoReloadIsEnabled = dic.object(forKey: "isForceSiteInfoReloadIsEnabled") as? NSNumber {
                    globalState.isForceSiteInfoReloadIsEnabled = isForceSiteInfoReloadIsEnabled.boolValue
                }
                if let isMenuItemIsAddNovelSpeakerItemsOnly = dic.object(forKey: "isMenuItemIsAddNovelSpeakerItemsOnly")  as? NSNumber {
                    globalState.isMenuItemIsAddNovelSpeakerItemsOnly = isMenuItemIsAddNovelSpeakerItemsOnly.boolValue
                }
                if let isPageTurningSoundEnabled = dic.object(forKey: "isPageTurningSoundEnabled") as? NSNumber {
                    globalState.isPageTurningSoundEnabled = isPageTurningSoundEnabled.boolValue
                }
                if let bookSelfSortType = dic.object(forKey: "bookSelfSortType") as? NSNumber {
                    globalState.bookShelfSortType = NarouContentSortType(rawValue: UInt(bookSelfSortType.intValue)) ?? NarouContentSortType.ncode
                }
                if let currentReadingNovelID = dic.object(forKey: "currentReadingNovelID") as? String {
                    globalState.currentReadingNovelID = currentReadingNovelID
                }
                if let readingDisplayColor = dic.object(forKey: "readingDisplayColor") as? NSDictionary {
                    if let foregroundColor = readingDisplayColor.object(forKey: "foregroundColor") as? NSDictionary, let red = foregroundColor.object(forKey: "red") as? NSNumber, let green = foregroundColor.object(forKey: "green") as? NSNumber, let blue = foregroundColor.object(forKey: "blue") as? NSNumber, let alpha = foregroundColor.object(forKey: "alpha") as? NSNumber {
                        globalState.foregroundColor = UIColor(red: CGFloat(red.floatValue), green: CGFloat(green.floatValue), blue: CGFloat(blue.floatValue), alpha: CGFloat(alpha.floatValue))
                    }
                    if let foregroundColor = readingDisplayColor.object(forKey: "backgroundColor") as? NSDictionary, let red = foregroundColor.object(forKey: "red") as? NSNumber, let green = foregroundColor.object(forKey: "green") as? NSNumber, let blue = foregroundColor.object(forKey: "blue") as? NSNumber, let alpha = foregroundColor.object(forKey: "alpha") as? NSNumber {
                        globalState.backgroundColor = UIColor(red: CGFloat(red.floatValue), green: CGFloat(green.floatValue), blue: CGFloat(blue.floatValue), alpha: CGFloat(alpha.floatValue))
                    }
                }
            }
        }
    }
    
    static func RestoreNovel_V_2_0_0(bookshelf:NSArray, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        NovelDownloadQueue.shared.downloadStop()
        defer { NovelDownloadQueue.shared.downloadStart() }
        let novelArrayCount = bookshelf.count
        var novelCount = 0
        for novelDic in bookshelf {
            novelCount += 1
            let progressString = NSLocalizedString("NovelSpeakerUtility_ExportingNovelData", comment: "小説を抽出中") + " (\(novelCount)/\(novelArrayCount))"
            progressUpdate(progressString)
            guard let novelDic = novelDic as? NSDictionary,
                let novelID = novelDic.object(forKey: "novelID") as? String,
                let type = novelDic.object(forKey: "type") as? NSNumber else { continue }
            autoreleasepool {
                let novel = RealmNovel.SearchNovelFrom(novelID: novelID) ?? RealmNovel()
                if novel.novelID != novelID {
                    novel.novelID = novelID
                }
                RealmUtil.Write { (realm) in
                    novel.type = NovelType(rawValue: type.intValue) ?? NovelType.UserCreated
                    if let writer = novelDic.object(forKey: "writer") as? String {
                        novel.writer = writer
                    }
                    if let title = novelDic.object(forKey: "title") as? String {
                        novel.title = title
                    }
                    if let url = novelDic.object(forKey: "url") as? String {
                        novel.url = url
                    }
                    if let secret = novelDic.object(forKey: "secret") as? String, let urlSecret = NiftyUtility.stringDecrypt(secret, key: novelID) {
                        novel.m_urlSecret = urlSecret
                    }
                    if let createdDateString = novelDic.object(forKey: "createdDate") as? String, let createdDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: createdDateString) {
                        novel.createdDate = createdDate
                    }
                    if let likeLevel = novelDic.object(forKey: "likeLevel") as? NSNumber {
                        novel.likeLevel = likeLevel.int8Value
                    }
                    if let isNeedSpeechAfterDelete = novelDic.object(forKey: "isNeedSpeechAfterDelete") as? NSNumber {
                        novel.isNeedSpeechAfterDelete = isNeedSpeechAfterDelete.boolValue
                    }
                    if let defaultSpeakerID = novelDic.object(forKey: "defaultSpeakerID") as? String {
                        novel.defaultSpeakerID = defaultSpeakerID
                    }
                    if let lastChapterStoryID = novelDic.object(forKey: "lastChapterStoryID") as? String {
                        novel.m_lastChapterStoryID = lastChapterStoryID
                    }
                    if let lastDownloadDateString = novelDic.object(forKey: "lastDownloadDate") as? String, let lastDownloadDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: lastDownloadDateString) {
                        novel.lastDownloadDate = lastDownloadDate
                    }
                    if let readingChapterStoryID = novelDic.object(forKey: "readingChapterStoryID") as? String {
                        novel.m_readingChapterStoryID = readingChapterStoryID
                    }
                    if let lastReadDateString = novelDic.object(forKey: "lastReadDate") as? String, let lastReadDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: lastReadDateString) {
                        novel.lastReadDate = lastReadDate
                    }
                    if let downloadDateArray = novelDic.object(forKey: "downloadDateArray") as? NSArray {
                        novel.downloadDateArray.removeAll()
                        for downloadDateStringObj in downloadDateArray {
                            if let downloadDateString = downloadDateStringObj as? String, let downloadDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: downloadDateString) {
                                novel.AppendDownloadDate(date: downloadDate, realm: realm)
                            }
                        }
                    }
                    realm.add(novel, update: .modified)
                }
            }
            var hasInvalidData = false
            if let storys = novelDic.object(forKey: "storys") as? NSArray {
                RealmUtil.Write { (realm) in
                    var storyArray:[Story] = []
                    var index = 0
                    let max = storys.count
                    for storyDic in storys {
                        index += 1
                        progressUpdate(progressString + " (\(index)/\(max))")
                        guard let storyDic = storyDic as? NSDictionary,
                            let chapterNumber = storyDic.object(forKey: "chapterNumber") as? NSNumber else { continue }
                        let data:Data
                        if let contentZipedString = storyDic.object(forKey: "contentZiped") as? String, let contentZiped = Data(base64Encoded: contentZipedString) {
                            data = contentZiped
                        }else{
                            guard let contentDirectoryString = novelDic.object(forKey: "contentDirectory") as? String,
                                let extractedDirectory = extractedDirectory else {
                                hasInvalidData = true
                                continue
                            }
                            let contentDirectory = extractedDirectory.appendingPathComponent(contentDirectoryString, isDirectory: true)
                            let contentFilePath = contentDirectory.appendingPathComponent("\(chapterNumber.intValue)")
                            guard let contentData = try? Data(contentsOf: contentFilePath) else {
                                hasInvalidData = true
                                continue
                            }
                            data = contentData
                        }
                        var story = Story()
                        story.novelID = novelID
                        story.chapterNumber = chapterNumber.intValue
                        story.content = NiftyUtility.stringInflate(data)
                        if let url = storyDic.object(forKey: "url") as? String {
                            story.url = url
                        }
                        if let subtitle = storyDic.object(forKey: "subtitle") as? String {
                            story.subtitle = subtitle
                        }
                        if let downloadDateString = storyDic.object(forKey: "downloadDate") as? String, let downloadDate = NiftyUtilitySwift.ISO8601String2Date(iso8601String: downloadDateString) {
                            story.downloadDate = downloadDate
                        }
                        storyArray.append(story)
                        if storyArray.count >= RealmStoryBulk.bulkCount {
                            RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                            storyArray.removeAll()
                        }
                    }
                    if storyArray.count > 0 {
                        RealmStoryBulk.SetStoryArrayWith(realm: realm, storyArray: storyArray)
                        storyArray.removeAll()
                    }
                }
            }
            if hasInvalidData {
                NovelDownloadQueue.shared.addQueue(novelID: novelID)
            }
        }
    }

    static func ProcessNovelSpeakerBackupJSONData_V_2_0_0(toplevelDictionary:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
        if let word_replacement_dictionary = toplevelDictionary.object(forKey: "word_replacement_dictionary") as? NSDictionary {
            RestoreSpeechMod_V_2_0_0(dic: word_replacement_dictionary, progressUpdate: progressUpdate)
        }
        if let speech_wait_config = toplevelDictionary.object(forKey: "speech_wait_config") as? NSArray {
            RestoreSpeechWaitConfig_V_2_0_0(waitArray: speech_wait_config, progressUpdate: progressUpdate)
        }
        if let speech_section_config = toplevelDictionary.object(forKey: "speech_section_config") as? NSArray {
            RestoreSpeechSectionConfig_V_2_0_0(sectionConfigArray:speech_section_config, progressUpdate: progressUpdate)
        }
        if let novel_tag = toplevelDictionary.object(forKey: "novel_tag") as? NSArray {
            RestoreNovelTag_V_2_0_0(novelTagArray: novel_tag, progressUpdate: progressUpdate)
        }
        if let bookmarks = toplevelDictionary.object(forKey: "bookmark") as? NSArray {
            RestoreBookmark_V_2_0_0(bookmarkArray: bookmarks, progressUpdate: progressUpdate)
        }
        // misc_settings には defaultDisplaySettingID,defaultSpeakerID,defaultSpeechOverrideSettingID が入っているので
        // 先に取り出しておかないと良くないことがおきます(´・ω・`)
        if let globalStateDic = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            if let defaultSpeakerID = globalStateDic.object(forKey: "defaultSpeakerID") as? String, let speaker_setting = toplevelDictionary.object(forKey: "speaker_setting") as? NSArray {
                RestoreSpeakerSettings_V_2_0_0(speakerArray:speaker_setting, defaultSpeakerSettingID:defaultSpeakerID, progressUpdate: progressUpdate)
            }
            if let defaultDisplaySettingID = globalStateDic.object(forKey: "defaultDisplaySettingID") as? String, let display_setting = toplevelDictionary.object(forKey: "display_setting") as? NSArray {
                RestoreDisplaySettings_V_2_0_0(displaySettingArray:display_setting, defaultSpeakerSettingID:defaultDisplaySettingID, progressUpdate: progressUpdate)
            }
            if let defaultSpeechOverrideSettingID = globalStateDic.object(forKey: "defaultSpeechOverrideSettingID") as? String, let speech_override_setting = toplevelDictionary.object(forKey: "speech_override_setting") as? NSArray {
                RestoreSpeechOverrideSettings_V_2_0_0(speechOverrideSettingArray:speech_override_setting, defaultSpeechOverrideSettingID:defaultSpeechOverrideSettingID, progressUpdate: progressUpdate)
            }
            
            RestoreGlobalState_V_2_0_0(dic:globalStateDic, progressUpdate: progressUpdate)
        }
        if let bookshelf = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            RestoreNovel_V_2_0_0(bookshelf:bookshelf, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
        }
        return true
    }

    // MARK: バックアップファイルからの書き戻し
    @discardableResult
    static func ProcessNovelSpeakerBackupFile_JSONType(url:URL, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
        progressUpdate(NSLocalizedString("NovelSpeakerUtility_RestoreingJSONType", comment: "バックアップファイルから設定を読み込んでいます。"))
        guard let data = try? Data(contentsOf: url), let jsonObj = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? NSDictionary, let dataVersion = jsonObj["data_version"] as? String else { return false }
        if dataVersion == "1.0.0" {
            return ProcessNovelSpeakerBackupJSONData_V_1_0_0(toplevelDictionary: jsonObj, progressUpdate: progressUpdate, extractedDirectory: extractedDirectory)
        }else if dataVersion == "1.1.0" {
            return ProcessNovelSpeakerBackupJSONData_V_1_1_0(toplevelDictionary: jsonObj, progressUpdate: progressUpdate, extractedDirectory: extractedDirectory)
        }else if dataVersion == "2.0.0" {
            return ProcessNovelSpeakerBackupJSONData_V_2_0_0(toplevelDictionary: jsonObj, progressUpdate: progressUpdate, extractedDirectory: extractedDirectory)
        }else{
            return false
        }
    }
    @discardableResult
    static func ProcessNovelSpeakerBackupFile_ZIPType(url:URL, progressUpdate:@escaping (String)->Void) -> Bool {
        let temporaryDirectoryName = "NovelSpeakerBackup"
        if let temporaryDirectory = NiftyUtilitySwift.CreateTemporaryDirectory(directoryName: temporaryDirectoryName) {
            do {
                try FileManager.default.removeItem(at: temporaryDirectory)
            }catch{
                // nothing to do.
            }
        }
        guard let temporaryDirectory = NiftyUtilitySwift.CreateTemporaryDirectory(directoryName: temporaryDirectoryName) else { return false }
        do {
            Zip.addCustomFileExtension("novelspeaker-backup+zip")
            try Zip.unzipFile(url, destination: temporaryDirectory, overwrite: true, password: nil, progress: { (progressDouble) in
                progressUpdate(NSLocalizedString("NovelSpeakerUtility_UnzipProgress", comment: "バックアップファイルを解凍しています") + " (\(Int(progressDouble * 100))%)")
            }, fileOutputHandler: nil)
        }catch{
            return false
        }
        defer {
            do {
                try FileManager.default.removeItem(at: temporaryDirectory)
            }catch{
                // nothing to do
            }
        }
        return ProcessNovelSpeakerBackupFile_JSONType(url: temporaryDirectory.appendingPathComponent("backup_data.json"), progressUpdate: progressUpdate, extractedDirectory: temporaryDirectory)
    }

    static func ProcessNovelSpeakerBackupFile(url:URL) -> Bool {
        guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return false }
        var builder = NiftyUtilitySwift.EasyDialogBuilder(viewController)
        let titleTag = 100
        let messageTag = 101
        builder = builder.label(text: NSLocalizedString("NovelSpeakerUtility_RestoreBackupTitle", comment: "バックアップデータを読み込んでいます"), textAlignment: .center, tag: titleTag)
        builder = builder.label(text: NSLocalizedString("NovelSpeakerUtility_RestoreBackupMessage", comment: "-"), textAlignment: .center, tag: messageTag)
        let dialog = builder.build()
        DispatchQueue.main.async {
            dialog.show()
        }
        func applyProgress(text:String) {
            DispatchQueue.main.async {
                guard let messageLabel = dialog.view.viewWithTag(messageTag) as? UILabel else { return }
                messageLabel.text = text
            }
        }
        DispatchQueue.global(qos: .utility).async {
            defer {
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
                NovelSpeakerNotificationTool.AnnounceGlobalStateChanged()
            }
            if url.pathExtension == "novelspeaker-backup+zip" {
                ProcessNovelSpeakerBackupFile_ZIPType(url: url, progressUpdate: applyProgress(text:))
                return
            }else{
                ProcessNovelSpeakerBackupFile_JSONType(url: url, progressUpdate: applyProgress(text:), extractedDirectory: nil)
            }
        }
        return true
    }
    #endif

    // MARK: バックアップデータ生成
    #if !os(watchOS)
    fileprivate static func CreateBackupDataDictionary_Story(novelID:String, contentWriteTo:URL?, progressString:String, progress:((_ description:String)->Void)?) -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let storyArray = RealmStoryBulk.SearchAllStoryFor(novelID: novelID) else { return result }
            var index = 0
            let max = storyArray.count
            for story in storyArray {
                index += 1
                if let progress = progress {
                    progress(progressString + " (\(index)/\(max))")
                }
                var storyData:[String:Any] = [
                    "chapterNumber": story.chapterNumber,
                    "readLocation": story.readLocation,
                ]
                if story.url.count > 0 {
                    storyData["url"] = story.url
                }
                if story.subtitle.count > 0 {
                    storyData["subtitle"] = story.subtitle
                }
                if story.downloadDate > Date(timeIntervalSince1970: 0) {
                    storyData["downloadDate"] = NiftyUtilitySwift.Date2ISO8601String(date: story.downloadDate)
                }
                if let contentZiped = NiftyUtility.stringDeflate(story.content, level: 9) {
                    if let contentWriteTo = contentWriteTo {
                        do {
                            let filePath = contentWriteTo.appendingPathComponent("\(story.chapterNumber)")
                            try contentZiped.write(to: filePath)
                        }catch{
                            print("\(novelID) chapter: \(story.chapterNumber) content write failed.")
                        }
                    }else{
                        storyData["contentZiped"] = contentZiped.base64EncodedString()
                    }
                }
                result.append(storyData)
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_Bookshelf(withAllStoryContent:Bool, contentWriteTo:URL, progress:((_ description:String)->Void)?) -> ([[String:Any]], [URL]) {
        var result:[[String:Any]] = []
        var fileArray:[URL] = []
        return autoreleasepool {
            guard let novelArray = RealmNovel.GetAllObjects() else { return (result, []) }
            var novelCount = 1
            let novelArrayCount = novelArray.count
            for novel in novelArray {
                let progressString = NSLocalizedString("NovelSpeakerUtility_ExportingNovelData", comment: "小説を抽出中") + " (\(novelCount)/\(novelArrayCount))"
                if let progress = progress {
                    progress(progressString)
                }
                var novelData:[String:Any] = [
                    "novelID": novel.novelID,
                    "type": novel.m_type,
                    "writer": novel.writer,
                    "title": novel.title,
                    "url": novel.url,
                    "secret": NiftyUtility.stringEncrypt(novel.m_urlSecret, key: novel.novelID) ?? "",
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: novel.createdDate),
                    "likeLevel": novel.likeLevel,
                    "isNeedSpeechAfterDelete": novel.isNeedSpeechAfterDelete,
                    "defaultSpeakerID": novel.defaultSpeakerID,
                    "lastChapterStoryID": novel.m_lastChapterStoryID,
                    "lastDownloadDate": NiftyUtilitySwift.Date2ISO8601String(date: novel.lastDownloadDate),
                    "readingChapterStoryID": novel.m_readingChapterStoryID,
                    "lastReadDate": NiftyUtilitySwift.Date2ISO8601String(date: novel.lastReadDate),
                    "downloadDateArray": Array(novel.downloadDateArray.map({ (date) -> String in
                        NiftyUtilitySwift.Date2ISO8601String(date: date)
                    })),
                    "contentDirectory": "\(novelCount)"
                ]
                if !withAllStoryContent {
                    result.append(novelData)
                    continue
                }
                let contentDirectory = NiftyUtilitySwift.CreateDirectoryFor(path: contentWriteTo, directoryName: "\(novelCount)")
                switch novel.type {
                case .URL:
                    novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: contentDirectory, progressString: progressString, progress: progress)
                    if let contentDirectory = contentDirectory {
                        fileArray.append(contentDirectory)
                    }
                    break
                case .UserCreated:
                    novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: contentDirectory, progressString: progressString, progress: progress)
                    break
                }
                result.append(novelData)
                novelCount += 1
            }
            return (result, fileArray)
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechModSetting() -> [String:[String:Any]] {
        return autoreleasepool {
            var result:[String:[String:Any]] = [:]
            guard let targetArray = RealmSpeechModSetting.GetAllObjects() else { return result }
            for setting in targetArray {
                result[setting.before] = [
                    "afterString": setting.after,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                    "isUseRegularExpression": setting.isUseRegularExpression,
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ]
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechWaitConfig() -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeechWaitConfig.GetAllObjects() else { return result }
            for setting in targetArray {
                result.append([
                    "targetText": setting.targetText,
                    "delayTimeInSec": setting.delayTimeInSec,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeakerSetting() -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeakerSetting.GetAllObjects() else { return result }
            for setting in targetArray {
                result.append([
                    "name": setting.name,
                    "pitch": setting.pitch,
                    "rate": setting.rate,
                    "lmd": setting.lmd,
                    "acc": setting.acc,
                    "base": setting.base,
                    "volume": setting.volume,
                    "type": setting.type,
                    "voiceIdentifier": setting.voiceIdentifier,
                    "locale": setting.locale,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechSectionConfig() -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeechSectionConfig.GetAllObjects() else { return result }
            for setting in targetArray {
                result.append([
                    "name": setting.name,
                    "startText": setting.startText,
                    "endText": setting.endText,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                    "speakerID": setting.speakerID,
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_GlobalState_TextColor(globalState:RealmGlobalState) -> [String:Any] {
        var result:[String:Any] = [:]
        if let color = globalState.foregroundColor {
            var red:CGFloat = -1.0
            var green:CGFloat = -1.0
            var blue:CGFloat = -1.0
            var alpha:CGFloat = -1.0
            if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                result["foreground"] = [
                    "red": Float(red),
                    "green": Float(green),
                    "blue": Float(blue),
                    "alpha": Float(alpha)
                ]
            }
        }
        if let color = globalState.backgroundColor {
            var red:CGFloat = -1.0
            var green:CGFloat = -1.0
            var blue:CGFloat = -1.0
            var alpha:CGFloat = -1.0
            if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                result["background"] = [
                    "red": Float(red),
                    "green": Float(green),
                    "blue": Float(blue),
                    "alpha": Float(alpha)
                ]
            }
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_GlobalState() -> [String:Any] {
        return autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else { return [:] }
            return [
                "maxSpeechTimeInSec": globalState.maxSpeechTimeInSec,
                "webImportBookmarkArray": Array(globalState.webImportBookmarkArray),
                "readedPrivacyPolicy": globalState.readedPrivacyPolicy,
                "isOpenRecentNovelInStartTime": globalState.isOpenRecentNovelInStartTime,
                "isDisallowsCellularAccess": globalState.IsDisallowsCellularAccess,
                "isNeedConfirmDeleteBook": globalState.IsNeedConfirmDeleteBook,
                "isLicenseReaded": globalState.isLicenseReaded,
                "isDuckOthersEnabled": globalState.isDuckOthersEnabled,
                "isMixWithOthersEnabled": globalState.isMixWithOthersEnabled,
                "isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled": globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled,
                "readingDisplayColor": CreateBackupDataDictionary_GlobalState_TextColor(globalState: globalState),
                "isPlaybackDurationEnabled": globalState.isPlaybackDurationEnabled,
                "isShortSkipEnabled": globalState.isShortSkipEnabled,
                "isReadingProgressDisplayEnabled": globalState.isReadingProgressDisplayEnabled,
                "isForceSiteInfoReloadIsEnabled": globalState.isForceSiteInfoReloadIsEnabled,
                "isMenuItemIsAddSpeechModSettingOnly": globalState.isMenuItemIsAddNovelSpeakerItemsOnly,
                //"isBackgroundNovelFetchEnabled": globalState.isBackgroundNovelFetchEnabled,
                "isPageTurningSoundEnabled": globalState.isPageTurningSoundEnabled,
                "bookSelfSortType": globalState.m_bookSelfSortType,
                "currentReadingNovelID": globalState.currentReadingNovelID,

                "defaultDisplaySettingID": globalState.defaultDisplaySettingID,
                "defaultSpeakerID": globalState.defaultSpeakerID,
                "defaultSpeechOverrideSettingID": globalState.defaultSpeechOverrideSettingID
            ]
        }
    }
    fileprivate static func CreateBackupDataDictionary_DisplaySetting() -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let targetArray = RealmDisplaySetting.GetAllObjects() else { return result }
            for setting in targetArray {
                result.append([
                    "textSizeValue": setting.textSizeValue,
                    "fontID": setting.fontID,
                    "name": setting.name,
                    "isVertical": setting.isVertical,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_NovelTag() -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let targetArray = RealmNovelTag.GetAllObjects() else { return result }
            for setting in targetArray {
                result.append([
                    "name": setting.name,
                    "type": setting.type,
                    "hint": setting.hint,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechOverrideSetting() -> [[String:Any]] {
        return autoreleasepool {
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeechOverrideSetting.GetAllObjects() else { return result }
            for setting in targetArray {
                result.append([
                    "name": setting.name,
                    "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                    "repeatSpeechType": setting.m_repeatSpeechType,
                    "isOverrideRubyIsEnabled": setting.isOverrideRubyIsEnabled,
                    "notRubyCharactorStringArray": setting.notRubyCharactorStringArray,
                    "isIgnoreURIStringSpeechEnabled": setting.isIgnoreURIStringSpeechEnabled,
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_Bookmark() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmBookmark.GetAllObjects() else { return result }
        for bookmark in targetArray {
            result.append([
                "id": bookmark.id,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: bookmark.createdDate),
                "novelID": bookmark.novelID,
                "chapterNumber": bookmark.chapterNumber,
                "location": bookmark.location,
            ])
        }
        return result
    }

    static func CreateBackupData(withAllStoryContent:Bool, progress:((_ description:String)->Void)?) -> URL? {
        let directoryName = "NovelSpeakerBackup"
        // 一旦対象のディレクトリを作って、中身を全部消します。
        if let outputPath = NiftyUtilitySwift.CreateTemporaryDirectory(directoryName: directoryName) {
            NiftyUtilitySwift.RemoveDirectory(directoryPath: outputPath)
        }
        // 改めてディレクトリを作り直します。
        guard let outputPath = NiftyUtilitySwift.CreateTemporaryDirectory(directoryName: directoryName) else {
            return nil
        }
        let bookshelfResult = CreateBackupDataDictionary_Bookshelf(withAllStoryContent: withAllStoryContent, contentWriteTo: outputPath, progress: progress)
        if let progress = progress {
            progress(NSLocalizedString("NovelSpeakerUtility_ExportOtherSettings", comment: "設定情報の抽出中"))
        }
        let jsonDictionary:[String:Any] = [
            "data_version": "2.0.0",
            "bookshelf": bookshelfResult.0,
            "word_replacement_dictionary": CreateBackupDataDictionary_SpeechModSetting(),
            "speech_wait_config": CreateBackupDataDictionary_SpeechWaitConfig(),
            "speaker_setting": CreateBackupDataDictionary_SpeakerSetting(),
            "speech_section_config": CreateBackupDataDictionary_SpeechSectionConfig(),
            "misc_settings": CreateBackupDataDictionary_GlobalState(),
            "display_setting": CreateBackupDataDictionary_DisplaySetting(),
            "novel_tag": CreateBackupDataDictionary_NovelTag(),
            "speech_override_setting": CreateBackupDataDictionary_SpeechOverrideSetting(),
            "bookmark": CreateBackupDataDictionary_Bookmark(),
        ]
        defer { NiftyUtilitySwift.RemoveDirectory(directoryPath: outputPath) }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "yyyyMMddHHmm"
        let dateString = dateFormatter.string(from: Date())
        var ziptargetFiles:[URL] = bookshelfResult.1
        let backupDataFilePath:URL
        if withAllStoryContent {
            backupDataFilePath = outputPath.appendingPathComponent("backup_data.json")
            ziptargetFiles.append(backupDataFilePath)
        }else{
            backupDataFilePath = NiftyUtilitySwift.GetTemporaryFilePath(fileName: String.init(format: "%@.novelspeaker-backup-json", dateString))
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDictionary, options: [.prettyPrinted])
            try jsonData.write(to: backupDataFilePath)
        }catch{
            print("JSONSerizization.data() failed. or jsonData.write() failed.")
            return nil
        }
        if !withAllStoryContent {
            return backupDataFilePath
        }
        if let progress = progress {
            progress(NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中"))
        }
        let zipFilePath = NiftyUtilitySwift.GetTemporaryFilePath(fileName: NiftyUtilitySwift.Date2ISO8601String(date: Date()) + ".zip")
        do {
            try Zip.zipFiles(paths: ziptargetFiles, zipFilePath: zipFilePath, password: nil, compression: .BestCompression, progress: { (progressPercent) in
                let description = NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中") + " (\(Int(progressPercent * 100))%)"
                if let progress = progress {
                    progress(description)
                }
            })
        }catch let err{
            print("zip file create error", zipFilePath.absoluteString, err)
            return nil
        }
        let backupFilePath = NiftyUtilitySwift.GetTemporaryFilePath(fileName: String.init(format: "%@.novelspeaker-backup+zip", dateString))
        do {
            try FileManager.default.moveItem(at: zipFilePath, to: backupFilePath)
        }catch let err{
            print("zip file move error", zipFilePath.absoluteString, " to" , backupFilePath.absoluteString, err)
            return nil
        }
        return backupFilePath
    }
    #endif
    
    static let LicenseReadKey = "NovelSpeaker_IsLicenseReaded"
    static func IsLicenseReaded() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [LicenseReadKey : false])
        return defaults.bool(forKey: LicenseReadKey)
    }
    static func SetLicenseReaded(isRead:Bool) {
        UserDefaults.standard.set(isRead, forKey: LicenseReadKey)
    }

    #if !os(watchOS)
    @objc static func StartAllLongLivedOperationIDWatcher() {
        let activityIndicatorID = "AllLongLivedOperationIDWatcher"
        func AllLongLivedOperationIDWatcher() {
            RealmUtil.FetchAllLongLivedOperationIDs { (operationIDArray, error) in
                if error == nil, let operationIDArray = operationIDArray, operationIDArray.count > 0 {
                    ActivityIndicatorManager.enable(id: activityIndicatorID)
                }else{
                    ActivityIndicatorManager.disable(id: activityIndicatorID)
                }
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1) {
                    AllLongLivedOperationIDWatcher()
                }
            }
        }
        AllLongLivedOperationIDWatcher()
    }
    #endif
    
    static func CheckAndRecoverStoryCount(novelID:String) {
        autoreleasepool {
            guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID), let storyList = RealmStoryBulk.SearchAllStoryFor(novelID: novelID), let lastStory = storyList.last else { return }
            let storyCount = storyList.count
            let lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: storyCount)
            if novel.m_lastChapterStoryID != lastChapterStoryID && RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: lastStory.chapterNumber) == lastChapterStoryID {
                autoreleasepool {
                    RealmUtil.Write(block: { (realm) in
                        novel.m_lastChapterStoryID = lastChapterStoryID
                    })
                }
            }
        }
    }
}
