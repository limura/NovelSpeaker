//
//  NovelSpeakerUtility.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/24.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import SSZipArchive
import RealmSwift
import AVFoundation

class NovelSpeakerUtility: NSObject {
    static let privacyPolicyURL = URL(string: "https://limura.github.io/NovelSpeaker/PrivacyPolicy.txt")
    static let privacyPolicyKey = "NovelSpeaker_ReadedPrivacyPolicy"
    static let UserCreatedContentPrefix = "https://novelspeaker.example.com/UserCreatedContent/"
    static func GetReadedPrivacyPolicy() -> String {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [privacyPolicyKey : ""])
        return defaults.string(forKey: privacyPolicyKey) ?? ""
    }
    static func SetPrivacyPolicyIsReaded(readedText:String) {
        UserDefaults.standard.set(readedText, forKey: privacyPolicyKey)
    }
    
    static let defaultRegexpSpeechModSettings:[String:String] = [
        "([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)\\s*[〜]\\s*([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)": "$1から$2", // 100〜200 → 100から200
        "([0-9０-９零壱弐参肆伍陸漆捌玖拾什陌佰阡仟萬〇一二三四五六七八九十百千万億兆]+)\\s*話": "$1は"
    ]
    
    struct SpeechModSetting: Codable {
        let before:String
        let after:String
        let targetNovelUrlArray:[String]?
        let isRegexp:Bool?
    }
    
    static func getSpeechModSettings(completion:([SpeechModSetting])->Void) {
        var speechModSettings:[SpeechModSetting]? = nil
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if let url = URL(string: globalState.defaultSpeechModURL) ?? URL(string: "https://raw.githubusercontent.com/limura/NovelSpeaker/master/NovelSpeaker/DefaultSpeechModList.json"), let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([SpeechModSetting].self, from: data) {
                    speechModSettings = result
                }
            }
        }
        if speechModSettings == nil, let path = Bundle.main.path(forResource: "DefaultSpeechModList", ofType: "json"), let handle = FileHandle(forReadingAtPath: path), let result = try? JSONDecoder().decode([SpeechModSetting].self, from: handle.readDataToEndOfFile()) {
            speechModSettings = result
        }
        completion(speechModSettings ?? [])
    }
    
    static func ForceOverrideHungSpeakStringToSpeechModSettings_NotRegexp(targets:[String:String]) {
        RealmUtil.RealmBlock { (realm) in
            var writeQueue:[String:String] = [:]
            for (before, after) in targets {
                if let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before){
                    if setting.after != after {
                        writeQueue[before] = after
                    }
                    continue
                }
                writeQueue[before] = after
            }
            if writeQueue.count > 0 {
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    for (before, after) in writeQueue {
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
    }
    
    static func ForceOverrideHungSpeakStringToSpeechModSettings_Regexp(targets:[String:String]) {
        RealmUtil.RealmBlock { (realm) in
            var writeQueue:[String:String] = [:]
            for (before, after) in targets {
                if let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before){
                    if setting.after != after {
                        writeQueue[before] = after
                    }
                    continue
                }
                writeQueue[before] = after
            }
            if writeQueue.count > 0 {
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    for (before, after) in writeQueue {
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
    }
    /// 読み上げ時にハングするような文字を読み上げ時にハングしない文字に変換するようにする読み替え辞書を強制的に登録します
    @objc static func ForceOverrideHungSpeakStringToSpeechModSettings() {
        let targets = ["*": " "]
        ForceOverrideHungSpeakStringToSpeechModSettings_NotRegexp(targets: targets)
        let regexpTargets = ["-{5,}": " "]
        ForceOverrideHungSpeakStringToSpeechModSettings_Regexp(targets: regexpTargets)
    }

    fileprivate static func targetNovelURLArrayToNovelIDArrayWith(novelIDArray:[String], urlArray:[String]?) -> [String] {
        guard let urlArray = urlArray else { return [] }
        var resultSet = Set<String>()
        for urlPattern in urlArray {
            if let firstChar = urlPattern.first, firstChar == "^" {
                // 最初の文字が "^" なら正規表現として扱う
                if let regex = try? NSRegularExpression(pattern: urlPattern, options: []) {
                    for novelID in novelIDArray {
                        if regex.matches(in: novelID, options: [], range: NSMakeRange(0, novelID.count)).count > 0 {
                            resultSet.insert(novelID)
                        }
                    }
                }
            }else{
                // そうでなければ NovelID として扱う
                resultSet.insert(urlPattern)
            }
        }
        return Array(resultSet)
    }
    // 標準の読み替え辞書を上書き登録します。
    static func OverrideDefaultSpeechModSettingsWith(realm:Realm) {
        getSpeechModSettings { (speechModSettings) in
            let novelIDArray:[String]
            if let lazyNovelIDArray = RealmNovel.GetAllObjectsWith(realm: realm)?.map({$0.novelID}) {
                novelIDArray = Array(lazyNovelIDArray)
            }else{
                novelIDArray = []
            }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                for modSetting in speechModSettings {
                    let before = modSetting.before
                    let after = modSetting.after
                    let targetNovelIDArray = targetNovelURLArrayToNovelIDArrayWith(novelIDArray: novelIDArray, urlArray: modSetting.targetNovelUrlArray)
                    
                    if let setting = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before) {
                        setting.after = after
                        setting.isUseRegularExpression = modSetting.isRegexp ?? false
                        if targetNovelIDArray.count > 0 {
                            setting.targetNovelIDArray.removeAll()
                            setting.targetNovelIDArray.append(objectsIn: targetNovelIDArray)
                        }
                        continue
                    }
                    let speechModSetting = RealmSpeechModSetting()
                    speechModSetting.before = before
                    speechModSetting.after = after
                    speechModSetting.isUseRegularExpression = modSetting.isRegexp ?? false
                    if targetNovelIDArray.count > 0 {
                        speechModSetting.targetNovelIDArray.append(objectsIn: targetNovelIDArray)
                    }else{
                        speechModSetting.targetNovelIDArray.append(RealmSpeechModSetting.anyTarget)
                    }
                    realm.add(speechModSetting, update: .modified)
                }
            }
        }
    }

    // 保存されている読み替え辞書の中から、標準の読み替え辞書を全て削除します
    static func RemoveAllDefaultSpeechModSettings() {
        getSpeechModSettings { (speechModSettings) in
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return }
                var removeTargetArray:[RealmSpeechModSetting] = []
                for targetSpeechModSetting in allSpeechModSettings {
                    for modSetting in speechModSettings {
                        let before = modSetting.before
                        let after = modSetting.after
                        let isUseRegularExpression = modSetting.isRegexp ?? false
                        if targetSpeechModSetting.before == before && targetSpeechModSetting.after == after && targetSpeechModSetting.isUseRegularExpression == isUseRegularExpression {
                            removeTargetArray.append(targetSpeechModSetting)
                            break
                        }
                    }
                }
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    for targetSpeechModSetting in removeTargetArray {
                        targetSpeechModSetting.delete(realm: realm)
                    }
                }
            }
        }
    }
    
    // 保存されている全ての読み替え辞書を削除します
    static func RemoveAllSpeechModSettings() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let allSpeechModSettings = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                for targetSpeechModSetting in allSpeechModSettings {
                    targetSpeechModSetting.delete(realm: realm)
                }
            }
        }
    }
    
    // 指定された realm に、必須データが入っているか否かを判定します。
    static func CheckDefaultSettingsAlive(realm:Realm) -> Bool {
        // 中身が無い事にはできない物について判定して、それが一つでもあったら必須データは入っていないと判定します。
        guard let globalState = realm.object(ofType: RealmGlobalState.self, forPrimaryKey: RealmGlobalState.UniqueID) else { return false }
        if globalState.defaultSpeakerID.count <= 0
            || globalState.defaultDisplaySettingID.count <= 0 { return false }
        // 中身が入っていない状態にできる物については判定しないことにします。
        //if globalState.webImportBookmarkArray.count <= 0 { return false }
        //if realm.objects(RealmSpeakerSetting.self).count <= 0 { return false }
        //if realm.objects(RealmSpeechSectionConfig.self).count <= 0 { return false }
        //if realm.objects(RealmSpeechWaitConfig.self).count <= 0 { return false }
        //if realm.objects(RealmSpeechModSetting.self).count <= 0 { return false }
        return true
    }
    // 標準設定を入れます。結構時間かかるのでバックグラウンドで行われます
    @objc static func InsertDefaultSettingsIfNeeded() {
        DispatchQueue.global(qos: .utility).async {
            RealmUtil.RealmBlock { (realm) -> Void in
                if CheckDefaultSettingsAlive(realm: realm) { return }
                let globalState:RealmGlobalState
                if let tmpGlobalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                    globalState = tmpGlobalState
                }else{
                    globalState = RealmGlobalState()
                    RealmUtil.WriteWith(realm: realm, block: { (realm) in
                        realm.add(globalState, update: .modified)
                    })
                }
                RealmUtil.WriteWith(realm: realm, block: { (realm) in
                    if globalState.defaultDisplaySettingWith(realm: realm) == nil {
                        let defaultDisplaySetting = RealmDisplaySetting()
                        defaultDisplaySetting.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
                        globalState.defaultDisplaySettingID = defaultDisplaySetting.name
                        realm.add(defaultDisplaySetting, update: .modified)
                    }
                    if globalState.defaultSpeakerWith(realm: realm) == nil {
                        let defaultSpeaker = RealmSpeakerSetting()
                        defaultSpeaker.name = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
                        globalState.defaultSpeakerID = defaultSpeaker.name
                        realm.add(defaultSpeaker, update: .modified)
                    }
                    if globalState.webImportBookmarkArray.count <= 0 {
                        let defaultBookmarks = [
                            "小説家になろう\nhttps://syosetu.com/",
                            "青空文庫\nhttp://www.aozora.gr.jp/",
                            "ハーメルン\nhttps://syosetu.org/",
                            "暁\nhttps://www.akatsuki-novels.com/",
                            "カクヨム\nhttps://kakuyomu.jp/",
                            "星空文庫\nhttps://slib.net/",
                            "アルファポリス\nhttps://www.alphapolis.co.jp/novel/",
                            "pixiv小説\nhttps://www.pixiv.net/novel/",
                            "ノベルアップ＋\nhttps://novelup.plus/",
                            "エブリスタ\nhttps://estar.jp/",
                            "ポケモン小説スクエア\nhttps://pokemon.sorakaze.info/"
                        ]
                        globalState.webImportBookmarkArray.append(objectsIn: defaultBookmarks)
                    }
                    if globalState.autoSplitStringList.count <= 0 {
                        let defaultAutoSplitStringList:[String] = [
                            "\n[[改ページ]]", "\n[改ページ]", "\n［＃改ページ］", "\n［＃改丁］", "\n\n\n"
                        ]
                        globalState.autoSplitStringList.append(objectsIn: defaultAutoSplitStringList)
                    }
                })

                if RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm)?.count ?? 0 <= 0 {
                    RealmUtil.WriteWith(realm: realm, block: { (realm) in
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

                if RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm)?.count ?? 0 <= 0 {
                    RealmUtil.WriteWith(realm: realm, block: { (realm) in
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

                if RealmSpeechModSetting.GetAllObjectsWith(realm: realm)?.count ?? 0 <= 0 {
                    OverrideDefaultSpeechModSettingsWith(realm: realm)
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
        let targetUrlString:String
        if host == "downloadncode" {
            DispatchQueue.global(qos: .utility).async {
                let ncodeArray = url.path.components(separatedBy: "-")
                var novelIDArray:[String] = []
                for ncode in ncodeArray {
                    guard let targetURL = URL(string: "https://ncode.syosetu.com/\(ncode.lowercased())/") else { continue }
                    let novelID = targetURL.absoluteString
                    RealmUtil.Write { (realm) in
                        let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) ?? RealmNovel()
                        if novel.novelID != novelID {
                            novel.novelID = novelID
                            novel.url = novelID
                            novel.type = .URL
                            realm.add(novel, update: .modified)
                        }
                    }
                    novelIDArray.append(novelID)
                }
                NovelDownloadQueue.shared.addQueueArray(novelIDArray: novelIDArray)
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
            let cookieString:String?
            if let cookieRange = Range(match.range(at: 2), in: absoluteString), let cookieStringCandidate =    String(absoluteString[cookieRange]).removingPercentEncoding {
                cookieString = cookieStringCandidate
            }else{
                cookieString = nil
            }
            guard let targetURL = URL(string: targetUrlString), let rootViewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return false }
            DispatchQueue.main.async {
                NiftyUtility.checkUrlAndConifirmToUser(viewController: rootViewController, url: targetURL, cookieString: cookieString, isNeedFallbackImportFromWebPageTab: true)
            }
            return true
        }else if host == "shareurl" {
            let targetURLString = url.absoluteString.replacingOccurrences(of: "^novelspeaker://shareurl/", with: "", options: .regularExpression)
            if targetURLString == url.absoluteString { return false }
            guard let targetURL = URL(string: targetURLString) else { return false }
            return ProcessURL(url: targetURL)
        }
        return false
    }
    #endif
    
    #if !os(watchOS)
    static func ProcessPDFFile(url:URL) -> Bool {
        let isSecureURL = url.startAccessingSecurityScopedResource()
        defer { if isSecureURL { url.stopAccessingSecurityScopedResource() } }
        guard let text = NiftyUtility.FilePDFToString(url: url) else {
            DispatchQueue.main.async {
                guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
                NiftyUtility.EasyDialogOneButton(
                    viewController: viewController,
                    title: NSLocalizedString("GlobalDataSingleton_PDFToStringFailed_Title", comment: "PDFのテキスト読み込みに失敗"),
                    message: NSLocalizedString("GlobalDataSingleton_PDFToStringFailed_Body", comment: "PDFファイルからの文字列読み込みに失敗しました。\nPDFファイルによっては文字列を読み込めない場合があります。また、iOS11より前のiOSではPDF読み込み機能は動作しません。"),
                    buttonTitle: nil, buttonAction: nil)
            }
            return false
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
            NiftyUtility.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil) { (registerdNovelID, importOptionSeparated) in
                guard let registerdNovelID = registerdNovelID else { return }
                RegisterOuterNovelFileAttributes(novelID: registerdNovelID, fileUrl: url, importOptionSeparated:importOptionSeparated, fileFormat: OuterNovelFileAttributes.FileFormat.pdf)
            }
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessRTFFile(url:URL) -> Bool {
        let isSecureURL = url.startAccessingSecurityScopedResource()
        defer { if isSecureURL { url.stopAccessingSecurityScopedResource() } }
        guard let text = NiftyUtility.FileRTFToAttributedString(url: url)?.string else {
            DispatchQueue.main.async {
                guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
                NiftyUtility.EasyDialogOneButton(
                    viewController: viewController,
                    title: nil,
                    message: NSLocalizedString("GlobalDataSingleton_RTFToStringFailed_Title", comment: "RTFのテキスト読み込みに失敗"),
                    buttonTitle: nil, buttonAction: nil)
            }
            return false
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
            NiftyUtility.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil) { (registerdNovelID, importOptionSeparated) in
                guard let registerdNovelID = registerdNovelID else { return }
                RegisterOuterNovelFileAttributes(novelID: registerdNovelID, fileUrl: url, importOptionSeparated:importOptionSeparated, fileFormat: OuterNovelFileAttributes.FileFormat.rtf)
            }
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessRTFDFile(url:URL) -> Bool {
        let isSecureURL = url.startAccessingSecurityScopedResource()
        defer { if isSecureURL { url.stopAccessingSecurityScopedResource() } }
        guard let text = NiftyUtility.FileRTFDToAttributedString(url: url)?.string else {
            DispatchQueue.main.async {
                guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
                NiftyUtility.EasyDialogOneButton(
                    viewController: viewController,
                    title: nil,
                    message: NSLocalizedString("GlobalDataSingleton_RTFToStringFailed_Title", comment: "RTFのテキスト読み込みに失敗"),
                    buttonTitle: nil, buttonAction: nil)
            }
            return false
        }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
            NiftyUtility.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil)
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessTextFile(url:URL) -> Bool {
        let isSecureURL = url.startAccessingSecurityScopedResource()
        defer { if isSecureURL { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: NiftyUtility.DetectEncoding(data: data)) else { return false }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
            NiftyUtility.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil) { (registerdNovelID, importOptionSeparated) in
                guard let registerdNovelID = registerdNovelID else { return }
                RegisterOuterNovelFileAttributes(novelID: registerdNovelID, fileUrl: url, importOptionSeparated:importOptionSeparated, fileFormat: OuterNovelFileAttributes.FileFormat.plainText)
            }
        }
        return true
    }
    #endif
    #if !os(watchOS)
    static func ProcessHtmlFile(url:URL) -> Bool {
        let isSecureURL = url.startAccessingSecurityScopedResource()
        defer { if isSecureURL { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return false }
        
        let (html, guessedEncoding) = NiftyUtility.decodeHTMLStringFrom(data: data, headerEncoding: NiftyUtility.DetectEncoding(data: data))
        let text:String?
        if let html = html {
            text = NiftyUtility.HTMLToString(htmlString: html)
        }else{
            text = NiftyUtility.HTMLDataToString(htmlData: data, encoding: guessedEncoding ?? .utf8)
        }
        guard let text = text else { return false }
        let fileName = url.deletingPathExtension().lastPathComponent
        DispatchQueue.main.async {
            guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return }
            NiftyUtility.checkTextImportConifirmToUser(viewController: viewController, title: fileName.count > 0 ? fileName : "unknown title", content: text, hintString: nil) { (registerdNovelID, importOptionSeparated) in
                guard let registerdNovelID = registerdNovelID else { return }
                RegisterOuterNovelFileAttributes(novelID: registerdNovelID, fileUrl: url, importOptionSeparated:importOptionSeparated, fileFormat: OuterNovelFileAttributes.FileFormat.html)
            }
        }
        return true
    }
    #endif

    #if !os(watchOS)
    @discardableResult
    @objc public static func ProcessURL(url:URL?) -> Bool {
        guard let url = url else { return false }
        print("ProcessURL: \(url.absoluteString)")
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
        if url.scheme == "http" || url.scheme == "https" {
            // fetch しようとしてみる。
            if let toplevelViewController = NiftyUtility.GetRegisterdToplevelViewController() {
                DispatchQueue.main.async {
                    NiftyUtility.checkUrlAndConifirmToUser(viewController: toplevelViewController, url: url, cookieString: nil, isNeedFallbackImportFromWebPageTab: true)
                }
                return true
            }
        }
        if url.pathExtension == "html" {
            return ProcessHtmlFile(url:url)
        }
        return ProcessTextFile(url:url)
    }
    #endif
    
    #if !os(watchOS)
    static func RestoreSpeechMod_V_1_0_0(dic:NSDictionary){
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let speechModArray = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return }
            for (key, value) in dic {
                guard let before = key as? String, let after = value as? String else { continue }
                var hit = false
                for speechMod in speechModArray {
                    if before == speechMod.before {
                        hit = true
                        if speechMod.after != after {
                            RealmUtil.WriteWith(realm: realm) { (realm) in
                                speechMod.after = after
                            }
                        }
                        break
                    }
                }
                if !hit {
                    RealmUtil.WriteWith(realm: realm) { (realm) in
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
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let speechModArray = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return }
            for (key, value) in dic {
                guard let valueDic = value as? NSDictionary, let before = key as? String, let after = valueDic.object(forKey: "afterString") as? String, let type = (valueDic.object(forKey: "type") as? NSNumber)?.intValue else { continue }
                var hit = false
                for speechMod in speechModArray {
                    if before == speechMod.before {
                        hit = true
                        if speechMod.after != after || speechMod.isUseRegularExpression != true {
                            RealmUtil.WriteWith(realm: realm) { (realm) in
                                speechMod.after = after
                                speechMod.isUseRegularExpression = type == Int(SpeechModSettingConvertType.regexp.rawValue)
                            }
                        }
                        break
                    }
                }
                if !hit {
                    RealmUtil.WriteWith(realm: realm) { (realm) in
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
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalStatus = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                for target in array {
                    guard let target = target as? NSDictionary else { continue }
                    for (key, value) in target {
                        guard let name = key as? String, let url = value as? String else { continue }
                        let bookmark:String
                        if name == "アルファポリス(Web取込 非対応サイトになりました。詳細はサポートサイト下部にありますQ&Aを御覧ください)\nhttps://www.alphapolis.co.jp/novel/" {
                            bookmark = "アルファポリス\n\(url)"
                        }else{
                            bookmark = "\(name)\n\(url)"
                        }
                        if globalStatus.webImportBookmarkArray.contains(bookmark) { continue }
                        globalStatus.webImportBookmarkArray.append(bookmark)
                        realm.add(globalStatus, update: .modified)
                    }
                }
            }
        }
    }
    
    static func RestoreSpeakPitch_V_1_0_0(dic:NSDictionary) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let defaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) else { return }
            if let defaultDictionary = dic.object(forKey: "default") as? NSDictionary, let pitch = defaultDictionary.object(forKey: "pitch") as? NSNumber, let rate = defaultDictionary.object(forKey: "rate") as? NSNumber {
                RealmUtil.WriteWith(realm: realm) { (realm) in
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
            guard let othersArray = dic.object(forKey: "others") as? NSArray, let speechSectionArray = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) else { return }
            for obj in othersArray {
                guard let dic = obj as? NSDictionary,
                    let title = dic.object(forKey: "title") as? String,
                    let start_text = dic.object(forKey: "start_text") as? String,
                    let end_text = dic.object(forKey: "end_text") as? String,
                    let pitch = dic.object(forKey: "pitch") as? NSNumber else { continue }
                let pitchValue = pitch.floatValue
                if pitchValue < 0.5 || pitchValue > 2.0 { continue }
                if let speaker = RealmSpeakerSetting.SearchFromWith(realm: realm, name: title) {
                    RealmUtil.WriteWith(realm: realm) { (realm) in
                        speaker.voiceIdentifier = defaultSpeaker.voiceIdentifier
                        speaker.locale = defaultSpeaker.locale
                        speaker.type = defaultSpeaker.type
                        speaker.rate = defaultSpeaker.rate
                        speaker.pitch = pitchValue
                    }
                    if let section = speechSectionArray.filter("startText = %@ AND endText = %@", start_text, end_text).first {
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            section.speakerID = speaker.name
                        }
                    }else{
                        RealmUtil.WriteWith(realm: realm) { (realm) in
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
                    speaker.locale = defaultSpeaker.locale
                    speaker.type = defaultSpeaker.type
                    RealmUtil.WriteWith(realm: realm) { (realm) in
                        realm.add(speaker, update: .modified)
                    }
                    if let section = speechSectionArray.filter("startText = %@ AND endText = %@", start_text, end_text).first {
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            section.speakerID = speaker.name
                        }
                    }else{
                        RealmUtil.WriteWith(realm: realm) { (realm) in
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
    
    static func RestoreSpeechWaitConfig_V_1_0_0(waitArray:NSArray) {
        for dic in waitArray {
            if let dic = dic as? NSDictionary, let target_text = dic.object(forKey: "target_text") as? String, let delay_time_in_sec = dic.object(forKey: "delay_time_in_sec") as? NSNumber, target_text.count > 0 && delay_time_in_sec.floatValue >= 0 {
                let delayTimeInSec = delay_time_in_sec.floatValue
                // 改行の保存形式は \r\n から \n に変更されました。
                let targetText = NovelSpeakerUtility.NormalizeNewlineString(string: target_text)
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let speechWaitConfig = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm)?.filter("targetText = %@", targetText).first {
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            speechWaitConfig.delayTimeInSec = delayTimeInSec
                        }
                    }else{
                        let speechWaitConfig = RealmSpeechWaitConfig()
                        speechWaitConfig.delayTimeInSec = delayTimeInSec
                        speechWaitConfig.targetText = targetText
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            realm.add(speechWaitConfig, update: .modified)
                        }
                    }
                }
            }
        }
    }
    
    static func RestoreMiscSettings_V_1_0_0(dic:NSDictionary) -> String? {
        return RealmUtil.RealmBlock { (realm) -> String? in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm), let defaultSpeaker = globalState.defaultSpeakerWith(realm: realm), let defaultDisplaySetting = globalState.defaultDisplaySettingWith(realm: realm) else { return nil }
            var currentReadingContent:String? = nil
            RealmUtil.WriteWith(realm: realm) { (realm) in
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
                    globalState.bookShelfSortType = NarouContentSortType(rawValue: content_sort_type.intValue) ?? NarouContentSortType.Title
                }
                if let menuitem_is_add_speech_mod_setting_only = dic.value(forKey: "menuitem_is_add_speech_mod_setting_only") as? NSNumber {
                    globalState.isMenuItemIsAddNovelSpeakerItemsOnly = menuitem_is_add_speech_mod_setting_only.boolValue
                }
                if let override_ruby_is_enabled = dic.value(forKey: "override_ruby_is_enabled") as? NSNumber {
                    globalState.isOverrideRubyIsEnabled = override_ruby_is_enabled.boolValue
                }
                if let is_ignore_url_speech_enabled = dic.value(forKey: "is_ignore_url_speech_enabled") as? NSNumber {
                    globalState.isIgnoreURIStringSpeechEnabled = is_ignore_url_speech_enabled.boolValue
                }
                if let not_ruby_charactor_array = dic.value(forKey: "not_ruby_charactor_array") as? String {
                    globalState.notRubyCharactorStringArray = not_ruby_charactor_array
                }
                if let force_siteinfo_reload_is_enabled = dic.value(forKey: "force_siteinfo_reload_is_enabled") as? NSNumber {
                    RealmGlobalState.SetIsForceSiteInfoReloadIsEnabled(newValue: force_siteinfo_reload_is_enabled.boolValue)
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
                    globalState.repeatSpeechType = RepeatSpeechType(rawValue: repeat_speech_type.intValue) ?? RepeatSpeechType.NoRepeat
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
                realm.add(globalState, update: .modified)
                if let current_reading_content = dic.value(forKey: "current_reading_content") as? String {
                    currentReadingContent = current_reading_content
                }
            }
            return currentReadingContent
        }
    }
    
    static func RestoreBookshelf_ncode_V_1_0_0(novel:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        guard let ncode = novel.object(forKey: "ncode") as? String else { return }
        RealmUtil.Write { (realm) in
            let urlString = CoreDataToRealmTool.NcodeToUrlString(ncode: ncode, no: 1, end: false)
            let realmNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: urlString) ?? RealmNovel()
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
                    realmNovel.m_readingChapterReadingPoint = currentReadLocation.intValue
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
            if let novelupdated_at = novel.object(forKey: "novelupdated_at") as? String, let lastDownloadDate = NiftyUtility.ISO8601String2Date(iso8601String: novelupdated_at) {
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
                    guard let data = try? Data(contentsOf: targetFilePath), let content = String(data: data, encoding: NiftyUtility.DetectEncoding(data: data))  else { break }
                    var story = Story()
                    story.novelID = novelID
                    story.chapterNumber = no
                    story.content = NormalizeNewlineString(string: content).replacingOccurrences(of: "\u{00}", with: "")
                    story.url = CoreDataToRealmTool.NcodeToUrlString(ncode: ncode, no: no, end: end.boolValue)
                    storyArray.append(story)
                    if no == currentReadingChapterNumber {
                        realmNovel.m_readingChapterContentCount = story.content.count
                    }
                    if storyArray.count >= RealmStoryBulk.bulkCount {
                        RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                        storyArray.removeAll()
                    }
                }while(true)
                if storyArray.count > 0 {
                    RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                    storyArray.removeAll()
                }
                no -= 1
                if no >= 0 {
                    realmNovel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: no)
                    realm.add(realmNovel, update: .modified)
                }
                for _ in 0...no {
                    realmNovel.AppendDownloadDate(realm: realm, date: realmNovel.lastDownloadDate)
                }
            }else{
                NovelDownloadQueue.shared.addQueue(novelID: novelID)
            }
        }
    }

    static func RestoreBookshelf_url_V_1_0_0(novel:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> [HTTPCookie] {
        guard let url = novel.object(forKey: "url") as? String else { return [] }
        var cookieArray:[HTTPCookie] = []
        func addNewCookie(urlSecret:String, urlString:String, lastUpdateDate:Date) {
            // 元のcookieでは path や expire date がどう指定されていたかを推測できないため、
            // とりあえず path は '/' 固定で、最終ダウンロード日時から1日後まで有効、という事にします。
            guard let fullPathURL = URL(string: urlString), let host = fullPathURL.host, let scheme = fullPathURL.scheme, let url = URL(string: "\(scheme)://\(host)") else { return }
            let expireDate = lastUpdateDate.addingTimeInterval(60*60*24)
            let newCookieArray = NiftyUtility.ConvertJavaScriptCookieStringToHTTPCookieArray(javaScriptCookieString: urlSecret, targetURL: url, expireDate: expireDate)
            cookieArray = NiftyUtility.RemoveExpiredCookie(cookieArray: NiftyUtility.MergeCookieArray(currentCookieArray: cookieArray, newCookieArray: newCookieArray))
        }
        RealmUtil.Write { (realm) in
            let realmNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: url) ?? RealmNovel()
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
                    realmNovel.m_readingChapterReadingPoint = currentReadLocation.intValue
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
            if let novelupdated_at = novel.object(forKey: "novelupdated_at") as? String, let lastDownloadDate = NiftyUtility.ISO8601String2Date(iso8601String: novelupdated_at) {
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
            if let secret = novel.object(forKey: "secret") as? String, let urlSecret = NiftyUtility.stringDecrypt(string: secret, key: url) {
                addNewCookie(urlSecret: urlSecret, urlString: novelID, lastUpdateDate: realmNovel.lastDownloadDate)
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
                    var result:Bool = false
                    autoreleasepool {
                        no += 1
                        let targetFilePath = contentDirectory.appendingPathComponent("\(no).txt")
                        guard let data = try? Data(contentsOf: targetFilePath), let content = String(data: data, encoding: NiftyUtility.DetectEncoding(data: data))  else { return }
                        var story = Story()
                        story.novelID = novelID
                        story.chapterNumber = no
                        story.content = NormalizeNewlineString(string: content).replacingOccurrences(of: "\u{00}", with: "")
                        if no == currentReadingChapterNumber {
                            realmNovel.m_readingChapterContentCount = story.content.count
                        }
                        storyArray.append(story)
                        if storyArray.count >= RealmStoryBulk.bulkCount {
                            autoreleasepool {
                                _ = RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                            }
                            storyArray.removeAll()
                        }
                        result = true
                    }
                    if result == false { break }
                }while(true)
                if storyArray.count > 0 {
                    RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                    storyArray.removeAll()
                }
                no -= 1
                if no >= 0 {
                    realmNovel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: no)
                    realm.add(realmNovel, update: .modified)
                }
                for _ in 0...no {
                    realmNovel.AppendDownloadDate(realm: realm, date: realmNovel.lastDownloadDate)
                }
                if no > 0, var story = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: no), let last_download_url = novel.object(forKey: "last_download_url") as? String {
                    story.url = last_download_url
                    RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                }
            }else{
                NovelDownloadQueue.shared.addQueue(novelID: novelID)
            }
        }
        return cookieArray
    }

    static func RestoreBookshelf_user_V_1_0_0(novel:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        guard let id = novel.object(forKey: "id") as? String, let title = novel.object(forKey: "title") as? String, let storys = novel.object(forKey: "storys") as? NSArray else { return }
        let novelID = NovelSpeakerUtility.UserCreatedContentPrefix + id
        RealmUtil.Write { (realm) in
            let realmNovel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) ?? RealmNovel()
            if realmNovel.novelID != novelID {
                realmNovel.novelID = novelID
                realmNovel.type = .UserCreated
            }
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
                story.content = NormalizeNewlineString(string: storyText).replacingOccurrences(of: "\u{00}", with: "")
                storyArray.append(story)
                if storyArray.count >= RealmStoryBulk.bulkCount {
                    RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                    storyArray.removeAll()
                }
            }
            if storyArray.count > 0 {
                RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                storyArray.removeAll()
            }
            if no > 0 {
                realmNovel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: no)
                realm.add(realmNovel, update: .modified)
            }
        }
    }
    
    static func RestoreBookshelf_V_1_0_0(novelArray:NSArray, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> [HTTPCookie] {
        // 一旦ダウンロードは止めておきます。
        NovelDownloadQueue.shared.downloadStop()
        defer { NovelDownloadQueue.shared.downloadStart() }
        var count = 0
        var cookieArray:[HTTPCookie] = []
        for novel in novelArray {
            count += 1
            progressUpdate(NSLocalizedString("GlobalDataSingleton_RestoreingBookProgress", comment: "小説の復元中") + "(\(count)/\(novelArray.count))")
            guard let novel = novel as? NSDictionary, let type = novel.value(forKey: "type") as? String else { continue }
            switch type {
            case "ncode":
                RestoreBookshelf_ncode_V_1_0_0(novel:novel, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
            case "url":
                let newCookieArray = RestoreBookshelf_url_V_1_0_0(novel:novel, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
                cookieArray = NiftyUtility.RemoveExpiredCookie(cookieArray: NiftyUtility.MergeCookieArray(currentCookieArray: cookieArray, newCookieArray: newCookieArray))
            case "user":
                RestoreBookshelf_user_V_1_0_0(novel:novel, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
            default:
                continue
            }
        }
        return cookieArray
    }
    
    static func ProcessNovelSpeakerBackupJSONData_V_1_0_0(toplevelDictionary:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
        // misc_settings を一番先に読み出すのは
        // misc_settings に default_voice_identifier があるからで、
        // default_voice_identifier で標準の読み上げ話者が設定された物を
        // 後で RestoreSpeakPitch_V_1_0_0 側で使うというトリッキーな事をしています。
        // さらに、currentReadingNovelID も misc_settings にあるため、
        // コレを取り出して後で使っています。(´・ω・`)
        let currentReadingNovelID:String?
        if let miscDictionary = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            currentReadingNovelID = RestoreMiscSettings_V_1_0_0(dic:miscDictionary)
        }else{
            currentReadingNovelID = nil
        }
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
        var newCookieArray:[HTTPCookie] = []
        if let novelArray = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            newCookieArray = RestoreBookshelf_V_1_0_0(novelArray:novelArray, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            if let targetNovelID = currentReadingNovelID, let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                let coreDataNarouContent = NarouContentCacheData()
                coreDataNarouContent.ncode = targetNovelID
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    if newCookieArray.count > 0 {
                        HTTPCookieSyncTool.shared.SaveCookiesFromCookieArrayWith(realm: realm, cookieArray: newCookieArray)
                        HTTPCookieSyncTool.shared.LoadCookiesFromRealmWith(realm: realm)
                    }
                    if coreDataNarouContent.isURLContent() {
                        globalState.currentReadingNovelID = targetNovelID
                    }else if targetNovelID.hasPrefix("_u") {
                        globalState.currentReadingNovelID = NovelSpeakerUtility.UserCreatedContentPrefix + targetNovelID
                    }else{
                        globalState.currentReadingNovelID = CoreDataToRealmTool.NcodeToUrlString(ncode: targetNovelID, no: 1, end: false)
                    }
                }
            }
        }
        return true
    }
    static func ProcessNovelSpeakerBackupJSONData_V_1_1_0(toplevelDictionary:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
        // misc_settings を一番先に読み出すのは
        // misc_settings に default_voice_identifier があるからで、
        // default_voice_identifier で標準の読み上げ話者が設定された物を
        // 後で RestoreSpeakPitch_V_1_0_0 側で使うというトリッキーな事をしています。
        // さらに、currentReadingNovelID も misc_settings にあるため、
        // コレを取り出して後で使っています。(´・ω・`)
        let currentReadingNovelID:String?
        if let miscDictionary = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            currentReadingNovelID = RestoreMiscSettings_V_1_0_0(dic:miscDictionary)
        }else{
            currentReadingNovelID = nil
        }
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
        var newCookieArray:[HTTPCookie] = []
        if let novelArray = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            newCookieArray = RestoreBookshelf_V_1_0_0(novelArray:novelArray, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            if let targetNovelID = currentReadingNovelID, let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                let coreDataNarouContent = NarouContentCacheData()
                coreDataNarouContent.ncode = targetNovelID
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    if newCookieArray.count > 0 {
                        HTTPCookieSyncTool.shared.SaveCookiesFromCookieArrayWith(realm: realm, cookieArray: newCookieArray)
                        HTTPCookieSyncTool.shared.LoadCookiesFromRealmWith(realm: realm)
                    }
                    if coreDataNarouContent.isURLContent() {
                        globalState.currentReadingNovelID = targetNovelID
                    }else if targetNovelID.hasPrefix("_u") {
                        globalState.currentReadingNovelID = NovelSpeakerUtility.UserCreatedContentPrefix + targetNovelID
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
                let mod = RealmSpeechModSetting.SearchFromWith(realm: realm, beforeString: before) ?? RealmSpeechModSetting()
                if mod.before != before {
                    mod.before = before
                }
                mod.after = after
                if let createdDateString = speechMod.object(forKey: "createdDate") as? String, let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
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
                realm.add(mod, update: .modified)
            }
        }
    }
    
    static func RestoreSpeechWaitConfig_V_2_0_0(waitArray:NSArray, progressUpdate:@escaping(String)->Void) {
        for speechWaitDic in waitArray {
            guard let speechWait = speechWaitDic as? NSDictionary,
                let delayTimeInSec = speechWait.object(forKey: "delayTimeInSec") as? NSNumber,
                let targetText = speechWait.object(forKey: "targetText") as? String else { return }
            RealmUtil.RealmBlock { (realm) -> Void in
                let speechWaitConfig = RealmSpeechWaitConfig.SearchFromWith(realm: realm, targetText: targetText) ?? RealmSpeechWaitConfig()
                if speechWaitConfig.targetText != targetText {
                    speechWaitConfig.targetText = targetText
                }
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    speechWaitConfig.delayTimeInSec = delayTimeInSec.floatValue
                    if let createdDateString = speechWait.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
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
            RealmUtil.RealmBlock { (realm) -> Void in
                let speakerSetting:RealmSpeakerSetting
                if name == defaultSpeakerSettingID {
                    guard let defaultSpeaker = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultSpeakerWith(realm: realm) else { return }
                    speakerSetting = defaultSpeaker
                }else{
                    speakerSetting = RealmSpeakerSetting.SearchFromWith(realm:realm, name: name) ?? RealmSpeakerSetting()
                    if speakerSetting.name != name {
                        speakerSetting.name = name
                    }
                }
                RealmUtil.WriteWith(realm: realm) { (realm) in
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
                        let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
                        speakerSetting.createdDate = createdDate
                    }
                    realm.add(speakerSetting, update: .modified)
                }
            }
        }
    }
    static func RestoreSpeechSectionConfig_V_2_0_0(sectionConfigArray:NSArray, progressUpdate:@escaping(String)->Void){
        RealmUtil.Write { realm in
            if let oldSectionConfigs = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) {
                for c in oldSectionConfigs {
                    realm.delete(c)
                }
            }
            struct configTmp {
                var sectionConfigDic:NSDictionary
                var name:String
                var startText:String
                var endText:String
                var speakerID:String
            }
            var newConfigs:[configTmp] = []
            for sectionConfig in sectionConfigArray {
                guard
                    let sectionConfigDic = sectionConfig as? NSDictionary,
                    let name = sectionConfigDic.object(forKey: "name") as? String,
                    let startText = sectionConfigDic.object(forKey: "startText") as? String,
                    let endText = sectionConfigDic.object(forKey: "endText") as? String,
                    let speakerID = sectionConfigDic.object(forKey: "speakerID") as? String
                else { continue }
                newConfigs.append(configTmp(sectionConfigDic: sectionConfigDic, name: name, startText: startText, endText: endText, speakerID: speakerID))
            }
            if newConfigs.count <= 0 { return }
            for newConfig in newConfigs {
                let sectionConfig = RealmSpeechSectionConfig()
                sectionConfig.name = newConfig.name
                sectionConfig.startText = newConfig.startText
                sectionConfig.endText = newConfig.endText
                if let createdDateString = newConfig.sectionConfigDic.object(forKey: "createdDate") as? String,
                   let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
                    sectionConfig.createdDate = createdDate
                }
                sectionConfig.speakerID = newConfig.speakerID
                sectionConfig.targetNovelIDArray.removeAll()
                if let targetNovelIDArray = newConfig.sectionConfigDic.object(forKey: "targetNovelIDArray") as? NSArray {
                    for novel in targetNovelIDArray {
                        guard let novel = novel as? String else { continue }
                        sectionConfig.targetNovelIDArray.append(novel)
                    }
                }
                realm.add(sectionConfig, update: .modified)
            }
        }
    }
    static func RestoreDisplaySettings_V_2_0_0(displaySettingArray:NSArray,  defaultSpeakerSettingID:String, progressUpdate:@escaping(String)->Void) {
        for displaySettingObj in displaySettingArray {
            guard let displaySettingDic = displaySettingObj as? NSDictionary,
                let name = displaySettingDic.object(forKey: "name") as? String else { continue }
            RealmUtil.RealmBlock { (realm) -> Void in
                let setting:RealmDisplaySetting
                if name == defaultSpeakerSettingID {
                    guard let defaultSetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) else { return }
                    setting = defaultSetting
                }else{
                    setting = RealmDisplaySetting.SearchFromWith(realm: realm, name: name) ?? RealmDisplaySetting()
                    if setting.name != name {
                        setting.name = name
                    }
                }
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    if let textSizeValue = displaySettingDic.object(forKey: "textSizeValue") as? NSNumber {
                        setting.textSizeValue = textSizeValue.floatValue
                    }
                    if let fontID = displaySettingDic.object(forKey: "fontID") as? String {
                        setting.fontID = fontID
                    }
                    if let viewTypeString = displaySettingDic.object(forKey: "viewType") as? String, let viewType = RealmDisplaySetting.ViewType(rawValue: viewTypeString) {
                        setting.viewType = viewType
                    }

                    if let createdDateString = displaySettingDic.object(forKey: "createdDate") as? String,
                        let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
                        setting.createdDate = createdDate
                    }
                    if let lineSpacing = displaySettingDic.object(forKey: "lineSpacing") as? NSNumber {
                        setting.lineSpacing = lineSpacing.floatValue
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
                let tag = RealmNovelTag.SearchWith(realm: realm, name: name, type: type) ?? RealmNovelTag.CreateNewTag(name: name, type: type)
                if let createdDateString = tagDic.object(forKey: "createdDate") as? String,
                    let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString){
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
                guard let bookmarkDic = bookmark as? NSDictionary, let id = bookmarkDic.object(forKey: "id") as? String, let createdDateString = bookmarkDic.object(forKey: "createdDate") as? String, let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString), let novelID = bookmarkDic.object(forKey: "novelID") as? String, let chapterNumber = (bookmarkDic.object(forKey: "chapterNumber") as? NSNumber)?.intValue, chapterNumber > 0, let location = (bookmarkDic.object(forKey: "location") as? NSNumber)?.intValue else { continue }
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

    static func RestoreGlobalState_V_2_0_0(dic:NSDictionary, progressUpdate:@escaping(String)->Void) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            RealmUtil.WriteWith(realm: realm) { (realm) in
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
                    RealmGlobalState.SetIsForceSiteInfoReloadIsEnabled(newValue: isForceSiteInfoReloadIsEnabled.boolValue)
                }
                if let isMenuItemIsAddNovelSpeakerItemsOnly = dic.object(forKey: "isMenuItemIsAddNovelSpeakerItemsOnly")  as? NSNumber {
                    globalState.isMenuItemIsAddNovelSpeakerItemsOnly = isMenuItemIsAddNovelSpeakerItemsOnly.boolValue
                }
                if let isPageTurningSoundEnabled = dic.object(forKey: "isPageTurningSoundEnabled") as? NSNumber {
                    globalState.isPageTurningSoundEnabled = isPageTurningSoundEnabled.boolValue
                }
                if let m_BookSelfSortType = dic.object(forKey: "bookSelfSortType") as? NSNumber, let bookSelfSortType = NarouContentSortType(rawValue: Int(m_BookSelfSortType.intValue)) {
                    globalState.bookShelfSortType = bookSelfSortType
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
                if let currentWebSearchSite = dic.object(forKey: "currentWebSearchSite") as? String {
                    globalState.currentWebSearchSite = currentWebSearchSite
                }
                if let autoSplitStringList = dic.object(forKey: "autoSplitStringList") as? NSArray {
                    globalState.autoSplitStringList.removeAll()
                    for splitString in autoSplitStringList {
                        if let splitString = splitString as? String {
                            globalState.autoSplitStringList.append(splitString)
                        }
                    }
                }
                if let novelSpeakerSiteInfoURL = dic.object(forKey: "novelSpeakerSiteInfoURL") as? String {
                    StoryHtmlDecoder.shared.ClearSiteInfo()
                    globalState.novelSpeakerSiteInfoURL = novelSpeakerSiteInfoURL
                }
                if let autopagerizeSiteInfoURL = dic.object(forKey: "autopagerizeSiteInfoURL") as? String {
                    StoryHtmlDecoder.shared.ClearSiteInfo()
                    globalState.autopagerizeSiteInfoURL = autopagerizeSiteInfoURL
                }
                if let defaultSpeechModURL = dic.object(forKey: "defaultSpeechModURL") as? String {
                    globalState.defaultSpeechModURL = defaultSpeechModURL
                }
                if let searchInfoURL = dic.object(forKey: "searchInfoURL") as? String {
                    globalState.searchInfoURL = searchInfoURL
                }
                if let speechViewButtonSettingArrayData = dic.object(forKey: "speechViewButtonSettingArrayData") as? String, let data = Data(base64Encoded: speechViewButtonSettingArrayData) {
                    globalState.speechViewButtonSettingArrayData = data
                }
                if let cookieArrayData = dic.object(forKey: "cookieArrayData") as? String, let data = Data(base64Encoded: cookieArrayData) {
                    globalState.cookieArrayData = data
                }
                if let m_DisplayType = dic.object(forKey: "novelDisplayType") as? NSNumber, let displayType = NovelDisplayType(rawValue: m_DisplayType.intValue) {
                    globalState.novelDisplayType = displayType
                }
                if let bookshelfViewButtonSettingArrayData = dic.object(forKey: "bookshelfViewButtonSettingArrayData") as? String, let data = Data(base64Encoded: bookshelfViewButtonSettingArrayData) {
                    globalState.bookshelfViewButtonSettingArrayData = data
                }
                if let repeatSpeechType = dic.object(forKey: "repeatSpeechType") as? NSNumber {
                    globalState.repeatSpeechType = RepeatSpeechType(rawValue: repeatSpeechType.intValue) ?? RepeatSpeechType.NoRepeat
                }
                if let repeatSpeechLoopType = dic.object(forKey: "repeatSpeechLoopType") as? String {
                    globalState.repeatSpeechLoopType = RepeatSpeechLoopType(rawValue: repeatSpeechLoopType) ?? RepeatSpeechLoopType.normal
                }
                if let isAnnounceAtRepatSpeechTime = dic.value(forKey: "isAnnounceAtRepatSpeechTime") as? NSNumber {
                    globalState.isAnnounceAtRepatSpeechTime = isAnnounceAtRepatSpeechTime.boolValue
                }
                if let isOverrideRubyIsEnabled = dic.object(forKey: "isOverrideRubyIsEnabled") as?   NSNumber {
                    globalState.isOverrideRubyIsEnabled = isOverrideRubyIsEnabled.boolValue
                }
                if let notRubyCharactorStringArray = dic.object(forKey:  "notRubyCharactorStringArray") as? String {
                    globalState.notRubyCharactorStringArray = notRubyCharactorStringArray
                }
                if let isIgnoreURIStringSpeechEnabled = dic.object(forKey:   "isIgnoreURIStringSpeechEnabled") as? NSNumber {
                    globalState.isIgnoreURIStringSpeechEnabled = isIgnoreURIStringSpeechEnabled.boolValue
                }
                if let isEnableSwipeOnStoryView = dic.object(forKey:   "isEnableSwipeOnStoryView") as? NSNumber {
                    globalState.isEnableSwipeOnStoryView = isEnableSwipeOnStoryView.boolValue
                }
                if let isDisableNarouRuby = dic.object(forKey: "isDisableNarouRuby") as? NSNumber {
                    globalState.isDisableNarouRuby = isDisableNarouRuby.boolValue
                }
                if let isNeedDisableIdleTimerWhenSpeechTime = dic.object(forKey: "isNeedDisableIdleTimerWhenSpeechTime") as? NSNumber {
                    globalState.isNeedDisableIdleTimerWhenSpeechTime = isNeedDisableIdleTimerWhenSpeechTime.boolValue
                }
                if let isDeleteBlockOnBookshelfTreeView = dic.object(forKey: "isDeleteBlockOnBookshelfTreeView") as? NSNumber {
                    globalState.isDeleteBlockOnBookshelfTreeView = isDeleteBlockOnBookshelfTreeView.boolValue
                }
                if let supportRotationMask = dic.object(forKey: "supportRotationMask") as? NSNumber {
                    if supportRotationMask.uintValue == UIInterfaceOrientationMask.all.rawValue {
                        NovelSpeakerUtility.supportRotationMask = .all
                    }else{
                        NovelSpeakerUtility.supportRotationMask = .portrait
                    }
                }
                if let novelLikeOrder = dic.object(forKey: "novelLikeOrder") as? NSArray {
                    globalState.novelLikeOrder.removeAll()
                    for novelID in novelLikeOrder {
                        if let novelID = novelID as? String {
                            globalState.novelLikeOrder.append(novelID)
                        }
                    }
                }
                if let menuItemsNotRemoved = dic.object(forKey: "menuItemsNotRemoved") as? NSArray {
                    globalState.menuItemsNotRemoved.removeAll()
                    for target in menuItemsNotRemoved {
                        if let target = target as? String {
                            globalState.menuItemsNotRemoved.append(target)
                        }
                    }
                }
                if let likeButtonDialogTypeNumber = dic.object(forKey: "likeButtonDialogType") as? NSNumber, let likeButtonDialogType = LikeButtonDialogType(rawValue: likeButtonDialogTypeNumber.intValue) {
                    globalState.likeButtonDialogType = likeButtonDialogType.rawValue
                }
                if let preferredSiteInfoURLList = dic.object(forKey: "preferredSiteInfoURLList") as? NSArray {
                    StoryHtmlDecoder.shared.ClearSiteInfo()
                    globalState.preferredSiteInfoURLList.removeAll()
                    for target in preferredSiteInfoURLList {
                        if let target = target as? String {
                            globalState.preferredSiteInfoURLList.append(target)
                        }
                    }
                }
                realm.add(globalState, update: .modified)
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
            let progressString = NSLocalizedString("NovelSpeakerUtility_RestoreingNovelData", comment: "工程 3/3\n小説を抽出中") + " (\(novelCount)/\(novelArrayCount))"
            progressUpdate(progressString)
            guard let novelDic = novelDic as? NSDictionary,
                let novelID = novelDic.object(forKey: "novelID") as? String,
                let type = novelDic.object(forKey: "type") as? NSNumber else { continue }
            RealmUtil.Write { (realm) in
                let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) ?? RealmNovel()
                if novel.novelID != novelID {
                    novel.novelID = novelID
                }
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
                if let createdDateString = novelDic.object(forKey: "createdDate") as? String, let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
                    novel.createdDate = createdDate
                }
                if let isNeedSpeechAfterDelete = novelDic.object(forKey: "isNeedSpeechAfterDelete") as? NSNumber {
                    novel.isNeedSpeechAfterDelete = isNeedSpeechAfterDelete.boolValue
                }
                if let defaultSpeakerID = novelDic.object(forKey: "defaultSpeakerID") as? String {
                    novel.defaultSpeakerID = defaultSpeakerID
                }
                if let isNotNeedUpdateCheck = novelDic.object(forKey: "isNotNeedUpdateCheck") as? Bool {
                    novel.isNotNeedUpdateCheck = isNotNeedUpdateCheck
                }
                if let lastChapterStoryID = novelDic.object(forKey: "lastChapterStoryID") as? String {
                    novel.m_lastChapterStoryID = lastChapterStoryID
                }
                if let lastDownloadDateString = novelDic.object(forKey: "lastDownloadDate") as? String, let lastDownloadDate = NiftyUtility.ISO8601String2Date(iso8601String: lastDownloadDateString) {
                    novel.lastDownloadDate = lastDownloadDate
                }
                if let readingChapterStoryID = novelDic.object(forKey: "readingChapterStoryID") as? String {
                    novel.m_readingChapterStoryID = readingChapterStoryID
                }
                if let lastReadDateString = novelDic.object(forKey: "lastReadDate") as? String, let lastReadDate = NiftyUtility.ISO8601String2Date(iso8601String: lastReadDateString) {
                    novel.lastReadDate = lastReadDate
                }
                if let downloadDateArray = novelDic.object(forKey: "downloadDateArray") as? NSArray {
                    novel.downloadDateArray.removeAll()
                    for downloadDateStringObj in downloadDateArray {
                        if let downloadDateString = downloadDateStringObj as? String, let downloadDate = NiftyUtility.ISO8601String2Date(iso8601String: downloadDateString) {
                            novel.AppendDownloadDate(realm: realm, date: downloadDate)
                        }
                    }
                }
                if let readingChapterReadingPoint = novelDic.object(forKey: "readingChapterReadingPoint") as? NSNumber {
                    novel.m_readingChapterReadingPoint = readingChapterReadingPoint.intValue
                }
                if let readingChapterContentCount = novelDic.object(forKey: "readingChapterContentCount") as? NSNumber {
                    novel.m_readingChapterContentCount = readingChapterContentCount.intValue
                }
                var hasInvalidData = false
                if let storys = novelDic.object(forKey: "storys") as? NSArray {
                    RealmUtil.Write { (realm) in
                        var storyArray:[Story] = []
                        var index = 0
                        for storyDic in storys {
                            index += 1
                            //progressUpdate(progressString + " (\(index)/\(max))")
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
                            guard let content = NiftyUtility.stringDecompress(data: data) else { continue }
                            var story = Story()
                            story.novelID = novelID
                            story.chapterNumber = chapterNumber.intValue
                            story.content = content.replacingOccurrences(of: "\u{00}", with: "")
                            if let url = storyDic.object(forKey: "url") as? String {
                                story.url = url
                            }
                            if let subtitle = storyDic.object(forKey: "subtitle") as? String {
                                story.subtitle = subtitle
                            }
                            if let downloadDateString = storyDic.object(forKey: "downloadDate") as? String, let downloadDate = NiftyUtility.ISO8601String2Date(iso8601String: downloadDateString) {
                                story.downloadDate = downloadDate
                            }
                            storyArray.append(story)
                            if storyArray.count >= RealmStoryBulk.bulkCount {
                                RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                                storyArray.removeAll()
                            }
                        }
                        if storyArray.count > 0 {
                            RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                            storyArray.removeAll()
                        }
                    }
                }
                // 既に登録されているChapterNumberの方が大きい場合は m_lastChapterNumber をそちらの値で上書きしておきます。
                if let lastChapterNumber = RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: novelID).flatMap({$0}).sorted().last {
                    if RealmStoryBulk.StoryIDToChapterNumber(storyID: novel.m_lastChapterStoryID) < lastChapterNumber {
                        novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: lastChapterNumber)
                    }
                }
                if hasInvalidData {
                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                }
                realm.add(novel, update: .modified)
            }
        }
    }
    
    static func RestoreNovel_V_2_1_0(bookshelf:NSArray, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) {
        NovelDownloadQueue.shared.downloadStop()
        defer { NovelDownloadQueue.shared.downloadStart() }
        let novelArrayCount = bookshelf.count
        var novelCount = 0
        for novelDic in bookshelf {
            novelCount += 1
            let progressString = NSLocalizedString("NovelSpeakerUtility_RestoreingNovelData", comment: "工程 3/3\n小説を抽出中") + " (\(novelCount)/\(novelArrayCount))"
            progressUpdate(progressString)
            guard let novelDic = novelDic as? NSDictionary,
                let novelID = novelDic.object(forKey: "novelID") as? String,
                let type = novelDic.object(forKey: "type") as? NSNumber else { continue }
            RealmUtil.Write { (realm) in
                let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) ?? RealmNovel()
                if novel.novelID != novelID {
                    novel.novelID = novelID
                }
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
                if let createdDateString = novelDic.object(forKey: "createdDate") as? String, let createdDate = NiftyUtility.ISO8601String2Date(iso8601String: createdDateString) {
                    novel.createdDate = createdDate
                }
                if let isNeedSpeechAfterDelete = novelDic.object(forKey: "isNeedSpeechAfterDelete") as? NSNumber {
                    novel.isNeedSpeechAfterDelete = isNeedSpeechAfterDelete.boolValue
                }
                if let defaultSpeakerID = novelDic.object(forKey: "defaultSpeakerID") as? String {
                    novel.defaultSpeakerID = defaultSpeakerID
                }
                if let isNotNeedUpdateCheck = novelDic.object(forKey: "isNotNeedUpdateCheck") as? Bool {
                    novel.isNotNeedUpdateCheck = isNotNeedUpdateCheck
                }
                if let lastChapterStoryID = novelDic.object(forKey: "lastChapterStoryID") as? String {
                    novel.m_lastChapterStoryID = lastChapterStoryID
                }
                if let lastDownloadDateString = novelDic.object(forKey: "lastDownloadDate") as? String, let lastDownloadDate = NiftyUtility.ISO8601String2Date(iso8601String: lastDownloadDateString) {
                    novel.lastDownloadDate = lastDownloadDate
                }
                if let readingChapterStoryID = novelDic.object(forKey: "readingChapterStoryID") as? String {
                    novel.m_readingChapterStoryID = readingChapterStoryID
                }
                if let lastReadDateString = novelDic.object(forKey: "lastReadDate") as? String, let lastReadDate = NiftyUtility.ISO8601String2Date(iso8601String: lastReadDateString) {
                    novel.lastReadDate = lastReadDate
                }
                if let downloadDateArray = novelDic.object(forKey: "downloadDateArray") as? NSArray {
                    novel.downloadDateArray.removeAll()
                    for downloadDateStringObj in downloadDateArray {
                        if let downloadDateString = downloadDateStringObj as? String, let downloadDate = NiftyUtility.ISO8601String2Date(iso8601String: downloadDateString) {
                            novel.AppendDownloadDate(realm: realm, date: downloadDate)
                        }
                    }
                }
                if let readingChapterReadingPoint = novelDic.object(forKey: "readingChapterReadingPoint") as? NSNumber {
                    novel.m_readingChapterReadingPoint = readingChapterReadingPoint.intValue
                }
                if let readingChapterContentCount = novelDic.object(forKey: "readingChapterContentCount") as? NSNumber {
                    novel.m_readingChapterContentCount = readingChapterContentCount.intValue
                }
                var hasInvalidData = false
                if let storys = novelDic.object(forKey: "storys") as? NSArray {
                    RealmUtil.Write { (realm) in
                        for storyDic in storys {
                            guard let storyDic = storyDic as? NSDictionary,
                                  let id = storyDic.object(forKey: "id") as? String,
                                  let chapterNumber = storyDic.object(forKey: "chapterNumber") as? NSNumber,
                                  let contentDirectoryString = novelDic.object(forKey: "contentDirectory") as? String,
                                  let extractedDirectory = extractedDirectory
                            else { continue }
                            let contentDirectory = extractedDirectory.appendingPathComponent(contentDirectoryString, isDirectory: true)
                            let contentFilePath = contentDirectory.appendingPathComponent("\(chapterNumber.intValue)")
                            guard let storyListAssetBinary = try? Data(contentsOf: contentFilePath) else {
                                hasInvalidData = true
                                continue
                            }
                            if let storyArray = RealmStoryBulk.StoryZipedAssetToStoryArray(zipedData: storyListAssetBinary) {
                                RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: storyArray)
                            }
                        }
                    }
                }
                // 既に登録されているChapterNumberの方が大きい場合は m_lastChapterNumber をそちらの値で上書きしておきます。
                if let lastChapterNumber = RealmStoryBulk.GetAllChapterNumberFor(realm: realm, novelID: novelID).flatMap({$0}).sorted().last {
                    if RealmStoryBulk.StoryIDToChapterNumber(storyID: novel.m_lastChapterStoryID) < lastChapterNumber {
                        novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: lastChapterNumber)
                    }
                }
                if hasInvalidData {
                    NovelDownloadQueue.shared.addQueue(novelID: novelID)
                }
                realm.add(novel, update: .modified)
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
        // misc_settings には defaultDisplaySettingID,defaultSpeakerID が入っているので
        // 先に取り出しておかないと良くないことがおきます(´・ω・`)
        if let globalStateDic = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            if let defaultSpeakerID = globalStateDic.object(forKey: "defaultSpeakerID") as? String, let speaker_setting = toplevelDictionary.object(forKey: "speaker_setting") as? NSArray {
                RestoreSpeakerSettings_V_2_0_0(speakerArray:speaker_setting, defaultSpeakerSettingID:defaultSpeakerID, progressUpdate: progressUpdate)
            }
            if let defaultDisplaySettingID = globalStateDic.object(forKey: "defaultDisplaySettingID") as? String, let display_setting = toplevelDictionary.object(forKey: "display_setting") as? NSArray {
                RestoreDisplaySettings_V_2_0_0(displaySettingArray:display_setting, defaultSpeakerSettingID:defaultDisplaySettingID, progressUpdate: progressUpdate)
            }
            
            RestoreGlobalState_V_2_0_0(dic:globalStateDic, progressUpdate: progressUpdate)
        }
        if let bookshelf = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            RestoreNovel_V_2_0_0(bookshelf:bookshelf, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
        }
        return true
    }

    static func ProcessNovelSpeakerBackupJSONData_V_2_1_0(toplevelDictionary:NSDictionary, progressUpdate:@escaping(String)->Void, extractedDirectory:URL?) -> Bool {
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
        // misc_settings には defaultDisplaySettingID,defaultSpeakerID が入っているので
        // 先に取り出しておかないと良くないことがおきます(´・ω・`)
        if let globalStateDic = toplevelDictionary.object(forKey: "misc_settings") as? NSDictionary {
            if let defaultSpeakerID = globalStateDic.object(forKey: "defaultSpeakerID") as? String, let speaker_setting = toplevelDictionary.object(forKey: "speaker_setting") as? NSArray {
                RestoreSpeakerSettings_V_2_0_0(speakerArray:speaker_setting, defaultSpeakerSettingID:defaultSpeakerID, progressUpdate: progressUpdate)
            }
            if let defaultDisplaySettingID = globalStateDic.object(forKey: "defaultDisplaySettingID") as? String, let display_setting = toplevelDictionary.object(forKey: "display_setting") as? NSArray {
                RestoreDisplaySettings_V_2_0_0(displaySettingArray:display_setting, defaultSpeakerSettingID:defaultDisplaySettingID, progressUpdate: progressUpdate)
            }
            
            RestoreGlobalState_V_2_0_0(dic:globalStateDic, progressUpdate: progressUpdate)
        }
        if let bookshelf = toplevelDictionary.object(forKey: "bookshelf") as? NSArray {
            RestoreNovel_V_2_1_0(bookshelf:bookshelf, progressUpdate:progressUpdate, extractedDirectory:extractedDirectory)
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
        }else if dataVersion == "2.1.0" {
            return ProcessNovelSpeakerBackupJSONData_V_2_1_0(toplevelDictionary: jsonObj, progressUpdate: progressUpdate, extractedDirectory: extractedDirectory)
        }else{
            return false
        }
    }
    @discardableResult
    static func ProcessNovelSpeakerBackupFile_ZIPType(url:URL, progressUpdate:@escaping (String)->Void) -> Bool {
        let temporaryDirectoryName = backupDirectoryName
        if let temporaryDirectory = NiftyUtility.CreateTemporaryDirectory(directoryName: temporaryDirectoryName) {
            do {
                try FileManager.default.removeItem(at: temporaryDirectory)
            }catch{
                // nothing to do.
            }
        }
        guard let temporaryDirectory = NiftyUtility.CreateTemporaryDirectory(directoryName: temporaryDirectoryName) else { return false }
        let unzipResult = SSZipArchive.unzipFile(atPath: url.path, toDestination: temporaryDirectory.path, overwrite: true, password: nil) { (fileName, fileInfo, progressCurrent, progressAllCount) in
            var progressFloat = Float(progressCurrent) / Float(progressAllCount)
            if progressFloat.isInfinite || progressFloat.isNaN {
                progressFloat = 1.0
            }
            let warningMessage:String
            if progressAllCount >= 65535 {
                warningMessage = NSLocalizedString("NovelSpeakerBackup_ProgressExtractingZip_WarningInvalidPercentage", comment: "\n展開中のバックアップファイル中のファイル数が多いため、進捗(%表示)が不正な値を指すことがあります")
            }else{
                warningMessage = ""
            }
            progressUpdate(NSLocalizedString("NovelSpeakerUtility_UnzipProgress", comment: "バックアップファイルを解凍しています") + " (\(Int(progressFloat * 100))%)\(warningMessage)")
        } completionHandler: { (text, result, err) in
            // nothing to do.
        }
        defer {
            do {
                try FileManager.default.removeItem(at: temporaryDirectory)
            }catch{
                // nothing to do
            }
        }
        if unzipResult == false { return false }
        return ProcessNovelSpeakerBackupFile_JSONType(url: temporaryDirectory.appendingPathComponent("backup_data.json"), progressUpdate: progressUpdate, extractedDirectory: temporaryDirectory)
    }

    static func ProcessNovelSpeakerBackupFile(url:URL) -> Bool {
        guard let viewController = NiftyUtility.GetToplevelViewController(controller: nil) else { return false }
        var builder = NiftyUtility.EasyDialogBuilder(viewController)
        let titleTag = 100
        let messageTag = 101
        builder = builder.label(text: NSLocalizedString("NovelSpeakerUtility_RestoreBackupTitle", comment: "バックアップデータを読み込んでいます"), textAlignment: .center, tag: titleTag)
        builder = builder.label(text: NSLocalizedString("NovelSpeakerUtility_RestoreBackupMessage", comment: "-"), textAlignment: .center, tag: messageTag)
        let dialog = builder.build()
        DispatchQueue.main.async {
            dialog.show {
                var prevMessageLabelText = ""
                var displayMessageDate = Date(timeIntervalSinceNow: -1.0)
                func applyProgress(text:String) {
                    if prevMessageLabelText == text || displayMessageDate > Date() { return }
                    DispatchQueue.main.async {
                        guard let messageLabel = dialog.view.viewWithTag(messageTag) as? UILabel else { return }
                        messageLabel.text = text
                        prevMessageLabelText = text
                        displayMessageDate = Date(timeIntervalSinceNow: 0.5)
                    }
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                        NovelSpeakerNotificationTool.AnnounceGlobalStateChanged()
                    }
                    let isSecureUrl = url.startAccessingSecurityScopedResource()
                    defer { if isSecureUrl { url.stopAccessingSecurityScopedResource() } }
                    if url.pathExtension == "novelspeaker-backup+zip" {
                        ProcessNovelSpeakerBackupFile_ZIPType(url: url, progressUpdate: applyProgress(text:))
                        return
                    }else{
                        ProcessNovelSpeakerBackupFile_JSONType(url: url, progressUpdate: applyProgress(text:), extractedDirectory: nil)
                    }
                }
            }
        }
        return true
    }
    #endif

    // MARK: バックアップデータ生成
    #if !os(watchOS)
    fileprivate static func CreateBackupDataDictionary_Story(novelID:String, contentWriteTo:URL, progressString:String, progress:((_ description:String)->Void)?) -> [[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            var result:[[String:Any]] = []
            let storyBulkArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: novelID)
            if let storyBulkArray = storyBulkArray {
                for storyBulk in storyBulkArray {
                    if storyBulk.isDeleted { continue }
                    guard let storyListAssetBinary = storyBulk.LoadCreamAssetBinary() else { continue }
                    do {
                        let filePath = contentWriteTo.appendingPathComponent("\(storyBulk.chapterNumber)")
                        try storyListAssetBinary.write(to: filePath)
                    }catch{
                        print("\(novelID) chapter: \(storyBulk.chapterNumber) content write failed.")
                    }
                    let storyBulkData:[String:Any] = [
                        "id": storyBulk.id,
                        "chapterNumber": storyBulk.chapterNumber,
                    ]
                    result.append(storyBulkData)
                }
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_Bookshelf(forNovelIDArray:[String], forStorySaveNovelIDArray:[String], contentWriteTo:URL, progress:((_ description:String)->Void)?) -> ([[String:Any]], [URL]) {
        let targetNovelIDArray = Array(Set(forNovelIDArray).union(Set(forStorySaveNovelIDArray)))
        var result:[[String:Any]] = []
        var fileArray:[URL] = []
        return RealmUtil.RealmBlock { (realm) -> ([[String:Any]], [URL]) in
            guard let novelArrayTmp = RealmNovel.GetAllObjectsWith(realm: realm) else { return (result, []) }
            let novelArray:Array<RealmNovel>
            if targetNovelIDArray.count > 0 {
                novelArray = novelArrayTmp.filter({targetNovelIDArray.contains($0.novelID)})
            }else{
                novelArray = Array(novelArrayTmp)
            }
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
                    "createdDate": NiftyUtility.Date2ISO8601String(date: novel.createdDate),
                    "isNeedSpeechAfterDelete": novel.isNeedSpeechAfterDelete,
                    "defaultSpeakerID": novel.defaultSpeakerID,
                    "isNotNeedUpdateCheck": novel.isNotNeedUpdateCheck,
                    "lastChapterStoryID": novel.m_lastChapterStoryID,
                    "lastDownloadDate": NiftyUtility.Date2ISO8601String(date: novel.lastDownloadDate),
                    "readingChapterStoryID": novel.m_readingChapterStoryID,
                    "lastReadDate": NiftyUtility.Date2ISO8601String(date: novel.lastReadDate),
                    "downloadDateArray": Array(novel.downloadDateArray.map({ (date) -> String in
                        NiftyUtility.Date2ISO8601String(date: date)
                    })),
                    "readingChapterReadingPoint": novel.m_readingChapterReadingPoint,
                    "readingChapterContentCount": novel.m_readingChapterContentCount,
                ]
                if !forStorySaveNovelIDArray.contains(novel.novelID) && novel.m_type != NovelType.UserCreated.rawValue {
                    result.append(novelData)
                    continue
                }
                guard let contentDirectory:URL = NiftyUtility.CreateDirectoryFor(path: contentWriteTo, directoryName: "\(novelCount)") else {
                    continue
                }
                novelData["contentDirectory"] = "\(novelCount)"
                novelData["storys"] = CreateBackupDataDictionary_Story(novelID: novel.novelID, contentWriteTo: contentDirectory, progressString: progressString, progress: progress)
                fileArray.append(contentDirectory)
                result.append(novelData)
                novelCount += 1
            }
            return (result, fileArray)
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechModSetting() -> [String:[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [String:[String:Any]] in
            var result:[String:[String:Any]] = [:]
            guard let targetArray = RealmSpeechModSetting.GetAllObjectsWith(realm: realm) else { return result }
            for setting in targetArray {
                result[setting.before] = [
                    "afterString": setting.after,
                    "createdDate": NiftyUtility.Date2ISO8601String(date: setting.createdDate),
                    "isUseRegularExpression": setting.isUseRegularExpression,
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ]
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechWaitConfig() -> [[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeechWaitConfig.GetAllObjectsWith(realm: realm) else { return result }
            for setting in targetArray {
                result.append([
                    "targetText": setting.targetText,
                    "delayTimeInSec": setting.delayTimeInSec,
                    "createdDate": NiftyUtility.Date2ISO8601String(date: setting.createdDate)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeakerSetting() -> [[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeakerSetting.GetAllObjectsWith(realm: realm) else { return result }
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
                    "createdDate": NiftyUtility.Date2ISO8601String(date: setting.createdDate)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_SpeechSectionConfig() -> [[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            var result:[[String:Any]] = []
            guard let targetArray = RealmSpeechSectionConfig.GetAllObjectsWith(realm: realm) else { return result }
            for setting in targetArray {
                result.append([
                    "name": setting.name,
                    "startText": setting.startText,
                    "endText": setting.endText,
                    "createdDate": NiftyUtility.Date2ISO8601String(date: setting.createdDate),
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
        return RealmUtil.RealmBlock { (realm) -> [String:Any] in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return [:] }
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
                "isForceSiteInfoReloadIsEnabled": RealmGlobalState.GetIsForceSiteInfoReloadIsEnabled(),
                "isMenuItemIsAddSpeechModSettingOnly": globalState.isMenuItemIsAddNovelSpeakerItemsOnly,
                //"isBackgroundNovelFetchEnabled": globalState.isBackgroundNovelFetchEnabled,
                "isPageTurningSoundEnabled": globalState.isPageTurningSoundEnabled,
                "bookSelfSortType": globalState.m_bookSelfSortType,
                "currentReadingNovelID": globalState.currentReadingNovelID,
                "currentWebSearchSite": globalState.currentWebSearchSite,
                "autoSplitStringList": Array(globalState.autoSplitStringList),
                "novelSpeakerSiteInfoURL": globalState.novelSpeakerSiteInfoURL,
                "autopagerizeSiteInfoURL": globalState.autopagerizeSiteInfoURL,
                "defaultSpeechModURL": globalState.defaultSpeechModURL,
                "searchInfoURL": globalState.searchInfoURL,
                "speechViewButtonSettingArrayData": globalState.speechViewButtonSettingArrayData.base64EncodedString(),
                //"cookieArrayData": globalState.cookieArrayData.base64EncodedString(),
                "novelDisplayType": globalState.novelDisplayType.rawValue,
                "bookshelfViewButtonSettingArrayData": globalState.bookshelfViewButtonSettingArrayData.base64EncodedString(),

                "defaultDisplaySettingID": globalState.defaultDisplaySettingID,
                "defaultSpeakerID": globalState.defaultSpeakerID,
                "repeatSpeechType": globalState.m_repeatSpeechType,
                "repeatSpeechLoopType": globalState.m_repeatSpeechLoopType,
                "isAnnounceAtRepatSpeechTime": globalState.isAnnounceAtRepatSpeechTime,
                "isOverrideRubyIsEnabled": globalState.isOverrideRubyIsEnabled,
                "notRubyCharactorStringArray": globalState.notRubyCharactorStringArray,
                "isIgnoreURIStringSpeechEnabled": globalState.isIgnoreURIStringSpeechEnabled,
                "isEnableSwipeOnStoryView": globalState.isEnableSwipeOnStoryView,
                "isDisableNarouRuby": globalState.isDisableNarouRuby,
                "isNeedDisableIdleTimerWhenSpeechTime": globalState.isNeedDisableIdleTimerWhenSpeechTime,
                "supportRotationMask": NovelSpeakerUtility.supportRotationMask.rawValue,
                "novelLikeOrder": Array(globalState.novelLikeOrder),
                "menuItemsNotRemoved": Array(globalState.menuItemsNotRemoved),
                "likeButtonDialogType": globalState.likeButtonDialogType,
                "preferredSiteInfoURLList": Array(globalState.preferredSiteInfoURLList),
                "isDeleteBlockOnBookshelfTreeView": globalState.isDeleteBlockOnBookshelfTreeView,
            ]
        }
    }
    fileprivate static func CreateBackupDataDictionary_DisplaySetting() -> [[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            var result:[[String:Any]] = []
            guard let targetArray = RealmDisplaySetting.GetAllObjectsWith(realm: realm) else { return result }
            for setting in targetArray {
                result.append([
                    "textSizeValue": setting.textSizeValue,
                    "lineSpacing": setting.lineSpacing,
                    "fontID": setting.fontID,
                    "name": setting.name,
                    "viewType": setting.viewType.rawValue,
                    "createdDate": NiftyUtility.Date2ISO8601String(date: setting.createdDate),
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_NovelTag() -> [[String:Any]] {
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            var result:[[String:Any]] = []
            guard let targetArray = RealmNovelTag.GetAllObjectsWith(realm: realm) else { return result }
            for setting in targetArray {
                result.append([
                    "name": setting.name,
                    "type": setting.type,
                    "hint": setting.hint,
                    "createdDate": NiftyUtility.Date2ISO8601String(date: setting.createdDate),
                    "targetNovelIDArray": Array(setting.targetNovelIDArray)
                ])
            }
            return result
        }
    }
    fileprivate static func CreateBackupDataDictionary_Bookmark() -> [[String:Any]] {
        var result:[[String:Any]] = []
        return RealmUtil.RealmBlock { (realm) -> [[String:Any]] in
            guard let targetArray = RealmBookmark.GetAllObjectsWith(realm: realm) else { return result }
            for bookmark in targetArray {
                result.append([
                    "id": bookmark.id,
                    "createdDate": NiftyUtility.Date2ISO8601String(date: bookmark.createdDate),
                    "novelID": bookmark.novelID,
                    "chapterNumber": bookmark.chapterNumber,
                    "location": bookmark.location,
                ])
            }
            return result
        }
    }
    
    static func CreateBackupData(withAllStoryContent:Bool, progress:((_ description:String)->Void)?) -> URL? {
        if withAllStoryContent {
            let result = RealmUtil.RealmBlock { (realm) -> URL? in
                if let novelArray = RealmNovel.GetAllObjectsWith(realm: realm) {
                    let novelIDArray = Array(novelArray.map({$0.novelID}))
                    return CreateBackupData(forNovelIDArray: novelIDArray, forStorySaveNovelIDArray: novelIDArray, progress: progress)
                }
                return nil
            }
            if let result = result {
                return result
            }
        }
        return CreateBackupData(forNovelIDArray: [], forStorySaveNovelIDArray: [], progress: progress)
    }
    
    static let backupDirectoryName = "NovelSpeakerBackup"
    @objc static func CleanBackupFolder() {
        let tmpDir = NSTemporaryDirectory()
        let temporaryDirectoryPath = URL(fileURLWithPath: tmpDir).appendingPathComponent(backupDirectoryName, isDirectory: true)
        do {
            let fileManager = FileManager.default
            let files = try fileManager.contentsOfDirectory(atPath: tmpDir)
            for file in files.filter({ $0.contains(".novelspeaker-backup") }) {
                let backupFile = URL(fileURLWithPath: tmpDir).appendingPathComponent(file, isDirectory: false)
                try fileManager.removeItem(at: backupFile)
            }
        } catch {
            // nothing to do
        }
        NiftyUtility.RemoveDirectory(directoryPath: temporaryDirectoryPath)
    }

    static func CreateBackupData(forNovelIDArray:[String], forStorySaveNovelIDArray: [String], isOnlyNovelData:Bool = false, fileNamePrefix:String = "", progress:((_ description:String)->Void)?) -> URL? {
        NovelDownloadQueue.shared.downloadStop()
        let directoryName = backupDirectoryName
        CleanBackupFolder()
        // 改めてディレクトリを作り直します。
        guard let outputPath = NiftyUtility.CreateTemporaryDirectory(directoryName: directoryName) else {
            return nil
        }
        let bookshelfResult = CreateBackupDataDictionary_Bookshelf(forNovelIDArray: forNovelIDArray, forStorySaveNovelIDArray: forStorySaveNovelIDArray, contentWriteTo: outputPath, progress: progress)
        defer { NiftyUtility.RemoveDirectory(directoryPath: outputPath) }
        if isOnlyNovelData && forNovelIDArray.count > 0 && bookshelfResult.0.count <= 0 {
            // forNovelIDArray が 0以上 で bookshelfResult に内容が無いようであるなら、それは失敗している(恐らくは指定されたNovelIDの小説が全て存在しなかった)
            return nil
        }
        progress?(NSLocalizedString("NovelSpeakerUtility_ExportOtherSettings", comment: "設定情報の抽出中"))
        let jsonDictionary:[String:Any]
        if isOnlyNovelData {
            jsonDictionary = [
                "data_version": "2.1.0",
                "bookshelf": bookshelfResult.0,
            ]
        }else{
            jsonDictionary = [
                "data_version": "2.1.0",
                "bookshelf": bookshelfResult.0,
                "word_replacement_dictionary": CreateBackupDataDictionary_SpeechModSetting(),
                "speech_wait_config": CreateBackupDataDictionary_SpeechWaitConfig(),
                "speaker_setting": CreateBackupDataDictionary_SpeakerSetting(),
                "speech_section_config": CreateBackupDataDictionary_SpeechSectionConfig(),
                "misc_settings": CreateBackupDataDictionary_GlobalState(),
                "display_setting": CreateBackupDataDictionary_DisplaySetting(),
                "novel_tag": CreateBackupDataDictionary_NovelTag(),
                "bookmark": CreateBackupDataDictionary_Bookmark(),
            ]
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "yyyyMMddHHmm"
        let dateString = dateFormatter.string(from: Date())
        var ziptargetFiles:[URL] = bookshelfResult.1
        let backupDataFilePath:URL = outputPath.appendingPathComponent("backup_data.json")
        ziptargetFiles.append(backupDataFilePath)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDictionary, options: [.prettyPrinted])
            try jsonData.write(to: backupDataFilePath)
        }catch{
            print("JSONSerizization.data() failed. or jsonData.write() failed.")
            return nil
        }
        progress?(NSLocalizedString("NovelSpeakerBackup_CompressingBackupData", comment: "圧縮準備中"))
        let zipFilePath = NiftyUtility.GetTemporaryFilePath(fileName: NiftyUtility.Date2ISO8601String(date: Date()) + ".zip")
        let zipResult = SSZipArchive.createZipFile(atPath: zipFilePath.path, withContentsOfDirectory: outputPath.path, keepParentDirectory: false, compressionLevel: 9, password: nil, aes: false) { (progressCount, progressAllCount) in
            var progressFloat = Float(progressCount) / Float(progressAllCount)
            if progressFloat.isNaN || progressFloat.isInfinite {
                progressFloat = 1.0
            }
            let description = NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中") + " (\(Int(progressFloat * 100))%)"
            progress?(description)
        }
        if zipResult == false {
            print("zip file create error", zipFilePath.absoluteString)
            return nil
        }
        let backupFilePath = NiftyUtility.GetTemporaryFilePath(fileName: String.init(format: "%@%@.novelspeaker-backup+zip", fileNamePrefix, dateString))
        do {
            try FileManager.default.moveItem(at: zipFilePath, to: backupFilePath)
        }catch let err{
            print("zip file move error", zipFilePath.absoluteString, " to" , backupFilePath.absoluteString, err)
            return nil
        }
        return backupFilePath
    }
    
    static func CreateShareFileFromData(fileName:String, data:Data) -> URL? {
        let directoryName = backupDirectoryName
        CleanBackupFolder()
        // 改めてディレクトリを作り直します。
        guard let outputPath = NiftyUtility.CreateTemporaryDirectory(directoryName: directoryName) else {
            return nil
        }
        defer { NiftyUtility.RemoveDirectory(directoryPath: outputPath) }
        let filePath = NiftyUtility.GetTemporaryFilePath(fileName: fileName)
        do {
            try data.write(to: filePath)
        }catch{
            print("CreateShareFileFromData data.write() failed.")
            return nil
        }
        return filePath
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

    /*
     iOSが再起動した後、パスコードでロックを解除する前にアプリが起動した場合、
     RealmのデータやUserDefaultsに保存されている値が読み込めなくなるようです。
     この場合、例えば、iCloudを使う(true)と設定されているはずなものが、iCloudは使わない(false)と設定されているかのように読み出されてしまう
     (UserDefaultsの初期値としてfalseを入れてから値を参照しているため、初期値が返っているぽい)事が発生します。
     こうなると色々と誤作動が起こるため、事前にこのような問題が発生するか否かを確認する必要があります。
     今(2023年11月25日)確認したところだと、ファイルの存在は確認できるが、UserDefaultsの値は読めないということらしいので、
     local用のRealmファイルとiCloud用のRealmファイルのそれぞれの存在確認をした上で、
     isUseCloud の値と照合して iCloud を使う設定になっていないとおかしいのに〜という部分を確認します。
     */
    @discardableResult
    @objc static func CheckRealmReadable() -> Bool {
        #if !os(watchOS)
        // まず UIApplication.shared.isProtectedDataAvailable が true を返すならロックされてないのでOKとします
        let isProtectedDataAvailable:Bool
        if Thread.isMainThread {
            isProtectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
        }else{
            isProtectedDataAvailable = DispatchQueue.main.sync {
                return UIApplication.shared.isProtectedDataAvailable
            }
        }
        if isProtectedDataAvailable == true {
            return true
        }
        #endif

        // ロックされているようなのでファイルの存在とUserDefaultsの設定の差異を確認する
        let localExists = RealmUtil.CheckIsLocalRealmCreated()
        let cloudExists = RealmUtil.CheckIsCloudRealmCreated()
        let isUseCloud = RealmUtil.IsUseCloudRealm()
        if isUseCloud {
            // IsUseCloudRealm で確認している値の初期値は false のため、ここで true が読めているのであれば正しい値が読めているので良しとします。
            return true
        }
        // iCloud は使わないのに cloud があるのはなにかおかしいです。
        if cloudExists == true {
            return false
        }
        // iCloud は使わないのに local が無いのもなにかおかしいです。
        if localExists == false {
            return false
        }
        return true
    }

    #if !os(watchOS)
    static let LongLivedOperationIDWatcherID = "AllLongLivedOperationIDWatcher"
    static func GetLongLivedOperationIDWatcherID() -> String {
        return LongLivedOperationIDWatcherID
    }
    
    @objc static func StartAllLongLivedOperationIDWatcher() {
        let activityIndicatorID = LongLivedOperationIDWatcherID
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
    
    static func CheckAndRecoverStoryCountWith(realm:Realm, novel:RealmNovel) {
        let (storyCount, lastStoryChapterNumber, _) = RealmStoryBulk.CountStoryFor(realm: realm, novelID: novel.novelID)
        let lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: storyCount)
        if novel.m_lastChapterStoryID != lastChapterStoryID && RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: lastStoryChapterNumber) == lastChapterStoryID {
            RealmUtil.WriteWith(realm: realm) { (realm) in
                novel.m_lastChapterStoryID = lastChapterStoryID
            }
        }
    }
    
    static func CheckAndRecoverStoryCountWith(realm:Realm, novelID:String) {
        guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
        CheckAndRecoverStoryCountWith(realm: realm, novel: novel)
    }
    
    static func CheckAndRecoverStoryCount(novelID:String) {
        // これ、いろんな所から呼ばれる(NovelDownloadQueue.addQueue() から呼ばれる)
        // のにもかかわらず RealmUtil.Write を呼び出すので別threadから呼ぶ事にします。(´・ω・`)
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) in
                CheckAndRecoverStoryCountWith(realm: realm, novelID: novelID)
            }
        }
    }
    
    // 指定された NSHTTPCookieStorage に入っている変なkeyになっている cookie項目 を削除します
    // 変なkey: 行頭に空白が入っているもの
    // 補足: この 変なkey があると、同じkeyが延々と追加されていってしまいには cookie header がでかくなりすぎて 400 を返すことになる(と思う)
    @objc static func RemoveInvalidKeyDataFromCookieStorage(storage:HTTPCookieStorage) {
        var deleteTargets:[HTTPCookie] = []
        if let cookies = storage.cookies {
            for cookie in cookies {
                let key = cookie.name
                let validKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                if key != validKey {
                    deleteTargets.append(cookie)
                }
            }
        }
        for cookie in deleteTargets {
            storage.deleteCookie(cookie)
        }
    }
    
    static let isAddedFirstStoryKey = "NovelSpeaker_NovelSpeakerUtility_IsAddedFirstStory"
    static func GetIsAddedFirstStory() -> Bool {
        let userDefaults = UserDefaults.standard
        userDefaults.register(defaults: [NovelSpeakerUtility.isAddedFirstStoryKey : false])
        return userDefaults.bool(forKey: NovelSpeakerUtility.isAddedFirstStoryKey)
    }
    static func SetIsIsAddedFirstStory(newValue:Bool) {
        let userDefaults = UserDefaults.standard
        userDefaults.set(newValue, forKey: NovelSpeakerUtility.isAddedFirstStoryKey)
    }
    fileprivate static let FirstStoryURLString = NSLocalizedString("NovelSpeakerUtility_FirstStoryURLString", comment: "https://limura.github.io/NovelSpeaker/topics/jp/00001.html")
    @objc static func AddFirstStoryIfNeeded() {
        if GetIsAddedFirstStory() { return }
        let novelID = FirstStoryURLString
        RealmUtil.Write { (realm) in
            let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) ?? RealmNovel()
            if novel.novelID != novelID {
                novel.novelID = novelID
                novel.url = novelID
                novel.title = NSLocalizedString("NovelSpeakerUtility_FirstStoryTitleString", comment: "はじめに(ことせかい の使い方)")
                novel.type = .URL
                realm.add(novel, update: .modified)
            }
        }
        NovelDownloadQueue.shared.addQueue(novelID: novelID)
        SetIsIsAddedFirstStory(newValue: true)
    }
    
    #if !os(watchOS)
    static func CreateNovelOnlyBackup(novelIDArray:[String], viewController:UIViewController, successAction:((_ filePath:URL, _ fileName: String)->Void)? = nil) {
        let labelTag = 100
        DispatchQueue.main.async {
            let dialog = NiftyUtility.EasyDialogBuilder(viewController)
                .label(text: NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……"), textAlignment: NSTextAlignment.center, tag: labelTag)
                .build()
            dialog.show {
                let fileNamePrefix:String
                if novelIDArray.count == 1, let novelID = novelIDArray.first, let title = RealmUtil.RealmBlock(block: { (realm) -> String? in
                        return RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.title
                }), title.count > 0 {
                    fileNamePrefix = title + "_"
                }else{
                    fileNamePrefix = ""
                }
                DispatchQueue.global(qos: .utility).async {
                    guard let backupData = NovelSpeakerUtility.CreateBackupData(forNovelIDArray: novelIDArray, forStorySaveNovelIDArray: novelIDArray, isOnlyNovelData: true, fileNamePrefix: fileNamePrefix, progress: { (description) in
                        DispatchQueue.main.async {
                            if let label = dialog.view.viewWithTag(labelTag) as? UILabel {
                                label.text = NSLocalizedString("SettingsViewController_CreatingBackupData", comment: "バックアップデータ作成中です。\r\nしばらくお待ち下さい……") + "\r\n"
                                    + description
                            }
                        }
                    }) else {
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false) {
                                DispatchQueue.main.async {
                                    NiftyUtility.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("SettingsViewController_GenerateBackupDataFailed", comment: "バックアップデータの生成に失敗しました。"), message: nil, buttonTitle: nil, buttonAction: nil)
                                }
                            }
                        }
                        return
                    }
                    let fileName = backupData.lastPathComponent
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            successAction?(backupData, fileName)
                        }
                    }
                }
            }
        }
    }
    #endif
    
    #if !os(watchOS)
    static func SearchStoryFor(selectedStoryID:String, viewController:UIViewController, searchString:String?, selectedResultHandler:((_ story:Story)->Void)? = nil) {
        NiftyUtility.EasyDialogNoButton(
            viewController: viewController,
            title: NSLocalizedString("SpeechViewController_NowSearchingTitle", comment: "検索中"),
            message: nil) { (searchingDialog) in
            RealmUtil.RealmBlock { (realm) -> Void in
                var displayTextArray:[String] = []
                RealmStoryBulk.SearchAllStoryFor(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: selectedStoryID)) { (story) -> Bool in
                    guard let searchString = searchString else { return true }
                    if searchString.count <= 0 { return true }
                    return story.content.contains(searchString)
                } iterate: { (story) in
                    displayTextArray.append("\(story.chapterNumber): \(story.GetSubtitle())")
                }
                var selectedText:String? = nil
                if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: selectedStoryID) {
                    selectedText = "\(story.chapterNumber): " + story.GetSubtitle()
                }
                let picker = PickerViewDialog.createNewDialog(displayTextArray: displayTextArray, firstSelectedString: selectedText) { (selectedText) in
                    guard let number = selectedText.components(separatedBy: ":").first, let chapterNumber = Int(number), let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: selectedStoryID), chapterNumber: chapterNumber)) else { return }
                    selectedResultHandler?(story)
                    //SpeechBlockSpeaker.shared.SetStory(story: story)
                }
                searchingDialog.dismiss(animated: false) {
                    picker?.popup(completion: nil)
                }
            }
        }
    }
    
    static func SearchStoryWithSearchDialog(storyID:String, viewController:UIViewController, selectedResultHandler:((_ story:Story)->Void)? = nil) {
        NiftyUtility.EasyDialogTextInput2Button(
            viewController: viewController,
            title: NSLocalizedString("SpeechViewController_SearchDialogTitle", comment: "検索"),
            message: NSLocalizedString("SpeechViewController_SearchDialogMessage", comment: "本文中から文字列を検索します"),
            textFieldText: nil,
            placeHolder: NSLocalizedString("SpeechViewController_SearchDialogPlaceholderText", comment: "空文字列で検索すると全ての章がリストされます"),
            leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
            rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
            leftButtonAction: nil,
            rightButtonAction: { (filterText) in
                SearchStoryFor(selectedStoryID: storyID, viewController: viewController, searchString: filterText) { story in
                    selectedResultHandler?(story)
                }
            },
            shouldReturnIsRightButtonClicked: true,
            completion: nil)
    }
    #endif
    
    // 改行文字について全てを "\n" に変更した String を生成します。
    static func NormalizeNewlineString(string:String) -> String {
        // newline に当たる文字は Unicode において (U+000A ~ U+000D, U+0085, U+2028, and U+2029) らしい。
        // 根拠はこれ https://developer.apple.com/documentation/foundation/nscharacterset/1416730-newlines
        // で、
        // U+000A~U+000D はそれぞれ \r\v\f\n になる(Swift だと \v, \f は無いみたいなので \u{} で書く
        let targetPattern = "(\r\n|[\r\u{000B}\u{000C}\u{0085}\u{2028}\u{2029}])"
        let convertTo = "\n"
        return string.replacingOccurrences(of: targetPattern, with: convertTo, options: [.regularExpression], range: string.range(of: string))
    }
    
    static func RepeatSpeechTypeToString(type:RepeatSpeechType) -> String? {
        switch type {
        case .NoRepeat:
            return NSLocalizedString("SettingTableViewController_RepeatType_NoRepeat", comment: "しない")
        case .RewindToFirstStory:
            return NSLocalizedString("SettingTableViewController_RepeatType_RewindToFirstStory", comment: "最初から")
        case .RewindToThisStory:
            return NSLocalizedString("SettingTableViewController_RepeatType_RewindToThisStory", comment: "一つの章")
        case .GoToNextLikeNovel:
            return NSLocalizedString("SettingTableViewController_RepeatType_GoToNextLikeNovel", comment: "お気に入りのうち未読の物")
        case .GoToNextSameFolderdNovel:
            return NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSameFolderdNovel", comment: "指定フォルダの小説のうち未読の物")
        case .GoToNextSelectedFolderdNovel:
            return NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSelectedFolderdNovel", comment: "指定されたフォルダの小説のうち未読の物を再生")
        case .GoToNextSameWriterNovel:
            return NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSameWriterNovel", comment: "同じ著者の小説のうち未読の物を再生")
        case .GoToNextSameWebsiteNovel:
            return NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSameWebsiteNovel", comment: "同じWebサイトの小説のうち未読の物を再生")
        }
    }
    static func RepeatSpeechStringToType(typeString:String) -> RepeatSpeechType? {
        switch typeString {
        case NSLocalizedString("SettingTableViewController_RepeatType_NoRepeat", comment: "しない"):
            return .NoRepeat
        case NSLocalizedString("SettingTableViewController_RepeatType_RewindToFirstStory", comment: "最初から"):
            return .RewindToFirstStory
        case NSLocalizedString("SettingTableViewController_RepeatType_RewindToThisStory", comment: "一つの章"):
            return .RewindToThisStory
        case NSLocalizedString("SettingTableViewController_RepeatType_GoToNextLikeNovel", comment: "お気に入りのうち未読の物"):
            return .GoToNextLikeNovel
        case NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSameFolderdNovel", comment: "指定フォルダの小説のうち未読の物"):
            return .GoToNextSameFolderdNovel
        case NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSelectedFolderdNovel", comment: "指定フォルダの小説のうち未読の物を再生"):
            return .GoToNextSelectedFolderdNovel
        case NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSameWriterNovel", comment: "同じ著者の小説のうち未読の物を再生"):
            return .GoToNextSameWriterNovel
        case NSLocalizedString("SettingTableViewController_RepeatType_GoToNextSameWebsiteNovel", comment: "同じWebサイトの小説のうち未読の物を再生"):
            return .GoToNextSameWebsiteNovel
        default:
            return nil
        }
    }
    static func GetAllRepeatSpeechType() -> [RepeatSpeechType] {
        return [.NoRepeat, .RewindToFirstStory, .RewindToThisStory, .GoToNextLikeNovel, .GoToNextSameFolderdNovel, .GoToNextSelectedFolderdNovel, .GoToNextSameWriterNovel, .GoToNextSameWebsiteNovel]
    }
    static func RepeatLikeButtonDialogTypeToString(type:LikeButtonDialogType) -> String {
        switch type {
        case .noDialog:
            return NSLocalizedString("SettingTableViewController_LikeButtonDialogType_noDialog", comment: "確認しない")
        case .dialogOnRequested:
            return NSLocalizedString("SettingTableViewController_LikeButtonDialogType_dialogOnRequested", comment: "登録する時のみ確認する")
        case .dialogOffRequested:
            return NSLocalizedString("SettingTableViewController_LikeButtonDialogType_dialogOffRequested", comment: "削除する時のみ確認する")
        case .dialogAlwaysRequested:
            return NSLocalizedString("SettingTableViewController_LikeButtonDialogType_dialogAlwaysRequested:", comment: "いつでも確認する")
        }
    }
    static func LikeButtonDialogTypeStringToType(typeString:String) -> LikeButtonDialogType? {
        switch typeString {
        case NSLocalizedString("SettingTableViewController_LikeButtonDialogType_noDialog", comment: "確認しない"):
            return LikeButtonDialogType.noDialog
        case NSLocalizedString("SettingTableViewController_LikeButtonDialogType_dialogOnRequested", comment: "登録する時のみ確認する"):
            return LikeButtonDialogType.dialogOnRequested
        case NSLocalizedString("SettingTableViewController_LikeButtonDialogType_dialogOffRequested", comment: "削除する時のみ確認する"):
            return LikeButtonDialogType.dialogOffRequested
        case NSLocalizedString("SettingTableViewController_LikeButtonDialogType_dialogAlwaysRequested:", comment: "いつでも確認する"):
            return LikeButtonDialogType.dialogAlwaysRequested
        default:
            return nil
        }
    }
    static func GetAllLikeButtonDialogType() -> [LikeButtonDialogType] {
        return [.noDialog, .dialogOnRequested, .dialogOffRequested, .dialogAlwaysRequested]
    }

    static func RepeatSpeechLoopTypeToString(type:RepeatSpeechLoopType) -> String? {
        switch type {
        case .normal:
            return NSLocalizedString("SettingTableViewController_RepeatSpeechLoopType_Normal", comment: "未読の物を続きから再生")
        case .noCheckReadingPoint:
            return NSLocalizedString("SettingTableViewController_RepeatSpeechLoopType_NoCheckReadingPoint", comment: "順に1ページ目から再生")
        }
    }
    static func RepeatSpeechLoopStringToType(typeString:String) -> RepeatSpeechLoopType? {
        switch typeString {
        case NSLocalizedString("SettingTableViewController_RepeatSpeechLoopType_Normal", comment: "未読の物を続きから再生"):
            return .normal
        case NSLocalizedString("SettingTableViewController_RepeatSpeechLoopType_NoCheckReadingPoint", comment: "順に1ページ目から再生"):
            return .noCheckReadingPoint
        default:
            return nil
        }
    }
    static func GetAllRepeatSpeechLoopType() -> [RepeatSpeechLoopType] {
        return [.normal, .noCheckReadingPoint]
    }
    // ReepatSpeechLoopType が .normal でない場合に対象となる RepeatSpeechType のリスト
    static func GetAllRepeatSpeechLoopTargetRepeatSpeechType() -> [RepeatSpeechType] {
        return [.GoToNextLikeNovel, .GoToNextSameWebsiteNovel, .GoToNextSameWriterNovel, .GoToNextSelectedFolderdNovel]
    }

    /// 保存されているStoryを調べて、chapterNumber が 1 から順についている事を確認しつつ、
    /// それに沿っていない Story があったら、そこから後ろの Story は全部消すという事をして
    /// 「chapterNumber は必ず 1 から順に1ずつ増加する形になっている」という状態に保とうとします。
    /// - Parameter novelID: 対象の小説の NovelID
    static func CleanInvalidStory(novelID:String) {
        RealmUtil.Write { (realm) in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            guard let storyBulkArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: novelID) else { return }
            var isInvalidFound:Bool = false
            var lastChapterStoryID:String? = nil
            var chapterNumber = 1
            for storyBulk in storyBulkArray {
                if isInvalidFound {
                    realm.delete(storyBulk)
                    continue
                }
                guard let storyArray = storyBulk.LoadStoryArray() else { continue }
                var validStoryArray:[Story] = []
                for story in storyArray {
                    if story.chapterNumber == chapterNumber {
                        validStoryArray.append(story)
                        chapterNumber += 1
                        continue
                    }
                    lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: chapterNumber)
                    break
                }
                if validStoryArray.count != storyArray.count {
                    realm.delete(storyBulk)
                    RealmStoryBulk.SetStoryArrayWith_new2(realm: realm, novelID: novelID, storyArray: validStoryArray)
                    isInvalidFound = true
                }
            }
            if let lastChapterStoryID = lastChapterStoryID {
                novel.m_lastChapterStoryID = lastChapterStoryID
            }
        }
    }
    
    
    /// 「chapterNumber は必ず 1 から順に1ずつ増加する形になっている」という状態になっていない小説を検索して
    /// その NovelID のリストを返します
    /// - Returns: 不正な状態になっている小説の NovelID のリスト
    static func FindInvalidStoryArrayNovelID() -> [String] {
        return RealmUtil.RealmBlock { (realm) -> [String] in
            guard let novelIDArray = RealmNovel.GetAllObjectsWith(realm: realm)?.map({$0.novelID}) else { return [] }
            var result:[String] = []
            for novelID in novelIDArray {
                guard let storyBulkArray = RealmStoryBulk.SearchStoryBulkWith(realm: realm, novelID: novelID) else { continue }
                var chapterNumber = 0
                for storyBulk in storyBulkArray {
                    guard let storyArray = storyBulk.LoadStoryArray() else {
                        result.append(novelID)
                        break
                    }
                    for story in storyArray {
                        chapterNumber += 1
                        if story.chapterNumber == chapterNumber { continue }
                        result.append(novelID)
                        break
                    }
                }
            }
            return result
        }
    }
    
    #if !os(watchOS)
    /// CoreData側の sqlite ファイルを削除します
    static func RemoveCoreDataDataFile() {
        GlobalDataSingleton.getInstance()?.removeCoreDataDataFile()
    }
    #endif
    
    fileprivate static let isUseWebSearchTabDisabledSite_Key = "isUseWebSearchTabDisabledSite_Key"
    static var isUseWebSearchTabDisabledSite: Bool {
        get {
            let defaults = UserDefaults.standard
            defaults.register(defaults: [isUseWebSearchTabDisabledSite_Key : false])
            return defaults.bool(forKey: isUseWebSearchTabDisabledSite_Key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isUseWebSearchTabDisabledSite_Key)
            UserDefaults.standard.synchronize()
        }
    }
    
    fileprivate static let isDebugMenuAlwaysEnabled_Key = "isDebugMenuAlwaysEnabled_Key"
    static var isDebugMenuAlwaysEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            defaults.register(defaults: [isDebugMenuAlwaysEnabled_Key : false])
            return defaults.bool(forKey: isDebugMenuAlwaysEnabled_Key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isDebugMenuAlwaysEnabled_Key)
            UserDefaults.standard.synchronize()
        }
    }
    
    #if !os(watchOS)
    @objc static var currentRotation = UIDeviceOrientation.unknown
    fileprivate static let supportRotationMask_Key = "supportRotationMask_Key"
    @objc static var supportRotationMask: UIInterfaceOrientationMask {
        get {
            if UIDevice.current.userInterfaceIdiom != .phone { return UIInterfaceOrientationMask.all }
            let defaults = UserDefaults.standard
            defaults.register(defaults: [supportRotationMask_Key : UIInterfaceOrientationMask.portrait.rawValue])
            let maskUInt = UInt(defaults.integer(forKey: supportRotationMask_Key))
            switch maskUInt {
            case UIInterfaceOrientationMask.all.rawValue:
                return UIInterfaceOrientationMask.all
            case UIInterfaceOrientationMask.portrait.rawValue:
                return UIInterfaceOrientationMask.portrait
            default:
                return UIInterfaceOrientationMask.portrait
            }
        }
        set {
            currentRotation = UIDevice.current.orientation
            UserDefaults.standard.set(newValue.rawValue, forKey: supportRotationMask_Key)
            UserDefaults.standard.synchronize()
        }
    }
    #endif
    
    #if !os(watchOS)
    static func ShareStory(viewController:UIViewController, novelID:String, barButton:UIBarButtonItem?) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else {
                NiftyUtility.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("SpeechViewController_UnknownErrorForShare", comment: "不明なエラーでシェアできませんでした。"), message: nil, buttonTitle: NSLocalizedString("OK_button", comment: "OK"), buttonAction: nil)
                return
            }
            let urlString:String
            if novel.type == .URL {
                urlString = novel.url
            }else{
                urlString = ""
            }
            let message = String(format: NSLocalizedString("SpeechViewController_TweetMessage", comment: "%@ %@ #ことせかい %@ %@"), novel.title, novel.writer, urlString, "https://itunes.apple.com/jp/app/kotosekai-xiao-shuo-jianinarou/id914344185")
            NiftyUtility.Share(message: message, viewController: viewController, barButton: barButton)
        }
    }
    #endif
    
    static func GenerateNSError(msg: String, code: Int = 0) -> NSError {
        return NSError(domain: "com.limuraproducts.novelspeaker", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
    
    #if false // つくりかけ
    /// 指定されたページ(章)を削除します。
    /// そのページ(章)より後のページ(章)番号が全て書き変わります。
    static func removeStory(storyID:String, completion: @escaping ((_ result:Bool)->Void)) {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
                let targetChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else {
                    completion(false)
                    return
                }
                guard let lastChapterNumber = novel.lastChapterNumber else {
                    completion(true)
                    return
                }
                if lastChapterNumber < targetChapterNumber {
                    completion(true)
                    return
                }
                var blockIndex = RealmStoryBulk.CalcBulkChapterNumber(chapterNumber: targetChapterNumber)
                while blockIndex < lastChapterNumber {
                    let currentBulkStoryID = RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: blockIndex)
                    guard let currentBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: currentBulkStoryID) else {
                        completion(false)
                        return
                    }
                    //TODO: hogehoge
                    blockIndex += RealmStoryBulk.bulkCount
                }
            }
        }
    }
    #endif
    
    /// 短時間で何度も再起動を繰り返しているかどうかを確認するためのツールです。
    /// 動作としては、CheckRestartFrequency() が呼び出されるたびにその時間を UserDefaults に保存します。
    /// その時に、直近の count回前 の CheckRestartFrequency() 呼び出しを行った時間が
    /// 現在時刻から tickTime を引いた時間よりも後であれば、true を返します。(それ以外は false を返します)
    /// 従って、例えば tickTime が 10(秒) で count が 3 であれば、
    /// 10秒以内に 3回以上 CheckRestartFrequency() が呼び出されているなら true が返ります。
    static let CheckRestartFrequencyKey = "CheckRestartFrequencyKey"
    @objc static func CheckRestartFrequency(tickTime:TimeInterval, count:Int) -> Bool {
        let maxCount = 10

        let now = Date()
        let expireDate = now.addingTimeInterval(tickTime * -1)

        let defaults = UserDefaults.standard
        defaults.register(defaults: [CheckRestartFrequencyKey : []])
        var prev = defaults.stringArray(forKey: CheckRestartFrequencyKey) ?? []
        let currentDateTime = NiftyUtility.Date2ISO8601String(date: now)
        prev.append(currentDateTime)
        while prev.count > maxCount {
            prev.removeFirst()
        }
        defaults.set(prev, forKey: CheckRestartFrequencyKey)
        defaults.synchronize()
        while prev.count > count {
            prev.removeFirst()
        }
        if prev.count != count {
            return false
        }
        guard let targetDateTimeString = prev.first, let targetDateTime = NiftyUtility.ISO8601String2Date(iso8601String: targetDateTimeString) else { return false }
        return targetDateTime >= expireDate
    }

    static func ClearCheckRestartFrequency() {
        let defaults = UserDefaults.standard
        let cleardArray:[String] = [NiftyUtility.Date2ISO8601String(date: Date())]
        defaults.set(cleardArray, forKey: CheckRestartFrequencyKey)
        defaults.synchronize()
    }

    static let IsNeed_OpenInWebImportTab_ButtonOnNovelSearchTargetCheckDialogKey = "IsNeed_OpenInWebImportTab_ButtonOnNovelSearchTargetCheckDialog"
    static var isNeed_OpenInWebImportTab_ButtonOnNovelSearchTargetCheckDialog: Bool {
        get {
            let defaults = UserDefaults.standard
            defaults.register(defaults: [IsNeed_OpenInWebImportTab_ButtonOnNovelSearchTargetCheckDialogKey : false])
            return defaults.bool(forKey: IsNeed_OpenInWebImportTab_ButtonOnNovelSearchTargetCheckDialogKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: IsNeed_OpenInWebImportTab_ButtonOnNovelSearchTargetCheckDialogKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    static let NovelBookmarkUserDefaultsKey = "NovelBookmarkUserDefaultsKey"
    static func GetNovelBookmark(novelID:String) -> Data?{
        let defaults = UserDefaults.standard
        if let currentDictionary = defaults.dictionary(forKey: NovelBookmarkUserDefaultsKey) as? [String:Data] {
            return currentDictionary[novelID]
        }
        return nil
    }
    static func SetNovelBookmark(novelID:String, bookmarkData:Data) {
        let defaults = UserDefaults.standard
        var currentDictionary:[String:Data] = defaults.dictionary(forKey: NovelBookmarkUserDefaultsKey) as? [String:Data] ?? [:]
        currentDictionary[novelID] = bookmarkData
        UserDefaults.standard.set(currentDictionary, forKey: NovelBookmarkUserDefaultsKey)
    }
    
    static let WkWebviewIsInspectableKey = "WkWebviewIsInspectableKey"
    static func IsInspectableWkWebview() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [WkWebviewIsInspectableKey: false])
        return defaults.bool(forKey: WkWebviewIsInspectableKey)
    }
    static func SetIsInspectableWkWebview(IsInspectable:Bool) {
        let defaults = UserDefaults.standard
        defaults.setValue(IsInspectable, forKey: WkWebviewIsInspectableKey)
        defaults.synchronize()
    }
    
    static let IsDisplaySpeechModChangeKey = "IsDisplaySpeechModChangeKey"
    static func IsDisplaySpeechModChange() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [IsDisplaySpeechModChangeKey: false])
        return defaults.bool(forKey: IsDisplaySpeechModChangeKey)
    }
    static func SetIsDisplaySpeechModChange(IsDisplay:Bool){
        let defaults = UserDefaults.standard
        defaults.setValue(IsDisplay, forKey: IsDisplaySpeechModChangeKey)
        defaults.synchronize()
    }

    static let IsNotClearToAboutBlankOnDownloadBrowserUrlKey = "IsNotClearToAboutBlankOnDownloadBrowserUrl"
    static func IsNotClearToAboutBlankOnDownloadBrowserUrl() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [IsNotClearToAboutBlankOnDownloadBrowserUrlKey: false])
        return defaults.bool(forKey: IsNotClearToAboutBlankOnDownloadBrowserUrlKey)
    }
    static func SetIsNotClearToAboutBlankOnDownloadBrowserUrl(IsDisplay:Bool){
        let defaults = UserDefaults.standard
        defaults.setValue(IsDisplay, forKey: IsNotClearToAboutBlankOnDownloadBrowserUrlKey)
        defaults.synchronize()
    }

    static let IsNotDisplayUpdateCheckDialogKey = "IsNotDisplayUpdateCheckDialog"
    static func IsNotDisplayUpdateCheckDialog() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [IsNotDisplayUpdateCheckDialogKey: false])
        return defaults.bool(forKey: IsNotDisplayUpdateCheckDialogKey)
    }
    static func SetIsNotDisplayUpdateCheckDialog(IsDisplay:Bool){
        let defaults = UserDefaults.standard
        defaults.setValue(IsDisplay, forKey: IsNotDisplayUpdateCheckDialogKey)
        defaults.synchronize()
    }
    static let IsNotDisplayNovelMultiSelectCheckboxKey = "IsNotDisplayNovelMultiSelectCheckbox"
    static func IsNotDisplayNovelMultiSelectCheckbox() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [IsNotDisplayNovelMultiSelectCheckboxKey: false])
        return defaults.bool(forKey: IsNotDisplayNovelMultiSelectCheckboxKey)
    }
    static func SetIsNotDisplayNovelMultiSelectCheckbox(IsDisplay:Bool){
        let defaults = UserDefaults.standard
        defaults.setValue(IsDisplay, forKey: IsNotDisplayNovelMultiSelectCheckboxKey)
        defaults.synchronize()
    }

    static let OuterNovelFileAttributesKey = "OuterNovelFileAttributesKey"
    struct OuterNovelFileAttributes: Codable {
        let modificationDate:Date
        let size:Int
        let bookmark:Data
        let importOptionSeparated:Bool
        let originalUrlAbsoluteString:String
        let isNeedCheckUpdate:Bool?
        enum FileFormat: Int, CodingKey {
            case invalidType = 0
            case plainText = 1
            case html = 2
            case pdf = 3
            case rtf = 4
        }
        func normalizeFileFormat(num:Int) -> FileFormat {
            switch num {
            case FileFormat.plainText.rawValue:
                return FileFormat.plainText
            case FileFormat.html.rawValue:
                return FileFormat.html
            case FileFormat.pdf.rawValue:
                return FileFormat.pdf
            case FileFormat.rtf.rawValue:
                return FileFormat.rtf
            default:
                return FileFormat.invalidType
            }
        }
        let fileFormat:Int?
        var rawFileFormat:FileFormat { get { return normalizeFileFormat(num: fileFormat ?? FileFormat.invalidType.rawValue) } }
    }
    fileprivate static func UpdateOuterNovelData(novelID:String, modificationDate:Date, size:Int, bookmark:Data, importOptionSeparated: Bool, originalUrl:URL, isNeedCheckUpdate:Bool, fileFormat:OuterNovelFileAttributes.FileFormat) -> Bool {
        let outerNovelDataAttribute = OuterNovelFileAttributes(modificationDate: modificationDate, size: size, bookmark: bookmark, importOptionSeparated: importOptionSeparated, originalUrlAbsoluteString: originalUrl.absoluteString, isNeedCheckUpdate: isNeedCheckUpdate, fileFormat: fileFormat.rawValue)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        guard let encodedData = try? encoder.encode(outerNovelDataAttribute) else {
            print("OuterNovelDataAttribute encode error")
            return false
        }
        let defaults = UserDefaults.standard
        var currentDictionary:[String:Data] = defaults.dictionary(forKey: OuterNovelFileAttributesKey) as? [String:Data] ?? [:]
        currentDictionary[novelID] = encodedData
        defaults.set(currentDictionary, forKey: OuterNovelFileAttributesKey)
        defaults.synchronize()
        return true
    }
    static func RemoveOuterNovelAttributes(novelID:String){
        let defaults = UserDefaults.standard
        guard var currentDictionary:[String:Data] = defaults.dictionary(forKey: OuterNovelFileAttributesKey) as? [String:Data] else {
            return
        }
        currentDictionary.removeValue(forKey: novelID)
        defaults.set(currentDictionary, forKey: OuterNovelFileAttributesKey)
        defaults.synchronize()
    }
    static func GetOuterNovelAttributes(novelID:String) -> OuterNovelFileAttributes? {
        let defaults = UserDefaults.standard
        guard let currentDictionary:[String:Data] = defaults.dictionary(forKey: OuterNovelFileAttributesKey) as? [String:Data] else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        guard let targetData = currentDictionary[novelID], let targetAttributes = try? decoder.decode(OuterNovelFileAttributes.self, from: targetData) else {
            print("OuterNovelFileAttribute decode error")
            return nil
        }
        return targetAttributes
    }
    static func UpdateOuterNovelFileAttirbuteOnlyNeedCheckUpdate(novelID:String, isNeedCheckUpdate:Bool) -> Bool {
        guard let originalAttributes = GetOuterNovelAttributes(novelID: novelID) else {
            print("novel: \(novelID) not registerd in OuterNovelFile")
            return false
        }
        guard let originalUrl = URL(string: originalAttributes.originalUrlAbsoluteString) else {
            print("originalUrl is not url string?")
            return false
        }
        return UpdateOuterNovelData(novelID: novelID, modificationDate: originalAttributes.modificationDate, size: originalAttributes.size, bookmark: originalAttributes.bookmark, importOptionSeparated: originalAttributes.importOptionSeparated, originalUrl: originalUrl, isNeedCheckUpdate: isNeedCheckUpdate, fileFormat: originalAttributes.rawFileFormat)
    }
    static func UpdateOuterNovelFileAttributesOnlySizeAndDate(novelID:String, fileUrl:URL) -> Bool {
        let scope = fileUrl.startAccessingSecurityScopedResource()
        defer {
            if scope {
                fileUrl.stopAccessingSecurityScopedResource()
            }
        }
        guard let originalAttributes = GetOuterNovelAttributes(novelID: novelID) else {
            print("novel: \(novelID) not registerd in OuterNovelFile")
            return false
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileUrl.path) else {
            print("attributes get failed.")
            return false
        }
        guard let size = attributes[FileAttributeKey.size] as? Int else {
            print("attributes has no size")
            return false
        }
        guard let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date else {
            print("attributes has no modificationDate")
            return false
        }
        guard let originalUrl = URL(string: originalAttributes.originalUrlAbsoluteString) else {
            print("originalUrl is not url string?")
            return false
        }

        return UpdateOuterNovelData(novelID: novelID, modificationDate: modificationDate, size: size, bookmark: originalAttributes.bookmark, importOptionSeparated: originalAttributes.importOptionSeparated, originalUrl: originalUrl, isNeedCheckUpdate: originalAttributes.isNeedCheckUpdate ?? false, fileFormat: originalAttributes.rawFileFormat)
    }
    fileprivate static func RegisterOuterNovelFileAttributes(novelID:String, fileUrl:URL, importOptionSeparated:Bool, fileFormat: OuterNovelFileAttributes.FileFormat, completion: ((_ result:Bool)->Void)? = nil) {
        let scope = fileUrl.startAccessingSecurityScopedResource()
        defer {
            if scope {
                fileUrl.stopAccessingSecurityScopedResource()
            }
        }
        let options:NSURL.BookmarkCreationOptions
        #if os(macOS)
            options = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
            options = .minimalBookmark
        #endif
        #if !os(watchOS)
        ReadFileUrlWithCompletionHandler(url: fileUrl) { data in
            guard let bookmark = try? fileUrl.bookmarkData(options: options
                , includingResourceValuesForKeys: nil, relativeTo: nil) else {
                print("bookmark create failed.")
                completion?(false)
                return
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileUrl.path) else {
                print("attributes get failed.")
                completion?(false)
                return
            }
            
            guard let size = attributes[FileAttributeKey.size] as? Int else {
                print("attributes has no size")
                completion?(false)
                return
            }
            guard let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date else {
                print("attributes has no modificationDate")
                completion?(false)
                return
            }
            _ = UpdateOuterNovelData(novelID: novelID, modificationDate: modificationDate, size: size, bookmark: bookmark, importOptionSeparated:importOptionSeparated, originalUrl: fileUrl, isNeedCheckUpdate: true, fileFormat: fileFormat)
            completion?(true)
        }
        #else
        completion?(false)
        #endif
    }
    static func CheckOuterNovelIsModified(novelID: String) -> Bool {
        guard let attributes = GetOuterNovelAttributes(novelID: novelID) else {
            // 保存されたデータが存在しない場合は変更があったとみなす(読み直しを推奨する)
            print("CheckOuterNovelIsModified return true: can not get novel attributes")
            return true
        }
        var isStale = false
        guard let bookmarkUrl = try? URL(resolvingBookmarkData: attributes.bookmark, bookmarkDataIsStale: &isStale), isStale == false else {
            // ブックマークが取得できない場合やブックマークが古くなっている場合は変更があったとみなす(読み直しを推奨する)
            print("can not decode bookmarkUrl or isStale != false")
            return true
        }
        let scope = bookmarkUrl.startAccessingSecurityScopedResource()
        defer {
            if scope {
                bookmarkUrl.stopAccessingSecurityScopedResource()
            }
        }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: bookmarkUrl.path) else {
            // ファイル情報が取得できない場合は変更があったとみなす(読み直しを推奨する)
            print("CheckOuterNovelIsModified return true: error in FileManager.default.attributesOfItem()")
            return true
        }
        if let size = fileAttributes[FileAttributeKey.size] as? Int, attributes.size != size {
            print("CheckOuterNovelIsModified return true: size. \(size) != \(attributes.size)")
            return true
        }
        if let modificationDate = fileAttributes[FileAttributeKey.modificationDate] as? Date {
            // fileAttributes[] の方のは ミリ秒 まで入っているけれど、
            // attributes.modificationDate は一旦 JSON化 するためにミリ秒部分は落とされているので
            // ミリ秒部分は落として比較します。
            // で、ミリ秒部分を消す方法を探すのが面倒くさかったので DateFormatter で文字列にして比較してしまっています。
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
            let fileDate = formatter.string(from: modificationDate)
            let attributeDate = formatter.string(from: attributes.modificationDate)
            if fileDate != attributeDate {
                print("CheckOuterNovelIsModified return true: modificationDate. \(fileDate) != \(attributeDate)")
                return true
            }
        }
        print("CheckOuterNovelIsModified return false.")
        return false
    }
    #if !os(watchOS)
    // url からデータを読み込みます。
    // 最初に Data(contentsOf:) で読み込もうとして失敗したら、
    // UIDocument を使って読み直そうとします。
    static func ReadFileUrl(url:URL) async -> Data? {
        if let data = try? Data(contentsOf: url) {
            return data
        }
        class dataDocument : UIDocument {
            var data:Data? = nil
            override func load(fromContents contents: Any, ofType typeName: String?) throws {
                guard let contents = contents as? Data else { return }
                data = contents
            }
        }
        let document = await dataDocument(fileURL: url)
        let openStatus = await document.open()
        if openStatus, let data = await document.data {
            return data
        }
        print("can not read document.data")
        return nil
    }
    static func ReadFileUrlWithCompletionHandler(url:URL, completion: @escaping ((_ data:Data?)->Void)) {
        if let data = try? Data(contentsOf: url) {
            completion(data)
            return
        }
        class dataDocument : UIDocument {
            var data:Data? = nil
            override func load(fromContents contents: Any, ofType typeName: String?) throws {
                guard let contents = contents as? Data else { return }
                data = contents
            }
        }
        let document = dataDocument(fileURL: url)
        document.open { result in
            guard result, let data = document.data else {
                completion(nil)
                return
            }
            completion(data)
        }
    }
    fileprivate static func ReadOuterNovel(novelID:String, fileFormat:OuterNovelFileAttributes.FileFormat, completion: @escaping ((_ content:String?, _ fileURL:URL?)->Void)) {
        guard let attributes = GetOuterNovelAttributes(novelID: novelID) else {
            completion(nil, nil)
            return
        }
        print("format: \(attributes.fileFormat ?? -1) novel: \(novelID)")
        var isStale = false
        guard let bookmarkUrl = try? URL(resolvingBookmarkData: attributes.bookmark, bookmarkDataIsStale: &isStale), isStale == false else {
            print("can not read bookmark. error decode bookmarkUrl or isStale != false")
            completion(nil, nil)
            return
        }
        let scope = bookmarkUrl.startAccessingSecurityScopedResource()
        defer {
            if scope {
                bookmarkUrl.stopAccessingSecurityScopedResource()
            }
        }
        func convertDataToString(data:Data) -> String? {
            if let string = String(data: data, encoding: .utf8) {
                return string
            }
            var nsString:NSString?
            let encodingValue = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &nsString, usedLossyConversion: nil)
            if encodingValue != 0 {
                let encoding = String.Encoding(rawValue: encodingValue)
                return String(data: data, encoding: encoding)
            }
            return nil
        }
        func convertPDFDataToString(data:Data) -> String? {
            return NiftyUtility.BinaryPDFToString(data: data)
        }
        func convertRTFDataToString(data:Data) -> String? {
            return NiftyUtility.RTFDataToAttributedString(data: data)?.string
        }
        func convertHTMLDataToString(data:Data) -> String? {
            let (html, guessedEncoding) = NiftyUtility.decodeHTMLStringFrom(data: data, headerEncoding: NiftyUtility.DetectEncoding(data: data))
            if let html = html {
                return NiftyUtility.HTMLToString(htmlString: html)
            }
            return NiftyUtility.HTMLDataToString(htmlData: data, encoding: guessedEncoding ?? .utf8)
        }
        
        ReadFileUrlWithCompletionHandler(url: bookmarkUrl, completion: { data in
            guard let data = data else {
                completion(nil, bookmarkUrl)
                return
            }
            print("format: \(fileFormat.stringValue)")
            let content:String?
            switch fileFormat {
            case .plainText:
                content = convertDataToString(data: data)
            case .html:
                content = convertHTMLDataToString(data: data)
            case .pdf:
                content = convertPDFDataToString(data: data)
            case .rtf:
                content = convertRTFDataToString(data: data)
            default:
                print("unknown format")
                content = nil
            }
            completion(content, bookmarkUrl)
        })
    }
    static func IsRegisteredOuterNovel(novelID:String) -> Bool {
        return GetOuterNovelAttributes(novelID: novelID) != nil
    }
    static func CheckAndUpdateRgisterdOuterNovel(novelID:String) {
        guard let attribute = GetOuterNovelAttributes(novelID: novelID), attribute.isNeedCheckUpdate != false else { return }
        guard CheckOuterNovelIsModified(novelID: novelID) else { return }
        ReadOuterNovel(novelID: novelID, fileFormat: attribute.rawFileFormat) { (content, fileURL) in
            guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let separatedText = NiftyUtility.CheckShouldSeparate(text: content)
            RealmUtil.RealmBlock { realm in
                if attribute.importOptionSeparated, let separatedText = separatedText, separatedText.count > 1 {
                    RealmUtil.WriteWith(realm: realm) { realm in
                        // StoryBulk を上書きする事で SpeechViewController で表示を更新させようと思ったのだけれど、
                        // うまいことイベントが飛ばないぽいのでいっそのことStoryBulkは全部消してしまって
                        // その削除イベントで本棚に戻す、みたいな残念制御をしています(´・ω・`)
                        //RealmStoryBulk.RemoveStoryChapterAndAfterWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: separatedText.count))
                        RealmStoryBulk.RemoveAllStoryWith(realm: realm, novelID: novelID)
                        _ = RealmNovel.OverrideStoryContentArrayWith(realm: realm, novelID: novelID, contentArray: separatedText)
                    }
                }else{
                    RealmUtil.WriteWith(realm: realm) { realm in
                        //RealmStoryBulk.RemoveStoryChapterAndAfterWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: novelID, chapterNumber: 2))
                        RealmStoryBulk.RemoveAllStoryWith(realm: realm, novelID: novelID)
                        var story = Story()
                        story.novelID = novelID
                        story.chapterNumber = 1
                        story.content = content.replacingOccurrences(of: "\u{00}", with: "")
                        RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                    }
                }
            }
            if let fileURL = fileURL {
                _ = UpdateOuterNovelFileAttributesOnlySizeAndDate(novelID: novelID, fileUrl: fileURL)
            }
        }
    }
    #endif

    // 個々のOS間(場合によってはOSバージョン間)で、同じ名前(?)の話者に別のIdentity文字列が定義されている場合があり、
    // iCloud同期をしている場合や別のOS間でのバックアップファイルの適用をすることで、
    // 同じ話者名なのにIdentity文字列が違う事で話者を選択できない場合がある。
    // これを回避するために、同じ名前で登録されているIdentity文字列についてリストを作って登録しておくことで
    // このリスト内であれば同じ話者であると仮定して設定できるようにする。
    // なお、この呼出は同期的に終了させるために default値 を持ち、初回のアクセス時やデータが取得できなかった時にはその値を返すようにしている。
    // これは、この関数が呼び出されるのは発話周りに関係する事になり、その呼出でネットワーク遅延(最大10秒とか)の「待ち」が入るのを良しとしない事からくる。
    static func GetVoiceIdentifierChangeTable() -> [[String]] {
        let targetURLString = "https://limura.github.io/NovelSpeaker/data/SpeakerConvertTable-Version1.json"
        let cacheFileName = "SpeakerConvertTable-Version1.json"
        let cacheFileExpireTimeinterval:Double = 60*60*24
        let defaultResult:[[String]] = [
            ["com.apple.ttsbundle.siri_O-ren_ja-JP_premium", "com.apple.ttsbundle.siri_female_ja-JP_premium"],
            ["com.apple.voice.enhanced.ja-JP.Kyoko", "com.apple.ttsbundle.Kyoko-premium", "com.apple.speech.synthesis.voice.kyoko.premium"],
            ["com.apple.voice.enhanced.ja-JP.Otoya", "com.apple.ttsbundle.Otoya-premium", "com.apple.speech.synthesis.voice.otoya.premium"],
            ["com.apple.ttsbundle.siri_O-ren_ja-JP_compact", "com.apple.ttsbundle.siri_female_ja-JP_compact"],
            ["com.apple.voice.compact.ja-JP.Kyoko", "com.apple.ttsbundle.Kyoko-compact"],
            ["com.apple.ttsbundle.siri_Hattori_ja-JP_compact", "com.apple.ttsbundle.siri_male_ja-JP_compact"],
            ["com.apple.voice.compact.ja-JP.Otoya", "com.apple.ttsbundle.Otoya-compact"]
        ]
        guard let changeTableURL = URL(string: targetURLString) else {
            return defaultResult
        }
        // 怪しくキャッシュファイルから読み込んで、HTTPリクエストはその後に勝手に出すようにします。
        let result:[[String]]
        if let cachedData = NiftyUtility.GetCachedHttpGetCachedData(url: changeTableURL, cacheFileName: cacheFileName, expireTimeinterval: cacheFileExpireTimeinterval), let table = try? JSONDecoder().decode([[String]].self, from: cachedData) {
            result = table
        }else{
            result = defaultResult
        }
        // 単にキャッシュファイルを更新するためだけの呼び出しです。
        NiftyUtility.FileCachedHttpGet(url: changeTableURL, cacheFileName: cacheFileName, expireTimeinterval: cacheFileExpireTimeinterval, successAction: nil, failedAction: nil)
        return result
    }

    @objc static func ForceStopSpeech() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { realm in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
            }
        }
    }
    static var initialAvailableMemory = 0
    @objc static func SetInitialAvailableMemory() {
        initialAvailableMemory = os_proc_available_memory()
    }
    static var MemoryUsageValidChecked = false
    static func CheckMemoryUsageIsValid() -> Bool {
        if MemoryUsageValidChecked || initialAvailableMemory == 0 { return true }
        let maxUsableMemory = 1750 * 1024 * 1024 // なんぼなんでも 1.75G 以上は使わんの助
        let borderUsableMemory = 100 * 1024 * 1024 // 残りが 100MBytes を下回ったらもう駄目と思う
        let availableMemory = os_proc_available_memory()
        // どうやら搭載メモリ量が大きい(iPadで16Gとかある)やつだと
        // 使えるとして大きなメモリ量を申告してくる事があるらしいんだけども、
        // 特殊なエンタイトルメントを追加してないと結局2Gの壁は超えられないらしいので
        // 最初に観測したものから maxUsableMemory 以上使ってたら駄目ということにします。
        // 参考: https://tech-blog.optim.co.jp/entry/2022/10/26/080000
        if (initialAvailableMemory - availableMemory) > maxUsableMemory {
            MemoryUsageValidChecked = true
            return false
        }
        if availableMemory > borderUsableMemory {
            return true
        }
        MemoryUsageValidChecked = true
        return false
    }
    static func ResetMemoryUsage() {
        MemoryUsageValidChecked = false
    }
    #if !os(watchOS)
    static func GetAppStoreAppVersionInfo(completion: @escaping (Date?, String?, Error?) -> Void) {
        let appStoreURLString = "https://apps.apple.com/jp/app/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84/id914344185"
        let cacheFileName = "NovelSpeaker_AppStore_Cache"
        let cacheFileExpireTimeInterval:TimeInterval = 60*30
        guard let appStoreURL = URL(string: appStoreURLString) else {
            completion(nil, nil, GenerateNSError(msg: "can not decode URL String: \(appStoreURLString)"))
            return
        }
        NiftyUtility.GetAppStoreAppVersionInfo(appStoreURL: appStoreURL, cacheFileName: cacheFileName, expireTimeinterval: cacheFileExpireTimeInterval) { date, version, err in
            completion(date, version, err)
            if version != nil {
                return true
            }
            return false
        }
    }
    #endif
    struct AppStoreWebPageXpath : Decodable {
        var latestDate:String?
        var latestShortVersion:String?
        init(){
            latestDate = "//div[contains(@class,'whats-new__latest')]//time[@datetime]/@datetime"
            latestShortVersion = "//div[contains(@class,'whats-new__latest')]//p[contains(@class,'whats-new__latest__version')]"
        }
    }
    struct NovelSpeakerRemoteConfig : Decodable {
        var appStoreWebPageXpath:AppStoreWebPageXpath?
    }
    static func GetNovelSpeakerRemoteConfig(completion: @escaping (NovelSpeakerRemoteConfig)->Void) {
        let defaultSetting = NovelSpeakerRemoteConfig(
            appStoreWebPageXpath: AppStoreWebPageXpath()
        )
        guard let url = URL(string: "https://raw.githubusercontent.com/limura/NovelSpeaker/gh-pages/data/NovelSpeakerRemoteConfig.json") else {
            completion(defaultSetting)
            return
        }
        // nil なら defaultSetting で上書きします
        func overrideDefaultSetting(config:NovelSpeakerRemoteConfig) -> NovelSpeakerRemoteConfig {
            var remoteConfig = config
            if remoteConfig.appStoreWebPageXpath == nil {
                remoteConfig.appStoreWebPageXpath = defaultSetting.appStoreWebPageXpath
            }else{
                remoteConfig.appStoreWebPageXpath!.latestDate = remoteConfig.appStoreWebPageXpath!.latestDate ?? defaultSetting.appStoreWebPageXpath?.latestDate
                remoteConfig.appStoreWebPageXpath!.latestShortVersion = remoteConfig.appStoreWebPageXpath!.latestShortVersion ?? defaultSetting.appStoreWebPageXpath?.latestShortVersion
            }
            return remoteConfig
        }
        let remoteConfigCacheFileName = "NovelSpeakerRemoteConfigCache"
        let expireTimeInterval:TimeInterval = 60*60*6
        NiftyUtility.FileCachedHttpGet(url: url, cacheFileName: remoteConfigCacheFileName, expireTimeinterval: expireTimeInterval) { data in
            let decoder = JSONDecoder()
            var remoteConfig:NovelSpeakerRemoteConfig
            if let httpRemoteConfig = try? decoder.decode(NovelSpeakerRemoteConfig.self, from: data) {
                remoteConfig = httpRemoteConfig
            } else {
                guard let cachedData = NiftyUtility.GetCachedHttpGetCachedData(url: url, cacheFileName: remoteConfigCacheFileName, expireTimeinterval: nil), let cacheRemoteConfig = try? decoder.decode(NovelSpeakerRemoteConfig.self, from: cachedData) else {
                    completion(defaultSetting)
                    return false
                }
                completion(cacheRemoteConfig)
                return false // デコードできなかったので false を返してキャッシュの上書きは許さないことにします
            }
            
            completion(overrideDefaultSetting(config: remoteConfig))
            return true
        } failedAction: { err in
            let decoder = JSONDecoder()
            guard let cachedData = NiftyUtility.GetCachedHttpGetCachedData(url: url, cacheFileName: remoteConfigCacheFileName, expireTimeinterval: nil), let cacheRemoteConfig = try? decoder.decode(NovelSpeakerRemoteConfig.self, from: cachedData) else {
                completion(defaultSetting)
                return
            }
            completion(overrideDefaultSetting(config: cacheRemoteConfig))
        }
    }

    /* AVSpeechSynthesizer を開放するとメモリ解放できそうなので必要なくなりました
    static let isDisableWillSpeakRangeKey = "isDisableWillSpeakRange"
    static func GetIsDisableWillSpeakRange() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [isDisableWillSpeakRangeKey: false])
        return defaults.bool(forKey: isDisableWillSpeakRangeKey)
    }
    static func SetIsDisableWillSpeakRange(isDisable:Bool) {
        let defaults = UserDefaults.standard
        defaults.set(isDisable, forKey: isDisableWillSpeakRangeKey)
        defaults.synchronize()
    }

    static let MoreSplitTargetsMinimumCountKey = "MoreSplitTargetsMinimumCountKey"
    static func GetMoreSplitTargetsMinimumCount() -> Int {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [MoreSplitTargetsMinimumCountKey: 50])
        return defaults.integer(forKey: MoreSplitTargetsMinimumCountKey)
    }
    static func SetMoreSplitTargetsMinimumCount(newValue:Int) {
        let defaults = UserDefaults.standard
        defaults.set(newValue, forKey: MoreSplitTargetsMinimumCountKey)
        defaults.synchronize()
    }
    */
}
