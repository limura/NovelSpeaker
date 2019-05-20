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
    
    let storySpeaker = StorySpeaker.instance
    
    override func viewDidLoad() {
        super.viewDidLoad()

        storySpeaker.AddDelegate(delegate: self)
        // Do any additional setup after loading the view.
        initWidgets()
        if let storyID = storyID, let story = RealmStory.SearchStoryFrom(storyID: storyID) {
            if let novel = RealmNovel.SearchNovelFrom(novelID: story.novelID){
                loadNovel(novel: novel)
            }
            self.storySpeaker.SetStory(story: story)
        }else{
            textView.text = NSLocalizedString("SpeechViewController_ContentReadFailed", comment: "文書の読み込みに失敗しました。")
        }
    }

    // 表示される直前に呼ばれる
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let globalState = RealmGlobalState.GetInstance(), globalState.isDarkThemeEnabled {
            applyDarkTheme()
        }
    }
    
    // 非表示になる直前に呼ばれる
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let globalState = RealmGlobalState.GetInstance(), globalState.isDarkThemeEnabled {
            applyBrightTheme()
        }
        let range = self.textView.selectedRange
        if range.location >= 0 && range.location < self.textView.text.count {
            storySpeaker.readLocation = range.location
        }
    }
    
    func initWidgets() {
        guard let globalState = RealmGlobalState.GetInstance() else {
            return
        }
        if let displaySetting = globalState.defaultDisplaySetting {
            textView.font = displaySetting.font
        }
        
        let leftSwipe = UISwipeGestureRecognizer(target: self, action: #selector(leftSwipe(_:)))
        leftSwipe.direction = .left
        view.addGestureRecognizer(leftSwipe)
        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(rightSwipe(_:)))
        rightSwipe.direction = .right
        view.addGestureRecognizer(rightSwipe)

        let menuController = UIMenuController.shared
        let speechModMenuItem = UIMenuItem.init(title: NSLocalizedString("SpeechViewController_AddSpeechModSettings", comment: "読み替え辞書へ登録"), action: #selector(setSpeechModSetting(sender:)))
        menuController.menuItems = [speechModMenuItem]
    }
    
    func loadNovel(novel:RealmNovel) {
        startStopButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Speak", comment: "Speak"), style: .plain, target: self, action: #selector(startStopButtonClicked(_:)))
        var barButtonArray:[UIBarButtonItem] = [
            startStopButtonItem!,
            UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Edit", comment: "編集"), style: .plain, target: self, action: #selector(detailButtonClicked(_:)))
        ]
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
    }
    
    func setStoryWithoutSetToStorySpeaker(story:RealmStory) {
        DispatchQueue.main.async {
            guard let novel = RealmNovel.SearchNovelFrom(novelID: story.novelID), let lastChapterNumber = novel.lastChapterNumber else {
                return
            }
            let storyID = story.id

            if story.chapterNumber <= 1 {
                self.previousChapterButton.isEnabled = false
            }else{
                self.previousChapterButton.isEnabled = true
            }
            if story.chapterNumber < lastChapterNumber {
                self.nextChapterButton.isEnabled = true
            }else{
                self.nextChapterButton.isEnabled = false
            }
            self.chapterSlider.minimumValue = 1.0
            self.chapterSlider.maximumValue = Float(lastChapterNumber) + Float(0.01)
            self.chapterSlider.value = Float(story.chapterNumber)
            
            self.chapterPositionLabel.text = "\(story.chapterNumber)/\(lastChapterNumber)"
            if let constraint = self.chapterPositionLabelWidthConstraint {
                self.chapterPositionLabel.removeConstraint(constraint)
            }
            self.chapterPositionLabel.sizeToFit()
            self.chapterPositionLabelWidthConstraint = self.chapterPositionLabel.widthAnchor.constraint(equalToConstant: self.chapterPositionLabel.frame.width)
            self.chapterPositionLabelWidthConstraint.isActive = true
            
            if let content = story.content {
                self.textView.text = content
            }else{
                self.textView.text = NSLocalizedString("SpeechViewController_ContentReadFailed", comment: "文書の読み込みに失敗しました。")
            }
            
            self.textView.select(self)
            self.textView.selectedRange = NSRange(location: story.readLocation, length: 1)
            self.textViewScrollTo(readLocation: story.readLocation)
            self.storyID = storyID
            self.observeStory(storyID: storyID)
            self.observeStoryArray(story: story)
        }
    }
    
    func observeNovel(novelID:String) {
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
    func observeStory(storyID:String) {
        guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else { return }
        self.storyObserverToken = story.observe({ [weak self] (change) in
            switch change {
            case .error(_):
                break
            case .change(let properties):
                for property in properties {
                    // content が書き換わった時のみを監視します。
                    // でないと lastReadDate とかが書き換わった時にも表示の更新が走ってしまいます。
                    if property.name == "contentZiped", let story = RealmStory.SearchStoryFrom(storyID: storyID) {
                        DispatchQueue.main.async {
                            self?.setStoryWithoutSetToStorySpeaker(story: story)
                        }
                    }
                }
            case .deleted:
                break
            }
        })
    }
    func observeStoryArray(story:RealmStory) {
        guard let storyArray = RealmStory.GetAllObjects()?.filter("novelID = %@", story.novelID) else { return }
        let storyID = story.id
        self.storyArrayObserverToken = storyArray.observe({ [weak self] (changes) in
            switch changes {
            case .initial(_):
                break
            case .update(_, let deletions, let insertions, _):
                if deletions.count > 0 || insertions.count > 0 {
                    guard let story = RealmStory.SearchStoryFrom(storyID: storyID) else {
                        // 表示しているstoryが削除されたっぽい
                        DispatchQueue.main.async {
                            print("SpeechViewController: current story deleted? popViewController")
                            self?.navigationController?.popViewController(animated: true)
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        print("SpeechViewController: story delete or inserted. update display")
                        self?.setStoryWithoutSetToStorySpeaker(story: story)
                    }
                }
            case .error(_):
                break
            }
        })
    }
    
    @objc func setSpeechModSetting(sender: UIMenuItem){
        guard let range = self.textView.selectedTextRange, let text = self.textView.text(in: range) else { return }
        if text.count <= 0 { return }
        let nextViewController = CreateSpeechModSettingViewControllerSwift()
        if let modSetting = RealmSpeechModSetting.GetAllObjects()?.filter("before = %@", text).first {
            nextViewController.targetSpeechModSettingID = modSetting.id
        }else{
            let modSetting = RealmSpeechModSetting()
            modSetting.before = text
            if let realm = try? RealmUtil.GetRealm() {
                try! realm.write {
                    realm.add(modSetting, update: true)
                }
            }
            nextViewController.targetSpeechModSettingID = modSetting.id
        }
        self.navigationController?.pushViewController(nextViewController, animated: true)
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
            if let nextViewController = segue.destination as? EditBookViewController, let storyID = self.storyID, let novel = RealmNovel.SearchNovelFrom(novelID: RealmStory.StoryIDToNovelID(storyID: storyID)) {
                nextViewController.targetNovel = novel
            }
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
    

    @objc func detailButtonClicked(_ sender: UIBarButtonItem) {
        pushToEditStory()
    }
    
    @objc func shareButtonClicked(_ sender: UIBarButtonItem) {
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
    
    @objc func urlRefreshButtonClicked(_ sender: UIBarButtonItem) {
        // TODO: not implemented yet.
    }
    @objc func safariButtonClicked(_ sender: UIBarButtonItem) {
        guard let storyID = self.storyID, let urlString = RealmNovel.SearchNovelFrom(novelID: RealmStory.StoryIDToNovelID(storyID: storyID))?.url else {
            return
        }
        /// XXX 謎の数字 2 が書いてある。WKWebView のタブの index なんだけども、なろう検索タブが消えたりすると変わるはず……
        let targetTabIndex = 2
        guard let viewController = self.tabBarController?.viewControllers?[targetTabIndex] as? ImportFromWebPageViewController, let url = URL(string: urlString) else { return }
        viewController.openTargetUrl = url
        self.tabBarController?.selectedIndex = targetTabIndex
    }
    @objc func startStopButtonClicked(_ sender: UIBarButtonItem) {
        if self.storySpeaker.isPlayng {
            self.storySpeaker.StopSpeech()
        }else{
            let range = self.textView.selectedRange
            storySpeaker.readLocation = range.location
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
    func storySpeakerStoryChanged(story:RealmStory){
        setStoryWithoutSetToStorySpeaker(story: story)
        if self.isNeedResumeSpeech {
            self.isNeedResumeSpeech = false
            self.storySpeaker.StartSpeech(withMaxSpeechTimeReset: true)
        }
    }


    @IBAction func chapterSliderValueChanged(_ sender: Any) {
        guard let storyID = self.storyID, let story = RealmStory.SearchStoryFrom(storyID: RealmStory.CreateUniqueID(novelID: RealmStory.StoryIDToNovelID(storyID: storyID), chapterNumber: Int(self.chapterSlider.value + 0.5))) else {
            return
        }
        self.chapterSlider.value = Float(story.chapterNumber)
        self.storySpeaker.SetStory(story: story)
    }
    @IBAction func previousChapterButtonClicked(_ sender: Any) {
        self.storySpeaker.LoadPreviousChapter()
    }
    @IBAction func nextChapterButtonClicked(_ sender: Any) {
        self.storySpeaker.LoadNextChapter()
    }

}
