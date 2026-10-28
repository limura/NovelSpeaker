import XCTest
import WebKit
import Erik
@testable import NovelSpeaker

final class HeadlessWebViewThreadTest: XCTestCase {
    private final class CheckedContentController: WKUserContentController {
        var registrations = 0
        var removals = 0
        override func add(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
            XCTAssertTrue(Thread.isMainThread, "WebKitのハンドラ登録はメインスレッドで行う")
            if name == HeadlessReadyMessageHandler.name { registrations += 1 }
            super.add(scriptMessageHandler, name: name)
        }
        override func removeScriptMessageHandler(forName name: String) {
            XCTAssertTrue(Thread.isMainThread, "WebKitのハンドラ解除はメインスレッドで行う")
            if name == HeadlessReadyMessageHandler.name { removals += 1 }
            super.removeScriptMessageHandler(forName: name)
        }
    }

    func testBackgroundCreationAndReloadRegisterHandlersOnMainThread() {
        let configuration = WKWebViewConfiguration()
        let controller = CheckedContentController()
        configuration.userContentController = controller
        let reloadConfiguration = WKWebViewConfiguration()
        let reloadController = CheckedContentController()
        reloadConfiguration.userContentController = reloadController
        let ready = expectation(description: "ready message after background reload")
        var retainedClient: HeadlessHttpClient?
        DispatchQueue.global(qos: .utility).async {
            let client = HeadlessHttpClient(config: configuration)
            client.ReloadWebView(config: reloadConfiguration)
            DispatchQueue.main.async {
                retainedClient = client
                XCTAssertEqual(controller.registrations, 1)
                XCTAssertEqual(controller.removals, 2)
                XCTAssertEqual(reloadController.registrations, 1)
                XCTAssertEqual(reloadController.removals, 1)
                client.readyHandler.onMessage = { body in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertEqual(body["ready"] as? Bool, true)
                    ready.fulfill()
                }
                client.webView.loadHTMLString("""
                    <html><body><script>
                    window.webkit.messageHandlers.novelSpeakerReady.postMessage({ready: true});
                    </script></body></html>
                    """, baseURL: nil)
            }
        }
        wait(for: [ready], timeout: 15)
        withExtendedLifetime(retainedClient) {}
        retainedClient = nil
    }
    private func drainMainQueue() {
        let done = expectation(description: "drain WebKit callbacks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testClientDestructionReleasesWebViewAndErikEngine() {
        // 設定が外部に残っていても、登録されたErikハンドラがWebViewを保持しないこと。
        let configuration = WKWebViewConfiguration()
        weak var webView: WKWebView?
        weak var engine: AnyObject?
        autoreleasepool {
            let client = HeadlessHttpClient(config: configuration)
            webView = client.webView
            engine = client.erik.layoutEngine as AnyObject
        }
        drainMainQueue()
        XCTAssertNil(webView)
        XCTAssertNil(engine)
        withExtendedLifetime(configuration) {}
    }

    func testReloadWithSameConfigurationReleasesPreviousWebView() {
        let configuration = WKWebViewConfiguration()
        var client: HeadlessHttpClient!
        weak var previousWebView: WKWebView?
        weak var previousEngine: AnyObject?
        autoreleasepool {
            client = HeadlessHttpClient(config: configuration)
            previousWebView = client.webView
            previousEngine = client.erik.layoutEngine as AnyObject
            client.ReloadWebView(config: configuration)
        }
        drainMainQueue()
        XCTAssertNil(previousWebView)
        XCTAssertNil(previousEngine)
        XCTAssertNotNil(client.webView)
        withExtendedLifetime(client) {}
    }

    func testButtonNavigationReusesWebViewAndReleasesItAfterwards() {
        weak var webView: WKWebView?
        autoreleasepool {
            let client = HeadlessHttpClient()
            webView = client.webView
            let identity = ObjectIdentifier(client.webView!)
            let loaded = expectation(description: "button page loaded")
            client.readyHandler.onMessage = { _ in loaded.fulfill() }
            client.webView.loadHTMLString("""
                <html><body><article id="content">1</article>
                <button class="next" onclick="document.getElementById('content').textContent=String(Number(document.getElementById('content').textContent)+1)">次へ</button>
                <script>window.webkit.messageHandlers.novelSpeakerReady.postMessage({ready:true});</script>
                </body></html>
                """, baseURL: nil)
            wait(for: [loaded], timeout: 15)
            client.readyHandler.onMessage = nil
            for expected in 1...4 {
                let done = expectation(description: "button page \(expected)")
                client.GetCurrentContent { document, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(document?.querySelectorAll("#content").first?.text, String(expected))
                    if expected < 4 {
                        guard let button = document?.querySelectorAll(".next").first else {
                            XCTFail("次ページのボタンがない")
                            done.fulfill()
                            return
                        }
                        button.click { _, error in
                            XCTAssertNil(error)
                            done.fulfill()
                        }
                    } else {
                        done.fulfill()
                    }
                }
                wait(for: [done], timeout: 20)
                XCTAssertEqual(ObjectIdentifier(client.webView!), identity)
            }
        }
        drainMainQueue()
        XCTAssertNil(webView)
    }

}

extension HeadlessWebViewThreadTest {
    private final class ContentThreadClient: HeadlessHttpClient {
        var completion: (() -> Void)?
        override func GetCurrentContent(completionHandler: ((Document?, Error?) -> Void)?) {
            XCTAssertTrue(Thread.isMainThread, "worker由来の共通待機もメインからDOM取得する")
            completionHandler?(nil, nil); completion?()
        }
    }
    func testWorkerCallbackZeroWaitEntersContentOnMain() {
        let done = expectation(description: "worker callback to content")
        done.assertForOverFulfill = true
        let client = ContentThreadClient(); client.completion = { done.fulfill() }
        DispatchQueue(label: "fixture.ErikCallBack").async {
            XCTAssertFalse(Thread.isMainThread)
            NiftyUtility.headlessWaitThenContent(client: client, url: URL(string: "https://fixture.invalid/")!, withWaitSecond: 0, siteInfoArrayOverride: []) { _,_ in }
        }
        wait(for: [done], timeout: 5)
        withExtendedLifetime(client) {}
    }
}

extension HeadlessWebViewThreadTest {
    private func threadSiteInfo(smart: Bool, dismiss: String? = nil) -> StorySiteInfo {
        StorySiteInfo(id: UUID().uuidString, name: "thread-fixture", pageElementV2: "//*[@id='content']", url: ".*", title: nil, subtitle: nil, firstPageLink: nil, nextLink: nil, tag: nil, author: nil, isNeedHeadless: "1", injectStyle: nil, nextButton: nil, firstPageButton: nil, waitSecondInHeadless: nil, forceClickButton: dismiss, resourceUrl: nil, overrideUserAgent: nil, forceErrorMessageAndElement: nil, scrollTo: nil, isNeedWhitespaceSplitForTag: nil, allowSmartWait: smart ? "1" : "0")
    }
    private func loadThreadFixture(_ client: HeadlessHttpClient, text: String, empty: Bool = false) {
        let loaded = expectation(description: "isolated HTML ready")
        client.readyHandler.onMessage = { _ in loaded.fulfill() }
        let content = empty ? "" : text
        client.webView.loadHTMLString("""
            <html><body><article id="content">\(content)</article>
            <button class="next" onclick="document.getElementById('content').textContent=String(Number(document.getElementById('content').textContent)+1)">Next</button>
            <button class="dismiss" onclick="this.remove()">Dismiss</button>
            <script>window.webkit.messageHandlers.novelSpeakerReady.postMessage({ready:true});</script></body></html>
            """, baseURL: URL(string: "https://thread-fixture.invalid/"))
        wait(for: [loaded], timeout: 15); client.readyHandler.onMessage = nil
    }
    func testActualErikClickCookieWorkerDismissAndNextPagesOnce() {
        let client = HeadlessHttpClient(); loadThreadFixture(client, text: "1")
        let site = threadSiteInfo(smart: false, dismiss: ".dismiss")
        for expected in 2...4 {
            let done = expectation(description: "real worker click/cookie -> main \(expected)"); done.assertForOverFulfill = true
            client.GetCurrentContent { document,error in
                XCTAssertTrue(Thread.isMainThread); XCTAssertNil(error)
                guard let button = document?.querySelectorAll(".next").first else { XCTFail("missing fixture next button");done.fulfill();return }
                button.click { _,error in
                    XCTAssertFalse(Thread.isMainThread, "Use the real ErikCallBack queue, not a mocked main callback")
                    XCTAssertNil(error)
                    client.GetCurrentCookieString { cookie,error in
                        XCTAssertFalse(Thread.isMainThread)
                        // StoryFetcher continues regardless of an empty/unsupported cookie result.
                        // This test concerns the real callback queue, not new cookie normalization.
                        if error != nil { XCTAssertNil(cookie) }
                        NiftyUtility.headlessWaitThenContent(client: client, url: URL(string:"https://thread-fixture.invalid/")!, withWaitSecond: 0, siteInfoArrayOverride: [site]) { document,error in
                            XCTAssertTrue(Thread.isMainThread);XCTAssertNil(error)
                            XCTAssertEqual(document?.querySelectorAll("#content").first?.text,String(expected))
                            XCTAssertTrue(document?.querySelectorAll(".dismiss").isEmpty == true)
                            done.fulfill()
                        }
                    }
                }
            }
            wait(for:[done],timeout:15)
        }
        withExtendedLifetime(client) {}
    }
    func testWorkerSmartAndFixedWaitKeepSeparateClientsAndDelay() {
        let smart = HeadlessHttpClient(), fixed = HeadlessHttpClient()
        loadThreadFixture(smart,text:"A");loadThreadFixture(fixed,text:"B")
        let ready=expectation(description:"smart client"),delayed=expectation(description:"fixed client")
        ready.assertForOverFulfill=true;delayed.assertForOverFulfill=true
        let smartSite=threadSiteInfo(smart:true),fixedSite=threadSiteInfo(smart:false)
        let started=Date()
        DispatchQueue(label:"fixture.ErikCallBack.multiple").async {
            NiftyUtility.headlessWaitThenContent(client:smart,url:URL(string:"https://thread-fixture.invalid/a")!,withWaitSecond:0.2,siteInfoArrayOverride:[smartSite]) {document,error in
                XCTAssertTrue(Thread.isMainThread);XCTAssertNil(error);XCTAssertEqual(document?.querySelectorAll("#content").first?.text,"A");ready.fulfill()
            }
            NiftyUtility.headlessWaitThenContent(client:fixed,url:URL(string:"https://thread-fixture.invalid/b")!,withWaitSecond:0.12,siteInfoArrayOverride:[fixedSite]) {document,error in
                XCTAssertTrue(Thread.isMainThread);XCTAssertNil(error);XCTAssertEqual(document?.querySelectorAll("#content").first?.text,"B")
                XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started),0.10);delayed.fulfill()
            }
        }
        wait(for:[ready,delayed],timeout:10)
        XCTAssertNil(smart.readyHandler.onMessage)
        withExtendedLifetime([smart,fixed]) {}
    }
    func testWorkerScriptErrorAndReadyTimeoutStillCompleteOnce() {
        let client=HeadlessHttpClient();loadThreadFixture(client,text:"",empty:true)
        let done=expectation(description:"error and ready timeout");done.assertForOverFulfill=true
        let site=threadSiteInfo(smart:true)
        client.ExecuteJavaScript(javaScript:"throw new Error('isolated fixture failure')") {_,error in
            XCTAssertFalse(Thread.isMainThread);XCTAssertNotNil(error)
            NiftyUtility.headlessWaitThenContent(client:client,url:URL(string:"https://thread-fixture.invalid/")!,withWaitSecond:0.05,siteInfoArrayOverride:[site]) {document,error in
                XCTAssertTrue(Thread.isMainThread);XCTAssertNil(error);XCTAssertEqual(document?.querySelectorAll("#content").first?.text,"");done.fulfill()
            }
        }
        wait(for:[done],timeout:10)
        let settled=expectation(description:"no repeated completion after timeout and DOM change")
        client.webView.evaluateJavaScript("document.getElementById('content').textContent='later'") {_,_ in
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) {settled.fulfill()}
        }
        wait(for:[settled],timeout:5);XCTAssertNil(client.readyHandler.onMessage)
        withExtendedLifetime(client) {}
    }
}

