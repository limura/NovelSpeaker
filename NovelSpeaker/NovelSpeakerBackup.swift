//
//  NovelSpeakerBackup.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/07/05.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit
import Zip

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
    
    /// novelspeaker-backup+zip のバイナリを生成して返します。一時的に zip 用のディレクトリやファイルが作成されます。
    @objc public static func createBackupData(progress:((String)->Void)?) -> URL? {
        func UpdateProgress(message:String) {
            if let progress = progress {
                progress(message)
            }
        }
        
        UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_InitializeBackup", comment: "初期化中"))
        // 最初に有無を言わさず作業用ディレクトリの中身を吹き飛ばします
        NovelSpeakerBackup.cleanBackupStoreDirectory()

        var zipPaths:[URL] = []
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
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                    try content.write(to: directory.appendingPathComponent(no.description + ".txt"), atomically: true, encoding: .utf8)
                } catch let error {
                    print("story content write error", error)
                    return false
                }
                return true
            }
            func loadAllStoryContent(ncode:String, bookShelfDictionary:Dictionary<String,Any>) -> (String?, [URL]?) {
                var zipPaths:[URL] = []
                if let storyArray = globalDataSingleton.getAllStoryText(forNcode: ncode) {
                    let contentDirectoryName = createContentDirectory(ncode: ncode)
                    let contentDirectoryURL = tmpDirURL.appendingPathComponent(contentDirectoryName)
                    zipPaths.append(contentDirectoryURL)
                    var isFailed = false
                    var no = 1
                    for storyObj in storyArray {
                        if let storyString = storyObj as? String {
                            if !addStoryContent(directory: contentDirectoryURL, no: no, content:storyString) {
                                isFailed = true
                                break
                            }
                            no = no + 1
                        }else{
                            isFailed = true
                            break
                        }
                    }
                    if isFailed {
                        print("isFailed")
                        do {
                            try FileManager.default.removeItem(at: contentDirectoryURL)
                        }catch{
                            // nothing to do
                        }
                    }else{
                        return (contentDirectoryName, zipPaths)
                    }
                }
                print("loadAllStory failed")
                return (nil, nil)
            }
            UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_ExportingNovelText", comment: "小説本文を抽出中") + " (" + bookShelfCountForDisplay.description + "/" + bookShelfArray.count.description + ")")
            
            if let type = bookShelfDictionary["type"] as? String {
                switch type {
                case "url":
                    if let url = bookShelfDictionary["url"] as? String {
                        let loadResult = loadAllStoryContent(ncode: url, bookShelfDictionary: bookShelfDictionary)
                        if let contentDirectoryName = loadResult.0, let appendZipPaths = loadResult.1 {
                            bookShelfDictionary["content_directory"] = contentDirectoryName
                            zipPaths.append(contentsOf: appendZipPaths)
                        }
                    }
                    break
                case "user":
                    break
                case "ncode":
                    if let ncode = bookShelfDictionary["ncode"] as? String {
                        let loadResult = loadAllStoryContent(ncode: ncode, bookShelfDictionary: bookShelfDictionary)
                        if let contentDirectoryName = loadResult.0, let appendZipPaths = loadResult.1 {
                            bookShelfDictionary["content_directory"] = contentDirectoryName
                            zipPaths.append(contentsOf: appendZipPaths)
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
            zipPaths.append(backupDataURL)
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
        do {
            print("zipPaths", zipPaths)
            try Zip.zipFiles(paths: zipPaths, zipFilePath: zipFilePath, password: nil, compression: ZipCompression.BestCompression, progress: { (progress) in
                print("zip progress:", progress)
                UpdateProgress(message: NSLocalizedString("NovelSpeakerBackup_CompressingBackupDataProgress", comment: "バックアップデータを圧縮中") + " (" + Int(progress * 100).description + "%)")
            })
        }catch let error {
            print("zip file create error", zipFilePath, error)
            return nil
        }
        do {
            try FileManager.default.moveItem(at: zipFilePath, to: novelSpeakerBackupZipFilePath)
        }catch let error {
            print("zip file move error", zipFilePath, novelSpeakerBackupZipFilePath, error)
            return nil
        }
        // zip作成に使ったディレクトリはこのタイミングで消します
        do {
            try FileManager.default.removeItem(at: tmpDirURL)
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
    @objc public static func parseBackupFile(url: URL, toplevelViewController:UIViewController, finally:((Bool)->Void)? = nil) -> Bool {
        let dialog = NiftyUtilitySwift.EasyDialogBuilder(toplevelViewController)
        .label(text: NSLocalizedString("NovelSpeakerBackup_Restoreing", comment: "バックアップより復元"), textAlignment: .center, tag: 100)
        .build()
        DispatchQueue.main.async {
            dialog.show()
        }
        
        func announceProgress(text:String){
            DispatchQueue.main.async {
                if let label = dialog.view.viewWithTag(100) as? UILabel {
                    label.text = NSLocalizedString("NovelSpeakerBackup_Restoreing", comment: "バックアップより復元") + "\r\n" + text
                }
            }
        }
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
            return false;
        }

        do {
            Zip.addCustomFileExtension("novelspeaker-backup+zip")
            try Zip.unzipFile(url, destination: tmpDirURL, overwrite: false, password: nil, progress: { (progress) in
                //print("progress", progress)
                announceProgress(text: NSLocalizedString("NovelSpeakerBackup_ProgressExtractingZip", comment: "展開中") + " (" + Int(progress * 100).description + "%)")
            }) { (url) in
                // print("fileOutput", url)
            }
        }catch let error{
            print("unzip failed", error, url)
            DispatchQueue.main.async {
                dialog.dismiss(animated: false, completion: {
                    if let finally = finally {
                        finally(false)
                    }
                })
            }
            return false
        }
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
            return false
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
            return false
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
            return false
        }
        
        DispatchQueue.main.async {
            dialog.dismiss(animated: false, completion: {
                if let finally = finally {
                    finally(result)
                }
            })
        }
        return result
    }
}
