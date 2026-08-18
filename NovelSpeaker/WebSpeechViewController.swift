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
import IceCream
import Eureka

/*
 TODO:
 - 別ページに移動するための手段が目次等しかない
   - 末尾で引っ張って次のページに移動できたら良いね
 - 読む部分を全画面表示にする
   - 表示に関する設定項目をまとめた物がダイアログ的に表示できると良いかもしれん
 - ダークモード・ライトモードの切り替えに追従できてないかも？(traitCollectionDidChange 辺りを確認しよう)
 - 「このページ内で検索」の機能が未実装
 */

class WebSpeechViewController: UIViewController, StorySpeakerDeletgate, RealmObserverResetDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
    var targetStoryID:String? = nil
    var isNeedResumeSpeech:Bool = false
    var isNeedUpdateReadDate:Bool = true
    var textWebView:CustomWKWebView? = nil
    let webSpeechTool = WebSpeechViewTool()
    // 「全て選択」後に標準の編集メニュー(コピー等)を出すための UIEditMenuInteraction(iOS16+)。
    // availability で型を書けないので AnyObject で保持しておく。
    private var selectionEditMenuInteraction: AnyObject? = nil
    var toggleInterfaceButton:UIButton? = nil
    
    var isNeedCollectDisplayLocation = false
    var webViewDisplayWholeText:String? = nil
    var speakerDisplayWholeText:String? = nil

    var globalStateObserverToken:NotificationToken? = nil
    var displaySettingObserverToken:NotificationToken? = nil
    var novelObserverToken:NotificationToken? = nil
    var novelObserverNovelID:String = ""
    var readingChapterStoryUpdateDate:Date = Date()
    var storyObserverToken:NotificationToken? = nil
    var storyObserverBulkStoryID:String = ""

    var currentReadStoryIDChangeAlertFloatingButton:FloatingButton? = nil

    var scrollPullAndFireHandler:ScrollPullAndFireHandler? = nil

    // MARK: 発話位置への自動スクロールの一時停止(通常版 SpeechViewController と同じ考え方)
    // WebView版はハイライト(canvas)と selection が別物なので、
    // 一時停止中も「ハイライトは動かす、スクロールと selection の張り替えはしない」にする。
    var isScrollFollowSuspended:Bool = false {
        didSet {
            self.textWebView?.isScrollFollowSuspended = self.isScrollFollowSuspended
            self.webSpeechTool.setKeepUserSelection(self.isScrollFollowSuspended)
        }
    }
    var scrollFollowSuspendTimer:Timer? = nil
    var scrollFollowPendingLocation:Int? = nil
    var speakFromHereLongPressRecognizer:UILongPressGestureRecognizer? = nil

    // 画面下部のボタン群(右上のボタン群とは独立した設定。既定では何も表示しない)
    var bottomButtonBar:SpeechViewBottomButtonBar? = nil
    var bottomStartStopButton:UIButton? = nil
    var bottomSkipBackwardButton:UIButton? = nil
    var bottomSkipForwardButton:UIButton? = nil
    // 直前に画面下部のボタン群を作った時の状態。
    // viewDidLayoutSubviews から呼ばれる事があるので、毎回作り直すと
    // 「作り直す→レイアウトが走る→また呼ばれる」で無限に回ってしまう。同じ内容なら何もしない。
    var currentBottomButtonSignature:String? = nil
    
    let previousChapterButton = UIButton()
    let nextChapterButton = UIButton()
    let chapterSlider = UISlider()
    let chapterPositionLabel = UILabel()
    var chapterPositionLabelWidthConstraint:NSLayoutConstraint? = nil
    
    var previousChapterBottomConstraint:NSLayoutConstraint? = nil
    var previousChapterTopConstraint:NSLayoutConstraint? = nil
    
    var lastChapterNumber:Int = -1
    
    var currentViewTypeCache:RealmDisplaySetting.ViewType? = nil

    @objc static weak var instance:WebSpeechViewController? = nil
    
    var searchView:SearchFloatingView? = nil
    var searchTextCache = ""

    let myScriptNamespace = "NovelSpeaker_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    
    var isUpperRightButtonsChanged:Bool = true
    // 右上ボタン群を「実レイアウト後に実測してはみ出したら『…』へ追い出す」ための状態
    // (読書画面 SpeechViewController と同一の仕組み。詳細は NovelSpeakerUtility.UpperButtonBarLayout 参照)。
    weak var upperButtonContainerView: UIView? = nil
    weak var upperButtonStackView: UIStackView? = nil
    var upperButtonFittedSlotLimit: Int? = nil
    var upperButtonFittedSlotLimitWidth: CGFloat = -1
    // trim のデバウンス用: 直前の実測結果(読書画面 SpeechViewController と同じ)。
    var upperButtonTrimPendingMeasure: (n: Int, overflow: CGFloat)? = nil
    // 現在のボタン群を組み立てた時の間隔設定。設定変更(間隔)を検知して作り直すために保持する。
    var currentBarButtonItemSpacing: CGFloat = -1

    // 実測で決めたスロット上限をリセットして、次のレイアウトで再見積もり+再実測させる。
    // 回転・文字サイズ変更・画面への入り直しで呼ぶ(「一度縮んだら戻らない」の防止)。
    func resetUpperButtonFittedSlotLimit() {
        if self.upperButtonFittedSlotLimit == nil { return }
        self.upperButtonFittedSlotLimit = nil
        self.upperButtonFittedSlotLimitWidth = -1
        self.upperButtonTrimPendingMeasure = nil
        self.isUpperRightButtonsChanged = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // 回転等で使える幅が変わるので、実測上限を捨てて新しい幅で再見積もり+再実測する
        self.resetUpperButtonFittedSlotLimit()
        coordinator.animate(alongsideTransition: nil) { _ in
            self.forceUpdateUpperButtons()
            self.scheduleUpperButtonTrim()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let webView = WebSpeechViewController.createWkWebViewWithUserContentController(handler:self, myScriptNamespace:myScriptNamespace)
        self.textWebView = webView
        createUIComponents(webView: webView)
        RestartObservers()
        RealmUtil.RealmBlock { realm in
            self.loadFirstContentWith(realm: realm, storyID: targetStoryID, webView: webView)
        }
        setCustomUIMenu()
        WebSpeechViewController.instance = self
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        registNotificationCenter()
    }
    
    deinit {
        self.scrollFollowSuspendTimer?.invalidate()
        self.scrollFollowSuspendTimer = nil
        StopObservers()
        self.unregistNotificationCenter()
        WebSpeechViewController.instance = nil
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        StorySpeaker.shared.AddDelegate(delegate: self)
        self.navigationController?.navigationBar.backgroundColor = UIColor.clear
        applyTheme()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.resumeTheme()
        self.cancelScrollFollowSuspend()
        StorySpeaker.shared.RemoveDelegate(delegate: self)
        self.displayTopAndDownComponents(animated: false)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.clearSearchView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.forceUpdateUpperButtons()
        self.scheduleUpperButtonTrim()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 画面に入り直すたびに実測上限をリセットしてから測り直す(誤検出で縮んだままの固着を防ぐ)。
        self.resetUpperButtonFittedSlotLimit()
        // 画面表示が完了し customView がナビバーに載ったこのタイミングで実測補正する(主トリガ)。
        self.scheduleUpperButtonTrim()
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
    
    func registNotificationCenter() {
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.BarButtonSpacingChanged, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            // 間隔が変わると使える幅も変わるので、作り直しフラグを立て、実測上限もリセットして測り直す。
            self.isUpperRightButtonsChanged = true
            self.resetUpperButtonFittedSlotLimit()
            self.forceUpdateUpperButtons()
            self.scheduleUpperButtonTrim()
        }
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.SpeechViewRightTopButtonTitleChanged, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            // ボタンの表示/非表示が変わったので、実測上限もリセットして作り直し+trim をやり直す。
            self.resetUpperButtonFittedSlotLimit()
            self.isUpperRightButtonsChanged = true
            self.forceUpdateUpperButtons()
            self.scheduleUpperButtonTrim()
        }
        // Dynamic Type の文字サイズ変更で使える幅が変わるので、実測上限をリセットして測り直す。
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: UIContentSizeCategory.didChangeNotification, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            self.resetUpperButtonFittedSlotLimit()
            self.forceUpdateUpperButtons()
            self.scheduleUpperButtonTrim()
        }
    }
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }
    func forceUpdateUpperButtons() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                let storyID = StorySpeaker.shared.storyID
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.RemoveRealmLink(), let buttonSettings = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() else { return }
                self.assignUpperButtons(novelID: novel.novelID, novelType: novel.type, aliveButtonSettings: buttonSettings)
            }
            self.assignBottomButtons()
        }
    }

    // 画面下部のボタン群を作り直す。設定が全部OFFなら何も表示しない(バー自体を消す)。
    // viewDidLayoutSubviews からも呼ばれるので、同じ内容なら何もしないで返す
    // (でないと「作り直す→レイアウトが走る→また呼ばれる」で無限に回る)。
    func assignBottomButtons() {
        DispatchQueue.main.async {
            let isPlayng = StorySpeaker.shared.isPlayng
            let info:(novelID:String, novelType:NovelType, settings:[SpeechViewButtonSetting], overlaps:Bool)? = RealmUtil.RealmBlock { (realm) -> (novelID:String, novelType:NovelType, settings:[SpeechViewButtonSetting], overlaps:Bool)? in
                let storyID = StorySpeaker.shared.storyID
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.RemoveRealmLink(),
                      let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return nil }
                return (novelID: novel.novelID, novelType: novel.type, settings: globalState.GetSpeechViewBottomButtonSetting(), overlaps: globalState.isSpeechViewBottomButtonOverlapsChapterBar)
            }
            guard let info = info else { return }
            let signature = "\(info.novelID)/\(info.novelType)/\(info.overlaps)/\(isPlayng)/\(NovelSpeakerUtility.GetBarButtonItemSpacing())/" + info.settings.map({ "\($0.type.rawValue):\($0.isOn)" }).joined(separator: ",")
            if self.currentBottomButtonSignature == signature { return }
            self.currentBottomButtonSignature = signature

            self.bottomButtonBar?.removeFromSuperview()
            self.bottomButtonBar = nil
            self.bottomStartStopButton = nil
            self.bottomSkipBackwardButton = nil
            self.bottomSkipForwardButton = nil
            if info.settings.contains(where: { $0.isOn }) == false { return }

            let buttons = self.createSpeechViewButtonArray(novelID: info.novelID, novelType: info.novelType, aliveButtonSettings: info.settings, buttonSize: 28, isForBottomBar: true)
            if buttons.isEmpty { return }

            let bar = SpeechViewBottomButtonBar()
            self.view.addSubview(bar)
            self.view.bringSubviewToFront(bar)
            bar.setButtons(buttons)
            let safeAreaGuide = self.view.safeAreaLayoutGuide
            var constraints:[NSLayoutConstraint] = [
                bar.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaGuide.leadingAnchor, constant: 8),
                bar.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaGuide.trailingAnchor, constant: -8),
                bar.centerXAnchor.constraint(equalTo: safeAreaGuide.centerXAnchor),
            ]
            if info.overlaps {
                // ページ送りのバーに重ねる(本文は最大限広いが、ページ送り/スライダは押せなくなる)
                constraints.append(bar.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor))
            }else{
                // ページ送りのバーの上に出す(ページ送りは押せるが、本文が少し隠れる)
                constraints.append(bar.bottomAnchor.constraint(equalTo: self.previousChapterButton.topAnchor, constant: -4))
            }
            NSLayoutConstraint.activate(constraints)
            self.bottomButtonBar = bar
            self.applyTheme()
        }
    }
    // background から redume した時に何故かWebViewの中身が空(真っ白)になる事があるぽいのでそれに対抗するために redume した時に呼ばれて再描画？する関数を用意しておきます。(´・ω・`)
    @objc func RedisplayWebView() {
        // MEMO: getCurrentDisplayLocation() でスクロールする起点を取得して、
        // overrideLocation にそれを渡す事で再表示しながら「現在表示されている部分へスクロールする」ようになるんだけれど……
        // WebViewOriginal みたいなのだと表示されている部分を検出できない可能性があるのよね。(´・ω・`)
        // あと、縦書きの時は1文字分ズレてしまうので、検出する時の xRaito と
        // スクロールする時の Raito を少し変える事で怪しく回避しようとしてるんだけど、
        // まぁ文字の大きさによって失敗するんよなこの方法だと
        let xRaito:Double
        let yRaito:Double
        let scrollRaito:Double
        if self.currentViewTypeCache == .webViewVertical || self.currentViewTypeCache == .webViewVertical2Column {
            xRaito = 0.99
            yRaito = 0.5
            scrollRaito = 0.95
        }else{
            xRaito = 0.5
            yRaito = 0.01
            scrollRaito = 0.95
        }
        self.webSpeechTool.getCurrentDisplayLocation(xRatio: xRaito, yRatio: yRaito) { currentDisplayLocation in
            RealmUtil.RealmBlock { realm in
                if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID) {
                    self.loadStoryWithoutStorySpeakerWith(story: story, overrideLocation: currentDisplayLocation, scrollRatio: scrollRaito)
                }
            }
        }
    }

    func StopObservers() {
        if let token = self.novelObserverToken {
            StorySpeaker.shared.RemoveUpdateReadDateWithoutNotifiningToken(token: token)
        }
        novelObserverToken = nil
        storyObserverToken = nil
        displaySettingObserverToken = nil
        globalStateObserverToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeDispaySetting()
        let storyID = StorySpeaker.shared.storyID
        observeStory(storyID: storyID)
        observeNovel(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))
        observeGlobalState()
    }
    
    func applyChapterListChange() {
        let storyID = StorySpeaker.shared.storyID
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
        var lastChapterNumber:Int = self.lastChapterNumber
        if lastChapterNumber <= 0 {
            RealmUtil.RealmBlock { (realm) -> Void in
                lastChapterNumber = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID)?.lastChapterNumber ?? -1
            }
            if lastChapterNumber <= 0 {
                return
            }
            self.lastChapterNumber = lastChapterNumber
        }
        DispatchQueue.main.async {
            if chapterNumber <= 1 {
                self.previousChapterButton.isEnabled = false
            }else{
                self.previousChapterButton.isEnabled = true
            }
            if chapterNumber < lastChapterNumber {
                self.nextChapterButton.isEnabled = true
            }else{
                self.nextChapterButton.isEnabled = false
            }
            self.chapterSlider.minimumValue = 1.0
            self.chapterSlider.maximumValue = Float(lastChapterNumber) + Float(0.01)
            self.chapterSlider.value = Float(chapterNumber)
            
            self.chapterPositionLabel.text = "\(chapterNumber)/\(lastChapterNumber)"
            self.chapterPositionLabel.sizeToFit()
            if self.view.subviews.contains(self.chapterPositionLabel) {
                if let constraint = self.chapterPositionLabelWidthConstraint {
                    self.chapterPositionLabel.removeConstraint(constraint)
                }
                self.chapterPositionLabelWidthConstraint = self.chapterPositionLabel.widthAnchor.constraint(equalToConstant: self.chapterPositionLabel.frame.width)
                self.chapterPositionLabelWidthConstraint?.isActive = true
            }
        }
    }

    func createUIComponents(webView:WKWebView) {
        let safeAreaGuide:UILayoutGuide
        if #available(iOS 11.0, *) {
            safeAreaGuide = self.view.safeAreaLayoutGuide
        } else {
            safeAreaGuide = self.view.layoutMarginsGuide
        }

        self.view.addSubview(previousChapterButton)
        self.view.addSubview(nextChapterButton)
        self.view.addSubview(chapterSlider)
        self.view.addSubview(chapterPositionLabel)
        if #available(iOS 13.0, *), let img = UIImage(systemName: "arrowtriangle.left.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)) {
            previousChapterButton.setImage(img, for: .normal)
        } else {
            previousChapterButton.setTitle("◀", for: .normal)
        }
        previousChapterButton.sizeToFit()
        previousChapterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title1)
        previousChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        previousChapterButton.accessibilityLabel = NSLocalizedString("SpeechViewController_PreviousChapterButton_VoiceOverTitle", comment: "前のページ")
        previousChapterButton.addTarget(self, action: #selector(previousChapterButtonClicked(_:)), for: .touchUpInside)
        previousChapterButton.translatesAutoresizingMaskIntoConstraints = false
        
        if #available(iOS 13.0, *), let img = UIImage(systemName: "arrowtriangle.right.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)) {
            nextChapterButton.setImage(img, for: .normal)
        } else {
            nextChapterButton.setTitle("▶", for: .normal)
        }
        nextChapterButton.sizeToFit()
        nextChapterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title1)
        nextChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nextChapterButton.accessibilityLabel = NSLocalizedString("SpeechViewController_NextChapterButton_VoiceOverTitle", comment: "次のページ")
        nextChapterButton.addTarget(self, action: #selector(nextChapterButtonClicked(_:)), for: .touchUpInside)
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false
        
        chapterSlider.translatesAutoresizingMaskIntoConstraints = false
        chapterSlider.addTarget(self, action: #selector(chapterSliderValueChanged(_:)), for: .valueChanged)

        chapterPositionLabel.adjustsFontForContentSizeCategory = true
        chapterPositionLabel.translatesAutoresizingMaskIntoConstraints = false
        chapterPositionLabel.font = UIFont.preferredFont(forTextStyle: .body)
        applyChapterListChange()
        
        self.previousChapterBottomConstraint = previousChapterButton.bottomAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor, constant: -8)
        NSLayoutConstraint.activate([
            self.previousChapterBottomConstraint!,
            self.chapterSlider.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor),
            self.previousChapterButton.leftAnchor.constraint(equalTo: safeAreaGuide.leftAnchor, constant: 16),
            self.chapterSlider.leftAnchor.constraint(equalTo: self.previousChapterButton.rightAnchor, constant: 8),
            self.nextChapterButton.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor),
            self.nextChapterButton.leftAnchor.constraint(equalTo: self.chapterSlider.rightAnchor, constant: 8),
            self.chapterPositionLabel.centerYAnchor.constraint(equalTo: self.previousChapterButton.centerYAnchor),
            self.chapterPositionLabel.leftAnchor.constraint(equalTo: self.nextChapterButton.rightAnchor, constant: 8),
            self.chapterPositionLabel.rightAnchor.constraint(equalTo: safeAreaGuide.rightAnchor, constant: -16),
            self.previousChapterButton.widthAnchor.constraint(equalToConstant: 40),
            self.nextChapterButton.widthAnchor.constraint(equalToConstant: 40),
        ])
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(webView)
        let scrollPullAndFireHandler =  ScrollPullAndFireHandler(parent: self.view, scrollView: webView.scrollView, behavior: .horizontal)
        scrollPullAndFireHandler.invokeMethod = { isForward in
            switch isForward {
            case true:
                RealmUtil.RealmBlock { (realm) -> Void in
                    StorySpeaker.shared.LoadNextChapter(realm: realm)
                }
            case false:
                RealmUtil.RealmBlock { (realm) -> Void in
                    StorySpeaker.shared.LoadPreviousChapter(realm: realm, moveReadingPointToLast: true)
                }
            }
        }
        scrollPullAndFireHandler.userScrollBeganHandler = { [weak self] in
            guard let self = self else { return }
            let second = self.scrollFollowSuspendSecond()
            if second <= 0 { return }
            self.suspendScrollFollow(second: second)
        }
        scrollPullAndFireHandler.userScrollEndedHandler = { [weak self] in
            guard let self = self else { return }
            // 指を離した時点から測り直す。
            self.suspendScrollFollow(second: self.scrollFollowSuspendSecond())
        }
        self.scrollPullAndFireHandler = scrollPullAndFireHandler

        // 長押しで「ここから発話開始」を出すために、長押し開始で一時停止を始める。
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.handleSpeakFromHereLongPress(_:)))
        longPressRecognizer.minimumPressDuration = 0.3
        longPressRecognizer.cancelsTouchesInView = false
        longPressRecognizer.delaysTouchesBegan = false
        longPressRecognizer.delegate = self
        webView.addGestureRecognizer(longPressRecognizer)
        self.speakFromHereLongPressRecognizer = longPressRecognizer
        (webView as? CustomWKWebView)?.speakFromHereSelector = #selector(self.speakFromHere(sender:))
        (webView as? CustomWKWebView)?.speakFromHereTarget = self
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: previousChapterButton.topAnchor, constant: -8),
            webView.leftAnchor.constraint(equalTo: safeAreaGuide.leftAnchor, constant: 8),
            webView.rightAnchor.constraint(equalTo: safeAreaGuide.rightAnchor, constant: -8),
        ])
        
        let toggleInterfaceButton = UIButton()
        toggleInterfaceButton.translatesAutoresizingMaskIntoConstraints = false
        toggleInterfaceButton.isAccessibilityElement = false
        //toggleInterfaceButton.backgroundColor = foregroundColor
        //toggleInterfaceButton.setTitleColor(backgroundColor, for: .normal)
        //toggleInterfaceButton.layer.cornerRadius = 3
        //toggleInterfaceButton.layer.borderWidth = 2
        //toggleInterfaceButton.layer.borderColor = foregroundColor.cgColor
        toggleInterfaceButton.clipsToBounds = true
        toggleInterfaceButton.addTarget(self, action: #selector(toggleInterfaceButtonClicked), for: .touchUpInside)
        self.toggleInterfaceButton = toggleInterfaceButton
        self.view.addSubview(toggleInterfaceButton)
        self.view.bringSubviewToFront(toggleInterfaceButton)
        self.view.sendSubviewToBack(webView)
        NSLayoutConstraint.activate([
            toggleInterfaceButton.bottomAnchor.constraint(equalTo: previousChapterButton.topAnchor, constant: -25),
            toggleInterfaceButton.rightAnchor.constraint(equalTo: safeAreaGuide.rightAnchor, constant: -25),
        ])
        assignHideToToggleInterfaceButton()
    }
    
    static func createInjectScriptAtDocumentStart(myScriptNamespace:String) -> String{
        return """
            \(myScriptNamespace) = {
                webkit: window.webkit
            };
            """
    }
    static func createInjectScriptAtDocumentEnd(myScriptNamespace:String) -> String{
        return """
            var console = {
                log: function(...args){
                    \(myScriptNamespace).webkit.messageHandlers.logging.postMessage(args);
                }
            };
            """
    }

    static func createWkWebViewWithUserContentController(handler:WebSpeechViewController, myScriptNamespace:String) -> CustomWKWebView {
        let injectScriptAtDocumentStart = createInjectScriptAtDocumentStart(myScriptNamespace:myScriptNamespace)
        let userScriptAtDocumentStart = WKUserScript(source: injectScriptAtDocumentStart, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let injectScriptAtDocumentEnd = createInjectScriptAtDocumentEnd(myScriptNamespace:myScriptNamespace)
        let userScriptAtDocumentEnd = WKUserScript(source: injectScriptAtDocumentEnd, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(userScriptAtDocumentStart)
        config.userContentController.addUserScript(userScriptAtDocumentEnd)
        config.userContentController.add(handler, name: "logging")
        NovelSpeakerUtility.ApplyPrivacyTrackingBlockRuleIfNeeded(to: config)
        return CustomWKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), configuration: config)
    }

    // WkWebView の JavaScript からのイベントを受け取るメッセージハンドラ
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "logging":
            print("WebViewConsole:", JavaScriptAnyToString(body: message.body))
        case "tapEvent":
            print("tapEvent from JavaScript");
        default:
            break
        }
    }
    func JavaScriptAnyToString(body:Any) -> String {
        if let number = body as? NSNumber {
            return "\(number)"
        }
        if let string = body as? String {
            return "\"\(string)\""
        }
        if let date = body as? NSDate {
            return "\(date)"
        }
        if let array = body as? NSArray {
            return array.reduce("[") { current, body in
                return current + (current.count <= 1 ? "" : ", ") + JavaScriptAnyToString(body: body)
            } + "]"
        }
        if let dictionary = body as? NSDictionary {
            return dictionary.reduce("{\n") { current, element in
                return current + (current.count <= 2 ? "" : "\n") + "  \(JavaScriptAnyToString(body: element.key)): \(JavaScriptAnyToString(body: element.value))"
            } + "\n}"
        }
        if body is NSNull {
            return "null"
        }
        return "unknown(\(String(describing: body))"
    }

    func hideTopAndDownComponents(animated:Bool = false, animateCompletion: (()->Void)? = nil) {
        if let bottomConstraint = self.previousChapterBottomConstraint {
            bottomConstraint.isActive = false
        }
        
        UIView.transition(with: self.view, duration: animated ? TimeInterval(UINavigationController.hideShowBarDuration) : 0, options: .curveEaseOut) {
            if let topConstraint = self.previousChapterTopConstraint { topConstraint.isActive = false }
            let safeAreaGuide:UILayoutGuide
            if #available(iOS 11.0, *) {
                safeAreaGuide = self.view.safeAreaLayoutGuide
            } else {
                safeAreaGuide = self.view.layoutMarginsGuide
            }
            self.previousChapterTopConstraint = self.previousChapterButton.topAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor)
            self.previousChapterTopConstraint?.isActive = true
            self.previousChapterButton.isHidden = true
            self.nextChapterButton.isHidden = true
            self.chapterSlider.isHidden = true
            self.chapterPositionLabel.isHidden = true
            self.navigationController?.setNavigationBarHidden(true, animated: animated)
            // setTabBarVisible を使うと SafeAreaGuide 周りが壊れるぽいので封印します。(´・ω・`)
            //self.tabBarController?.setTabBarVisible(visible:false, animated: animated, animateCompletion: animateCompletion)
            self.tabBarController?.tabBar.isHidden = true
        } completion: { finished in
            animateCompletion?()
        }
        self.assignDisplayToToggleInterfaceButton()
    }
    func displayTopAndDownComponents(animated:Bool = false, animateCompletion: (()->Void)? = nil) {
        if let topConstraint = self.previousChapterTopConstraint {
            topConstraint.isActive = false
        }
        UIView.transition(with: self.view, duration: animated ? TimeInterval(UINavigationController.hideShowBarDuration) : 0, options: .curveEaseOut) {
            if let bottomConstraint = self.previousChapterBottomConstraint { bottomConstraint.isActive = false }
            let safeAreaGuide:UILayoutGuide
            if #available(iOS 11.0, *) {
                safeAreaGuide = self.view.safeAreaLayoutGuide
            } else {
                safeAreaGuide = self.view.layoutMarginsGuide
            }
            self.previousChapterBottomConstraint = self.previousChapterButton.bottomAnchor.constraint(equalTo: safeAreaGuide.bottomAnchor, constant: -8)
            self.previousChapterBottomConstraint?.isActive = true
            self.previousChapterButton.isHidden = false
            self.nextChapterButton.isHidden = false
            self.chapterSlider.isHidden = false
            self.chapterPositionLabel.isHidden = false

            self.navigationController?.setNavigationBarHidden(false, animated: animated)
            //self.tabBarController?.setTabBarVisible(visible:true, animated: animated, animateCompletion: animateCompletion)
            self.tabBarController?.tabBar.isHidden = false
        } completion: { finished in
            animateCompletion?()
        }
        self.assignHideToToggleInterfaceButton()
    }

    func loadStoryWithoutStorySpeakerWith(story:Story, overrideLocation:Int? = nil, scrollRatio: Double? = nil) {
        guard let webView = self.textWebView else { return }
        RealmUtil.RealmBlock { realm in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: story.novelID) else { return }
            let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm)
            let readLocation = story.readLocation(realm: realm)
            self.currentViewTypeCache = displaySetting?.viewType
            let novelTitle = novel.title
            DispatchQueue.main.async {
                self.title = novelTitle
            }
            if let lastChapterNumber = novel.lastChapterNumber {
                self.lastChapterNumber = lastChapterNumber
            }
            let aliveButtonSettings = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() ?? SpeechViewButtonSetting.defaultSetting
            self.assignUpperButtons(novelID: novel.novelID, novelType: novel.type, aliveButtonSettings: aliveButtonSettings)
            self.webViewDisplayWholeText = nil
            if story.url.count > 0, novel.type == .URL, let url = URL(string: story.url), displaySetting?.viewType == .webViewOriginal {
                self.isNeedCollectDisplayLocation = true
                let siteInfoArray = StoryHtmlDecoder.shared.SearchSiteInfoArrayFrom(urlString: story.url)
                let request = URLRequest(url: url)
                self.webSpeechTool.loadUrl(webView: webView, request: request, siteInfoArray: siteInfoArray, completionHandler: {
                    self.webSpeechTool.getSpeechText { text in
                        self.webViewDisplayWholeText = text
                    }
                    //self.webSpeechTool.hideNotPageElement {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1) {
                        if let overrideLocation = overrideLocation, overrideLocation >= 0 {
                            self.webSpeechTool.scrollToIndex(location: overrideLocation, length: 1, scrollRatio: scrollRatio ?? 0.5)
                        }else{
                            self.webSpeechTool.scrollToIndex(location: readLocation, length: 1, scrollRatio: 0.3)
                        }
                    }
                    //}
                })
                return
            }
            if let type = displaySetting?.viewType, type == .webViewHorizontal || type == .webViewVertical || type == .webViewVertical2Column {
                self.scrollPullAndFireHandler?.setupFor(scrollBehavior: type == .webViewVertical ? .vertical : .horizontal)
                if story.chapterNumber <= 1 {
                    self.scrollPullAndFireHandler?.isBackwardEnabled = false
                }else{
                    self.scrollPullAndFireHandler?.isBackwardEnabled = true
                }
                if let lastChapterNumber = novel.lastChapterNumber, lastChapterNumber == story.chapterNumber {
                    self.scrollPullAndFireHandler?.isForwardEnabled = false
                }else{
                    self.scrollPullAndFireHandler?.isForwardEnabled = true
                }
            }
            self.isNeedCollectDisplayLocation = false
            let (fg, bg) = getForegroundBackgroundColor()
            let font = displaySetting?.font
            let viewType = displaySetting?.viewType
            let lineSpacingDisplayValue = displaySetting?.lineSpacingDisplayValue
            DispatchQueue.main.async {
                self.webSpeechTool.applyFromNovelSpeakerString(webView: webView, content: story.content, foregroundColor: fg, backgroundColor: bg, font: font, viewType: viewType, lineSpacingDisplayValue: lineSpacingDisplayValue, baseURL: nil) {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1) {
                        if let overrideLocation = overrideLocation, overrideLocation > 0 {
                            self.webSpeechTool.scrollToIndex(location: overrideLocation, length: 1, scrollRatio: scrollRatio ?? 0.5)
                        }else{
                            self.webSpeechTool.scrollToIndex(location: readLocation, length: 1, scrollRatio: 0.3)
                        }
                    }
                }
            }
        }
    }
    
    func loadNovelWith(realm:Realm, story:Story, webView:WKWebView) {
        webView.loadHTMLString("<html><body class='NovelSpeakerBody'>\(NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))</body></html>", baseURL: nil)
        StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { story in
            self.loadStoryWithoutStorySpeakerWith(story: story)
        }
    }
    
    func loadFirstContentWith(realm:Realm, storyID:String?, webView:WKWebView) {
        guard let storyID = storyID, let targetStory = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) else {
            webView.loadHTMLString("<html><body class='NovelSpeakerBody'>\( NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))</body></html>", baseURL: nil)
            return
        }
        loadNovelWith(realm: realm, story: targetStory, webView: webView)
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
    
    override var childForStatusBarStyle: UIViewController? {
        return nil
    }
    // スタイルを保持する変数（初期値はデフォルト）
    var currentStatusBarStyle: UIStatusBarStyle = .default

    // システムがステータスバーの色を尋ねてきたときにこの変数を返す
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return currentStatusBarStyle
    }

    func applyThemeColor(backgroundColor:UIColor, foregroundColor:UIColor, indicatorStyle:UIScrollView.IndicatorStyle, barStyle:UIBarStyle) {
        self.bottomButtonBar?.applyThemeColor(backgroundColor: backgroundColor, foregroundColor: foregroundColor)
        
        self.view.backgroundColor = backgroundColor;
        if #available(iOS 13.0, *) {
            // nothing.
        }else{
            self.nextChapterButton.backgroundColor = backgroundColor
            self.nextChapterButton.setTitleColor(self.view.tintColor, for: .normal)
            self.nextChapterButton.setTitleColor(self.view.tintColor.withAlphaComponent(0.5), for: .disabled)
            self.previousChapterButton.backgroundColor = backgroundColor
            self.previousChapterButton.setTitleColor(self.view.tintColor, for: .normal)
            self.previousChapterButton.setTitleColor(self.view.tintColor.withAlphaComponent(0.5), for: .disabled)
        }
        self.chapterSlider.backgroundColor = backgroundColor
        self.chapterPositionLabel.backgroundColor = backgroundColor
        self.chapterPositionLabel.textColor = foregroundColor
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.tabBarController?.tabBar.backgroundColor = backgroundColor
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: foregroundColor]
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = barStyle
        if barStyle == .black {
            currentStatusBarStyle = .lightContent
        } else {
            currentStatusBarStyle = .default
        }
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = barStyle
        // WebView にはCSSで注入する
        applyFgBgColorToWebView(foregroundColor: foregroundColor, backgroundColor: backgroundColor)
        // 引っ張って次ページへ移動の奴にも色を設定する
        self.scrollPullAndFireHandler?.setColor(foreground: foregroundColor, background: backgroundColor)

        // navigation bar の appearance を変更する
        let appearance = UINavigationBarAppearance()
        // 1. 背景を不透明（Opaque）に設定し、背景色を指定
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = backgroundColor
        // 2. タイトルの色を設定
        appearance.titleTextAttributes = [.foregroundColor: foregroundColor]
        // 3. 全ての状態（通常時・スクロール時）に同じ外観を適用する
        self.navigationController?.navigationBar.standardAppearance = appearance
        self.navigationController?.navigationBar.scrollEdgeAppearance = appearance
        self.navigationController?.navigationBar.compactAppearance = appearance
        
        // 【重要】ステータスバーの外観更新を明示的に要求する
        self.setNeedsStatusBarAppearanceUpdate()
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
    
    func resumeTheme() {
        var backgroundColor = UIColor.white
        var foregroundColor = UIColor.black
        let indicatorStyle = UIScrollView.IndicatorStyle.default
        let barStyle = UIBarStyle.default
        
        if #available(iOS 13.0, *) {
            backgroundColor = UIColor.systemBackground
            foregroundColor = UIColor.label
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
                                self.assignUpperButtons(novelID: novel.novelID, novelType: novel.type, aliveButtonSettings: buttonSettings)
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

    func observeStory(storyID:String) {
        if storyObserverBulkStoryID == RealmStoryBulk.StoryIDToBulkID(storyID: storyID) { return }
        self.storyObserverToken = nil
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let storyBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: storyID) else { return }
            storyObserverBulkStoryID = storyBulk.id
            self.storyObserverToken = storyBulk.observe({ [weak self] (change) in
                guard let self = self else { return }
                let targetStoryID = StorySpeaker.shared.storyID
                guard self.storyObserverBulkStoryID == RealmStoryBulk.StoryIDToBulkID(storyID: targetStoryID) else {
                    return
                }
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        // content が書き換わった時のみを監視します。
                        // でないと lastReadDate とかが書き換わった時にも表示の更新が走ってしまいます。
                        let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: targetStoryID)
                        if property.name == "storyListAsset", let newValue = property.newValue as? CreamAsset, let storyArray = RealmStoryBulk.StoryCreamAssetToStoryArray(asset: newValue) {
                            // [Story] に変換できた
                            if let story = RealmStoryBulk.StoryBulkArrayToStory(storyArray: storyArray, chapterNumber: chapterNumber) {
                                // 今開いている Story が書き換えられているぽい
                                if story.chapterNumber == chapterNumber, story.content != self.speakerDisplayWholeText {
                                    self.speakerDisplayWholeText = story.content
                                    DispatchQueue.main.async {
                                        self.loadStoryWithoutStorySpeakerWith(story: story)
                                    }
                                }
                            }else{
                                // 今開いている Story が存在しなかった(恐らくは最後の章を開いていて、その章が削除された)
                                if let lastStory = storyArray.last {
                                    DispatchQueue.main.async {
                                        StorySpeaker.shared.SetStory(story: lastStory, withUpdateReadDate: true)
                                    }
                                }
                            }
                        }
                    }
                case .deleted:
                    break
                }
            })
        }
    }

    func observeNovel(novelID:String) {
        if novelObserverNovelID == RealmStoryBulk.StoryIDToNovelID(storyID: StorySpeaker.shared.storyID) { return }
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
            self.lastChapterNumber = novel.lastChapterNumber ?? -1
            novelObserverNovelID = novelID
            self.novelObserverToken = novel.observe({ [weak self] (change) in
                guard let self = self else { return }
                switch change {
                case .error(_):
                    break
                case .change(_, let properties):
                    for property in properties {
                        if property.name == "title", let newValue = property.newValue as? String {
                            DispatchQueue.main.async {
                                self.title = newValue
                            }
                        }
                        if property.name == "m_lastChapterStoryID", let newValue = property.newValue as? String {
                            let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: newValue)
                            if chapterNumber > 0 && self.lastChapterNumber != chapterNumber {
                                self.lastChapterNumber = chapterNumber
                                self.applyChapterListChange()
                            }
                        }
                        if property.name == "m_readingChapterStoryID", let newReadingChapterStoryID = property.newValue as? String, newReadingChapterStoryID != StorySpeaker.shared.storyID, self.readingChapterStoryUpdateDate < Date(timeIntervalSinceNow: -1.5) {
                            self.currentReadingStoryIDChangedEventHandler(newReadingStoryID: newReadingChapterStoryID)
                        }
                     }
                case .deleted:
                    break
                }
            })
            if let token = self.novelObserverToken {
                StorySpeaker.shared.AddUpdateReadDateWithoutNotificationToken(token: token)
            }
        }
    }
    
    func disableCurrentReadingStoryChangeFloatingButton() {
        guard let oldFloatingButton = self.currentReadStoryIDChangeAlertFloatingButton else { return }
        self.currentReadStoryIDChangeAlertFloatingButton = nil
        DispatchQueue.main.async {
            oldFloatingButton.hide()
        }
    }
    func currentReadingStoryIDChangedEventHandler(newReadingStoryID:String) {
        let currentStoryID = StorySpeaker.shared.storyID
        guard newReadingStoryID != currentStoryID else { return }
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: newReadingStoryID) else { return }
            let newChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: newReadingStoryID)
            DispatchQueue.main.async {
                self.currentReadStoryIDChangeAlertFloatingButton = FloatingButton.createNewFloatingButton()
                guard let floatingButton = self.currentReadStoryIDChangeAlertFloatingButton else { return }
                floatingButton.assignToView(view: self.view, currentOffset: CGPoint(x: -1, y: -1), text: String(format: NSLocalizedString("SpeechViewController_CurrentReadingStoryChangedFloatingButton_Format", comment: "他端末で更新された %d章 へ移動"), newChapterNumber), animated: true, bottomConstraintAppend: -32.0) {
                    StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: false)
                    floatingButton.hideAnimate()
                }
            }
        }
    }

    //MARK: 上のボタン群の設定
    var startStopButton:UIButton? = nil
    var shareButtonItem:UIBarButtonItem? = nil
    var skipBackwardButtonItem:UIButton? = nil
    var skipForwardButtonItem:UIButton? = nil
    var currentWindowWidth:CGFloat = 0.0
    // 右上のボタン群と画面下部のボタン群の両方で使う、設定配列から実際のボタンを作る処理。
    func createSpeechViewButtonArray(novelID: String, novelType: NovelType, aliveButtonSettings:[SpeechViewButtonSetting], buttonSize:CGFloat, isForBottomBar:Bool) -> [UIButton] {
        var barButtonArray:[UIButton] = []
        
        func createBarButtonItem(image: UIImage?, action: Selector, accessibilityLabel: String) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(image, for: .normal)
            button.addTarget(self, action: action, for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityLabel = accessibilityLabel
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: buttonSize)
            widthConstraint.priority = UILayoutPriority(999) // 1000未満にする
            let heightConstraint = button.heightAnchor.constraint(equalToConstant: buttonSize)
            heightConstraint.priority = UILayoutPriority(999)
            NSLayoutConstraint.activate([
                widthConstraint,
                heightConstraint
            ])
            return button
        }

        for buttonSetting in aliveButtonSettings {
            if buttonSetting.isOn == false { continue }
            switch buttonSetting.type {
            case .openCurrentWebPage:
                if novelType == .URL {
                    let button = createBarButtonItem(
                        image: UIImage(systemName: "globe.americas.fill"),
                        action: #selector(self.openCurrentWebPageButtonClicked(_:)),
                        accessibilityLabel: NSLocalizedString("SpeechViewController_CurrentWebPageButton_VoiceOverTitle", comment: "現在のページをWeb取込タブで開く")
                    )
                    barButtonArray.append(button)
                }
            case .openWebPage:
                if novelType == .URL {
                    let button = createBarButtonItem(
                        image: UIImage(systemName: "globe.badge.chevron.backward"),
                        action: #selector(self.safariButtonClicked(_:)),
                        accessibilityLabel: NSLocalizedString("SpeechViewController_WebPageButton_VoiceOverTitle", comment: "Web取込タブで開く")
                    )
                    barButtonArray.append(button)
                }
            case .reload:
                if novelType == .URL || (novelType == .UserCreated && NovelSpeakerUtility.IsRegisteredOuterNovel(novelID: novelID)) {
                    let button = createBarButtonItem(
                        image: UIImage(systemName: "arrow.clockwise"),
                        action: #selector(self.urlRefreshButtonClicked(_:)),
                        accessibilityLabel: NSLocalizedString("SpeechViewController_RefreshButton_AccessibilityLabel", comment: "この小説の更新確認を行う")
                    )
                    barButtonArray.append(button)
                }
            case .share:
                if novelType == .URL {
                    let button = createBarButtonItem(
                        image: UIImage(systemName: "square.and.arrow.up"),
                        action: #selector(self.shareButtonClicked(_:)),
                        accessibilityLabel: NSLocalizedString("SpeechViewButtonType_Share", comment: "小説のURLをシェアする")
                    )
                    barButtonArray.append(button)
                }
            case .search:
                //barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(searchButtonClicked(_:))))
                let button = createBarButtonItem(
                    image: UIImage(systemName: "magnifyingglass"),
                    action: #selector(self.searchButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_SearchButton_AccessibilityLabel", comment: "検索")
                )
                barButtonArray.append(button)
                /*
            case .searchByText:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "doc.text.magnifyingglass"),
                    action: #selector(self.searchByTextButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_SearchByTextButton_AccessibilityLabel", comment: "ページ内を検索")
                )
                barButtonArray.append(button)
                 */
            case .edit:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "pencil"),
                    action: #selector(self.editButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_Edit", comment: "編集")
                )
                barButtonArray.append(button)
            case .detail:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "book.pages"),
                    action: #selector(self.detailButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_Detail", comment: "詳細")
                )
                barButtonArray.append(button)
            case .backup:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "tray.and.arrow.up"),
                    action: #selector(self.backupButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_BackupButton", comment: "バックアップ")
                )
                barButtonArray.append(button)
            case .skipBackward:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "gobackward.30"),
                    action: #selector(self.skipBackwardButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_SkipBackwardButtonTitle", comment: "巻き戻し")
                )
                if isForBottomBar { self.bottomSkipBackwardButton = button } else { self.skipBackwardButtonItem = button }
                barButtonArray.append(button)
            case .skipForward:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "goforward.30"),
                    action: #selector(self.skipForwardButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_SkipForwardButtonTitle", comment: "少し先へ")
                )
                if isForBottomBar { self.bottomSkipForwardButton = button } else { self.skipForwardButtonItem = button }
                barButtonArray.append(button)
            case .showTableOfContents:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "list.bullet"),
                    action: #selector(self.showTableOfContentsButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewController_ShowTableOfContentsButtonTitle", comment: "目次")
                )
                barButtonArray.append(button)
            case .addPageToOtherNovel:
                let button = createBarButtonItem(
                    image: UIImage(systemName: "book.badge.plus"),
                    action: #selector(self.addPageToOtherNovelButtonClicked(_:)),
                    accessibilityLabel: NSLocalizedString("SpeechViewButtonType_AddPageToOtherNovel", comment: "他の小説にこのページを追加する")
                )
                barButtonArray.append(button)
            case .speechStop:
                let button = createBarButtonItem(image: UIImage(systemName: "play.fill"), action: #selector(self.startStopButtonClicked(_:)), accessibilityLabel: NSLocalizedString("SpeechViewController_Speak", comment: "Speak"))
                if isForBottomBar { self.bottomStartStopButton = button } else { self.startStopButton = button }
                barButtonArray.append(button)
            default:
                break
            }
        }

        return barButtonArray
    }

    func assignUpperButtons(novelID: String, novelType: NovelType, aliveButtonSettings:[SpeechViewButtonSetting]) {
        DispatchQueue.main.async {
            let nowWidth = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.bounds.width ?? UIScreen.main.bounds.width
            if abs(self.currentWindowWidth - nowWidth) < 0.0001 && self.isUpperRightButtonsChanged == false {
                return
            }
            let barButtonArray = self.createSpeechViewButtonArray(novelID: novelID, novelType: novelType, aliveButtonSettings: aliveButtonSettings, buttonSize: 28, isForBottomBar: false)

            let spacing: CGFloat = CGFloat(NovelSpeakerUtility.GetBarButtonItemSpacing())
            // 見積もりは通常の本文画面(SpeechViewController)と完全に同一にする。
            // (以前は WebView 側だけ 0.30/nowWidth 基準で、iPad 縦だと通常版より多く見積もって
            //  「…」が中央タブに潜って押せなくなっていた。飯村さん報告 2026-07-09)
            var maxButtons: Int = {
                let isPad = self.traitCollection.userInterfaceIdiom == .pad
                // ウインドウモードにおいて、画面の半分以下の幅だとタブバーは下になるぽい？のでそう判定させます
                let isUpperTabBarDisabled = NovelSpeakerUtility.IsNeedOverrideTabBarTraits() || (nowWidth < (UIScreen.main.bounds.width / 2))

                let buttonWidth: CGFloat = 28
                let totalUnitWidth = buttonWidth + spacing

                // 本文画面ではタイトルを潰してでもボタン数を優先する。タイトル幅は引かず、
                // iPad で上部タブバーがある場合のみ控えめな割合を絶対上限にする。
                let backButtonAndMargins: CGFloat = 88
                let widthFraction: CGFloat = (isPad && (isUpperTabBarDisabled != true)) ? 0.25 : 0.76
                let containerHardCap = UIScreen.main.bounds.width * widthFraction

                let usableWidth = nowWidth - backButtonAndMargins
                let containerMaxWidth = max(totalUnitWidth, min(usableWidth, containerHardCap))

                return max(1, Int(floor((containerMaxWidth + spacing) / totalUnitWidth)))
            }()
            // 同じ画面幅で「実測の結果ここまでしか入らない」と判明していれば、その上限まで下げる。
            // (見積もりが実レイアウトで溢れる=クリップするのを確実に防ぐための頭打ち。
            //  trimUpperButtonsToFitIfNeeded が設定する)
            if let fittedLimit = self.upperButtonFittedSlotLimit, abs(self.upperButtonFittedSlotLimitWidth - nowWidth) < 0.5 {
                maxButtons = min(maxButtons, fittedLimit)
            }
            // VoiceOver 環境下 であれば重なってしまってもよしとする
            if UIAccessibility.isVoiceOverRunning {
                // 表示されているボタンを直接タップして使うという場面が VoiceOver でもあるようなので、あえて重ねられるような仕様は封印しておきます
                //maxButtons = 999
            }

            let allButtons = barButtonArray
            guard let lastButton = allButtons.last else { return }

            var visibleButtons: [UIButton] = []
            var overflowButtons: [UIButton] = []

            if allButtons.count <= maxButtons {
                visibleButtons = allButtons
            } else {
                // lastButton を除いた残り
                let others = Array(allButtons.dropLast())

                // 表示可能数から lastButton と overflow 分を引く
                let capacityForOthers = maxButtons - 2

                if capacityForOthers > 0 {
                    // 後ろから優先して残す
                    let kept = others.suffix(capacityForOthers)
                    overflowButtons = Array(others.prefix(others.count - kept.count))
                    visibleButtons = Array(kept) + [lastButton]
                } else {
                    overflowButtons = others
                    visibleButtons = [lastButton]
                }
            }
            if !overflowButtons.isEmpty {
                let actions = overflowButtons.map { button in
                    UIAction(title: button.accessibilityLabel ?? "",
                             image: button.image(for: .normal)) { _ in
                        button.sendActions(for: .touchUpInside)
                    }
                }

                let menu = UIMenu(children: actions)

                let moreButton = UIButton(type: .system)
                moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
                moreButton.menu = menu
                moreButton.showsMenuAsPrimaryAction = true
                moreButton.accessibilityLabel = NSLocalizedString("SpeechViewController_moreButton_AccessibilityLabel", comment: "隠れたメニュー項目を表示する")
                // 他のボタンと同じ 28pt 固定にする。これが無いと「…」だけ intrinsic 幅
                // (Dynamic Type で変動)になり、幅見積もり(28pt×個数)と実レイアウトがズレる。
                moreButton.translatesAutoresizingMaskIntoConstraints = false
                let moreWidthConstraint = moreButton.widthAnchor.constraint(equalToConstant: 28)
                moreWidthConstraint.priority = UILayoutPriority(999)
                let moreHeightConstraint = moreButton.heightAnchor.constraint(equalToConstant: 28)
                moreHeightConstraint.priority = UILayoutPriority(999)
                NSLayoutConstraint.activate([moreWidthConstraint, moreHeightConstraint])

                visibleButtons.insert(moreButton, at: 0)
            }

            func isSameAction(lhs: UIButton, rhs: UIButton) -> Bool {
                let event = UIControl.Event.touchUpInside // 判定したいイベントを指定
                
                let lhsTargets = lhs.allTargets
                let rhsTargets = rhs.allTargets
                
                // ターゲットの数が違う場合は不一致
                guard lhsTargets == rhsTargets else { return false }
                
                // 各ターゲットに対するアクション名を比較
                for target in lhsTargets {
                    let lhsActions = lhs.actions(forTarget: target, forControlEvent: event)
                    let rhsActions = rhs.actions(forTarget: target, forControlEvent: event)
                    if lhsActions != rhsActions { return false }
                }
                
                return true
            }
            // 幅が前回と同じで、同じアクションのボタンが、同じ間隔で入っているならすることはないはず。
            // (間隔設定を変えた時に反映されるよう spacing も一致条件に加える)
            let epsilon: CGFloat = 0.000001
            if abs(self.currentWindowWidth - nowWidth) < epsilon && abs(self.currentBarButtonItemSpacing - spacing) < epsilon {
                if let currentStackView = self.navigationItem.rightBarButtonItem?.customView?.subviews.first as? UIStackView {
                    let subviews = currentStackView.arrangedSubviews.compactMap { $0 as? UIButton }
                    let buttons = visibleButtons
                    let isIdentical = subviews.count == buttons.count && zip(subviews, buttons).allSatisfy { isSameAction(lhs: $0, rhs: $1) }
                    if isIdentical {
                        return
                    }
                }
            }
            self.currentWindowWidth = nowWidth
            self.currentBarButtonItemSpacing = spacing
            self.isUpperRightButtonsChanged = false

            let stack = UIStackView()
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = spacing
            stack.translatesAutoresizingMaskIntoConstraints = false
            for button in visibleButtons {
                stack.addArrangedSubview(button)
            }
            
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let maxWidth = UIScreen.main.bounds.width * 0.76
            container.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth).isActive = true
            container.addSubview(stack)
            let barItem = UIBarButtonItem(customView: container)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                stack.topAnchor.constraint(equalTo: container.topAnchor),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            self.navigationItem.rightBarButtonItem = barItem
            // viewDidLayoutSubviews / viewDidAppear で実測補正するために参照を控えておく
            self.upperButtonContainerView = container
            self.upperButtonStackView = stack
            // customView がナビバーに取り込まれて実フレームが確定するのは次のレイアウト後なので、
            // 遅延+数回リトライで確実に実測補正する(読書画面 SpeechViewController と同じ理由)。
            self.scheduleUpperButtonTrim()
        }
    }

    // まだ実測できないうちは短い間隔で数回だけ再試行する(読書画面 SpeechViewController と同じ)。
    func scheduleUpperButtonTrim(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.15)) { [weak self] in
            guard let self = self else { return }
            if self.trimUpperButtonsToFitIfNeeded() == false && attempt < 10 {
                self.scheduleUpperButtonTrim(attempt: attempt + 1)
            }
        }
    }

    // 右上ボタン群が実際のナビバー幅に収まっているかを実レイアウト後に実測し、はみ出して
    // いる(=最右がクリップされて消える)場合は表示スロット数を1段階減らして溢れ分を「…」へ
    // 追い出す。収まるまで繰り返し呼ばれて収束する。読書画面と同一の仕組み。
    // 戻り値: 実測できたら true、まだ測れなければ false(呼び出し側が再試行)。
    @discardableResult
    func trimUpperButtonsToFitIfNeeded() -> Bool {
        if self.navigationController?.transitionCoordinator != nil { return false }
        guard let stack = self.upperButtonStackView,
              let navBar = self.navigationController?.navigationBar,
              navBar.window != nil else { return false }
        let n = stack.arrangedSubviews.count
        // 「…」+ 保護対象1個 の 2個未満はこれ以上減らせない
        guard n >= 2 else { return true }

        guard let overflow = NovelSpeakerUtility.UpperButtonBarLayout.rightmostButtonOverflow(navBar: navBar, stack: stack, container: self.upperButtonContainerView) else { return false }

        if overflow > 0.5 {
            // 過渡レイアウトの誤検出を防ぐため、2回連続で同じはみ出しを観測した時だけ削る(デバウンス)。
            guard let pending = self.upperButtonTrimPendingMeasure, pending.n == n, abs(pending.overflow - overflow) < 0.5 else {
                self.upperButtonTrimPendingMeasure = (n, overflow)
                return false // 再試行(次の実測)で確認する
            }
            self.upperButtonTrimPendingMeasure = nil
            let newLimit = n - 1
            if self.upperButtonFittedSlotLimit == nil || newLimit < (self.upperButtonFittedSlotLimit ?? Int.max) || abs(self.upperButtonFittedSlotLimitWidth - self.currentWindowWidth) >= 0.5 {
                self.upperButtonFittedSlotLimit = newLimit
                self.upperButtonFittedSlotLimitWidth = self.currentWindowWidth
                self.isUpperRightButtonsChanged = true
                self.forceUpdateUpperButtons()
            }
        } else {
            self.upperButtonTrimPendingMeasure = nil
        }
        return true
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
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
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

    func clearSearchView(){
        if let searchView = self.searchView {
            self.searchView = nil
            DispatchQueue.main.async {
                searchView.removeFromSuperview()
            }
        }
    }
    
    func searchResultAnnounceIfVoiceOverEnabled(foundString:String){
        guard UIAccessibility.isVoiceOverRunning == true else { return }
        let announceString = String(format: NSLocalizedString("SpeechViewController_SearchByText_Found_Announce_to_VoiceOverUser_Formated", comment: "%@"), foundString)
        StorySpeaker.shared.AnnounceSpeech(text: announceString)
    }
    
    func prevSearchByText(searchString:String){
        let searchStringCount = searchString.unicodeScalars.count
        self.webSpeechTool.getSelectedLocation { location in
            let targetText:String
            if let targetLocation = location, targetLocation > 0 {
                targetText = self.webViewDisplayWholeText?.NiftySubstring(from: 0, to: targetLocation - 1) ?? ""
            }else{
                targetText = ""
            }
            guard let nextRange = targetText.range(of: searchString, options: .backwards) else {
                DispatchQueue.main.async {
                    NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("SpeechViewController_SearchByText_NotFound", comment: "ページ内に検索文字列を発見できませんでした。"))
                }
                return
            }
            let targetLocation = max((targetText.distance(from: targetText.startIndex, to: nextRange.lowerBound) as Int), 0)
            self.webSpeechTool.highlightSpeechLocation(location: targetLocation, length: searchStringCount) {
                self.webSpeechTool.scrollToIndex(location: targetLocation, length: 1, scrollRatio: 0.3)
            }

            if let foundString = self.webViewDisplayWholeText?.NiftySubstring(from: targetLocation, to: targetLocation + min(searchStringCount + 20, 30)) {
                self.searchResultAnnounceIfVoiceOverEnabled(foundString: foundString)
            }
        }
    }
    func nextSearchByText(searchString:String){
        print("nextSearchByText in.")
        let searchStringCount = searchString.unicodeScalars.count
        guard let currentText = self.webViewDisplayWholeText else { return }
        print("currentText.count: \(currentText.count)")
        self.webSpeechTool.getSelectedLocation { location in
            print("self.webSpeechTool.getSelectedLocation: \(location)")
            let targetText:String, currentLocation:Int
            if location != nil && currentText.unicodeScalars.count > location ?? 0 {
                currentLocation = location!
                targetText = currentText.NiftySubstring(from: currentLocation, to: currentText.unicodeScalars.count)
            }else{
                currentLocation = 0
                targetText = currentText
            }
            guard let nextRange = targetText.range(of: searchString) else {
                DispatchQueue.main.async {
                    NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("SpeechViewController_SearchByText_NotFound", comment: "ページ内に検索文字列を発見できませんでした。"))
                }
                return
            }
            print("nextRange: \(nextRange)")
            let targetLocation = (targetText.distance(from: targetText.startIndex, to: nextRange.lowerBound) as Int) + currentLocation
            print("targetLocation: \(targetLocation)")
            self.webSpeechTool.highlightSpeechLocation(location: targetLocation, length: searchStringCount) {
                self.webSpeechTool.scrollToIndex(location: targetLocation, length: 1, scrollRatio: 0.3)
            }

            if let foundString = self.webViewDisplayWholeText?.NiftySubstring(from: targetLocation, to: targetLocation + min(searchStringCount + 20, 30)) {
                self.searchResultAnnounceIfVoiceOverEnabled(foundString: foundString)
            }
        }
    }
    
    @objc func searchByTextButtonClicked(_ sender: UIBarButtonItem) {
        if self.searchView != nil {
            clearSearchView()
            return
        }
        if StorySpeaker.shared.isPlayng {
            RealmUtil.RealmBlock { realm in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession:true)
            }
        }
        guard let topLevelViewController = self.parent?.parent else { return }
        self.searchView = SearchFloatingView.generate(parentView: topLevelViewController.view, firstText: searchTextCache, leftButtonClickHandler: { searchString in
            guard let searchString = searchString else { return }
            self.prevSearchByText(searchString: searchString)
        }, rightButtonClickHandler: { searchString in
            guard let searchString = searchString else { return }
            self.nextSearchByText(searchString: searchString)
        }, isDeletedHandler: {
            self.searchView = nil
        })
    }

    @objc func shareButtonClicked(_ sender: UIBarButtonItem) {
        let storyID = StorySpeaker.shared.storyID
        NovelSpeakerUtility.ShareStory(viewController: self, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), barButton: self.shareButtonItem)
    }
    
    @objc func urlRefreshButtonClicked(_ sender: UIBarButtonItem) {
        let storyID = StorySpeaker.shared.storyID
        NovelDownloadQueue.shared.addQueue(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))
    }
    @objc func openCurrentWebPageButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let urlString = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID)?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    @objc func safariButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            let storyID = StorySpeaker.shared.storyID
            guard storyID.count > 0, let urlString = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    
    func CheckFolderAndStartSpeech() {
        RealmUtil.RealmBlock { realm in
            self.disableCurrentReadingStoryChangeFloatingButton()
            self.webSpeechTool.getSelectedLocation { location in
                print("startStopButtonClicked selectedLocation: \(location ?? -1)")
                RealmUtil.RealmBlock { realm in
                    if let location = location {
                        StorySpeaker.shared.setReadLocationWith(realm: realm, location: location)
                    }
                    func runNextSpeech(nextFolder:RealmNovelTag?){
                        StorySpeaker.shared.targetFolderNameForGoToNextSelectedFolderdNovel = nextFolder?.name
                        self.clearSearchView()
                        RealmUtil.RealmBlock { realm in
                            StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面(Speakボタンを押した 又は 本棚画面で「▶︎ 再生:〜」を選択した 又は 次のフォルダの小説に移行した).\(#function)", isNeedRepeatSpeech: true)
                            self.checkDummySpeechFinished()
                        }
                    }
                    let storyID = StorySpeaker.shared.storyID
                    if let repeatType = RealmGlobalState.GetInstanceWith(realm: realm)?.repeatSpeechType, repeatType == .GoToNextSelectedFolderdNovel, let folderArray = RealmNovelTag.SearchWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), type: RealmNovelTag.TagType.Folder) {
                        let folderArray = Array(folderArray)
                        if folderArray.count == 1, let folder = folderArray.first {
                            runNextSpeech(nextFolder: folder)
                            return
                        }else if folderArray.count > 1 {
                            EurekaPopupViewController.RunSimplePopupViewController(formSetupMethod: { vc in
                                let section = Section(NSLocalizedString("SpeechViewController_SelectFolder_Title", comment: "連続再生するフォルダを選択"))
                                for folder in folderArray {
                                    section <<< LabelRow() {
                                        $0.title = folder.name
                                        $0.cell.textLabel?.numberOfLines = 0
                                        $0.cell.accessibilityTraits = .button
                                    }.onCellSelection({ (_, row) in
                                        runNextSpeech(nextFolder: folder)
                                        vc.close(animated: true, completion: nil)
                                    })
                                }
                                vc.form +++ section
                                vc.form +++ Section()
                                <<< LabelRow() {
                                    $0.title = NSLocalizedString("SpeechViewController_NotUseNextSpeechNovel", comment: "続けて再生を使わずに開始")
                                    $0.cell.textLabel?.numberOfLines = 0
                                    $0.cell.accessibilityTraits = .button
                                }.onCellSelection({ (_, row) in
                                    runNextSpeech(nextFolder: nil)
                                    vc.close(animated: true, completion: nil)
                                })
                                <<< LabelRow() {
                                    $0.title = NSLocalizedString("Cancel", comment: "Cancel")
                                    $0.cell.textLabel?.numberOfLines = 0
                                    $0.cell.accessibilityTraits = .button
                                }.onCellSelection({ (_, row) in
                                    vc.close(animated: true, completion: nil)
                                })
                            }, parentViewController: self, animated: true, completion: nil)
                            return
                        }
                    }
                    runNextSpeech(nextFolder: nil)
                }
            }
        }
    }

    @objc func startStopButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            if StorySpeaker.shared.isPlayng {
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
            }else{
                self.CheckFolderAndStartSpeech()
            }
        }
    }
    @objc func skipBackwardButtonClicked(_ sender: UIBarButtonItem) {
        if StorySpeaker.shared.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: false) {
                    StorySpeaker.shared.SkipBackward(realm: realm, length: 30) {
                        self.clearSearchView()
                        RealmUtil.RealmBlock { realm in
                            StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面.\(#function)", isNeedRepeatSpeech: true)
                        }
                    }
                }
            }
        }
    }
    @objc func skipForwardButtonClicked(_ sender: UIBarButtonItem) {
        if StorySpeaker.shared.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: false) {
                    StorySpeaker.shared.SkipForward(realm: realm, length: 30) {
                        self.clearSearchView()
                        StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面.\(#function)", isNeedRepeatSpeech: true)
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

    // 「他の小説にこのページを追加する」。通常の本文画面(SpeechViewController)と同一実装。
    @objc func addPageToOtherNovelButtonClicked(_ sender: Any) {
        let storyID = StorySpeaker.shared.storyID
        let currentNovelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        let story:Story? = RealmUtil.RealmBlock { (realm) -> Story? in
            return RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID)
        }
        guard let story = story else { return }
        let content = story.content
        let subtitle = story.subtitle
        MultipleNovelIDSelectorViewController.PushSingleSelector(
            parent: self,
            excludeNovelID: currentNovelID,
            title: NSLocalizedString("SpeechViewButtonType_AddPageToOtherNovel", comment: "他の小説にこのページを追加する"),
            confirmMessage: { novelTitle in
                String(format: NSLocalizedString("AddPageToOtherNovel_ConfirmMessage", comment: "「%@」にこのページを追加しますか？"), novelTitle)
            },
            onConfirmed: { [weak self] targetNovelID in
                guard let self = self else { return }
                let result = NovelSpeakerUtility.AppendPageToNovelTail(targetNovelID: targetNovelID, content: content, subtitle: subtitle)
                let message = result ? NSLocalizedString("AddPageToOtherNovel_Success", comment: "ページを追加しました。") : NSLocalizedString("AddPageToOtherNovel_Failure", comment: "ページの追加に失敗しました。")
                NiftyUtility.EasyDialogMessageDialog(viewController: self, message: message)
            })
    }

    @objc func chapterSliderValueChanged(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        let storyID = StorySpeaker.shared.storyID
        let chapterNumber = Int(self.chapterSlider.value + 0.5)
        let targetStoryID = RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), chapterNumber: chapterNumber)
        //self.chapterSlider.value = Float(chapterNumber)
        RealmUtil.RealmBlock { (realm) -> Void in
            if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: targetStoryID) {
                StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
            }
        }
    }
    
    @objc func previousChapterButtonClicked(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadPreviousChapter(realm: realm)
        }
    }
    @objc func nextChapterButtonClicked(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadNextChapter(realm: realm)
        }
    }

    
    func assignHideToToggleInterfaceButton() {
        guard let toggleInterfaceButton = self.toggleInterfaceButton else { return }
        DispatchQueue.main.async {
            if #available(iOS 13.0, *), let img = UIImage(systemName: "dock.arrow.down.rectangle", withConfiguration:  UIImage.SymbolConfiguration(pointSize: 24, weight: .light, scale: .default)) {
                toggleInterfaceButton.setImage(img, for: .normal)
            } else {
                toggleInterfaceButton.setTitle(NSLocalizedString("WebSpechViewController_ToggleInterfaceButton_Hide_Title", comment: "本文のみへ"), for: .normal)
                let (foregroundColor, backgroundColor) = self.getForegroundBackgroundColor()
                toggleInterfaceButton.backgroundColor = foregroundColor
                toggleInterfaceButton.setTitleColor(backgroundColor, for: .normal)
            }
        }
    }
    func assignDisplayToToggleInterfaceButton() {
        guard let toggleInterfaceButton = self.toggleInterfaceButton else { return }
        DispatchQueue.main.async {
            if #available(iOS 13.0, *), let img = UIImage(systemName: "dock.arrow.up.rectangle", withConfiguration:  UIImage.SymbolConfiguration(pointSize: 24, weight: .light, scale: .default)) {
                toggleInterfaceButton.setImage(img, for: .normal)
            } else {
                toggleInterfaceButton.setTitle(NSLocalizedString("WebSpechViewController_ToggleInterfaceButton_Display_Title", comment: "ボタン表示"), for: .normal)
                let (foregroundColor, backgroundColor) = self.getForegroundBackgroundColor()
                toggleInterfaceButton.backgroundColor = foregroundColor
                toggleInterfaceButton.setTitleColor(backgroundColor, for: .normal)
            }
        }
    }

    @objc func toggleInterfaceButtonClicked(_ sender:UIButton){
        func highlight(overrideLocation:Int?, scrollRatio:Double?){
            RealmUtil.RealmBlock { realm in
                guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: StorySpeaker.shared.storyID) else { return }
                let readLocation = story.readLocation(realm: realm)
                DispatchQueue.main.async {
                    self.webSpeechTool.highlightSpeechLocation(location: readLocation, length: 1) {
                        if let overrideLocation = overrideLocation, overrideLocation > 0 {
                            self.webSpeechTool.scrollToIndex(location: overrideLocation, length: 1, scrollRatio: scrollRatio ?? 0.5)
                        }else{
                            self.webSpeechTool.scrollToIndex(location: readLocation, length: 1, scrollRatio: 0.3)
                        }
                    }
                }
            }
        }
        print("width: \(self.textWebView?.frame.width ?? -1)")
        let xRaito:Double
        let yRaito:Double
        let scrollRaito:Double
        if self.currentViewTypeCache == .webViewVertical || self.currentViewTypeCache == .webViewVertical2Column {
            xRaito = 0.99
            yRaito = 0.5
            scrollRaito = 0.95
        }else{
            xRaito = 0.5
            yRaito = 0.03
            scrollRaito = 0.95
        }
        self.webSpeechTool.getCurrentDisplayLocation(xRatio: xRaito, yRatio: yRaito) { currentDisplayLocation in
            if((self.navigationController?.isNavigationBarHidden ?? false) == false){
                self.hideTopAndDownComponents(animated: false, animateCompletion: { highlight(overrideLocation: currentDisplayLocation, scrollRatio: scrollRaito) })
            }else{
                self.displayTopAndDownComponents(animated: false, animateCompletion: { highlight(overrideLocation: currentDisplayLocation, scrollRatio: scrollRaito) })
            }
        }
    }
    
    @objc func leftSwipe(_ sender: UISwipeGestureRecognizer) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadNextChapter(realm: realm)
        }
    }
    @objc func rightSwipe(_ sender: UISwipeGestureRecognizer) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.LoadPreviousChapter(realm: realm)
        }
    }

    
    //MARK: StorySpeakerDeletgate handler
    func storySpeakerStartSpeechEvent(storyID:String) {
        DispatchQueue.main.async {
            self.clearSearchView()
            self.startStopButton?.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            self.startStopButton?.accessibilityLabel = NSLocalizedString("SpeechViewController_Stop", comment: "Stop")
            self.skipBackwardButtonItem?.isEnabled = true
            self.skipForwardButtonItem?.isEnabled = true
            self.removeCustomUIMenu()
        }
    }
    func storySpeakerStopSpeechEvent(storyID:String) {
        DispatchQueue.main.async {
            self.startStopButton?.setImage(UIImage(systemName: "play.fill"), for: .normal)
            self.startStopButton?.accessibilityLabel = NSLocalizedString("SpeechViewController_Speak", comment: "Speak")
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
        // 自分でスクロールした直後はスクロールだけ止める。
        // ハイライト(canvas)はそのまま動かして構わない(スクロールしないので支障がない)。
        // ただし selection の張り替えは JS 側(SetKeepUserSelection)で止めてある。
        if self.isScrollFollowSuspended {
            self.scrollFollowPendingLocation = location
            self.webSpeechTool.highlightSpeechLocation(location: location, length: range.length, completionHandler: nil)
            return
        }
        self.webSpeechTool.highlightSpeechLocation(location: location, length: range.length) {
            self.webSpeechTool.scrollToIndex(location: location, length: 1, scrollRatio: 0.3)
        }
    }
    func storySpeakerStoryChanged(story:Story) {
        self.readingChapterStoryUpdateDate = Date()
        // ページが変わると表示位置も溜めていた発話位置も意味を失うので一時停止は取り消す。
        NiftyUtility.DispatchSyncMainQueue {
            self.cancelScrollFollowSuspend()
        }
        self.speakerDisplayWholeText = StorySpeaker.shared.GenerateWholeDisplayText()
        self.loadStoryWithoutStorySpeakerWith(story: story)
        DispatchQueue.main.async {
            self.observeStory(storyID: story.storyID)
            self.observeNovel(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: story.storyID))
        }
        self.applyChapterListChange()
        if self.isNeedResumeSpeech {
            self.isNeedResumeSpeech = false
            DispatchQueue.main.async {
                self.CheckFolderAndStartSpeech()
            }
        }
    }
}

