//
//  SpeechViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/19.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift
import IceCream
import Eureka

class SpeechViewController: UIViewController, StorySpeakerDeletgate, RealmObserverResetDelegate /*, UIEditMenuInteractionDelegate */ {
    
    public var storyID : String? = nil
    public var isNeedResumeSpeech : Bool = false
    public var isNeedUpdateReadDate : Bool = true

    @IBOutlet weak var textView : UITextView!
    @IBOutlet weak var previousChapterButton : UIButton!
    @IBOutlet weak var nextChapterButton : UIButton!
    @IBOutlet weak var chapterSlider : UISlider!
    @IBOutlet weak var chapterPositionLabel : UILabel!
    @IBOutlet weak var chapterPositionLabelWidthConstraint : NSLayoutConstraint!
    
    var startStopButtonItem:UIBarButtonItem? = nil
    var shareButtonItem:UIBarButtonItem? = nil
    var skipBackwardButtonItem:UIBarButtonItem? = nil
    var skipForwardButtonItem:UIBarButtonItem? = nil
    var showTableOfContentsButtonItem:UIBarButtonItem? = nil

    var novelObserverToken:NotificationToken? = nil
    var novelObserverNovelID:String = ""
    var storyObserverToken:NotificationToken? = nil
    var storyObserverBulkStoryID:String = ""
    var displaySettingObserverToken:NotificationToken? = nil
    var globalStateObserverToken:NotificationToken? = nil
    var readingChapterStoryUpdateDate:Date = Date()
    var storyTextAttribute:[NSAttributedString.Key: Any] = [:]
    var displayTextCache:String = ""
    var leftSwipeRecgnizer:UISwipeGestureRecognizer = UISwipeGestureRecognizer()
    var rightSwipeRecgnizer:UISwipeGestureRecognizer = UISwipeGestureRecognizer()
    
    var searchView:SearchFloatingView? = nil
    var searchTextCache = ""

    let storySpeaker = StorySpeaker.shared
    
    var lastChapterNumber:Int = -1
    
