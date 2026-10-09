//
//  SpeakerTest.swift
//  NovelSpeakerTests
//
//  Created by 飯村卓司 on 2020/01/10.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import XCTest
import UIKit
import WebKit
import AVFoundation
import RealmSwift
import Eureka
@testable import NovelSpeaker

class SpeakerTest: XCTestCase {
    var speaker = SpeechBlockSpeaker()

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        speaker = SpeechBlockSpeaker()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStopSpeechHandlerRunsEvenWhenSynthesizerDoesNotSendCancelCallback() {
        let exp = expectation(description: "stop handler should run without synthesizer callback")
        speaker.m_IsSpeaking = true

        speaker.StopSpeech {
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.2)
    }

    func testStopSpeechHandlerRunsOnlyOnceWhenCancelCallbackArrivesBeforeFallback() {
        let exp = expectation(description: "stop handler should run once")
        exp.expectedFulfillmentCount = 1
        exp.assertForOverFulfill = true
        speaker.m_IsSpeaking = true

        speaker.StopSpeech {
            exp.fulfill()
        }
        speaker.finishSpeak(isCancel: true, speechString: "")

        wait(for: [exp], timeout: 1.2)
    }

    func testCarAudioIsExternalPlaybackRoute() {
        XCTAssertTrue(StorySpeaker.isExternalPlaybackRoute(portTypes: [.carAudio]))
    }

}

// ナビバー右上ボタン群のクリップ検出ロジック(NovelSpeakerUtility.UpperButtonBarLayout)の検証。
// 実アプリと同じ「customView(container) + UIStackView(28pt ボタン)」構造を実ウインドウに載せて
// レイアウトさせ、rightmostButtonOverflow がクリップの有無を実測から正しく返すことを確認する。
class UpperButtonBarLayoutTest: XCTestCase {
    private var window: UIWindow!

