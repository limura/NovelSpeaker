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

/*
 TODO:
 * 明るさの変更
 * 読む部分を全画面表示にする
   * 表示に関する設定項目をまとめた物がダイアログ的に表示できると良いかもしれん
 */

extension UIColor {
    var cssColor:String? {
        get {
            var red:CGFloat = 0
            var green:CGFloat = 0
            var blue:CGFloat = 0
            var alpha:CGFloat = 0
            if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
               , !red.isInfinite, !red.isNaN
               , !green.isInfinite, !green.isNaN
               , !blue.isInfinite, !blue.isNaN
               , !alpha.isInfinite, !alpha.isNaN
            {
                return "rgba(\(String(format: "%d", Int(red*255))), \(String(format: "%d", Int(green*255))), \(String(format: "%d", Int(blue*255))), \(alpha))"
            }
            return nil
        }
    }
}

class WebSpeechViewController: UIViewController, StorySpeakerDeletgate, RealmObserverResetDelegate {
    var targetStoryID:String? = nil
    var isNeedResumeSpeech:Bool = false
    var isNeedUpdateReadDate:Bool = true
    let textWebView = WKWebView()
    let webSpeechTool = WebSpeechViewTool()
    
    var isNeedCollectDisplayLocation = false
    var webViewDisplayWholeText:String? = nil
    var speakerDisplayWholeText:String? = nil

    var globalStateObserverToken:NotificationToken? = nil
    var displaySettingObserverToken:NotificationToken? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        textWebView.enableConsoleLog()
        createUIComponents()
        RestartObservers()
        RealmUtil.RealmBlock { realm in
            self.loadFirstContentWith(realm: realm, storyID: targetStoryID)
        }
        setCustomUIMenu()
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        StorySpeaker.shared.AddDelegate(delegate: self)
        applyTheme()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        StorySpeaker.shared.RemoveDelegate(delegate: self)
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

    func StopObservers() {
        //novelObserverToken = nil
        //storyObserverToken = nil
        displaySettingObserverToken = nil
        globalStateObserverToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeDispaySetting()
        //let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID)
        //observeStory(storyID: storyID)
        //observeNovel(novelID: novelID)
        observeGlobalState()
    }

    func createUIComponents() {
        self.textWebView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(textWebView)
        NSLayoutConstraint.activate([
            self.textWebView.topAnchor.constraint(equalTo: self.view.firstBaselineAnchor),
            self.textWebView.bottomAnchor.constraint(equalTo: self.view.lastBaselineAnchor),
            self.textWebView.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            self.textWebView.rightAnchor.constraint(equalTo: self.view.rightAnchor),
        ])
    }
    
    func convertNovelSepakerStringToHTML(text:String) -> String {
        return text.replacingOccurrences(of: "\\|([^|(]+?)[(]([^)]+?)[)]", with: "<ruby> $1<rt> $2 </rt></ruby>", options: .regularExpression, range: text.range(of: text)).replacingOccurrences(of: "\r\n", with: "  <br>").replacingOccurrences(of: "\n", with: " <br>")
    }
    
