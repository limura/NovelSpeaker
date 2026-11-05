//
//  RealmSpeakerSettingDefaultValueTest.swift
//  NovelSpeakerTests
//
//  Realm のモデルの「既定値」に重い処理を書いてはいけない、という事のテスト。
//
//  Realm は保存済みのオブジェクトを取り出す時にも Swift の既定値初期化子を走らせるので、
//  既定値に重い処理を書くと **1件取り出すごとに** その処理が走る。
//
//  実機(iPhone)の計測では、話者設定がたった4件しか無いのに
//    realm.objects(RealmSpeakerSetting.self).filter("isDeleted = false AND name = %@", ...).first
//  1回に118msかかっていた。voiceIdentifier の既定値 GuessBestVoiceIdentifier() が
//  AVSpeechSynthesisVoice.speechVoices() を呼んでおり、これが実機で100ms級だったため。
//  読み上げ設定の組み立てが1作品0.5秒かかっていた主因がこれだった。
//  (シミュレータは入っている音声が少なく速いので、母艦での計測では見えなかった)
//

import XCTest
import AVFoundation
import RealmSwift
import SSZipArchive
@testable import NovelSpeaker

class RealmSpeakerSettingDefaultValueTest: XCTestCase {

    // 既定の音声の判定は、何度呼んでも1回ぶんの手間で済む事。
    func testGuessBestVoiceIdentifierIsCached() {
        // 1回目で覚えるので、まず1回呼んでおく。
        let first = RealmSpeakerSetting.GuessBestVoiceIdentifier()

        let start = Date()
        for _ in 0..<1000 {
            XCTAssertEqual(RealmSpeakerSetting.GuessBestVoiceIdentifier(), first)
        }
        let elapsed = Date().timeIntervalSince(start)
        NSLog("NovelSpeaker.Benchmark: GuessBestVoiceIdentifier 1000回 = %.1f ms", elapsed * 1000)
        // 覚えていなければ speechVoices() が1000回走る事になる。
        // 実機では1回100ms級なので100秒かかる計算になり、桁で落ちる。
        XCTAssertLessThan(elapsed, 1.0, "既定の音声の判定が毎回やり直されている(オブジェクトを作る度に走る)")
    }

    // オブジェクトを沢山作っても、既定値の計算で待たされない事。
    func testCreatingManySpeakerSettingsIsFast() {
        _ = RealmSpeakerSetting.GuessBestVoiceIdentifier()
        let start = Date()
        for _ in 0..<1000 {
            _ = RealmSpeakerSetting()
        }
        let elapsed = Date().timeIntervalSince(start)
        NSLog("NovelSpeaker.Benchmark: RealmSpeakerSetting を1000個作る = %.1f ms", elapsed * 1000)
        XCTAssertLessThan(elapsed, 1.0, "話者設定を作るのが遅い(既定値に重い処理が入っている)")
    }

    // 覚えた値を捨てられる事。
    //
    // ことせかい を起動したまま「設定」アプリから音声をダウンロードされると、
    // 端末に入っている音声の一覧は変わる。しかもアプリ内で
    // 「話者が少ないなら設定アプリから追加してください」と案内しているので、
    // 追加した人にこそ反映されない、では困る。
    // 前面に戻ってきた時に捨てる作りにしてあるので、その口が効く事を確かめる。
    func testCachedBestVoiceIdentifierCanBeCleared() {
        let first = RealmSpeakerSetting.GuessBestVoiceIdentifier()
        RealmSpeakerSetting.ClearCachedBestVoiceIdentifier()
        // 捨てた後は計算し直す(音声の増減が無ければ同じ値になる)。
        XCTAssertEqual(RealmSpeakerSetting.GuessBestVoiceIdentifier(), first)
    }

    // 参考: 端末に入っている音声の一覧の取得そのものが、どれだけ掛かるか。
    // ここが遅い端末ほど、覚えておく効果が大きい。
    func testSpeechVoicesCostForReference() {
        let start = Date()
        _ = AVSpeechSynthesisVoice.speechVoices()
        NSLog("NovelSpeaker.Benchmark: AVSpeechSynthesisVoice.speechVoices() = %.1f ms",
              Date().timeIntervalSince(start) * 1000)
    }
}