extension HeadlessWebViewThreadTest {
    private final class CheckedNavigationWebView: WKWebView {
        var delegateReads = 0
        override var navigationDelegate: WKNavigationDelegate? {
            get { XCTAssertTrue(Thread.isMainThread, "Erikのロード待機診断もWKWebView getterはメインから読む");delegateReads += 1;return super.navigationDelegate }
            set { XCTAssertTrue(Thread.isMainThread);super.navigationDelegate = newValue }
        }
    }
    private final class HeldNavigationDelegate: NSObject, WKNavigationDelegate, Navigable {
        private let lock = NSLock()
        private var loading = true
        var navigate: Bool {
            get { lock.lock(); defer { lock.unlock() }; return loading }
            set { lock.lock(); loading = newValue; lock.unlock() }
        }
    }
    func testErikDiagnosticEachWaitLeavesMainResponsiveAndTimeoutCompletesOnce() throws {
        let configuration = WKWebViewConfiguration(), handler = HeadlessReadyMessageHandler()
        configuration.userContentController.add(handler, name: HeadlessReadyMessageHandler.name)
        let view = CheckedNavigationWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "local DOM ready")
        handler.onMessage = { _ in loaded.fulfill() }
        view.loadHTMLString("<html><body>fixture<script>window.webkit.messageHandlers.novelSpeakerReady.postMessage({ready:true});</script></body></html>", baseURL: nil)
        wait(for: [loaded], timeout: 15); handler.onMessage = nil
        let delegate = HeldNavigationDelegate(); view.navigationDelegate = delegate
        let browser = Erik(webView: view)
        let engine = try XCTUnwrap(browser.layoutEngine as? WebKitLayoutEngine)
        engine.pageLoadTimeout = 0.08
        defer {
            for name in [HeadlessReadyMessageHandler.name, "erikError", "erikEnd"] { configuration.userContentController.removeScriptMessageHandler(forName: name) }
        }
        for index in 0..<2 {
            let before = view.delegateReads
            let done = expectation(description: "timeout once \(index)"); done.assertForOverFulfill = true
            let heartbeat = expectation(description: "main remains responsive \(index)")
            browser.currentContent { document, error in
                XCTAssertNil(document); XCTAssertNotNil(error); done.fulfill()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { heartbeat.fulfill() }
            wait(for: [done, heartbeat], timeout: 5)
            XCTAssertGreaterThan(view.delegateReads, before, "Every new wait must schedule the same main-thread identity diagnostic")
        }
        delegate.navigate = false
        let success = expectation(description: "content after loading ends"); success.assertForOverFulfill = true
        browser.currentContent { document, error in
            XCTAssertTrue(Thread.isMainThread); XCTAssertNil(error); XCTAssertNotNil(document); success.fulfill()
        }
        wait(for: [success], timeout: 5)
        withExtendedLifetime((browser, delegate)) {}
    }
    func testErikLoadingDelegateDiagnosticReadsWebViewOnMain() {
        let configuration=WKWebViewConfiguration(),handler=HeadlessReadyMessageHandler()
        configuration.userContentController.add(handler,name:HeadlessReadyMessageHandler.name)
        let view=CheckedNavigationWebView(frame:.zero,configuration:configuration),browser=Erik(webView:view)
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName:HeadlessReadyMessageHandler.name)
            configuration.userContentController.removeScriptMessageHandler(forName:"erikError")
            configuration.userContentController.removeScriptMessageHandler(forName:"erikEnd")
        }
        let loaded=expectation(description:"checked DOM loaded")
        handler.onMessage={_ in loaded.fulfill()}
        view.loadHTMLString("<html><body>fixture<script>window.webkit.messageHandlers.novelSpeakerReady.postMessage({ready:true});</script></body></html>",baseURL:nil)
        wait(for:[loaded],timeout:15);handler.onMessage=nil
        let before=view.delegateReads,done=expectation(description:"checked loading delegate")
        browser.currentContent {document,error in XCTAssertTrue(Thread.isMainThread);XCTAssertNil(error);XCTAssertNotNil(document);done.fulfill()}
        wait(for:[done],timeout:15);XCTAssertGreaterThan(view.delegateReads,before)
        withExtendedLifetime(browser) {}
    }
    func testWorkerPageClearAndContentCallbackKeepExistingCompletionContract() {
        let client=HeadlessHttpClient();loadThreadFixture(client,text:"previous")
        let done=expectation(description:"page clear/capture completes once");done.assertForOverFulfill=true
        DispatchQueue(label:"fixture.ErikCallBack.cancel").async {
            // LoadAboutPage is asynchronous navigation, not a cancellation token.
            // An existing capture may still finish; do not change that contract.
            client.LoadAboutPage()
            NiftyUtility.headlessWaitThenContent(client:client,url:URL(string:"https://thread-fixture.invalid/")!,withWaitSecond:0,siteInfoArrayOverride:[]) {document,error in
                XCTAssertTrue(Thread.isMainThread)
                if document != nil { XCTAssertNil(error) } else { XCTAssertNotNil(error) }
                done.fulfill()
            }
        }
        wait(for:[done],timeout:15)
        let cleared=expectation(description:"blank navigation committed")
        func checkBlank(_ attempts:Int) {
            XCTAssertTrue(Thread.isMainThread)
            if client.webView.url?.absoluteString == "about:blank", !client.webView.isLoading {cleared.fulfill();return}
            guard attempts > 0 else {XCTFail("fixture blank navigation did not finish");cleared.fulfill();return}
            DispatchQueue.main.asyncAfter(deadline:.now()+0.01) {checkBlank(attempts-1)}
        }
        checkBlank(500);wait(for:[cleared],timeout:10)
        let empty=expectation(description:"new capture after clear has no old document");empty.assertForOverFulfill=true
        client.GetCurrentContent {document,error in XCTAssertTrue(Thread.isMainThread);XCTAssertNil(document);XCTAssertNotNil(error);empty.fulfill()}
        wait(for:[empty],timeout:10);withExtendedLifetime(client) {}
    }
    func testWorkerFetchZeroTTLStopsOnceWithoutNavigation() {
        let fetcher=StoryFetcher(),url=URL(string:"https://thread-fixture.invalid/ttl")!
        let state=StoryState(url:url,cookieString:nil,content:nil,nextUrl:nil,firstPageLink:nil,title:nil,author:nil,subtitle:nil,tagArray:[],siteInfoArray:[],isNeedHeadless:true,waitSecondInHeadless:nil,previousContent:nil,document:nil,nextButton:nil,firstPageButton:nil,forceClickButton:nil,forceErrorMessage:nil)
        let done=expectation(description:"TTL failure exactly once");done.assertForOverFulfill=true
        DispatchQueue(label:"fixture.fetch.worker").async {
            fetcher.FetchNext(currentState:state,fetchTimeToLive:0,successAction:{_ in XCTFail("TTL must not fetch")},failedAction:{failedURL,message in XCTAssertEqual(failedURL,url);XCTAssertFalse(message.isEmpty);done.fulfill()})
        }
        wait(for:[done],timeout:5);withExtendedLifetime(fetcher) {}
    }
}

