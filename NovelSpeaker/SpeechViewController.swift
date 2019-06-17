//
//  SpeechViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/19.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class SpeechViewController: UIViewController, StorySpeakerDeletgate {
    
    public var storyID : String? = nil
    public var isNeedResumeSpeech : Bool = false

    @IBOutlet weak var textView : UITextView!
    @IBOutlet weak var previousChapterButton : UIButton!
    @IBOutlet weak var nextChapterButton : UIButton!
    @IBOutlet weak var chapterSlider : UISlider!
    @IBOutlet weak var chapterPositionLabel : UILabel!
    @IBOutlet weak var chapterPositionLabelWidthConstraint : NSLayoutConstraint!
    
    var startStopButtonItem:UIBarButtonItem? = nil
    var shareButtonItem:UIBarButtonItem? = nil
    
    var novelObserverToken:NotificationToken? = nil
    var storyObserverToken:NotificationToken? = nil
    var storyArrayObserverToken:NotificationToken? = nil
    var displaySettingObserverToken:NotificationToken? = nil
    
    let storySpeaker = StorySpeaker.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()

        storySpeaker.AddDelegate(delegate: self)
        // Do any additional setup after loading the view.
        initWidgets()
        if let storyID = storyID {
            autoreleasepool {
                if let novel = RealmNovel.SearchNovelFrom(novelID: RealmStory.StoryIDToNovelID(storyID: storyID)){
                    loadNovel(novel: novel)
                }
            }
            self.storySpeaker.SetStory(storyID: storyID)
        }else{
            textView.text = NSLocalizedString("SpeechViewController_ContentReadFailed", comment: "文書の読み込みに失敗しました。")
        }
        observeDispaySetting()
        registNotificationCenter()
    }
    
    deinit {
        self.unregistNotificationCenter()
    }

    // 表示される直前に呼ばれる
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        autoreleasepool {
            if let globalState = RealmGlobalState.GetInstance(), globalState.isDarkThemeEnabled {
                applyDarkTheme()
            }
        }
    }
    
    // 非表示になる直前に呼ばれる
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        autoreleasepool {
            if let globalState = RealmGlobalState.GetInstance(), globalState.isDarkThemeEnabled {
                applyBrightTheme()
            }
        }
        let range = self.textView.selectedRange
        if range.location >= 0 && range.location < self.textView.text.count {
            storySpeaker.readLocation = range.location
        }
    }
    
    func initWidgets() {
        autoreleasepool {
            guard let globalState = RealmGlobalState.GetInstance() else {
                return
            }
            if let displaySetting = globalState.defaultDisplaySetting {
                textView.font = displaySetting.font
            }
        }
        
        let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(leftSwipe(_:)))
        leftSwipe.direction = .left
        view.addGestureRecognizer(leftSwipe)
        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(rightSwipe(_:)))
        rightSwipe.direction = .right
        view.addGestureRecognizer(rightSwipe)

        let menuController = UIMenuController.shared
        let speechModMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettings", comment: "読み替え辞書へ登録"), action: #selector(setSpeechModSetting(sender:)))
        let speechModForThisNovelMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettingsForThisNovel", comment: "この小説用の読み替え辞書へ登録"), action: #selector(setSpeechModForThisNovelSetting(sender:)))
        let checkSpeechTextMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddCheckSpeechText", comment: "読み替え後の文字列を確認する"), action: #selector(checkSpeechText(sender:)))
        let menuItems:[UIMenuItem] = [speechModMenuItem, speechModForThisNovelMenuItem, checkSpeechTextMenuItem]
        menuController.menuItems = menuItems
    }
    
    func loadNovel(novel:RealmNovel) {
        startStopButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Speak", comment: "Speak"), style: .plain, target: self, action: #selector(startStopButtonClicked(_:)))
        var barButtonArray:[UIBarButtonItem] = [
            startStopButtonItem!,
            UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Edit", comment: "編集"), style: .plain, target: self, action: #selector(editButtonClicked(_:)))
        ]
        barButtonArray.append(
            UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Detail", comment: "詳細"), style: .plain, target: self, action: #selector(detailButtonClicked(_:))))
        barButtonArray.append(UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Subtitles", comment: "目次"), style: .plain, target: self, action: #selector(tableOfContentsButtonClicked(_:))))
        if novel.type == .URL {
            let buttonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action:   #selector(shareButtonClicked(_:)))
            self.shareButtonItem = buttonItem
            barButtonArray.append(buttonItem)
            barButtonArray.append(UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(urlRefreshButtonClicked(_:))))
            barButtonArray.append(UIBarButtonItem(image: UIImage(named: "earth"), style: .plain, target: self, action: #selector(safariButtonClicked(_:))))
        }
        navigationItem.rightBarButtonItems = barButtonArray
        navigationItem.title = novel.title
        observeNovel(novelID: novel.novelID)
        self.observeStoryArray(novelID: novel.novelID)
    }
    
    func applyChapterListChange() {
        autoreleasepool {
            guard let storyID = self.storyID, let story = RealmStory.SearchStoryFrom(storyID: storyID) else { return }
            let novelID = story.novelID
            let chapterNumber = story.chapterNumber
            DispatchQueue.main.async {
                autoreleasepool {
                    guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID), let lastChapterNumber = novel.lastChapterNumber else {
                        return
                    }
                    
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
        }
    }
    
    func setStoryWithoutSetToStorySpeaker(storyID:String) {
        autoreleasepool {
            guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else { return }
            let content = story.content
            let storyID = story.id
            let readLocation = story.readLocation
            if let currentStoryID = self.storyID, currentStoryID != storyID {
                self.observeStory(storyID: storyID)
            }
            self.storyID = storyID
            self.applyChapterListChange()
            DispatchQueue.main.async {
                if let textViewText = self.textView.text, textViewText != content {
                    if let content = content {
                        self.textView.text = content
                    }else{
                        self.textView.text = NSLocalizedString("SpeechViewController_ContentReadFailed", comment: "文書の読み込みに失敗しました。")
                    }
                    self.textView.select(self)
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
    }
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }
    
    func observeNovel(novelID:String) {
        autoreleasepool {
            guard let novel = RealmNovel.SearchNovelFrom(novelID: novelID) else { return }
            self.novelObserverToken = novel.observe({ [weak self] (change) in
                switch change {
                case .error(_):
                    break
                case .change(let properties):
                    for property in properties {
                        if property.name == "title", let newValue = property.newValue as? String {
                            DispatchQueue.main.async {
                                self?.title = newValue
                            }
                        }
                     }
                case .deleted:
                    break
                }
            })
        }
    }
    func observeStory(storyID:String) {
        autoreleasepool {
            guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else { return }
            self.storyObserverToken = story.observe({ [weak self] (change) in
                switch change {
                case .error(_):
                    break
                case .change(let properties):
                    for property in properties {
                        // content が書き換わった時のみを監視します。
                        // でないと lastReadDate とかが書き換わった時にも表示の更新が走ってしまいます。
                        if property.name == "contentZiped" {
                            self?.setStoryWithoutSetToStorySpeaker(storyID: storyID)
                        }
                    }
                case .deleted:
                    break
                }
            })
        }
    }
    func observeStoryArray(novelID:String) {
        autoreleasepool {
            guard let storyArray = RealmStory.GetAllObjects()?.filter("novelID = %@", novelID) else { return }
            self.storyArrayObserverToken = storyArray.observe({ [weak self] (changes) in
                switch changes {
                case .initial(_):
                    break
                case .update(_, let deletions, let insertions, _):
                    if deletions.count > 0 || insertions.count > 0 {
                        DispatchQueue.main.async {
                            print("SpeechViewController: story delete or inserted. update display")
                            self?.applyChapterListChange()
                        }
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    func observeDispaySetting() {
        autoreleasepool {
            guard let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting else { return }
            displaySettingObserverToken = displaySetting.observe({ (change) in
                switch change {
                case .change(let properties):
                    for propaty in properties {
                        if propaty.name == "textSizeValue" || propaty.name == "fontID" {
                            DispatchQueue.main.async {
                                autoreleasepool {
                                    guard let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting else { return }
                                    self.textView.font = displaySetting.font
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
            nextViewController.targetNovelID = RealmStory.StoryIDToNovelID(storyID: storyID)
        }else{
            // 不測の事態だ……('A`)
            return
        }
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }

    @objc func checkSpeechText(sender: UIMenuItem) {
        guard let range = self.textView.selectedTextRange, let text = self.textView.text(in: range), let storyID = self.storyID else { return }
        let novelID = RealmStory.StoryIDToNovelID(storyID: storyID)
        let dummySpeaker = NiftySpeaker()
        dummySpeaker.clearSpeakSettings()
        self.storySpeaker.applySpeechConfig(novelID: novelID, speaker: dummySpeaker)
        self.storySpeaker.applySpeechModSetting(novelID: novelID, targetText: text, speaker: dummySpeaker)
        dummySpeaker.setText(text)
        if let speechText = dummySpeaker.getSpeechText() {
            NiftyUtilitySwift.EasyDialogOneButton(viewController: self, title: NSLocalizedString("SpeechViewController_CheckSpeechTextDialogTitle", comment: "読み上げに使われる文字列は以下のようになります。"), message: speechText, buttonTitle: nil, buttonAction: nil)
        }
    }

    func textViewScrollTo(readLocation:Int) {
        guard let text = self.textView.text else {
            return
        }
        let textLength = text.count
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
        var index = text.index(text.startIndex, offsetBy: location)
        while index < text.endIndex {
            if text[index].unicodeScalars.contains(where: { (s) -> Bool in
                return CharacterSet.newlines.contains(s)
            }) {
                lineCount += 1
                if lineCount > maxLineCount && appendLength > minAppendLength {
                    break
                }
            }
            appendLength += 1
            if appendLength > maxAppendLength {
                break
            }
            index = text.index(index, offsetBy: 1)
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
                nextViewController.targetNovelID = RealmStory.StoryIDToNovelID(storyID: storyID)
            }
        }else if segue.identifier == "NovelDetailViewPushSegue" {
            guard let nextViewController = segue.destination as? NovelDetailViewController, let storyID = self.storyID else { return }
            nextViewController.novelID = RealmStory.StoryIDToNovelID(storyID: storyID)
        }
    }

    func applyDarkTheme() {
        let backgroundColor = UIColor.black
        let foregroundColor = UIColor.white
        
        self.view.backgroundColor = backgroundColor;
        self.textView.textColor = foregroundColor;
        self.textView.backgroundColor = backgroundColor;
        self.textView.indicatorStyle = UIScrollView.IndicatorStyle.white
        self.nextChapterButton.backgroundColor = backgroundColor
        self.previousChapterButton.backgroundColor = backgroundColor
        self.chapterSlider.backgroundColor = backgroundColor
        self.chapterPositionLabel.backgroundColor = backgroundColor
        self.chapterPositionLabel.textColor = foregroundColor
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: foregroundColor]
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = UIBarStyle.black
    }
    
    func applyBrightTheme() {
        let backgroundColor = UIColor.white
        let foregroundColor = UIColor.black
        
        self.view.backgroundColor = backgroundColor;
        self.textView.textColor = foregroundColor;
        self.textView.backgroundColor = backgroundColor;
        self.textView.indicatorStyle = UIScrollView.IndicatorStyle.black
        self.nextChapterButton.backgroundColor = backgroundColor
        self.previousChapterButton.backgroundColor = backgroundColor
        self.chapterSlider.backgroundColor = backgroundColor
        self.chapterPositionLabel.backgroundColor = backgroundColor
        self.chapterPositionLabel.textColor = foregroundColor
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: foregroundColor]
        // ステータスバーの色を指定する
        self.navigationController?.navigationBar.barStyle = UIBarStyle.default
    }
    

    @objc func editButtonClicked(_ sender: UIBarButtonItem) {
        pushToEditStory()
    }
    @objc func detailButtonClicked(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: "NovelDetailViewPushSegue", sender: self)
    }
    @objc func tableOfContentsButtonClicked(_ sender: UIBarButtonItem) {
        autoreleasepool {
            guard let storyID = storyID, let storys = RealmNovel.SearchNovelFrom(novelID: RealmStory.StoryIDToNovelID(storyID: storyID))?.linkedStorys else {
                NiftyUtilitySwift.EasyDialogOneButton(
                    viewController: self,
                    title: nil,
                    message: NSLocalizedString("SpeechViewController_CanNotGetStorys", comment: "小説情報を参照できませんでした。"),
                    buttonTitle: nil, buttonAction: nil)
                return
            }
            let displayTextArray = Array(storys.map { (story) -> String in
                return "\(story.chapterNumber): " + story.GetSubtitle()
            })
            var selectedText:String? = nil
            autoreleasepool {
                if let story = RealmStory.SearchStoryFrom(storyID: storyID) {
                    selectedText = "\(story.chapterNumber): " + story.GetSubtitle()
                }
            }
            let picker = PickerViewDialog.createNewDialog(displayTextArray, firstSelectedString: selectedText, parentView: self.view) { (selectedText) in
                guard let selectedText = selectedText, let number = selectedText.components(separatedBy: ":").first, let chapterNumber = Int(number) else { return }
                self.storySpeaker.SetStory(storyID: RealmStory.CreateUniqueID(novelID: RealmStory.StoryIDToNovelID(storyID: storyID), chapterNumber: chapterNumber))
            }
            picker?.popup(nil)
        }
    }

    @objc func shareButtonClicked(_ sender: UIBarButtonItem) {
        autoreleasepool {
            guard let storyID = self.storyID, let novel = RealmNovel.SearchNovelFrom(novelID: RealmStory.StoryIDToNovelID(storyID: storyID)) else {
                NiftyUtilitySwift.EasyDialogOneButton(viewController: self, title: NSLocalizedString("SpeechViewController_UnknownErrorForShare", comment: "不明なエラーでシェアできませんでした。"), message: nil, buttonTitle: NSLocalizedString("OK_button", comment: "OK"), buttonAction: nil)
                return
            }
            let urlString:String
            if novel.type == .URL {
                urlString = novel.url
            }else{
                urlString = ""
            }
            let message = String(format: NSLocalizedString("SpeechViewController_TweetMessage", comment: "%@ %@ #narou #ことせかい %@ %@"), novel.title, novel.writer, urlString, "https://itunes.apple.com/jp/app/kotosekai-xiao-shuo-jianinarou/id914344185")
            NiftyUtilitySwift.Share(message: message, viewController: self, barButton: self.shareButtonItem)
        }
    }
    
    @objc func urlRefreshButtonClicked(_ sender: UIBarButtonItem) {
        guard let storyID = self.storyID else { return }
        NovelDownloadQueue.shared.addQueue(novelID: RealmStory.StoryIDToNovelID(storyID: storyID))
    }
    @objc func safariButtonClicked(_ sender: UIBarButtonItem) {
        autoreleasepool {
            guard let storyID = self.storyID, let urlString = RealmNovel.SearchNovelFrom(novelID: RealmStory.StoryIDToNovelID(storyID: storyID))?.url else {
                return
            }
            /// XXX 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
            let targetTabIndex = 2
            guard let viewController = self.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController, let url = URL(string: urlString) else { return }
            viewController.openTargetUrl = url
            self.tabBarController?.selectedIndex = targetTabIndex
        }
    }
    @objc func startStopButtonClicked(_ sender: UIBarButtonItem) {
        if self.storySpeaker.isPlayng {
            self.storySpeaker.StopSpeech()
        }else{
            storySpeaker.readLocation = self.textView.selectedRange.location
            self.storySpeaker.StartSpeech(withMaxSpeechTimeReset: true)
        }
    }
    @objc func leftSwipe(_ sender: UISwipeGestureRecognizer) {
        self.storySpeaker.LoadNextChapter()
    }
    @objc func rightSwipe(_ sender: UISwipeGestureRecognizer) {
        self.storySpeaker.LoadPreviousChapter()
    }
    
    // MARK: StorySpeakerDelegate
    func storySpeakerStartSpeechEvent(storyID:String){
        DispatchQueue.main.async {
            self.startStopButtonItem?.title = NSLocalizedString("SpeechViewController_Stop", comment: "Stop")
        }
    }
    func storySpeakerStopSpeechEvent(storyID:String){
        DispatchQueue.main.async {
            self.startStopButtonItem?.title = NSLocalizedString("SpeechViewController_Speak", comment: "Speak")
        }
    }
    func storySpeakerUpdateReadingPoint(storyID:String, range:NSRange){
        DispatchQueue.main.async {
            let contentLength = self.textView.text.count
            if contentLength >= (range.location + range.length) {
                self.textView.select(self) // この「おまじない」をしないと選択範囲が表示されない
                self.textView.selectedRange = range
            }
            self.textViewScrollTo(readLocation: range.location)
        }
    }
    func storySpeakerStoryChanged(storyID:String){
        setStoryWithoutSetToStorySpeaker(storyID: storyID)
        if self.isNeedResumeSpeech {
            self.isNeedResumeSpeech = false
            self.storySpeaker.StartSpeech(withMaxSpeechTimeReset: true)
        }
    }


    @IBAction func chapterSliderValueChanged(_ sender: Any) {
        guard let storyID = self.storyID else {
            return
        }
        let chapterNumber = Int(self.chapterSlider.value + 0.5)
        let targetStoryID = RealmStory.CreateUniqueID(novelID: RealmStory.StoryIDToNovelID(storyID: storyID), chapterNumber: chapterNumber)
        self.chapterSlider.value = Float(chapterNumber)
        self.storySpeaker.SetStory(storyID: targetStoryID)
    }
    @IBAction func previousChapterButtonClicked(_ sender: Any) {
        self.storySpeaker.LoadPreviousChapter()
    }
    @IBAction func nextChapterButtonClicked(_ sender: Any) {
        self.storySpeaker.LoadNextChapter()
    }

}
