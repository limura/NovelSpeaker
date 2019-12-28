//
//  SampleUrlFetcher.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/19.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import PDFKit
import RealmSwift
import UserNotifications

class NiftyUtilitySwift: NSObject {
    static let textCountSeparatorArray:[String] = ["[[改ページ]]", "[改ページ]", "［＃改ページ］", "［＃改丁］", "\n\n\n", "\r\n\r\n\r\n", "\r\r\r"]
    
    // 分割すべき大きさで、分割できそうな文字列であれば分割して返します
    static func CheckShouldSeparate(text:String) -> [String]? {
        var separated:[String] = [text]
        for separator in textCountSeparatorArray {
            var newSeparated:[String] = []
            for text in separated {
                newSeparated.append(contentsOf: text.components(separatedBy: separator))
            }
            separated = newSeparated
        }
        print("separated.count: \(separated.count)")
        if separated.count > 1 {
            return separated
        }
        return nil
    }
    
    static var toplevelViewController:UIViewController? = nil
    @objc static func RegisterToplevelViewController(viewController:UIViewController?) {
        toplevelViewController = viewController
    }
    @objc static func GetRegisterdToplevelViewController() -> UIViewController? {
        return toplevelViewController
    }
    
    @objc public static func checkTextImportConifirmToUser(viewController: UIViewController, title: String, content: String, hintString: String?){
        DispatchQueue.main.async {
            var easyDialog = EasyDialogBuilder(viewController)
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
            easyDialog = easyDialog.addButton(title: NSLocalizedString("NiftyUtilitySwift_CancelImport", comment: "取り込まない"), callback: { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
            })
            easyDialog = easyDialog.addButton(title: NSLocalizedString("NiftyUtilitySwift_Import", comment: "このまま取り込む"), callback: { (dialog) in
                let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                let title = titleTextField.text ?? title
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
                RealmNovel.AddNewNovelOnlyText(content: content, title: title)
            })
            if let separatedText = CheckShouldSeparate(text: content), separatedText.reduce(0, { (result, body) -> Int in
                return result + (body.count > 0 ? 1 : 0)
            }) > 1 {
                easyDialog = easyDialog.addButton(title: NSLocalizedString("NiftyUtilitySwift_ImportSeparatedContent", comment: "テキトーに分割して取り込む"), callback: { (dialog) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                    RealmNovel.AddNewNovelWithMultiplText(contents: separatedText, title: title)
                })
            }
            easyDialog.build().show()
        }

    }
    
