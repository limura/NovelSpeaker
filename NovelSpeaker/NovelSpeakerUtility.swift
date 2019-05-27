//
//  NovelSpeakerUtility.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/24.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Zip

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
        guard let speechModSettingArray = RealmSpeechModSetting.GetAllObjects() else { return }
        RealmUtil.Write { (realm) in
            for (before, after) in targets {
                var isHit = false
                for setting in speechModSettingArray {
                    if setting.before == before {
                        isHit = true
                        setting.after = after
                        setting.isUseRegularExpression = false
                        break
                    }
                }
                if isHit { continue }
                let speechModSetting = RealmSpeechModSetting()
                speechModSetting.before = before
                speechModSetting.after = after
                speechModSetting.isUseRegularExpression = false
                realm.add(speechModSetting, update: true)
            }
        }
    }

    // 標準の読み替え辞書を上書き登録します。
    static func OverrideDefaultSpeechModSettings() {
        guard let speechModSettingArray = RealmSpeechModSetting.GetAllObjects() else { return }
        RealmUtil.Write { (realm) in
            for (before, after) in defaultSpeechModSettings() {
                var isHit = false
                for setting in speechModSettingArray {
                    if setting.before == before {
                        isHit = true
                        setting.after = after
                        setting.isUseRegularExpression = false
                        break
                    }
                }
                if isHit { continue }
                let speechModSetting = RealmSpeechModSetting()
                speechModSetting.before = before
                speechModSetting.after = after
                speechModSetting.isUseRegularExpression = false
                realm.add(speechModSetting, update: true)
            }
            for (before, after) in defaultRegexpSpeechModSettings {
                var isHit = false
                for setting in speechModSettingArray {
                    if setting.before == before {
                        isHit = true
                        setting.after = after
                        setting.isUseRegularExpression = true
                        break
                    }
                }
                if isHit { continue }
                let speechModSetting = RealmSpeechModSetting()
                speechModSetting.before = before
                speechModSetting.after = after
                speechModSetting.isUseRegularExpression = true
                realm.add(speechModSetting, update: true)
            }
        }
    }

    // 保存されている読み替え辞書の中から、標準の読み替え辞書を全て削除します
    static func RemoveAllDefaultSpeechModSettings() {
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
    
    // 保存されている全ての読み替え辞書を削除します
    static func RemoveAllSpeechModSettings() {
        guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjects() else { return }
        RealmUtil.Write { (realm) in
            for targetSpeechModSetting in allSpeechModSettings {
                targetSpeechModSetting.delete(realm: realm)
            }
        }
    }
    
    // 標準設定を入れます。結構時間かかるのでバックグラウンドで行われます
    @objc static func InsertDefaultSettingsIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            if RealmGlobalState.GetInstance() != nil {
                return
            }
            RealmUtil.Write(block: { (realm) in
                let globalState = RealmGlobalState()
                let defaultSpeaker = RealmSpeakerSetting()
                let defaultDisplaySetting = RealmDisplaySetting()
                let defaultSpeechOverrideSetting = RealmSpeechOverrideSetting()
                globalState.defaultSpeakerID = defaultSpeaker.id
                globalState.defaultDisplaySettingID = defaultDisplaySetting.id
                globalState.defaultSpeechOverrideSettingID = defaultSpeechOverrideSetting.id
                realm.add(globalState, update: true)
                realm.add(defaultSpeaker, update: true)
                realm.add(defaultDisplaySetting, update: true)
                realm.add(defaultSpeechOverrideSetting, update: true)
            })
            RealmUtil.Write(block: { (realm) in
                let talk1Speaker = RealmSpeakerSetting()
                let talk2Speaker = RealmSpeakerSetting()
                let talk1SectionConfig = RealmSpeechSectionConfig()
                let talk2SectionConfig = RealmSpeechSectionConfig()
                
                talk1Speaker.pitch = 1.5
                talk1Speaker.name = NSLocalizedString("GlobalDataSingleton_Conversation1", comment: "会話文")
                talk1SectionConfig.startText = "「"
                talk1SectionConfig.endText = "」"
                talk1SectionConfig.speakerID = talk1Speaker.id
                
                talk2Speaker.pitch = 1.2
                talk2Speaker.name = NSLocalizedString("GlobalDataSingleton_Conversation2", comment: "会話文2")
                talk2SectionConfig.startText = "『"
                talk2SectionConfig.endText = "』"
                talk2SectionConfig.speakerID = talk2Speaker.id
                
                realm.add(talk1Speaker, update: true)
                realm.add(talk2Speaker, update: true)
                realm.add(talk1SectionConfig, update: true)
                realm.add(talk2SectionConfig, update: true)
            })
            RealmUtil.Write(block: { (realm) in
                let waitConfig1 = RealmSpeechWaitConfig()
                waitConfig1.targetText = "\n\n"
                waitConfig1.delayTimeInSec = 0.5
                realm.add(waitConfig1, update: true)
                for target in ["……", "。", "、", "・"] {
                    let waitConfig = RealmSpeechWaitConfig()
                    waitConfig.targetText = target
                    waitConfig.delayTimeInSec = 0.0
                    realm.add(waitConfig, update: true)
                }
            })
            OverrideDefaultSpeechModSettings()
        }
    }
    
    static func ProcessNovelSpeakerURLScheme(url:URL) -> Bool {
        guard let host = url.host else { return false }
        var cookieArray:[String]? = nil
        let targetUrlString:String
        if host == "downloadncode" {
            // TODO: downloadncode は ncode-ncode-ncode-... と ncode を沢山列記できるので、個別に checkUrlAndConifirmToUser() で取り込み確認をしてもらう事ができない。従って、確実に download できる URL を生成する必要があるが、将来に渡ってそれが生成できるかはよくわからんし、そもそも download queue に入れられるのは RealmNovel と 1章目 の RealmStory が揃っているもののみであり、これを実現するには「1章分だけダウンロードして RealmNovel と RealmStory を作って NovelDownloadQueue に突っ込み直す」という謎の process を入れる必要があり、それをやるとなると NovelDownloadQueue とその process の間で1.5秒間隔のアクセス制限を同期？しないと駄目になってあばばばばばばば…… と思ったので当面は対応しないことにします。
            DispatchQueue.main.async {
                guard let toplevelViewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else {return}
                NiftyUtilitySwift.EasyDialogOneButton(viewController: toplevelViewController, title: nil, message: NSLocalizedString("NovelSpeakerUtility_downloadncodeSchemeIsNotImplementedYet", comment: "novelspeaker://downloadncode/ のサポートは一時的に非サポートになっています。使えるようにするのも吝かではないのですが、多分あまり使っている人が居ないのではないかという気がすごくしますので、開発が後回しになっています。早めの実装をお望みであればその旨をサポートサイト等からお問い合わせください。"), buttonTitle: nil, buttonAction: nil)
            }
            return false
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
    static func ProcessTextFile(url:URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: NiftyUtilitySwift.DetectEncoding(data: data)) else { return false }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtilitySwift.GetToplevelViewController(controller: nil) else { return }
            NiftyUtilitySwift.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil)
        }
        return true
    }

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

    // MARK: バックアップファイルからの書き戻し
    static func ProcessNovelSpeakerBackupFile(url:URL) -> Bool {
        return false
    }

    // MARK: バックアップデータ生成
    fileprivate static func CreateBackupDataDictionary_Story(novelID:String, contentWriteTo:URL?) -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let storyArray = RealmStory.GetAllObjects()?.filter("novelID = %@", novelID).sorted(byKeyPath: "chapterNumber", ascending: true) else { return result }
        for story in storyArray {
            if let contentWriteTo = contentWriteTo {
                do {
                    let filePath = contentWriteTo.appendingPathComponent("\(story.chapterNumber)")
                    try story.contentZiped.write(to: filePath)
                }catch{
                    print("\(story.novelID) chapter: \(story.chapterNumber) content write failed.")
                }
            }
            result.append([
                //"id": story.id,
                "novelID": story.novelID,
                "chapterNumber": story.chapterNumber,
                //"contentZiped": story.contentZiped,
                "readLocation": story.readLocation,
                "url": story.url,
                "lastReadDate": NiftyUtilitySwift.Date2ISO8601String(date: story.lastReadDate),
                "downloadDate": NiftyUtilitySwift.Date2ISO8601String(date: story.downloadDate),
                "subtitle": story.subtitle
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_Bookshelf(withAllStoryContent:Bool, contentWriteTo:URL, progress:((_ description:String)->Void)?) -> ([[String:Any]], [URL]) {
        var result:[[String:Any]] = []
        var fileArray:[URL] = []
        guard let novelArray = RealmNovel.GetAllObjects() else { return (result, []) }
        var novelCount = 1
        let novelArrayCount = novelArray.count
        for novel in novelArray {
            if let progress = progress {
                progress(NSLocalizedString("NovelSpeakerUtility_ExportingNovelData", comment: "小説を抽出中") + " (\(novelCount)/\(novelArrayCount))")
            }
            var novelData:[String:Any] = [
                "novelID": novel.novelID,
                "type": novel._type,
                "writer": novel.writer,
                "title": novel.title,
                "url": novel.url,
                "secret": NiftyUtility.stringEncrypt(novel._urlSecret, key: novel.novelID) ?? "",
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: novel.createdDate),
                "likeLevel": novel.likeLevel,
                "isNeedSpeechAfterDelete": novel.isNeedSpeechAfterDelete,
                "contentDirectory": "\(novelCount)"
            ]
            let contentDirectory = NiftyUtilitySwift.CreateDirectoryFor(path: contentWriteTo, directoryName: "\(novelCount)")
            switch novel.type {
            case .URL:
                if !withAllStoryContent {
                    novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: nil)
                    break
                }
                fallthrough
            case .UserCreated:
                novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: contentDirectory)
                if let contentDirectory = contentDirectory {
                    fileArray.append(contentDirectory)
                }
            }
            result.append(novelData)
            novelCount += 1
        }
        return (result, fileArray)
    }
    fileprivate static func CreateBackupDataDictionary_SpeechModSetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechModSetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "before": setting.before,
                "after": setting.after,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "isUseRegularExpression": setting.isUseRegularExpression,
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeechWaitConfig() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechWaitConfig.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "delayTimeInSec": setting.delayTimeInSec,
                "targetText": setting.targetText,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeakerSetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeakerSetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
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
    fileprivate static func CreateBackupDataDictionary_SpeechSectionConfig() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechSectionConfig.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "startText": setting.startText,
                "endText": setting.endText,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "speakerID": setting.speakerID,
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_GlobalState() -> [String:Any] {
        guard let globalState = RealmGlobalState.GetInstance() else { return [:] }
        return [
            "maxSpeechTimeInSec": globalState.maxSpeechTimeInSec,
            "webImportBookmarkArray": Array(globalState.webImportBookmarkArray),
            "readedPrivacyPolicy": globalState.readedPrivacyPolicy,
            "isOpenRecentNovelInStartTime": globalState.isOpenRecentNovelInStartTime,
            "isLicenseReaded": globalState.isLicenseReaded,
            "isDuckOthersEnabled": globalState.isDuckOthersEnabled,
            "isMixWithOthersEnabled": globalState.isMixWithOthersEnabled,
            "isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled": globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled,
            "isDarkThemeEnabled": globalState.isDarkThemeEnabled,
            "isPlaybackDurationEnabled": globalState.isPlaybackDurationEnabled,
            "isShortSkipEnabled": globalState.isShortSkipEnabled,
            "isReadingProgressDisplayEnabled": globalState.isReadingProgressDisplayEnabled,
            "isForceSiteInfoReloadIsEnabled": globalState.isForceSiteInfoReloadIsEnabled,
            "isMenuItemIsAddSpeechModSettingOnly": globalState.isMenuItemIsAddSpeechModSettingOnly,
            //"isBackgroundNovelFetchEnabled": globalState.isBackgroundNovelFetchEnabled,
            "isPageTurningSoundEnabled": globalState.isPageTurningSoundEnabled,
            "bookSelfSortType": globalState._bookSelfSortType,

            "defaultDisplaySettingID": globalState.defaultDisplaySettingID,
            "defaultSpeakerID": globalState.defaultSpeakerID,
            "defaultSpeechOverrideSettingID": globalState.defaultSpeechOverrideSettingID
        ]
    }
    fileprivate static func CreateBackupDataDictionary_DisplaySetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmDisplaySetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
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
    fileprivate static func CreateBackupDataDictionary_NovelTag() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmNovelTag.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "name": setting.name,
                "type": setting.type,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }
    fileprivate static func CreateBackupDataDictionary_SpeechOverrideSetting() -> [[String:Any]] {
        var result:[[String:Any]] = []
        guard let targetArray = RealmSpeechOverrideSetting.GetAllObjects() else { return result }
        for setting in targetArray {
            result.append([
                "id": setting.id,
                "name": setting.name,
                "createdDate": NiftyUtilitySwift.Date2ISO8601String(date: setting.createdDate),
                "repeatSpeechType": setting._repeatSpeechType,
                "isOverrideRubyIsEnabled": setting.isOverrideRubyIsEnabled,
                "notRubyCharactorStringArray": setting.notRubyCharactorStringArray,
                "isIgnoreURIStringSpeechEnabled": setting.isIgnoreURIStringSpeechEnabled,
                "targetNovelIDArray": Array(setting.targetNovelIDArray)
            ])
        }
        return result
    }

    static func CreateBackupData(withAllStoryContent:Bool, progress:((_ description:String)->Void)?) -> Data? {
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
        ]
        defer { NiftyUtilitySwift.RemoveDirectory(directoryPath: outputPath) }
        var ziptargetFiles:[URL] = bookshelfResult.1
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDictionary, options: [.prettyPrinted])
            let backupDataPath = outputPath.appendingPathComponent("backup_data.json")
            try jsonData.write(to: backupDataPath)
            ziptargetFiles.append(backupDataPath)
        }catch{
            print("JSONSerizization.data() failed. or jsonData.write() failed.")
            return nil
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
        let zipData:Data
        do {
            zipData = try Data(contentsOf: zipFilePath, options: .dataReadingMapped)
        }catch let err{
            print("zip file read error", err)
            return nil
        }
        return zipData
    }
    
    static let LicenseReadKey = "NovelSpeaker_IsLicenseReaded"
    static func IsLicenseReaded() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [LicenseReadKey : false])
        return defaults.bool(forKey: LicenseReadKey)
    }
    static func SetLicenseReaded(isRead:Bool) {
        UserDefaults.standard.set(isRead, forKey: LicenseReadKey)
    }
}