    func createContentHTML(story:Story, displaySetting: RealmDisplaySetting?) -> String {
        var fontName:String = "-apple-system-title1"
        var fontPixelSize:Float = 18
        var letterSpacing:String = "0.03em"
        var lineHeight:String = "1.5em"
        var verticalModeCSS:String = ""
        let (foregroundColor, backgroundColor) = getForegroundBackgroundColor()
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

        if let displaySetting = displaySetting {
            fontName = displaySetting.font.fontName
            fontPixelSize = Float(displaySetting.font.pointSize)
            let lineSpacePix = max(displaySetting.font.pointSize, displaySetting.lineSpacingDisplayValue)
            let lineSpaceEm = lineSpacePix / max(1, displaySetting.font.xHeight)
            lineHeight = "\(lineSpaceEm)"
            verticalModeCSS = displaySetting.viewType == .webViewVertical ? "writing-mode: vertical-rl;" : ""
            print("fontName: \(fontName), font-size: \(fontPixelSize)px, lineSpacePix: \(lineSpacePix), font.xHeight: \(displaySetting.font.xHeight), line-height: \(lineHeight), vertical: \"\(verticalModeCSS)\"")
        }
        
        let htmledText = convertNovelSepakerStringToHTML(text: story.content)
        /* goole font を読み込む場合はこうするよのメモ
         <html>
         <head>
         <style type="text/css">
         @import url('https://fonts.googleapis.com/css2?family=Hachi+Maru+Pop&display=swap');
         html {
           font-family: 'Hachi Maru Pop', cursive;
           font-size: \(fontPixelSize);
           letter-spacing: \(letterSpacing);
           line-height: \(lineHeight);
           font-feature-settings: 'pkna';
           \(verticalModeCSS)
         }
         */
        let html = """
<html>
<head>
<style type="text/css">
html {
  font: \(fontName);
  font-size: \(fontPixelSize);
  letter-spacing: \(letterSpacing);
  line-height: \(lineHeight);
  font-feature-settings: 'pwid';
  \(verticalModeCSS)
}
ruby rt {
    font-size: 0.65em;
}
body.NovelSpeakerBody {
  \(foregroundColorCSS);
  \(backgroundColorCSS);
}
* {
  scroll-behavior: smooth;
}
</style>
</head>
<html><body class="NovelSpeakerBody">
"""
        + htmledText
        + """
</body></html>
"""
        return html
    }
    
