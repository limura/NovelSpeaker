//
//  SearchFloatingView.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2022/05/20.
//  Copyright © 2022 IIMURA Takuji. All rights reserved.
//

import Foundation

class SearchFloatingView: UIView, UITextFieldDelegate {
    let searchTextField:UITextField = UITextField()
    var leftButton:UIButton? = nil
    var rightButton:UIButton? = nil
    var closeButton:UIButton? = nil
    var leftButtonClickHandler:((String?)->Void)? = nil
    var rightButtonClickHandler:((String?)->Void)? = nil
    var isDeletedHandler:(()->Void)? = nil
    
    @objc public static func generate(parentView:UIView, firstText:String, leftButtonClickHandler:((String?)->Void)?, rightButtonClickHandler:((String?)->Void)?, isDeletedHandler:(()->Void)?) -> SearchFloatingView? {
        guard let leftButtonImage = UIImage(systemName: "arrowtriangle.left"), let rightButtonImage = UIImage(systemName: "arrowtriangle.right"), let closeButtonImage = UIImage(systemName: "xmark") else {
            return nil
        }
        
        let view = SearchFloatingView()
        let searchTextField = view.searchTextField
        let leftButton = UIButton.systemButton(with: leftButtonImage, target: view, action: #selector(leftButtonClicked))
        let rightButton = UIButton.systemButton(with: rightButtonImage, target: view, action: #selector(rightButtonClicked))
        let closeButton = UIButton.systemButton(with: closeButtonImage, target: view, action: #selector(closeButtonClicked))

        parentView.addSubview(view)

        view.addSubview(searchTextField)
        view.addSubview(leftButton)
        view.addSubview(rightButton)
        view.addSubview(closeButton)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        searchTextField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8).isActive = true
        searchTextField.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 8).isActive = true
        leftButton.leftAnchor.constraint(equalTo: searchTextField.rightAnchor, constant: 8).isActive = true
        rightButton.leftAnchor.constraint(equalTo: leftButton.rightAnchor, constant: 8).isActive = true
        closeButton.leftAnchor.constraint(equalTo: rightButton.rightAnchor, constant: 8).isActive = true
        closeButton.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -8).isActive = true
        leftButton.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor).isActive = true
        rightButton.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor).isActive = true
        closeButton.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor).isActive = true
        leftButton.widthAnchor.constraint(equalTo: leftButton.heightAnchor, constant: 8).isActive = true
        rightButton.widthAnchor.constraint(equalTo: rightButton.heightAnchor, constant: 8).isActive = true
        closeButton.widthAnchor.constraint(equalTo: closeButton.heightAnchor, constant: 8).isActive = true
        
        searchTextField.borderStyle = .roundedRect
        searchTextField.clearButtonMode = .always
        searchTextField.placeholder = NSLocalizedString("SearchFloatingView_SearchTextFieldPlaceHolder", comment: "検索する文字を入力します")
        searchTextField.text = firstText
        searchTextField.font = UIFont.preferredFont(forTextStyle: .body)
        searchTextField.returnKeyType = .done
        searchTextField.delegate = view

        searchTextField.adjustsFontForContentSizeCategory = true
        leftButton.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true
        rightButton.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true
        closeButton.imageView?.adjustsImageSizeForAccessibilityContentSizeCategory = true

        searchTextField.accessibilityLabel = NSLocalizedString("SearchFloatingView_AccessibilityHint_SearchTextField", comment: "検索文字を入力")
        leftButton.accessibilityLabel = NSLocalizedString("SearchFloatingView_AccessibilityHint_LeftButton", comment: "一つ前を検索")
        rightButton.accessibilityLabel = NSLocalizedString("SearchFloatingView_AccessibilityHint_RightButton", comment: "一つ後ろを検索")
        closeButton.accessibilityLabel = NSLocalizedString("SearchFloatingView_AccessibilityHint_CloseButton", comment: "検索窓を終了")

        view.leftButton = leftButton
        view.rightButton = rightButton
        view.leftButtonClickHandler = leftButtonClickHandler
        view.rightButtonClickHandler = rightButtonClickHandler
        view.isDeletedHandler = isDeletedHandler

        view.layer.cornerRadius = 5
        view.layer.masksToBounds = false
        view.layer.shadowOffset = CGSize(width: 5, height: 5)
        view.layer.shadowOpacity = 0.7
        view.layer.shadowRadius = 5
        view.backgroundColor = UIColor.white
        
        view.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: 0).isActive = true
        view.leftAnchor.constraint(equalTo: parentView.leftAnchor, constant: 8).isActive = true
        view.rightAnchor.constraint(equalTo: parentView.rightAnchor, constant: -8).isActive = true
        view.heightAnchor.constraint(equalTo: searchTextField.heightAnchor, constant: 8*2).isActive = true
        
        parentView.bringSubviewToFront(view)
        searchTextField.becomeFirstResponder()
        
        return view
    }
    
    @objc func leftButtonClicked() {
        self.searchTextField.resignFirstResponder()
        leftButtonClickHandler?(searchTextField.text)
    }
    @objc func rightButtonClicked() {
        self.searchTextField.resignFirstResponder()
        rightButtonClickHandler?(searchTextField.text)
    }
    
    @objc func closeButtonClicked() {
        self.removeFromSuperview()
        self.isDeletedHandler?()
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        rightButtonClicked()
        return false
    }
}
