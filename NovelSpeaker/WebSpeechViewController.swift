//
//  WebSpeechViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/05/17.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import UIKit
import WebKit
import RealmSwift
import IceCream
import Eureka

/*
 TODO:
 - 別ページに移動するための手段が目次等しかない
   - 末尾で引っ張って次のページに移動できたら良いね
 - 読む部分を全画面表示にする
   - 表示に関する設定項目をまとめた物がダイアログ的に表示できると良いかもしれん
 - ダークモード・ライトモードの切り替えに追従できてないかも？(traitCollectionDidChange 辺りを確認しよう)
 */

class WebSpeechViewController: UIViewController, StorySpeakerDeletgate, RealmObserverResetDelegate, WKScriptMessageHandler {
    var targetStoryID:String? = nil
    var isNeedResumeSpeech:Bool = false
    var isNeedUpdateReadDate:Bool = true
    var textWebView:CustomWKWebView? = nil
    let webSpeechTool = WebSpeechViewTool()
    var toggleInterfaceButton:UIButton? = nil
    
    var isNeedCollectDisplayLocation = false
    var webViewDisplayWholeText:String? = nil
    var speakerDisplayWholeText:String? = nil

    var globalStateObserverToken:NotificationToken? = nil
    var displaySettingObserverToken:NotificationToken? = nil
    var novelObserverToken:NotificationToken? = nil
    var novelObserverNovelID:String = ""
    var readingChapterStoryUpdateDate:Date = Date()
    var storyObserverToken:NotificationToken? = nil
    var storyObserverBulkStoryID:String = ""

    var currentReadStoryIDChangeAlertFloatingButton:FloatingButton? = nil

    var scrollPullAndFireHandler:ScrollPullAndFireHandler? = nil
    
    let previousChapterButton = UIButton()
    let nextChapterButton = UIButton()
    let chapterSlider = UISlider()
    let chapterPositionLabel = UILabel()
    var chapterPositionLabelWidthConstraint:NSLayoutConstraint? = nil
    
    var previousChapterBottomConstraint:NSLayoutConstraint? = nil
    var previousChapterTopConstraint:NSLayoutConstraint? = nil
    
    var lastChapterNumber:Int = -1
    
    var currentViewTypeCache:RealmDisplaySetting.ViewType? = nil

    @objc static weak var instance:WebSpeechViewController? = nil