    private func makeButton() -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "circle"), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        let w = b.widthAnchor.constraint(equalToConstant: 28); w.priority = UILayoutPriority(999); w.isActive = true
        let h = b.heightAnchor.constraint(equalToConstant: 28); h.priority = UILayoutPriority(999); h.isActive = true
        return b
    }

    // 実アプリの assignUpperButtons と同じ構造でナビバーを組み立ててレイアウトし、
    // (navBar, stack, container) を返す。
    private func layoutNavBar(title: String, buttonCount: Int, screenWidth: CGFloat) -> (UINavigationBar, UIStackView, UIView) {
        let root = UIViewController()
        root.navigationItem.title = title

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<buttonCount { stack.addArrangedSubview(makeButton()) }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let cap = container.widthAnchor.constraint(lessThanOrEqualToConstant: screenWidth * 0.76)
        cap.priority = UILayoutPriority(999); cap.isActive = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        root.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: container)

        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: screenWidth, height: 800))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        // 実レイアウトを確定させる
        nav.view.setNeedsLayout()
        nav.view.layoutIfNeeded()
        nav.navigationBar.setNeedsLayout()
        nav.navigationBar.layoutIfNeeded()
        return (nav.navigationBar, stack, container)
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // 少数ボタン(2個)は iPhone 幅で必ず収まるので、はみ出し量は 0 以下(=クリップ無し)であること。
    func testFewButtonsDoNotOverflow() throws {
        let (navBar, stack, container) = layoutNavBar(title: "テスト小説", buttonCount: 2, screenWidth: 390)
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        let value = try XCTUnwrap(overflow, "window に載っていれば実測できるはず")
        XCTAssertLessThanOrEqual(value, 0.5, "2個のボタンはクリップされないこと(overflow=\(value))")
    }

    // 多数ボタン(10個=約 316pt)は iPhone 幅(390pt)にタイトル込みでは収まらず、
    // 最右ボタンがはみ出す(=クリップされる)ので overflow > 0 になること。
    // これが検出できることが本修正の肝(黙ってクリップされるのを検知して「…」へ退避する)。
    func testManyButtonsOverflow() throws {
        let (navBar, stack, container) = layoutNavBar(title: "とても長めのタイトル文字列です", buttonCount: 10, screenWidth: 390)
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        let value = try XCTUnwrap(overflow, "window に載っていれば実測できるはず")
        XCTAssertGreaterThan(value, 0.5, "10個のボタンは収まらず最右がクリップされること(overflow=\(value))")
    }

    // 読書画面(SpeechViewController)相当の構成: 戻るボタン付き(=nav stack に2枚)+ タイトル + 右5個。
    // iPhone 標準幅では 5個(検索/詳細/編集/再生/addPage 相当)が収まるはずで、over-trim しない
    // (overflow <= 0)ことを確認する。実機で 5→2 のような過剰削減が起きないことの回帰テスト。
    private func layoutReadingLikeNavBar(title: String, buttonCount: Int, screenWidth: CGFloat) -> (UINavigationBar, UIStackView, UIView) {
        let root = UIViewController()
        root.navigationItem.title = "本棚"

        let page = UIViewController()
        page.navigationItem.title = title
        let stack = UIStackView()
        stack.axis = .horizontal; stack.alignment = .center; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<buttonCount { stack.addArrangedSubview(makeButton()) }
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let cap = container.widthAnchor.constraint(lessThanOrEqualToConstant: screenWidth * 0.76)
        cap.priority = UILayoutPriority(999); cap.isActive = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        page.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: container)

        let nav = UINavigationController(rootViewController: root)
        nav.pushViewController(page, animated: false) // 戻るボタンを出す
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: screenWidth, height: 800))
        window.rootViewController = nav
        window.makeKeyAndVisible()
        self.window = window
        nav.view.setNeedsLayout(); nav.view.layoutIfNeeded()
        nav.navigationBar.setNeedsLayout(); nav.navigationBar.layoutIfNeeded()
        return (nav.navigationBar, stack, container)
    }

    func testReadingScreenFiveButtonsFit() throws {
        let (navBar, stack, container) = layoutReadingLikeNavBar(title: "クロード本文A改題テスト", buttonCount: 5, screenWidth: 390)
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        let value = try XCTUnwrap(overflow)
        // 5個は iPhone(390pt)+戻るボタン+12文字タイトルで収まる想定。over-trim しないこと。
        XCTAssertLessThanOrEqual(value, 0.5, "5個は収まるので削らないこと(overflow=\(value))")
    }

    // 本文画面の方針(タイトルは潰してでもボタン数を優先)の回帰テスト。
    // 長いタイトルでも、ナビバーがタイトルを truncate してボタン群にフル幅を譲るので、
    // iPhone 標準幅(390pt)で 7 個までは全ボタンが収まる(overflow <= 0)。
    // 以前はタイトル幅を差し引いた見積もりで「…」込み3個まで減っていた退行の防止。
    func testLongTitleTruncatesForManyButtons() throws {
        for count in [5, 6, 7] {
            let (navBar, stack, container) = layoutReadingLikeNavBar(
                title: "とても長い小説のタイトルですあいうえおかきくけこさしすせそ", buttonCount: count, screenWidth: 390)
            let overflow = try XCTUnwrap(NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container))
            XCTAssertLessThanOrEqual(overflow, 0.5, "長いタイトルでも \(count) 個は収まる(タイトルが truncate される)こと。overflow=\(overflow)")
        }
    }

    // window に載っていない container では測定不能(nil)を返し、呼び出し側が再試行できること。
    func testReturnsNilWhenNotInWindow() {
        let stack = UIStackView()
        stack.addArrangedSubview(makeButton())
        let container = UIView()
        container.addSubview(stack)
        let navBar = UINavigationBar()
        let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: container)
        XCTAssertNil(overflow, "window に載っていなければ nil(測定不能)を返すこと")
    }
}

