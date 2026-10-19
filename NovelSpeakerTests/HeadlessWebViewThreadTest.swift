import XCTest
import WebKit
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
        // Erik自身もハンドラを追加するため、リロード時は新しい設定を渡す。
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
                XCTAssertEqual(controller.removals, 1)
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
}
