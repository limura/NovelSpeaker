//
//  ImportFromWebPageViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/13.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import WebKit

class ImportFromWebPageViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    
    var wkWebView: WKWebView?
    var cookiesString: String?
    var alertCount = 0
    var alertBlock = false
    var addressBarBackgroundColor = #colorLiteral(red: 0.8865675194, green: 0.8865675194, blue: 0.8865675194, alpha: 1)
    var addressBarBackgroundColorValid = #colorLiteral(red: 0.8865675194, green: 0.8865675194, blue: 0.8865675194, alpha: 1)
    var addressBarBackgroundColorInvalid = #colorLiteral(red: 0.9254902005, green: 0.2352941185, blue: 0.1019607857, alpha: 1)

    @IBOutlet weak var bookmarkUIBarButtonItem: UIBarButtonItem!
    @IBOutlet weak var toolBar: UIToolbar!
    @IBOutlet weak var backButton: UIBarButtonItem!
    @IBOutlet weak var forwardButton: UIBarButtonItem!
    @IBOutlet weak var refreshButton: UIBarButtonItem!
    @IBOutlet weak var importButton: UIBarButtonItem!
    @IBOutlet weak var homeButton: UIBarButtonItem!
    @IBOutlet weak var bookmarkButton: UIBarButtonItem!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var addressBarUITextField: UITextField!
    @IBOutlet weak var safariButton: UIBarButtonItem!
    
    let getCookiesStringHandler = "getCookiesStringHandler"
    let deleteBookmarkHandler = "deleteBookmarkHandler"
    let sharedWKProcessPool = WKProcessPool()
    
    @objc public var openTargetUrl:URL? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "ImportFromWebPageViewController viewDidLoad", data: [:])
        
        if #available(iOS 13.0, *) {
            addressBarBackgroundColor = UIColor.secondarySystemBackground
            addressBarBackgroundColorValid = UIColor.secondarySystemBackground
        }
        self.addressBarUITextField.backgroundColor = addressBarBackgroundColor

        reloadWebView()
    }
    
    deinit {
        delObservers()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let url = openTargetUrl, let webView = wkWebView {
            webView.load(URLRequest(url: url))
            openTargetUrl = nil
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    // MARK: - WKWebView observers
    
    func reloadWebView() {
        // 既に WkWebView が登録されていたら消します
        for subview in self.view.subviews{
            if subview is WKWebView {
                subview.removeFromSuperview()
            }
        }

        let wkWebViewConfiguration = makeWKWebViewConfiguration()
        let wkWebView = WKWebView(frame: .zero, configuration: wkWebViewConfiguration)
        if #available(iOS 16.4, *) {
            wkWebView.isInspectable = NovelSpeakerUtility.IsInspectableWkWebview()
        }
        self.wkWebView = wkWebView
        wkWebView.navigationDelegate = self
        wkWebView.uiDelegate = self
        wkWebView.allowsBackForwardNavigationGestures = true
        
        // wkWebView の observer を登録します
        addObservers()

        wkWebView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(wkWebView)
        let topConstraint = NSLayoutConstraint.init(item: wkWebView, attribute: .top, relatedBy: .equal, toItem: self.addressBarUITextField, attribute: .bottom, multiplier: 1.0, constant: 10.0)
        let bottomConstraint = NSLayoutConstraint.init(item: wkWebView, attribute: .bottom, relatedBy: .equal, toItem: self.progressView, attribute: .top, multiplier: 1.0, constant: 0)
        let trailingConstraint = NSLayoutConstraint.init(item: wkWebView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailingMargin, multiplier: 1.0, constant: 0.0)
        let leadingConstraint = NSLayoutConstraint.init(item: wkWebView, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leadingMargin, multiplier: 1.0, constant: 0.0)
        NSLayoutConstraint.activate([
            topConstraint,
            bottomConstraint,
            trailingConstraint,
            leadingConstraint,
            ])

        loadHomePage()
    }
    
    func addObservers(){
        guard let wkWebView = self.wkWebView else {
            return
        }
        wkWebView.addObserver(self, forKeyPath: "estimatedProgress", options: NSKeyValueObservingOptions.new, context: nil)
        wkWebView.addObserver(self, forKeyPath: "loading", options: NSKeyValueObservingOptions.new, context: nil)
        wkWebView.addObserver(self, forKeyPath: "URL", options: NSKeyValueObservingOptions.new, context: nil)
        wkWebView.addObserver(self, forKeyPath: "canGoBack", options: NSKeyValueObservingOptions.new, context: nil)
        wkWebView.addObserver(self, forKeyPath: "canGoForward", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    func delObservers(){
        guard let wkWebView = self.wkWebView else {
            return
        }
        wkWebView.removeObserver(self, forKeyPath: "canGoForward")
        wkWebView.removeObserver(self, forKeyPath: "canGoBack")
        wkWebView.removeObserver(self, forKeyPath: "URL")
        wkWebView.removeObserver(self, forKeyPath: "loading")
        wkWebView.removeObserver(self, forKeyPath: "estimatedProgress")
    }
    
    // Key Value Observe でひっ捕らえたイベントは全部コイツが受ける
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath, let wkWebView = self.wkWebView else {
            return
        }
        switch keyPath {
        case "estimatedProgress":
            self.progressView.setProgress(Float(wkWebView.estimatedProgress), animated: true)
            break
        case "loading":
            let activityIndicatorID = "ImportFormWebPageViewController_loading"
            if wkWebView.isLoading {
                self.progressView.setProgress(0.1, animated: true)
                ActivityIndicatorManager.enable(id: activityIndicatorID)
            }else{
                self.progressView.setProgress(0.0, animated: false)
                ActivityIndicatorManager.disable(id: activityIndicatorID)
            }
            break
        case "URL":
            updateForwardBackButtonState()
            if let url = wkWebView.url {
                updateAddressBarState(url: url)
                updateBookmarkButtonState(url: url)
                updateSafariButtonState(url: url)
                alertCount = 0
                alertBlock = false
            }else{
                print("url changed. but wkWebView.url is nil")
            }
            break
        case "canGoForward":
            updateForwardBackButtonState()
            break
        case "canGoBack":
            updateForwardBackButtonState()
            break
        default:
            break
        }
    }
    
    func updateAddressBarState(url:URL) {
        self.addressBarUITextField?.text = url.absoluteString
    }
    
    func updateBookmarkButtonState(url:URL) {
        if isBookmarked(targetUrl: url) {
            self.bookmarkUIBarButtonItem.image = #imageLiteral(resourceName: "bookmark-true.png")
        }else{
            self.bookmarkUIBarButtonItem.image = #imageLiteral(resourceName: "bookmark-false.png")
        }
    }
    
    // 現在の状態から forward/back button を enable/disable します
    func updateForwardBackButtonState(){
        if let wkWebView = self.wkWebView {
            if wkWebView.canGoBack {
                self.backButton.isEnabled = true
            }else{
                self.backButton.isEnabled = false
            }
            if wkWebView.canGoForward {
                self.forwardButton.isEnabled = true
            }else{
                self.forwardButton.isEnabled = false
            }
        }
    }
    
    // 現在の状態から、Safari button の enable/disable をします
    func updateSafariButtonState(url:URL){
        if UIApplication.shared.canOpenURL(url) {
            self.safariButton.isEnabled = true
        }else{
            self.safariButton.isEnabled = false
        }
    }
    
    // WKWebView に毎ページ毎に流し込むJavaScriptを設定したConfigurationを生成します
    func makeWKWebViewConfiguration() -> WKWebViewConfiguration {
        let javaScriptString = "webkit.messageHandlers.\(self.getCookiesStringHandler).postMessage(document.cookie)"
        
        let userScript = WKUserScript(
            source: javaScriptString,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        
        let controller = WKUserContentController()
        controller.addUserScript(userScript)
        controller.add(self, name: self.getCookiesStringHandler)
        controller.add(self, name: self.deleteBookmarkHandler)
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.processPool = self.sharedWKProcessPool
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        if #available(iOS 9.0, *) {
            configuration.allowsAirPlayForMediaPlayback = true
            configuration.allowsPictureInPictureMediaPlayback = true
        }
        
        return configuration
    }

    // WKWebView の UserContentController からの post message を受け取るハンドラ
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == self.getCookiesStringHandler {
            if let cookiesString = message.body as? String {
                self.cookiesString = cookiesString
            }
        }
        if message.name == self.deleteBookmarkHandler {
            if let targetUrlString = message.body as? String, let targetUrl = URL(string: targetUrlString) {
                let bookmarks = self.getBookmark()
                guard let targetBookmark = bookmarks.reduce(into: [String: URL](), { result, dictionary in
                    result.merge(dictionary) { (_, new) in new }
                }).filter({$0.value == targetUrl}).first else {
                    return
                }
                print("targetBookmark: \(targetBookmark.value), \(targetBookmark.key)")
                NiftyUtility.EasyDialogTwoButton(
                    viewController: self,
                    title: NSLocalizedString(
                        "ImportFromWebPageViewController_RemoveBookmark",
                        comment: "ブックマークの削除"
                    ),
                    message: String(format: NSLocalizedString("ImportFromWebPageViewController_RemoveBookmark_Confirm", comment: "%s\nを削除しますか？"), "\(targetBookmark.key)\n\(targetUrl.absoluteString)"),
                    button1Title: NSLocalizedString("Cancel_button", comment: "キャンセル"),
                    button1Action: nil,
                    button2Title: NSLocalizedString("ImportFromWebPageViewController_RemoveBookmark_Delete", comment: "削除")) {
                        self.delBookmark(url: targetUrl)
                        self.loadHomePage()
                    }
            }
        }
    }
    
    // url がブックマークされているか否かを取得します
    func isBookmarked(targetUrl:URL) -> Bool {
        let bookmarks = getBookmark()
        for bookmark in bookmarks {
            for (_, url) in bookmark {
                let urlString = url.absoluteString
                let targetUrlString = targetUrl.absoluteString
                let urlStringRemoveHTTP = urlString.replacingOccurrences(of: "^http://", with: "https://", options: [.regularExpression, .caseInsensitive], range: nil)
                let targetUrlStringRemoveHTTP = targetUrlString.replacingOccurrences(of: "^http://", with: "https://", options: [.regularExpression, .caseInsensitive], range: nil)
                if urlStringRemoveHTTP == targetUrlStringRemoveHTTP {
                    return true
                }
            }
        }
        return false
    }

    // よりSwiftらしいBookmarkの形式([[String:URL]])のブックマークリストとしてブックマークリストを読み出します。
    func getBookmark() -> ([[String:URL]]) {
        return RealmUtil.RealmBlock { (realm) -> [[String:URL]] in
            var resultArray = [[String:URL]]()
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                return resultArray
            }
            var bookmarks = globalState.webImportBookmarkArray
            // 「アルファポリスは非対応」と言ってたのを排除します
            let removeTarget = "アルファポリス(Web取込 非対応サイトになりました。詳細はサポートサイト下部にありますQ&Aを御覧ください)\nhttps://www.alphapolis.co.jp/novel/"
            let replaceTo = "アルファポリス\nhttps://www.alphapolis.co.jp/novel/"
            if bookmarks.contains(removeTarget) {
                var newBookmarkArray:[String] = []
                for bookmark in bookmarks {
                    if bookmark == removeTarget {
                        newBookmarkArray.append(replaceTo)
                    }else{
                        newBookmarkArray.append(bookmark)
                    }
                }
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    globalState.webImportBookmarkArray.removeAll()
                    globalState.webImportBookmarkArray.append(objectsIn: newBookmarkArray)
                }
                bookmarks = globalState.webImportBookmarkArray
            }
            for bookmarkString in bookmarks {
                let nameAndURL = bookmarkString.components(separatedBy: "\n")
                if nameAndURL.count != 2 {
                    continue
                }
                let name = nameAndURL[0]
                let urlString = nameAndURL[1]
                let url = URL(string: urlString)
                if let url = url {
                    resultArray.append([name:url])
                }
            }
            return resultArray
        }
    }
    func delBookmark(url:URL) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                return
            }
            var dic:[String:Int] = [:]
            var i:Int = -1
            for bookmarkString in globalState.webImportBookmarkArray {
                i += 1
                let nameAndURL = bookmarkString.components(separatedBy: "\n")
                if nameAndURL.count != 2 {
                    continue
                }
                let urlString = nameAndURL[1]
                dic[urlString] = i
            }
            if let index = dic[url.absoluteString] {
                RealmUtil.WriteWith(realm: realm) { (realm) in
                    globalState.webImportBookmarkArray.remove(at: index)
                }
            }
        }
    }
    func addBookmark(url:URL, name:String) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                return
            }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                let saveName = NovelSpeakerUtility.NormalizeNewlineString(string: name).replacingOccurrences(of: "\n", with: "")
                globalState.webImportBookmarkArray.append("\(saveName)\n\(url.absoluteString)")
            }
        }
    }

    func loadHomePage(){
        var homePageHtmlString = "<html>"
            + "<head>"
            + "<title>home</title>"
            + "<style type=\"text/css\">"
            + """
html {
  font: -apple-system-title1;
}
li {
  padding: 0.12em;
}
@media (prefers-color-scheme: light) {
  body {
    background-color: #e0e0e0;
    color: black;
  }
  a:link { color: #0000ff; }
  a:visited { color: #000080; }
}
@media (prefers-color-scheme: dark) {
  body {
    background-color: #202020;
    color: #a0a0a0;
  }
  a:link { color: #5050ff; }
  a:visited { color: #4040a0; }
}
"""
            + "</style>"
            + "</head>"
            + "<html><body>"
        homePageHtmlString += "<ul>"
        //homePageHtmlString += "<li><a href=\"\"></a></li>"
        homePageHtmlString += "<li><a href=\"https://limura.github.io/NovelSpeaker/\">ことせかい サポートサイト</a></li>"
        homePageHtmlString += "<li><a href=\"" + NSLocalizedString("NovelSpeakerUtility_FirstStoryURLString", comment: "https://limura.github.io/NovelSpeaker/topics/jp/00001.html") + "\">" + NSLocalizedString("NovelSpeakerUtility_FirstStoryTitleString", comment: "はじめに(ことせかい の使い方)") + "</a></li>"
        homePageHtmlString += "<li><a href=\"https://limura.github.io/NovelSpeaker/WebImport.html\">Web取込機能の使い方(下記のサイト以外の取り込み方等)</a></li>"
        let bookmarks = getBookmark()
        for bookmark in bookmarks {
            for (name, url) in bookmark {
                homePageHtmlString += "<li><a href=\"" + url.absoluteString + "\">" + name + "</a>&nbsp;<button onclick=\"deleteBookmark('\(url.absoluteString)')\")>🗑️</button></li>"
            }
        }
        homePageHtmlString += "</ul>"
        homePageHtmlString += """
            <script>
                function deleteBookmark(url){
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.deleteBookmarkHandler) {
                        window.webkit.messageHandlers.deleteBookmarkHandler.postMessage(url);
                    }
                }
            </script>
            """
        homePageHtmlString += "</body></html>"
        if let wkWebView = self.wkWebView {
            wkWebView.loadHTMLString(homePageHtmlString, baseURL: nil)
            updateAddressBackgroundColor(color: addressBarBackgroundColorValid)
        }
    }
    
    @IBAction func backButtonClicked(_ sender: Any) {
        if let wkWebView = self.wkWebView {
            wkWebView.goBack()
        }
    }
    @IBAction func forwardButtonClicked(_ sender: Any) {
        if let wkWebView = self.wkWebView {
            wkWebView.goForward()
        }
    }
    
    @IBAction func safariButtonClicked(_ sender: Any) {
        if let url = self.wkWebView?.url {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    @IBAction func homeButtonClicked(_ sender: Any) {
        loadHomePage()
    }
    @IBAction func reloadButtonClicked(_ sender: Any) {
        if let wkWebView = self.wkWebView {
            wkWebView.reload()
        }
    }
    @IBAction func importButonClicked(_ sender: Any) {
        guard let url = self.wkWebView?.url else {
            print("url is nil")
            return
        }
        if #available(iOS 11.0, *) {
            if let store = self.wkWebView?.configuration.websiteDataStore.httpCookieStore {
                store.getAllCookies { (cookieArray) in
                    RealmUtil.Write { (realm) in
                        HTTPCookieSyncTool.shared.SaveCookiesFromCookieArrayWith(realm: realm, cookieArray: cookieArray)
                    }
                    NiftyUtility.checkUrlAndConifirmToUser(viewController: self, url: url, cookieString: nil, isNeedFallbackImportFromWebPageTab: false)
                }
                return
            }
        }
        NiftyUtility.checkUrlAndConifirmToUser(viewController: self, url: url, cookieString: self.cookiesString, isNeedFallbackImportFromWebPageTab: false)
    }
    @IBAction func bookmarkButtonClicked(_ sender: Any) {
        guard let url = self.wkWebView?.url else {
            return
        }
        if isBookmarked(targetUrl: url) {
            NiftyUtility.EasyDialogBuilder(self)
            .label(text: NSLocalizedString("ImportFromWebPageViewController_ConifirmDeleteBookmark", comment: "このページのブックマークを削除します。よろしいですか？"))
            .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel")) { (dialog) in
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
            }.addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
                self.delBookmark(url: url)
                self.updateBookmarkButtonState(url: url)
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
            }.build().show()
        }else{
            let titleString = self.wkWebView?.title
            NiftyUtility.EasyDialogBuilder(self)
                .label(text: NSLocalizedString("ImportFromWebPageViewController_CreateBookmark", comment: "ブックマークします。名前を入力してください。"))
                .textField(tag: 100, placeholder: "name", content: (titleString != nil) ? titleString! : url.absoluteString, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .roundedRect)
                .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                })
                .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                    let nameTextField = dialog.view.viewWithTag(100) as! UITextField
                    let nameString = nameTextField.text ?? url.absoluteString
                    self.addBookmark(url: url, name: nameString)
                    self.updateBookmarkButtonState(url: url)
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                })
            .build().show()
        }
    }
    
    // アドレスバーのキーボードが消える時に呼ばれるので、そのタイミングでナビゲートする
    @IBAction func addressBarUITextViewEditingDidEndOnExitEvent(_ sender: Any) {
        guard let wkWebView = self.wkWebView,
            let addressString = self.addressBarUITextField.text
            else {
            // fail
            return
        }
        
        if let url = URL(string: addressString) {
            let request = URLRequest(url: url)
            wkWebView.load(request)
            // success
            return
        }
        if let query = addressString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let queryString = "https://www.google.co.jp/search?q=" + query
            if let url = URL(string: queryString) {
                let request = URLRequest(url: url)
                wkWebView.load(request)
                // success
                return
            }
        }
        // fail
    }
    // アドレスバーにキーボードが現れる時に呼ばれるので、全体を選択した状態にする
    @IBAction func addressBarUITextViewEditingDidBeginEvent(_ sender: Any) {
        guard let textField = self.addressBarUITextField else {
            return
        }
        textField.selectedTextRange = textField.textRange(from: textField.beginningOfDocument, to: textField.endOfDocument)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("webView didFailProvisionalNavigation", error.localizedDescription)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("webView didFail: ", navigation.debugDescription, error.localizedDescription)
    }
    
    func updateAddressBackgroundColor(color:UIColor) {
        self.addressBarBackgroundColor = color
        guard let addressBar = self.addressBarUITextField else {
            return
        }
        addressBar.backgroundColor = color
    }
    
    // 認証周りのチェックに呼ばれる
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        //print("webView:didReceive challenge:completionHandler called.")
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.rejectProtectionSpace, nil)
                return
            }
            // SecTrustEvaluate() が非推奨になったので SecTrustEvaluateWithError を使うようにします。
            // それに伴って CFError を受け取らずに単に SecTrustEvaluateWithError が true を返すかどうかだけで判定するようにします。
            DispatchQueue.global(qos: .utility).async {
                if SecTrustEvaluateWithError(serverTrust, nil) == false {
                    MainActor.assumeIsolated {
                        completionHandler(.rejectProtectionSpace, nil)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.updateAddressBackgroundColor(color: self.addressBarBackgroundColorValid)
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                }
            }
            return
        }
        else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodDefault
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodNegotiate
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodNTLM
            {
            NiftyUtility.EasyDialogBuilder(self)
            .title(title: NSLocalizedString("ImportFromWebPageViewController_AuthenticationRequired", comment: "認証が必要です"))
            .textField(tag: 100, placeholder: "user id", content: "", keyboardType: .default, secure: false, focusKeyboard: false, borderStyle: .roundedRect)
            .textField(tag: 101, placeholder: "password", content: "", keyboardType: .default, secure: true, focusKeyboard: false, borderStyle: .roundedRect)
                .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
                    completionHandler(URLSession.AuthChallengeDisposition.cancelAuthenticationChallenge, nil)
                    if let wkWebView = self.wkWebView {
                        if wkWebView.canGoBack {
                            wkWebView.goBack()
                        }
                    }
                    DispatchQueue.main.async {
                        dialog.dismiss(animated: false, completion: nil)
                    }
                })
            .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
                let userIDTextField = dialog.view.viewWithTag(100) as! UITextField
                let userID = userIDTextField.text ?? ""
                let passwordTextField = dialog.view.viewWithTag(101) as! UITextField
                let password = passwordTextField.text ?? ""
                let credential = URLCredential(user: userID, password: password, persistence: URLCredential.Persistence.forSession)
                completionHandler(URLSession.AuthChallengeDisposition.useCredential, credential)
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: nil)
                }
            }.build().show()
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
    
    // _blank へな link をそのまま表示させる、みたいな奴
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if navigationAction.targetFrame == nil
                || !navigationAction.targetFrame!.isMainFrame {
                if let url = navigationAction.request.url {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
            }else{
                if #available(iOS 14.5, *) {
                    if navigationAction.shouldPerformDownload {
                        decisionHandler(.download)
                        return
                    }
                }
            }
        }
        let app = UIApplication.shared
        if let url = navigationAction.request.url {
            if app.canOpenURL(url) {
                // 謎の allow.rawValue + 2 で universal link (アプリが起動しちゃうリンク) を封殺できる
                // from: https://stackoverflow.com/questions/38450586/prevent-universal-links-from-opening-in-wkwebview-uiwebview
                decisionHandler(WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2)!)
                return
            }
        }
        decisionHandler(.allow)
    }
    
    // decisionHandler(.download) を指定した場合こいつが呼ばれるぽい
    // で、呼ばれたらダウンロードするためのハンドラを自分にする
    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    // WkWebView でダウンロードされるファイルがあった場合のダウンロードされたファイルへのpath(URL)を保存しておく場所。
    // これ、ダウンロードが開始される時には保存されるべきファイル名が渡されるのに、
    // ダウンロードが終了した時にはそのファイル名は渡されないためにこっちで覚えておかねばならんという問題があったので仕方なく覚えているという奴です。(´・ω・`)
    var downloadFileUrl:URL? = nil
    // ページが表示された時に呼ばれるみたい
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateAddressBackgroundColor(color: addressBarBackgroundColor)
        if let url = webView.url, url.absoluteString == "about:blank" {
            self.homeButton.isEnabled = true
            self.bookmarkButton.isEnabled = false
            self.refreshButton.isEnabled = false
            self.importButton.isEnabled = false
        }else{
            self.homeButton.isEnabled = true
            self.bookmarkButton.isEnabled = true
            self.refreshButton.isEnabled = true
            self.importButton.isEnabled = true
        }
    }
    
    // JavaScript で Alertされた時
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping  @MainActor () -> Void) {
        if alertBlock {
            completionHandler()
            return
        }
        var hostString = NSLocalizedString("ImportFromWebPageViewController_UnknownHost", comment: "不明なホスト")
        if let host = self.wkWebView?.url?.host {
            hostString = host
        }
        alertCount += 1
        if alertCount > 3 {
            NiftyUtility.EasyDialogBuilder(self)
            .title(title: String.localizedStringWithFormat(NSLocalizedString("ImportFromWebPageViewController_MessageFrom...", comment: "%@からのメッセージ"), hostString))
            .label(text: message)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
                dialog.dismiss(animated: false, completion: nil)
            }
            .addButton(title: NSLocalizedString("ImportFromWebPageViewController_NoMoreDisplay", comment: "もう表示しない"), callback: { (dialog) in
                self.alertBlock = true
                dialog.dismiss(animated: false, completion: nil)
            })
            .build().show()
        }
        NiftyUtility.EasyDialogBuilder(self)
        .title(title: String.localizedStringWithFormat(NSLocalizedString("ImportFromWebPageViewController_MessageFrom...", comment: "%@からのメッセージ"), hostString))
        .label(text: message)
        .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
            dialog.dismiss(animated: false, completion: nil)
        }
        .build().show()
        completionHandler()
    }

    // テキスト入力を迫られた場合のハンドラ
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping  @MainActor (String?) -> Void) {
        var hostString = NSLocalizedString("ImportFromWebPageViewController_UnknownHost", comment: "不明なホスト")
        if let host = self.wkWebView?.url?.host {
            hostString = host
        }
        NiftyUtility.EasyDialogBuilder(self)
        .title(title: String.localizedStringWithFormat(NSLocalizedString("ImportFromWebPageViewController_ImputRequiredFrom...", comment: "%@が入力を求めています"), hostString))
        .label(text: prompt)
        .textField(tag: 100, placeholder: defaultText, content: defaultText, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .roundedRect)
        .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
            let textField = dialog.view.viewWithTag(100) as! UITextField
            let inputString = textField.text ?? ""
            completionHandler(inputString)
            dialog.dismiss(animated: false, completion: nil)
        }.build().show()
    }
    
    // OK/NGが聞かれた時のハンドラ
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping  @MainActor (Bool) -> Void) {
        var hostString = NSLocalizedString("ImportFromWebPageViewController_UnknownHost", comment: "不明なホスト")
        if let host = self.wkWebView?.url?.host {
            hostString = host
        }
        NiftyUtility.EasyDialogBuilder(self)
        .title(title: String.localizedStringWithFormat(NSLocalizedString("ImportFromWebPageViewController_MessageFrom...", comment: "%@からのメッセージ"), hostString))
        .label(text: message)
        .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel")) { (dialog) in
            completionHandler(false)
            dialog.dismiss(animated: false, completion: nil)
        }
        .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
            completionHandler(true)
            dialog.dismiss(animated: false, completion: nil)
        }
        .build().show()
    }
    
    func load(url:URL) {
        if let webView = wkWebView {
            webView.load(URLRequest(url: url))
        }else{
            self.openTargetUrl = url
        }
    }
}

