import XCTest

final class NovelSpeakerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        // Duo上で回転ケースを検証できるよう、アプリの回転設定をテスト中だけ全方向にする。
        app.launchArguments += ["-UITestingAllowRotation"]
    }

    func testLaunchOnSimulator() throws {
        app.launch()
        XCTAssertTrue(app.waitForExistence(timeout: 30))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLongMessageDialogLandscapeThenPortrait() throws {
        XCUIDevice.shared.orientation = .landscapeRight
        app.launchArguments += ["-UITestingLongMessageDialog", "-UITestingStartLandscape"]
        app.launch()

        XCTAssertTrue(app.waitForExistence(timeout: 30))

        let dialog = app.otherElements["UITestEasyDialog"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 15))
        let okButton = app.buttons["OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 5))
        assertAppWindowIsLandscape(named: "landscape")
        assertElementIsInsideAppWindow(okButton, named: "landscape")
        captureScreen(named: "long-dialog-landscape")

        XCUIDevice.shared.orientation = .portrait
        let portraitTrigger = app.buttons["UITestRotateToPortrait"]
        XCTAssertTrue(portraitTrigger.waitForExistence(timeout: 5))
        portraitTrigger.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        XCTAssertTrue(okButton.waitForExistence(timeout: 5))
        assertAppWindowIsPortrait(named: "portrait-after-landscape")
        assertElementIsInsideAppWindow(okButton, named: "portrait-after-landscape")
        XCTAssertTrue(okButton.isHittable)
        captureScreen(named: "long-dialog-portrait-after-landscape")
    }

    func testLongMessageDialogPortrait() throws {
        app.launchArguments += ["-UITestingLongMessageDialog"]
        app.launch()

        XCTAssertTrue(app.waitForExistence(timeout: 30))
        let dialog = app.otherElements["UITestEasyDialog"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 15))
        let okButton = app.buttons["OK"]
        XCTAssertTrue(okButton.waitForExistence(timeout: 5))
        assertElementIsInsideAppWindow(okButton, named: "portrait")
        XCTAssertTrue(okButton.isHittable)
        captureScreen(named: "long-dialog-portrait")
    }

    func testLongMessageTwoButtonDialogLandscapeThenPortrait() throws {
        XCUIDevice.shared.orientation = .landscapeRight
        app.launchArguments += ["-UITestingLongMessageTwoButtonDialog", "-UITestingStartLandscape"]
        app.launch()

        XCTAssertTrue(app.waitForExistence(timeout: 30))
        let dialog = app.otherElements["UITestEasyDialog"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 15))
        let firstButton = app.buttons["UITestDialogButton1"]
        let secondButton = app.buttons["UITestDialogButton2"]
        XCTAssertTrue(firstButton.waitForExistence(timeout: 5))
        XCTAssertTrue(secondButton.waitForExistence(timeout: 5))
        assertAppWindowIsLandscape(named: "two-button-landscape")
        assertTwoButtonLayout(firstButton, secondButton, named: "two-button-landscape")
        captureScreen(named: "long-dialog-two-button-landscape")

        XCUIDevice.shared.orientation = .portrait
        let portraitTrigger = app.buttons["UITestRotateToPortrait"]
        XCTAssertTrue(portraitTrigger.waitForExistence(timeout: 5))
        portraitTrigger.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 10))
        XCTAssertTrue(firstButton.waitForExistence(timeout: 5))
        XCTAssertTrue(secondButton.waitForExistence(timeout: 5))
        assertAppWindowIsPortrait(named: "two-button-portrait-after-landscape")
        assertTwoButtonLayout(firstButton, secondButton, named: "two-button-portrait-after-landscape")
        XCTAssertTrue(firstButton.isHittable)
        XCTAssertTrue(secondButton.isHittable)
        captureScreen(named: "long-dialog-two-button-portrait-after-landscape")
    }

    private func assertAppWindowIsLandscape(named name: String) {
        let frame = app.windows.element(boundBy: 0).frame
        XCTAssertGreaterThan(frame.width, frame.height, "\(name): expected landscape window, got \(frame)")
    }

    private func assertAppWindowIsPortrait(named name: String) {
        let frame = app.windows.element(boundBy: 0).frame
        XCTAssertGreaterThan(frame.height, frame.width, "\(name): expected portrait window, got \(frame)")
    }

    private func assertTwoButtonLayout(_ firstButton: XCUIElement, _ secondButton: XCUIElement, named name: String) {
        let windowFrame = app.windows.element(boundBy: 0).frame
        let firstFrame = firstButton.frame
        let secondFrame = secondButton.frame
        let firstInside = windowFrame.contains(firstFrame)
        let secondInside = windowFrame.contains(secondFrame)
        let sideBySide = firstFrame.maxX <= secondFrame.minX && firstFrame.minY == secondFrame.minY && firstFrame.height == secondFrame.height
        XCTContext.runActivity(named: "\(name): window=\(windowFrame), first=\(firstFrame), second=\(secondFrame), firstInside=\(firstInside), secondInside=\(secondInside), sideBySide=\(sideBySide)") { activity in
            activity.add(XCTAttachment(string: "window=\(windowFrame) first=\(firstFrame) second=\(secondFrame) firstInside=\(firstInside) secondInside=\(secondInside) sideBySide=\(sideBySide)"))
        }
        XCTAssertTrue(firstInside && secondInside, "\(name): dialog buttons must be inside app window")
        XCTAssertTrue(sideBySide, "\(name): dialog buttons must be side by side without overlap")
    }

    private func assertElementIsInsideAppWindow(_ element: XCUIElement, named name: String) {
        let window = app.windows.element(boundBy: 0)
        let windowFrame = window.frame
        let elementFrame = element.frame
        let isInside = windowFrame.contains(elementFrame)
        XCTContext.runActivity(named: "\(name): window=\(windowFrame), element=\(elementFrame), inside=\(isInside)") { activity in
            activity.add(XCTAttachment(string: "window=\(windowFrame) element=\(elementFrame) inside=\(isInside)"))
        }
        XCTAssertTrue(isInside, "\(name): element frame \(elementFrame) is outside app window \(windowFrame)")
    }

    private func captureScreen(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