// 青空文庫HTMLのルビ変換で閉じ <rp>）</rp> の「）」が残らないことの回帰テスト。
class RubyTagConvertTest: XCTestCase {
    // 青空文庫形式(rb + 開き/閉じ rp + rt)。閉じ rp の「）」が残っていた不具合の再現。
    func testAozoraRubyClosingRpRemoved() {
        let html = "<ruby><rb>親譲</rb><rp>（</rp><rt>おやゆず</rt><rp>）</rp></ruby>りの"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: html)
        XCTAssertEqual(result, "|親譲(おやゆず)りの", "閉じ <rp>）</rp> の「）」が残らないこと")
    }

    // rb 無し・開き/閉じ rp 付きのルビも「）」が残らないこと。
    func testRubyWithoutRbClosingRpRemoved() {
        let html = "<ruby>無鉄砲<rp>（</rp><rt>むてっぽう</rt><rp>）</rp></ruby>"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: html)
        XCTAssertEqual(result, "|無鉄砲(むてっぽう)", "rb 無しでも閉じ rp が残らないこと")
    }

    // rp を持たない素朴なルビは従来通り変換できること(退行防止)。
    func testSimpleRubyStillWorks() {
        let html = "<ruby>漢字<rt>かんじ</rt></ruby>"
        let result = NiftyUtility.ConvertRubyTagToVerticalBarRubyText(htmlString: html)
        XCTAssertEqual(result, "|漢字(かんじ)", "rp 無しの素朴なルビも変換できること")
    }
}

// 実際のテーマ適用・復帰処理を検証。読み込み/読み上げの副作用のみ除く。
private class ThemeTestSpeechController: SpeechViewController {
    override func loadView() {
        view = UIView()
        let text = UITextView(); view.addSubview(text); textView = text
        let previous = UIButton(); view.addSubview(previous); previousChapterButton = previous
        let next = UIButton(); view.addSubview(next); nextChapterButton = next
        let slider = UISlider(); view.addSubview(slider); chapterSlider = slider
        let label = UILabel(); view.addSubview(label); chapterPositionLabel = label
    }
    override func viewDidLoad() {}
    override func viewWillAppear(_ animated: Bool) {}
    override func viewDidAppear(_ animated: Bool) {}
    override func viewWillDisappear(_ animated: Bool) {}
    override func viewDidDisappear(_ animated: Bool) {}
}
private class ThemeTestWebController: WebSpeechViewController {
    override func loadView() { view = UIView() }
    override func viewDidLoad() {}
    override func viewWillAppear(_ animated: Bool) {}
    override func viewDidAppear(_ animated: Bool) {}
    override func viewWillDisappear(_ animated: Bool) {}
    override func viewDidDisappear(_ animated: Bool) {}
}
class TabBarThemeRegressionTest: XCTestCase {
    func testReaderThemeAndRestoreInLightAndDark() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for reader in [ThemeTestSpeechController(), ThemeTestWebController()] as [UIViewController] {
                reader.loadViewIfNeeded()
                let nav = UINavigationController(rootViewController: reader)
                let tabs = UITabBarController(); tabs.viewControllers = [nav]
                tabs.overrideUserInterfaceStyle = style
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = tabs; window.makeKeyAndVisible()
                defer { window.isHidden = true; window.rootViewController = nil }
                for background in [UIColor.white, .black, UIColor(red: 0.24, green: 0.12, blue: 0.4, alpha: 1)] {
                    if let text = reader as? SpeechViewController {
                        text.applyThemeColor(backgroundColor: background, foregroundColor: .yellow, indicatorStyle: .white, barStyle: .black)
                        let expectedTextView = UITextView(); expectedTextView.backgroundColor = background
                        XCTAssertEqual(text.textView.backgroundColor, expectedTextView.backgroundColor)
                        XCTAssertEqual(text.textView.textColor, .yellow)
                    } else if let web = reader as? WebSpeechViewController {
                        web.applyThemeColor(backgroundColor: background, foregroundColor: .yellow, indicatorStyle: .white, barStyle: .black)
                    }
                    XCTAssertEqual(reader.view.backgroundColor, background)
                    XCTAssertEqual(tabs.tabBar.barTintColor, background)
                    XCTAssertEqual(tabs.tabBar.backgroundColor?.cgColor.alpha, 0)
                    XCTAssertFalse(tabs.tabBar.isHidden)
                    XCTAssertEqual(nav.navigationBar.standardAppearance.backgroundColor, background)
                    XCTAssertEqual(nav.navigationBar.scrollEdgeAppearance?.backgroundColor, background)
                }
                if let text = reader as? SpeechViewController { text.resumeTheme() }
                if let web = reader as? WebSpeechViewController { web.resumeTheme() }
                XCTAssertEqual(reader.view.backgroundColor, .systemBackground)
                XCTAssertEqual(tabs.tabBar.barTintColor, .systemBackground)
                XCTAssertEqual(tabs.tabBar.backgroundColor?.cgColor.alpha, 0)
                XCTAssertFalse(tabs.tabBar.isHidden)
            }
        }
    }
}