// Exercise the actual DCL loader with a short test timeout; production remains 300 seconds.
final class HeadlessDCLLifetimeTest: XCTestCase {
    private enum Mode { case success, failure, pending }
    private final class PageHandler: NSObject, WKURLSchemeHandler {
        let mode: Mode
        var started: (() -> Void)?
        var stops = 0
        var responseDelay: TimeInterval = 0
        private var stopped: Set<ObjectIdentifier> = []
        init(_ mode: Mode) { self.mode = mode }
        func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
            stopped.remove(ObjectIdentifier(task))
            started?()
            switch mode {
            case .success:
                if responseDelay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + responseDelay) { [weak self] in
                        guard let self, !self.stopped.contains(ObjectIdentifier(task)) else { return }
                        self.sendPage(task)
                    }
                } else { sendPage(task) }
            case .failure:
                task.didFailWithError(URLError(.cannotLoadFromNetwork))
            case .pending:
                break // Never deliver data. stopLoading is invoked by the test.
            }
        }
        private func sendPage(_ task: WKURLSchemeTask) {
            let label = task.request.url!.lastPathComponent
            let data = Data(("<html><body><article id='content'>" + label + "</article><script>window.webkit.messageHandlers.novelSpeakerReady.postMessage({ready:true});</script></body></html>").utf8)
            task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
            task.didReceive(data); task.didFinish()
        }
        func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
            stops += 1; stopped.insert(ObjectIdentifier(task))
        }
    }
    private final class Client: HeadlessHttpClient {
        var onDeinit: (() -> Void)?
        deinit { onDeinit?() }
    }
    private final class Probe {
        weak var client: Client?
        weak var view: WKWebView?
        weak var engine: AnyObject?
        var callbacks = 0
        var deinits = 0
        var callbackError: Error?
        let start = Date()

    }
    private let callerTimeout: TimeInterval = 4 // Production StoryFetcher supplies 300; actual +2.5 is unchanged.
    private func drain(_ seconds: TimeInterval) {
        let done = expectation(description: "lifetime observation interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }
    private func finishAfterDeadline(_ probe: Probe) {
        drain(max(0.3, callerTimeout + 2.5 + 0.7 - Date().timeIntervalSince(probe.start)))
        XCTAssertEqual(probe.callbacks, 1)
        XCTAssertEqual(probe.deinits, 1)
        XCTAssertNil(probe.client)
        // WKWebView release is observed separately: WebKit may retain a loaded page beyond client/engine teardown.
        XCTAssertNil(probe.engine)
    }
    func testNoDCLRequestReleasesClientWithoutWaitingForTimer() {
        XCTAssertTrue(Thread.isMainThread)
        let probe = Probe()
        autoreleasepool {
            let client = Client()
            client.onDeinit = { probe.deinits += 1 }
            probe.client = client; probe.view = client.webView; probe.engine = client.erik.layoutEngine as AnyObject
        }
        drain(0.5)
        XCTAssertEqual(probe.deinits, 1)
        XCTAssertNil(probe.client); XCTAssertNil(probe.view); XCTAssertNil(probe.engine)
    }
    func testActualSuccessfulDCLReleasesClientBeforeOldTimeout() {
        XCTAssertTrue(Thread.isMainThread)
        let handler = PageHandler(.success)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe(), done = expectation(description: "actual DCL success once")
        done.assertForOverFulfill = true
        var owner: Client? = Client(config: config!)
        config = nil // Product owns its configuration; do not retain a separate fixture owner.
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/success")!, timeoutInterval: callerTimeout) { error in
            probe.callbacks += 1; probe.callbackError = error; done.fulfill()
        }
        wait(for: [done], timeout: callerTimeout + 4)
        XCTAssertNil(probe.callbackError)
        XCTAssertLessThan(Date().timeIntervalSince(probe.start), callerTimeout + 2.0)
        autoreleasepool { owner = nil }
        drain(0.25)
        XCTAssertNil(probe.client, "Completed DCL must not retain its client until the old timeout")
        XCTAssertNil(probe.engine)
        XCTAssertEqual(probe.deinits, 1)
        finishAfterDeadline(probe)

    }
    func testActualFailedNavigationFinishesOnceAndReleasesAfterTimeout() {
        XCTAssertTrue(Thread.isMainThread)
        let handler = PageHandler(.failure)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe(), started = expectation(description: "failure scheme started"), done = expectation(description: "actual DCL timeout after navigation failure")
        done.assertForOverFulfill = true; handler.started = { started.fulfill() }
        var owner: Client? = Client(config: config!)
        config = nil // Product owns its configuration; do not retain a separate fixture owner.
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/failure")!, timeoutInterval: callerTimeout) { error in
            probe.callbacks += 1; probe.callbackError = error; done.fulfill()
        }
        wait(for: [started], timeout: 5); handler.started = nil
        autoreleasepool { owner = nil }
        drain(0.25)
        XCTAssertNotNil(probe.client); XCTAssertEqual(probe.callbacks, 0)
        wait(for: [done], timeout: callerTimeout + 4)
        XCTAssertNotNil(probe.callbackError)
        finishAfterDeadline(probe)

    }
    func testStopLoadingDoesNotCancelLogicalTimeoutOrReleaseClientEarly() {
        XCTAssertTrue(Thread.isMainThread)
        let handler = PageHandler(.pending)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe(), started = expectation(description: "pending local scheme started"), done = expectation(description: "actual DCL timeout after stopLoading")
        done.assertForOverFulfill = true; handler.started = { started.fulfill() }
        var owner: Client? = Client(config: config!)
        config = nil // Product owns its configuration; do not retain a separate fixture owner.
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/pending")!, timeoutInterval: callerTimeout) { error in
            probe.callbacks += 1; probe.callbackError = error; done.fulfill()
        }
        wait(for: [started], timeout: 5); handler.started = nil
        owner?.webView.stopLoading()
        autoreleasepool { owner = nil }
        drain(0.25)
        XCTAssertNotNil(probe.client); XCTAssertEqual(probe.callbacks, 0)
        wait(for: [done], timeout: callerTimeout + 4)
        XCTAssertNotNil(probe.callbackError)
        XCTAssertGreaterThanOrEqual(handler.stops, 1)
        finishAfterDeadline(probe)

    }
    func testLoadedLocalPageWithoutDCLSeparatesWebViewFromClientLifetime() {
        let handler = PageHandler(.success)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe(), loaded = expectation(description: "local page without DCL loader")
        var owner: Client? = Client(config: config!)
        config = nil
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        owner?.readyHandler.onMessage = { _ in loaded.fulfill() }
        owner?.webView.load(URLRequest(url: URL(string: "lifetime-fixture://local/baseline")!))
        wait(for: [loaded], timeout: 8)
        owner?.readyHandler.onMessage = nil
        autoreleasepool { owner = nil }
        drain(0.6)
        XCTAssertEqual(probe.deinits, 1)
        XCTAssertNil(probe.client); XCTAssertNil(probe.engine)
    }

    func testPendingRequestSurvivesExternalOwnerReleaseUntilTimeout() {
        let handler = PageHandler(.pending)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe(), started = expectation(description: "pending request owns client"), done = expectation(description: "pending timeout exactly once")
        done.assertForOverFulfill = true; handler.started = { started.fulfill() }
        var owner: Client? = Client(config: config!); config = nil
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/pending-timeout")!, timeoutInterval: callerTimeout) { error in
            probe.callbacks += 1; probe.callbackError = error; done.fulfill()
        }
        wait(for: [started], timeout: 5); handler.started = nil
        autoreleasepool { owner = nil }
        drain(0.25); XCTAssertNotNil(probe.client); XCTAssertEqual(probe.callbacks, 0)
        wait(for: [done], timeout: callerTimeout + 4)
        XCTAssertNotNil(probe.callbackError)
        finishAfterDeadline(probe)
    }
    func testCallerDOMWorkRetainsClientAfterDCLThenReleasesWithoutOldTimeout() {
        let handler = PageHandler(.success)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe(), done = expectation(description: "real post-DCL content fetch")
        done.assertForOverFulfill = true
        var owner: Client? = Client(config: config!); config = nil
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        let url = URL(string: "lifetime-fixture://local/post-DOM")!
        owner?.LoadUntilDOMContentLoaded(url: url, timeoutInterval: callerTimeout) { error in
            XCTAssertNil(error); probe.callbacks += 1
            guard let client = probe.client else { XCTFail("lost client before DOM handoff"); done.fulfill(); return }
            owner = nil
            NiftyUtility.headlessWaitThenContent(client: client, url: url, withWaitSecond: 0.2, siteInfoArrayOverride: []) { document, error in
                XCTAssertNil(error); XCTAssertEqual(document?.querySelectorAll("#content").first?.text, "post-DOM")
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 6)
        drain(0.3)
        XCTAssertNil(probe.client); XCTAssertNil(probe.engine); XCTAssertEqual(probe.deinits, 1)
        finishAfterDeadline(probe)
    }
    func testSameClientCanLoadAndExtractTwoSuccessiveDocuments() {
        let handler = PageHandler(.success)
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        let probe = Probe()
        var owner: Client? = Client(config: config!); config = nil
        owner?.onDeinit = { probe.deinits += 1 }
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        let viewID = ObjectIdentifier(owner!.webView!)
        for label in ["reuse-A", "reuse-B"] {
            let done = expectation(description: "successive document " + label); done.assertForOverFulfill = true
            owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/" + label)!, timeoutInterval: callerTimeout) { error in
                XCTAssertNil(error); probe.callbacks += 1
                probe.client?.GetCurrentContent { document, error in
                    XCTAssertNil(error); XCTAssertEqual(document?.querySelectorAll("#content").first?.text, label); done.fulfill()
                }
            }
            wait(for: [done], timeout: 6)
            XCTAssertEqual(ObjectIdentifier(owner!.webView!), viewID)
        }
        owner = nil; drain(0.3)
        XCTAssertNil(probe.client); XCTAssertNil(probe.engine); XCTAssertEqual(probe.deinits, 1)
        drain(max(0.3, callerTimeout + 2.5 + 0.7 - Date().timeIntervalSince(probe.start)))
        XCTAssertEqual(probe.callbacks, 2)
    }
    func testNavigationNearTimeoutBoundaryFinishesExactlyOnce() {
        for delay in [2.0, 3.3, 3.8] {
            let handler = PageHandler(.success); handler.responseDelay = delay
            var config: WKWebViewConfiguration? = WKWebViewConfiguration()
            config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
            let probe = Probe(), done = expectation(description: "completion boundary " + String(delay)); done.assertForOverFulfill = true
            var owner: Client? = Client(config: config!); config = nil
            owner?.onDeinit = { probe.deinits += 1 }
            probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
            owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/boundary")!, timeoutInterval: 1) { error in
                probe.callbacks += 1; probe.callbackError = error; done.fulfill()
            }
            wait(for: [done], timeout: 6)
            if delay == 2.0 { XCTAssertNil(probe.callbackError) }
            if delay == 3.8 { XCTAssertNotNil(probe.callbackError) }
            owner = nil; drain(0.3)
            XCTAssertNil(probe.client); XCTAssertNil(probe.engine); XCTAssertEqual(probe.deinits, 1)
            drain(max(0.3, 4.8 - Date().timeIntervalSince(probe.start)))
            XCTAssertEqual(probe.callbacks, 1)
        }
    }

}

