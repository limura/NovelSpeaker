//
//  EditBookViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/16.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift
import SZTextView

class EditBookViewController: UIViewController {
    public var targetNovel:RealmNovel? = nil
    
    @IBOutlet weak var titleTextField: UITextField!
    @IBOutlet weak var movePreviousButton: UIButton!
    @IBOutlet weak var moveNextButton: UIButton!
    @IBOutlet weak var chapterSlider: UISlider!
    @IBOutlet weak var storyTextView: SZTextView!
    @IBOutlet weak var addChapterButton: UIButton!
    @IBOutlet weak var deleteChapterButton: UIButton!
    @IBOutlet weak var chapterNumberIndicatorLabel: UILabel!
    @IBOutlet weak var entryButton: UIButton!
    /* TODO: 自前で配置すると色がおかしくなるので当面は封印します(´・ω・`)
    let titleTextField: UITextField = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let movePreviousButton: UIButton = UIButton(type: .system)
    let moveNextButton: UIButton = UIButton(type: .system)
    let chapterSlider: UISlider = UISlider(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let storyTextView: SZTextView = SZTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let addChapterButton: UIButton = UIButton(type: .system)
    let deleteChapterButton: UIButton = UIButton(type: .system)
    let chapterNumberIndicatorLabel: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let titleLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    let entryButton = UIButton(type: .system)
    */
    
    @IBOutlet weak var storyTextViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var chapterNumberIndicatorLabelWidthConstraint: NSLayoutConstraint!
    //var storyTextViewBottomConstraint:NSLayoutConstraint? = nil
    //var chapterNumberIndicatorLabelWidthConstraint:NSLayoutConstraint? = nil
    var fontSizeObserveToken:NotificationToken? = nil
    var currentStory:RealmStory = RealmStory()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        initWidgets()
        if let novel = targetNovel {
            applyNovel(novel: novel)
        }else{
            navigationController?.popViewController(animated: true)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // safe area guide は viewDidLoad() では受け取れなくて viewDidAppear() で受け取るとかなんとか？
        // https://i-app-tec.com/ios/iphone-safearea.html
        startObserve()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        endObserve()
        saveCurrentStory()
        saveCurrentNovel()
    }
    
    func initWidgets() {
        if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting {
            storyTextView.font = displaySetting.font
        }
        
        storyTextView.placeholder = NSLocalizedString("EditBookViewController_StoryPlaceholderText", comment: "ここに本文を入力します。")

        // ボタンは内部の titleLabel の Dynamic Type 対応を storyboard 側でできないぽいので自前で指定します。(´・ω・`)
        for button in [movePreviousButton, moveNextButton, addChapterButton, deleteChapterButton, entryButton] {
            button?.titleLabel?.numberOfLines = 0
            button?.titleLabel?.adjustsFontForContentSizeCategory = true
        }
    }
    
    func applyNovel(novel:RealmNovel) {
        titleTextField.text = novel.title
        if let story = novel.readingChapter {
            setStory(story: story, novel: novel)
        }else if let story = novel.linkedStorys?.first {
            print("load chapter: \(story.chapterNumber)")
            setStory(story: story, novel: novel)
        }else{
            let story = RealmStory.CreateNewStory(novel: novel, chapterNumber: 1)
            currentStory = story
            print("create new chapter: 1, \(story.id)")
            saveCurrentStory()
            setStory(story: story, novel: novel)
        }
    }
    