private final class BottomControlsTestWebController: WebSpeechViewController {
    override func loadView() {
        view = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        createUIComponents(webView: CustomWKWebView(frame: .zero, configuration: WKWebViewConfiguration()))
    }
    override func viewDidLoad() {}
    override func viewWillAppear(_ animated: Bool) {}
    override func viewDidAppear(_ animated: Bool) {}
    override func viewWillDisappear(_ animated: Bool) {}
    override func viewDidDisappear(_ animated: Bool) {}
    override func viewDidLayoutSubviews() {}
}

final class WebReaderBottomControlsTest: XCTestCase {
    func testFullscreenHidesBottomBarAndReplacementUntilRestored() {
        let reader = BottomControlsTestWebController()
        reader.loadViewIfNeeded()
        let bar = SpeechViewBottomButtonBar()
        reader.view.addSubview(bar)
        reader.bottomButtonBar = bar
        reader.hideTopAndDownComponents(animated: false)
        XCTAssertTrue(bar.isHidden)
        XCTAssertTrue(reader.isReaderInterfaceHidden)
        let replacement = SpeechViewBottomButtonBar()
        reader.view.addSubview(replacement)
        reader.bottomButtonBar = replacement
        XCTAssertTrue(replacement.isHidden, "再生成したバーも全画面状態を維持する")
        reader.displayTopAndDownComponents(animated: false)
        XCTAssertFalse(replacement.isHidden)
        XCTAssertFalse(reader.isReaderInterfaceHidden)
    }

    func testEnabledVoicevoxButtonIsCreatedForBothLocationsAndOffIsRespected() {
        let reader = BottomControlsTestWebController()
        for bottom in [true, false] {
            let enabled = reader.createSpeechViewButtonArray(novelID: "test", novelType: .UserCreated, aliveButtonSettings: [SpeechViewButtonSetting(type: .voicevoxCacheGeneration, isOn: true)], buttonSize: 28, isForBottomBar: bottom)
            XCTAssertEqual(enabled.count, 1)
            XCTAssertNotNil(enabled.first?.image(for: .normal))
            XCTAssertEqual(enabled.first?.actions(forTarget: reader, forControlEvent: .touchUpInside), ["voicevoxCacheGenerationButtonClicked:"])
            let disabled = reader.createSpeechViewButtonArray(novelID: "test", novelType: .UserCreated, aliveButtonSettings: [SpeechViewButtonSetting(type: .voicevoxCacheGeneration, isOn: false)], buttonSize: 28, isForBottomBar: bottom)
            XCTAssertTrue(disabled.isEmpty)
        }
    }
}

private final class RequiredSettingsTestController: SettingsViewController {
    var testRealm: Realm!
    override func loadView() { view = UIView() }
    override func viewDidLoad() {}
    override func requiredSettingsStatusForUI() -> NovelSpeakerUtility.RequiredSettingsStatus {
        NovelSpeakerUtility.requiredSettingsStatus(realm: testRealm)
    }
}

