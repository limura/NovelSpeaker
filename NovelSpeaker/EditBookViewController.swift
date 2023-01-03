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

class EditBookViewController: UIViewController, RealmObserverResetDelegate, UITextFieldDelegate, StorySpeakerDeletgate {
    public var targetNovelID:String = ""
    
    @IBOutlet weak var titleTextField: UITextField!
    @IBOutlet weak var movePreviousButton: UIButton!
    @IBOutlet weak var moveNextButton: UIButton!
    @IBOutlet weak var chapterSlider: UISlider!
    @IBOutlet weak var storyTextView: SZTextView!
    @IBOutlet weak var addChapterButton: UIButton!
    @IBOutlet weak var deleteChapterButton: UIButton!
    @IBOutlet weak var chapterNumberIndicatorLabel: UILabel!
    @IBOutlet weak var entryButton: UIButton!
    @IBOutlet weak var cursorMoveRightButton: UIButton!
    @IBOutlet weak var cursorMoveUpButton: UIButton!
    @IBOutlet weak var cursorMoveDownButton: UIButton!
    @IBOutlet weak var cursorMoveLeftButton: UIButton!

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
    var fontSizeObserverToken:NotificationToken? = nil
    var currentStoryID:String = ""
    let caretView = UIView()
    var startStopButtonItem = UIBarButtonItem()