// Release backport regressions use an isolated Realm, never the user's database.
final class ReleaseBackportTest: XCTestCase {
    private func withRealm(_ body: (Realm) throws -> Void) throws {
        let configuration = Realm.Configuration(inMemoryIdentifier: UUID().uuidString)
        let realm = try Realm(configuration: configuration)
        try realm.write { realm.add(RealmGlobalState()) }
        try RealmUtil.withTemporaryRealmForTesting(configuration: configuration) { try body(realm) }
    }
    private func assertColor(_ actual: UIColor?, _ expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else { return XCTFail("Missing color", file: file, line: line) }
        func rgba(_ color: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a); return [r,g,b,a]
        }
        for (a,e) in zip(rgba(actual),rgba(expected)) { XCTAssertEqual(a,e,accuracy:0.00001,file:file,line:line) }
    }
    func testCanonicalBackupColorsAndMenuRestoreThroughBothVersions() throws {
        try withRealm { realm in
            let state = try XCTUnwrap(RealmGlobalState.GetInstanceWith(realm: realm))
            let colors: [String:Any] = ["foreground":["red":0.1,"green":0.2,"blue":0.3,"alpha":0.8],"background":["red":0.7,"green":0.6,"blue":0.5,"alpha":0.9]]
            for version21 in [false,true] {
                for flag in [false,true] {
                    try realm.write { state.foregroundColor = .magenta; state.backgroundColor = .green; state.isMenuItemIsAddNovelSpeakerItemsOnly = !flag }
                    let data: NSDictionary = ["misc_settings":["readingDisplayColor":colors,"isMenuItemIsAddSpeechModSettingOnly":flag]]
                    if version21 { XCTAssertTrue(NovelSpeakerUtility.ProcessNovelSpeakerBackupJSONData_V_2_1_0(toplevelDictionary:data,progressUpdate:{_ in},extractedDirectory:nil)) }
                    else { XCTAssertTrue(NovelSpeakerUtility.ProcessNovelSpeakerBackupJSONData_V_2_0_0(toplevelDictionary:data,progressUpdate:{_ in},extractedDirectory:nil)) }
                    realm.refresh()
                    assertColor(state.foregroundColor,UIColor(red:0.1,green:0.2,blue:0.3,alpha:0.8))
                    assertColor(state.backgroundColor,UIColor(red:0.7,green:0.6,blue:0.5,alpha:0.9))
                    XCTAssertEqual(state.isMenuItemIsAddNovelSpeakerItemsOnly,flag)
                }
            }
        }
    }
    @MainActor private func drain() {
        let done=expectation(description:"main queue drained")
        DispatchQueue.main.async { DispatchQueue.main.async { done.fulfill() } }
        wait(for:[done],timeout:5)
    }
    private final class NormalReader: SpeechViewController {
        override func viewDidLoad() { view.backgroundColor = .white }
        override func viewWillAppear(_ animated: Bool) {}
        override func viewDidAppear(_ animated: Bool) {}
        override func viewWillDisappear(_ animated: Bool) {}
        override func viewDidLayoutSubviews() {}
    }
    private final class WebReader: WebSpeechViewController {
        override func viewDidLoad() { view.backgroundColor = .white }
        override func viewWillAppear(_ animated: Bool) {}
        override func viewDidAppear(_ animated: Bool) {}
        override func viewWillDisappear(_ animated: Bool) {}
        override func viewDidLayoutSubviews() {}
    }
    @MainActor private func mounted(_ controller: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window=UIWindow(windowScene:scene)
        window.rootViewController=UINavigationController(rootViewController:controller)
        window.makeKeyAndVisible(); window.layoutIfNeeded(); drain()
        return window
    }
    @MainActor func testNormalUnchangedToolbarKeepsMountedReferences() throws {
        try withRealm { _ in
            let reader=NormalReader(); let window=try mounted(reader)
            window.rootViewController=UINavigationController(rootViewController:reader); window.layoutIfNeeded();drain()
            defer { window.isHidden=true;window.rootViewController=nil }
            let settings=[SpeechViewButtonSetting(type:.skipBackward,isOn:true),SpeechViewButtonSetting(type:.skipForward,isOn:true),SpeechViewButtonSetting(type:.speechStop,isOn:true)]
            reader.assignUpperButtons(novelID:"backport",novelType:.URL,aliveButtonSettings:settings);drain()
            let backward=try XCTUnwrap(reader.skipBackwardButtonItem), forward=try XCTUnwrap(reader.skipForwardButtonItem)
            let root=try XCTUnwrap(NovelSpeakerUtility.UpperButtonBarLayout.rightBarCustomView(for:reader.navigationItem))
            let actualActions = root.subviews.flatMap { $0.subviews }.compactMap { $0 as? UIButton }.flatMap { $0.menu?.children.compactMap { $0 as? UIAction } ?? [] }
            XCTAssertTrue(actualActions.contains { $0.identifier.rawValue == "ReaderSkipBackward" })
            XCTAssertTrue(actualActions.contains { $0.identifier.rawValue == "ReaderSkipForward" })
            XCTAssertTrue(actualActions.contains { $0.identifier.rawValue == "reader.playback" })
            reader.currentUpperButtonBarLayoutSignature=nil
            reader.isUpperRightButtonsChanged=true
            reader.assignUpperButtons(novelID:"backport",novelType:.URL,aliveButtonSettings:settings);drain()
            XCTAssertTrue(root === NovelSpeakerUtility.UpperButtonBarLayout.rightBarCustomView(for:reader.navigationItem))
            XCTAssertTrue(backward === reader.skipBackwardButtonItem,"state updates must target mounted buttons")
            XCTAssertTrue(forward === reader.skipForwardButtonItem)
        }
    }
    @MainActor func testWebUnchangedToolbarKeepsMountedReferences() throws {
        try withRealm { _ in
            let reader=WebReader(); let window=try mounted(reader)
            window.rootViewController=UINavigationController(rootViewController:reader);window.layoutIfNeeded();drain()
            defer { window.isHidden=true;window.rootViewController=nil }
            let settings=[SpeechViewButtonSetting(type:.skipBackward,isOn:true),SpeechViewButtonSetting(type:.skipForward,isOn:true),SpeechViewButtonSetting(type:.speechStop,isOn:true)]
            reader.assignUpperButtons(novelID:"backport",novelType:.URL,aliveButtonSettings:settings);drain()
            let backward=try XCTUnwrap(reader.skipBackwardButtonItem), forward=try XCTUnwrap(reader.skipForwardButtonItem)
            let root=try XCTUnwrap(NovelSpeakerUtility.UpperButtonBarLayout.rightBarCustomView(for:reader.navigationItem))
            let actualActions = root.subviews.flatMap { $0.subviews }.compactMap { $0 as? UIButton }.flatMap { $0.menu?.children.compactMap { $0 as? UIAction } ?? [] }
            XCTAssertTrue(actualActions.contains { $0.identifier.rawValue == "ReaderSkipBackward" })
            XCTAssertTrue(actualActions.contains { $0.identifier.rawValue == "ReaderSkipForward" })
            XCTAssertTrue(actualActions.contains { $0.identifier.rawValue == "reader.playback" })
            reader.currentUpperButtonBarLayoutSignature=nil
            reader.isUpperRightButtonsChanged=true
            reader.assignUpperButtons(novelID:"backport",novelType:.URL,aliveButtonSettings:settings);drain()
            XCTAssertTrue(root === NovelSpeakerUtility.UpperButtonBarLayout.rightBarCustomView(for:reader.navigationItem))
            XCTAssertTrue(backward === reader.skipBackwardButtonItem)
            XCTAssertTrue(forward === reader.skipForwardButtonItem)
        }
    }
    @MainActor func testNormalStopUpdatesBottomButtons() throws {
        try withRealm { _ in
            let reader=NormalReader(), backward=UIButton(), forward=UIButton()
            reader.bottomSkipBackwardButton=backward;reader.bottomSkipForwardButton=forward
            reader.storySpeakerStopSpeechEvent(storyID:"");drain()
            XCTAssertFalse(backward.isEnabled);XCTAssertFalse(forward.isEnabled)
        }
    }
    @MainActor func testWebStopUpdatesBottomButtons() throws {
        try withRealm { _ in
            let reader=WebReader(), backward=UIButton(), forward=UIButton()
            reader.bottomSkipBackwardButton=backward;reader.bottomSkipForwardButton=forward
            reader.storySpeakerStopSpeechEvent(storyID:"");drain()
            XCTAssertFalse(backward.isEnabled);XCTAssertFalse(forward.isEnabled)
        }
    }
}