    func loadStoryWithoutStorySpeakerWith(story:Story) {
        RealmUtil.RealmBlock { realm in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: story.novelID) else { return }
            let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm)
            let readLocation = story.readLocation(realm: realm)
            DispatchQueue.main.async {
                self.title = novel.title
            }
            let aliveButtonSettings = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() ?? SpeechViewButtonSetting.defaultSetting
            self.assignUpperButtons(novel: novel, aliveButtonSettings: aliveButtonSettings)
            self.webViewDisplayWholeText = nil
            if story.url.count > 0, let url = URL(string: story.url), displaySetting?.viewType == .webViewOriginal {
                self.isNeedCollectDisplayLocation = true
                let siteInfoArray = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: story.url)
                let request = URLRequest(url: url)
                self.webSpeechTool.loadUrl(webView: self.textWebView, request: request, siteInfoArray: siteInfoArray, completionHandler: {
                    self.webSpeechTool.getSpeechText { text in
                        self.webViewDisplayWholeText = text
                    }
                    //self.webSpeechTool.hideNotPageElement {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1, scrollRatio: 0.3)
                    //}
                })
                return
            }
            self.isNeedCollectDisplayLocation = false
            self.webSpeechTool.loadHtmlString(webView: self.textWebView, html: self.createContentHTML(story: story, displaySetting: displaySetting), baseURL: nil, completionHandler: {
                self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1, scrollRatio: 0.3)
            })
        }
    }
    
    func loadNovelWith(realm:Realm, story:Story) {
        self.textWebView.loadHTMLString("<html><body class='NovelSpeakerBody'>\(NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))</body></html>", baseURL: nil)
        StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { story in
            self.loadStoryWithoutStorySpeakerWith(story: story)
        }
    }
    
    func loadFirstContentWith(realm:Realm, storyID:String?) {
        guard let storyID = storyID, let targetStory = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) else {
            self.textWebView.loadHTMLString("<html><body class='NovelSpeakerBody'>\( NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))</body></html>", baseURL: nil)
            return
        }
        loadNovelWith(realm: realm, story: targetStory)
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
        /*
        self.textView.textColor = foregroundColor;
        self.textView.backgroundColor = backgroundColor;
        self.textView.indicatorStyle = indicatorStyle
        self.nextChapterButton.backgroundColor = backgroundColor
        self.previousChapterButton.backgroundColor = backgroundColor
        self.chapterSlider.backgroundColor = backgroundColor
        self.chapterPositionLabel.backgroundColor = backgroundColor
        self.chapterPositionLabel.textColor = foregroundColor
         */
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: foregroundColor]
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = barStyle
        // WebView にはCSSで注入する
        applyFgBgColorToWebView(foregroundColor: foregroundColor, backgroundColor: backgroundColor)
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
                                self.assignUpperButtons(novel: novel, aliveButtonSettings: buttonSettings)
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


    //MARK: 上のボタン群の設定
    var startStopButtonItem:UIBarButtonItem? = nil
    var shareButtonItem:UIBarButtonItem? = nil
    var skipBackwardButtonItem:UIBarButtonItem? = nil
    var skipForwardButtonItem:UIBarButtonItem? = nil
    var showTableOfContentsButtonItem:UIBarButtonItem? = nil
    func assignUpperButtons(novel:RealmNovel, aliveButtonSettings:[SpeechViewButtonSetting]) {
        var barButtonArray:[UIBarButtonItem] = []
        
        for buttonSetting in aliveButtonSettings {
            if buttonSetting.isOn == false { continue }
            switch buttonSetting.type {
            case .openWebPage:
                let webPageButton = UIBarButtonItem(image: UIImage(named: "earth"), style: .plain, target: self, action: #selector(safariButtonClicked(_:)))
                webPageButton.accessibilityLabel = NSLocalizedString("SpeechViewController_WebPageButton_VoiceOverTitle", comment: "Web取込タブで開く")
                if novel.type == .URL {
                    barButtonArray.append(webPageButton)
                }
            case .reload:
                if novel.type == .URL {
                    barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(urlRefreshButtonClicked(_:))))
                }
            case .share:
                if novel.type == .URL {
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

        navigationItem.rightBarButtonItems = barButtonArray
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
        //TODO: not implemented yet.
        // disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.StopSpeech(realm: realm)
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
    @objc func safariButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            let storyID = StorySpeaker.shared.storyID
            guard storyID.count > 0, let urlString = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfRATreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    @objc func startStopButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            if StorySpeaker.shared.isPlayng {
                StorySpeaker.shared.StopSpeech(realm: realm)
            }else{
                // TODO: not implememted yet.
                // disableCurrentReadingStoryChangeFloatingButton()
                self.webSpeechTool.getSelectedLocation { location in
                    print("startStopButtonClicked selectedLocation: \(location ?? -1)")
                    RealmUtil.RealmBlock { realm in
                        if let location = location {
                            StorySpeaker.shared.setReadLocationWith(realm: realm, location: location)
                        }
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                    }
                }
                self.checkDummySpeechFinished()
            }
        }
    }
    @objc func skipBackwardButtonClicked(_ sender: UIBarButtonItem) {
        if StorySpeaker.shared.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                StorySpeaker.shared.StopSpeech(realm: realm) {
                    StorySpeaker.shared.SkipBackward(realm: realm, length: 30) {
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                    }
                }
            }
        }
    }
    @objc func skipForwardButtonClicked(_ sender: UIBarButtonItem) {
        if StorySpeaker.shared.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                StorySpeaker.shared.StopSpeech(realm: realm) {
                    StorySpeaker.shared.SkipForward(realm: realm, length: 30) {
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
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
    @objc func leftSwipe(_ sender: UISwipeGestureRecognizer) {
        // TODO: not implemented yet
        // disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadNextChapter(realm: realm)
        }
    }
    @objc func rightSwipe(_ sender: UISwipeGestureRecognizer) {
        // TODO: not implemented yet
        // disableCurrentReadingStoryChangeFloatingButton()
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
        self.webSpeechTool.highlightSpeechLocation(location: location, length: range.length, scrollRatio: 0.3)
    }
    func storySpeakerStoryChanged(story:Story) {
        self.speakerDisplayWholeText = StorySpeaker.shared.GenerateWholeDisplayText()
        self.loadStoryWithoutStorySpeakerWith(story: story)
        if self.isNeedResumeSpeech {
            self.isNeedResumeSpeech = false
            DispatchQueue.main.async {
                RealmUtil.RealmBlock { (realm) -> Void in
                    StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                }
                self.checkDummySpeechFinished()
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
            guard let startIndex = startIndex, let endIndex = endIndex, startIndex <= endIndex else { return }
            DispatchQueue.main.async {
                let speechText = StorySpeaker.shared.GenerateSpeechTextFrom(displayTextRange: NSMakeRange(startIndex, endIndex - startIndex))
                NiftyUtility.EasyDialogLongMessageDialog(viewController: self, message: speechText)
            }
        }
    }
}
