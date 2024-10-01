//
//  FloatingWindowViewController.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2024/09/28.
//  Copyright © 2024 IIMURA Takuji. All rights reserved.
//

import UIKit

class FloatingWindowViewController: UIViewController {
    private var invisibleGuide: UIView!
    private var floatingWindow: UIView!
    private var contentStackView: UIStackView!
    //private var dragHandle: UILabel!
    private var dragHandle: UIImageView!
    private var parentVC:UIViewController!
    
    // UI要素への参照 (複数のUILabelやUITextFieldを保持)
    private var labelMap: [String: UILabel] = [:]
    private var textFieldMap: [String: UITextField] = [:]
    private var buttonMap: [String: UIButton] = [:]
    
    // フローティングウインドウ自体の縦位置のconstraint
    private var invisibleGuideHeightConstraint: NSLayoutConstraint? = nil
    
    var topLimitPercentage = 0.1
    var bottomLimitPercentage = 0.15
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        self.overrideUserInterfaceStyle = .unspecified
    }
    
    // フローティングウィンドウを表示する
    func showFloatingWindow(in parentVC: UIViewController, yPositionFactor: CGFloat = 0.5, topLimitPercentage:CGFloat = 0.1, bottomLimitPercentage:CGFloat = 0.1) {
        guard floatingWindow == nil else { return }
        self.parentVC = parentVC
        
        var yPositionFactorV:CGFloat = 0.1
        if yPositionFactor < topLimitPercentage {
            yPositionFactorV = topLimitPercentage
        }
        if yPositionFactor > bottomLimitPercentage {
            yPositionFactorV = bottomLimitPercentage
        }
        self.topLimitPercentage = topLimitPercentage
        self.bottomLimitPercentage = bottomLimitPercentage
        
        invisibleGuide = UIView()
        //invisibleGuide.backgroundColor = .lightGray
        invisibleGuide.isHidden = true
        invisibleGuide.translatesAutoresizingMaskIntoConstraints = false
        parentVC.view.addSubview(invisibleGuide)
        
        // フローティングウィンドウの作成
        floatingWindow = UIView()
        floatingWindow.backgroundColor = .systemGray6
        floatingWindow.layer.cornerRadius = 5
        floatingWindow.layer.borderWidth = 1.5
        floatingWindow.layer.borderColor = UIColor.systemGreen.cgColor // TODO: CGColor だとダークモード・ライトモードでは変わらないけどまぁ……いいか……？
        floatingWindow.translatesAutoresizingMaskIntoConstraints = false
        parentVC.view.addSubview(floatingWindow)

        invisibleGuideHeightConstraint = invisibleGuide.heightAnchor.constraint(equalTo: parentVC.view.heightAnchor, multiplier: yPositionFactorV)
        NSLayoutConstraint.activate([
            invisibleGuide.topAnchor.constraint(equalTo: parentVC.view.safeAreaLayoutGuide.topAnchor),
            invisibleGuide.leadingAnchor.constraint(equalTo: parentVC.view.leadingAnchor),
            invisibleGuide.trailingAnchor.constraint(equalTo: parentVC.view.trailingAnchor),
            invisibleGuideHeightConstraint!,

            floatingWindow.widthAnchor.constraint(lessThanOrEqualTo: parentVC.view.widthAnchor, multiplier: 0.98),
            floatingWindow.centerXAnchor.constraint(equalTo: parentVC.view.centerXAnchor),
            floatingWindow.centerYAnchor.constraint(equalTo: invisibleGuide.bottomAnchor),
        ])
        
        // StackViewの作成
        contentStackView = UIStackView()
        contentStackView.axis = .horizontal
        contentStackView.spacing = 12
        contentStackView.alignment = .fill
        contentStackView.distribution = .fillProportionally
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        floatingWindow.addSubview(contentStackView)
        
        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: floatingWindow.leadingAnchor, constant: 8),
            contentStackView.topAnchor.constraint(equalTo: floatingWindow.topAnchor, constant: 4),
            contentStackView.bottomAnchor.constraint(equalTo: floatingWindow.bottomAnchor, constant: -4),
            // dragHandle分の余白はdragHandleからのconstraintにするのでdragHandleを作ってから登録します
        ])
        
        // ドラッグ用ハンドルの作成
        // line.3.horizontal は iOS 15 かららしいので多分nilが返ることはないんじゃないかな……？
        dragHandle = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        dragHandle.tintColor = .label
        dragHandle.contentMode = .scaleAspectFit
        dragHandle.isUserInteractionEnabled = true
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        floatingWindow.addSubview(dragHandle)
        /*
         // "line.3.horizontal" が使えない場合は "☰" で逃げられないことはないけど UILabel に変わるのでDynamicType対応とかが必要
        dragHandle = UILabel()
        dragHandle.backgroundColor = .red
        dragHandle.text = "☰"
        dragHandle.textAlignment = .center
        dragHandle.isUserInteractionEnabled = true
        dragHandle.adjustsFontForContentSizeCategory = true
        dragHandle.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        floatingWindow.addSubview(dragHandle)
         */
        NSLayoutConstraint.activate([
            //dragHandle.widthAnchor.constraint(equalToConstant: 40),
            dragHandle.trailingAnchor.constraint(equalTo: floatingWindow.trailingAnchor, constant: -8),
            dragHandle.topAnchor.constraint(equalTo: floatingWindow.topAnchor, constant: 4),
            dragHandle.bottomAnchor.constraint(equalTo: floatingWindow.bottomAnchor, constant: -4),
            dragHandle.heightAnchor.constraint(equalTo: contentStackView.heightAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: dragHandle.leadingAnchor, constant: -8),
        ])
        
        // ドラッグジェスチャーを追加
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrag))
        dragHandle.addGestureRecognizer(panGesture)
    }
    
    // ラベルを追加し、Identityを返す
    @discardableResult
    func addLabel(text: String, identity: String) -> String {
        let label = UILabel()
        label.text = text
        label.adjustsFontForContentSizeCategory = true // DynamicType対応
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.setContentHuggingPriority(.required, for: .horizontal)
        contentStackView.addArrangedSubview(label)
        labelMap[identity] = label
        return identity
    }
    
    // テキストフィールドを追加し、Identityを返す
    @discardableResult
    func addTextField(placeholder: String, identity: String) -> String {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.adjustsFontForContentSizeCategory = true // DynamicType対応
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStackView.addArrangedSubview(textField)
        textFieldMap[identity] = textField
        return identity
    }
    
    // ボタンを追加し、Identityを返す
    @discardableResult
    func addButton(title: String, identity: String, action: @escaping () -> Void) -> String {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.adjustsFontForContentSizeCategory = true // DynamicType対応
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button.setContentHuggingPriority(.required, for: .horizontal)
        contentStackView.addArrangedSubview(button)
        button.addAction(UIAction(handler: { _ in action() }), for: .touchUpInside)
        buttonMap[identity] = button
        return identity
    }
    
    // Identityを使ってUIButtonの状態を取得・更新
    func getButtonState(identity: String) -> Bool? {
        return buttonMap[identity]?.isEnabled
    }
    
    func setButtonState(identity: String, isEnabled: Bool) {
        buttonMap[identity]?.isEnabled = isEnabled
    }
    
    // Identityを使ってUILabelのテキストを取得・更新
    func getLabelText(identity: String) -> String? {
        return labelMap[identity]?.text
    }
    
    func setLabelText(identity: String, text: String) {
        labelMap[identity]?.text = text
    }
    
    // Identityを使ってUITextFieldのテキストを取得・更新
    func getTextFieldText(identity: String) -> String? {
        return textFieldMap[identity]?.text
    }
    
    func setTextFieldText(identity: String, text: String) {
        textFieldMap[identity]?.text = text
    }
    
    // ドラッグハンドルの表示・非表示切り替え
    func setDragHandleHidden(_ hidden: Bool) {
        dragHandle.isHidden = hidden
        
        /*
        // ドラッグハンドルの表示に応じて横幅を調整
        let constant: CGFloat = hidden ? -8 : -48
        if let trailingConstraint = contentStackView.constraints.first(where: { $0.identifier == "trailingConstraint" }) {
            trailingConstraint.constant = constant
        }
         */
        
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
    // フローティングウィンドウをドラッグで移動
    @objc private func handleDrag(gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        
        if let floatingWindow = floatingWindow {
            // 画面の向きによってY軸と思う値が変わってしまうようなのでそこに対応しておきます。(´・ω・`)
            let y:CGFloat
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                y = -translation.x
            case .landscapeRight:
                y = translation.x
            case .portrait:
                y = translation.y
            case .portraitUpsideDown:
                y = -translation.y
            default:
                y = translation.y
            }
            /*
            floatingWindow.center = CGPoint(x: floatingWindow.center.x, y: floatingWindow.center.y + y)
             */
            // 現在のフローティングウィンドウの位置を取得
            var newY = floatingWindow.frame.minY + y
            
            // 移動範囲の制限を適用
            let topLimit = self.parentVC.view.frame.height * self.topLimitPercentage
            let bottomLimit = self.parentVC.view.frame.height * (1 - self.bottomLimitPercentage) - floatingWindow.frame.height
            newY = max(topLimit, min(newY, bottomLimit))
            
            // フローティングウィンドウの位置を更新
            floatingWindow.frame.origin.y = newY
            gesture.setTranslation(.zero, in: view)

            if gesture.state == .ended {
                // Calculate new multiplier for invisibleGuide height
                let newY = floatingWindow.frame.minY
                let totalHeight = parentVC.view.frame.height
                let newMultiplier = newY / totalHeight
                
                // Update invisibleGuide height constraint
                invisibleGuideHeightConstraint?.isActive = false
                invisibleGuideHeightConstraint = invisibleGuide.heightAnchor.constraint(equalTo: self.parentVC.view.heightAnchor, multiplier: newMultiplier)
                invisibleGuideHeightConstraint?.isActive = true
            }
        }
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let keyboardHeight = keyboardFrame.height
            let windowMaxY = floatingWindow.frame.maxY
            let visibleHeight = view.frame.height - keyboardHeight
            
            if windowMaxY > visibleHeight {
                let offset = windowMaxY - visibleHeight
                floatingWindow.frame.origin.y -= offset + 20
            }
        }
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        UIView.animate(withDuration: 0.3) {
            self.floatingWindow.frame.origin.y = 100
        }
    }
    
    @objc func closeFloatingWindow() {
        labelMap.removeAll()
        textFieldMap.removeAll()
        floatingWindow.removeFromSuperview()
        floatingWindow = nil
    }
    
    @objc var isFloatingWindowOpened: Bool {
        get {
            return floatingWindow != nil
        }
    }
}