    // TODO: 自前でWidgetsを新規作成して配置すると色が全然駄目なので封印します。
    /*
    func initWidgets() {
        // AutoLayout のみを使うように translatesAutoresizingMaskIntoConstraints に false を入れる。
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        movePreviousButton.translatesAutoresizingMaskIntoConstraints = false
        moveNextButton.translatesAutoresizingMaskIntoConstraints = false
        chapterSlider.translatesAutoresizingMaskIntoConstraints = false
        storyTextView.translatesAutoresizingMaskIntoConstraints = false
        addChapterButton.translatesAutoresizingMaskIntoConstraints = false
        deleteChapterButton.translatesAutoresizingMaskIntoConstraints = false
        chapterNumberIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        entryButton.translatesAutoresizingMaskIntoConstraints = false

        // 固定のテキスト等を設定する
        titleLabel.text = NSLocalizedString("EditBookViewController_TitleText", comment: "小説名")
        titleTextField.text = targetNovel?.title
        entryButton.titleLabel?.text = NSLocalizedString("EditBookViewController_EntryButtonTitle", comment: "登録")
        addChapterButton.titleLabel?.text = NSLocalizedString("EditBookViewController_AddNewChapterButtonTitle", comment: "新しく章を追加")
        deleteChapterButton.titleLabel?.text = NSLocalizedString("EditBookViewController_DeleteChapterButtonTitle", comment: "この章を削除")
        movePreviousButton.titleLabel?.text = "＜"
        moveNextButton.titleLabel?.text = "＞"

        // 文字が入力できる部分は枠をつけたりしておきます
        titleTextField.borderStyle = .roundedRect
        storyTextView.placeholder = NSLocalizedString("EditBookViewController_StoryPlaceholderText", comment: "ここに本文を入力します。")
        
        // Dynamic Type に対応します
        titleTextField.font = UIFont.preferredFont(forTextStyle: .body)
        titleTextField.adjustsFontForContentSizeCategory = true
        movePreviousButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        movePreviousButton.titleLabel?.adjustsFontForContentSizeCategory = true
        moveNextButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        moveNextButton.titleLabel?.adjustsFontForContentSizeCategory = true
        // storyTextView は自前のフォント設定を使います
        if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting {
            storyTextView.font = displaySetting.font
        }
        addChapterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        addChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        deleteChapterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        deleteChapterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        chapterNumberIndicatorLabel.font = UIFont.preferredFont(forTextStyle: .body)
        chapterNumberIndicatorLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        entryButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        entryButton.titleLabel?.adjustsFontForContentSizeCategory = true

        if let realm = try? RealmUtil.GetRealm(), let globalState = RealmGlobalState.GetInstance() {
            try! realm.write {
                globalState.isDarkThemeEnabled = true
            }
            globalState.ApplyThemaToAppearance()
        }else{
            RealmGlobalState.FallbackApplyAppearance()
        }
        
        titleTextField.tintAdjustmentMode = .normal
        movePreviousButton.tintAdjustmentMode = .normal
        moveNextButton.tintAdjustmentMode = .normal
        chapterSlider.tintAdjustmentMode = .normal
        storyTextView.tintAdjustmentMode = .normal
        addChapterButton.tintAdjustmentMode = .normal
        deleteChapterButton.tintAdjustmentMode = .normal
        chapterNumberIndicatorLabel.tintAdjustmentMode = .normal
        titleLabel.tintAdjustmentMode = .normal
        entryButton.tintAdjustmentMode = .normal

        // 固定のテキストを設定したものについてはサイズをそのテキストの大きさに自動調節しておいてもらいます
        titleLabel.sizeToFit()
        entryButton.sizeToFit()
        addChapterButton.sizeToFit()
        deleteChapterButton.sizeToFit()
        movePreviousButton.sizeToFit()
        moveNextButton.sizeToFit()
        
        // self.view の配下に入れます
        self.view.addSubview(titleTextField)
        self.view.addSubview(movePreviousButton)
        self.view.addSubview(moveNextButton)
        self.view.addSubview(chapterSlider)
        self.view.addSubview(storyTextView)
        self.view.addSubview(addChapterButton)
        self.view.addSubview(deleteChapterButton)
        self.view.addSubview(chapterNumberIndicatorLabel)
        self.view.addSubview(titleLabel)
        self.view.addSubview(entryButton)
        
        // AutoLayout で整列させます
        let guide:UILayoutGuide
        if #available(iOS 11.0, *) {
            guide = self.view.safeAreaLayoutGuide
        } else {
            guide = self.view.layoutMarginsGuide
        }
        // 一段目
        titleLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8).isActive = true
        titleLabel.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: 8).isActive = true
        titleLabel.widthAnchor.constraint(equalToConstant: titleLabel.frame.width).isActive = true
        titleLabel.heightAnchor.constraint(equalToConstant: titleLabel.frame.height).isActive = true
        titleTextField.leftAnchor.constraint(equalTo: titleLabel.rightAnchor, constant: 8).isActive = true
        titleTextField.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor).isActive = true
        titleTextField.rightAnchor.constraint(equalTo: entryButton.leftAnchor, constant: 8).isActive = true
        entryButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor).isActive = true
        entryButton.rightAnchor.constraint(equalTo: guide.rightAnchor, constant: -8).isActive = true
        entryButton.widthAnchor.constraint(equalToConstant: entryButton.frame.width).isActive = true
        // 二段目
        deleteChapterButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8).isActive = true
        deleteChapterButton.rightAnchor.constraint(equalTo: guide.rightAnchor, constant: -8).isActive = true
        addChapterButton.rightAnchor.constraint(equalTo: deleteChapterButton.leftAnchor, constant: 8).isActive = true
        addChapterButton.centerYAnchor.constraint(equalTo: deleteChapterButton.centerYAnchor).isActive = true
        // 三段目
        movePreviousButton.topAnchor.constraint(equalTo: deleteChapterButton.bottomAnchor, constant: 8).isActive = true
        movePreviousButton.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: 8).isActive = true
        chapterSlider.leftAnchor.constraint(equalTo: movePreviousButton.rightAnchor, constant: 8).isActive = true
        chapterSlider.centerYAnchor.constraint(equalTo: movePreviousButton.centerYAnchor).isActive = true
        chapterSlider.rightAnchor.constraint(equalTo: chapterNumberIndicatorLabel.leftAnchor, constant: 8).isActive = true
        chapterNumberIndicatorLabel.centerYAnchor.constraint(equalTo: movePreviousButton.centerYAnchor).isActive = true
        chapterNumberIndicatorLabel.rightAnchor.constraint(equalTo: moveNextButton.leftAnchor, constant: 8).isActive = true
        chapterNumberIndicatorLabelWidthConstraint = chapterNumberIndicatorLabel.widthAnchor.constraint(equalToConstant: chapterNumberIndicatorLabel.frame.width)
        chapterNumberIndicatorLabelWidthConstraint?.isActive = true
        moveNextButton.centerYAnchor.constraint(equalTo: movePreviousButton.centerYAnchor).isActive = true
        moveNextButton.rightAnchor.constraint(equalTo: guide.rightAnchor, constant: -8).isActive = true
        /// 四段目
        storyTextView.topAnchor.constraint(equalTo: movePreviousButton.bottomAnchor, constant: 8).isActive = true
        storyTextView.leftAnchor.constraint(equalTo: guide.leftAnchor, constant: 8).isActive = true
        storyTextView.rightAnchor.constraint(equalTo: guide.rightAnchor, constant: -8).isActive = true
        storyTextViewBottomConstraint = storyTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8)
        storyTextViewBottomConstraint?.isActive = true
        
        // イベントハンドラを設定しておきます
        entryButton.addTarget(self, action: #selector(entryButtonClicked(_:)), for: .touchUpInside)
        movePreviousButton.addTarget(self, action: #selector(movePreviousButtonClicked(_:)), for: .touchUpInside)
        moveNextButton.addTarget(self, action: #selector(moveNextButtonClicked(_:)), for: .touchUpInside)
        chapterSlider.addTarget(self, action: #selector(chapterSliderChanged(_:)), for: .valueChanged)
        addChapterButton.addTarget(self, action: #selector(addChapterButtonClicked(_:)), for: .touchUpInside)
        deleteChapterButton.addTarget(self, action: #selector(deleteChapterButtonClicked(_:)), for: .touchUpInside)
    }
     */
    