    var currentReadStoryIDChangeAlertFloatingButton:FloatingButton? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        storySpeaker.AddDelegate(delegate: self)
        // Do any additional setup after loading the view.
        initWidgets()
        if let storyID = storyID {
            let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
            DispatchQueue.global(qos: .background).async {
                NovelSpeakerUtility.CheckAndRecoverStoryCount(novelID: novelID)
            }
            RealmUtil.RealmBlock { (realm) -> Void in
                if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID){
                    loadNovel(novelID: novel.novelID, novelTitle: novel.title, novelType: novel.type, aliveButtonSettings: RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() ?? SpeechViewButtonSetting.defaultSetting)
                }
                if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) {
                    self.storySpeaker.SetStory(story: story, withUpdateReadDate: isNeedUpdateReadDate)
                }else{
                    self.applyStoryText(
                        text: NSLocalizedString(
                            "SpeechViewController_LoadingFailed_GlobalStateIsNull",
                            comment: "本文の読み込みに失敗しました。小説のページを読み込めませんでした。"
                        )
                    )
                }
            }
            self.observeStory(storyID: storyID)
        }else{
            textView.text = NSLocalizedString("SpeechViewController_ContentReadFailed", comment: "文書の読み込みに失敗しました。")
        }
        observeDispaySetting()
        observeGlobalState()
        registNotificationCenter()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        searchTextCache = ""
        
        /* // TODO: UIEditMenuInteraction をサポートする場合用。「設定タブ」→「本文中の長押しメニュー項目を減らす」がうまく実装できていないの一旦封印しておきます。
        if #available(iOS 16.0, *) {
            let editMenuInteraction = UIEditMenuInteraction(delegate: self)
            self.textView.addInteraction(editMenuInteraction)
        }
         */
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.textView.becomeFirstResponder()
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                if globalState.isEnableSwipeOnStoryView {
                    self.assignSwipeRecognizer()
                }else{
                    self.removeSwipeRecognizer()
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.clearSearchView()
    }
    
    deinit {
        StopObservers()
        self.unregistNotificationCenter()
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }

    // 表示される直前に呼ばれる
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }
    
    // 非表示になる直前に呼ばれる
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resumeTheme()
        let range = self.textView.selectedRange
        if self.storySpeaker.isPlayng == false && range.location >= 0 && range.location < self.textView.text.count {
            RealmUtil.RealmBlock { (realm) -> Void in
                self.storySpeaker.setReadLocationWith(realm: realm, location: range.location)
            }
        }
        if let floatingButton = self.currentReadStoryIDChangeAlertFloatingButton {
            floatingButton.hide()
            self.currentReadStoryIDChangeAlertFloatingButton = nil
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
        guard let storyID = self.storyID else { return }
        let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        observeStory(storyID: storyID)
        observeNovel(novelID: novelID)
        observeGlobalState()
    }
    
    func initWidgets() {
        self.applyStoryText(text: NSLocalizedString("SpeechViewController_NowLoadingText", comment: "本文を読込中……"))
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else {
                self.applyStoryText(
                    text: NSLocalizedString(
                        "SpeechViewController_LoadingFailed_GlobalStateIsNull",
                        comment: "本文の読み込みに失敗しました。全体設定を読み込めませんでした。"
                    )
                )
                return
            }
            if let displaySetting = globalState.defaultDisplaySettingWith(realm: realm) {
                //textView.font = displaySetting.font
                updateStoryTextAttribute(font: displaySetting.font, lineSpacing: displaySetting.lineSpacingDisplayValue)
            }
        }
        
        self.leftSwipeRecgnizer = UISwipeGestureRecognizer(target: self, action: #selector(leftSwipe(_:)))
        self.leftSwipeRecgnizer.direction = .left
        self.rightSwipeRecgnizer = UISwipeGestureRecognizer(target: self, action: #selector(rightSwipe(_:)))
        self.rightSwipeRecgnizer.direction = .right
        
        previousChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        nextChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        chapterPositionLabel.adjustsFontForContentSizeCategory = true
        
        previousChapterButton.accessibilityLabel = NSLocalizedString("SpeechViewController_PreviousChapterButton_VoiceOverTitle", comment: "前のページ")
        nextChapterButton.accessibilityLabel = NSLocalizedString("SpeechViewController_NextChapterButton_VoiceOverTitle", comment: "次のページ")

        setCustomUIMenu()
    }
    
    func assignSwipeRecognizer() {
        self.textView.addGestureRecognizer(self.leftSwipeRecgnizer)
        self.textView.addGestureRecognizer(self.rightSwipeRecgnizer)
    }
    func removeSwipeRecognizer() {
        self.textView.removeGestureRecognizer(self.leftSwipeRecgnizer)
        self.textView.removeGestureRecognizer(self.rightSwipeRecgnizer)
    }
    
    func setCustomUIMenu() {
        let menuController = UIMenuController.shared
        let speechModMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettings", comment: "読み替え辞書へ登録"), action: #selector(setSpeechModSetting(sender:)))
        let speechModForThisNovelMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettingsForThisNovel", comment: "この小説用の読み替え辞書へ登録"), action: #selector(setSpeechModForThisNovelSetting(sender:)))
        let checkSpeechTextMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddCheckSpeechText", comment: "読み替え後の文字列を確認する"), action: #selector(checkSpeechText(sender:)))
        let menuItems:[UIMenuItem] = [speechModMenuItem, speechModForThisNovelMenuItem, checkSpeechTextMenuItem]
        menuController.menuItems = menuItems
    }
    func removeCustomUIMenu() {
        let menuController = UIMenuController.shared
        menuController.menuItems = []
    }
    
    func assignUpperButtons(novelID: String, novelType:NovelType, aliveButtonSettings:[SpeechViewButtonSetting]) {
        var barButtonArray:[UIBarButtonItem] = []
        
        for buttonSetting in aliveButtonSettings {
            if buttonSetting.isOn == false { continue }
            switch buttonSetting.type {
            case .openCurrentWebPage:
                let webPageButton = UIBarButtonItem(image: UIImage(named: "earth"), style: .plain, target: self, action: #selector(openCurrentWebPageButtonClicked(_:)))
                webPageButton.accessibilityLabel = NSLocalizedString("SpeechViewController_CurrentWebPageButton_VoiceOverTitle", comment: "現在のページをWeb取込タブで開く")
                if novelType == .URL {
                    barButtonArray.append(webPageButton)
                }
            case .openWebPage:
                let webPageButton = UIBarButtonItem(image: UIImage(named: "earth"), style: .plain, target: self, action: #selector(safariButtonClicked(_:)))
                webPageButton.accessibilityLabel = NSLocalizedString("SpeechViewController_WebPageButton_VoiceOverTitle", comment: "Web取込タブで開く")
                if novelType == .URL {
                    barButtonArray.append(webPageButton)
                }
            case .reload:
                if novelType == .URL || (novelType == .UserCreated && NovelSpeakerUtility.IsRegisteredOuterNovel(novelID: novelID)) {
                    barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(urlRefreshButtonClicked(_:))))
                }
            case .share:
                if novelType == .URL {
                    let shareButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action:   #selector(shareButtonClicked(_:)))
                    self.shareButtonItem = shareButtonItem
                    barButtonArray.append(shareButtonItem)
                }
            case .search:
                barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(searchButtonClicked(_:))))
            case .searchByText:
                let button = UIBarButtonItem(image: UIImage(systemName: "doc.text.magnifyingglass"), style: .plain, target: self, action: #selector(searchByTextButtonClicked(_:)))
                button.accessibilityLabel = NSLocalizedString("SpeechViewController_SearchByTextButton_AccessibilityLabel", comment: "ページ内を検索")
                barButtonArray.append(button)
            case .edit:
                barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Edit", comment: "編集"), style: .plain, target: self, action: #selector(editButtonClicked(_:))))
            case .detail:
                barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Detail", comment: "詳細"), style: .plain, target: self, action: #selector(detailButtonClicked(_:))))
            case .backup:
                barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_BackupButton", comment: "バックアップ"), style: .plain, target: self, action: #selector(backupButtonClicked(_:))))
                break
            case .skipBackward:
                let skipBackwardButtonItem:UIBarButtonItem
                if #available(iOS 13.0, *) {
                    skipBackwardButtonItem = UIBarButtonItem(image: UIImage(systemName: "gobackward.30"), style: .plain, target: self, action: #selector(skipBackwardButtonClicked(_:)))
                    skipBackwardButtonItem.accessibilityLabel = NSLocalizedString("SpeechViewController_SkipBackwardButtonTitle", comment: "巻き戻し")
                } else {
                    skipBackwardButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_SkipBackwardButtonTitle", comment: "巻き戻し"), style: .plain, target: self, action: #selector(skipBackwardButtonClicked(_:)))
                }
                skipBackwardButtonItem.isEnabled = false
                self.skipBackwardButtonItem = skipBackwardButtonItem
                barButtonArray.append(skipBackwardButtonItem)
            case .skipForward:
                let skipForwardButtonItem:UIBarButtonItem
                if #available(iOS 13.0, *) {
                    skipForwardButtonItem = UIBarButtonItem(image: UIImage(systemName: "goforward.30"), style: .plain, target: self, action: #selector(skipForwardButtonClicked(_:)))
                    skipForwardButtonItem.accessibilityLabel = NSLocalizedString("SpeechViewController_SkipForwardButtonTitle", comment: "少し先へ")
                } else {
                    skipForwardButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_SkipForwardButtonTitle", comment: "少し先へ"), style: .plain, target: self, action: #selector(skipForwardButtonClicked(_:)))
                }
                skipForwardButtonItem.isEnabled = false
                self.skipForwardButtonItem = skipForwardButtonItem
                barButtonArray.append(skipForwardButtonItem)
            case .showTableOfContents:
                let showTableOfContentsButtonItem:UIBarButtonItem
                if #available(iOS 13.0, *) {
                    showTableOfContentsButtonItem = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(showTableOfContentsButtonClicked(_:)))
                    showTableOfContentsButtonItem.accessibilityLabel = NSLocalizedString("SpeechViewController_ShowTableOfContentsButtonTitle", comment: "目次")
                } else {
                    showTableOfContentsButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_ShowTableOfContentsButtonTitle", comment: "目次"), style: .plain, target: self, action: #selector(showTableOfContentsButtonClicked(_:)))
                }
                self.showTableOfContentsButtonItem = showTableOfContentsButtonItem
                barButtonArray.append(showTableOfContentsButtonItem)
            default:
                break
            }
        }
        let startStopButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Speak", comment: "Speak"), style: .plain, target: self, action: #selector(startStopButtonClicked(_:)))
        self.startStopButtonItem = startStopButtonItem
        barButtonArray.append(startStopButtonItem)
        barButtonArray.reverse()

        navigationItem.rightBarButtonItems = barButtonArray
    }
    
    func loadNovel(novelID: String, novelTitle: String, novelType:NovelType, aliveButtonSettings: [SpeechViewButtonSetting]) {
        NiftyUtility.DispatchSyncMainQueue {
            self.assignUpperButtons(novelID: novelID, novelType: novelType, aliveButtonSettings: aliveButtonSettings)
            self.navigationItem.title = novelTitle
            self.observeNovel(novelID: novelID)
        }
    }
    
    func applyChapterListChange() {
        guard let storyID = self.storyID else { return }
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
            if let constraint = self.chapterPositionLabelWidthConstraint {
                self.chapterPositionLabel.removeConstraint(constraint)
            }
            self.chapterPositionLabel.sizeToFit()
            self.chapterPositionLabelWidthConstraint = self.chapterPositionLabel.widthAnchor.constraint(equalToConstant: self.chapterPositionLabel.frame.width)
            self.chapterPositionLabelWidthConstraint.isActive = true
        }
    }
    
    func updateStoryTextAttribute(font:UIFont?, lineSpacing:CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing // 行間
        //style.paragraphSpacing = 10 // 改行の時の間
        var attributes:[NSAttributedString.Key:Any] = [
            .paragraphStyle: style
        ]
        if let font = font {
            attributes[.font] = font
        }
        storyTextAttribute = attributes
        reloadStoryText()
    }
    
    func applyStoryTextWithSpeechModAttribute(){
        let displayAttributedString = NSMutableAttributedString()
        let normalAttribute = self.storyTextAttribute
        var redAttribute:[NSAttributedString.Key:Any] = [.foregroundColor : UIColor.systemRed, .strokeWidth: -5.0, .strokeColor: UIColor.systemRed]
        normalAttribute.forEach {redAttribute[$0.key] = $0.value}
        for block in self.storySpeaker.speechBlockArray {
            if block.displayText != block.speechText {
                for block2 in block.speechBlockArray {
                    if block2.speechText != nil {
                        displayAttributedString.append(NSMutableAttributedString(string: block2.displayText, attributes: redAttribute))
                    }else{
                        displayAttributedString.append(NSMutableAttributedString(string: block2.displayText, attributes: normalAttribute))
                    }
                }
            }else{
                displayAttributedString.append(NSMutableAttributedString(string: block.displayText, attributes: normalAttribute))
            }
        }
        self.textView.attributedText = displayAttributedString
        self.applyTheme()
    }
    func applyStoryText(text:String) {
        self.displayTextCache = text
        self.reloadStoryText()
    }
    func reloadStoryText() {
        self.textView.attributedText = NSAttributedString(string: self.displayTextCache, attributes: self.storyTextAttribute)
        self.applyTheme()
    }
    
    func setStoryWithoutSetToStorySpeaker(story:Story) {
        self.readingChapterStoryUpdateDate = Date()
        RealmUtil.RealmBlock { (realm) -> Void in
            let content = story.content
            let storyID = story.storyID
            let novelID = story.novelID
            if let currentStoryID = self.storyID, novelID != RealmStoryBulk.StoryIDToNovelID(storyID: currentStoryID), let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) {
                let title = novel.title
                let type = novel.type
                let buttonSetting = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() ?? SpeechViewButtonSetting.defaultSetting
                NiftyUtility.DispatchSyncMainQueue {
                    self.loadNovel(novelID: novelID, novelTitle: title, novelType: type, aliveButtonSettings: buttonSetting)
                }
            }
            let readLocation = story.readLocation(realm: realm)
            if let currentStoryID = self.storyID, currentStoryID != storyID {
                NiftyUtility.DispatchSyncMainQueue {
                    self.observeStory(storyID: storyID)
                }
            }
            self.storyID = storyID
            self.applyChapterListChange()
            DispatchQueue.main.async {
                if let textViewText = self.textView.text, textViewText != content {
                    if story.content.count <= 0 {
                        self.applyStoryText(text: NSLocalizedString("SpeechViewController_ContentReadFailed", comment: "文書の読み込みに失敗しました。"))
                        return
                    }
                    // スクロールした状態で .attributedText を更新すると怪しい動きをするようなので、
                    // .attributedText を書き換える前にスクロール位置を先頭に移動しておきます
                    self.textView.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
                    if NovelSpeakerUtility.IsDisplaySpeechModChange() {
                        self.applyStoryTextWithSpeechModAttribute()
                    }else{
                        self.applyStoryText(text: story.content)
                    }
                    // textView.select() すると、選択範囲の上にメニューが出るようになるのでこの時点では select() はしない。
                    // でも、textView.becomeFirstResponder() しておかないと選択範囲自体が表示されないようなので becomeFirstResponder() はどこかでしておかないと駄目っぽい。
                    //self.textView.select(self)
                    self.textView.selectedRange = NSRange(location: readLocation, length: 1)
                    self.textViewScrollTo(readLocation: readLocation)
                }
            }
        }
    }
    
    func registNotificationCenter() {
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.RealmSettingChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
        }
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.ForcePopViewControllerForSpeechView, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }
    
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
                                guard let storyID = self.storyID, let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.RemoveRealmLink(), let buttonSettings = RealmGlobalState.GetInstanceWith(realm: realm)?.GetSpeechViewButtonSetting() else { return }
                                self.assignUpperButtons(novelID: novel.novelID, novelType: novel.type, aliveButtonSettings: buttonSettings)
                            }
                        }
                        if property.name == "isEnableSwipeOnStoryView" {
                            if let value = property.newValue as? Bool {
                                DispatchQueue.main.async {
                                    if value == true {
                                        self.assignSwipeRecognizer()
                                    }else{
                                        self.removeSwipeRecognizer()
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
    
    func observeNovel(novelID:String) {
        if novelObserverNovelID == novelID { return }
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
                        if property.name == "m_readingChapterStoryID", let newReadingChapterStoryID = property.newValue as? String, let currentStoryID = self.storyID, newReadingChapterStoryID != currentStoryID, self.readingChapterStoryUpdateDate < Date(timeIntervalSinceNow: -1.5) {
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
    func observeStory(storyID:String) {
        if storyObserverBulkStoryID == RealmStoryBulk.StoryIDToBulkID(storyID: storyID) { return }
        self.storyObserverToken = nil
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let storyBulk = RealmStoryBulk.SearchStoryBulkWith(realm: realm, storyID: storyID) else { return }
            storyObserverBulkStoryID = storyBulk.id
            self.storyObserverToken = storyBulk.observe({ [weak self] (change) in
                guard let self = self else { return }
                guard let targetStoryID = self.storyID, self.storyObserverBulkStoryID == RealmStoryBulk.StoryIDToBulkID(storyID: targetStoryID) else {
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
                                // 今開いている Story が存在した
                                if story.chapterNumber == chapterNumber, let currentText = self.textView.text, story.content != currentText {
                                    DispatchQueue.main.async {
                                        self.setStoryWithoutSetToStorySpeaker(story: story)
                                    }
                                }
                            }else{
                                // 今開いている Story が存在しなかった(恐らくは最後の章を開いていて、その章が削除された)
                                if let lastStory = storyArray.last {
                                    DispatchQueue.main.async {
                                        self.storySpeaker.SetStory(story: lastStory, withUpdateReadDate: true)
                                    }
                                }
                            }
                        }
                    }
                case .deleted:
                    DispatchQueue.main.async {
                        self.navigationController?.popViewController(animated: true)
                    }
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
                        // ViewType が normal 以外に変わっていたら元画面に戻します
                        if property.name == "m_ViewType", let newValue = property.newValue as? String, newValue != RealmDisplaySetting.ViewType.normal.rawValue {
                            DispatchQueue.main.async {
                                self.navigationController?.popViewController(animated: true)
                            }
                            return
                        }
                        if property.name == "textSizeValue" || property.name == "fontID" || property.name == "lineSpacing" {
                            DispatchQueue.main.async {
                                RealmUtil.RealmBlock { (realm) -> Void in
                                    guard let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) else { return }
                                    //self.textView.font = displaySetting.font
                                    self.updateStoryTextAttribute(font: displaySetting.font, lineSpacing: displaySetting.lineSpacingDisplayValue)
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
    
    
    @objc func setSpeechModSetting(sender: UIMenuItem){
        guard let range = self.textView.selectedTextRange, let text = self.textView.text(in: range) else { return }
        if text.count <= 0 { return }
        let nextViewController = CreateSpeechModSettingViewControllerSwift()
        nextViewController.targetSpeechModSettingBeforeString = text
        nextViewController.targetNovelID = RealmSpeechModSetting.anyTarget
        nextViewController.isUseAnyNovelID = true
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }
    @objc func setSpeechModForThisNovelSetting(sender: UIMenuItem){
        guard let range = self.textView.selectedTextRange, let text = self.textView.text(in: range) else { return }
        if text.count <= 0 { return }
        let nextViewController = CreateSpeechModSettingViewControllerSwift()
        nextViewController.targetSpeechModSettingBeforeString = text
        nextViewController.isUseAnyNovelID = true
        if let storyID = storyID {
            nextViewController.targetNovelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        }else{
            // 不測の事態だ……('A`)
            return
        }
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }

    @objc func checkSpeechText(sender: UIMenuItem) {
        guard let range = self.textView.selectedTextRange else { return }
        let startOffset = self.textView.offset(from: self.textView.beginningOfDocument, to: range.start)
        let endOffset = self.textView.offset(from: self.textView.beginningOfDocument, to: range.end)
        let speechText = storySpeaker.GenerateSpeechTextFrom(displayTextRange: NSMakeRange(startOffset, endOffset - startOffset))
        NiftyUtility.EasyDialogLongMessageDialog(viewController: self, message: speechText)

        /*
        let nextViewController = SpeechModCheckViewController()
        nextViewController.targetStoryID = self.storyID
        self.navigationController?.pushViewController(nextViewController, animated: true)
         */
    }

    func textViewScrollTo(readLocation:Int) {
        guard let swiftText = self.textView.text, readLocation >= 0 else {
            return
        }
        let text = swiftText as NSString
        let textLength = text.length
        var location = readLocation
        
        if textLength <= 0 {
            location = 0
        }else if location >= textLength {
            location = textLength - 1
        }
        var range = NSRange(location: location, length: 1)

        let maxLineCount = 5
        let minAppendLength = 15
        let maxAppendLength = 120
        var appendLength = 0
        var lineCount = 0
        var index = location
        while index < textLength {
            if let c = UnicodeScalar(text.character(at: index)), CharacterSet.newlines.contains(c) {
                lineCount += 1
                if lineCount > maxLineCount && appendLength > minAppendLength {
                    break
                }
            }
            appendLength += 1
            if appendLength > maxAppendLength {
                break
            }
            index += 1
        }
        range.location = location;
        range.length = appendLength
        self.textView.scrollRangeToVisible(range)
    }
    
    func pushToEditStory() {
        performSegue(withIdentifier: "EditUserTextSegue", sender: self)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "EditUserTextSegue" {
            if let nextViewController = segue.destination as? EditBookViewController, let storyID = self.storyID {
                nextViewController.targetNovelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
            }
        }else if segue.identifier == "NovelDetailViewPushSegue" {
            guard let nextViewController = segue.destination as? NovelDetailViewController, let storyID = self.storyID else { return }
            nextViewController.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
        }
    }
    
    func applyThemeColor(backgroundColor:UIColor, foregroundColor:UIColor, indicatorStyle:UIScrollView.IndicatorStyle, barStyle:UIBarStyle) {
        
        self.view.backgroundColor = backgroundColor;
        self.textView.textColor = foregroundColor;
        self.textView.backgroundColor = backgroundColor;
        self.textView.indicatorStyle = indicatorStyle
        self.nextChapterButton.backgroundColor = backgroundColor
        self.previousChapterButton.backgroundColor = backgroundColor
        self.chapterSlider.backgroundColor = backgroundColor
        self.chapterPositionLabel.backgroundColor = backgroundColor
        self.chapterPositionLabel.textColor = foregroundColor
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: foregroundColor]
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = barStyle
    }
    
    func applyTheme() {
        var backgroundColor = UIColor.white
        var foregroundColor = UIColor.black
        var indicatorStyle = UIScrollView.IndicatorStyle.default
        var barStyle = UIBarStyle.default
        
        if #available(iOS 13.0, *) {
            backgroundColor = UIColor.systemBackground
            foregroundColor = UIColor.label
        }
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalState = RealmGlobalState.GetInstanceWith(realm: realm) {
                if let fgColor = globalState.foregroundColor {
                    foregroundColor = fgColor
                }
                if let bgColor = globalState.backgroundColor {
                    backgroundColor = bgColor
                }
            }
        }
        
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

    @objc func backupButtonClicked(_ sender: UIBarButtonItem) {
        guard let storyID = self.storyID else { return }
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
        pushToEditStory()
    }
    @objc func detailButtonClicked(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: "NovelDetailViewPushSegue", sender: self)
    }
    @objc func searchButtonClicked(_ sender: UIBarButtonItem) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            self.storySpeaker.StopSpeech(realm: realm, stopAudioSession:true)
            
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
                    guard let storyID = self.storyID else { return }
                    self.searchTextCache = filterText
                    NovelSpeakerUtility.SearchStoryFor(selectedStoryID: storyID, viewController: self, searchString: filterText) { (story) in
                        self.storySpeaker.SetStory(story: story, withUpdateReadDate: true)
                    }
                },
                shouldReturnIsRightButtonClicked: true,
                completion: nil)
        }
    }
    
    func clearSearchView(){
        if let searchView = self.searchView {
            self.searchView = nil
            searchView.removeFromSuperview()
        }
    }
    
    func searchResultAnnounceIfVoiceOverEnabled(foundString:String){
        guard UIAccessibility.isVoiceOverRunning == true else { return }
        let announceString = String(format: NSLocalizedString("SpeechViewController_SearchByText_Found_Announce_to_VoiceOverUser_Formated", comment: "%@"), foundString)
        self.storySpeaker.AnnounceSpeech(text: announceString)
    }
    
    func prevSearchByText(searchString:String){
        let searchStringCount = searchString.unicodeScalars.count
        let currentRange = self.textView.selectedRange
        let targetText:String
        if currentRange.location == NSNotFound {
            targetText = ""
        }else{
            targetText = self.textView.text.NiftySubstring(from: 0, to: currentRange.location - 1)
        }
        guard let nextRange = targetText.range(of: searchString, options: .backwards) else {
            DispatchQueue.main.async {
                NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("SpeechViewController_SearchByText_NotFound", comment: "ページ内に検索文字列を発見できませんでした。"))
            }
            return
        }
        let targetLocation = max((targetText.distance(from: targetText.startIndex, to: nextRange.lowerBound) as Int), 0)
        self.textView.becomeFirstResponder()
        self.textView.selectedRange = NSRange(location: targetLocation, length: searchStringCount)
        self.textViewScrollTo(readLocation: targetLocation)
        
        let foundString = self.textView.text.NiftySubstring(from: targetLocation, to: targetLocation + min(searchStringCount + 20, 30))
        self.searchResultAnnounceIfVoiceOverEnabled(foundString: foundString)
    }
    func nextSearchByText(searchString:String){
        let searchStringCount = searchString.unicodeScalars.count
        let currentRange = self.textView.selectedRange
        let targetText:String, currentLocation:Int
        if currentRange.location == NSNotFound {
            currentLocation = 0
            targetText = self.textView.text
        }else{
            currentLocation = currentRange.location + 1
            targetText = self.textView.text.NiftySubstring(from: currentLocation, to: self.textView.text.unicodeScalars.count)
        }
        guard let nextRange = targetText.range(of: searchString) else {
            DispatchQueue.main.async {
                NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("SpeechViewController_SearchByText_NotFound", comment: "ページ内に検索文字列を発見できませんでした。"))
            }
            return
        }
        let targetLocation = (targetText.distance(from: targetText.startIndex, to: nextRange.lowerBound) as Int) + currentLocation
        self.textView.becomeFirstResponder()
        self.textView.selectedRange = NSRange(location: targetLocation, length: searchStringCount)
        self.textViewScrollTo(readLocation: targetLocation)

        let foundString = self.textView.text.NiftySubstring(from: targetLocation, to: targetLocation + min(searchStringCount + 20, 30))
        self.searchResultAnnounceIfVoiceOverEnabled(foundString: foundString)
    }
    
    @objc func searchByTextButtonClicked(_ sender: UIBarButtonItem) {
        if self.searchView != nil {
            clearSearchView()
            return
        }
        if self.storySpeaker.isPlayng {
            RealmUtil.RealmBlock { realm in
                self.storySpeaker.StopSpeech(realm: realm, stopAudioSession:true)
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
        guard let storyID = self.storyID else { return }
        NovelSpeakerUtility.ShareStory(viewController: self, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), barButton: self.shareButtonItem)
    }
    
    @objc func urlRefreshButtonClicked(_ sender: UIBarButtonItem) {
        guard let storyID = self.storyID else { return }
        NovelDownloadQueue.shared.addQueue(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))
    }
    @objc func openCurrentWebPageButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let storyID = self.storyID, let urlString = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID)?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    @objc func safariButtonClicked(_ sender: UIBarButtonItem) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let storyID = self.storyID, let urlString = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID))?.url, let url = URL(string: urlString) else {
                return
            }
            BookShelfTreeViewController.LoadWebPageOnWebImportTab(url: url)
        }
    }
    func CheckFolderAndStartSpeech() {
        RealmUtil.RealmBlock { realm in
            disableCurrentReadingStoryChangeFloatingButton()
            storySpeaker.setReadLocationWith(realm: realm, location: self.textView.selectedRange.location)

            func runNextSpeech(nextFolder:RealmNovelTag?){
                self.storySpeaker.targetFolderNameForGoToNextSelectedFolderdNovel = nextFolder?.name
                self.clearSearchView()
                RealmUtil.RealmBlock { realm in
                    self.storySpeaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面(Speakボタンを押した 又は 本棚画面で「▶︎ 再生:〜」を選択した 又は 次のフォルダの小説に移行した).\(#function)", isNeedRepeatSpeech: true)
                    self.checkDummySpeechFinished()
                }
            }
            if let storyID = self.storyID, let repeatType = RealmGlobalState.GetInstanceWith(realm: realm)?.repeatSpeechType, repeatType == .GoToNextSelectedFolderdNovel, let folderArray = RealmNovelTag.SearchWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), type: RealmNovelTag.TagType.Folder) {
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
    
    @objc func startStopSpeech() {
        RealmUtil.RealmBlock { (realm) -> Void in
            if self.storySpeaker.isPlayng {
                self.storySpeaker.StopSpeech(realm: realm, stopAudioSession:true)
            }else{
                self.CheckFolderAndStartSpeech()
            }
        }
    }
    
    @objc func startStopButtonClicked(_ sender: UIBarButtonItem) {
        startStopSpeech()
    }
    @objc func skipBackwardButtonClicked(_ sender: UIBarButtonItem) {
        if self.storySpeaker.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                self.storySpeaker.StopSpeech(realm: realm, stopAudioSession:false) {
                    self.storySpeaker.SkipBackward(realm: realm, length: 30) {
                        self.clearSearchView()
                        self.storySpeaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面(少し戻すボタン).\(#function)", isNeedRepeatSpeech: true)
                    }
                }
            }
        }
    }
    @objc func skipForwardButtonClicked(_ sender: UIBarButtonItem) {
        if self.storySpeaker.isPlayng == false { return }
        NiftyUtility.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                self.storySpeaker.StopSpeech(realm: realm, stopAudioSession:false) {
                    self.storySpeaker.SkipForward(realm: realm, length: 30) {
                        self.clearSearchView()
                        self.storySpeaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説本文画面(少し進めるボタン).\(#function)", isNeedRepeatSpeech: true)
                    }
                }
            }
        }
    }
    @objc func showTableOfContentsButtonClicked(_ sender: UIBarButtonItem) {
        guard let storyID = self.storyID else { return }
        NovelSpeakerUtility.SearchStoryFor(selectedStoryID: storyID, viewController: self, searchString: nil) { (story) in
            self.storySpeaker.SetStory(story: story, withUpdateReadDate: true)
        }
    }
    @objc func leftSwipe(_ sender: UISwipeGestureRecognizer) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            self.storySpeaker.LoadNextChapter(realm: realm)
        }
    }
    @objc func rightSwipe(_ sender: UISwipeGestureRecognizer) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            self.storySpeaker.LoadPreviousChapter(realm: realm)
        }
    }
    
    func checkDummySpeechFinished() {
        if self.storySpeaker.isDummySpeechAlive() {
            DispatchQueue.main.async {
                let dialog = NiftyUtility.EasyDialogBuilder(self).text(content: NSLocalizedString("SpeechViewController_WaitingSpeakerReady", comment: "話者の準備が整うのを待っています。"))
                    .build()
                dialog.show()
                func waitDummySpeechFinish() {
                    if self.storySpeaker.isDummySpeechAlive() == false {
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
    
    // MARK: StorySpeakerDelegate
    func storySpeakerStartSpeechEvent(storyID:String){
        DispatchQueue.main.async {
            self.clearSearchView()
            self.startStopButtonItem?.title = NSLocalizedString("SpeechViewController_Stop", comment: "Stop")
            self.skipBackwardButtonItem?.isEnabled = true
            self.skipForwardButtonItem?.isEnabled = true
            self.removeCustomUIMenu()
        }
    }
    func storySpeakerStopSpeechEvent(storyID:String){
        DispatchQueue.main.async {
            self.startStopButtonItem?.title = NSLocalizedString("SpeechViewController_Speak", comment: "Speak")
            self.skipBackwardButtonItem?.isEnabled = false
            self.skipForwardButtonItem?.isEnabled = false
            self.setCustomUIMenu()
        }
    }
    func storySpeakerUpdateReadingPoint(storyID:String, range:NSRange){
        DispatchQueue.main.async {
            let contentLength = self.textView.text.unicodeScalars.count
            let newRange:NSRange
            if range.length == 0 && contentLength >= (range.location + 1) {
                newRange = NSMakeRange(range.location, 1)
            }else{
                newRange = range
            }
            if contentLength >= (newRange.location + newRange.length) {
                self.textView.select(self) // この「おまじない」をしないと選択範囲が表示されない
                self.textView.selectedRange = newRange
            }
            self.textViewScrollTo(readLocation: range.location)
        }
    }
    func storySpeakerStoryChanged(story:Story){
        setStoryWithoutSetToStorySpeaker(story: story)
        if self.isNeedResumeSpeech {
            self.isNeedResumeSpeech = false
            DispatchQueue.main.async {
                self.CheckFolderAndStartSpeech()
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
        guard let currentStoryID = self.storyID, newReadingStoryID != currentStoryID else { return }
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: newReadingStoryID) else { return }
            let newChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: newReadingStoryID)
            DispatchQueue.main.async {
                self.currentReadStoryIDChangeAlertFloatingButton = FloatingButton.createNewFloatingButton()
                guard let floatingButton = self.currentReadStoryIDChangeAlertFloatingButton else { return }
                floatingButton.assignToView(view: self.view, currentOffset: CGPoint(x: -1, y: -1), text: String(format: NSLocalizedString("SpeechViewController_CurrentReadingStoryChangedFloatingButton_Format", comment: "他端末で更新された %d章 へ移動"), newChapterNumber), animated: true, bottomConstraintAppend: -32.0) {
                    self.storySpeaker.SetStory(story: story, withUpdateReadDate: false)
                    floatingButton.hideAnimate()
                }
            }
        }
    }

    @IBAction func chapterSliderValueChanged(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        guard let storyID = self.storyID else {
            return
        }
        let chapterNumber = Int(self.chapterSlider.value + 0.5)
        let targetStoryID = RealmStoryBulk.CreateUniqueID(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID), chapterNumber: chapterNumber)
        //self.chapterSlider.value = Float(chapterNumber)
        RealmUtil.RealmBlock { (realm) -> Void in
            if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: targetStoryID) {
                self.storySpeaker.SetStory(story: story, withUpdateReadDate: true)
            }
        }
    }
    @IBAction func previousChapterButtonClicked(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            self.storySpeaker.LoadPreviousChapter(realm: realm)
        }
    }
    @IBAction func nextChapterButtonClicked(_ sender: Any) {
        disableCurrentReadingStoryChangeFloatingButton()
        RealmUtil.RealmBlock { (realm) -> Void in
            self.storySpeaker.LoadNextChapter(realm: realm)
        }
    }
    @available(iOS 16.0, *)
    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        print("HOGEHOGE: editMenuInteraction: \(configuration.identifier) \(suggestedActions.map({"\($0.title):\($0.subtitle ?? "nil"):\($0.debugDescription)"}).joined(separator: ", "))")
        if self.storySpeaker.isPlayng {
            return nil
        }
        
        let addActions: [UIMenuElement] = [
            UIAction(title: NSLocalizedString("SpeechViewController_AddSpeechModSettings", comment: "読み替え辞書へ登録"), handler: { _ in
                self.setSpeechModSetting(sender: UIMenuItem())
             }),
            UIAction(title: NSLocalizedString("SpeechViewController_AddSpeechModSettingsForThisNovel", comment: "この小説用の読み替え辞書へ登録"), handler: { _ in
                self.setSpeechModForThisNovelSetting(sender: UIMenuItem())
            }),
            UIAction(title: NSLocalizedString("SpeechViewController_AddCheckSpeechText", comment: "読み替え後の文字列を確認する"), handler: { _ in
                self.checkSpeechText(sender:UIMenuItem())
            })
        ]
        return UIMenu(children: suggestedActions + addActions)
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            .init(title: NSLocalizedString("SpeechViewController_KeyboardShortcut_StartStopSpeech_Title", comment: "発話の開始/停止"), action: #selector(startStopSpeech), input: "s", modifierFlags: [.control]),
            .init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettings", comment: "読み替え辞書へ登録"), action: #selector(setSpeechModSetting(sender:)), input: "r", modifierFlags: [.control]),
            .init(title: NSLocalizedString("SpeechViewController_AddCheckSpeechText", comment: "読み替え後の文字列を確認する"), action: #selector(checkSpeechText(sender:)), input: "c", modifierFlags: [.control]),
        ]
    }
}
