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

    func testCloudRecoveryWarningCanBeCancelled() throws {
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let settings = app.buttons["設定"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        let row = app.tables.cells.containing(.staticText, identifier: "iCloudの処理を確認・再開する").firstMatch
        for _ in 0..<25 {
            if row.exists && row.isHittable { break }
            app.tables.firstMatch.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["iCloudの処理を確認・再開する"].exists)
        XCTAssertTrue(alert.buttons["確認・再開"].exists)
        XCTAssertFalse(alert.buttons["削除"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "cloud-recovery-warning"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        alert.buttons["キャンセル"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    func testCloudDataRemovalWarningCanBeCancelled() throws {
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let settings = app.buttons["設定"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        let row = app.tables.cells.containing(.staticText, identifier: "iCloud上のことせかいのデータを削除").firstMatch
        for _ in 0..<25 {
            if row.exists && row.isHittable { break }
            app.tables.firstMatch.swipeUp()
        }
        if !row.exists { print(app.debugDescription) }
        XCTAssertTrue(row.isHittable)
        row.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["iCloud上のことせかいのデータを削除"].exists)
        XCTAssertTrue(alert.buttons["削除"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "cloud-data-removal-warning"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // 実際のCloudKitへの削除要求は送らない。
        alert.buttons["キャンセル"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists)
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

final class ActivityIndicatorUITests: XCTestCase {
    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIApplication().screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testIndicatorSurvivesOverlappingJobs() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-ActivityIndicatorVisualUITesting", "-UITestingAllowRotation"]; app.launch()
        app.buttons["IndicatorStartA"].tap()
        let state = app.staticTexts["IndicatorVisualState"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "active=1"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "FT-active-visual"; image.lifetime = .keepAlways; add(image)
        XCTAssertTrue(state.label.contains("sceneViews=1") && state.label.contains("drawnViews=1"), state.label)
        app.buttons["IndicatorStartB"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "active=2"), evaluatedWith: state); waitForExpectations(timeout: 5)
        app.buttons["IndicatorStopA"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "active=1"), evaluatedWith: state); waitForExpectations(timeout: 5)
        XCTAssertTrue(state.label.contains("sceneViews=1") && state.label.contains("drawnViews=1"), state.label)
        app.buttons["IndicatorStopB"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "active=0"), evaluatedWith: state); waitForExpectations(timeout: 5)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "sceneViews=0"), evaluatedWith: state); waitForExpectations(timeout: 5)
        app.buttons["IndicatorStartA"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "active=1"), evaluatedWith: state); waitForExpectations(timeout: 5)
        app.buttons["IndicatorPush"].tap()
        XCTAssertTrue(app.navigationBars["Dark fixture"].waitForExistence(timeout: 5))
        let dark = XCTAttachment(screenshot: app.screenshot()); dark.name = "FT-dark-navigation"; dark.lifetime = .keepAlways; add(dark)
        app.buttons["IndicatorReturn"].tap()
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTAttachment(screenshot: app.screenshot()); rotated.name = "FT-landscape"; rotated.lifetime = .keepAlways; add(rotated)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(state.label.contains("drawnViews=1"), state.label)

    }
    func testActivityIndicatorPadUsesSceneOverlay() {
        let app = XCUIApplication(); app.launchArguments = ["-ActivityIndicatorVisualUITesting"]; app.launch()
        app.buttons["IndicatorStartA"].tap()
        let state = app.staticTexts["IndicatorVisualState"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "active=1"), evaluatedWith: state); waitForExpectations(timeout: 5)
        expectation(for: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "sceneViews=1", "drawnViews=1"), evaluatedWith: state); waitForExpectations(timeout: 5)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "indicator-ipad-scene-overlay"; image.lifetime = .keepAlways; add(image)
        app.buttons["IndicatorStopA"].tap()
    }
    func testSceneIndicatorSurvivesTabsFullScreenAndRotation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-ActivityIndicatorVisualUITesting","-UITestingAllowRotation","-IndicatorExtendedLayoutTesting"];app.launch()
        app.buttons["IndicatorStartA"].tap();app.buttons["IndicatorShowLayout"].tap()
        let second=app.buttons["Second"].firstMatch;screenshot("indicator-tabs-presented");XCTAssertTrue(second.waitForExistence(timeout:5),app.debugDescription);second.tap()
        let state=app.staticTexts["IndicatorLayoutState"]
        expectation(for:NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@", "active=1","drawnViews=1"),evaluatedWith:state);waitForExpectations(timeout:5)
        screenshot("indicator-tabs-title-controls")
        let toggle=app.buttons["IndicatorToggleFullScreen"];toggle.tap()
        XCTAssertTrue(toggle.isHittable);XCTAssertTrue(app.buttons["IndicatorLayoutClose"].isHittable)
        XCTAssertTrue(state.label.contains("drawnViews=1"));screenshot("indicator-full-screen-safe-area")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(state.waitForExistence(timeout:5));XCTAssertTrue(state.label.contains("drawnViews=1"));screenshot("indicator-expanded-rotated")
        XCUIDevice.shared.orientation = .portrait
        toggle.tap();XCTAssertTrue(second.waitForExistence(timeout:5))
        app.buttons["IndicatorLayoutClose"].tap();app.buttons["IndicatorStopA"].tap()
        let original=app.staticTexts["IndicatorVisualState"]
        expectation(for:NSPredicate(format:"label CONTAINS %@ AND label CONTAINS %@", "active=0","drawnViews=0"),evaluatedWith:original);waitForExpectations(timeout:5)
    }
}

