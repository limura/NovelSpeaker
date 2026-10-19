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