extension ReleaseBackportTest {
    func testBackupAliasesPrecedenceInvalidAndAbsentValues() throws {
        try withRealm { realm in
            let state=try XCTUnwrap(RealmGlobalState.GetInstanceWith(realm:realm))
            let red:[String:Any] = ["red":1.0,"green":0.0,"blue":0.0,"alpha":0.75]
            let blue:[String:Any] = ["red":0.0,"green":0.0,"blue":1.0,"alpha":0.5]
            func apply(_ data:[String:Any]) { NovelSpeakerUtility.RestoreGlobalState_V_2_0_0(dic:data as NSDictionary,progressUpdate:{_ in});realm.refresh() }
            for flag in [false,true] {
                apply(["readingDisplayColor":["foregroundColor":red,"backgroundColor":blue],"isMenuItemIsAddNovelSpeakerItemsOnly":flag])
                assertColor(state.foregroundColor,UIColor(red:1,green:0,blue:0,alpha:0.75));assertColor(state.backgroundColor,UIColor(red:0,green:0,blue:1,alpha:0.5));XCTAssertEqual(state.isMenuItemIsAddNovelSpeakerItemsOnly,flag)
            }
            apply(["readingDisplayColor":["foreground":blue,"foregroundColor":red,"background":red,"backgroundColor":blue],"isMenuItemIsAddSpeechModSettingOnly":false,"isMenuItemIsAddNovelSpeakerItemsOnly":true])
            for invalid in [NSNull(),"bad",["red":true,"green":0,"blue":0,"alpha":1],["red":2.0,"green":0,"blue":0,"alpha":1],["red":Double.nan,"green":0,"blue":0,"alpha":1],["red":1,"green":0,"blue":0]] as [Any] {
                apply(["readingDisplayColor":["foreground":invalid,"foregroundColor":red,"background":invalid,"backgroundColor":blue],"isMenuItemIsAddSpeechModSettingOnly":"true","isMenuItemIsAddNovelSpeakerItemsOnly":true])
                assertColor(state.foregroundColor,UIColor(red:0,green:0,blue:1,alpha:0.5));assertColor(state.backgroundColor,UIColor(red:1,green:0,blue:0,alpha:0.75));XCTAssertFalse(state.isMenuItemIsAddNovelSpeakerItemsOnly)
            }
            for invalid in [NSNull(),2,0.5,[true]] as [Any] { apply(["isMenuItemIsAddSpeechModSettingOnly":invalid]);XCTAssertFalse(state.isMenuItemIsAddNovelSpeakerItemsOnly) }
            apply([:]);assertColor(state.foregroundColor,UIColor(red:0,green:0,blue:1,alpha:0.5));XCTAssertFalse(state.isMenuItemIsAddNovelSpeakerItemsOnly)
        }
    }
    func testProductionBackupZIPRoundTripRestoresExportedSpelling() throws {
        try withRealm { realm in
            _ = try NovelSpeakerUtility.repairRequiredSettings(realm:realm)
            let state=try XCTUnwrap(RealmGlobalState.GetInstanceWith(realm:realm))
            try realm.write { state.foregroundColor = .red;state.backgroundColor = .blue;state.isMenuItemIsAddNovelSpeakerItemsOnly=true }
            let zip=try XCTUnwrap(NovelSpeakerUtility.CreateBackupData(forNovelIDArray:[],forStorySaveNovelIDArray:[],progress:nil))
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:zip);try? FileManager.default.removeItem(at:directory) }
            XCTAssertTrue(SSZipArchive.unzipFile(atPath:zip.path,toDestination:directory.path))
            let json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("backup_data.json"))) as? [String:Any])
            let misc=try XCTUnwrap(json["misc_settings"] as? [String:Any]), colors=try XCTUnwrap(misc["readingDisplayColor"] as? [String:Any])
            XCTAssertNotNil(colors["foreground"]);XCTAssertNotNil(colors["background"]);XCTAssertNil(colors["foregroundColor"])
            XCTAssertNotNil(misc["isMenuItemIsAddSpeechModSettingOnly"]);XCTAssertNil(misc["isMenuItemIsAddNovelSpeakerItemsOnly"])
            try realm.write { state.foregroundColor = .green;state.backgroundColor = .magenta;state.isMenuItemIsAddNovelSpeakerItemsOnly=false }
            XCTAssertTrue(NovelSpeakerUtility.ProcessNovelSpeakerBackupJSONData_V_2_1_0(toplevelDictionary:["misc_settings":["readingDisplayColor":colors,"isMenuItemIsAddSpeechModSettingOnly":misc["isMenuItemIsAddSpeechModSettingOnly"]!]] as NSDictionary,progressUpdate:{_ in},extractedDirectory:directory))
            realm.refresh();assertColor(state.foregroundColor,.red);assertColor(state.backgroundColor,.blue);XCTAssertTrue(state.isMenuItemIsAddNovelSpeakerItemsOnly)
        }
    }
    @MainActor func testPlaybackStateUpdatesVisibleAndOverflowControlsInBothReaders() throws {
        try withRealm { _ in
            for web in [false,true] {
                let normal=NormalReader(), html=WebReader()
                let reader:UIViewController = web ? html : normal
                let window=try mounted(reader)
                defer { window.isHidden=true;window.rootViewController=nil }
                let backward=UIButton(),forward=UIButton(),play=UIButton(),bottomBack=UIButton(),bottomForward=UIButton(),bottomPlay=UIButton()
                backward.accessibilityIdentifier="ReaderSkipBackward";forward.accessibilityIdentifier="ReaderSkipForward"
                bottomBack.accessibilityIdentifier="ReaderSkipBackward";bottomForward.accessibilityIdentifier="ReaderSkipForward"
                bottomBack.accessibilityLabel="Back";bottomForward.accessibilityLabel="Forward"
                let more=UIButton();more.menu=UIMenu(children:[UIAction(title:"Back",identifier:.init("ReaderSkipBackward"),attributes:.disabled){_ in},UIAction(title:"Forward",identifier:.init("ReaderSkipForward"),attributes:.disabled){_ in},UIAction(title:"Play",identifier:.init("reader.playback")){_ in}])
                let root=UIView();root.addSubview(more);reader.navigationItem.rightBarButtonItem=UIBarButtonItem(customView:root)
                let parent=UIView(frame:CGRect(x:0,y:0,width:160,height:60)),bottom=SpeechViewBottomButtonBar(frame:CGRect(x:0,y:0,width:160,height:60))
                reader.view.addSubview(parent);parent.addSubview(bottom);bottom.translatesAutoresizingMaskIntoConstraints=true;reader.view.layoutIfNeeded();parent.layoutIfNeeded();bottom.setButtons([bottomBack,bottomForward]+(0..<8).map {_ in UIButton()}+[bottomPlay])
                if web { html.startStopButton=play;html.skipBackwardButtonItem=backward;html.skipForwardButtonItem=forward;html.bottomStartStopButton=bottomPlay;html.bottomSkipBackwardButton=bottomBack;html.bottomSkipForwardButton=bottomForward;html.bottomButtonBar=bottom }
                else { normal.startStopButton=play;normal.skipBackwardButtonItem=backward;normal.skipForwardButtonItem=forward;normal.bottomStartStopButton=bottomPlay;normal.bottomSkipBackwardButton=bottomBack;normal.bottomSkipForwardButton=bottomForward;normal.bottomButtonBar=bottom }
                for playing in [true,false,true] {
                    if web { html.applyReaderPlaybackControls(playing:playing) } else { normal.applyReaderPlaybackControls(playing:playing) }
                    for button in [backward,forward,bottomBack,bottomForward] { XCTAssertEqual(button.isEnabled,playing) }
                    let actions=try XCTUnwrap(more.menu?.children.compactMap {$0 as? UIAction})
                    XCTAssertEqual(actions[0].attributes.contains(.disabled),!playing);XCTAssertEqual(actions[1].attributes.contains(.disabled),!playing)
                    XCTAssertEqual(actions[2].title,NSLocalizedString(playing ? "SpeechViewController_Stop":"SpeechViewController_Speak",comment:""))
                    let lower=try XCTUnwrap(bottom.subviews.flatMap {$0.subviews}.compactMap {$0 as? UIButton}.first {$0.menu != nil})
                    let lowerActions=try XCTUnwrap(lower.menu?.children.compactMap {$0 as? UIAction})
                    XCTAssertEqual(lowerActions.first {$0.title == "Back"}?.attributes.contains(.disabled),!playing)
                    XCTAssertEqual(lowerActions.first {$0.title == "Forward"}?.attributes.contains(.disabled),!playing)
                }
            }
        }
    }
}