    // キーボードが現れたイベントを拾って constraint を書き換えてやらないとキーボードに隠れてしまう(´・ω・`)
    func startObserve() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willShowKeyboardEventHandler(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(willHideKeyboardEventHandler(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        // storyTextView は自前のフォント設定を使うので、それが更新されるのを監視しておきます
        if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting {
            fontSizeObserveToken = displaySetting.observe({ (change) in
                switch change {
                case .change(_):
                    if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting {
                        DispatchQueue.main.async {
                            self.storyTextView.font = displaySetting.font
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
    func endObserve() {
        let center = NotificationCenter.default
        center.removeObserver(self)
    }

    @objc func willShowKeyboardEventHandler(notification:Notification) {
        guard let userInfo = notification.userInfo, let rect = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else {
            return
        }

        let guide:UILayoutGuide
        if #available(iOS 11.0, *) {
            guide = self.view.safeAreaLayoutGuide
        } else {
            guide = self.view.layoutMarginsGuide
        }

        // 一番下を決定している Window の constraint を書き換える
        self.view.layoutIfNeeded()
        if let constraint = self.storyTextViewBottomConstraint {
            self.storyTextView.removeConstraint(constraint)
        }
        self.storyTextViewBottomConstraint = self.storyTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: 8 - rect.size.height + self.bottomLayoutGuide.length)
        self.storyTextViewBottomConstraint?.isActive = true
        UIView.animate(withDuration: TimeInterval(duration.floatValue)) {
            self.view.layoutIfNeeded()
        }
    }
    @objc func willHideKeyboardEventHandler(notification:Notification) {
        guard let userInfo = notification.userInfo, let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else {
            return
        }

        let guide:UILayoutGuide
        if #available(iOS 11.0, *) {
            guide = self.view.safeAreaLayoutGuide
        } else {
            guide = self.view.layoutMarginsGuide
        }
        self.view.layoutIfNeeded()
        if let constraint = self.storyTextViewBottomConstraint {
            self.storyTextView.removeConstraint(constraint)
        }
        self.storyTextViewBottomConstraint = self.storyTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8)
        self.storyTextViewBottomConstraint?.isActive = true
        UIView.animate(withDuration: TimeInterval(duration.floatValue)) {
            self.view.layoutIfNeeded()
        }
    }

    func setStory(story:RealmStory, novel:RealmNovel) {
        DispatchQueue.main.async {
            if let linkedStoryArray = novel.linkedStorys {
                let maxChapterNumber = linkedStoryArray.count
                self.chapterNumberIndicatorLabel.text = "\(story.chapterNumber)/\(maxChapterNumber)"
                self.chapterNumberIndicatorLabel.removeConstraint(self.chapterNumberIndicatorLabelWidthConstraint)
                self.chapterNumberIndicatorLabel.sizeToFit()
                self.chapterNumberIndicatorLabelWidthConstraint = self.chapterNumberIndicatorLabel.widthAnchor.constraint(equalToConstant: self.chapterNumberIndicatorLabel.frame.width)
                self.chapterNumberIndicatorLabelWidthConstraint.isActive = true
                self.chapterNumberIndicatorLabel.layoutIfNeeded()
                
                self.chapterSlider.minimumValue = 1.0
                self.chapterSlider.maximumValue = Float(maxChapterNumber) + 0.01
                self.chapterSlider.value = Float(story.chapterNumber)
                
                if story.chapterNumber >= maxChapterNumber {
                    self.moveNextButton.isEnabled = false
                    self.addChapterButton.isEnabled = true
                    self.deleteChapterButton.isEnabled = true
                }else{
                    self.moveNextButton.isEnabled = true
                    self.addChapterButton.isEnabled = false
                    self.deleteChapterButton.isEnabled = false
                }
                if story.chapterNumber <= 1 {
                    self.movePreviousButton.isEnabled = false
                    // 最後の章であったとしても、最初の章は削除させない。章の無い本は存在できないので。
                    // 本の削除は本棚で行います。
                    self.deleteChapterButton.isEnabled = false
                }else{
                    self.movePreviousButton.isEnabled = true
                }
            }
            
            self.storyTextView.text = story.content
            if story.readLocation <= story.content?.count ?? 0 {
                let range = NSRange(location: story.readLocation, length: 0)
                self.storyTextView.isScrollEnabled = false
                self.storyTextView.isScrollEnabled = true
                self.storyTextView.selectedRange = range
                self.storyTextView.scrollRangeToVisible(range)
            }
            self.currentStory = story
            self.saveCurrentStory()
        }
    }
    
    func saveCurrentStory() {
        if let realm = try? RealmUtil.GetRealm() {
            try! realm.write {
                currentStory.content = storyTextView.text
                realm.add(currentStory, update: true)
            }
        }
    }
    func saveCurrentNovel() {
        if let realm = try? RealmUtil.GetRealm() {
            if let novel = targetNovel {
                try! realm.write {
                    if let title = titleTextField.text, title.count > 0 {
                        novel.title = title
                    }
                    realm.add(novel, update: true)
                }
            }
        }
    }

    @IBAction func entryButtonClicked(_ sender: Any) {
        saveCurrentNovel()
        saveCurrentStory()
        navigationController?.popViewController(animated: true)
    }
    @IBAction func movePreviousButtonClicked(_ sender: Any) {
        saveCurrentStory()
        let chapterNumber = currentStory.chapterNumber - 1
        if let novel = targetNovel, let story = novel.linkedStorys?.filter("chapterNumber = %@", chapterNumber).first {
            setStory(story: story, novel: novel)
        }else{
            print("chapter: \(chapterNumber) not found")
        }
    }
    @IBAction func moveNextButtonClicked(_ sender: Any) {
        saveCurrentStory()
        let chapterNumber = currentStory.chapterNumber + 1
        if let novel = targetNovel, let story = novel.linkedStorys?.filter("chapterNumber = %@", chapterNumber).first {
            setStory(story: story, novel: novel)
        }else{
            print("chapter: \(chapterNumber) not found")
        }
    }
    @IBAction func chapterSliderChanged(_ sender: Any) {
        saveCurrentStory()
        let chapterNumber = Int(chapterSlider.value)
        if let novel = targetNovel, let story = novel.linkedStorys?.filter("chapterNumber = %@", chapterNumber).first {
            setStory(story: story, novel: novel)
        }else{
            print("chapter: \(chapterNumber) not found")
        }
    }
    @IBAction func addChapterButtonClicked(_ sender: Any) {
        saveCurrentStory()

        if let novel = targetNovel, let lastStory = novel.linkedStorys?.sorted(byKeyPath: "chapterNumber", ascending: true).last {
            let newStory = RealmStory.CreateNewStory(novel: novel, chapterNumber: lastStory.chapterNumber + 1)
            setStory(story: newStory, novel: novel)
        }
    }
    @IBAction func deleteChapterButtonClicked(_ sender: Any) {
        // memo: 削除できるのは最後の章だけ(のはず)です。
        guard let realm = try? RealmUtil.GetRealm() else {
            return
        }
        try! realm.write {
            realm.delete(currentStory)
        }
        if let novel = targetNovel, let story = novel.linkedStorys?.sorted(byKeyPath: "chapterNumber", ascending: true).last {
            setStory(story: story, novel: novel)
        }else{
            print("last chapter not found")
        }
    }
}