extension ActivityIndicatorUITests {
    func testRightPlacementWaitsForActualPortraitLandscapeAndHiddenStatusBar() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-ActivityIndicatorVisualUITesting","-UITestingAllowRotation","-IndicatorExtendedLayoutTesting"]
        XCUIDevice.shared.orientation = .portrait
        app.launch();app.buttons["IndicatorStartA"].tap();app.buttons["IndicatorShowLayout"].tap()
        let state=app.staticTexts["IndicatorLayoutState"]
        XCTAssertTrue(state.waitForExistence(timeout:10))
        func rect(_ key:String, _ text:String) -> CGRect? {
            guard let start=text.range(of:key)?.upperBound,
                  let opening=text[start...].firstIndex(of:"("),let closing=text[opening...].firstIndex(of:")") else {return nil}
            let values=text[text.index(after:opening)..<closing].split(separator:",").compactMap {Double($0.trimmingCharacters(in:.whitespaces))}
            guard values.count == 4 else {return nil}
            return CGRect(x:values[0],y:values[1],width:values[2],height:values[3])
        }
        func check(portrait:Bool,hidden:Bool,name:String) throws {
            expectation(for:NSPredicate(block:{_,_ in
                let text=state.label
                guard let bounds=rect("bounds=",text),let status=rect("status=",text) else{return false}
                return (portrait ? bounds.height > bounds.width : bounds.width > bounds.height) && (hidden ? status.height == 0 : status.height > 0) && text.contains("drawnViews=1")
            }),evaluatedWith:state)
            waitForExpectations(timeout:15)
            let bounds=try XCTUnwrap(rect("bounds=",state.label)),indicator=try XCTUnwrap(rect("indicatorWindowFrames=",state.label))
            XCTAssertGreaterThan(indicator.midX,bounds.midX,state.label)
            XCTAssertTrue(bounds.contains(indicator),state.label)
            // The app-window snapshot can still use portrait coordinates during rotation.
            // Wait for the display itself and capture the complete screen.
            expectation(for:NSPredicate(block:{_,_ in
                let size=XCUIScreen.main.screenshot().image.size
                return portrait ? size.height > size.width : size.width > size.height
            }),evaluatedWith:state)
            waitForExpectations(timeout:15)
            let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
            attachment.name=name+"-\(Int(bounds.width))x\(Int(bounds.height))"
            attachment.lifetime = .keepAlways;add(attachment)
        }
        try check(portrait:true,hidden:false,name:"indicator-right-portrait")
        app.buttons["IndicatorToggleFullScreen"].tap()
        try check(portrait:true,hidden:true,name:"indicator-right-portrait-hidden")
        XCUIDevice.shared.orientation = .landscapeLeft
        try check(portrait:false,hidden:true,name:"indicator-right-landscape-hidden")
        XCUIDevice.shared.orientation = .portrait
        try check(portrait:true,hidden:true,name:"indicator-right-restored-portrait-hidden")
        app.buttons["IndicatorToggleFullScreen"].tap()
        try check(portrait:true,hidden:false,name:"indicator-right-restored-portrait")
        app.buttons["IndicatorLayoutClose"].tap();app.buttons["IndicatorStopA"].tap()
    }
}
