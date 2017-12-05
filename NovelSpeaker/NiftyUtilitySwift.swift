//
//  SampleUrlFetcher.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/19.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit

class NiftyUtilitySwift: NSObject {
    @objc public static func checkUrlAndConifirmToUser(viewController: UIViewController, url: URL, cookieArray: [String], depth: Int = 0) {
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
}