    override func viewDidLoad() {
        super.viewDidLoad()

        initWidgets()
        StorySpeaker.shared.AddDelegate(delegate: self)
        RealmUtil.RealmBlock { (realm) -> Void in
            StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession:true)
            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.targetNovelID) {
                applyNovelWith(realm: realm, novelID: novel.novelID)
            }else{
                DispatchQueue.main.async {
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
        self.movePreviousButton.accessibilityLabel = NSLocalizedString("SpeechViewController_PreviousChapterButton_VoiceOverTitle", comment: "前のページ")
        self.moveNextButton.accessibilityLabel = NSLocalizedString("SpeechViewController_NextChapterButton_VoiceOverTitle", comment: "次のページ")
        self.titleTextField.clearButtonMode = .always
        self.titleTextField.delegate = self
        registNotificationCenter()
        startObserve()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    deinit {
        self.unregistNotificationCenter()
        endObserve()
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NovelDownloadQueue.shared.downloadStop()
    }

    override func viewDidDisappear(_ animated: Bool) {
        saveCurrentStory()
        saveCurrentNovel()
    }
    
    func StopObservers() {
        endObserve()
    }
    func RestartObservers() {
        StopObservers()
        startObserve()
    }
    
    func initWidgets() {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) {
                storyTextView.font = displaySetting.font
            }
        }
        
        storyTextView.placeholder = NSLocalizedString("EditBookViewController_StoryPlaceholderText", comment: "ここに本文を入力します。")

        let insets = UIEdgeInsets(top: 8, left: 8, bottom: min(50, storyTextView.frame.height / 4.0), right: 0)
        storyTextView.contentInset = insets
        //storyTextView.textContainerInset = insets
        //storyTextView.scrollIndicatorInsets = insets
        
        // ボタンは内部の titleLabel の Dynamic Type 対応を storyboard 側でできないぽいので自前で指定します。(´・ω・`)
        for button in [movePreviousButton, moveNextButton, addChapterButton, deleteChapterButton, entryButton] {
            button?.titleLabel?.numberOfLines = 0
            button?.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        
        let startStopButtonItem = UIBarButtonItem(title: NSLocalizedString("SpeechViewController_Speak", comment: "Speak"), style: .plain, target: self, action: #selector(SepakTestButtonClicked(_:)))
        self.startStopButtonItem = startStopButtonItem
        self.startStopButtonItem.accessibilityLabel = NSLocalizedString("EditBookViewController_SpeakTestButton_AccesibilityLabel", comment: "発話テストを開始する")
        self.navigationItem.rightBarButtonItems = [startStopButtonItem]
        
        self.addChapterButton.accessibilityLabel = NSLocalizedString("EditBookViewController_AddNewChapterButtonTitle", comment: "章を追加")
        self.deleteChapterButton.accessibilityLabel = NSLocalizedString("EditBookViewController_DeleteChapterButtonTitle", comment: "この章を削除")
        assignCursorKeyButtons()
        
        self.caretView.alpha = 0.4
        self.caretView.backgroundColor = UIColor.green
        self.caretView.isHidden = true
        self.storyTextView.addSubview(self.caretView)
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
    
    func applyNovelWith(realm: Realm, novelID:String) {
        guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
        titleTextField.text = novel.title
        if let story = novel.readingChapterWith(realm: realm) {
            setStory(storyID: story.storyID)
        }else if let story = novel.firstChapterWith(realm: realm) {
            print("load chapter: \(story.chapterNumber)")
            setStory(storyID: story.storyID)
        }else{
            currentStoryID = RealmStoryBulk.CreateUniqueID(novelID: novel.novelID, chapterNumber: 1)
            saveCurrentStory()
            setStory(storyID: currentStoryID)
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

        if let globalState = RealmGlobalState.GetInstance() {
            RealmUtil.Write { (realm) in
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
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) {
                fontSizeObserverToken = displaySetting.observe({ [weak self] (change) in
                    guard let self = self else { return }
                    switch change {
                    case .change(_, _):
                        DispatchQueue.main.async {
                            RealmUtil.RealmBlock { (realm) -> Void in
                                guard let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) else { return }
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
    }
    func endObserve() {
        let center = NotificationCenter.default
        center.removeObserver(self)
        fontSizeObserverToken = nil
    }
    
    /* // UIBarButtonItem に long press の物を入れるにはこんな事をすると良いぽい。
    func createLongPressImageView(image:UIImage, target: Any?, tapAction: Selector?, longPressAction: Selector?) -> UIView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        if let tapAction = tapAction {
            let tap = UITapGestureRecognizer(target: target, action: tapAction)
            view.addGestureRecognizer(tap)
        }
        if let longPressAction = longPressAction {
            let longPress = UILongPressGestureRecognizer(target: target, action: longPressAction)
            view.addGestureRecognizer(longPress)
        }
        return view
    }
    func createLongPressImageUIBarButtonItem(image: UIImage, target: Any?, tapAction: Selector?, longPressAction: Selector?) -> UIBarButtonItem {
        let view = createLongPressImageView(image: image, target: target, tapAction: tapAction, longPressAction: longPressAction)
        let button = UIBarButtonItem()

        button.customView = view
        return button
    } */

    /* // キーボードの上の方にボタンを追加する奴
    func addKeyboardBarButtonItems() {
        var newItems:[UIBarButtonItem] = []

        let leftButtonItem:UIBarButtonItem
        if #available(iOS 13.0, *), let leftButtonImage = UIImage(systemName: "arrow.left") {
            leftButtonItem = createLongPressImageUIBarButtonItem(image: leftButtonImage, target: self, tapAction: #selector(KeyboardBarButton_Left_EventHandler(_:)), longPressAction: #selector(KeyboardBarButton_LeftLongTap_EventHandler(_:)))
        } else {
            leftButtonItem = UIBarButtonItem(title: "<", style: .plain, target: self, action: #selector(KeyboardBarButton_Left_EventHandler(_:)))
        }
        leftButtonItem.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Left", comment: "左へカーソル移動")
        newItems.append(leftButtonItem)
        
        let downButtonItem:UIBarButtonItem
        if #available(iOS 13.0, *), let leftButtonImage = UIImage(systemName: "arrow.down") {
            downButtonItem = UIBarButtonItem(image: leftButtonImage, style: .plain, target: self, action: #selector(KeyboardBarButton_Down_EventHandler(_:)))
        } else {
            downButtonItem = UIBarButtonItem(title: "v", style: .plain, target: self, action: #selector(KeyboardBarButton_Down_EventHandler(_:)))
        }
        downButtonItem.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Down", comment: "下へカーソル移動")
        newItems.append(downButtonItem)
        
        let upButtonItem:UIBarButtonItem
        if #available(iOS 13.0, *), let leftButtonImage = UIImage(systemName: "arrow.up") {
            upButtonItem = UIBarButtonItem(image: leftButtonImage, style: .plain, target: self, action: #selector(KeyboardBarButton_Up_EventHandler(_:)))
        } else {
            upButtonItem = UIBarButtonItem(title: "^", style: .plain, target: self, action: #selector(KeyboardBarButton_Up_EventHandler(_:)))
        }
        upButtonItem.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Up", comment: "上へカーソル移動")
        newItems.append(upButtonItem)
        
        let rightButtonItem:UIBarButtonItem
        if #available(iOS 13.0, *), let leftButtonImage = UIImage(systemName: "arrow.right") {
            rightButtonItem = UIBarButtonItem(image: leftButtonImage, style: .plain, target: self, action: #selector(KeyboardBarButton_Right_EventHandler(_:)))
        } else {
            rightButtonItem = UIBarButtonItem(title: ">", style: .plain, target: self, action: #selector(KeyboardBarButton_Right_EventHandler(_:)))
        }
        rightButtonItem.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Right", comment: "右へカーソル移動")
        newItems.append(rightButtonItem)

        let trailingBarButtonGroup = UIBarButtonItemGroup(barButtonItems: newItems, representativeItem: nil)
        self.storyTextView.inputAssistantItem.trailingBarButtonGroups.append(trailingBarButtonGroup)
    }*/
    

    func enableCursorKeys() {
        self.cursorMoveUpButton.isEnabled = true
        self.cursorMoveDownButton.isEnabled = true
        self.cursorMoveLeftButton.isEnabled = true
        self.cursorMoveRightButton.isEnabled = true
    }
    func disableCursorKeys() {
        self.cursorMoveUpButton.isEnabled = false
        self.cursorMoveDownButton.isEnabled = false
        self.cursorMoveLeftButton.isEnabled = false
        self.cursorMoveRightButton.isEnabled = false
    }
    
    func assignLongPressRecognizer(view:UIView, target: Any?, longPressAction: Selector?){
        if let longPressAction = longPressAction {
            let longPress = UILongPressGestureRecognizer(target: target, action: longPressAction)
            longPress.minimumPressDuration = 0
            view.addGestureRecognizer(longPress)
        }
    }

    func assignCursorKeyButtons() {
        assignLongPressRecognizer(view: self.cursorMoveLeftButton, target: self, longPressAction: #selector(KeyboardBarButton_LeftLongTap_EventHandler(_:)))
        assignLongPressRecognizer(view: self.cursorMoveUpButton, target: self, longPressAction: #selector(KeyboardBarButton_UpLongTap_EventHandler(_:)))
        assignLongPressRecognizer(view: self.cursorMoveDownButton, target: self, longPressAction: #selector(KeyboardBarButton_DownLongTap_EventHandler(_:)))
        assignLongPressRecognizer(view: self.cursorMoveRightButton, target: self, longPressAction: #selector(KeyboardBarButton_RightLongTap_EventHandler(_:)))

        self.cursorMoveLeftButton.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Left", comment: "左へカーソル移動")
        self.cursorMoveDownButton.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Down", comment: "下へカーソル移動")
        self.cursorMoveUpButton.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Up", comment: "上へカーソル移動")
        self.cursorMoveRightButton.accessibilityLabel = NSLocalizedString("EditBookViewController_KeyboardBarButtonItem_Right", comment: "右へカーソル移動")
    }
    
    func cursorMoveLeft() {
        NiftyUtility.DispatchSyncMainQueue {
            guard let selectedRange = self.storyTextView.selectedTextRange, selectedRange.start.isEqual(self.storyTextView.beginningOfDocument) == false, let newPosition = self.storyTextView.position(from: selectedRange.start, offset: -1) else { return }
            self.storyTextView.selectedTextRange = self.storyTextView.textRange(from: newPosition, to: newPosition)
            self.storyTextView.scrollRangeToVisible(self.storyTextView.selectedRange)
        }
    }
    var cursorLeftButtonTouchDownTime:Date? = nil
    func LeftLongTapInterval() {
        guard let startDate = cursorLeftButtonTouchDownTime else {
            return
        }
        let currentDate = Date()
        if startDate.addingTimeInterval(0.5) < currentDate {
            self.cursorMoveLeft()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.LeftLongTapInterval()
        }
    }
    @objc func KeyboardBarButton_LeftLongTap_EventHandler(_ sender: UITapGestureRecognizer) {
        switch sender.state {
        case .began:
            cursorLeftButtonTouchDownTime = Date()
            self.cursorMoveLeft()
            LeftLongTapInterval()
        case .changed: break
        case .ended, .cancelled:
            cursorLeftButtonTouchDownTime = nil
        default:
            cursorLeftButtonTouchDownTime = nil
        }
    }
    
    func cursorMoveUp() {
        NiftyUtility.DispatchSyncMainQueue {
            guard let selectedRange = self.storyTextView.selectedTextRange else { return }
            let caretRect = self.storyTextView.caretRect(for: selectedRange.start)
            let nextY = caretRect.origin.y - caretRect.size.height * 2 / 3
            let nextCaretPoint = CGPoint(x: caretRect.origin.x, y: nextY)
            guard let newPosition = self.storyTextView.closestPosition(to: nextCaretPoint) else { return }
            self.storyTextView.selectedTextRange = self.storyTextView.textRange(from: newPosition, to: newPosition)
            //self.storyTextView.scrollRangeToVisible(self.storyTextView.selectedRange)
            self.storyTextView.scrollRectToVisible(CGRect(origin: nextCaretPoint, size: CGSize(width: 1, height: 1)), animated: false)
        }
    }
    var cursorUpButtonTouchDownTime:Date? = nil
    func UpLongTapInterval() {
        guard let startDate = cursorUpButtonTouchDownTime else {
            return
        }
        let currentDate = Date()
        if startDate.addingTimeInterval(0.5) < currentDate {
            self.cursorMoveUp()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.UpLongTapInterval()
        }
    }
    @objc func KeyboardBarButton_UpLongTap_EventHandler(_ sender: UITapGestureRecognizer) {
        switch sender.state {
        case .began:
            cursorUpButtonTouchDownTime = Date()
            self.cursorMoveUp()
            UpLongTapInterval()
        case .changed: break
        case .ended, .cancelled:
            cursorUpButtonTouchDownTime = nil
        default:
            cursorUpButtonTouchDownTime = nil
        }
    }
    
    func cursorMoveDown() {
        NiftyUtility.DispatchSyncMainQueue {
            guard let selectedRange = self.storyTextView.selectedTextRange else { return }
            let caretRect = self.storyTextView.caretRect(for: selectedRange.start)
            let nextY = caretRect.origin.y + caretRect.size.height * 3 / 2
            let nextCaretPoint = CGPoint(x: caretRect.origin.x, y: nextY)
            guard let newPosition = self.storyTextView.closestPosition(to: nextCaretPoint) else { return }
            self.storyTextView.selectedTextRange = self.storyTextView.textRange(from: newPosition, to: newPosition)
            //self.storyTextView.scrollRangeToVisible(self.storyTextView.selectedRange)
            self.storyTextView.scrollRectToVisible(CGRect(origin: nextCaretPoint, size: CGSize(width: 1, height: 1)), animated: false)
        }
    }
    var cursorDownButtonTouchDownTime:Date? = nil
    func DownLongTapInterval() {
        guard let startDate = cursorDownButtonTouchDownTime else {
            return
        }
        let currentDate = Date()
        if startDate.addingTimeInterval(0.5) < currentDate {
            self.cursorMoveDown()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.DownLongTapInterval()
        }
    }

    @objc func KeyboardBarButton_DownLongTap_EventHandler(_ sender: UITapGestureRecognizer) {
        switch sender.state {
        case .began:
            cursorDownButtonTouchDownTime = Date()
            self.cursorMoveDown()
            DownLongTapInterval()
        case .changed: break
        case .ended, .cancelled:
            cursorDownButtonTouchDownTime = nil
        default:
            cursorDownButtonTouchDownTime = nil
        }
    }
    
    func cursorMoveRight() {
        NiftyUtility.DispatchSyncMainQueue {
            guard let selectedRange = self.storyTextView.selectedTextRange, selectedRange.start.isEqual(self.storyTextView.endOfDocument) == false, let newPosition = self.storyTextView.position(from: selectedRange.start, offset: 1) else { return }
            self.storyTextView.selectedTextRange = self.storyTextView.textRange(from: newPosition, to: newPosition)
            self.storyTextView.scrollRangeToVisible(self.storyTextView.selectedRange)
        }
    }
    var cursorRightButtonTouchDownTime:Date? = nil
    func RightLongTapInterval() {
        guard let startDate = cursorRightButtonTouchDownTime else {
            return
        }
        let currentDate = Date()
        if startDate.addingTimeInterval(0.5) < currentDate {
            self.cursorMoveRight()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.RightLongTapInterval()
        }
    }
    @objc func KeyboardBarButton_RightLongTap_EventHandler(_ sender: UITapGestureRecognizer) {
        switch sender.state {
        case .began:
            cursorRightButtonTouchDownTime = Date()
            self.cursorMoveRight()
            RightLongTapInterval()
        case .changed: break
        case .ended, .cancelled:
            cursorRightButtonTouchDownTime = nil
        default:
            cursorRightButtonTouchDownTime = nil
        }
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
            constraint.isActive = false
            self.storyTextView.removeConstraint(constraint)
        }
        self.storyTextViewBottomConstraint = self.storyTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: 8 - rect.size.height + self.view.safeAreaInsets.bottom)
        self.storyTextViewBottomConstraint?.isActive = true
        UIView.animate(withDuration: TimeInterval(duration.floatValue)) {
            self.view.layoutIfNeeded()
        } completion: { result in
            DispatchQueue.main.async {
                guard let selectedRange = self.storyTextView.selectedTextRange else { return }
                let caretRect = self.storyTextView.caretRect(for: selectedRange.start)
                let nextY = max(0, caretRect.origin.y - caretRect.size.height * 2 / 3)
                let nextCaretPoint = CGPoint(x: caretRect.origin.x, y: nextY)
                self.storyTextView.scrollRectToVisible(CGRect(origin: nextCaretPoint, size: CGSize(width: 1, height: 1)), animated: false)
            }
        }
        enableCursorKeys()
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
            constraint.isActive = false
            self.storyTextView.removeConstraint(constraint)
        }
        self.storyTextViewBottomConstraint = self.storyTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8)
        self.storyTextViewBottomConstraint?.isActive = true
        UIView.animate(withDuration: TimeInterval(duration.floatValue)) {
            self.view.layoutIfNeeded()
        }
        disableCursorKeys()
    }

    func setStory(storyID:String) {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                let novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyID)
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return }
                let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
                var story:Story
                if let storyObj = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID) {
                    story = storyObj
                }else{
                    story = Story()
                    story.novelID = novelID
                    story.chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: storyID)
                    RealmUtil.WriteWith(realm: realm) { (realm) in
                        RealmStoryBulk.SetStoryWith(realm: realm, story: story)
                    }
                }
                if let maxChapterNumber = novel.lastChapterNumber {
                    self.chapterNumberIndicatorLabel.text = "\(chapterNumber)/\(maxChapterNumber)"
                    self.chapterNumberIndicatorLabel.removeConstraint(self.chapterNumberIndicatorLabelWidthConstraint)
                    self.chapterNumberIndicatorLabel.sizeToFit()
                    self.chapterNumberIndicatorLabelWidthConstraint = self.chapterNumberIndicatorLabel.widthAnchor.constraint(equalToConstant: self.chapterNumberIndicatorLabel.frame.width)
                    self.chapterNumberIndicatorLabelWidthConstraint.isActive = true
                    self.chapterNumberIndicatorLabel.layoutIfNeeded()
                    
                    self.chapterSlider.minimumValue = 1.0
                    self.chapterSlider.maximumValue = Float(maxChapterNumber) + 0.01
                    self.chapterSlider.value = Float(chapterNumber)
                    
                    self.addChapterButton.isEnabled = true
                    if chapterNumber >= maxChapterNumber {
                        self.moveNextButton.isEnabled = false
                    }else{
                        self.moveNextButton.isEnabled = true
                    }
                    self.deleteChapterButton.isEnabled = true
                    if chapterNumber <= 1 {
                        self.movePreviousButton.isEnabled = false
                        // 最後の章であった場合で、その章が最後の章だった場合は削除させません。
                        // 本の削除は本棚で行います。
                        if let lastChapterNumber = novel.lastChapterNumber, lastChapterNumber <= 1 {
                            self.deleteChapterButton.isEnabled = false
                        }
                    }else{
                        self.movePreviousButton.isEnabled = true
                    }
                }
                
                self.storyTextView.text = story.content
                let readLocation = story.readLocation(realm: realm)
                if readLocation <= story.content.count {
                    let range = NSRange(location: readLocation, length: 0)
                    self.storyTextView.isScrollEnabled = false
                    self.storyTextView.isScrollEnabled = true
                    self.storyTextView.selectedRange = range
                    self.storyTextView.scrollRangeToVisible(range)
                }
                self.currentStoryID = storyID
            }
            self.saveCurrentStory()
        }
    }
    
    func saveCurrentStory() {
        guard let content = storyTextView.text else { return }
        RealmUtil.RealmBlock { (realm) -> Void in
            var story:Story
            if let storyObj = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.currentStoryID) {
                story = storyObj
                if story.content == content { return }
            }else{
                story = Story()
                story.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: self.currentStoryID)
                story.chapterNumber = 1
            }
            story.content = content
            RealmUtil.WriteWith(realm: realm) { (realm) in
                RealmStoryBulk.SetStoryWith(realm: realm, story: story)
            }
        }
    }
    func saveCurrentNovel() {
        RealmUtil.RealmBlock { (realm) in
            guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: targetNovelID), novel.title != title else { return }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                if let title = titleTextField.text, title.count > 0 {
                    novel.title = title
                }
                realm.add(novel, update: .modified)
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
        let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: currentStoryID) - 1
        setStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: chapterNumber))
    }
    @IBAction func moveNextButtonClicked(_ sender: Any) {
        saveCurrentStory()
        let chapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: currentStoryID) + 1
        setStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: chapterNumber))
    }
    @IBAction func chapterSliderChanged(_ sender: Any) {
        saveCurrentStory()
        let chapterNumber = Int(chapterSlider.value)
        setStory(storyID: RealmStoryBulk.CreateUniqueID(novelID: targetNovelID, chapterNumber: chapterNumber))
    }
    
    func insertNewChapter(chapterNumber:Int) {
        RealmUtil.RealmBlock { (realm) in
            var story = Story()
            story.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: self.currentStoryID)
            story.chapterNumber = chapterNumber
            RealmUtil.WriteWith(realm: realm) { (realm) in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.targetNovelID) else {
                    DispatchQueue.main.async {
                        NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("EditBookViewController_InsertPageError", comment: "ページの追加に失敗しました") + ":1")
                    }
                    return
                }
                if novel.type == .URL, let url = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: story.storyID)?.url ?? novel.lastDownloadURLWith(realm: realm) {
                    // 小説の type が URL の場合は続きがダウンロードできるように近いページのURLをコピーしておきます。
                    story.url = url
                }
                let result = RealmStoryBulk.InsertStoryWith(realm: realm, story: story)
                if result == false {
                    DispatchQueue.main.async {
                        NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("EditBookViewController_InsertPageError", comment: "ページの追加に失敗しました") + ":2")
                    }
                }else{
                    setStory(storyID: story.storyID)
                }
            }
        }
    }
    
    @IBAction func addChapterButtonClicked(_ sender: Any) {
        saveCurrentStory()
        let currentChapterNumber = RealmStoryBulk.StoryIDToChapterNumber(storyID: self.currentStoryID)
        if currentChapterNumber == 1 {
            DispatchQueue.main.async {
                var builder = NiftyUtility.EasyDialogBuilder(self)
                builder = builder.title(title: NSLocalizedString("EditBookViewController_InsertChapter_HowToInsertToFirstChapter", comment: "新しいページを1ページ目に追加するか、2ページ目に追加するかを選択してください"))
                builder = builder.addButton(title: NSLocalizedString("EditBookViewController_InsertChapter_HowToInsertToFirstChapter_page1", comment: "1ページ目に追加する"), callback: { dialog in
                    dialog.dismiss(animated: false) {
                        self.insertNewChapter(chapterNumber: 1)
                    }
                })
                builder = builder.addButton(title: NSLocalizedString("EditBookViewController_InsertChapter_HowToInsertToFirstChapter_page2", comment: "2ページ目に追加する"), callback: { dialog in
                    dialog.dismiss(animated: false) {
                        self.insertNewChapter(chapterNumber: 2)
                    }
                })
                builder = builder.addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel"), callback: { dialog in
                    dialog.dismiss(animated: false)
                })
                builder.build().show()
            }
            return
        }
        self.insertNewChapter(chapterNumber: currentChapterNumber + 1)
    }

    // 3回削除するまではON/OFFは出さないようにしようかと思ったけれど、最初から出していても良さそうなので最初から出すようにします。
    var deleteChapterButtonClickCounter = 3
    var isDisableDeleteChapterConifirm = false
    @IBAction func deleteChapterButtonClicked(_ sender: Any) {
        let switchMessage:String?
        if deleteChapterButtonClickCounter >= 3 && isDisableDeleteChapterConifirm == false {
            switchMessage = NSLocalizedString("EditBookViewController_ConifirmDeleteStory_IsNeedConifirmSwitch_Message", comment: "暫くの間は確認を求めないようにする")
        }else{
            switchMessage = nil
        }
        func deleteStory() {
            NiftyUtility.EasyDialogNoButton(viewController: self, title: NSLocalizedString("EditBookViewController_NowDeleting_Title", comment: "削除中……"), message: nil) { dialog in
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.currentStoryID), story.storyID == self.currentStoryID {
                        RealmUtil.WriteWith(realm: realm) { (realm) in
                            guard RealmStoryBulk.RemoveStoryWith(realm: realm, story: story) == true else { return }
                            let (_, lastStoryChapterNumber, _) = RealmStoryBulk.CountStoryFor(realm: realm, novelID: self.targetNovelID)
                            if let newStory = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.currentStoryID) {
                                self.setStory(storyID: newStory.storyID)
                                return
                            }
                            if let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: self.targetNovelID), lastStoryChapterNumber > 0 {
                                novel.m_lastChapterStoryID = RealmStoryBulk.CreateUniqueID(novelID: self.targetNovelID, chapterNumber: lastStoryChapterNumber)
                                self.setStory(storyID: novel.m_lastChapterStoryID)
                            }
                        }
                    }
                }
                dialog.dismiss(animated: false, completion: nil)
            }
        }
        
        if isDisableDeleteChapterConifirm {
            deleteStory()
            return
        }
        
        NiftyUtility.EasyDialogTwoButtonWithSwitch(viewController: self, title: NSLocalizedString("EditBookViewController_ConifirmDeleteStory_Title", comment: "章を削除します"), message: NSLocalizedString("EditBookViewController_ConifirmDeleteStory_Message", comment: "この操作は元に戻せません。削除しますか？"), switchMessage: switchMessage, switchValue: isDisableDeleteChapterConifirm, button1Title: nil, button1Action: nil, button2Title: NSLocalizedString("EditBookViewController_ConifirmDeleteStory_OKButton", comment: "削除する")) { (switchResult) in
            self.deleteChapterButtonClickCounter += 1
            self.isDisableDeleteChapterConifirm = switchResult
            deleteStory()
        }
    }
    
    @objc func SepakTestButtonClicked(_ sender: Any) {
        if StorySpeaker.shared.isPlayng {
            RealmUtil.Write { realm in
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession:true)
            }
            return
        }
        NiftyUtility.EasyDialogNoButton(viewController: self, title: nil, message: NSLocalizedString("EditBookViewController_WaitingSpeakerSetting", comment: "本文を設定し直しています。")) { dialog in
            self.saveCurrentNovel()
            self.saveCurrentStory()
            RealmUtil.RealmBlock { realm in
                guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: self.currentStoryID) else {
                    dialog.dismiss(animated: false, completion: nil)
                    return
                }
                RealmUtil.WriteWith(realm: realm) { realm in
                    StorySpeaker.shared.setReadLocationWith(realm: realm, location: self.storyTextView.selectedRange.location)
                }
                StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: false) { story in
                    DispatchQueue.main.async {
                        RealmUtil.Write { realm in
                            dialog.dismiss(animated: false, completion: nil)
                            StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "小説編集画面(Speakボタン).\(#function)", isNeedRepeatSpeech: false)
                        }
                    }
                }
            }
        }
    }
    
    func storySpeakerStartSpeechEvent(storyID: String) {
        DispatchQueue.main.async {
            self.caretView.isHidden = false
            self.startStopButtonItem.title = NSLocalizedString("SpeechViewController_Stop", comment: "Stop")
        }
    }
    
    func storySpeakerStopSpeechEvent(storyID: String) {
        DispatchQueue.main.async {
            self.caretView.isHidden = true
            self.startStopButtonItem.title = NSLocalizedString("SpeechViewController_Speak", comment: "Speak")
        }
    }
    
    func storySpeakerUpdateReadingPoint(storyID: String, range: NSRange) {
        DispatchQueue.main.async {
            guard let position = self.storyTextView.position(from: self.storyTextView.beginningOfDocument, offset: range.location) else { return }
            let rect = self.storyTextView.caretRect(for: position)
            self.caretView.frame = CGRect(origin: rect.origin, size: CGSize(width: max(rect.width, rect.height), height: rect.height))
            self.storyTextView.scrollRectToVisible(self.caretView.frame, animated: true)
        }
    }
    
    func storySpeakerStoryChanged(story: Story) {
        setStory(storyID: story.storyID)
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textField.selectedTextRange = textField.textRange(from: textField.beginningOfDocument, to: textField.endOfDocument)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
}