    public static func checkUrlAndConifirmToUser(viewController: UIViewController, url: URL, cookieArray: [String], depth: Int = 0, prevHtmlStoryArray:[HtmlStory?] = []) {
        BehaviorLogger.AddLog(description: "checkUrlAndConifirmToUser called.", data: ["url": url.absoluteString])
        DispatchQueue.main.async {
            let builder = EasyDialogBuilder(viewController)
            .text(content: NSLocalizedString("ImportFromWebPageViewController_loading", comment: "loading"))
            let dialog = builder.build()
            dialog.show {
                let uriLoader = NovelDownloadQueue.shared.createUriLoader()
                uriLoader.fetchOneUrl(url, cookieArray: cookieArray, successAction: { (story: HtmlStory?) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            // firstPageLink があった場合はそっちを読み直します
                            if let firstPageLink = story?.firstPageLink {
                                // ただし、depth が 5 を越えたら読み直さず先に進みます
                                if depth < 5 {
                                    NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: viewController, url: firstPageLink, cookieArray: cookieArray, depth: depth+1, prevHtmlStoryArray: prevHtmlStoryArray + [story])
                                    return
                                }
                            }
                            guard let content = story?.content, content.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
                                DispatchQueue.main.async {
                                    EasyDialogBuilder(viewController)
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
                                if (story?.nextUrl) != nil {
                                    multiPageString = NSLocalizedString("NiftyUtilitySwift_FollowingPageAreAvailable", comment: "続ページ：有り")
                                }
                                var titleString = NSLocalizedString("NiftyUtilitySwift_TitleUnknown", comment: "不明なタイトル")
                                if let title = story?.title {
                                    titleString = title
                                }else{
                                    for story in prevHtmlStoryArray {
                                        if let title = story?.title {
                                            titleString = title
                                            break
                                        }
                                    }
                                }
                                var builder = EasyDialogBuilder(viewController)
                                builder = builder.textField(tag: 100, placeholder: titleString, content: titleString, keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect)
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
                                builder = builder.addButton(title: NSLocalizedString("NiftyUtilitySwift_Import", comment: "このまま取り込む"), callback: { (dialog) in
                                        let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                                        let titleString = titleTextField.text ?? titleString
                                        DispatchQueue.main.async {
                                            dialog.dismiss(animated: false, completion: nil)
                                        }
                                        let cookieParameter = cookieArray.joined(separator: ";")
                                        if let story = story {
                                            var topUrl = url
                                            var author = story.author
                                            var keywordSet = Set<String>()
                                            for key in story.keyword {
                                                if let key = key as? String {
                                                    keywordSet.insert(NovelSpeakerUtility.CleanTagString(tag: key))
                                                }
                                            }
                                            for prevStory in prevHtmlStoryArray {
                                                if let urlString = prevStory?.url, let url = URL(string: urlString) {
                                                    // こうやって topUrl を上書きしていくと、最後にダウンロードしたURLよりも、その一つ前にダウンロードしたものが優先されるようになる
                                                    topUrl = url
                                                }
                                                let prevAuthor = story.author.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if prevAuthor.count > 0 {
                                                    author = prevAuthor
                                                }
                                                if let prevStoryKeywords = prevStory?.keyword {
                                                    for key in prevStoryKeywords {
                                                        if let key = key as? String {
                                                            keywordSet.insert(NovelSpeakerUtility.CleanTagString(tag: key))
                                                        }
                                                    }
                                                }
                                            }
                                            if let novelID = RealmNovel.AddNewNovelWithFirstStory(url: topUrl, htmlStory: story, cookieParameter: cookieParameter, title: titleString, author: author, tagArray: Array(keywordSet), firstContent: content){
                                                NovelDownloadQueue.shared.addQueue(novelID: novelID)
                                                DispatchQueue.main.async {
                                                    if let floatingButton = FloatingButton.createNewFloatingButton() {
                                                        floatingButton.assignToView(view: viewController.view, text: NSLocalizedString("NiftyUtilitySwift_AddNewNovelToBookshelfTitle", comment: "本棚に小説を追加しました"), animated: true, buttonClicked: {})
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                                                            floatingButton.hideAnimate()
                                                        })
                                                    }else{
                                                        NiftyUtilitySwift.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("NiftyUtilitySwift_AddNewNovelToBookshelfTitle", comment: "本棚に小説を追加しました"), message: NSLocalizedString("NiftyUtilitySwift_AddNewNovelToBookshelfMessage", comment: "続く章があればダウンロードを続けます。"), buttonTitle: nil, buttonAction: nil)
                                                    }
                                                }
                                            }else{
                                                DispatchQueue.main.async {
                                                    NiftyUtilitySwift.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("NiftyUtilitySwift_FailedAboutAddNewNovelFromWithStoryTitle", comment: "小説の本棚への追加に失敗しました。"), message: NSLocalizedString("NiftyUtilitySwift_FailedAboutAddNewNovelFromWithStoryMessage", comment: "既に登録されている小説などの原因が考えられます。"), buttonTitle: nil, buttonAction: nil)
                                                }
                                            }
                                        }
                                    })
                                if story?.nextUrl == nil, let separatedText = CheckShouldSeparate(text: content), separatedText.reduce(0, { (result, body) -> Int in
                                    return result + (body.count > 0 ? 1 : 0)
                                }) > 1 {
                                    builder = builder.addButton(title: NSLocalizedString("NiftyUtilitySwift_ImportSeparatedContent", comment: "テキトーに分割して取り込む"), callback: { (dialog) in
                                        let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                                        let titleString = titleTextField.text ?? titleString
                                        DispatchQueue.main.async {
                                            dialog.dismiss(animated: false, completion: nil)
                                        }
                                        RealmNovel.AddNewNovelWithMultiplText(contents: separatedText, title: titleString)
                                    })
                                }
                                builder.build().show()
                            }
                        })
                    }
                }, failedAction: { (url:URL?, error:String?) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            var errorMessage = NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfTitle", comment: "不明なエラー")
                            if let err = error {
                                errorMessage = err
                            }
                            NiftyUtilitySwift.EasyDialogMessageDialog(viewController: viewController, title: NSLocalizedString("NiftyUtilitySwift_ImportError", comment: "取り込み失敗"), message: errorMessage, completion: nil)
                        })
                    }
                })
            }
        }
    }
    
    @available(iOS 11.0, *)
    static func PDFToStringArray(pdf:PDFDocument) -> [String] {
        var result:[String] = []
        var index = 0
        while let page = pdf.page(at: index) {
            if let pageText = page.string {
                print("PDF page: ", pageText)
                result.append(pageText)
            }
            index += 1
        }
        return result
    }
    
    @objc public static func BinaryPDFToString(data: Data) -> String? {
        if #available(iOS 11.0, *) {
            guard let pdf = PDFDocument(data: data) else { return nil }
            let stringArray = PDFToStringArray(pdf: pdf)
            if stringArray.count > 0 {
                return stringArray.joined(separator: "\n\n\n")
            }
        }
        return nil
    }
    
    @objc public static func FilePDFToString(url: URL) -> String? {
        if #available(iOS 11.0, *) {
            guard let pdf = PDFDocument(url: url) else { return nil }
            let stringArray = PDFToStringArray(pdf: pdf)
            if stringArray.count > 0 {
                return stringArray.joined(separator: "\n\n\n")
            }
        }
        return nil
    }
    
    @objc public static func FileRTFToAttributedString(url: URL) -> NSAttributedString? {
        do {
            let attributedString = try NSAttributedString(url: url, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return attributedString
        }catch let error{
            print("AttributedString from RTF failed. error: ", error)
        }
        return nil
    }
    @objc public static func FileRTFDToAttributedString(url: URL) -> NSAttributedString? {
        do {
            let attributedString = try NSAttributedString(url: url, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)
            return attributedString
        }catch let error{
            print("AttributedString from RTFD failed. error: ", error)
        }
        return nil
    }
    
    public static func searchToplevelViewController(targetViewController: UIViewController) -> UIViewController {
        var currentViewController = targetViewController
        while let parent = currentViewController.parent {
            currentViewController = parent
        }
        return currentViewController
    }
    
    public static func EasyDialogBuilder(_ viewController: UIViewController) -> EasyDialog.Builder {
        return EasyDialog.Builder(searchToplevelViewController(targetViewController: viewController))
    }
    
    @discardableResult
    @objc public static func EasyDialogNoButton(viewController: UIViewController, title: String?, message: String?, completion:((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left, tag: 100)
        }
        let builded = dialog.build()
        builded.show {
            completion?(builded)
        }
        return builded
    }
    
    @discardableResult
    @objc public static func EasyDialogMessageDialog(viewController: UIViewController, message: String, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        return EasyDialogOneButton(viewController: viewController, title: nil, message: message, buttonTitle: nil, buttonAction: nil, completion: completion)
    }
    
    @discardableResult
    @objc public static func EasyDialogLongMessageDialog(viewController: UIViewController, message: String, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        let dialog = EasyDialogBuilder(viewController)
            .textView(content: message, heightMultiplier: 0.7)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
                dialog.dismiss(animated: false, completion: nil)
            }
            .build()
        dialog.show { completion?(dialog) }
        return dialog
    }

    @discardableResult
    @objc public static func EasyDialogOneButton(viewController: UIViewController, title: String?, message: String?, buttonTitle: String?, buttonAction:(()->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        dialog = dialog.addButton(title: buttonTitle != nil ? buttonTitle! : NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                if let buttonAction = buttonAction {
                    buttonAction()
                }
            })
        })
        let builded = dialog.build()
        builded.show { completion?(builded) }
        return builded
    }
    
    @discardableResult
    @objc public static func EasyDialogTwoButton(viewController: UIViewController, title: String?, message: String?, button1Title: String?, button1Action:(()->Void)?, button2Title: String?, button2Action:(()->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        dialog = dialog.addButton(title: button1Title != nil ? button1Title! : NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                if let button1Action = button1Action {
                    button1Action()
                }
            })
        })
        dialog = dialog.addButton(title: button2Title != nil ? button2Title! : NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                if let button2Action = button2Action {
                    button2Action()
                }
            })
        })
        let builded = dialog.build()
        builded.show { completion?(builded) }
        return builded
    }
    
    @discardableResult
    @objc public static func EasyDialogForButton(viewController: UIViewController, title: String?, message: String?, button1Title: String?, button1Action:(()->Void)?, button2Title: String?, button2Action:(()->Void)?, button3Title: String?, button3Action:(()->Void)?, button4Title: String?, button4Action:(()->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        if let button1Title = button1Title, button1Title.count > 0 {
            dialog = dialog.addButton(title: button1Title, callback: { (dialog) in
                dialog.dismiss(animated: false, completion: {
                    button1Action?()
                })
            })
        }
        if let button2Title = button2Title, button2Title.count > 0 {
            dialog = dialog.addButton(title: button2Title, callback: { (dialog) in
                dialog.dismiss(animated: false, completion: {
                    button2Action?()
                })
            })
        }
        dialog = dialog.addButton(title: button3Title != nil ? button3Title! : NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                button3Action?()
            })
        })
        dialog = dialog.addButton(title: button4Title != nil ? button4Title! : NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                button4Action?()
            })
        })
        let builded = dialog.build()
        builded.show { completion?(builded) }
        return builded
    }
    
    @objc public static func EasyDialogTextInput(viewController: UIViewController, title: String?, message: String?, textFieldText: String?, placeHolder: String?, action:((String)->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        let builded = dialog.textField(tag: 100, placeholder: placeHolder, content: textFieldText, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .none, clearButtonMode: .always)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
                dialog.dismiss(animated: false, completion: {
                    if let action = action {
                        let filterTextField = dialog.view.viewWithTag(100) as! UITextField
                        let newFilterString = filterTextField.text ?? ""
                        action(newFilterString)
                    }
                })
            }.build()
        builded.show { completion?(builded) }
    }
    
    @objc public static func EasyDialogTextInput2Button(viewController: UIViewController, title: String?, message: String?, textFieldText: String?, placeHolder: String?, leftButtonText: String?, rightButtonText: String?, leftButtonAction:((String)->Void)?, rightButtonAction:((String)->Void)?, shouldReturnIsRightButtonClicked:Bool = false, completion: ((_ dialog:EasyDialog)->Void)? = nil) {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        dialog = dialog.textField(tag: 100, placeholder: placeHolder, content: textFieldText, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .none, clearButtonMode: .always, shouldReturnEventHandler:{ (dialog) in
            if shouldReturnIsRightButtonClicked {
                dialog.dismiss(animated: false) {
                    if let action = rightButtonAction {
                        let filterTextField = dialog.view.viewWithTag(100) as! UITextField
                        let newFilterString = filterTextField.text ?? ""
                        action(newFilterString)
                    }
                }
            }
        })
        if let leftButtonText = leftButtonText {
            dialog = dialog.addButton(title: leftButtonText, callback: { (dialog) in
                dialog.dismiss(animated: false) {
                    if let action = leftButtonAction {
                        let filterTextField = dialog.view.viewWithTag(100) as! UITextField
                        let newFilterString = filterTextField.text ?? ""
                        action(newFilterString)
                    }
                }
            })
        }
        if let rightButtonText = rightButtonText {
            dialog = dialog.addButton(title: rightButtonText, callback: { (dialog) in
                dialog.dismiss(animated: false) {
                    if let action = rightButtonAction {
                        let filterTextField = dialog.view.viewWithTag(100) as! UITextField
                        let newFilterString = filterTextField.text ?? ""
                        action(newFilterString)
                    }
                }
            })
        }
        let builded = dialog.build()
        builded.show { completion?(builded) }
    }
    @objc public static func EasyDialogMessageDialog(viewController: UIViewController, title: String?, message: String?, completion:(()->Void)?) {
        var builder = EasyDialogBuilder(viewController)
        if let title = title {
            builder = builder.title(title: title)
        }
        if let message = message {
            builder = builder.textView(content: message, heightMultiplier: 0.6)
        }
        builder.addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
            dialog.dismiss(animated: false) {
                completion?()
            }
        }.build().show()
    }

    @objc public static func httpGet(url: URL, successAction:((Data)->Void)?, failedAction:((Error?)->Void)?){
        let session: URLSession = URLSession.shared
        DispatchQueue.global(qos: .utility).async {
            session.dataTask(with: url) { data, response, error in
                if let data = data, let response = response as? HTTPURLResponse, Int(response.statusCode / 100) % 10 == 2, let successAction = successAction {
                    successAction(data)
                    return
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
    
    /// 指定された文字列がフォント名として正しいか否かを判定します
    @objc public static func isValidFontName(fontName: String) -> Bool {
        for familyName in UIFont.familyNames.sorted() {
            for currentFontName in UIFont.fontNames(forFamilyName: familyName).sorted() {
                if currentFontName == fontName {
                    return true
                }
            }
        }
        return false
    }
    
    static func sleep(second:TimeInterval) {
        Thread.sleep(forTimeInterval: second)
        //RunLoop.current.run(mode: .defaultRunLoopMode, before: Date(timeIntervalSinceNow: second))
    }
    
    static let backgroundQueue = DispatchQueue(label: "com.limuraproducts.novelspeaker.backgroundqueue", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
    /// 怪しく background で回しつつ終了を待ちます(ただ、コレを使おうと思う場合はなにかおかしいと思ったほうが良さそうです)
    public static func backgroundAndWait(block:(()->Void)?) {
        guard let block = block else {
            return
        }
        let dispatchSemaphore = DispatchSemaphore(value: 0)
        NiftyUtilitySwift.backgroundQueue.asyncAfter(deadline: .now() + 0.05) {
            block()
            dispatchSemaphore.signal()
        }
        while dispatchSemaphore.wait(timeout: DispatchTime.now()) == DispatchTimeoutResult.timedOut {
            NiftyUtilitySwift.sleep(second: 0.1)
        }
    }
    
    // バイト数(例えば 4096)から "4.00[KBytes]" みたいな文字列に変換します
    public static func ByteSizeToVisibleString(byteSize:Int) -> String {
        let unitArray = ["Byte", "KByte", "MByte", "GByte", "TByte", "PByte"]
        var unitCount = 0
        var currentSizeUnit = byteSize
        var currentRemainder = 0
        while currentSizeUnit > 1024 {
            currentRemainder = currentSizeUnit % 1024
            currentSizeUnit /= 1024
            unitCount += 1
            if unitArray.count <= unitCount {
                break
            }
        }
        let answer = Float(currentSizeUnit * 1024 + currentRemainder) / 1024.0
        var s = ""
        if answer > 1 {
            s = "s"
        }
        return String(format: "%.2f[%@%@]", answer, unitArray[unitCount], s)
    }
    
    @objc public static func Date2EpochSecond(date:Date) -> UInt {
        return UInt(date.timeIntervalSince1970)
    }
    @objc public static func EpochSecond2Date(second:UInt) -> Date {
        return Date.init(timeIntervalSince1970: TimeInterval(second))
    }
    // ISO-8601 形式っぽい文字列を Date に変換する。失敗すると nil を返す。
    // ISO-8601 の一部にしか対応してない。
    // 例えばタイムゾーン部分は Z と +0900 みたいなのは対応しているけれど、+09:00 には対応していない
    // (そっちに対応するなら Z 一文字じゃなくて ZZZZZ と Zを5文字にしないと駄目なんだけれど
    // そうすると +0900 (":"が無い)に対応できない)
    // 同様に yyyy-MM... と "-" の入った拡張表記が強制であったり、MM や dd を省く形式にも対応していない。
    // YYYY-Www-D のような週の記述にも対応していない。
    // 時刻の hh:mm, hh のような省略形式にも対応していない。
    // 11:30:30,5 といった1秒未満の値も対応していない。当然 11,5 (11時半) という表記も対応していない。
    @objc public static func Date2ISO8601String(date:Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.string(from:date)
    }
    @objc public static func ISO8601String2Date(iso8601String:String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.date(from: iso8601String)
    }
    
    @objc public static func RestoreBackupFromJSONWithProgressDialog(jsonData:Data, dataDirectory:URL?, rootViewController:UIViewController){
        let globalDataSingleton = GlobalDataSingleton.getInstance()
        var builder = EasyDialogBuilder(rootViewController)
        NiftyUtilitySwift.DispatchSyncMainQueue {
            builder = builder.label(text: NSLocalizedString("NovelSpeakerBackup_Restoreing", comment: "バックアップより復元"), textAlignment: .center, tag: 100)
            let dialog = builder.build()
            dialog.show()
            
            DispatchQueue.global(qos: .background).async {
                let result = globalDataSingleton?.restoreBackup(fromJSONData: jsonData, dataDirectory: dataDirectory, progress: { (progressText) in
                    DispatchQueue.main.async {
                        if let label = dialog.view.viewWithTag(100) as? UILabel, let progressText = progressText{
                            label.text = NSLocalizedString("NovelSpeakerBackup_Restoreing", comment: "バックアップより復元")
                            + "\r\n" + progressText
                        }
                    }
                })
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        if result == true {
                            EasyDialogBuilder(rootViewController)
                            .label(text: NSLocalizedString("GlobalDataSingleton_BackupDataLoaded", comment:"設定データを読み込みました。ダウンロードされていた小説については現在ダウンロード中です。すべての小説のダウンロードにはそれなりの時間がかかります。"), textAlignment: .center)
                            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                dialog.dismiss(animated: false, completion: nil)
                            })
                            .build().show()
                        }else{
                            EasyDialogBuilder(rootViewController)
                            .label(text: NSLocalizedString("GlobalDataSingleton_RestoreBackupDataFailed", comment:"設定データの読み込みに失敗しました。"), textAlignment: .center)
                            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                                dialog.dismiss(animated: false, completion: nil)
                            })
                            .build().show()
                        }
                    })
                }
            }
        }
    }
    
    @objc static public func DispatchSyncMainQueue(block:(()->Void)?) -> Void {
        guard let block = block else {
            return
        }
        if Thread.isMainThread {
            block()
        }else{
            DispatchQueue.main.sync {
                block()
            }
        }
    }
    
    @objc static public func GetAppVersionString() -> String {
        var appVersionString = "*"
        if let infoDictionary = Bundle.main.infoDictionary, let bundleVersion = infoDictionary["CFBundleVersion"] as? String, let shortVersion = infoDictionary["CFBundleShortVersionString"] as? String {
            appVersionString = String.init(format: "%@(%@)", shortVersion, bundleVersion)
        }
        return appVersionString
    }
    
    static let USER_DEFAULTS_LAST_READ_IMPORTANT_INFORMATION_TEXT = "UserDefaultsLastReadImportantInformationText"
    static let IMPORTANT_INFORMATION_TEXT_URL = "https://limura.github.io/NovelSpeaker/ImportantInformation.txt"
    @objc static public func FetchNewImportantImformation(fetched:@escaping ((_ text:String, _ holeText:String)->Void), err:(()->Void)?) {
        guard let url = URL(string: IMPORTANT_INFORMATION_TEXT_URL) else { return }
        cashedHTTPGet(url: url, delay: 60*60*6, successAction: { (data) in
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            var stripedText = ""
            text.enumerateLines(invoking: { (line, inOut) in
                if line.count > 0 && line[line.startIndex] != "#" {
                    stripedText += line + "\n"
                }
            })
            fetched(stripedText, text)
        }) { (error) in
            err?()
        }
    }
    @objc static public func CheckNewImportantImformation(hasNewInformationAlive:@escaping ((_ text:String)->Void), hasNoNewInformation:(()->Void)?) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [USER_DEFAULTS_LAST_READ_IMPORTANT_INFORMATION_TEXT: ""])
        guard let lastReadInformationText = defaults.string(forKey: USER_DEFAULTS_LAST_READ_IMPORTANT_INFORMATION_TEXT) else { return }
        FetchNewImportantImformation(fetched: { (text, holeText) in
            if lastReadInformationText != text {
                hasNewInformationAlive(text)
            }else{
                hasNoNewInformation?()
            }
        }) {
            hasNoNewInformation?()
        }
    }
    @objc static public func SaveCheckedImportantInformation(text:String) {
        let defaults = UserDefaults.standard
        defaults.set(text, forKey: USER_DEFAULTS_LAST_READ_IMPORTANT_INFORMATION_TEXT)
    }
    
    @objc static public func getLogText(searchString:String?) -> String {
        let logStringArray = GlobalDataSingleton.getInstance().getLogStringArray()
        var logResult = ""
        for logString in logStringArray! {
            guard let logString = logString as? String else {
                continue
            }
            if let searchString = searchString {
                if searchString.count > 0 {
                    if !logString.contains(searchString) {
                        continue
                    }
                }
            }
            logResult += logString + "\r\n"
        }
        return logResult
    }
    
    static public func Share(message:String, viewController:UIViewController, barButton:UIBarButtonItem?) {
        let activityViewController = UIActivityViewController.init(activityItems: [message], applicationActivities: nil)
        
        if let barButton = barButton {
            activityViewController.popoverPresentationController?.barButtonItem = barButton;
        }else{
            let frame = UIScreen.main.bounds
            activityViewController.popoverPresentationController?.sourceView = viewController.view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.midX - 60, y: frame.size.height - 50, width: 120, height: 50)
        }
        viewController.present(activityViewController, animated: true, completion: nil)
    }
    
    @objc static public func IsEscapeAboutSpeechPositionDisplayBugOniOS12Enabled() -> Bool {
        return autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else {
                return false
            }
            return globalState.isEscapeAboutSpeechPositionDisplayBugOniOS12Enabled
        }
    }
    
    static public func GetCacheFilePath(fileName:String) -> URL? {
        guard let path = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first else { return nil }
        var urlPath = URL(fileURLWithPath: path)
        urlPath.appendPathComponent(fileName)
        return urlPath
    }
    static public func GetTemporaryFilePath(fileName:String) -> URL {
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(fileName)
    }
    static public func CreateTemporaryDirectory(directoryName:String) -> URL? {
        let tmpDir = NSTemporaryDirectory()
        let result = URL(fileURLWithPath: tmpDir).appendingPathComponent(directoryName, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: result.path, withIntermediateDirectories: true, attributes: nil)
        }catch{
            print("can not create directory: \(result.path)")
            return nil
        }
        return result
    }
    static public func CreateDirectoryFor(path:URL, directoryName:String) -> URL? {
        let result = path.appendingPathComponent(directoryName, isDirectory: true)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: result.path, withIntermediateDirectories: true, attributes: nil)
        }catch{
            print("can not create directory: \(result.path)")
            return nil
        }
        return result
    }
    static public func RemoveDirectory(directoryPath:URL) {
        do {
            try FileManager.default.removeItem(at: directoryPath)
        }catch{
            // nothing to do!
        }
    }
    
    static public func FileCachedHttpGet_RemoveCacheFile(cacheFileName:String) {
        guard let cacheFilePath = GetCacheFilePath(fileName: cacheFileName) else { return }
        do {
            try FileManager.default.removeItem(at: cacheFilePath)
        }catch{
            // nothing to do!
        }
    }
    
    static public func FileCachedHttpGet(url: URL, cacheFileName:String, expireTimeinterval:TimeInterval, successAction:((Data)->Void)?, failedAction:((Error?)->Void)?) {
        if let cacheFilePath = GetCacheFilePath(fileName: cacheFileName),
            FileManager.default.fileExists(atPath: cacheFilePath.path),
            let attribute = try? FileManager.default.attributesOfItem(atPath: cacheFilePath.path),
            let modificationDate = attribute[FileAttributeKey.modificationDate] as? Date,
            (Date().timeIntervalSince1970 - modificationDate.timeIntervalSince1970) < expireTimeinterval,
            let successAction = successAction,
            let dataZiped = try? Data(contentsOf: cacheFilePath),
            let data = NiftyUtility.dataInflate(dataZiped) {
            successAction(data)
            return
        }
        httpGet(url: url, successAction: { (data) in
            if let cacheFilePath = GetCacheFilePath(fileName: cacheFileName), let dataZiped = NiftyUtility.dataDeflate(data, level: 9) {
                do {
                    try dataZiped.write(to: cacheFilePath, options: Data.WritingOptions.atomic)
                }catch{
                    print("cache file write error. for url: \(url.absoluteString)")
                }
            }
            if let successAction = successAction {
                successAction(data)
            }
        }) { (err) in
            guard let failedAction = failedAction else { return }
            failedAction(err)
        }
    }
    
    static let PreviousTimeVersionKey = "NovelSpeaker_PreviousTimeVersion"
    // 前回実行時とくらべてビルド番号が変わっているか否かを取得します
    static func IsVersionUped() -> Bool {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [PreviousTimeVersionKey : "unknown"])
        let currentVersion = GetAppVersionString()
        guard let previousVersion = defaults.string(forKey: PreviousTimeVersionKey) else { return true }
        return currentVersion != previousVersion
    }
    // 保存されている「前回起動時のバージョン番号」を現在のバージョン番号に更新します
    static func UpdateCurrentVersionSaveData() {
        let defaults = UserDefaults.standard
        let currentVersion = GetAppVersionString()
        defaults.set(currentVersion, forKey: PreviousTimeVersionKey)
    }
    
    // 通知の許可をユーザに願い出る
    static func RegisterUserNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .alert]) { (granted, err) in
            //
        }
    }
    
    static func GetToplevelViewController(controller:UIViewController?) -> UIViewController? {
        guard let view = controller else {
            if let viewController = GetRegisterdToplevelViewController() {
                return GetToplevelViewController(controller: viewController)
            }
            if let viewController = UIApplication.shared.keyWindow?.rootViewController {
                return GetToplevelViewController(controller: viewController)
            }
            return nil
        }
        if let tabBarController = view as? UITabBarController {
            return GetToplevelViewController(controller: tabBarController.selectedViewController)
        }
        if let navigationController = view as? UINavigationController {
            return GetToplevelViewController(controller: navigationController.visibleViewController)
        }
        if let presentedViewController = view.presentedViewController, presentedViewController.isBeingDismissed == false {
            return GetToplevelViewController(controller: presentedViewController)
        }
        return view;
    }
    
    // https://qiita.com/mosson/items/c4c329d433d99e3583ec
    static func DetectEncoding(data:Data) -> String.Encoding {
        let encoding:String.Encoding = .utf8
        let targetEncodings:[String.Encoding] = [
            .utf8,
            .nonLossyASCII,
            .japaneseEUC,
            .macOSRoman,
            .windowsCP1251,
            .windowsCP1252,
            .windowsCP1253,
            .windowsCP1254,
            .windowsCP1250,
            .isoLatin1,
            .unicode
        ]
        
        if data.contains(0x1b) {
            if String(data: data, encoding: .iso2022JP) != nil {
                return .iso2022JP
            }
        }
        for targetEncoding in targetEncodings {
            if String(data: data, encoding: targetEncoding) != nil {
                return targetEncoding
            }
        }
        return encoding
    }
    
    static func RunLoopSleep(deltaSecond:TimeInterval) {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: deltaSecond))
    }
    
    static func FindRubyNotation(text:String) -> [String:String] {
        let targetRegexpArray = [
            "\\|([^|《(（]+?)[《(（]([^》)）]+?)[》)）]", // | のある場合
            "\\｜([^｜《(（]+?)[《(（]([^》)）]+?)[》)）]", // ｜ のある場合
        ]
        var result:[String:String] = [:]
        for pattern in targetRegexpArray {
            guard let regexp = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regexp.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            guard matches.count >= 1 else { continue }
            let match = matches[0]
            guard let beforeRange = Range(match.range(at: 1), in: text), let afterRange = Range(match.range(at: 2), in: text) else { continue}
            let before = String(text[beforeRange])
            let after = String(text[afterRange])
            result[before] = after
        }
        return result
    }
}
