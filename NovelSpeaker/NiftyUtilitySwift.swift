//
//  SampleUrlFetcher.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/19.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import PDFKit

class NiftyUtilitySwift: NSObject {
    @objc public static func checkTextImportConifirmToUser(viewController: UIViewController, title: String, content: String, hintString: String?){
        DispatchQueue.main.async {
            var easyDialog = EasyDialog.Builder(viewController)
                .textField(tag: 100, placeholder: title, content: title, keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect)
                // TODO: 怪しくheightを画面の縦方向からの比率で指定している。
                // ここに 1.0 とか書くと他のViewの分の高さが入って全体は画面の縦幅よりも高くなるので全部が表示されない。
                // つまり、この謎の数字 0.53 というのは、できれば書きたくない値であり、この値でも大きすぎるかもしれず、
                // 小さすぎるかもしれず、適切な大きさ(baseViewが表示領域の縦幅に入る状態)になるように縮む必要があるのだが、
                // EasyDialog をそのように修正するのが面倒なのでやっていないという事なのであった。('A`)
                .textView(content: content, heightMultiplier: 0.53)
                
            if let hintString = hintString {
                easyDialog = easyDialog.label(text: hintString)
            }
            easyDialog.addButton(title: NSLocalizedString("NiftyUtilitySwift_CancelImport", comment: "取り込まない"), callback: { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
            })
            .addButton(title: NSLocalizedString("NiftyUtilitySwift_Import", comment: "このまま取り込む"), callback: { (dialog) in
                let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                let title = titleTextField.text ?? title
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
                if let globalData = GlobalDataSingleton.getInstance() {
                    if let newUserBook = globalData.createNewUserBook() {
                        newUserBook.title = title
                        newUserBook.general_all_no = NSNumber.init(value: 1)
                        globalData.updateNarouContent(newUserBook)
                        globalData.updateStory(content, chapter_number: 1, parentContent:   newUserBook)
                        return
                    }
                }
                DispatchQueue.main.sync {
                    EasyDialog.Builder(viewController)
                        .title(title: NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfTitle", comment: "不明なエラー"))
                        .label(text: NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfBody", comment: "本棚への追加に失敗しました。"))
                        .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                            DispatchQueue.main.async {
                                dialog.dismiss(animated: false, completion: nil)
                            }
                        })
                        .build().show()
                }
            })
            .build().show()
        }

    }
    
