//
//  NiftyUtility.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/19.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
// import RealmSwift にすると Erik の Document が
// Realm 10.* 以降の BSON.swiftで定義されてる Document とかち合ってしまうので、
// struct Realm だけを取り込む
import struct RealmSwift.Realm
import UserNotifications
import Kanna
import DataCompression
import StoreKit
import AVFoundation

#if !os(watchOS)
import PDFKit
import Erik
import MessageUI
#endif

class NiftyUtility: NSObject {
    // 分割すべき大きさで、分割できそうな文字列であれば分割して返します
    static func CheckShouldSeparate(text:String) -> [String]? {
        guard let realm = try? RealmUtil.GetRealm(), let textCountSeparatorArray = RealmGlobalState.GetInstanceWith(realm: realm)?.autoSplitStringList else { return nil }
        let text = NovelSpeakerUtility.NormalizeNewlineString(string: text)
        var separated:[String] = [text]
        for separator in textCountSeparatorArray {
            var newSeparated:[String] = []
            for text in separated {
                newSeparated.append(contentsOf: text.components(separatedBy: separator).filter({$0.count > 0}))
            }
            separated = newSeparated
        }
        separated = separated.map({$0.trimmingCharacters(in: .whitespacesAndNewlines)}).filter({$0.count > 0})
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
    @objc public static func checkTextImportConifirmToUser(viewController: UIViewController, title: String, content: String, hintString: String?, completion:((_ registerdNovelID:String?, _ importOptionSeparated:Bool)->Void)? = nil){
        let content = NovelSpeakerUtility.NormalizeNewlineString(string: content)
        DispatchQueue.main.async {
            var easyDialog = EasyDialogBuilder(viewController)
                .textField(tag: 100, placeholder: title, content: title, keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect)
                // TODO: 怪しくheightを画面の縦方向からの比率で指定している。
                // ここに 1.0 とか書くと他のViewの分の高さが入って全体は画面の縦幅よりも高くなるので全部が表示されない。
                // つまり、この謎の数字 0.45 というのは、できれば書きたくない値であり、この値でも大きすぎるかもしれず、
                // 小さすぎるかもしれず、適切な大きさ(baseViewが表示領域の縦幅に入る状態)になるように縮む必要があるのだが、
                // EasyDialog をそのように修正するのが面倒なのでやっていないという事なのであった。('A`)
                .textView(content: content, heightMultiplier: 0.45)
                
            if let hintString = hintString {
                easyDialog = easyDialog.label(text: hintString)
            }
            easyDialog = easyDialog.addButton(title: NSLocalizedString("NiftyUtility_CancelImport", comment: "取り込まない"), callback: { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false) {
                        completion?(nil, false)
                    }
                }
            })
            easyDialog = easyDialog.addButton(title: NSLocalizedString("NiftyUtility_Import", comment: "このまま取り込む"), callback: { (dialog) in
                let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                let title = titleTextField.text ?? title
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
                let novelID = RealmNovel.AddNewNovelOnlyText(content: content, title: title)
                completion?(novelID, false)
            })
            if let separatedText = CheckShouldSeparate(text: content), separatedText.reduce(0, { (result, body) -> Int in
                return result + (body.count > 0 ? 1 : 0)
            }) > 1 {
                easyDialog = easyDialog.addButton(title: NSLocalizedString("NiftyUtility_ImportSeparatedContent", comment: "テキトーに分割して取り込む"), callback: { (dialog) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                    let novelID = RealmNovel.AddNewNovelWithMultiplText(contents: separatedText, title: title)
                    completion?(novelID, true)
                })
            }
            easyDialog.build(isForMessageDialog: true).show()
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
    // エラーメッセージについて、開発者にメールを送ってもなんともできない物以外については true を返します(つまり開発者にメールを送れるようになります)
    static func isRecoverbleErrorString(error:String) -> Bool {
        let targetArray:[String] = [
            NSLocalizedString("UriLoader_NSURLConnectionRequestFailed", comment: "Webサーバからの取得に失敗しました。(恐らくは接続に失敗しています。ネットワーク状況を確認してください〜"),
            NSLocalizedString("StoryFetcher_FetchError_RobotsText", comment: "Webサイト様側で機械的なアクセスを制限されているサイトであったため、ことせかい による取得ができません。(robots.txt で拒否されています)"),
        ]
        for target in targetArray {
            if error.contains(target) {
                return false
            }
        }
        return true
    }
    
    static func checkUrlAndConifirmToUser_ErrorHandle(error:String, viewController:UIViewController, url: URL?, cookieString:String?, isNeedFallbackImportFromWebPageTab:Bool) {
        if isRecoverbleErrorString(error: error) && MFMailComposeViewController.canSendMail() {
            var errorMessage = error
            errorMessage += NSLocalizedString("NiftyUtility_ImportError_SendProblemReportMessage", comment: "\n\n問題の起こった小説について開発者に送信する事もできます。ただし、この報告への返信は基本的には致しません。返信が欲しい場合には、「設定」→「開発者に問い合わせる」からお問い合わせください。")
            var builder = EasyDialogBuilder(viewController)
            builder = builder.title(title: NSLocalizedString("NiftyUtility_ImportError", comment: "取り込み失敗"))
            .textView(content: errorMessage, heightMultiplier: 0.45)
            .addButton(title: NSLocalizedString("NiftyUtility_ImportError_SendProblemReportButton", comment: "報告メールを作成"), callback: { (dialog) in
                dialog.dismiss(animated: false) {
                    DispatchQueue.main.async {
                        let picker = MFMailComposeViewController()
                        //picker.mailComposeDelegate = self;
                        picker.setToRecipients(["limuraproducts@gmail.com"])
                        picker.setSubject(NSLocalizedString("NiftyUtility_ImportError_SendProblemReport_Mail_Title", comment:"ことせかい 取り込み失敗レポート"))
                        let (preferredSiteInfoURLList,novelSpeakerSiteInfoURL,autopagerizeSiteInfoURL) = RealmUtil.RealmBlock { realm -> ([String], String, String) in
                            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return ([], "", "") }
                            return (globalState.preferredSiteInfoURLList.map{$0}, globalState.novelSpeakerSiteInfoURL, globalState.autopagerizeSiteInfoURL)
                        }
                        let messageBody = NSLocalizedString("NiftyUtility_ImportError_SendProblemReport_Mail_Body", comment:"このまま編集せずに送信してください。\nなお、このメールへの返信は基本的には行っておりません。\n\nエラーメッセージ:\n") + error
                            + "\n\n------\nurl: \(url?.absoluteString ?? "-")"
                            + "\napp version: \(NiftyUtility.GetAppVersionString())"
                            + "\niOS version: \(UIDevice.current.systemVersion)"
                            + "\ndevice model: \(UIDevice.modelName)"
                            + "\npreferredSiteInfoURLList: \(preferredSiteInfoURLList)"
                            + "\nnovelSpeakerSiteInfoURL: \(novelSpeakerSiteInfoURL)"
                            + "\nautopagerizeSiteInfoURL: \(autopagerizeSiteInfoURL)"
                        picker.setMessageBody(messageBody, isHTML: false)
                        DummyMailComposeViewController.shared.currentViewController = viewController
                        picker.mailComposeDelegate = DummyMailComposeViewController.shared
                        viewController.present(picker, animated: true, completion: nil)
                    }
                }
            })
            if isNeedFallbackImportFromWebPageTab == true, let url = url {
                builder = builder.addButton(title: NSLocalizedString("NiftyUtility_ImportRetryToWebImportTabButton", comment: "Web取込タブで開き直してみる(ログインが必要な場合はこちらで直るかもしれません)"), callback: { (dialog) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
                        }
                    }
                })
            }
            builder = builder.addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                dialog.dismiss(animated: false, completion: nil)
                })
            
            builder.build(isForMessageDialog: true).show()
        }else{
            NiftyUtility.EasyDialogMessageDialog(viewController: viewController, title: NSLocalizedString("NiftyUtility_ImportError", comment: "取り込み失敗"), message: error, completion: nil)
        }
    }
    
    static func ImportStoryStateConifirmToUser(viewController:UIViewController, state:StoryState, isNeedFallbackImportFromWebPageTab: Bool = false) {
        guard let content = state.content else {
            checkUrlAndConifirmToUser_ErrorHandle(error: NSLocalizedString("NiftyUtility_ImportStoryStateConifirmToUser_NoContent", comment: "本文がありませんでした。"), viewController: viewController, url: state.url, cookieString: state.cookieString ?? "", isNeedFallbackImportFromWebPageTab: isNeedFallbackImportFromWebPageTab)
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
            multiPageString = NSLocalizedString("NiftyUtility_FollowingPageAreAvailable", comment: "続ページ：有り")
        }else {
            multiPageString = NSLocalizedString("NiftyUtility_FollowingPageAreNotAvailable", comment: "続ページ：無し")
        }
        DispatchQueue.main.async {
            var builder = EasyDialogBuilder(viewController)
            builder = builder.textField(tag: 100, placeholder: titleString, content: titleString, keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect, isNeedAllSelectOnEditTime: true)
                // TODO: 怪しくheightを画面の縦方向からの比率で指定している。
                // ここに 1.0 とか書くと他のViewの分の高さが入って全体は画面の縦幅よりも高くなるので全部が表示されない。
                // つまり、この謎の数字 0.45 というのは、できれば書きたくない値であり、この値でも大きすぎるかもしれず、
                // 小さすぎるかもしれず、適切な大きさ(baseViewが表示領域の縦幅に入る状態)になるように縮む必要があるのだが、
                // EasyDialog をそのように修正するのが面倒なのでやっていないという事なのであった。('A`)
                .textView(content: content, heightMultiplier: 0.45)
                .label(text: multiPageString)
                .addButton(title: NSLocalizedString("NiftyUtility_CancelImport", comment: "取り込まない"), callback: { (dialog) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                })
            builder = builder.addButton(title: NSLocalizedString("NiftyUtility_Import", comment: "このまま取り込む"),
                                        callback: {
                (dialog) in
                let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                let titleString = titleTextField.text ?? titleString
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false,
                                   completion: {
                        let (novelIDTmp, errorString, duplicatedNovelID) = RealmNovel.AddNewNovelWithFirstStoryState(state:state.TitleChanged(title:titleString))
                        guard let novelID = novelIDTmp else {
                            DispatchQueue.main.async {
                                let errorMessage = errorString ?? NSLocalizedString("NiftyUtility_FailedAboutAddNewNovelFromWithStoryMessage", comment: "既に登録されている小説などの原因が考えられます。")
                                if let duplicatedNovelID = duplicatedNovelID {
                                    NiftyUtility.EasyDialogTwoButton(
                                        viewController: viewController,
                                        title: NSLocalizedString("NiftyUtility_FailedAboutAddNewNovelFromWithStoryTitle", comment: "小説の本棚への追加に失敗しました。"),
                                        message: errorMessage,
                                        button1Title: NSLocalizedString(
                                            "NiftyUtility_FailedAboutAddNewNovel_DuplicateNovelID_OpenNovelButton",
                                            comment: "既存の小説を開く"
                                        ),
                                        button1Action: {
                                            BookShelfTreeViewController.OpenNovelOnBookShelf(novelID: duplicatedNovelID)
                                        },
                                        button2Title: nil,
                                        button2Action: nil
                                    )
                                }else{
                                        NiftyUtility.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("NiftyUtility_FailedAboutAddNewNovelFromWithStoryTitle", comment: "小説の本棚への追加に失敗しました。"), message: errorMessage, buttonTitle: nil, buttonAction: nil)
                                    }
                                }
                                return
                            }
                            NovelDownloadQueue.shared.addQueue(novelID: novelID)
                            DispatchQueue.main.async {
                                if let floatingButton = FloatingButton.createNewFloatingButton() {
                                    floatingButton.assignToView(view: viewController.view, currentOffset: CGPoint(x: -1, y: -1), text: NSLocalizedString("NiftyUtility_AddNewNovelToBookshelfTitle", comment: "本棚に小説を追加しました"), animated: true, buttonClicked: {})
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                                        floatingButton.hideAnimate()
                                    })
                                }else{
                                    NiftyUtility.EasyDialogOneButton(viewController: viewController, title: NSLocalizedString("NiftyUtility_AddNewNovelToBookshelfTitle", comment: "本棚に小説を追加しました"), message: NSLocalizedString("NiftyUtility_AddNewNovelToBookshelfMessage", comment: "続く章があればダウンロードを続けます。"), buttonTitle: nil, buttonAction: nil)
                                }
                            }
                        })
                    }
                })
            if state.IsNextAlive != true, let separatedText = CheckShouldSeparate(text: content), separatedText.reduce(0, { (result, body) -> Int in
                return result + (body.count > 0 ? 1 : 0)
            }) > 1 {
                builder = builder.addButton(title: NSLocalizedString("NiftyUtility_ImportSeparatedContent", comment: "テキトーに分割して取り込む"), callback: { (dialog) in
                    let titleTextField = dialog.view.viewWithTag(100) as! UITextField
                    let titleString = titleTextField.text ?? titleString
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                    RealmNovel.AddNewNovelWithMultiplText(contents: separatedText, title: titleString)
                })
            }
            if isNeedFallbackImportFromWebPageTab == true {
                builder = builder.addButton(title: NSLocalizedString("NiftyUtility_ImportRetryToWebImportTabButton", comment: "Web取込タブで開き直してみる(ログインが必要な場合はこちらで直るかもしれません)"), callback: { (dialog) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false) {
                            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: state.url)
                        }
                    }
                })
            }
            builder.build(isForMessageDialog: true).show()
        }
    }
    
    static let staticFetcher = StoryFetcher()
    public static func checkUrlAndConifirmToUser(viewController: UIViewController, url: URL, cookieString:String?, isNeedFallbackImportFromWebPageTab:Bool) {
        BehaviorLogger.AddLog(description: "checkUrlAndConifirmToUser called.", data: ["url": url.absoluteString])
        DispatchQueue.main.async {
            let builder = EasyDialogBuilder(viewController)
            .text(content: NSLocalizedString("ImportFromWebPageViewController_loading", comment: "loading"))
            let dialog = builder.build()
            let fetcher = staticFetcher
            dialog.show {
                fetcher.FetchFirstContent(url: url, cookieString: cookieString, previousContent: nil) { (url, state, errorString) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: {
                            if let state = state, (state.content?.count ?? 0) > 0 {
                                ImportStoryStateConifirmToUser(viewController: viewController, state: state, isNeedFallbackImportFromWebPageTab: isNeedFallbackImportFromWebPageTab)
                                return
                            }
                            checkUrlAndConifirmToUser_ErrorHandle(error: errorString ?? NSLocalizedString("NiftyUtility_CanNotAddToBookshelfTitle", comment: "不明なエラー"), viewController: viewController, url: url, cookieString: cookieString, isNeedFallbackImportFromWebPageTab: isNeedFallbackImportFromWebPageTab)
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
    
    static func RTFDataToAttributedString(data:Data) -> NSAttributedString? {
        do {
            let attributedString = try NSAttributedString(data: data, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            return attributedString
        }catch let error {
            print("AttributedString from RTF data failed. error: ", error)
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
            .build(isForMessageDialog: true)
        dialog.show { completion?(dialog) }
        return dialog
    }
    #endif
    
    #if !os(watchOS)
    @discardableResult
    public static func EasyDialogLongMessageTwoButton(viewController: UIViewController, title: String?, message: String?, button1Title: String?, button1Action:(()->Void)?, button2Title: String?, button2Action:(()->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.textView(content: message, heightMultiplier: 0.55)
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
        let builded = dialog.build(isForMessageDialog: true)
        builded.show { completion?(builded) }
        return builded
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
    @objc public static func EasyDialogOneButtonWithSwitch(viewController: UIViewController, title: String?, message: String?, switchMessage:String? = nil, switchValue:Bool = false, button1Title: String?, button1Action:((Bool)->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        if let switchMessage = switchMessage {
            dialog = dialog.switchField(tag: 200, message: switchMessage, value: switchValue)
        }
        func getSwitchValue(dialog:EasyDialog) -> Bool {
            guard let switchView =  dialog.view.viewWithTag(200) as? UISwitch else { return false }
            return switchView.isOn
        }
        dialog = dialog.addButton(title: button1Title != nil ? button1Title! : NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                if let button1Action = button1Action {
                    button1Action(getSwitchValue(dialog: dialog))
                }
            })
        })
        let builded = dialog.build()
        builded.show { completion?(builded) }
        return builded
    }
    
    @discardableResult
    @objc public static func EasyDialogTwoButtonWithSwitch(viewController: UIViewController, title: String?, message: String?, switchMessage:String? = nil, switchValue:Bool = false, button1Title: String?, button1Action:((Bool)->Void)?, button2Title: String?, button2Action:((Bool)->Void)?, completion: ((_ dialog:EasyDialog)->Void)? = nil) -> EasyDialog {
        var dialog = EasyDialogBuilder(viewController)
        if let title = title {
            dialog = dialog.title(title: title)
        }
        if let message = message {
            dialog = dialog.label(text: message, textAlignment: .left)
        }
        if let switchMessage = switchMessage {
            dialog = dialog.switchField(tag: 200, message: switchMessage, value: switchValue)
        }
        func getSwitchValue(dialog:EasyDialog) -> Bool {
            guard let switchView =  dialog.view.viewWithTag(200) as? UISwitch else { return false }
            return switchView.isOn
        }
        dialog = dialog.addButton(title: button1Title != nil ? button1Title! : NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                if let button1Action = button1Action {
                    button1Action(getSwitchValue(dialog: dialog))
                }
            })
        })
        dialog = dialog.addButton(title: button2Title != nil ? button2Title! : NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
            dialog.dismiss(animated: false, completion: {
                if let button2Action = button2Action {
                    button2Action(getSwitchValue(dialog: dialog))
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
        }.build(isForMessageDialog: true).show()
    }
    #endif
    
    #if !os(watchOS)
    static var headlessHttpClientObj:HeadlessHttpClient? = nil
    static func headlessClientLoadAboutPage() {
        if let client = headlessHttpClientObj {
            client.LoadAboutPage()
        }
    }
    static func httpHeadlessRequest(url: URL, postData:Data? = nil, timeoutInterval:TimeInterval = 10, cookieString: String? = nil, mainDocumentURL:URL? = nil, httpClient:HeadlessHttpClient? = nil, withWaitSecond:TimeInterval? = nil, injectJavaScript:String? = nil, successAction:((Document)->Void)? = nil, failedAction:((Error?)->Void)? = nil) {
        // TODO: おおよそ関係の無い所で Realm を触る必要があってうぅむ。
        let allowsCellularAccess:Bool = RealmUtil.RealmBlock { (realm) -> Bool in
            if let globalData = RealmGlobalState.GetInstanceWith(realm: realm), globalData.IsDisallowsCellularAccess {
                return false
            }
            return true
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
                func waitProcess() {
                    if let withWaitSecond = withWaitSecond, withWaitSecond > 0.0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + withWaitSecond) {
                            client.GetCurrentContent { (document, err) in
                                if let document = document {
                                    successAction?(document)
                                }else{
                                    failedAction?(err)
                                }
                            }
                        }
                    }else{
                        successAction?(doc)
                    }
                }
                if let injectJavaScript = injectJavaScript {
                    DispatchQueue.main.async {
                        client.ExecuteJavaScript(javaScript: injectJavaScript) { result, err in
                            waitProcess()
                        }
                    }
                }else{
                    waitProcess()
                }
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
    
    static func getContentTypeHeaderFromURLResponse(urlResponse:URLResponse?) -> String? {
        guard let httpURLResponse = urlResponse as? HTTPURLResponse else { return nil }
        guard let contentType = httpURLResponse.allHeaderFields.filter({ (element) -> Bool in
            if let key = element.key as? String, key.lowercased() == "content-type" {
                return true
            }
            return false
        }).first?.value as? String else { return nil }
        return contentType
    }
    
    static func getCharsetStringFromContentTypeString(contentType:String?) -> String? {
        guard let contentType = contentType else { return nil }
        return GetMatchedText1(text: contentType, regexpPattern: "; *charset=([^ ]*)")
    }
    
    static func getCharsetStringFromURLResponse(urlResponse:URLResponse?) -> String? {
        guard let contentType = getContentTypeHeaderFromURLResponse(urlResponse: urlResponse) else { return nil }
        return getCharsetStringFromContentTypeString(contentType: contentType)
    }
    
    static func isPDFFileByContentTypeString(contentType: String?) -> Bool {
        guard let contentType = contentType else { return false }
        return contentType.lowercased() == "application/pdf"
    }
    
    static func guessStringEncodingFrom(charset:String?) -> String.Encoding? {
        guard let charset = charset?.lowercased() else { return nil }
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
    
    static func forceDecodeToStringByUTF8(data:Data) -> String {
        return String(decoding: data, as: UTF8.self)
    }

    static func tryDecodeToString(data:Data, encoding:String.Encoding?) -> (String?, String.Encoding?) {
        // UTF8 の時だけは問答無用でUTF8としてデコードする事にします。(変換できなかった文字は空白か何かに変わるはずです)
        if let encoding = encoding, encoding == .utf8 {
            return (forceDecodeToStringByUTF8(data: data), encoding)
        }
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
        let (stringOptional, _) = tryDecodeToString(data: data, charset: charset)
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
        // headerEncoding で decode できるのならそれを信じます。(HTML の meta よりも優先します)
        if let encoding = headerEncoding, let tmpString = String(data: data, encoding: encoding) {
            return (tmpString, encoding)
        }
        // headerEncoding では駄目だったと仮定して、html meta encoding を取り出します。
        // tryDecodeToString() はなんとなく頑張ってencodingを推測するはずです。
        let (tmpStringOptional, firstEncoding) = tryDecodeToString(data: data, encoding: headerEncoding)
        guard let tmpString = tmpStringOptional else {
            return (nil, nil)
        }
        if let metaEncoding = getHTMLMetaEncoding(html: tmpString) {
            let (decodedHtml, encoding) = tryDecodeToString(data: data, encoding: metaEncoding)
            if let html = decodedHtml {
                return (html, encoding ?? .utf8)
            }
        }
        return (tmpString, firstEncoding ?? .utf8)
    }

    #if !os(watchOS)
    static var headlessClientMap:[String:HeadlessHttpClient] = [:]
    
    public static func RemoveHeadlessHTTPClient(key:String) {
        headlessClientMap.removeValue(forKey: key)
    }
    
    public static func ClickOnHeadlessHTTPClient(key:String, element:Element, completion: @escaping ((String?)->Void)) {
        guard let client = headlessClientMap[key] else {
            completion(nil)
            return
        }
        element.click(completionHandler: { _, err in
            if err != nil {
                completion(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                client.GetCurrentContent { document, err in
                    guard let document = document else {
                        completion(nil)
                        return
                    }
                    completion(document.innerHTML)
                }
            }
        })
    }
    
    public static func QuerySelectorForHeadlessHTTPClient(key:String, selector:String, completion: @escaping ((Element?)->Void)){
        guard let client = headlessClientMap[key] else {
            completion(nil)
            return
        }
        client.GetCurrentContent { document, err in
            guard let document = document else {
                completion(nil)
                return
            }
            let result = document.querySelector(selector)
            completion(result)
        }
    }
    
    public static func QuerySelectorForHeadlessHTTPClientAsync(key:String, selector:String) async -> Element? {
        await withCheckedContinuation({ result in
            QuerySelectorForHeadlessHTTPClient(key: key, selector: selector) { element in
                result.resume(returning: element)
            }
        })
    }
    #endif

    static let httpRequestDefaultTimeoutInterval:TimeInterval = 10
    public static func httpRequest(url: URL, postData:Data? = nil, timeoutInterval:TimeInterval? = httpRequestDefaultTimeoutInterval, cookieString:String? = nil, isNeedHeadless:Bool = false, mainDocumentURL:URL? = nil, allowsCellularAccess:Bool = true, headlessClientKey:String? = nil, withWaitSecond:Double? = nil, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)? = nil, failedAction:((Error?)->Void)? = nil){
        #if !os(watchOS)
        if isNeedHeadless {
            var headlessClient:HeadlessHttpClient? = nil
            if let headlessClientKey = headlessClientKey {
                if let client = headlessClientMap[headlessClientKey] {
                    headlessClient = client
                }else{
                    let newClient = HeadlessHttpClient()
                    headlessClientMap[headlessClientKey] = newClient
                    headlessClient = newClient
                }
            }
            httpHeadlessRequest(url: url, postData: postData, timeoutInterval: timeoutInterval ?? httpRequestDefaultTimeoutInterval, cookieString: cookieString, mainDocumentURL: mainDocumentURL, httpClient: headlessClient, withWaitSecond: withWaitSecond, successAction: { (doc) in
                if let data = doc.innerHTML?.data(using: .utf8) {
                    successAction?(data, .utf8)
                    return
                }
            }, failedAction: failedAction)
            return
        }
        #endif
        let session: URLSession = URLSession.shared
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeoutInterval ?? httpRequestDefaultTimeoutInterval)
        if let postData = postData {
            request.httpMethod = "POST"
            request.httpBody = postData
        }
        if let cookieString = cookieString {
            if let cookieStorage = session.configuration.httpCookieStorage, let oldCookies = cookieStorage.cookies, let host = url.host, let domainURL = URL(string: "http://\(host)/") {
                let newCookieArray = FilterNewCookie(oldCookieArray: oldCookies, newCookieArray: ConvertJavaScriptCookieStringToHTTPCookieArray(javaScriptCookieString: cookieString, targetURL: domainURL/*, expireDate: Date(timeIntervalSinceNow: 60*60*24)*/))
                if newCookieArray.count > 0 {
                    cookieStorage.setCookies(newCookieArray, for: domainURL, mainDocumentURL: nil)
                }
            }else{
                request.addValue(cookieString, forHTTPHeaderField: "Cookie")
            }
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
                        print("\(url.absoluteString) return \(response.statusCode)")
                        failedAction?(NovelSpeakerUtility.GenerateNSError(msg:
                            String(format: NSLocalizedString("UriLoader_HTTPResponseIsInvalid", comment: "サーバから返されたステータスコードが正常値(200 OK等)ではなく、%ld を返されました。ログインが必要なサイトである場合などに発生する場合があります。ことせかい アプリ側でできることはあまり無いかもしれませんが、ことせかい のサポートサイトに設置してあります、ご意見ご要望フォームにこの問題の起こったURLとこの症状が起こった前にやったことを添えて報告して頂けると、あるいはなんとかできるかもしれません。"), response.statusCode)))
                        return
                    }
                }
                if let data = data {
                    let contentType = getContentTypeHeaderFromURLResponse(urlResponse: response)
                    #if !os(watchOS)
                    if isPDFFileByContentTypeString(contentType: contentType), let pdfString = NiftyUtility.BinaryPDFToString(data: data) {
                        let fileName = (url.lastPathComponent as NSString).deletingPathExtension
                        let dummyHtml = "<html><head><title>\(fileName)</title><meta charset=\"UTF-8\"></head><body><pre>\(pdfString)</pre></body></html>"
                        if let dummyData = dummyHtml.data(using: .utf8) {
                            successAction?(dummyData, String.Encoding.utf8)
                            return
                        }
                    }else{
                        let charset = getCharsetStringFromContentTypeString(contentType: contentType)
                        let encoding = guessStringEncodingFrom(charset: charset)
                        successAction?(data, encoding)
                        return
                    }
                    #else
                    let charset = getCharsetStringFromContentTypeString(contentType: contentType)
                    let encoding = guessStringEncodingFrom(charset: charset)
                    successAction?(data, encoding)
                    return
                    #endif
                }
                failedAction?(NovelSpeakerUtility.GenerateNSError(msg: String(format: NSLocalizedString("NiftyUtility_URLSessionRequestFailedAboutError", comment: "サーバからのデータの取得に失敗しました。(末尾に示されているエラー内容とエラーの起こったURLとエラーが起こるまでの操作手順を添えて、サポートサイト下部にありますご意見ご要望フォームか、設定→開発者に問い合わせるよりお問い合わせ頂けますと、あるいは何かできるかもしれません。\nエラー内容: %@)"), error?.localizedDescription ?? "unknown error(nil)")))
            }.resume()
        }
    }
    
    public static func httpGet(url: URL, timeoutInterval:TimeInterval? = nil, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)?, failedAction:((Error?)->Void)?){
        httpRequest(url: url, postData: nil, timeoutInterval: timeoutInterval, successAction: successAction, failedAction: failedAction)
    }
    
    public static func httpPost(url: URL, data:Data, successAction:((_ content:Data, _ headerCharset:String.Encoding?)->Void)?, failedAction:((Error?)->Void)?){
        httpRequest(url: url, postData: data, successAction: successAction, failedAction: failedAction)
    }
    
    public static func getAllCookies(completionHandler:(([HTTPCookie]?)->Void)) {
        let cookies = URLSession.shared.configuration.httpCookieStorage?.cookies
        completionHandler(cookies)
    }
    
    public static func injectCookie(cookie:HTTPCookie) -> Bool {
        guard let cookieStorage = URLSession.shared.configuration.httpCookieStorage else { return false }
        cookieStorage.setCookie(cookie)
        return true
    }
    
    // newCookieArray に入っている cookie のうち、oldCookieArray で既に指定されている物を排除します。
    // つまり、新しく設定する必要のあると思われる cookie だけにするための関数です。
    // 内容としては、domain, path, name の全てが一致した物が無い場合には残ります。
    // またそれらが一致していても、expireDate がより後になっていなければ残しません。
    // expireDate が指定されていない場合は残ります。
    public static func FilterNewCookie(oldCookieArray:[HTTPCookie], newCookieArray:[HTTPCookie]) -> [HTTPCookie] {
        var result:[HTTPCookie] = []
        for newCookie in newCookieArray {
            var hit:Bool = false
            for oldCookie in oldCookieArray {
                if newCookie == oldCookie {
                    hit = true
                    continue
                }
                if newCookie.domain != oldCookie.domain ||
                    newCookie.path != oldCookie.path ||
                    newCookie.name != oldCookie.name
                     {
                    continue
                }
                if let newExpireDate = newCookie.expiresDate, let oldExpireDate = oldCookie.expiresDate, newExpireDate > oldExpireDate { continue }
                hit = true
            }
            if !hit {
                //print("FilterNewCookie new cookie found:\n\(newCookie.description)")
                result.append(newCookie)
            }
        }
        return result
    }
    
    public static func RemoveExpiredCookie(cookieArray:[HTTPCookie]) -> [HTTPCookie] {
        var result:[HTTPCookie] = []
        let now = Date()
        for cookie in cookieArray {
            if let expiresDate = cookie.expiresDate, expiresDate > now {
                result.append(cookie)
            }
        }
        return result
    }
    
    public static func MergeCookieArray(currentCookieArray:[HTTPCookie], newCookieArray:[HTTPCookie]) -> [HTTPCookie] {
        var tmpCookies:[String:HTTPCookie] = [:]
        var filterdCookieArray = currentCookieArray
        filterdCookieArray.append(contentsOf: newCookieArray)
        for cookie in filterdCookieArray {
            let key = "\(cookie.domain)/\(cookie.path)#\(cookie.name)"
            if let prevCookie = tmpCookies[key] {
                if let prevDate = prevCookie.expiresDate, let currentDate = cookie.expiresDate, currentDate > prevDate {
                    tmpCookies[key] = cookie
                }
            }else{
                tmpCookies[key] = cookie
            }
        }
        filterdCookieArray = Array(tmpCookies.values)
        return RemoveExpiredCookie(cookieArray: filterdCookieArray)
    }
    
    public static func ConvertJavaScriptCookieStringToHTTPCookieArray(javaScriptCookieString:String, targetURL:URL, expireDate:Date? = nil, portArray:[Int]? = nil, isSecure:Bool? = nil) -> [HTTPCookie] {
        var result:[HTTPCookie] = []
        let keyValueArray = javaScriptCookieString.split(separator: ";")
        for keyValueWithWhitespace in keyValueArray {
            let keyValue = keyValueWithWhitespace.trimmingCharacters(in: .whitespaces).split(separator: "=")
            guard keyValue.count == 2 else { continue }
            let key = keyValue[0]
            let value = keyValue[1]
            guard let host = targetURL.host else { continue }
            let path = targetURL.path
            // HTTPCookie を生成するには
            // cookies(withResponseHeaderFields:for:)
            // https://developer.apple.com/documentation/foundation/httpcookie/1393011-cookies
            // っていうのもあるんだけれど、JavaScript から取得できる document.cookie は
            // HTTP header の情報は載っていないので
            // HTTPCookie のコンストラクタに properites を渡す形で生成します。
            var properties:[HTTPCookiePropertyKey:Any] = [
                .name: key,
                .value: value,
                .domain: host,
                .path: path,
            ]
            if let expireDate = expireDate {
                properties[.expires] = expireDate
            }
            if let portArray = portArray {
                properties[.port] = portArray.map({$0.description}).joined(separator: ",")
            }
            if let isSecure = isSecure {
                properties[.secure] = isSecure ? "TRUE" : "FALSE"
            }
            guard let cookie = HTTPCookie(properties: properties) else { continue }
            result.append(cookie)
        }
        return result
    }
    
    static func DumpHTTPCookieArray(cookieArray:[HTTPCookie]) {
        var domainCount:[String:Int] = [:]
        for cookie in cookieArray {
            print(cookie.description)
            if let count = domainCount[cookie.domain] {
                domainCount[cookie.domain] = count + 1
            }else{
                domainCount[cookie.domain] = 1
            }
        }
        for kv in domainCount {
            let domain = kv.key
            let count = kv.value
            print("  \(domain):\(count)")
        }
        print("cookieArray.count: \(cookieArray.count)")
    }
    
    static func AssignCookieArrayToCookieStorage(cookieArray:[HTTPCookie], cookieStorage:HTTPCookieStorage) {
        for cookie in cookieArray {
            cookieStorage.setCookie(cookie)
        }
    }
    
    static func RemoveAllCookieInCookieStorage(cookieStorage:HTTPCookieStorage) {
        guard let cookieArray = cookieStorage.cookies else { return }
        for cookie in cookieArray {
            cookieStorage.deleteCookie(cookie)
        }
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
        NiftyUtility.httpGet(url: url, successAction: { (data, encoding) in
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
        NiftyUtility.backgroundQueue.asyncAfter(deadline: .now() + 0.05) {
            block()
            dispatchSemaphore.signal()
        }
        while dispatchSemaphore.wait(timeout: DispatchTime.now()) == DispatchTimeoutResult.timedOut {
            NiftyUtility.sleep(second: 0.1)
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
        return RealmUtil.RealmBlock { (realm) -> Bool in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
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
    
    static func GetCachedHttpGetCachedData(url: URL, cacheFileName: String, expireTimeinterval:TimeInterval?) -> Data? {
        guard let cacheFilePath = GetCacheFilePath(fileName: cacheFileName),
              FileManager.default.fileExists(atPath: cacheFilePath.path) else {
            return nil
        }
        if let expireTimeinterval = expireTimeinterval {
            if let attribute = try? FileManager.default.attributesOfItem(atPath: cacheFilePath.path),
               let modificationDate = attribute[FileAttributeKey.modificationDate] as? Date,
               (Date().timeIntervalSince1970 - modificationDate.timeIntervalSince1970) >= expireTimeinterval {
                return nil
            }
        }
        guard let dataZiped = try? Data(contentsOf: cacheFilePath),
              let data = decompress(data: dataZiped) else {
            return nil
        }
        return data
    }
    
    static public func FileCachedHttpGet(url: URL, cacheFileName:String, expireTimeinterval:TimeInterval, canRecoverOldFile:Bool = false, requestTimeout:TimeInterval? = nil, successAction:((Data)->Void)?, failedAction:((Error?)->Void)?) {
        if let data = GetCachedHttpGetCachedData(url: url, cacheFileName: cacheFileName, expireTimeinterval: expireTimeinterval) {
            successAction?(data)
            return
        }
        httpGet(url: url, timeoutInterval: requestTimeout, successAction: { (data, encoding) in
            if let cacheFilePath = GetCacheFilePath(fileName: cacheFileName), let dataZiped = compress(data: data) {
                do {
                    try dataZiped.write(to: cacheFilePath, options: Data.WritingOptions.atomic)
                }catch{
                    print("cache file write error. for url: \(url.absoluteString)")
                }
            }
            successAction?(data)
        }) { (err) in
            if canRecoverOldFile, let cacheFilePath = GetCacheFilePath(fileName: cacheFileName),
                FileManager.default.fileExists(atPath: cacheFilePath.path), let dataZiped = try? Data(contentsOf: cacheFilePath),
                let data = decompress(data: dataZiped) {
                successAction?(data)
                return
            }
            failedAction?(err)
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
            for scene in UIApplication.shared.connectedScenes {
                if scene.activationState == .foregroundActive, let window = ((scene as? UIWindowScene)?.delegate as? UIWindowSceneDelegate)?.window, let rootViewController = window?.rootViewController {
                    return GetToplevelViewController(controller: rootViewController)
                }
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
    
    #if !os(watchOS)
    static func UpdateSettingsTabBadge(badge:String?) {
        DispatchQueue.main.async {
            print(#function)
            guard let viewController = GetRegisterdToplevelViewController() else { return }
            @discardableResult
            func searchTabBarController(badge:String?, viewController:UIViewController, depth:Int) -> Bool {
                if depth > 2 { return false }
                if let tabBarController = viewController.tabBarController {
                    tabBarController.tabBar.items?[3].badgeValue = badge
                    return true
                }
                for vc in viewController.children {
                    if searchTabBarController(badge: badge, viewController: vc, depth: depth + 1) {
                        return true
                    }
                }
                return false
            }
            searchTabBarController(badge: badge, viewController: viewController, depth: 0)
        }
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
    static let ConvertRubyTagToVerticalBarRubyText_ConvFromString = "<ruby[^>]*?>\\s*(<rb[^>]*?>)?\\s*([^<]+)\\s*(</rb[^>]*?>)?\\s*(<rp[^>]*?>[^<]*</rp[^>]*?>)?\\s*(<rt[^>]*?>[^<]+</rt[^>]*?>)\\s*(<r[pt][^>]*?>[^<]*</r[pt][^>]*?>)?\\s*</ruby[^>]*?>"
    static let ConvertRubyTagToVerticalBarRubyText_RegexpConvFrom = try? NSRegularExpression(pattern: ConvertRubyTagToVerticalBarRubyText_ConvFromString, options: [.caseInsensitive, .dotMatchesLineSeparators])
    static func ConvertRubyTagToVerticalBarRubyText(htmlString:String) -> String {
        let convTo = "|$1$2$3($5)"
        guard let regexp = ConvertRubyTagToVerticalBarRubyText_RegexpConvFrom else { return htmlString }
        return regexp.stringByReplacingMatches(in: htmlString, options: [], range: NSMakeRange(0, htmlString.count), withTemplate: convTo)
    }
    
    // HTML から String に変換する時に必要なくなるタグ等を削除します。
    static let RemoveNoNeedTagRegexpArray = [
        //try? NSRegularExpression(pattern: "<script.*?/script>", options: [.caseInsensitive, .dotMatchesLineSeparators]), // AttributedString に変換する場合、そちらで <script> は無視されるのでここで消しておく必要は多分ない
        try? NSRegularExpression(pattern: "<iframe.*?/iframe>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<frame.*?>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<link.*?>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<meta.*?>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<noscript.*?/noscript>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<img.*?>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        // <head>や<title>の中はNSAttributedString で取り出そうとしても消えてしまうため、<head>や<title>タグを消してしまうことでこれに対応します。
        try? NSRegularExpression(pattern: "<\\s*head[^>]*>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
        try? NSRegularExpression(pattern: "<\\s*title[^>]*>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
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
    
    static func FilterXpathToHtml(xmlDocument:Kanna.XMLDocument, xpath:String) -> String {
        let xpathResult = xmlDocument.xpath(xpath)
        switch xpathResult {
        case .none:
            return ""
        case .NodeSet(let nodeset):
            var resultHTML = ""
            for element in nodeset {
                var elementXML = ""
                let toHtml = element.toHTML
                if let toHtml = toHtml, let tagName = element.tagName, let content = element.content, toHtml == " \(tagName)=\"\(content)\"" {
                    elementXML = content
                }else{
                    elementXML = toHtml ?? ""
                }
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
        case .Bool(let bool):
            return "\(bool)"
        case .Number(let num):
            return "\(num)"
        case .String(let text):
            return text
        }
    }
    static func FilterXpathToHtml(xmlElement:Kanna.XMLElement, xpath:String) -> String {
        var resultHTML = ""
        //print("FilterXpathToHtml(xmlElement:, xpath:\(xpath)): \(xmlElement.innerHTML ?? "nil")")
        for element in xmlElement.xpath(xpath) {
            var elementXML = element.toHTML ?? ""
            //print("FilterXpathToHtml element: tagName: \(element.tagName ?? "nil"), xml: \(elementXML)")
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
    
    static func FilterXpathWithConvertString(xmlDocument:Kanna.XMLDocument, xpath:String, injectStyle:String? = nil) -> String {
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
    static func FilterXpathWithConvertString(xmlElement:Kanna.XMLElement, xpath:String, injectStyle:String? = nil) -> String {
        let filterdHTML = FilterXpathToHtml(xmlElement: xmlElement, xpath: xpath)
        let resultHTML:String
        if let injectStyle = injectStyle, injectStyle.count > 0 {
            resultHTML = "<style>" + injectStyle + "</style>" + filterdHTML
        }else{
            resultHTML = filterdHTML
        }
        if let result = HTMLToString(htmlString: resultHTML) {
            return result
        }
        return xmlElement.xpath(xpath).reduce(""){ $0 + ($1.content ?? "") }
    }
    
    static func FilterXpathWithExtructFirstHrefLink(xmlDocument:Kanna.XMLDocument, xpath:String, baseURL:URL) -> URL? {
        guard let urlNode = xmlDocument.xpath(xpath).first else { return nil }
        let urlString = urlNode["href"] ?? urlNode.content ?? ""
        return URL(string: urlString, relativeTo: baseURL)
    }
    
    static func FilterXpathWithExtructFirstHrefLink(xmlElement:Kanna.XMLElement, xpath:String, baseURL:URL) -> URL? {
        guard let urlNode = xmlElement.xpath(xpath).first else { return nil }
        let urlString = urlNode["href"] ?? urlNode.content ?? ""
        return URL(string: urlString, relativeTo: baseURL)
    }
    
    static func FilterXpathWithExtructTagString(xmlDocument:Kanna.XMLDocument, xpath:String, isNeedWhitespaceSplitForTag:Bool) -> Set<String> {
        var tagSet = Set<String>()
        for element in xmlDocument.xpath(xpath) {
            guard let elementXML = element.toHTML, let tagString = HTMLToString(htmlString: elementXML) else { continue }
            let trimedString = tagString.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#＃♯"))
            if trimedString.count <= 0 { continue }
            if isNeedWhitespaceSplitForTag {
                tagSet.formUnion(Set<String>(trimedString.components(separatedBy: " 　\u{C2A0}"))) // C2A0 == &nbsp;
            }
            tagSet.insert(trimedString)
        }
        return tagSet
    }

    static func FilterXpathWithExtructTagString(xmlElement:Kanna.XMLElement, xpath:String, isNeedWhitespaceSplitForTag:Bool) -> Set<String> {
        var tagSet = Set<String>()
        for element in xmlElement.xpath(xpath) {
            guard let elementXML = element.toHTML, let tagString = HTMLToString(htmlString: elementXML) else { continue }
            let trimedString = tagString.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#＃♯"))
            if trimedString.count <= 0 { continue }
            if isNeedWhitespaceSplitForTag {
                tagSet.formUnion(Set<String>(trimedString.components(separatedBy: " 　\u{C2A0}"))) // C2A0 == &nbsp;
            }
            tagSet.insert(trimedString)
        }
        return tagSet
    }

    // a を b で xor します。b が a より短い場合はループして適用します
    static func xorData(a:Data, b:Data) -> Data {
        var result:Data = Data(capacity: a.count)
        for i in 0..<a.count {
            result.append(a[i] ^ b[i % b.count])
        }
        return result
    }
    
    #if !os(watchOS)
    static func sha256(data: Data) -> Data {
        let nsData = NSData(data: data)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256(nsData.bytes, CC_LONG(nsData.length), &digest)
        let resultNSData = NSData(bytes: &digest, length: Int(CC_SHA256_DIGEST_LENGTH))
        return resultNSData as Data
    }

    /// ダサい暗号化
    static func stringEncrypt(string:String, key:String) -> String? {
        guard let data = string.data(using: .utf8), let keyData = key.data(using: .utf8) else { return nil }
        let hashedKeyData = sha256(data: keyData)
        guard let zipedData = data.zip() else { return nil }
        let encryptedData = xorData(a: zipedData, b: hashedKeyData)
        return encryptedData.base64EncodedString()
    }
    /// ダサい暗号化の戻し
    static func stringDecrypt(string:String, key:String) -> String? {
        guard let data = Data(base64Encoded: string) else { return nil }
        guard let keyData = key.data(using: .utf8) else { return nil }
        let hashedKeyData = sha256(data: keyData)
        let decryptedData = xorData(a: data, b: hashedKeyData)
        guard let unzipedData = decryptedData.unzip() else { return nil }
        return String(data: unzipedData, encoding: .utf8)
    }
    #endif
    
    // 通知を表示させます。
    static func InvokeNotificationNow(title:String, message:String, badgeNumber:Int) {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = title
        notificationContent.body = message
        notificationContent.badge = NSNumber(value: badgeNumber)
        // 怪しく identifier は日付を入れることにします。
        // (複数登録された場合でも最後の一つにならないように)
        // なお、通知を自分で消す場合はこの identifier をどこかに保存しておかないと駄目です。
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYYMMDDhhmmss"
        let formatedNow = formatter.string(from: Date())
        let identifier = "NovelSpeaker_Notification_\(formatedNow)"
        let request = UNNotificationRequest(identifier: identifier, content: notificationContent, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    static func compress(data:Data) -> Data? {
        return data.compress(withAlgorithm: .lzfse)
        //return data.zip()
    }
    static func decompress(data:Data) -> Data? {
        return data.decompress(withAlgorithm: .lzfse)
        //return data.unzip()
    }
    static func stringCompress(string:String) -> Data? {
        return string.data(using: .utf8, allowLossyConversion: true)?.compress(withAlgorithm: .lzfse)
        //return string.data(using: .utf8, allowLossyConversion: true)?.zip()
    }
    static func stringDecompress(data:Data) -> String? {
        guard let data = data.decompress(withAlgorithm: .lzfse) else {
        //guard let data = data.unzip() else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
    
    #if !os(watchOS)
    static func StopiCloudSync(viewController:UIViewController) {
        EasyDialogNoButton(viewController: viewController, title: NSLocalizedString("SettingsViewController_CopyingCloudToLocal", comment: "iCloud側のデータを端末側のデータへ変換中"), message: "-") { (dialog) in
            func assignMessage(message:String) {
                DispatchQueue.main.async {
                    guard let label = dialog.view.viewWithTag(100) as? UILabel else { return }
                    label.text = message
                }
            }
            if RealmUtil.CheckIsLocalRealmCreated() {
                assignMessage(message: NSLocalizedString("SettingsViewController_IsNeedRestartApp_Message", comment: "この操作を行うためには一旦アプリを再起動させる必要があります。Appスイッチャーなどからアプリを終了させ、再度起動させた後にもう一度お試しください。"))
                return
            }
            guard let cloudRealm = try? RealmUtil.GetCloudRealm(), let localRealm = try? RealmUtil.GetLocalRealm() else {
                assignMessage(message: NSLocalizedString("NiftyUtility_FailedConvertiCloudToLocal_CreateRealmFailed", comment: "iCloud側のデータからlocalデータへの書き換えに失敗しました。(どちらかのデータを開けませんでした)\n念の為、アプリを再起動してもう一度試してみてください。"))
                return
            }
            do {
                try RealmToRealmCopyTool.DoCopy(from: cloudRealm, to: localRealm, progress: { (text) in
                    assignMessage(message: text)
                })
            }catch{
                assignMessage(message: NSLocalizedString("NiftyUtility_FailedConvertiCloudToLocal_DoCopyFailed", comment: "iCloud側のデータからlocalデータへの書き換えに失敗しました。(データのコピー中にエラーが発生しました)\n念の為、アプリを再起動してもう一度試してみてください。"))
                return
            }
            RealmUtil.ChangeToLocalRealm()
            dialog.dismiss(animated: false) {
                NiftyUtility.EasyDialogOneButton(
                viewController: viewController,
                title: nil,
                message: NSLocalizedString("SettingsViewController_iCloudDisable_done", comment: "iCloud同期を停止しました"),
                buttonTitle: nil,
                buttonAction: nil)
            }
        }
    }
    #endif
    
    #if !os(watchOS)
    @objc static func StartiCloudDataVersionChecker() {
        RealmCloudVersionChecker.RunChecker { (version) in
            DispatchQueue.main.async {
                print("RealmCloudVersionChecker.RunChecker hit: \(version)")
                guard let toplevelViewController = GetToplevelViewController(controller: nil) else { return }
                // ここで呼び出すダイアログは閉じる事はしないため、
                // 汎用の物は使わずに自前で制御します。
                print("RealmCloudVersionChecker.RunChecker building Dialog...")
                EasyDialogBuilder(toplevelViewController)
                .title(title: NSLocalizedString("NiftyUtility_iCloudDataVersionIsLow_Title", comment: "iCloudとの同期に問題があります"))
                .textView(content: NSLocalizedString("NiftyUtility_iCloudDataVersionIsLow_Message", comment: "iCloud側に保存されているデータは、この ことせかい の扱っているデータよりも新しいバージョンになっているようです。このまま iCloud同期 を行い続けるにはアプリのバージョンアップが必要となります。\nなお、古いiOSでご利用中などでアプリのバージョンアップができない場合など、アプリのバージョンアップができない場合には iCloud同期 を解除して頂く必要があります。どちらかを選択してください。"), heightMultiplier: 0.55)
                .addButton(title: NSLocalizedString("NiftyUtility_iCloudDataVersionIsLow_AppVersionUpButton", comment: "バージョンアップ")) { (dialog) in
                    guard let url = URL(string: "https://apps.apple.com/jp/app/%E3%81%93%E3%81%A8%E3%81%9B%E3%81%8B%E3%81%84/id914344185") else { return }
                    RealmUtil.stopSyncEngine()
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                .addButton(title: NSLocalizedString("NiftyUtility_iCloudDataVersionIsLow_DisableiCloudButton", comment: "iCloud同期を停止")) { (dialog) in
                    dialog.dismiss(animated: false) {
                        StopiCloudSync(viewController: toplevelViewController)
                    }
                }
                .build().show()
            }
        }
    }
    #endif
    
    static func GetStackTrace() -> String {
        return Thread.callStackSymbols.map({$0.description}).joined(separator: "\n")
    }
    
    static func DoubleToInt(value:Double?) -> Int? {
        guard let value = value, !value.isNaN, !value.isInfinite else { return nil }
        return Int(value)
    }
    
    static func isTesting() -> Bool {
        // https://qiita.com/takecian/items/b106675e0b2ded41db57
        return NSClassFromString("XCTest") != nil // nil じゃなかったらテスト実行中
    }
}

extension String {
    /// startIndex 以上 endIndex以下 部分の文字を取り出して返します。
    /// 範囲外の部分は空文字列として扱われます。そのため、"hoge".NiftySubstring(from: 5, to: 10) は "" が返ります。
    func NiftySubstring(from:Int, to:Int) -> String {
        var s:String.Index = self.startIndex
        var e:String.Index = self.startIndex
        var from = from
        var to = to
        if from < 0 { from = 0 }
        if from > self.count { from = self.count }
        if to < from { to = from }
        if to > self.count { to = self.count }
        if let si = self.index(self.startIndex, offsetBy: from, limitedBy: self.endIndex) {
            s = si
            e = si
        }
        if let ei = self.index(self.startIndex, offsetBy: to, limitedBy: self.endIndex), ei > s {
            e = ei
        }
        return String(self[s..<e])
    }
    
    var firstLine:String? {
        get {
            var resultLine:String? = nil
            self.enumerateLines { line, stop in
                resultLine = line
                stop = true
            }
            return resultLine
        }
    }
    var lastLine:String? {
        get {
            // TODO: 巨大な文字列だとクッソ遅いです。後ろから "\r\n" とかを探したほうが良いです。
            var resultLine:String? = nil
            self.enumerateLines { line, stop in
                resultLine = line
            }
            return resultLine
        }
    }
    
    func getFirstLines(lineCount:Int, maxCharacterCount:Int) -> String {
        return String(self.split(separator: "\n").prefix(lineCount).joined(separator: "\n").prefix(maxCharacterCount))
    }
}

// ログをURL、発話、通知に飛ばします。何らかの問題でprintをデバッガから参照できない場合に使います。
// 一応、メモリ内に蓄えて後から参照するようなものもつけてます。
class DebugLogger: NSObject {
    @objc public static let shared = DebugLogger()
    var log:[String] = []
    let synthe = AVSpeechSynthesizer()
    var count = 0
    
    @objc static func SendLogToWeb(log:String, urlBase:String = "http://172.21.139.2/DebugLogger/") {
        if let url = URL(string: "\(urlBase)\(log)") {
            let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("HTTP Error: \(httpResponse.statusCode)")
                } else if let responseData = data {
                    let responseString = String(data: responseData, encoding: .utf8)
                    print("Response: \(responseString ?? "")")
                }
            }
            task.resume()
        } else {
            print("SendLogToWeb: Invalid URL")
        }
    }
    @objc static func SendLogToSpeech(log:String) {
        print("SendLogToSpeech: \(log)")
        let utt = AVSpeechUtterance(string: log)
        utt.voice = AVSpeechSynthesisVoice(language: "ja-JP") ?? AVSpeechSynthesisVoice()
        DebugLogger.shared.synthe.speak(utt)
    }
    @objc static func SendLogToNotification(log:String){
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm.ss"
        let currentTime = formatter.string(from: Date())
        
        let content = UNMutableNotificationContent()
        content.body = log
        
        // identifier は被らないようにします。そうすると複数の通知を流しても全部表示されるはずです(multithread で同時に呼ばれた場合はケアしてません)
        let request = UNNotificationRequest(identifier: "DebugLogger-\(currentTime)+\(DebugLogger.shared.count)", content: content, trigger: nil)
        DebugLogger.shared.count+=1
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知のスケジュールに失敗: \(error.localizedDescription)")
            } else {
                print(log)
            }
        }
    }
    
    @objc func AddLogToMemory(log:String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm.ss"
        let currentTime = formatter.string(from: Date())
        #if !os(watchOS)
        let isProtectedDataAvailable:Bool
        if Thread.isMainThread {
            isProtectedDataAvailable = UIApplication.shared.isProtectedDataAvailable
        }else{
            isProtectedDataAvailable = DispatchQueue.main.sync {
                return UIApplication.shared.isProtectedDataAvailable
            }
        }
        let logString = "\(currentTime):\n\(log)\nisProtectedDataAvailable: \(isProtectedDataAvailable)"
        #else
        let logString = "\(currentTime):\n\(log)"
        #endif
        self.log.append(logString)
    }
    @objc func GetMemoryLog() -> [String] {
        return self.log
    }
    @objc func GetMemoryLogString() -> String {
        return self.log.joined(separator: "\n\n")
    }
}

/*
 let startTime = DispatchTime.now()
 defer { FunctionExecutionMetrics.shared.recordExecutionTime(startTime: startTime, functionName: #function) }
 とかして使う。
 で、情報を集めた後に
 FunctionExecutionMetrics.shared.PrintMetrics()
 で表示する。
 */
class FunctionExecutionMetrics {
    static let shared = FunctionExecutionMetrics()

    private var executionMetrics:[String:[TimeInterval]] = [:]
    private init() {}

    func RecordExecutionTime(startTime:DispatchTime, functionName: String = #function) {
        let endTime = DispatchTime.now()
        let nanoSeconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let executionTime = TimeInterval(nanoSeconds / 1_000_000_000)

        if var metrics = executionMetrics[functionName] {
            metrics.append(executionTime)
            executionMetrics[functionName] = metrics
        }else{
            executionMetrics[functionName] = [executionTime]
        }
    }

    func ClearMetrics() {
        executionMetrics = [:]
    }
    
    func GetMetricsByString() -> String {
        var result = ""
        result += "=== Function Execution Metrics ===\n"
        for (functionName, metrics) in executionMetrics {
            if metrics.isEmpty {
                result += "\(functionName): not called?\n"
            }else{
                let sum = metrics.reduce(0.0, +)
                let count = metrics.count
                let average = sum / Double(metrics.count)
                result += "\(functionName): \(count) called. average: \(average), all: \(metrics)\n"
            }
        }
        return result
    }

    func PrintMetrics() {
        print(GetMetricsByString())
    }
}