final class RequiredSettingsRepairTest: XCTestCase {
    private func makeRealm() throws -> Realm {
        try Realm(configuration: Realm.Configuration(inMemoryIdentifier: UUID().uuidString))
    }

    private func addState(_ realm: Realm, display: String = "missing-display", speaker: String = "voice") throws -> RealmGlobalState {
        let state = RealmGlobalState()
        state.defaultDisplaySettingID = display
        state.defaultSpeakerID = speaker
        try realm.write { realm.add(state) }
        return state
    }

    private func addSpeaker(_ realm: Realm, name: String = "voice") throws -> RealmSpeakerSetting {
        let setting = RealmSpeakerSetting()
        setting.name = name
        setting.type = "VOICEVOX"
        setting.voiceIdentifier = "47"
        setting.rate = 0.73
        try realm.write { realm.add(setting) }
        return setting
    }

    private func addDisplay(_ realm: Realm, name: String) throws -> RealmDisplaySetting {
        let setting = RealmDisplaySetting()
        setting.name = name
        setting.textSizeValue = 79
        setting.fontID = "preserve-font"
        setting.lineSpacing = 12
        setting.viewType = .webViewVertical
        try realm.write { realm.add(setting) }
        return setting
    }

    func testObservedAirLocalStateIsRepairedWithoutOptionalSeeding() throws {
        let realm = try makeRealm()
        let state = try addState(realm)
        let speaker = try addSpeaker(realm)
        // Airの観測: global有効、非空ID、display active/deleted共に0、旧health=true。
        XCTAssertFalse(state.isDeleted)
        XCTAssertFalse(state.defaultDisplaySettingID.isEmpty)
        XCTAssertEqual(realm.objects(RealmDisplaySetting.self).count, 0)
        XCTAssertTrue(NovelSpeakerUtility.CheckDefaultSettingsAlive(realm: realm))
        XCTAssertNil(state.defaultDisplaySettingWith(realm: realm))
        let result = try NovelSpeakerUtility.repairRequiredSettingsAtLaunch(realm: realm, isCloud: false)
        XCTAssertEqual(result.createdRecords, 1)
        XCTAssertEqual(result.updatedReferences, 1)
        XCTAssertEqual(NovelSpeakerUtility.requiredSettingsStatus(realm: realm), .ready)
        XCTAssertEqual(realm.objects(RealmDisplaySetting.self).count, 1)
        XCTAssertEqual(speaker.type, "VOICEVOX")
        XCTAssertEqual(speaker.voiceIdentifier, "47")
        XCTAssertEqual(speaker.rate, 0.73)
        XCTAssertTrue(state.webImportBookmarkArray.isEmpty)
        XCTAssertTrue(state.autoSplitStringList.isEmpty)
        XCTAssertTrue(realm.objects(RealmSpeechSectionConfig.self).isEmpty)
        XCTAssertTrue(realm.objects(RealmSpeechWaitConfig.self).isEmpty)
        XCTAssertTrue(realm.objects(RealmSpeechModSetting.self).isEmpty)
        XCTAssertFalse(try NovelSpeakerUtility.repairRequiredSettings(realm: realm).changed)
    }

    func testValidReferencesAndValuesStayUnchangedEvenWithEarlierNames() throws {
        let realm = try makeRealm()
        let state = try addState(realm, display: "z-display", speaker: "z-voice")
        let display = try addDisplay(realm, name: "z-display")
        let speaker = try addSpeaker(realm, name: "z-voice")
        _ = try addDisplay(realm, name: "a-display")
        _ = try addSpeaker(realm, name: "a-voice")
        let date = display.createdDate
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertFalse(result.changed)
        XCTAssertEqual(state.defaultDisplaySettingID, "z-display")
        XCTAssertEqual(state.defaultSpeakerID, "z-voice")
        XCTAssertEqual(display.textSizeValue, 79)
        XCTAssertEqual(display.fontID, "preserve-font")
        XCTAssertEqual(display.lineSpacing, 12)
        XCTAssertEqual(display.viewType, .webViewVertical)
        XCTAssertEqual(display.createdDate, date)
        XCTAssertEqual(speaker.type, "VOICEVOX")
        XCTAssertEqual(speaker.voiceIdentifier, "47")
        XCTAssertEqual(realm.objects(RealmDisplaySetting.self).count, 2)
        XCTAssertEqual(realm.objects(RealmSpeakerSetting.self).count, 2)
    }