// MARK: 発話位置への自動スクロールの一時停止
extension WebSpeechViewController {
    // 設定されている「手動スクロールで止める秒数」。0 ならこの機能自体を使わない。
    func scrollFollowSuspendSecond() -> Int {
        return RealmUtil.RealmBlock { (realm) -> Int in
            return RealmGlobalState.GetInstanceWith(realm: realm)?.scrollFollowSuspendSecond ?? 0
        }
    }

    // second 秒だけ自動スクロールを止める。既に止まっていれば測り直す。
    func suspendScrollFollow(second:Int) {
        if second <= 0 { return }
        self.scrollFollowSuspendTimer?.invalidate()
        self.scrollFollowSuspendTimer = nil
        self.isScrollFollowSuspended = true
        self.scrollFollowSuspendTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(second), repeats: false) { [weak self] _ in
            self?.resumeScrollFollow()
        }
    }

    // 一時停止を取り消す(溜めていた発話位置へは追いつかない)。
    func cancelScrollFollowSuspend() {
        self.scrollFollowSuspendTimer?.invalidate()
        self.scrollFollowSuspendTimer = nil
        self.scrollFollowPendingLocation = nil
        self.isScrollFollowSuspended = false
    }

    // 自動スクロールを再開する。止まっている間に発話が進んでいれば、その位置へ追いつく。
    func resumeScrollFollow() {
        self.scrollFollowSuspendTimer?.invalidate()
        self.scrollFollowSuspendTimer = nil
        if self.isScrollFollowSuspended == false { return }
        self.isScrollFollowSuspended = false
        guard let location = self.scrollFollowPendingLocation else { return }
        self.scrollFollowPendingLocation = nil
        self.webSpeechTool.highlightSpeechLocation(location: location, length: 1) {
            self.webSpeechTool.scrollToIndex(location: location, length: 1, scrollRatio: 0.3)
        }
    }

    // 長押しは OS 標準の選択用ジェスチャと同時に動いてもらう必要がある。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === self.speakFromHereLongPressRecognizer
    }

    @objc func handleSpeakFromHereLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began, StorySpeaker.shared.isPlayng else { return }
        // viewDidLoad で設定した UIMenuController.shared.menuItems が長押しの時点では
        // 空になっている事があるので貼り直す(通常版と同じ理由)。
        self.setCustomUIMenu()
        // 一時停止していないと、選んだ位置が次の発話位置更新で上書きされてしまうので、
        // 長押しの開始時点で一時停止を始める(秒数は手動スクロール時と同じ設定値を使う)。
        self.suspendScrollFollow(second: self.scrollFollowSuspendSecond())
    }

    // 発話を止めずに、選択されている位置へ読み上げ位置だけを移す。
    @objc func speakFromHere(sender: UIMenuItem) {
        self.webSpeechTool.getSelectedLocation { location in
            guard let location = location, location >= 0 else { return }
            NiftyUtility.DispatchSyncMainQueue {
                RealmUtil.RealmBlock { (realm) -> Void in
                    StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: false) {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            StorySpeaker.shared.setReadLocationWith(realm: realm, location: location)
                        }
                        self.clearSearchView()
                        // 連打で AVSpeechSynthesizer が固着するのを避けるため、再生再開はデバウンス経由で行う。
                        StorySpeaker.shared.scheduleSpeechRestartAfterSeek(callerInfo: "小説本文画面(WebView)の長押しメニューの「ここから発話開始」.\(#function)")
                    }
                }
            }
            // 移動先へすぐ追従してほしいので、一時停止は解除する。
            DispatchQueue.main.async {
                self.cancelScrollFollowSuspend()
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
        // 「全てを選択する」は常にメニュー項目として登録し、表示可否は canPerformAction で(長押しメニュー削減設定に従って)判定する。
        let selectAllMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_SelectAllText", comment: "全てを選択する"), action: #selector(selectAllText(sender:)))
        // 「ここから発話開始」は常に登録しておいて、表示可否は canPerformAction に任せる
        // (発話中 かつ 自動スクロール一時停止中 の時だけ表示される)。
        let speakFromHereMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_SpeakFromHere", comment: "ここから発話開始"), action: #selector(speakFromHere(sender:)))
        let menuItems:[UIMenuItem] = [speechModMenuItem, speechModForThisNovelMenuItem, checkSpeechTextMenuItem, selectAllMenuItem, speakFromHereMenuItem]
        menuController.menuItems = menuItems
        #if targetEnvironment(macCatalyst)
        #if false
        let intraction = UIContextMenuInteraction(delegate: self)
        self.textWebView?.addInteraction(intraction)
        #endif
        #endif
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
            print("startIndex: \(String(describing: startIndex)), endIndex: \(String(describing: endIndex))")
            guard let startIndex = startIndex, let endIndex = endIndex, startIndex <= endIndex else { return }
            DispatchQueue.main.async {
                let speechText = StorySpeaker.shared.GenerateSpeechTextFrom(displayTextRange: NSMakeRange(startIndex, endIndex - startIndex))
                NiftyUtility.EasyDialogLongMessageDialog(viewController: self, message: speechText)
            }
        }
    }

    // WKWebView 上の本文を全選択する(標準の「すべてを選択」が出ないため独自に提供)。
    // プログラムによる選択では標準の編集メニュー(コピー等)が自動で出ないので、
    // 選択範囲の矩形を取得して自前で編集メニューを提示する。
    @objc func selectAllText(sender: UIMenuItem) {
        guard let webView = self.textWebView else { return }
        // 全選択し、選択範囲の矩形(getBoundingClientRect: ビューポート座標)を JSON で返す。
        let js = "(function(){var r=document.createRange();r.selectNodeContents(document.body);var s=window.getSelection();s.removeAllRanges();s.addRange(r);try{var rc=s.getRangeAt(0).getBoundingClientRect();return JSON.stringify({x:rc.left,y:rc.top,w:rc.width,h:rc.height});}catch(e){return \"\";}})()"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Double],
                  let x = dict["x"], let y = dict["y"], let w = dict["w"], let h = dict["h"] else { return }
            // getBoundingClientRect はビューポート座標なので、そのまま WKWebView 自身の座標系として扱える(ズーム無し前提)。
            let rectInWebView = CGRect(x: x, y: y, width: w, height: h)
            DispatchQueue.main.async {
                self.presentEditMenu(webView: webView, rectInWebView: rectInWebView)
            }
        }
    }

    // 選択範囲の矩形に編集メニュー(コピー等)を提示する。
    // WKWebView の copy: を効かせるため、メニューは WKWebView に紐付けて(= WKWebView の
    // レスポンダ連鎖を辿らせて)提示する。iOS16+ は UIEditMenuInteraction、それ未満は UIMenuController。
    private func presentEditMenu(webView: WKWebView, rectInWebView: CGRect) {
        // 選択が無い(全選択で何も選べなかった)場合は矩形が空になるので出さない。
        guard rectInWebView.width > 0.5 || rectInWebView.height > 0.5 else { return }
        if #available(iOS 16.0, *) {
            let interaction: UIEditMenuInteraction
            if let existing = self.selectionEditMenuInteraction as? UIEditMenuInteraction {
                interaction = existing
                if interaction.view !== webView {
                    interaction.view?.removeInteraction(interaction)
                    webView.addInteraction(interaction)
                }
            } else {
                interaction = UIEditMenuInteraction(delegate: nil)
                webView.addInteraction(interaction)
                self.selectionEditMenuInteraction = interaction
            }
            let point = CGPoint(x: rectInWebView.midX, y: max(rectInWebView.minY, 0))
            let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: point)
            interaction.presentEditMenu(with: config)
        } else {
            let menu = UIMenuController.shared
            webView.becomeFirstResponder()
            menu.showMenu(from: webView, rect: rectInWebView)
        }
    }

    // 長押しメニュー削減が ON の時は menuItemsNotRemoved に .selectAll がある時だけ表示する。OFF なら常に表示。
    func shouldShowSelectAllMenuItem() -> Bool {
        return RealmUtil.RealmBlock { (realm) -> Bool in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return true }
            if globalState.isMenuItemIsAddNovelSpeakerItemsOnly {
                return globalState.menuItemsNotRemoved.contains(MenuItemsNotRemovedType.selectAll.rawValue)
            }
            return true
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 発話中は「ここから発話開始」以外の長押しメニューを出さない(通常版と同じ理由)。
        if StorySpeaker.shared.isPlayng {
            if action == #selector(self.speakFromHere(sender:)) {
                return self.isScrollFollowSuspended
            }
            return false
        }
        if action == #selector(self.speakFromHere(sender:)) {
            return false
        }
        if action == #selector(self.selectAllText(sender:)) {
            return shouldShowSelectAllMenuItem()
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

#if targetEnvironment(macCatalyst)
#if false
extension WebSpeechViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestActions in
            
        })
    }
    
}
#endif
#endif // targetEnvironment(macCatalyst)