extension HeadlessDCLLifetimeTest {
    private final class CompletionPayload {}
    func testCompletionCaptureIsReleasedWhileReusableClientStaysAlive() {
        let handler = PageHandler(.success); handler.responseDelay = 0.4
        var config: WKWebViewConfiguration? = WKWebViewConfiguration()
        config?.setURLSchemeHandler(handler, forURLScheme: "lifetime-fixture")
        var owner: Client? = Client(config: config!); config = nil
        let probe = Probe(), done = expectation(description: "completion capture released after invocation")
        done.assertForOverFulfill = true
        probe.client = owner; probe.view = owner?.webView; probe.engine = owner?.erik.layoutEngine as AnyObject
        owner?.onDeinit = { probe.deinits += 1 }
        var payload: CompletionPayload? = CompletionPayload()
        weak var observedPayload = payload
        owner?.LoadUntilDOMContentLoaded(url: URL(string: "lifetime-fixture://local/payload")!, timeoutInterval: callerTimeout) { [captured = payload!] error in
            withExtendedLifetime(captured) {}
            XCTAssertNil(error); probe.callbacks += 1; done.fulfill()
        }
        payload = nil
        drain(0.1); XCTAssertNotNil(observedPayload, "Pending operation must keep its completion alive")
        wait(for: [done], timeout: 6)
        drain(0.25)
        XCTAssertNil(observedPayload, "Completed operation must release callback captures before old timeout")
        XCTAssertNotNil(probe.client, "Caller can still reuse its client")
        owner = nil; drain(0.25)
        XCTAssertNil(probe.client); XCTAssertNil(probe.engine); XCTAssertEqual(probe.deinits, 1)
        finishAfterDeadline(probe)
    }
}