    @objc public static func checkUrlAndConifirmToUser(viewController: UIViewController, url: URL, cookieArray: [String], depth: Int = 0) {
        BehaviorLogger.AddLog(description: "checkUrlAndConifirmToUser called.", data: ["url": url.absoluteString])
        DispatchQueue.main.async {
            let easyAlert = EasyAlert(viewController: viewController)
            let alertActionHolder = easyAlert?.show(NSLocalizedString("ImportFromWebPageViewController_loading", comment: "loading"), message: nil)
            let uriLoader = UriLoader()
            let customSiteInfoData = GlobalDataSingleton.getInstance().getCachedCustomAutoPagerizeSiteInfoData()
            uriLoader.addCustomSiteInfo(from: customSiteInfoData)
            let siteInfoData = GlobalDataSingleton.getInstance().getCachedAutoPagerizeSiteInfoData()
            uriLoader.addSiteInfo(from: siteInfoData)
            uriLoader.fetchOneUrl(url, cookieArray: cookieArray, successAction: { (story: HtmlStory?) in
                DispatchQueue.main.sync {
                    alertActionHolder?.closeAlert(false, completion: {
                        // firstPageLink があった場合はそっちを読み直します
                        if let firstPageLink = story?.firstPageLink {
                            // ただし、depth が 5 を越えたら読み直さず先に進みます
                            if depth < 5 {
                                NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: viewController, url: firstPageLink, cookieArray: cookieArray, depth: depth+1)
                                return
                            }
                        }
                        guard let content = story?.content else {
                            DispatchQueue.main.async {
                                EasyDialog.Builder(viewController)
                                    .title(title: NSLocalizedString("NiftyUtilitySwift_ImportError", comment: "取り込み失敗"))
                                    .label(text: NSLocalizedString("NiftyUtilitySwift_ImportedButNoTextFound", comment: "読み込めはしたけれど、内容がありませんでした"))
                                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                        DispatchQueue.main.async {
                                            dialog.dismiss(animated: false, completion: nil)
                                        }
                                    })
                                    .build().show()
                            }
                            return
                        }
                        DispatchQueue.main.async {
                            var multiPageString = NSLocalizedString("NiftyUtilitySwift_FollowingPageAreNotAvailable", comment: "続ページ：無し")
                            let nextUrl:URL? = story?.nextUrl ?? nil
                            if (story?.nextUrl) != nil {
                                multiPageString = NSLocalizedString("NiftyUtilitySwift_FollowingPageAreAvailable", comment: "続ページ：有り")
                            }
                            var titleString = NSLocalizedString("NiftyUtilitySwift_TitleUnknown", comment: "不明なタイトル")
                            if let title = story?.title {
                                titleString = title
                            }
                            EasyDialog.Builder(viewController)
                                .textField(tag: 100, placeholder: titleString, content: titleString, keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect)
                                //.title(title: titleString)
                                // TODO: 怪しくheightを画面の縦方向からの比率で指定している。
                                // ここに 1.0 とか書くと他のViewの分の高さが入って全体は画面の縦幅よりも高くなるので全部が表示されない。
                                // つまり、この謎の数字 0.53 というのは、できれば書きたくない値であり、この値でも大きすぎるかもしれず、
                                // 小さすぎるかもしれず、適切な大きさ(baseViewが表示領域の縦幅に入る状態)になるように縮む必要があるのだが、
                                // EasyDialog をそのように修正するのが面倒なのでやっていないという事なのであった。('A`)
                                .textView(content: content, heightMultiplier: 0.53)
                                .label(text: multiPageString)
                                .addButton(title: NSLocalizedString("NiftyUtilitySwift_CancelImport", comment: "取り込まない"), callback: { (dialog) in
                                    DispatchQueue.main.async {
                                        dialog.dismiss(animated: false, completion: nil)
                                    }
                                })
                                .addButton(title: NSLocalizedString("NiftyUtilitySwift_Import", comment: "このまま取り込む"), callback: { (dialog) in
                                    let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                                    let titleString = titleTextField.text ?? titleString
                                    DispatchQueue.main.async {
                                        dialog.dismiss(animated: false, completion: nil)
                                    }
                                    guard let globalData = GlobalDataSingleton.getInstance() else {
                                        DispatchQueue.main.sync {
                                            EasyDialog.Builder(viewController)
                                                .title(title: NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfTitle", comment: "不明なエラー"))
                                                .label(text: NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfBody", comment: "本棚への追加に失敗しました。"))
                                                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                                    DispatchQueue.main.async {
                                                        dialog.dismiss(animated: false, completion: nil)
                                                    }
                                                })
                                                .build().show()
                                        }
                                        return
                                    }
                                    let cookieParameter = cookieArray.joined(separator: ";")
                                    globalData.addNewContent(for: url, nextUrl:nextUrl, cookieParameter: cookieParameter, title: titleString, author: story?.author, firstContent: content, viewController: viewController)
                                })
                                .build().show()
                        }
                    })
                }
            }, failedAction: { (url:URL?, error:String?) in
                DispatchQueue.main.async {
                    alertActionHolder?.closeAlert(false, completion: {
                        var errorMessage = NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfTitle", comment: "不明なエラー")
                        if let err = error {
                            errorMessage = err
                        }
                        EasyDialog.Builder(viewController)
                            .title(title: NSLocalizedString("NiftyUtilitySwift_ImportError", comment: "取り込み失敗"))
                            .label(text: errorMessage)
                            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                DispatchQueue.main.async {
                                    dialog.dismiss(animated: false, completion: nil)
                                }
                            })
                            .build().show()
                    })
                }
            })
        }
    }
    
    @objc public static func BinaryPDFToString(data: Data) -> String? {
        if #available(iOS 11.0, *) {
            let pdf = PDFDocument(data: data)
            if let str = pdf?.string {
                return str
            }
        }
        return nil
    }
    
    @objc public static func FilePDFToString(url: URL) -> String? {
        if #available(iOS 11.0, *) {
            let pdf = PDFDocument(url: url)
            if let str = pdf?.string {
                return str
            }
        }
        return nil
    }
    
    @objc public static func EasyDialogOneButton(viewController: UIViewController, title: String?, message: String?, buttonTitle: String?, buttonAction:(()->Void)?) {
        var dialog = EasyDialog.Builder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        dialog = dialog.addButton(title: buttonTitle != nil ? buttonTitle! : NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
            if let buttonAction = buttonAction {
                buttonAction()
            }
            dialog.dismiss(animated: false, completion: nil)
        })
        dialog.build().show()
    }
    
    @objc public static func httpGet(url: URL, successAction:((Data)->Void)?, failedAction:((Error?)->Void)?){
        let session: URLSession = URLSession.shared
        DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async {
            session.dataTask(with: url) { data, response, error in
                if let data = data, let response = response as? HTTPURLResponse {
                    if Int(response.statusCode / 100) % 10 == 2 {
                        if let successAction = successAction {
                            successAction(data)
                            return
                        }
                    }
                }
                if let failedAction = failedAction {
                    failedAction(error)
                }
            }.resume()
        }
    }
    
    // cachedHTTPGet で使われるキャッシュの情報
    struct dataCache {
        var data: Data?
        let cachedDate: Date
        var error: Error?
    }
    // cachedHTTPGet のキャッシュ
    static var httpCache = Dictionary<URL,dataCache>()

    // 今から指定したTimeInterval時間前より新しいデータをキャッシュしていたなら、特に何にもアクセスせずにそれを返します。
    // キャッシュはメモリを使うのでちと微妙です。
    @objc public static func cashedHTTPGet(url: URL, delay: TimeInterval, successAction:((Data)->Void)?, failedAction:((Error?)->Void)?){
        if let cache = httpCache[url] {
            if cache.cachedDate < Date(timeIntervalSinceNow: delay) {
                if let data = cache.data {
                    if let successAction = successAction {
                        successAction(data)
                    }
                }else{
                    if let failedAction = failedAction {
                        failedAction(cache.error)
                    }
                }
                return
            }
        }
        NiftyUtilitySwift.httpGet(url: url, successAction: { (data) in
            let cache = dataCache(data: data, cachedDate: Date(timeIntervalSinceNow: 0), error: nil)
            httpCache[url] = cache
            if let successAction = successAction {
                successAction(data)
            }
        }, failedAction: { (error) in
            let cache = dataCache(data: nil, cachedDate: Date(timeIntervalSinceNow: 0), error: error)
            httpCache[url] = cache
            if let failedAction = failedAction {
                failedAction(error)
            }
        })
    }
}
