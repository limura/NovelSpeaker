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
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var addressBarUITextField: UITextField!
    
    let getCookiesStringHandler = "getCookiesStringHandler"
    let sharedWKProcessPool = WKProcessPool()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.addressBarUITextField.backgroundColor = #colorLiteral(red: 0.8865675194, green: 0.8865675194, blue: 0.8865675194, alpha: 1)

        let wkWebViewConfiguration = makeWKWebViewConfiguration()
        let wkWebView = WKWebView(frame: .zero, configuration: wkWebViewConfiguration)
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
        //wkWebView.load(URLRequest(url: URL(string: "https://www.google.co.jp/")!))
    }
    
    deinit {
        delObservers()
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
            UIApplication.shared.isNetworkActivityIndicatorVisible = wkWebView.isLoading
            if wkWebView.isLoading {
                self.progressView.setProgress(0.1, animated: true)
            }else{
                self.progressView.setProgress(0.0, animated: false)
            }
            break
        case "URL":
            updateForwardBackButtonState()
            if let url = wkWebView.url {
                updateAddressBarState(url: url)
                updateBookmarkButtonState(url: url)
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
        
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.processPool = self.sharedWKProcessPool
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaPlaybackAllowsAirPlay = true
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
    }
    
    // url がブックマークされているか否かを取得します
    func isBookmarked(targetUrl:URL) -> Bool {
        let bookmarks = getBookmark()
        for bookmark in bookmarks {
            for (_, url) in bookmark {
                if url.absoluteString == targetUrl.absoluteString {
                    return true
                }
            }
        }
        return false
    }

    // よりSwiftらしいBookmarkの形式([[String:URL]])のブックマークリストとしてブックマークリストを読み出します。
    func getBookmark() -> ([[String:URL]]) {
        var resultArray = [[String:URL]]()
        if let globalData = GlobalDataSingleton.getInstance() {
            if let bookmarks = globalData.getWebImportBookmarks() {
                for bookmarkString in bookmarks {
                    if let bookmarkString:String = bookmarkString as? String {
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
                }
            }
        }
        return resultArray
    }

    func loadHomePage(){
        var homePageHtmlString = "<html>"
            + "<head>"
            + "<title>home</title>"
            + "<style type=\"text/css\">"
            + "body{font-size: 2.4rem;}"
            + "</style>"
            + "</head>"
            + "<html><body>"
        homePageHtmlString += "<ul>"
        //homePageHtmlString += "<li><a href=\"\"></a></li>"
        homePageHtmlString += "<li><a href=\"https://limura.github.io/NovelSpeaker/\">ことせかい サポートサイト</a></li>"
        let bookmarks = getBookmark()
        for bookmark in bookmarks {
            for (name, url) in bookmark {
                homePageHtmlString += "<li><a href=\"" + url.absoluteString + "\">" + name + "</a></li>"
            }
        }
        homePageHtmlString += "</ul>"
        homePageHtmlString += "</body></html>"
        if let wkWebView = self.wkWebView {
            wkWebView.loadHTMLString(homePageHtmlString, baseURL: nil)
            updateAddressBackgroundColor(color: addressBarBackgroundColorValid)
        }
    }
    
    func cookiesToCookieStringArray(cookiesString:String?) -> [String] {
        guard let cookiesString = cookiesString else {
            return []
        }
        return cookiesString.components(separatedBy: ";")
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
        let cookieArray = cookiesToCookieStringArray(cookiesString: self.cookiesString)
        NiftyUtilitySwift.checkUrlAndConifirmToUser(viewController: self, url: url, cookieArray: cookieArray)
    }
    @IBAction func bookmarkButtonClicked(_ sender: Any) {
        guard let url = self.wkWebView?.url else {
            return
        }
        if isBookmarked(targetUrl: url) {
            GlobalDataSingleton.getInstance().delURL(fromWebImportBookmark: url)
            updateBookmarkButtonState(url: url)
        }else{
            let titleString = self.wkWebView?.title
            EasyDialog.Builder(self)
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
                    GlobalDataSingleton.getInstance().addWebImportBookmark(forName: nameString, url: url)
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
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("webView:didReceive challenge:completionHandler called.")
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            guard let serverTrust = challenge.protectionSpace.serverTrust else {
                completionHandler(.rejectProtectionSpace, nil)
                return
            }
            var trustResult = SecTrustResultType.invalid
            guard SecTrustEvaluate(serverTrust, &trustResult) == noErr else {
                completionHandler(.rejectProtectionSpace, nil)
                return
            }
            switch trustResult {
            case .recoverableTrustFailure: // リカバリしてもいいけど問題のあるTrustFailure
                print("SecTrustEvaluate: .recoverableTrustFailure")
                // recoverable だけれど、結局後で fetch しようとすると失敗するので見せない事にします。
                EasyDialog.Builder(self)
                    .label(text:
                        // NSLocalizedString("ImportFromWebPageViewController_InvalidServerCertificate_CanContinue",
                        NSLocalizedString("ImportFromWebPageViewController_InvalidServerCertificate", comment: "サーバの証明書に何らかの問題がありました。"))
                    /*
                    .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { (dialog) in
                        completionHandler(.rejectProtectionSpace, nil)
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                    })*/
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                        completionHandler(.rejectProtectionSpace, nil)
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                        /*
                        self.updateAddressBackgroundColor(color: self.addressBarBackgroundColorInvalid)
                        let credential = URLCredential(trust: serverTrust)
                        completionHandler(.useCredential, credential)
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                        */
                    })
                    .build().show()
                return
            case .fatalTrustFailure: // リカバリしちゃ駄目なTrustFailure
                print("SecTrustEvaluate: .fatalTrustFailure")
                EasyDialog.Builder(self)
                    .label(text: NSLocalizedString("ImportFromWebPageViewController_InvalidServerCertificate", comment: "サーバの証明書に何らかのエラーがありました。"))
                    .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                        DispatchQueue.main.async {
                            dialog.dismiss(animated: false, completion: nil)
                        }
                    })
                    .build().show()
                completionHandler(.rejectProtectionSpace, nil)
                return
            case .proceed: // 続けてOK
                print("SecTrustEvaluate: .proceed")
                break
            case .deny: // ユーザが駄目と言った
                print("SecTrustEvaluate: .deny")
                completionHandler(.rejectProtectionSpace, nil)
                return
            case .unspecified: // 問題なかった(通常はこれが返るらしい)
                //print("SecTrustEvaluate: .unspecified")
                break
            case .otherError: // その他エラー
                print("SecTrustEvaluate: .otherError")
                completionHandler(.rejectProtectionSpace, nil)
                return
            case .invalid: // 初期値
                print("SecTrustEvaluate: .invalid")
                completionHandler(.rejectProtectionSpace, nil)
                break
            default:
                print("SecTrustEvaluate: default")
                break
            }
            self.updateAddressBackgroundColor(color: self.addressBarBackgroundColorValid)
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }
        else if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodDefault
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodNegotiate
            || challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodNTLM
            {
            EasyDialog.Builder(self)
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
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if navigationAction.targetFrame == nil
                || !navigationAction.targetFrame!.isMainFrame {
                if let url = navigationAction.request.url {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
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
    
    // ページが表示された時に呼ばれるみたい
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateAddressBackgroundColor(color: addressBarBackgroundColor)
    }
    
    // JavaScript で Alertされた時
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
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
            EasyDialog.Builder(self)
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
        EasyDialog.Builder(self)
        .title(title: String.localizedStringWithFormat(NSLocalizedString("ImportFromWebPageViewController_MessageFrom...", comment: "%@からのメッセージ"), hostString))
        .label(text: message)
        .addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
            dialog.dismiss(animated: false, completion: nil)
        }
        .build().show()
        completionHandler()
    }

    // テキスト入力を迫られた場合のハンドラ
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        var hostString = NSLocalizedString("ImportFromWebPageViewController_UnknownHost", comment: "不明なホスト")
        if let host = self.wkWebView?.url?.host {
            hostString = host
        }
        EasyDialog.Builder(self)
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
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        var hostString = NSLocalizedString("ImportFromWebPageViewController_UnknownHost", comment: "不明なホスト")
        if let host = self.wkWebView?.url?.host {
            hostString = host
        }
        EasyDialog.Builder(self)
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
}