@available(iOS 14.5, *)
extension ImportFromWebPageViewController: WKDownloadDelegate {
    // WkWebViewでのダウンロード用に保存されるファイルへの path を生成する。
    // 保存場所を テンポラリディレクトリ/download に固定するので、起動時にそれを消す事を想定している。
    static func GetDownloadTemplaryDirectoryPath() -> URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("WKWebViewDownload", isDirectory: true)
    }
    // WkWebView でのダウンロード用に保存されたファイルを全部消す
    @objc static func ClearDownloadTemporaryDirectory() {
        NiftyUtility.RemoveDirectory(directoryPath: GetDownloadTemplaryDirectoryPath())
    }
    static func GetDownloadTempolaryFilePath(fileName:String) -> URL {
        let dir = GetDownloadTemplaryDirectoryPath()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        let path = dir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: path)
        return path
    }
    
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping  @MainActor (URL?) -> Void) {
        let downloadFilePath = ImportFromWebPageViewController.GetDownloadTempolaryFilePath(fileName: suggestedFilename)
        self.downloadFileUrl = downloadFilePath
        completionHandler(downloadFilePath)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        print("download failed: \(error.localizedDescription)")
    }
    
    func downloadDidFinish(_ download: WKDownload) {
        guard let path = self.downloadFileUrl, FileManager.default.fileExists(atPath: path.path) else { return }
        DispatchQueue.main.async {
            func shareFile() {
                let activityViewController = UIActivityViewController(activityItems: [path], applicationActivities: nil)
                let frame = UIScreen.main.bounds
                activityViewController.popoverPresentationController?.sourceView = self.view
                activityViewController.popoverPresentationController?.sourceRect = CGRect(x: frame.width / 2 - 60, y: frame.size.height - 50, width: 120, height: 50)
                self.present(activityViewController, animated: true, completion: nil)
            }
            
            if ["novelspeaker-backup-json", "novelspeaker-backup+json", "novelspeaker-backup+zip"].contains(path.pathExtension) {
                NiftyUtility.EasyDialogTwoButton(viewController: self, title: NSLocalizedString("ImportFromWebPageViewController_DidDownloadNovelSpeakerBackupFileTitle", comment: "ことせかい バックアップファイルのダウンロード"), message: NSLocalizedString("ImportFromWebPageViewController_DidDownloadNovelSpeakerBackupFileMessage", comment: "ダウンロードされたファイルは ことせかい のバックアップファイルのようです。このまま適用しますか？"), button1Title: NSLocalizedString("ImportFromWebPageViewController_DidDownloadNovelSpeakerBackupFileCancel", comment: "適用しない(シェアメニューを開く)"), button1Action: {
                    DispatchQueue.main.async {
                        shareFile()
                    }
                }, button2Title: NSLocalizedString("ImportFromWebPageViewController_DidDownloadNovelSpeakerBackupFileOK", comment: "適用する")) {
                    DispatchQueue.main.async {
                        NovelSpeakerUtility.ProcessURL(url: path)
                    }
                }
                return
            }
            shareFile()
        }
    }
}