    let myScriptNamespace = "NovelSpeaker_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let webView = WebSpeechViewController.createWkWebViewWithUserContentController(handler:self, myScriptNamespace:myScriptNamespace)
        self.textWebView = webView
        createUIComponents(webView: webView)
        RestartObservers()
        RealmUtil.RealmBlock { realm in
            self.loadFirstContentWith(realm: realm, storyID: targetStoryID, webView: webView)
        }
        setCustomUIMenu()
        WebSpeechViewController.instance = self
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    deinit {
        StopObservers()
        WebSpeechViewController.instance = nil
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        StorySpeaker.shared.AddDelegate(delegate: self)
        applyTheme()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        StorySpeaker.shared.RemoveDelegate(delegate: self)
        self.displayTopAndDownComponents(animated: false)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "WebViewToEditUserTextSegue" {
            if let nextViewController = segue.destination as? EditBookViewController {
                nextViewController.targetNovelID = RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID)
            }
        }else if segue.identifier == "WebViewReaderToNovelDetailViewPushSegue" {
            guard let nextViewController = segue.destination as? NovelDetailViewController else { return }
            nextViewController.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID)
        }
    }
    
    // background から redume した時に何故かWebViewの中身が空(真っ白)になる事があるぽいのでそれに対抗するために redume した時に呼ばれて再描画？する関数を用意しておきます。(´・ω・`)
    @objc func RedisplayWebView() {
        // MEMO: getCurrentDisplayLocation() でスクロールする起点を取得して、
        // overrideLocation にそれを渡す事で再表示しながら「現在表示されている部分へスクロールする」ようになるんだけれど……
        // WebViewOriginal みたいなのだと表示されている部分を検出できない可能性があるのよね。(´・ω・`)
        // あと、縦書きの時は1文字分ズレてしまうので、検出する時の xRaito と
        // スクロールする時の Raito を少し変える事で怪しく回避しようとしてるんだけど、
        // まぁ文字の大きさによって失敗するんよなこの方法だと
        let xRaito:Double
        let yRaito:Double
        let scrollRaito:Double
        if self.currentViewTypeCache == .webViewVertical || self.currentViewTypeCache == .webViewVertical2Column {
            xRaito = 0.99
            yRaito = 0.5
            scrollRaito = 0.95
        }else{
            xRaito = 0.5
            yRaito = 0.01
            scrollRaito = 0.95
        }
        self.webSpeechTool.getCurrentDisplayLocation(xRatio: xRaito, yRatio: yRaito) { currentDisplayLocation in
            RealmUtil.RealmBlock { realm in
                if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID) {
                    self.loadStoryWithoutStorySpeakerWith(story: story, overrideLocation: currentDisplayLocation, scrollRatio: scrollRaito)
                }
            }
        }
    }

    func StopObservers() {
        if let token = self.novelObserverToken {
            StorySpeaker.shared.RemoveUpdateReadDateWithoutNotifiningToken(token: token)
        }
        novelObserverToken = nil
        storyObserverToken = nil
        displaySettingObserverToken = nil
        globalStateObserverToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeDispaySetting()
        let storyID = StorySpeaker.shared.storyID
        observeStory(storyID: storyID)
        observeNovel(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))
        observeGlobalState()
    }
    
    func applyChapterListChange() {
        let storyID = StorySpeaker.shared.storyID
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
        var lastChapterNumber:Int = self.lastChapterNumber
        if lastChapterNumber <= 0 {
            RealmUtil.RealmBlock { (realm) -> Void in
                lastChapterNumber = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.lastChapterNumber ?? -1
            }
            if lastChapterNumber <= 0 {
                return
            }
            self.lastChapterNumber = lastChapterNumber
        }
        DispatchQueue.main.async {
            if chapterNumber <= 1 {
                self.previousChapterButton.isEnabled = false
            }else{
                self.previousChapterButton.isEnabled = true
            }
            if chapterNumber < lastChapterNumber {
                self.nextChapterButton.isEnabled = true
            }else{
                self.nextChapterButton.isEnabled = false
            }
            self.chapterSlider.minimumValue = 1.0
            self.chapterSlider.maximumValue = Float(lastChapterNumber) + Float(0.01)
            self.chapterSlider.value = Float(chapterNumber)
            
            self.chapterPositionLabel.text = "\(chapterNumber)/\(lastChapterNumber)"
            self.chapterPositionLabel.sizeToFit()
            if self.view.subviews.contains(self.chapterPositionLabel) {
                if let constraint = self.chapterPositionLabelWidthConstraint {
                    self.chapterPositionLabel.removeConstraint(constraint)
                }
                self.chapterPositionLabelWidthConstraint = self.chapterPositionLabel.widthAnchor.constraint(equalToConstant: self.chapterPositionLabel.frame.width)
                self.chapterPositionLabelWidthConstraint?.isActive = true
            }
        }
    }

    func createUIComponents(webView:WKWebView) {
        let safeAreaGuide:UILayoutGuide
        if #available(iOS 11.0, *) {
            safeAreaGuide = self.view.safeAreaLayoutGuide
        } else {
            safeAreaGuide = self.view.layoutMarginsGuide
        }

        self.view.addSubview(previousChapterButton)
        self.view.addSubview(nextChapterButton)
        self.view.addSubview(chapterSlider)
        self.view.addSubview(chapterPositionLabel)
        if #available(iOS 13.0, *), let img = UIImage(systemName: "arrowtriangle.left.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)) {
            previousChapterButton.setImage(img, for: .normal)
        } else {
            previousChapterButton.setTitle("◀", for: .normal)
        }
        previousChapterButton.sizeToFit()
        previousChapterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title1)
        previousChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        previousChapterButton.accessibilityLabel = NSLocalizedString("SpeechViewController_PreviousChapterButton_VoiceOverTitle", comment: "前のページ")
        previousChapterButton.addTarget(self, action: #selector(previousChapterButtonClicked(_:)), for: .touchUpInside)
        previousChapterButton.translatesAutoresizingMaskIntoConstraints = false
        
        if #available(iOS 13.0, *), let img = UIImage(systemName: "arrowtriangle.right.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)) {
            nextChapterButton.setImage(img, for: .normal)
        } else {
            nextChapterButton.setTitle("▶", for: .normal)
        }
        nextChapterButton.sizeToFit()
        nextChapterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title1)
        nextChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nextChapterButton.accessibilityLabel = NSLocalizedString("SpeechViewController_NextChapterButton_VoiceOverTitle", comment: "次のページ")
        nextChapterButton.addTarget(self, action: #selector(nextChapterButtonClicked(_:)), for: .touchUpInside)
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false
        
        chapterSlider.translatesAutoresizingMaskIntoConstraints = false
        chapterSlider.addTarget(self, action: #selector(chapterSliderValueChanged(_:)), for: .valueChanged)

        chapterPositionLabel.adjustsFontForContentSizeCategory = true
        chapterPositionLabel.translatesAutoresizingMaskIntoConstraints = false
        chapterPositionLabel.font = UIFont.preferredFont(forTextStyle: .body)
        applyChapterListChange()
        
        self.previousChapterBottomConstraint = previousChapterButton.bottomAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor, constant: -8)
        NSLayoutConstraint.activate([
            self.previousChapterBottomConstraint!,
            self.chapterSlider.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor),
            self.previousChapterButton.leftAnchor.constraint(equalTo: safeAreaGuide.leftAnchor, constant: 16),
            self.chapterSlider.leftAnchor.constraint(equalTo: self.previousChapterButton.rightAnchor, constant: 8),
            self.nextChapterButton.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor),
            self.nextChapterButton.leftAnchor.constraint(equalTo: self.chapterSlider.rightAnchor, constant: 8),
            self.chapterPositionLabel.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor),
            self.chapterPositionLabel.leftAnchor.constraint(equalTo: self.nextChapterButton.rightAnchor, constant: 8),
            self.chapterPositionLabel.rightAnchor.constraint(equalTo: safeAreaGuide.rightAnchor, constant: -16),
            self.previousChapterButton.widthAnchor.constraint(equalToConstant: 40),
            self.nextChapterButton.widthAnchor.constraint(equalToConstant: 40),
        ])
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(webView)
        let scrollPullAndFireHandler =  ScrollPullAndFireHandler(parent: self.view, scrollView: webView.scrollView, behavior: .horizontal)
        scrollPullAndFireHandler.invokeMethod = { isForward in
            switch isForward {
            case true:
                RealmUtil.RealmBlock { (realm) -> Void in
                    StorySpeaker.shared.LoadNextChapter(realm: realm)
                }
            case false:
                RealmUtil.RealmBlock { (realm) -> Void in
                    StorySpeaker.shared.LoadPreviousChapter(realm: realm, moveReadingPointToLast: true)
                }
            }
        }
        self.scrollPullAndFireHandler = scrollPullAndFireHandler
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: previousChapterButton.topAnchor, constant: -8),
            webView.leftAnchor.constraint(equalTo: safeAreaGuide.leftAnchor, constant: 8),
            webView.rightAnchor.constraint(equalTo: safeAreaGuide.rightAnchor, constant: -8),
        ])
        
        let toggleInterfaceButton = UIButton()
        toggleInterfaceButton.translatesAutoresizingMaskIntoConstraints = false
        toggleInterfaceButton.isAccessibilityElement = false
        //toggleInterfaceButton.backgroundColor = foregroundColor
        //toggleInterfaceButton.setTitleColor(backgroundColor, for: .normal)
        //toggleInterfaceButton.layer.cornerRadius = 3
        //toggleInterfaceButton.layer.borderWidth = 2
        //toggleInterfaceButton.layer.borderColor = foregroundColor.cgColor
        toggleInterfaceButton.clipsToBounds = true
        toggleInterfaceButton.addTarget(self, action: #selector(toggleInterfaceButtonClicked), for: .touchUpInside)
        self.toggleInterfaceButton = toggleInterfaceButton
        self.view.addSubview(toggleInterfaceButton)
        self.view.bringSubviewToFront(toggleInterfaceButton)
        self.view.sendSubviewToBack(webView)
        NSLayoutConstraint.activate([
            toggleInterfaceButton.bottomAnchor.constraint(equalTo: previousChapterButton.topAnchor, constant: -25),
            toggleInterfaceButton.rightAnchor.constraint(equalTo: safeAreaGuide.rightAnchor, constant: -25),
        ])
        assignHideToToggleInterfaceButton()
    }
    
    static func createInjectScriptAtDocumentStart(myScriptNamespace:String) -> String{
        return """
            \(myScriptNamespace) = {
                webkit: window.webkit
            };
            """
    }
    static func createInjectScriptAtDocumentEnd(myScriptNamespace:String) -> String{
        return """
            var console = {
                log: function(...args){
                    \(myScriptNamespace).webkit.messageHandlers.logging.postMessage(args);
                }
            };
            """
    }

    static func createWkWebViewWithUserContentController(handler:WebSpeechViewController, myScriptNamespace:String) -> CustomWKWebView {
        let injectScriptAtDocumentStart = createInjectScriptAtDocumentStart(myScriptNamespace:myScriptNamespace)
        let userScriptAtDocumentStart = WKUserScript(source: injectScriptAtDocumentStart, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let injectScriptAtDocumentEnd = createInjectScriptAtDocumentEnd(myScriptNamespace:myScriptNamespace)
        let userScriptAtDocumentEnd = WKUserScript(source: injectScriptAtDocumentEnd, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(userScriptAtDocumentStart)
        config.userContentController.addUserScript(userScriptAtDocumentEnd)
        config.userContentController.add(handler, name: "logging")
        return CustomWKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), configuration: config)
    }

    // WkWebView の JavaScript からのイベントを受け取るメッセージハンドラ
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "logging":
            print("WebViewConsole:", JavaScriptAnyToString(body: message.body))
        case "tapEvent":
            print("tapEvent from JavaScript");
        default:
            break
        }
    }
    func JavaScriptAnyToString(body:Any) -> String {
        if let number = body as? NSNumber {
            return "\(number)"
        }
        if let string = body as? String {
            return "\"\(string)\""
        }
        if let date = body as? NSDate {
            return "\(date)"
        }
        if let array = body as? NSArray {
            return array.reduce("[") { current, body in
                return current + (current.count <= 1 ? "" : ", ") + JavaScriptAnyToString(body: body)
            } + "]"
        }
        if let dictionary = body as? NSDictionary {
            return dictionary.reduce("{\n") { current, element in
                return current + (current.count <= 2 ? "" : "\n") + "  \(JavaScriptAnyToString(body: element.key)): \(JavaScriptAnyToString(body: element.value))"
            } + "\n}"
        }
        if body is NSNull {
            return "null"
        }
        return "unknown(\(String(describing: body))"
    }

    func hideTopAndDownComponents(animated:Bool = false, animateCompletion: (()->Void)? = nil) {
        if let bottomConstraint = self.previousChapterBottomConstraint {
            bottomConstraint.isActive = false
        }
        
        UIView.transition(with: self.view, duration: animated ? TimeInterval(UINavigationController.hideShowBarDuration) : 0, options: .curveEaseOut) {
            if let topConstraint = self.previousChapterTopConstraint { topConstraint.isActive = false }
            let safeAreaGuide:UILayoutGuide
            if #available(iOS 11.0, *) {
                safeAreaGuide = self.view.safeAreaLayoutGuide
            } else {
                safeAreaGuide = self.view.layoutMarginsGuide
            }
            self.previousChapterTopConstraint = self.previousChapterButton.topAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor)
            self.previousChapterTopConstraint?.isActive = true
            self.previousChapterButton.isHidden = true
            self.nextChapterButton.isHidden = true
            self.chapterSlider.isHidden = true
            self.chapterPositionLabel.isHidden = true
            self.navigationController?.setNavigationBarHidden(true, animated: animated)
            // setTabBarVisible を使うと SafeAreaGuide 周りが壊れるぽいので封印します。(´・ω・`)
            //self.tabBarController?.setTabBarVisible(visible:false, animated: animated, animateCompletion: animateCompletion)
            self.tabBarController?.tabBar.isHidden = true
        } completion: { finished in
            animateCompletion?()
        }
        self.assignDisplayToToggleInterfaceButton()
    }
    func displayTopAndDownComponents(animated:Bool = false, animateCompletion: (()->Void)? = nil) {
        if let topConstraint = self.previousChapterTopConstraint {
            topConstraint.isActive = false
        }
        UIView.transition(with: self.view, duration: animated ? TimeInterval(UINavigationController.hideShowBarDuration) : 0, options: .curveEaseOut) {
            if let bottomConstraint = self.previousChapterBottomConstraint { bottomConstraint.isActive = false }
            let safeAreaGuide:UILayoutGuide
            if #available(iOS 11.0, *) {
                safeAreaGuide = self.view.safeAreaLayoutGuide
            } else {
                safeAreaGuide = self.view.layoutMarginsGuide
            }
            self.previousChapterBottomConstraint = self.previousChapterButton.bottomAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor, constant: -8)
            self.previousChapterBottomConstraint?.isActive = true
            self.previousChapterButton.isHidden = false
            self.nextChapterButton.isHidden = false
            self.chapterSlider.isHidden = false
            self.chapterPositionLabel.isHidden = false

            self.navigationController?.setNavigationBarHidden(false, animated: animated)
            //self.tabBarController?.setTabBarVisible(visible:true, animated: animated, animateCompletion: animateCompletion)
            self.tabBarController?.tabBar.isHidden = false
        } completion: { finished in
            animateCompletion?()
        }
        self.assignHideToToggleInterfaceButton()
    }

    func loadStoryWithoutStorySpeakerWith(story:Story, overrideLocation:Int? = nil, scrollRatio: Double? = nil) {
        guard let webView = self.textWebView else { return }
        RealmUtil.RealmBlock { realm in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: story.novelID) else { return }
            let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm)
            let readLocation = story.readLocation(realm: realm)
            self.currentViewTypeCache = displaySetting?.viewType
            let novelTitle = novel.title
            DispatchQueue.main.async {
                self.title = novelTitle
            }
            if let lastChapterNumber = novel.lastChapterNumber {
                self.lastChapterNumber = lastChapterNumber
            }
            let aliveButtonSettings = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() ?? SpeechViewButtonSetting.defaultSetting
            self.assignUpperButtons(novelID: novel.novelID, novelType: novel.type, aliveButtonSettings: aliveButtonSettings)
            self.webViewDisplayWholeText = nil
            if story.url.count > 0, novel.type == .URL, let url = URL(string: story.url), displaySetting?.viewType == .webViewOriginal {
                self.isNeedCollectDisplayLocation = true
                let siteInfoArray = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: story.url)
                let request = URLRequest(url: url)
                self.webSpeechTool.loadUrl(webView: webView, request: request, siteInfoArray: siteInfoArray, completionHandler: {
                    self.webSpeechTool.getSpeechText { text in
                        self.webViewDisplayWholeText = text
                    }
                    //self.webSpeechTool.hideNotPageElement {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1) {
                        if let overrideLocation = overrideLocation, overrideLocation >= 0 {
                            self.webSpeechTool.scrollToIndex(location: overrideLocation, length: 1, scrollRatio: scrollRatio ?? 0.5)
                        }else{
                            self.webSpeechTool.scrollToIndex(location: readLocation, length: 1, scrollRatio: 0.3)
                        }
                    }
                    //}
                })
                return
            }
            if let type = displaySetting?.viewType, type == .webViewHorizontal || type == .webViewVertical || type == .webViewVertical2Column {
                self.scrollPullAndFireHandler?.setupFor(scrollBehavior: type == .webViewVertical ? .vertical : .horizontal)
                if story.chapterNumber <= 1 {
                    self.scrollPullAndFireHandler?.isBackwardEnabled = false
                }else{
                    self.scrollPullAndFireHandler?.isBackwardEnabled = true
                }
                if let lastChapterNumber = novel.lastChapterNumber, lastChapterNumber == story.chapterNumber {
                    self.scrollPullAndFireHandler?.isForwardEnabled = false
                }else{
                    self.scrollPullAndFireHandler?.isForwardEnabled = true
                }
            }
            self.isNeedCollectDisplayLocation = false
            let (fg, bg) = getForegroundBackgroundColor()
            let font = displaySetting?.font
            let viewType = displaySetting?.viewType
            let lineSpacingDisplayValue = displaySetting?.lineSpacingDisplayValue
            DispatchQueue.main.async {
                self.webSpeechTool.applyFromNovelSpeakerString(webView: webView, content: story.content, foregroundColor: fg, backgroundColor: bg, font: font, viewType: viewType, lineSpacingDisplayValue: lineSpacingDisplayValue, baseURL: nil) {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1) {
                        if let overrideLocation = overrideLocation, overrideLocation > 0 {
                            self.webSpeechTool.scrollToIndex(location: overrideLocation, length: 1, scrollRatio: scrollRatio ?? 0.5)
                        }else{
                            self.webSpeechTool.scrollToIndex(location: readLocation, length: 1, scrollRatio: 0.3)
                        }
                    }
                }
            }
        }
    }
    
    func loadNovelWith(realm:Realm, story:Story, webView:WKWebView) {
        webView.loadHTMLString("<html><body class='NovelSpeakerBody'>\(NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))</body></html>", baseURL: nil)
        StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { story in
            self.loadStoryWithoutStorySpeakerWith(story: story)
        }
    }
    
    func loadFirstContentWith(realm:Realm, storyID:String?, webView:WKWebView) {
        guard let storyID = storyID, let targetStory = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) else {
            webView.loadHTMLString("<html><body class='NovelSpeakerBody'>\( NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))</body></html>", baseURL: nil)
            return
        }
        loadNovelWith(realm: realm, story: targetStory, webView: webView)
    }
    
    func checkDummySpeechFinished() {
        if StorySpeaker.shared.isDummySpeechAlive() {
            DispatchQueue.main.async {
                let dialog = NiftyUtility.EasyDialogBuilder(self).text(content: NSLocalizedString("SpeechViewController_WaitingSpeakerReady", comment: "話者の準備が整うのを待っています。"))
                    .build()
                dialog.show()
                func waitDummySpeechFinish() {
                    if StorySpeaker.shared.isDummySpeechAlive() == false {
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        waitDummySpeechFinish()
                    }
                }
                waitDummySpeechFinish()
            }
        }
    }
    
    func applyThemeColor(backgroundColor:UIColor, foregroundColor:UIColor, indicatorStyle:UIScrollView.IndicatorStyle, barStyle:UIBarStyle) {
        
        self.view.backgroundColor = backgroundColor;
        if #available(iOS 13.0, *) {
            // nothing.
        }else{
            self.nextChapterButton.backgroundColor = backgroundColor
            self.nextChapterButton.setTitleColor(self.view.tintColor, for: .normal)
            self.nextChapterButton.setTitleColor(self.view.tintColor.withAlphaComponent(0.5), for: .disabled)
            self.previousChapterButton.backgroundColor = backgroundColor
            self.previousChapterButton.setTitleColor(self.view.tintColor, for: .normal)
            self.previousChapterButton.setTitleColor(self.view.tintColor.withAlphaComponent(0.5), for: .disabled)
        }
        self.chapterSlider.backgroundColor = backgroundColor
        self.chapterPositionLabel.backgroundColor = backgroundColor
        self.chapterPositionLabel.textColor = foregroundColor
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: foregroundColor]
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = barStyle
        // WebView にはCSSで注入する
        applyFgBgColorToWebView(foregroundColor: foregroundColor, backgroundColor: backgroundColor)
        // 引っ張って次ページへ移動の奴にも色を設定する
        self.scrollPullAndFireHandler?.setColor(foreground: foregroundColor, background: backgroundColor)
    }
    
    func getForegroundBackgroundColor() -> (UIColor, UIColor) {
        var backgroundColor = UIColor.white
        var foregroundColor = UIColor.black
        if #available(iOS 13.0, *) {
            backgroundColor = UIColor.systemBackground
            foregroundColor = UIColor.label
        }
        RealmUtil.RealmBlock { realm in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if let fgColor = globalState.foregroundColor {
                    foregroundColor = fgColor
                }
                if let bgColor = globalState.backgroundColor {
                    backgroundColor = bgColor
                }
            }
        }
        return (foregroundColor, backgroundColor)
    }
    
    func applyFgBgColorToWebView(foregroundColor:UIColor, backgroundColor:UIColor) {
        let foregroundColorCSS:String
        if let fgColor = foregroundColor.cssColor {
            foregroundColorCSS = "color: \(fgColor)"
        }else{
            foregroundColorCSS = ""
        }
        let backgroundColorCSS:String
        if let bgColor = backgroundColor.cssColor {
            backgroundColorCSS = "background-color: \(bgColor)"
        }else{
            backgroundColorCSS = ""
        }
        let cssColorSetting = """
body.NovelSpeakerBody {
    \(foregroundColorCSS);
    \(backgroundColorCSS);
}
"""
        self.webSpeechTool.assignCSS(cssString: cssColorSetting)
    }
    
    func applyTheme() {
        let (foregroundColor, backgroundColor) = getForegroundBackgroundColor()
        var indicatorStyle = UIScrollView.IndicatorStyle.default
        var barStyle = UIBarStyle.default
        
        var red:CGFloat = -1.0
        var green:CGFloat = -1.0
        var blue:CGFloat = -1.0
        var alpha:CGFloat = -1.0
        if backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            if ((Float(red) + Float(green) + Float(blue)) / 3.0) < 0.5 {
                indicatorStyle = UIScrollView.IndicatorStyle.white
                barStyle = UIBarStyle.black
            }
        }

        applyThemeColor(backgroundColor: backgroundColor, foregroundColor: foregroundColor, indicatorStyle: indicatorStyle, barStyle: barStyle)
    }
    
    // MARK: Realm の Observer 周り
    func observeGlobalState() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            self.globalStateObserverToken = globalState.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .change(_, let propertys):
                    for property in propertys {
                        if property.name == "speechViewButtonSettingArrayData" {
                            RealmUtil.RealmBlock { (realm) -> Void in
                                let storyID = StorySpeaker.shared.storyID
                                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.RemoveRealmLink(), let buttonSettings = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() else { return }
                                self.assignUpperButtons(novelID: novel.novelID, novelType: novel.type, aliveButtonSettings: buttonSettings)
                            }
                        }
                        if property.name == "isEnableSwipeOnStoryView" {
                            // TODO: このオプションどういう扱いにする？横書きと縦書き表示で左右スワイプ上下スワイプの意味が変わるので、「設定タブ」の「小説本文画面での左右スワイプでページめくりが出来るようにする」って文言だと「左右」の意味が固定されちゃってて困る事になる。
                            if let value = property.newValue as? Bool {
                                DispatchQueue.main.async {
                                    if value == true {
                                        //self.assignSwipeRecognizer()
                                    }else{
                                        //self.removeSwipeRecognizer()
                                    }
                                }
                            }
                        }
                    }
                default:
                    break
                }
            })
        }
    }
    
    func observeDispaySetting() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) else { return }
            displaySettingObserverToken = displaySetting.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .change(_, let properties):
                    for property in properties {
                        // ViewType が normal に変わっていたら元画面に戻します。
                        // WARN: ViewType が normal 以外の物は全て WebSpeechViewController で処理できるという仮定を置いているので危険です。
                        if property.name == "m_ViewType", let newValue = property.newValue as? String, newValue == RealmDisplaySetting.ViewType.normal.rawValue {
                            DispatchQueue.main.async {
                                self.navigationController?.popViewController(animated: true)
                            }
                            return
                        }
                        if property.name == "textSizeValue" || property.name == "fontID" || property.name == "lineSpacing" || property.name == "m_ViewType" {
                            DispatchQueue.main.async {
                                RealmUtil.RealmBlock { (realm) -> Void in
                                    guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID) else { return }
                                    self.loadStoryWithoutStorySpeakerWith(story: story)
                                }
                            }
                        }
                    }
                case .error(_):
                    break
                case .deleted:
                    break
                }
            })
        }
    }

    func observeStory(storyID:String) {
        if storyObserverBulkStoryID == RealmStoryBulk.StoryIDToBulkID(storyID: storyID) { return }
        self.storyObserverToken = nil
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let storyBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: storyID) else { return }
            storyObserverBulkStoryID = storyBulk.id
            self.storyObserverToken = storyBulk.observe({ [weak self] (change) in
                guard let self = self else { return }
                let targetStoryID = StorySpeaker.shared.storyID
                guard self.storyObserverBulkStoryID == RealmStoryBulk.StoryIDToBulkID(storyID: targetStoryID) else {
                    return
                }
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        // content が書き換わった時のみを監視します。
                        // でないと lastReadDate とかが書き換わった時にも表示の更新が走ってしまいます。
                        let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: targetStoryID)
                        if property.name == "storyListAsset", let newValue = property.newValue as? CreamAsset, let storyArray = RealmStoryBulk.StoryCreamAssetToStoryArray(asset: newValue) {
                            // [Story] に変換できた
                            if let story = RealmStoryBulk.StoryBulkArrayToStory(storyArray: storyArray, chapterNumber: chapterNumber) {
                                // 今開いている Story が書き換えられているぽい
                                if story.chapterNumber == chapterNumber, story.content != self.speakerDisplayWholeText {
                                    self.speakerDisplayWholeText = story.content
                                    DispatchQueue.main.async {
                                        self.loadStoryWithoutStorySpeakerWith(story: story)
                                    }
                                }
                            }else{
                                // 今開いている Story が存在しなかった(恐らくは最後の章を開いていて、その章が削除された)
                                if let lastStory = storyArray.last {
                                    DispatchQueue.main.async {
                                        StorySpeaker.shared.SetStory(story: lastStory, withUpdateReadDate: true)
                                    }
                                }
                            }
                        }
                    }
                case .deleted:
                    break
                }
            })
        }
    }

    func observeNovel(novelID:String) {
        if novelObserverNovelID == RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID) { return }
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            self.lastChapterNumber = novel.lastChapterNumber ?? -1
            novelObserverNovelID = novelID
            self.novelObserverToken = novel.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        if property.name == "title", let newValue = property.newValue as? String {
                            DispatchQueue.main.async {
                                self.title = newValue
                            }
                        }
                        if property.name == "m_lastChapterStoryID", let newValue = property.newValue as? String {
                            let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: newValue)
                            if chapterNumber > 0 && self.lastChapterNumber != chapterNumber {
                                self.lastChapterNumber = chapterNumber
                                self.applyChapterListChange()
                            }
                        }
                        if property.name == "m_readingChapterStoryID", let newReadingChapterStoryID = property.newValue as? String, newReadingChapterStoryID != StorySpeaker.shared.storyID, self.readingChapterStoryUpdateDate < Date(timeIntervalSinceNow: -1.5) {
                            self.currentReadingStoryIDChangedEventHandler(newReadingStoryID: newReadingChapterStoryID)
                        }
                     }
                case .deleted:
                    break
                }
            })
            if let token = self.novelObserverToken {
                StorySpeaker.shared.AddUpdateReadDateWithoutNotificationToken(token: token)
            }
        }
    }
    
    func disableCurrentReadingStoryChangeFloatingButton() {
        guard let oldFloatingButton = self.currentReadStoryIDChangeAlertFloatingButton else { return }
        self.currentReadStoryIDChangeAlertFloatingButton = nil
        DispatchQueue.main.async {
            oldFloatingButton.hide()
        }
    }
    func currentReadingStoryIDChangedEventHandler(newReadingStoryID:String) {
        let currentStoryID = StorySpeaker.shared.storyID
        guard newReadingStoryID != currentStoryID else { return }
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: newReadingStoryID) else { return }
            let newChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: newReadingStoryID)
            DispatchQueue.main.async {
                self.currentReadStoryIDChangeAlertFloatingButton = FloatingButton.createNewFloatingButton()
                guard let floatingButton = self.currentReadStoryIDChangeAlertFloatingButton else { return }
                floatingButton.assignToView(view: self.view, currentOffset: CGPoint(x: -1, y: -1), text: String(format: NSLocalizedString("SpeechViewController_CurrentReadingStoryChangedFloatingButton_Format", comment: "他端末で更新された %d章 へ移動"), newChapterNumber), animated: true, bottomConstraintAppend: -32.0) {
                    StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: false)
                    floatingButton.hideAnimate()
                }
            }
        }
    }

    //MARK: 上のボタン群の設定
    var startStopButtonItem:UIBarButtonItem? = nil
    var shareButtonItem:UIBarButtonItem? = nil
    var skipBackwardButtonItem:UIBarButtonItem? = nil
    var skipForwardButtonItem:UIBarButtonItem? = nil
    var showTableOfContentsButtonItem:UIBarButtonItem? = nil
    func assignUpperButtons(novelID: String, novelType: NovelType, aliveButtonSettings:[SpeechViewButtonSetting]) {
        var barButtonArray:[UIBarButtonItem] = []
        
        for buttonSetting in aliveButtonSettings {
            if buttonSetting.isOn == false { continue }
            switch buttonSetting.type {
            case .openCurrentWebPage:
                let webPageButton = UIBarButtonItem(image: UIImage(named: "earth"), style: .plain, target: self, action: #selector(openCurrentWebPageButtonClicked(_:)))
                webPageButton.accessibilityLabel = NSLocalizedString("SpeechViewController_CurrentWebPageButton_VoiceOverTitle", comment: "現在のページをWeb取込タブで開く")
                if novelType == .URL {
                    barButtonArray.append(webPageButton)
                }
            case .openWebPage:
                let webPageButton = UIBarButtonItem(image: UIImage(named: "earth"), style: .plain, target: self, action: #selector(safariButtonClicked(_:)))
                webPageButton.accessibilityLabel = NSLocalizedString("SpeechViewController_WebPageButton_VoiceOverTitle", comment: "Web取込タブで開く")
                if novelType == .URL {
                    barButtonArray.append(webPageButton)
                }
            case .reload:
                if novelType == .URL {
                    barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(urlRefreshButtonClicked(_:))))
                }
            case .share:
                if novelType == .URL {
                    let shareButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action:   #selector(shareButtonClicked(_:)))
                    self.shareButtonItem = shareButtonItem
                    barButtonArray.append(shareButtonItem)
                }
            case .search:
                barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(searchButtonClicked(_:))))
            case .edit:
                barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Edit", comment: "編集"), style: .plain, target: self, action: #selector(editButtonClicked(_:))))
            case .detail:
                barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Detail", comment: "詳細"), style: .plain, target: self, action: #selector(detailButtonClicked(_:))))
            case .backup:
                barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_BackupButton", comment: "バックアップ"), style: .plain, target: self, action: #selector(backupButtonClicked(_:))))
                break
            case .skipBackward:
                let skipBackwardButtonItem:UIBarButtonItem
                if #available(iOS 13.0, *) {
                    skipBackwardButtonItem = UIBarButtonItem(image: UIImage(systemName: "gobackward.30"), style: .plain, target: self, action: #selector(skipBackwardButtonClicked(_:)))
                    skipBackwardButtonItem.accessibilityLabel = NSLocalizedString("SpeechViewController_SkipBackwardButtonTitle", comment: "巻き戻し")
                } else {
                    skipBackwardButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_SkipBackwardButtonTitle", comment: "巻き戻し"), style: .plain, target: self, action: #selector(skipBackwardButtonClicked(_:)))
                }
                skipBackwardButtonItem.isEnabled = false
                self.skipBackwardButtonItem = skipBackwardButtonItem
                barButtonArray.append(skipBackwardButtonItem)
            case .skipForward:
                let skipForwardButtonItem:UIBarButtonItem
                if #available(iOS 13.0, *) {
                    skipForwardButtonItem = UIBarButtonItem(image: UIImage(systemName: "goforward.30"), style: .plain, target: self, action: #selector(skipForwardButtonClicked(_:)))
                    skipForwardButtonItem.accessibilityLabel = NSLocalizedString("SpeechViewController_SkipForwardButtonTitle", comment: "少し先へ")
                } else {
                    skipForwardButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_SkipForwardButtonTitle", comment: "少し先へ"), style: .plain, target: self, action: #selector(skipForwardButtonClicked(_:)))
                }
                skipForwardButtonItem.isEnabled = false
                self.skipForwardButtonItem = skipForwardButtonItem
                barButtonArray.append(skipForwardButtonItem)
            case .showTableOfContents:
                let showTableOfContentsButtonItem:UIBarButtonItem
                if #available(iOS 13.0, *) {
                    showTableOfContentsButtonItem = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(showTableOfContentsButtonClicked(_:)))
                    showTableOfContentsButtonItem.accessibilityLabel = NSLocalizedString("SpeechViewController_ShowTableOfContentsButtonTitle", comment: "目次")
                } else {
                    showTableOfContentsButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_ShowTableOfContentsButtonTitle", comment: "目次"), style: .plain, target: self, action: #selector(showTableOfContentsButtonClicked(_:)))
                }
                self.showTableOfContentsButtonItem = showTableOfContentsButtonItem
                barButtonArray.append(showTableOfContentsButtonItem)
            default:
                break
            }
        }
        let startStopButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Speak", comment: "Speak"), style: .plain, target: self, action: #selector(startStopButtonClicked(_:)))
        self.startStopButtonItem = startStopButtonItem
        barButtonArray.append(startStopButtonItem)
        barButtonArray.reverse()

        DispatchQueue.main.async {
            self.navigationItem.rightBarButtonItems = barButtonArray
        }
    }
    
    //MARK: @objc Delegate methods
    @objc func backupButtonClicked(_ sender: UIBarButtonItem) {
        let storyID = StorySpeaker.shared.storyID
        guard storyID.count > 0 else { return }
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        NovelSpeakerUtility.CreateNovelOnlyBackup(novelIDArray: [novelID], viewController: self) { (fileUrl, fileName) in
            DispatchQueue.main.async {
                let activityViewController = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
                let frame = UIScreen.main.bounds
                activityViewController.popoverPresentationController?.sourceView = self.view
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.width / 2 - 60, y: frame.size.height - 50, width: 120, height: 50)
                self.present(activityViewController, animated: true, completion: nil)
            }
        }
    }
    @objc func editButtonClicked(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: "WebViewToEditUserTextSegue", sender: self)
    }
    @objc func detailButtonClicked(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: "WebViewReaderToNovelDetailViewPushSegue", sender: self)
    }
    @objc func searchButtonClicked(_ sender: UIBarButtonItem) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
            func searchFunc(searchString:String?){
                NiftyUtility.EasyDialogNoButton(
                    viewController: self,
                    title: NSLocalizedString("SpeechViewController_NowSearchingTitle", comment: "検索中"),
                    message: nil) { (searchingDialog) in
                    RealmUtil.RealmBlock { (realm) -> Void in
                        var displayTextArray:[String] = []
                        let storyID = StorySpeaker.shared.storyID
                        RealmStoryBulk.SearchAllStoryFor(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID)) { (story) -> Bool in
                            guard let searchString = searchString else { return true }
                            if searchString.count <= 0 { return true }
                            return story.content.contains(searchString)
                        } iterate: { (story) in
                            displayTextArray.append("\(story.chapterNumber): \(story.GetSubtitle())")
                        }
                        var selectedText:String? = nil
                        if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) {
                            selectedText = "\(story.chapterNumber): " + story.GetSubtitle()
                        }
                        let picker = PickerViewDialog.createNewDialog(displayTextArray: displayTextArray, firstSelectedString: selectedText) { (selectedText) in
                            guard let number = selectedText.components(separatedBy: ":").first, let chapterNumber = Int(number), let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), chapterNumber: chapterNumber)) else { return }
                            StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
                        }
                        searchingDialog.dismiss(animated: false) {
                            picker?.popup(completion: nil)
                        }
                    }
                }
            }
            
            NiftyUtility.EasyDialogTextInput2Button(
                viewController: self,
                title: NSLocalizedString("SpeechViewController_SearchDialogTitle", comment: "検索"),
                message: NSLocalizedString("SpeechViewController_SearchDialogMessage", comment: "本文中から文字列を検索します"),
                textFieldText: nil,
                placeHolder: NSLocalizedString("SpeechViewController_SearchDialogPlaceholderText", comment: "空文字列で検索すると全ての章がリストされます"),
                leftButtonText: NSLocalizedString("Cancel_button", comment: "Cancel"),
                rightButtonText: NSLocalizedString("OK_button", comment: "OK"),
                leftButtonAction: nil,
                rightButtonAction: { (filterText) in
                    NovelSpeakerUtility.SearchStoryFor(selectedStoryID: StorySpeaker.shared.storyID, viewController: self, searchString: filterText) { (story) in
                        StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
                    }
                },
                shouldReturnIsRightButtonClicked: true,
                completion: nil)
        }
    }

    @objc func shareButtonClicked(_ sender: UIBarButtonItem) {
        let storyID = StorySpeaker.shared.storyID
        NovelSpeakerUtility.ShareStory(viewController: self, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), barButton: self.shareButtonItem)
    }
    
    @objc func urlRefreshButtonClicked(_ sender: UIBarButtonItem) {
        let storyID = StorySpeaker.shared.storyID
        NovelDownloadQueue.shared.addQueue(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))
    }
    @objc func openCurrentWebPageButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let urlString = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID)?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    @objc func safariButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            let storyID = StorySpeaker.shared.storyID
            guard storyID.count > 0, let urlString = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    
    func CheckFolderAndStartSpeech() {
        RealmUtil.RealmBlock { realm in
            self.disableCurrentReadingStoryChangeFloatingButton()
            self.webSpeechTool.getSelectedLocation { location in
                print("startStopButtonClicked selectedLocation: \(location ?? -1)")
                RealmUtil.RealmBlock { realm in
                    if let location = location {
                        StorySpeaker.shared.setReadLocationWith(realm: realm, location: location)
                    }
                    func runNextSpeech(nextFolder:RealmNovelTag?){
                        StorySpeaker.shared.targetFolderNameForGoToNextSelectedFolderdNovel = nextFolder?.name
                        RealmUtil.RealmBlock { realm in
                            StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面(Speakボタンを押した 又は 本棚画面で「▶︎ 再生:〜」を選択した 又は 次のフォルダの小説に移行した).\(#function)", isNeedRepeatSpeech: true)
                            self.checkDummySpeechFinished()
                        }
                    }
                    let storyID = StorySpeaker.shared.storyID
                    if let repeatType = RealmGlobalState.GetInstanceWith(realm: realm)?.repeatSpeechType, repeatType == .GoToNextSelectedFolderdNovel, let folderArray = RealmNovelTag.SearchWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), type: RealmNovelTag.TagType.Folder) {
                        let folderArray = Array(folderArray)
                        if folderArray.count == 1, let folder = folderArray.first {
                            runNextSpeech(nextFolder: folder)
                            return
                        }else if folderArray.count > 1 {
                            EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: { vc in
                                let section = Section(NSLocalizedString("SpeechViewController_SelectFolder_Title", comment: "連続再生するフォルダを選択"))
                                for folder in folderArray {
                                    section <<< LabelRow() {
                                        $0.title = folder.name
                                        $0.cell.textLabel?.numberOfLines = 0
                                        $0.cell.accessibilityTraits = .button
                                    }.onCellSelection({ (_, row) in
                                        runNextSpeech(nextFolder: folder)
                                        vc.close(animated: true, completion: nil)
                                    })
                                }
                                vc.form +++ section
                                vc.form +++ Section()
                                <<< LabelRow() {
                                    $0.title = NSLocalizedString("SpeechViewController_NotUseNextSpeechNovel", comment: "続けて再生を使わずに開始")
                                    $0.cell.textLabel?.numberOfLines = 0
                                    $0.cell.accessibilityTraits = .button
                                }.onCellSelection({ (_, row) in
                                    runNextSpeech(nextFolder: nil)
                                    vc.close(animated: true, completion: nil)
                                })
                                <<< LabelRow() {
                                    $0.title = NSLocalizedString("Cancel", comment: "Cancel")
                                    $0.cell.textLabel?.numberOfLines = 0
                                    $0.cell.accessibilityTraits = .button
                                }.onCellSelection({ (_, row) in
                                    vc.close(animated: true, completion: nil)
                                })
                            }, parentViewController: self, animated: true, completion: nil)
                            return
                        }
                    }
                    runNextSpeech(nextFolder: nil)
                }
            }
        }
    }

    @objc func startStopButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            if StorySpeaker.shared.isPlayng {
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
            }else{
                self.CheckFolderAndStartSpeech()
            }
        }
    }
    @objc func skipBackwardButtonClicked(_ sender: UIBarButtonItem) {
        if StorySpeaker.shared.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: false) {
                    StorySpeaker.shared.SkipBackward(realm: realm, length: 30) {
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面.\(#function)", isNeedRepeatSpeech: true)
                    }
                }
            }
        }
    }
    @objc func skipForwardButtonClicked(_ sender: UIBarButtonItem) {
        if StorySpeaker.shared.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: false) {
                    StorySpeaker.shared.SkipForward(realm: realm, length: 30) {
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面.\(#function)", isNeedRepeatSpeech: true)
                    }
                }
            }
        }
    }
    @objc func showTableOfContentsButtonClicked(_ sender: UIBarButtonItem) {
        NovelSpeakerUtility.SearchStoryFor(selectedStoryID: StorySpeaker.shared.storyID, viewController: self, searchString: nil) { (story) in
            StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
        }
    }
    
    @objc func chapterSliderValueChanged(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        let storyID = StorySpeaker.shared.storyID
        let chapterNumber = Int(self.chapterSlider.value + 0.5)
        let targetStoryID = RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), chapterNumber: chapterNumber)
        //self.chapterSlider.value = Float(chapterNumber)
        RealmUtil.RealmBlock { (realm) -> Void in
            if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: targetStoryID) {
                StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
            }
        }
    }
    
    @objc func previousChapterButtonClicked(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadPreviousChapter(realm: realm)
        }
    }
    @objc func nextChapterButtonClicked(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadNextChapter(realm: realm)
        }
    }

    
    func assignHideToToggleInterfaceButton() {
        guard let toggleInterfaceButton = self.toggleInterfaceButton else { return }
        DispatchQueue.main.async {
            if #available(iOS 13.0, *), let img = UIImage(systemName: "dock.arrow.down.rectangle", withConfiguration:  UIImage.SymbolConfiguration(pointSize: 24, weight: .light, scale: .default)) {
                toggleInterfaceButton.setImage(img, for: .normal)
            } else {
                toggleInterfaceButton.setTitle(NSLocalizedString("WebSpechViewController_ToggleInterfaceButton_Hide_Title", comment: "本文のみへ"), for: .normal)
                let (foregroundColor, backgroundColor) = self.getForegroundBackgroundColor()
                toggleInterfaceButton.backgroundColor = foregroundColor
                toggleInterfaceButton.setTitleColor(backgroundColor, for: .normal)
            }
        }
    }
    func assignDisplayToToggleInterfaceButton() {
        guard let toggleInterfaceButton = self.toggleInterfaceButton else { return }
        DispatchQueue.main.async {
            if #available(iOS 13.0, *), let img = UIImage(systemName: "dock.arrow.up.rectangle", withConfiguration:  UIImage.SymbolConfiguration(pointSize: 24, weight: .light, scale: .default)) {
                toggleInterfaceButton.setImage(img, for: .normal)
            } else {
                toggleInterfaceButton.setTitle(NSLocalizedString("WebSpechViewController_ToggleInterfaceButton_Display_Title", comment: "ボタン表示"), for: .normal)
                let (foregroundColor, backgroundColor) = self.getForegroundBackgroundColor()
                toggleInterfaceButton.backgroundColor = foregroundColor
                toggleInterfaceButton.setTitleColor(backgroundColor, for: .normal)
            }
        }
    }

    @objc func toggleInterfaceButtonClicked(_ sender:UIButton){
        func highlight(overrideLocation:Int?, scrollRatio:Double?){
            RealmUtil.RealmBlock { realm in
                guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID) else { return }
                let readLocation = story.readLocation(realm: realm)
                DispatchQueue.main.async {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1) {
                        if let overrideLocation = overrideLocation, overrideLocation > 0 {
                            self.webSpeechTool.scrollToIndex(location: overrideLocation, length: 1, scrollRatio: scrollRatio ?? 0.5)
                        }else{
                            self.webSpeechTool.scrollToIndex(location: readLocation, length: 1, scrollRatio: 0.3)
                        }
                    }
                }
            }
        }
        print("width: \(self.textWebView?.frame.width ?? -1)")
        let xRaito:Double
        let yRaito:Double
        let scrollRaito:Double
        if self.currentViewTypeCache == .webViewVertical || self.currentViewTypeCache == .webViewVertical2Column {
            xRaito = 0.99
            yRaito = 0.5
            scrollRaito = 0.95
        }else{
            xRaito = 0.5
            yRaito = 0.03
            scrollRaito = 0.95
        }
        self.webSpeechTool.getCurrentDisplayLocation(xRatio: xRaito, yRatio: yRaito) { currentDisplayLocation in
            if((self.navigationController?.isNavigationBarHidden ?? false) == false){
                self.hideTopAndDownComponents(animated: false, animateCompletion: { highlight(overrideLocation: currentDisplayLocation, scrollRatio: scrollRaito) })
            }else{
                self.displayTopAndDownComponents(animated: false, animateCompletion: { highlight(overrideLocation: currentDisplayLocation, scrollRatio: scrollRaito) })
            }
        }
    }
    
    @objc func leftSwipe(_ sender: UISwipeGestureRecognizer) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadNextChapter(realm: realm)
        }
    }
    @objc func rightSwipe(_ sender: UISwipeGestureRecognizer) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadPreviousChapter(realm: realm)
        }
    }

    
    //MARK: StorySpeakerDeletgate handler
    func storySpeakerStartSpeechEvent(storyID:String) {
        DispatchQueue.main.async {
            self.startStopButtonItem?.title = NSLocalizedString("SpeechViewController_Stop", comment: "Stop")
            self.skipBackwardButtonItem?.isEnabled = true
            self.skipForwardButtonItem?.isEnabled = true
            self.removeCustomUIMenu()
        }
    }
    func storySpeakerStopSpeechEvent(storyID:String) {
        DispatchQueue.main.async {
            self.startStopButtonItem?.title = NSLocalizedString("SpeechViewController_Speak", comment: "Speak")
            self.skipBackwardButtonItem?.isEnabled = false
            self.skipForwardButtonItem?.isEnabled = false
            self.setCustomUIMenu()
        }
    }
    func storySpeakerUpdateReadingPoint(storyID:String, range:NSRange) {
        //print("storySpeakerUpdateReadingPoint(range: \(range.location), \(range.length))")
        let location:Int
        if self.isNeedCollectDisplayLocation, let webViewWholeText = self.webViewDisplayWholeText, let speakerWholeText = self.speakerDisplayWholeText, webViewWholeText.count != speakerWholeText.count, speakerWholeText.count > 0 {
            location = Int(Double(webViewWholeText.count) * Double(range.location) / Double(speakerWholeText.count))
        }else{
            location = range.location
        }
        self.webSpeechTool.highlightSpeechLocation(location: location, length: range.length) {
            self.webSpeechTool.scrollToIndex(location: location, length: 1, scrollRatio: 0.3)
        }
    }
    func storySpeakerStoryChanged(story:Story) {
        self.readingChapterStoryUpdateDate = Date()
        self.speakerDisplayWholeText = StorySpeaker.shared.GenerateWholeDisplayText()
        self.loadStoryWithoutStorySpeakerWith(story: story)
        DispatchQueue.main.async {
            self.observeStory(storyID: story.storyID)
            self.observeNovel(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: story.storyID))
        }
        self.applyChapterListChange()
        if self.isNeedResumeSpeech {
            self.isNeedResumeSpeech = false
            DispatchQueue.main.async {
                self.CheckFolderAndStartSpeech()
            }
        }
    }
}