    func testMissingReferencesChooseNameAscendingWithoutIncreasingCount() throws {
        let realm = try makeRealm()
        let state = try addState(realm, speaker: "missing-voice")
        _ = try addDisplay(realm, name: "z-display")
        let chosenDisplay = try addDisplay(realm, name: "a-display")
        _ = try addSpeaker(realm, name: "z-voice")
        let chosenSpeaker = try addSpeaker(realm, name: "a-voice")
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertEqual(result.createdRecords, 0)
        XCTAssertEqual(result.updatedReferences, 2)
        XCTAssertEqual(state.defaultDisplaySettingID, chosenDisplay.name)
        XCTAssertEqual(state.defaultSpeakerID, chosenSpeaker.name)
        XCTAssertEqual(chosenDisplay.textSizeValue, 79)
        XCTAssertEqual(chosenSpeaker.type, "VOICEVOX")
        XCTAssertEqual(realm.objects(RealmDisplaySetting.self).count, 2)
        XCTAssertEqual(realm.objects(RealmSpeakerSetting.self).count, 2)
        XCTAssertFalse(try NovelSpeakerUtility.repairRequiredSettings(realm: realm).changed)
    }

    func testMissingGlobalAdoptsOnlyExistingSettingsWithoutReplacingThem() throws {
        let realm = try makeRealm()
        let display = try addDisplay(realm, name: "only-display")
        let speaker = try addSpeaker(realm, name: "only-voice")
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        let state = try XCTUnwrap(RealmGlobalState.GetInstanceWith(realm: realm))
        XCTAssertEqual(result.createdRecords, 1)
        XCTAssertEqual(state.defaultDisplaySettingID, display.name)
        XCTAssertEqual(state.defaultSpeakerID, speaker.name)
        XCTAssertEqual(display.fontID, "preserve-font")
        XCTAssertEqual(speaker.voiceIdentifier, "47")
        XCTAssertEqual(realm.objects(RealmDisplaySetting.self).count, 1)
        XCTAssertEqual(realm.objects(RealmSpeakerSetting.self).count, 1)
    }

    func testZeroSettingsCreatesOneEachAndSetsReferences() throws {
        let realm = try makeRealm()
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertEqual(result.createdRecords, 3)
        XCTAssertEqual(result.updatedReferences, 2)
        XCTAssertEqual(realm.objects(RealmGlobalState.self).count, 1)
        XCTAssertEqual(realm.objects(RealmDisplaySetting.self).count, 1)
        XCTAssertEqual(realm.objects(RealmSpeakerSetting.self).count, 1)
        XCTAssertEqual(NovelSpeakerUtility.requiredSettingsStatus(realm: realm), .ready)
        XCTAssertFalse(try NovelSpeakerUtility.repairRequiredSettings(realm: realm).changed)
    }

    func testEmptyReferencesSelectExistingRatherThanAddStandards() throws {
        let realm = try makeRealm()
        let state = try addState(realm, display: "", speaker: "")
        _ = try addDisplay(realm, name: "user-display")
        _ = try addSpeaker(realm, name: "user-voice")
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertEqual(result.createdRecords, 0)
        XCTAssertEqual(state.defaultDisplaySettingID, "user-display")
        XCTAssertEqual(state.defaultSpeakerID, "user-voice")
    }

