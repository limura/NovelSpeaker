//
//  NovelSpeakerBackup.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/07/05.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit
import SSZipArchive

class NovelSpeakerBackup: NSObject {
    static func getBackupDirectoryPath() -> String {
        return NSTemporaryDirectory() + "/" + "backupDir"
    }
    
    static func createDateString() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "yyyyMMddHHmm"
        let dateString = dateFormatter.string(from: Date())
        return dateString
    }
    
    // バックアップ用にテンポラリディレクトリを掘ってそのURLを返します。失敗した場合は nil を返します。
    static func createBackupDirectory() -> URL? {
        let dateString = NovelSpeakerBackup.createDateString()
        let tmpDir = NovelSpeakerBackup.getBackupDirectoryPath() + "/" + dateString
        let defaultFileManager = FileManager.default
        if defaultFileManager.fileExists(atPath: tmpDir) {
            return nil
        }
        do {
            try defaultFileManager.createDirectory(atPath: tmpDir, withIntermediateDirectories: true, attributes: nil)
        }catch{
            return nil;
        }
        return URL(fileURLWithPath: tmpDir)
    }
    
    static func getDocumentsBackupDirectoryPathString() -> String {
        return NSHomeDirectory() + "/Documents/Backup"
    }
    
    static func cleanBackupStoreDirectory() {
        do {
            try FileManager.default.removeItem(atPath: NovelSpeakerBackup.getBackupDirectoryPath())
        }catch{
            // nothing to do!
        }
        do {
            try FileManager.default.removeItem(atPath: getDocumentsBackupDirectoryPathString())
        }catch{
            // nothing to do!
        }
        do {
            try FileManager.default.createDirectory(atPath: getDocumentsBackupDirectoryPathString(), withIntermediateDirectories: true, attributes: nil)
        }catch let error{
            // nothing to do!
            print("create backup directory error:", error)
        }
    }
    
    @objc public static func updateStory(globalData:GlobalDataSingleton, text:String, chapterNumber:Int, ncode:String) {
        let content = NarouContentCacheData()
        content.ncode = ncode
        globalData.updateStory(text, chapter_number: Int32(chapterNumber), parentContent: content)
    }
    
    /// novelspeaker-backup+zip のバイナリを生成して返します。一時的に zip 用のディレクトリやファイルが作成されます。
    @objc public static func createBackupData(progress:((String)->Void)?) -> URL? {
        func UpdateProgress(message:String) {
            if let progress = progress {
                progress(message)
            }
        }
        let fileManager = FileManager.default
        
        UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_InitializeBackup", comment: "初期化中"))
        // 最初に有無を言わさず作業用ディレクトリの中身を吹き飛ばします
        NovelSpeakerBackup.cleanBackupStoreDirectory()

        guard let tmpDirURL = createBackupDirectory(),
            let globalDataSingleton = GlobalDataSingleton.getInstance(),
            var backupDataDictionary = globalDataSingleton.createBackupDataDictionary(),
            let bookShelfArray = backupDataDictionary["bookshelf"] as? [Dictionary<String,Any>]
            else {
            return nil
        }
        UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_ExportingNovelText", comment: "小説本文を抽出中"))
        var newBookShelfArray:[Dictionary<String, Any>] = []
        var bookShelfCount = 1
        var bookShelfCountDictionary:Dictionary<String,String> = [:]
        var bookShelfCountForDisplay = 0;
        for var bookShelfDictionary in bookShelfArray {
            bookShelfCountForDisplay += 1
            // TODO: 本文を保存しつつ、中身を書き換える
            func createContentDirectory(ncode:String) -> String {
                if let count = bookShelfCountDictionary[ncode] {
                    return count
                }
                let str = bookShelfCount.description
                bookShelfCount += 1
                bookShelfCountDictionary[ncode] = str
                return str
            }
            func addStoryContent(directory:URL, no:Int, content:String) -> Bool {
                do {
                    try autoreleasepool {
                        //try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                        try content.write(to: directory.appendingPathComponent(no.description + ".txt"), atomically: true, encoding: .utf8)
                    }
                } catch let error {
                    print("story content write error", error)
                    return false
                }
                return true
            }
            func loadAllStoryContent(ncode:String, progressString:String) -> String? {
                let contentDirectoryName = createContentDirectory(ncode: ncode)
                let contentDirectoryURL = tmpDirURL.appendingPathComponent(contentDirectoryName)
                var isFailed = false
                var no = 1
                let storyCount = globalDataSingleton.getStoryCount(forNcode: ncode)
                
                do {
                    try fileManager.createDirectory(at: contentDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                }catch let error {
                    print("createDirectory failed: \(error)")
                    return nil
                }
                globalDataSingleton.getAllStoryTextForNcode(withBlock: ncode) { (text) in
                    guard let storyString = text else { return }
                    if !addStoryContent(directory: contentDirectoryURL, no: no, content:storyString) {
                        isFailed = true
                        return
                    }
                    no = no + 1
                    let currentProgressString = "\(progressString) (\(no)/\(storyCount))"
                    UpdateProgress(message: currentProgressString)
                }
                if isFailed {
                    return nil
                }
                return contentDirectoryName
            }
            let extractingMessage = NSLocalizedString("NovelSpeakerBackup_ExportingNovelText", comment: "小説本文を抽出中") + " (" + bookShelfCountForDisplay.description + "/" + bookShelfArray.count.description + ")"
            UpdateProgress(message: extractingMessage)
            
            if let type = bookShelfDictionary["type"] as? String {
                switch type {
                case "url":
                    if let url = bookShelfDictionary["url"] as? String {
                        if let contentDirectoryName = loadAllStoryContent(ncode: url, progressString: extractingMessage) {
                            bookShelfDictionary["content_directory"] = contentDirectoryName
                        }
                    }
                    break
                case "user":
                    break
                case "ncode":
                    if let ncode = bookShelfDictionary["ncode"] as? String {
                        if let contentDirectoryName = loadAllStoryContent(ncode: ncode, progressString: extractingMessage) {
                            bookShelfDictionary["content_directory"] = contentDirectoryName
                        }
                    }
                    break
                default:
                    break
                }
            }
            newBookShelfArray.append(bookShelfDictionary)
        }
        backupDataDictionary["bookshelf"] = newBookShelfArray
        
        // backup_data.json ファイルを zip されるディレクトリに追加
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: backupDataDictionary, options: .prettyPrinted)
            let backupDataURL = tmpDirURL.appendingPathComponent("backup_data.json")
            try jsonData.write(to: backupDataURL)
        }catch let error {
            print("JSONSerialization or write", error)
            return nil
        }
        
        // zipFilePath に zip された後のファイル名を入れて zip する
        let dateString = NovelSpeakerBackup.createDateString()
        //let zipFilePath = URL(fileURLWithPath: NovelSpeakerBackup.getBackupDirectoryPath()).appendingPathComponent(dateString + ".zip")
        let zipFilePath = URL(fileURLWithPath: NovelSpeakerBackup.getDocumentsBackupDirectoryPathString()).appendingPathComponent("NovelSpeakerBackup-" + dateString + ".zip")
        let novelSpeakerBackupZipFilePath = URL(fileURLWithPath: NovelSpeakerBackup.getDocumentsBackupDirectoryPathString()).appendingPathComponent("NovelSpeakerBackup-" + dateString + ".novelspeaker-backup+zip")
        UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_CompressingBackupData", comment: "バックアップデータを圧縮中"))
        let result = SSZipArchive.createZipFile(atPath: zipFilePath.path, withContentsOfDirectory: tmpDirURL.path, keepParentDirectory: false, compressionLevel: 9, password: nil, aes: false) { (progressA, progressB) in
            print("SSZipArchive progress: \(progressA), \(progressB)")
            UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中") + " (\(Int(Float(progressA)/Float(progressB)*100.0))%)")
        }
        if result == false {
            print("zip file create error", zipFilePath)
            return nil
        }
        do {
            try fileManager.moveItem(at: zipFilePath, to: novelSpeakerBackupZipFilePath)
        }catch let error {
            print("zip file move error", zipFilePath, novelSpeakerBackupZipFilePath, error)
            return nil
        }
        UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_RemovingStoryFiles", comment: "後処理中"))
        // zip作成に使ったディレクトリはこのタイミングで消します
        do {
            try fileManager.removeItem(at: tmpDirURL)
        }catch let error {
            print("zip directory delete error", tmpDirURL, error)
            return nil
        }

        // 作られた zip file を読み込んで返す。ファイルは消します
        do {
            let _ = try Data(contentsOf: novelSpeakerBackupZipFilePath, options: .dataReadingMapped)
            //try FileManager.default.removeItem(at: zipFilePath) // dataReadingMapped なのでファイルが消せません……(´・ω・`)
            return novelSpeakerBackupZipFilePath
        }catch let error {
            print("read zipFile or file delete error", zipFilePath, error)
            return nil
        }
    }
    
    /// novelspeaker-backup+zip へのパス(URL)を受け取って、それを適用します。成否を返します。
    @objc public static func parseBackupFile(url: URL, toplevelViewController:UIViewController, finally:((Bool)->Void)? = nil) {
        let dialog = NiftyUtilitySwift.EasyDialogBuilder(toplevelViewController)
        .label(text: NSLocalizedString("NovelSpeakerBackup_Restoreing", comment: "バックアップより復元"), textAlignment: .center, tag: 100)
        .build()
        func announceProgress(text:String){
            NiftyUtilitySwift.DispatchSyncMainQueue {
                if let label = dialog.view.viewWithTag(100) as? UILabel {
                    label.text = NSLocalizedString("NovelSpeakerBackup_Restoreing", comment: "バックアップより復元") + "\r\n" + text
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0))
                }
            }
        }
        DispatchQueue.main.async {
            dialog.show {
                // 最初に有無を言わさず作業用ディレクトリの中身を吹き飛ばします
                NovelSpeakerBackup.cleanBackupStoreDirectory()

                guard let tmpDirURL = createBackupDirectory(),
                    let globalDataSingleton = GlobalDataSingleton.getInstance() else {
                    print("create backup directory failed.")
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            if let finally = finally {
                                finally(false)
                            }
                        })
                    }
                    return
                }

                let zipResult = SSZipArchive.unzipFile(atPath: url.path, toDestination: tmpDirURL.path, overwrite: true, password: nil) { (fileName, fileInfo, progressA, progressB) in
                    //print("progress: \(fileName), \(progressA), \(progressB)")
                    let warningText:String
                    if progressB >= 65535 {
                        warningText = NSLocalizedString("NovelSpeakerBackup_ProgressExtractingZip_WarningInvalidPercentage", comment: "\n展開中のバックアップファイル中のファイル数が多いため、進捗(%表示)が不正な値を指すことがあります")
                    }else{
                        warningText = ""
                    }
                    announceProgress(text: NSLocalizedString("NovelSpeakerBackup_ProgressExtractingZip", comment: "展開中") + " (\(Int(Float(progressA)/Float(progressB)*100.0))%)\(warningText)")
                } completionHandler: { (str, result, err) in
                    print("completion: \(str), \(result ? "true": "false"), \(err?.localizedDescription ?? "-")")
                }
                if zipResult == false {
                    print("unzipFile failed.")
                    return
                }
                // TODO: completion でなんとかしないと駄目
                var jsonData:Data? = nil
                do {
                    let backupDataJsonFilePath = tmpDirURL.appendingPathComponent("backup_data.json", isDirectory: false)
                    try jsonData = Data(contentsOf: backupDataJsonFilePath)
                }catch let error{
                    print("read backup_data.json failed", error)
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            if let finally = finally {
                                finally(false)
                            }
                        })
                    }
                    return
                }

                guard let jsonDataClean = jsonData else {
                    print("no jsonData")
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            if let finally = finally {
                                finally(false)
                            }
                        })
                    }
                    return
                }
                announceProgress(text: NSLocalizedString("NovelSpeakerBackup_RestoreingBackupData", comment: "適用中"))
                let result = globalDataSingleton.restoreBackup(fromJSONData: jsonDataClean, dataDirectory: tmpDirURL) { (text) in
                    if let text = text {
                        announceProgress(text: text)
                    }
                }
                
                // zip展開に使ったディレクトリを消します
                do {
                    try FileManager.default.removeItem(at: tmpDirURL)
                }catch let error {
                    print("zip directory delete error", tmpDirURL, error)
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            if let finally = finally {
                                finally(false)
                            }
                        })
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        if let finally = finally {
                            finally(result)
                        }
                    })
                }
            }
        }
    }
}