// MARK: custom UI Menu 周り
extension WebSpeechViewController {
    func setCustomUIMenu() {
        let menuController = UIMenuController.shared
        let speechModMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettings", comment: "読み替え辞書へ登録"), action: #selector(setSpeechModSetting(sender:)))
        let speechModForThisNovelMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettingsForThisNovel", comment: "この小説用の読み替え辞書へ登録"), action: #selector(setSpeechModForThisNovelSetting(sender:)))
        let checkSpeechTextMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddCheckSpeechText", comment: "読み替え後の文字列を確認する"), action: #selector(checkSpeechText(sender:)))
        let menuItems:[UIMenuItem] = [speechModMenuItem, speechModForThisNovelMenuItem, checkSpeechTextMenuItem]
        menuController.menuItems = menuItems
        #if targetEnvironment(macCatalyst)
        #if false
        let intraction = UIContextMenuInteraction(delegate: self)
        self.textWebView?.addInteraction(intraction)
        #endif
        #endif
    }
    func removeCustomUIMenu() {
        let menuController = UIMenuController.shared
        menuController.menuItems = []
    }
    
    @objc func setSpeechModSetting(sender: UIMenuItem){
        self.webSpeechTool.getSelectedString { string in
            guard let text = string, text.count > 0 else { return }
            DispatchQueue.main.async {
                let nextViewController = CreateSpeechModSettingViewControllerSwift()
                nextViewController.targetSpeechModSettingBeforeString = text
                nextViewController.targetNovelID = RealmSpeechModSetting.anyTarget
                nextViewController.isUseAnyNovelID = true
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }
        }
    }
    @objc func setSpeechModForThisNovelSetting(sender: UIMenuItem){
        self.webSpeechTool.getSelectedString { string in
            guard let text = string, text.count > 0 else { return }
            DispatchQueue.main.async {
                let nextViewController = CreateSpeechModSettingViewControllerSwift()
                nextViewController.targetSpeechModSettingBeforeString = text
                nextViewController.isUseAnyNovelID = true
                if let storyID = self.targetStoryID {
                    nextViewController.targetNovelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
                }else{
                    // 不測の事態だ……('A`)
                    return
                }
                self.navigationController?.pushViewController(nextViewController, animated: true)
            }
        }
    }

    @objc func checkSpeechText(sender: UIMenuItem) {
        self.webSpeechTool.getSelectedRange { startIndex, endIndex in
            print("startIndex: \(String(describing: startIndex)), endIndex: \(String(describing: endIndex))")
            guard let startIndex = startIndex, let endIndex = endIndex, startIndex <= endIndex else { return }
            DispatchQueue.main.async {
                let speechText = StorySpeaker.shared.GenerateSpeechTextFrom(displayTextRange: NSMakeRange(startIndex, endIndex - startIndex))
                NiftyUtility.EasyDialogLongMessageDialog(viewController: self, message: speechText)
            }
        }
    }
}

#if targetEnvironment(macCatalyst)
#if false
extension WebSpeechViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestActions in
            
        })
    }
    
}
#endif
#endif // targetEnvironment(macCatalyst)
