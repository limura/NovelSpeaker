//
//  NiftyUtilitySwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/19.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift
import UserNotifications
import Kanna

#if !os(watchOS)
import PDFKit
import Erik
import MessageUI
#endif

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
    
    #if !os(watchOS)
    static var toplevelViewController:UIViewController? = nil
    @objc static func RegisterToplevelViewController(viewController:UIViewController?) {
        toplevelViewController = viewController
    }
    @objc static func GetRegisterdToplevelViewController() -> UIViewController? {
        return toplevelViewController
    }
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
    class DummyMailComposeViewController: NSObject, MFMailComposeViewControllerDelegate {
        static let shared = DummyMailComposeViewController()
        var currentViewController:UIViewController? = nil
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            currentViewController?.dismiss(animated: true, completion: nil)
        }
    }
    #endif

    #if !os(watchOS)
    static func checkUrlAndConifirmToUser_ErrorHandle(error:String, viewController:UIViewController, url: URL?, cookieString:String) {
        if MFMailComposeViewController.canSendMail() {
            var errorMessage = error
            errorMessage += NSLocalizedString("NiftyUtilitySwift_ImportError_SendProblemReportMessage", comment: "\n\n問題の起こった小説について開発者に送信する事もできます。ただし、この報告への返信は基本的には致しません。返信が欲しい場合には、「設定」→「開発者に問い合わせる」からお問い合わせください。")
            EasyDialogBuilder(viewController)
            .title(title: NSLocalizedString("NiftyUtilitySwift_ImportError", comment: "取り込み失敗"))
            .textView(content: errorMessage, heightMultiplier: 0.55)
            .addButton(title: NSLocalizedString("NiftyUtilitySwift_ImportError_SendProblemReportButton", comment: "報告メールを作成"), callback: { (dialog) in
                dialog.dismiss(animated: false) {
                    DispatchQueue.main.async {
                        let picker = MFMailComposeViewController()
                        //picker.mailComposeDelegate = self;
                        picker.setToRecipients(["limuraproducts@gmail.com"])
                        picker.setSubject(NSLocalizedString("NiftyUtilitySwift_ImportError_SendProblemReport_Mail_Title", comment:"ことせかい 取り込み失敗レポート"))
                        let messageBody = NSLocalizedString("NiftyUtilitySwift_ImportError_SendProblemReport_Mail_Body", comment:"このまま編集せずに送信してください。\nなお、このメールへの返信は基本的には行っておりません。\n\nエラーメッセージ:\n") + error
                        picker.setMessageBody(messageBody, isHTML: false)
                        let sendData:[String:String] = [
                            "url": url?.absoluteString ?? "-",
                            "cookie": cookieString
                        ]
                        if let data = try? JSONEncoder().encode(sendData) {
                            picker.addAttachmentData(data, mimeType: "application/json", fileName: "import_description.json")
                        }
                        DummyMailComposeViewController.shared.currentViewController = viewController
                        picker.mailComposeDelegate = DummyMailComposeViewController.shared
                        viewController.present(picker, animated: true, completion: nil)
                    }
                }
            })
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                dialog.dismiss(animated: false, completion: nil)
                })
            .build().show()
        }else{
            NiftyUtilitySwift.EasyDialogMessageDialog(viewController: viewController, title: NSLocalizedString("NiftyUtilitySwift_ImportError", comment: "取り込み失敗"), message: error, completion: nil)
        }
    }
    
    static func ImportStoryStateConifirmToUser(viewController:UIViewController, state:StoryState) {
        guard let content = state.content else {
            checkUrlAndConifirmToUser_ErrorHandle(error: NSLocalizedString("NiftyUtilitySwift_ImportStoryStateConifirmToUser_NoContent", comment: "本文がありませんでした。"), viewController: viewController, url: state.url, cookieString: state.cookieString ?? "")
            return
        }
        let titleString:String
        if let title = state.title {
            titleString = title
        }else{
            titleString = "-"
        }
        let multiPageString:String
        if state.IsNextAlive {
            multiPageString = NSLocalizedString("NiftyUtilitySwift_FollowingPageAreAvailable", comment: "続ページ：有り")
        }else {
            multiPageString = NSLocalizedString("NiftyUtilitySwift_FollowingPageAreNotAvailable", comment: "続ページ：無し")
        }
        DispatchQueue.main.async {
            var builder = EasyDialogBuilder(viewController)
            builder = builder.textField(tag: 100, placeholder: titleString, content: titleString, keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect)
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
                        
                        dialog.dismiss(animated: false, completion: {
                            guard let novelID = RealmNovel.AddNewNovelWithFirstStoryState(state:state.TitleChanged(title:titleString)) else {
                                DispatchQueue.main.async {
                                    NiftyUtilitySwift.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("NiftyUtilitySwift_FailedAboutAddNewNovelFromWithStoryTitle", comment: "小説の本棚への追加に失敗しました。"), message: NSLocalizedString("NiftyUtilitySwift_FailedAboutAddNewNovelFromWithStoryMessage", comment: "既に登録されている小説などの原因が考えられます。"), buttonTitle: nil, buttonAction: nil)
                                }
                                return
                            }
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
                        })
                    }
                })
            if state.IsNextAlive != true, let separatedText = CheckShouldSeparate(text: content), separatedText.reduce(0, { (result, body) -> Int in
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
    }
    
    public static func checkUrlAndConifirmToUser(viewController: UIViewController, url: URL, cookieString:String) {
        BehaviorLogger.AddLog(description: "checkUrlAndConifirmToUser called.", data: ["url": url.absoluteString])
        DispatchQueue.main.async {
            let builder = EasyDialogBuilder(viewController)
            .text(content: NSLocalizedString("ImportFromWebPageViewController_loading", comment: "loading"))
            let dialog = builder.build()
            let fetcher = StoryFetcher()
            dialog.show {
                fetcher.FetchFirstContent(url: url, cookieString: cookieString) { (url, state, errorString) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            if let state = state, (state.content?.count ?? 0) > 0 {
                                ImportStoryStateConifirmToUser(viewController: viewController, state: state)
                                return
                            }
                            checkUrlAndConifirmToUser_ErrorHandle(error: errorString ?? NSLocalizedString("NiftyUtilitySwift_CanNotAddToBookshelfTitle", comment: "不明なエラー"), viewController: viewController, url: url, cookieString: cookieString)
                        })
                    }
                }
            }
        }
    }
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    
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
    
    #if !os(watchOS)
    public static func searchToplevelViewController(targetViewController: UIViewController) -> UIViewController {
        var currentViewController = targetViewController
        while let parent = currentViewController.parent {
            currentViewController = parent
        }
        return currentViewController
    }
    #endif
    
    #if !os(watchOS)
    public static func EasyDialogBuilder(_ viewController: UIViewController) -> EasyDialog.Builder {
        return EasyDialog.Builder(searchToplevelViewController(targetViewController: viewController))
    }
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
    @discardableResult
    @objc public static func EasyDialogMessageDialog(viewController: UIViewController, message: String, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        return EasyDialogOneButton(viewController: viewController, title: nil, message: message, buttonTitle: nil, buttonAction: nil, completion: completion)
    }
    #endif
    
    #if !os(watchOS)
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
    #endif

    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
    static var headlessHttpClientObj:HeadlessHttpClient? = nil
    static func httpHeadlessRequest(url: URL, postData:Data? = nil, timeoutInterval:TimeInterval = 10, cookieString: String? = nil, mainDocumentURL:URL? = nil, httpClient:HeadlessHttpClient? = nil, successAction:((Document)->Void)? = nil, failedAction:((Error?)->Void)? = nil) {
        let allowsCellularAccess:Bool
        if let globalData = RealmGlobalState.GetInstance(), globalData.IsDisallowsCellularAccess {
            allowsCellularAccess = false
        }else{
            allowsCellularAccess = true
        }
        DispatchQueue.main.async {
            let client:HeadlessHttpClient
            if let httpClient = httpClient {
                client = httpClient
            }else if let staticClient = headlessHttpClientObj {
                client = staticClient
            }else{
                client = HeadlessHttpClient()
                headlessHttpClientObj = client
            }
            client.HttpRequest(url: url, postData: postData, timeoutInterval: timeoutInterval, cookieString: cookieString, mainDocumentURL: mainDocumentURL, allowsCellularAccess: allowsCellularAccess, successResultHandler: { (doc) in
                successAction?(doc)
            }) { (err) in
                failedAction?(err)
            }
        }
    }
    #endif
    
    static func GetMatchedText1(text:String, regexpPattern:String) -> String? {
        guard let regexp = try? NSRegularExpression(pattern: regexpPattern, options: []) else { return nil }
        guard let matchResult = regexp.firstMatch(in: text, options: [], range: NSMakeRange(0, text.count)) else { return nil }
        if matchResult.numberOfRanges <= 0 { return nil }
        let range = matchResult.range(at: 1)
        let fromIndex = text.index(text.startIndex, offsetBy: range.location)
        let toIndex = text.index(text.startIndex, offsetBy: range.location + range.length)
        return String(text[fromIndex..<toIndex])
    }
    
    static func getCharsetStringFromURLResponse(urlResponse:URLResponse?) -> String? {
        guard let httpURLResponse = urlResponse as? HTTPURLResponse else { return nil }
        guard let contentType = httpURLResponse.allHeaderFields.filter({ (element) -> Bool in
            if let key = element.key as? String, key.lowercased() == "content-type" {
                return true
            }
            return false
        }).first?.value as? String else { return nil }
        return GetMatchedText1(text: contentType, regexpPattern: "; *charset=([^ ]*)")
    }
    
    static func guessStringEncodingFrom(charset:String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        if cfEncoding != kCFStringEncodingInvalidId {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String.Encoding(rawValue: nsEncoding)
        }
        let encodingMap:[String:String.Encoding] = [
            "sjis": .shiftJIS,
            "shiftjis": .shiftJIS,
            "shift-jis": .shiftJIS,
            "shift_jis": .shiftJIS,
            "euc": .japaneseEUC,
            "euc-jp": .japaneseEUC,
            "euc_jp": .japaneseEUC,
            "japaneseeuc": .japaneseEUC,
            "iso-2022-jp": .iso2022JP,
            "utf8": .utf8,
            "utf-8": .utf8,
            "utf16": .utf16,
            "utf-16": .utf16,
            "utf32": .utf32,
            "utf-32": .utf32,
            "unicode": .unicode,
        ]
        return encodingMap[charset]
    }
    
    static func getStringEncodingFromURLResponse(urlResponse:URLResponse?) -> String.Encoding? {
        guard let charset = getCharsetStringFromURLResponse(urlResponse: urlResponse) else { return nil }
        return guessStringEncodingFrom(charset: charset)
    }
    
    static func decodeDataToStringWith(charset:String, data:Data) -> (String?, String.Encoding?) {
        guard let encoding = guessStringEncodingFrom(charset: charset) else { return (nil, nil) }
        guard let decodedString = String(data: data, encoding: encoding) else { return (nil, nil) }
        return (decodedString, encoding)
    }
    
    // Data を String に変換しようとしてみます。
    // charset がわかっているならそれをヒントに変換を試みます。
    // charset がわかっていないならテキトーに変換できそうかどうかを確認しながら変換します。
    static func tryDecodeToString(data:Data, charset:String?) -> (String?, String.Encoding?) {
        return tryDecodeToString(data: data, encoding: charset != nil ? guessStringEncodingFrom(charset: charset!) : nil)
    }

    static func tryDecodeToString(data:Data, encoding:String.Encoding?) -> (String?, String.Encoding?) {
        if let encoding = encoding, let string = String(data: data, encoding: encoding) {
            return (string, encoding)
        }
        let targetEncodingArray:[String.Encoding] = [.utf8, .japaneseEUC, .shiftJIS, .iso2022JP]
        for encoding in targetEncodingArray {
            if let string = String(data: data, encoding: encoding) {
                return (string, encoding)
            }
        }
        return (nil, nil)
    }
    
    // HTML内部に書かれている meta charset を取り出して String.Encoding にして返します
    static func getHTMLMetaEncoding(html:String) -> String.Encoding? {
        let metaTargetArray:[String] = [
            "content=[\"'].*?; *charset=(.*?)[\"']",
            "meta +charset=[\"'](.*?)[\"']",
        ]
        for metaPattern in metaTargetArray {
            if let charset = GetMatchedText1(text: html, regexpPattern: metaPattern), let encoding = guessStringEncodingFrom(charset: charset) {
                return encoding
            }
        }
        return nil
    }
    
    // とりあえず HTML の meta が読めるように decode された string から
    // meta を読み込んで charset があればそれを使って String を生成しようとします。
    static func decodeDataToStringUseHTMLMetaCharset(data:Data, charset:String?) -> (String?, String.Encoding?) {
        let (stringOptional, encoding) = tryDecodeToString(data: data, charset: charset)
        guard let string = stringOptional else { return (nil, nil) }
        let metaTargetArray:[String] = [
            "content=[\"'].*?; *charset=(.*?)[\"']",
            "meta +charset=[\"'](.*?)[\"']",
        ]
        for metaPattern in metaTargetArray {
            if let charset = GetMatchedText1(text: string, regexpPattern: metaPattern) {
                let (html, encoding) = decodeDataToStringWith(charset: charset, data: data)
                if let html = html {
                    print("encoding guessed: \(charset)")
                    return (html, encoding ?? .utf8)
                }
            }
        }
        return (nil, nil)
    }
    
    static func convertStringEncoding(data:Data, urlResponse:URLResponse?) -> (String?, String.Encoding?) {
        if let encoding = getCharsetStringFromURLResponse(urlResponse: urlResponse) {
            let (html, encoding) = decodeDataToStringWith(charset: encoding, data: data)
            if let html = html {
                // HTTP response に書かれていたencodingでちゃんとデコードできたのならそれで良しとする
                return (html, encoding)
            }
        }
        return tryDecodeToString(data: data, charset: nil)
    }
    
    //
    static func decodeHTMLStringFrom(data:Data, headerEncoding: String.Encoding?) -> (String?, String.Encoding?) {
        let (tmpStringOptional, firstEncoding) = tryDecodeToString(data: data, encoding: headerEncoding)
        guard let tmpString = tmpStringOptional else {
            return (nil, nil)
        }
        if let metaEncoding = getHTMLMetaEncoding(html: tmpString) {
            let (decodedHtml, encoding) = tryDecodeToString(data: data, encoding: metaEncoding)
            if let html = decodedHtml {
                return (decodedHtml, encoding ?? .utf8)
            }
        }
        return (tmpString, firstEncoding ?? .utf8)
    }
    
    public static func httpRequest(url: URL, postData:Data? = nil, timeoutInterval:TimeInterval = 10, cookieString:String? = nil, isNeedHeadless:Bool = false, mainDocumentURL:URL? = nil, allowsCellularAccess:Bool = true, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)? = nil, failedAction:((Error?)->Void)? = nil){
        #if !os(watchOS)
        if isNeedHeadless {
            httpHeadlessRequest(url: url, postData: postData, timeoutInterval: timeoutInterval, cookieString: cookieString, mainDocumentURL: mainDocumentURL, successAction: { (doc) in
                if let data = doc.innerHTML?.data(using: .utf8) {
                    successAction?(data, .utf8)
                    return
                }
            }, failedAction: failedAction)
            return
        }
        #endif
        let session: URLSession = URLSession.shared
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeoutInterval)
        if let postData = postData {
            request.httpMethod = "POST"
            request.httpBody = postData
        }
        if let cookieString = cookieString {
            request.addValue(cookieString, forHTTPHeaderField: "Cookie")
        }
        request.allowsCellularAccess = allowsCellularAccess
        request.mainDocumentURL = mainDocumentURL
        let requestID = "HTTPRequest" + url.absoluteString
        DispatchQueue.global(qos: .utility).async {
            #if !os(watchOS)
            ActivityIndicatorManager.enable(id: requestID)
            #endif
            session.dataTask(with: request) { data, response, error in
                #if !os(watchOS)
                ActivityIndicatorManager.disable(id: requestID)
                #endif
                if let response = response as? HTTPURLResponse {
                    var statusCodeDiv100:Int = response.statusCode / 100
                    statusCodeDiv100 %= 10
                    if statusCodeDiv100 != 2 {
                        failedAction?(SloppyError(msg:
                            String(format: NSLocalizedString("UriLoader_HTTPResponseIsInvalid", comment: "サーバから返されたステータスコードが正常値(200 OK等)ではなく、%ld を返されました。ログインが必要なサイトである場合などに発生する場合があります。ことせかい アプリ側でできることはあまり無いかもしれませんが、ことせかい のサポートサイトに設置してあります、ご意見ご要望フォームにこの問題の起こったURLとこの症状が起こった前にやったことを添えて報告して頂けると、あるいはなんとかできるかもしれません。"), response.statusCode)))
                        return
                    }
                }
                if let data = data {
                    successAction?(data, getStringEncodingFromURLResponse(urlResponse: response))
                    return
                }
                failedAction?(SloppyError(msg: String(format: NSLocalizedString("NiftyUtilitySwift_URLSessionRequestFailedAboutError", comment: "サーバからのデータの取得に失敗しました。(末尾に示されているエラー内容とエラーの起こったURLとエラーが起こるまでの操作手順を添えて、サポートサイト下部にありますご意見ご要望フォームか、設定→開発者に問い合わせるよりお問い合わせ頂けますと、あるいは何かできるかもしれません。\nエラー内容: %@)"), error?.localizedDescription ?? "unknown error(nil)")))
            }.resume()
        }
    }
    
    public static func httpGet(url: URL, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)?, failedAction:((Error?)->Void)?){
        httpRequest(url: url, postData: nil, successAction: successAction, failedAction: failedAction)
    }
    
    public static func httpPost(url: URL, data:Data, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)?, failedAction:((Error?)->Void)?){
        httpRequest(url: url, postData: data, successAction: successAction, failedAction: failedAction)
    }
    
    // cachedHTTPGet で使われるキャッシュの情報
    struct dataCache {
        var data: Data?
        let cachedDate: Date
        var error: Error?
        let encoding: String.Encoding?
    }
    // cachedHTTPGet のキャッシュ
    static var httpCache = Dictionary<URL,dataCache>()

    // 今から指定したTimeInterval時間前より新しいデータをキャッシュしていたなら、特に何にもアクセスせずにそれを返します。
    // キャッシュはメモリを使うのでちと微妙です。
    public static func cashedHTTPGet(url: URL, delay: TimeInterval, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)?, failedAction:((Error?)->Void)?){
        if let cache = httpCache[url] {
            if cache.cachedDate < Date(timeIntervalSinceNow: delay) {
                if let data = cache.data {
                    if let successAction = successAction {
                        successAction(data, cache.encoding)
                    }
                }else{
                    if let failedAction = failedAction {
                        failedAction(cache.error)
                    }
                }
                return
            }
        }
        NiftyUtilitySwift.httpGet(url: url, successAction: { (data, encoding) in
            let cache = dataCache(data: data, cachedDate: Date(timeIntervalSinceNow: 0), error: nil, encoding: encoding)
            httpCache[url] = cache
            if let successAction = successAction {
                successAction(data, encoding)
            }
        }, failedAction: { (error) in
            let cache = dataCache(data: nil, cachedDate: Date(timeIntervalSinceNow: 0), error: error, encoding: nil)
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
        cashedHTTPGet(url: url, delay: 60*60*6, successAction: { (data, encoding) in
            guard let text = String(bytes: data, encoding: encoding ?? .utf8) else { return }
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
    
    #if !os(watchOS)
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
    #endif
    
    #if !os(watchOS)
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
    #endif
    
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
        httpGet(url: url, successAction: { (data, encoding) in
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
    
    #if !os(watchOS)
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
    #endif
    
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

    /// 怪しく <ruby>xxx<rp>(</rp><rt>yyy</rt><rp>)</rt></ruby> や、<ruby>xxx<rt>yyy</rt></ruby> という文字列を
    /// |xxx(yyy) という文字列に変換します。
    /// つまり、xxx(yyy) となるはずのものを、|xxx(yyy) となるように変換するわけです。
    static let ConvertRubyTagToVerticalBarRubyText_ConvFromString = "<ruby>(<rb>)?([^<]+)\\s*(</rb>)?\\s*(<rp>[^<]*</rp>)?\\s*(<rt>[^<]+</rt>)\\s*(<rp>[^<]*</rp>)?</ruby>"
    static let ConvertRubyTagToVerticalBarRubyText_RegexpConvFrom = try? NSRegularExpression(pattern: ConvertRubyTagToVerticalBarRubyText_ConvFromString, options: [.caseInsensitive])
    static func ConvertRubyTagToVerticalBarRubyText(htmlString:String) -> String {
        let convTo = "|$1$2$3($5)"
        guard let regexp = ConvertRubyTagToVerticalBarRubyText_RegexpConvFrom else { return htmlString }
        return regexp.stringByReplacingMatches(in: htmlString, options: [], range: NSMakeRange(0, htmlString.count), withTemplate: convTo)
    }
    
    // HTML から String に変換する時に必要なくなるタグ等を削除します。
    static let RemoveNoNeedTagRegexpArray = [
        //try? NSRegularExpression(pattern: "<script.*?/script>", options: [.caseInsensitive, .dotMatchesLineSeparators]), // AttributedString に変換する場合、そちらで <script> は虫されるのでここで消しておく必要は多分ない
        try? NSRegularExpression(pattern: "<iframe.*?/iframe>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<link.*?>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<meta.*?>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<noscript.*?/noscript>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
    ]
    static func RemoveNoNeedTag(htmlString:String) -> String {
        var result = htmlString
        for regexp in RemoveNoNeedTagRegexpArray {
            guard let regexp = regexp else { continue }
            result = regexp.stringByReplacingMatches(in: result, options: [], range: NSMakeRange(0, result.count), withTemplate: "")
        }
        return result
    }
    
    static func HTMLDataToString(htmlData:Data, encoding:String.Encoding) -> String? {
        var result:String? = nil
        DispatchSyncMainQueue {
            if let attributedString = try? NSAttributedString(data: htmlData, options: [.documentType:NSAttributedString.DocumentType.html, .characterEncoding:encoding.rawValue], documentAttributes: nil) {
                result = attributedString.string
            }
        }
        return result
    }
    
    static func HTMLUtf8DataToString(htmlUtf8Data:Data) -> String? {
        return HTMLDataToString(htmlData: htmlUtf8Data, encoding: .utf8)
    }
    
    static func HTMLToString(htmlString:String) -> String? {
        let removeRubyed = ConvertRubyTagToVerticalBarRubyText(htmlString: htmlString)
        let removeNoUseTaged = RemoveNoNeedTag(htmlString: removeRubyed)
        guard let data = removeNoUseTaged.data(using: .utf8) else { return removeNoUseTaged }
        return HTMLUtf8DataToString(htmlUtf8Data: data)
    }
    
    static func FilterXpathToHtml(xmlDocument:XMLDocument, xpath:String) -> String {
        var resultHTML = ""
        for element in xmlDocument.xpath(xpath) {
            var elementXML = element.innerHTML ?? ""
            if let parent = element.parent, let parentTag = parent.tagName {
                if element.nextSibling == nil && element.previousSibling == nil {
                    elementXML = "<\(parentTag)>\(elementXML)</\(parentTag)>"
                }else if element.nextSibling == nil {
                    elementXML = "\(elementXML)</\(parentTag)>"
                }else if element.previousSibling == nil {
                    elementXML = "<\(parentTag)>\(elementXML)"
                }
            }
            resultHTML += elementXML
        }
        return resultHTML
    }
    
    static func FilterXpathWithConvertString(xmlDocument:XMLDocument, xpath:String, injectStyle:String? = nil) -> String {
        let filterdHTML = FilterXpathToHtml(xmlDocument: xmlDocument, xpath: xpath)
        let resultHTML:String
        if let injectStyle = injectStyle, injectStyle.count > 0 {
            resultHTML = "<style>" + injectStyle + "</style>" + filterdHTML
        }else{
            resultHTML = filterdHTML
        }
        if let result = HTMLToString(htmlString: resultHTML) {
            return result
        }
        return xmlDocument.xpath(xpath).reduce(""){ $0 + ($1.content ?? "") }
    }
    
    static func FilterXpathWithExtructFirstHrefLink(xmlDocument:XMLDocument, xpath:String, baseURL:URL) -> URL? {
        guard let urlNode = xmlDocument.xpath(xpath).first else { return nil }
        let urlString = urlNode["href"] ?? urlNode.content ?? ""
        return URL(string: urlString, relativeTo: baseURL)
    }
}