    func testDeletedReferencedRecordIsNotRevivedAndActiveOneIsAdopted() throws {
        let realm = try makeRealm()
        let state = try addState(realm, display: "deleted")
        let deleted = try addDisplay(realm, name: "deleted")
        try realm.write { deleted.isDeleted = true }
        _ = try addDisplay(realm, name: "active")
        _ = try addSpeaker(realm)
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertEqual(result.createdRecords, 0)
        XCTAssertEqual(state.defaultDisplaySettingID, "active")
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertEqual(deleted.textSizeValue, 79)
    }

    func testDeletedGlobalRequiresDecisionWithoutAnyChanges() throws {
        let realm = try makeRealm()
        let state = try addState(realm)
        try realm.write { state.isDeleted = true }
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertEqual(result.decisionKey, "RequiredSettingsRepair_DeletedGlobal")
        XCTAssertFalse(result.changed)
        XCTAssertTrue(state.isDeleted)
        XCTAssertTrue(realm.objects(RealmDisplaySetting.self).isEmpty)
        XCTAssertTrue(realm.objects(RealmSpeakerSetting.self).isEmpty)
    }

    func testDeletedStandardCollisionDoesNotOverwriteOrPartiallyCreate() throws {
        let realm = try makeRealm()
        let base = NSLocalizedString("CoreDataToRealmTool_DefaultSpeaker", comment: "標準")
        let deleted = try addSpeaker(realm, name: base)
        try realm.write { deleted.isDeleted = true }
        let result = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        XCTAssertEqual(result.decisionKey, "RequiredSettingsRepair_DeletedStandard")
        XCTAssertFalse(result.changed)
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertEqual(deleted.voiceIdentifier, "47")
        XCTAssertTrue(realm.objects(RealmGlobalState.self).isEmpty)
        XCTAssertTrue(realm.objects(RealmDisplaySetting.self).isEmpty)
    }

    func testCloudLaunchDoesNotRepairMissingData() throws {
        let realm = try makeRealm()
        let state = try addState(realm)
        _ = try addSpeaker(realm)
        XCTAssertFalse(try NovelSpeakerUtility.repairRequiredSettingsAtLaunch(realm: realm, isCloud: true).changed)
        XCTAssertEqual(state.defaultDisplaySettingID, "missing-display")
        XCTAssertTrue(realm.objects(RealmDisplaySetting.self).isEmpty)
    }

    func testRepairRowIsAvailableWithoutGlobalAndUpdatesDisabledState() throws {
        let realm = try makeRealm()
        let controller = RequiredSettingsTestController()
        controller.testRealm = realm
        let row = controller.makeRequiredSettingsRepairRow()
        controller.form +++ Section() <<< row
        row.evaluateDisabled()
        XCTAssertFalse(row.isDisabled)
        _ = try NovelSpeakerUtility.repairRequiredSettings(realm: realm)
        controller.updateRequiredSettingsRepairRow()
        XCTAssertTrue(row.isDisabled)
        XCTAssertEqual(row.value, NSLocalizedString("RequiredSettingsRepair_NotNeeded", comment: ""))
        XCTAssertEqual(row.cell.textLabel?.text, NSLocalizedString("RequiredSettingsRepair_Title", comment: ""))
        XCTAssertEqual(row.cell.detailTextLabel?.text, NSLocalizedString("RequiredSettingsRepair_NotNeeded", comment: ""))
        XCTAssertTrue(row.cell.textLabel?.adjustsFontForContentSizeCategory == true)
        XCTAssertTrue(row.cell.detailTextLabel?.adjustsFontForContentSizeCategory == true)
        XCTAssertEqual(row.cell.detailTextLabel?.numberOfLines, 0)
        XCTAssertEqual(row.cell.textLabel?.textColor, UIColor.gray)
        let display = try XCTUnwrap(RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm))
        try realm.write { realm.delete(display) }
        controller.updateRequiredSettingsRepairRow()
        XCTAssertFalse(row.isDisabled)
        XCTAssertNil(row.value)
        XCTAssertNil(row.cell.detailTextLabel?.text)
    }
}
