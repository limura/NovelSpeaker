//
//  ScrollPullAndFireHandler.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/06/27.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import Foundation
import UIKit

class ScrollPullAndFireHandler: NSObject, UIScrollViewDelegate {
    let scrollView:UIScrollView
    enum ScrollBehavior {
        case vertical
        case horizontal
    }
    var invokeMergin:CGFloat = 16
    var activeThreshold:CGFloat = 80
    var isBackwardEnabled = true
    var isForwardEnabled = true
    var m_scrollBehavior = ScrollBehavior.horizontal
    var scrollBehavior: ScrollBehavior {
        get { return m_scrollBehavior }
        set {
            setupFor(scrollBehavior: newValue)
        }
    }
    var invokeMethod:((_ isForward:Bool)->Void)? = nil

    let forwardScrollHintLabel = UILabel()
    let backwardScrollHintLabel = UILabel()

    init(parent:UIView, scrollView:UIScrollView, behavior:ScrollBehavior) {
        self.scrollView = scrollView
        super.init()
        
        self.scrollView.delegate = self

        parent.addSubview(forwardScrollHintLabel)
        parent.addSubview(backwardScrollHintLabel)
        parent.bringSubviewToFront(forwardScrollHintLabel)
        parent.bringSubviewToFront(backwardScrollHintLabel)
        forwardScrollHintLabel.alpha = 0
        forwardScrollHintLabel.numberOfLines = 0
        forwardScrollHintLabel.translatesAutoresizingMaskIntoConstraints = false
        forwardScrollHintLabel.textAlignment = .center
        backwardScrollHintLabel.alpha = 0
        backwardScrollHintLabel.numberOfLines = 0
        backwardScrollHintLabel.translatesAutoresizingMaskIntoConstraints = false
        backwardScrollHintLabel.textAlignment = .center
        self.setupFor(scrollBehavior: behavior)
    }
    
    func setColor(foreground:UIColor, background:UIColor) {
        DispatchQueue.main.async {
            self.forwardScrollHintLabel.backgroundColor = background
            self.forwardScrollHintLabel.textColor = foreground
            self.backwardScrollHintLabel.backgroundColor = background
            self.backwardScrollHintLabel.textColor = foreground
        }
    }
    
    func setAlpha(bounceLevel:CGFloat) {
        if isDragging == false {
            self.backwardScrollHintLabel.alpha = 0
            self.forwardScrollHintLabel.alpha = 0
            return
        }
        let backEnable:CGFloat = self.isBackwardEnabled ? 1 : 0
        let forwardEnable:CGFloat = self.isForwardEnabled ? 1 : 0
        if invokeMergin > activeThreshold {
            self.backwardScrollHintLabel.alpha = 1 * backEnable
            self.forwardScrollHintLabel.alpha = 1 * forwardEnable
            return
        }
        switch m_scrollBehavior {
        case .horizontal:
            if bounceLevel < -activeThreshold {
                self.backwardScrollHintLabel.alpha = 1 * backEnable
                self.forwardScrollHintLabel.alpha = 0
            }else if bounceLevel < -invokeMergin {
                self.backwardScrollHintLabel.alpha = abs(bounceLevel) / (activeThreshold - invokeMergin) * backEnable
                self.forwardScrollHintLabel.alpha = 0
            }else if bounceLevel <= invokeMergin {
                self.backwardScrollHintLabel.alpha = 0
                self.forwardScrollHintLabel.alpha = 0
            }else if bounceLevel < activeThreshold {
                self.backwardScrollHintLabel.alpha = 0
                self.forwardScrollHintLabel.alpha = abs(bounceLevel) / (activeThreshold - invokeMergin) * forwardEnable
            }else{
                self.backwardScrollHintLabel.alpha = 0
                self.forwardScrollHintLabel.alpha = 1 * forwardEnable
            }
        case .vertical:
            if bounceLevel < -activeThreshold {
                self.backwardScrollHintLabel.alpha = 0
                self.forwardScrollHintLabel.alpha = 1 * forwardEnable
            }else if bounceLevel < -invokeMergin {
                self.backwardScrollHintLabel.alpha = 0
                self.forwardScrollHintLabel.alpha = abs(bounceLevel) / (activeThreshold - invokeMergin) * forwardEnable
            }else if bounceLevel <= invokeMergin {
                self.backwardScrollHintLabel.alpha = 0
                self.forwardScrollHintLabel.alpha = 0
            }else if bounceLevel < activeThreshold {
                self.backwardScrollHintLabel.alpha = abs(bounceLevel) / (activeThreshold - invokeMergin) * backEnable
                self.forwardScrollHintLabel.alpha = 0
            }else{
                self.backwardScrollHintLabel.alpha = 1 * backEnable
                self.forwardScrollHintLabel.alpha = 0
            }
        }
    }
    
    var backwardCenterXAnchor:NSLayoutConstraint? = nil
    var backwardBottomAnchor:NSLayoutConstraint? = nil
    var backwardWidthAnchor:NSLayoutConstraint? = nil
    var forwardCenterXAnchor:NSLayoutConstraint? = nil
    var forwardTopAnchor:NSLayoutConstraint? = nil
    var forwardWidthAnchor:NSLayoutConstraint? = nil
    var backwardCenterYAnchor:NSLayoutConstraint? = nil
    var backwardLeftAnchor:NSLayoutConstraint? = nil
    var backwardHeightAnchor:NSLayoutConstraint? = nil
    var forwardCenterYAnchor:NSLayoutConstraint? = nil
    var forwardRightAnchor:NSLayoutConstraint? = nil
    var forwardHeightAnchor:NSLayoutConstraint? = nil
    func deactivateAnchors() {
        backwardCenterXAnchor?.isActive = false
        backwardBottomAnchor?.isActive = false
        backwardWidthAnchor?.isActive = false
        forwardCenterXAnchor?.isActive = false
        forwardTopAnchor?.isActive = false
        forwardWidthAnchor?.isActive = false
        backwardCenterYAnchor?.isActive = false
        backwardLeftAnchor?.isActive = false
        backwardHeightAnchor?.isActive = false
        forwardCenterYAnchor?.isActive = false
        forwardRightAnchor?.isActive = false
        forwardHeightAnchor?.isActive = false
    }
    func setLabelPositionForHorizontal(bounceLevel:CGFloat) {
        deactivateAnchors()
        let backwardBottomConstant:CGFloat
        if isBackwardEnabled == false || isDragging == false {
            backwardBottomConstant = -invokeMergin
        }else if bounceLevel < -activeThreshold {
            backwardBottomConstant = activeThreshold - invokeMergin
        }else if bounceLevel < -invokeMergin {
            backwardBottomConstant = -bounceLevel - invokeMergin
        }else{
            backwardBottomConstant = -invokeMergin
        }
        let forwardTopConstant:CGFloat
        if isForwardEnabled == false || isDragging == false {
            forwardTopConstant = invokeMergin
        }else if bounceLevel < invokeMergin {
            forwardTopConstant = invokeMergin
        }else if bounceLevel < activeThreshold {
            forwardTopConstant = -(bounceLevel - invokeMergin)
        }else{
            forwardTopConstant = -(activeThreshold - invokeMergin)
        }
        backwardCenterXAnchor = self.backwardScrollHintLabel.centerXAnchor.constraint(equalTo: self.scrollView.centerXAnchor)
        backwardBottomAnchor = self.backwardScrollHintLabel.bottomAnchor.constraint(equalTo: self.scrollView.topAnchor, constant: backwardBottomConstant)
        forwardCenterXAnchor = self.forwardScrollHintLabel.centerXAnchor.constraint(equalTo: self.scrollView.centerXAnchor)
        forwardTopAnchor = self.forwardScrollHintLabel.topAnchor.constraint(equalTo: self.scrollView.bottomAnchor, constant: forwardTopConstant)
        NSLayoutConstraint.activate([
            backwardCenterXAnchor!,
            backwardBottomAnchor!,
            forwardCenterXAnchor!,
            forwardTopAnchor!,
        ])
        //print("bounceLevel: \(bounceLevel), backwardBottomConstant: \(backwardBottomConstant), forwardTopConstant: \(forwardTopConstant)")
    }
    func setLabelPositionForVertical(bounceLevel:CGFloat) {
        deactivateAnchors()
        let backwardRightConstant:CGFloat
        if isBackwardEnabled == false || isDragging == false {
            backwardRightConstant = invokeMergin
        }else if bounceLevel > activeThreshold {
            backwardRightConstant = -(activeThreshold - invokeMergin)
        }else if bounceLevel > invokeMergin {
            backwardRightConstant = -(bounceLevel - invokeMergin)
        }else{
            backwardRightConstant = invokeMergin
        }
        let forwardLeftConstant:CGFloat
        if isForwardEnabled == false || isDragging == false {
            forwardLeftConstant = -invokeMergin
        }else if bounceLevel < -activeThreshold {
            forwardLeftConstant = activeThreshold - invokeMergin
        }else if bounceLevel < -invokeMergin {
            forwardLeftConstant = -bounceLevel - invokeMergin
        }else{
            forwardLeftConstant = -invokeMergin
        }
        backwardCenterYAnchor = self.backwardScrollHintLabel.centerYAnchor.constraint(equalTo: self.scrollView.centerYAnchor)
        backwardLeftAnchor = self.backwardScrollHintLabel.leftAnchor.constraint(equalTo: self.scrollView.rightAnchor, constant: backwardRightConstant)
        forwardCenterYAnchor = self.forwardScrollHintLabel.centerYAnchor.constraint(equalTo: self.scrollView.centerYAnchor)
        forwardRightAnchor = self.forwardScrollHintLabel.rightAnchor.constraint(equalTo: self.scrollView.leftAnchor, constant: forwardLeftConstant)
        NSLayoutConstraint.activate([
            backwardCenterYAnchor!,
            backwardLeftAnchor!,
            forwardCenterYAnchor!,
            forwardRightAnchor!,
        ])
        //print("bounceLevel: \(bounceLevel), backwardRightConstant: \(backwardRightConstant), forwardLeftConstant: \(forwardLeftConstant)")
    }
    
    func createLabelAttributedString(text:String, image:UIImage?, isVertical:Bool) -> NSAttributedString {
        let attributedString:NSMutableAttributedString
        if isVertical {
            // .verticalGlyphForm: true にしても個々の時が縦書き用の draw() になるだけで文字を縦に配列してくれるわけではないぽいのでカンジ悪く "\n" を全ての文字の間に入れるという手段で回避します。(´・ω・`)
            let enterdText = text.map({"\n" + String($0)}).joined()
            attributedString = NSMutableAttributedString(string: enterdText, attributes: [.verticalGlyphForm: true])
        }else{
            attributedString = NSMutableAttributedString(string: text)
        }
        if let image = image {
            let attachment = NSTextAttachment()
            attachment.image = image
            let imageString = NSAttributedString(attachment: attachment)
            attributedString.insert(imageString, at: 0)
        }
        return attributedString
    }
    
    func createBoldAllowImage(systemName: String) -> UIImage? {
        if #available(iOS 13.0, *) {
            return UIImage.init(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        }
        return nil
    }
    
    func setLabelTextForHorizontal(bounceLevel:CGFloat){
        if bounceLevel < -activeThreshold {
            self.backwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_BackwardHintLabelText_Active", comment: "離して前のページへ"), image: createBoldAllowImage(systemName: "chevron.up.circle.fill"), isVertical: false)
            self.forwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_ForwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.up.circle"), isVertical: false)
        }else if bounceLevel > activeThreshold {
            self.backwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_BackwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.down.circle"), isVertical: false)
            self.forwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_ForwardHintLabelText_Active", comment: "離して次のページへ"), image: createBoldAllowImage(systemName: "chevron.down.circle.fill"), isVertical: false)
        }else{
            self.backwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_BackwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.down.circle"), isVertical: false)
            self.forwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_ForwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.up.circle"), isVertical: false)
        }
        self.backwardScrollHintLabel.sizeToFit()
        self.forwardScrollHintLabel.sizeToFit()
    }
    func setLabelTextForVertical(bounceLevel:CGFloat){
        if bounceLevel < -activeThreshold {
            self.backwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_BackwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.right.circle"), isVertical: true)
            self.forwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_ForwardHintLabelText_Active", comment: "離して次のページへ"), image: createBoldAllowImage(systemName: "chevron.backward.circle.fill"), isVertical: true)
        }else if bounceLevel > activeThreshold {
            self.backwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_BackwardHintLabelText_Active", comment: "離して前のページへ"), image: createBoldAllowImage(systemName: "chevron.right.circle.fill"), isVertical: true)
            self.forwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_ForwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.backward.circle"), isVertical: true)
        }else{
            self.backwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_BackwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.backward.circle"), isVertical: true)
            self.forwardScrollHintLabel.attributedText = createLabelAttributedString(text: NSLocalizedString("ScrollPullAndFireHandler_ForwardHintLabelText_Initial", comment: "強く引っ張って・・・"), image: createBoldAllowImage(systemName: "chevron.right.circle"), isVertical: true)
        }
        self.backwardScrollHintLabel.sizeToFit()
        self.forwardScrollHintLabel.sizeToFit()
    }

    func setupFor(scrollBehavior:ScrollBehavior) {
        self.m_scrollBehavior = scrollBehavior
        DispatchQueue.main.async {
            switch scrollBehavior {
            case .horizontal:
                self.setLabelTextForHorizontal(bounceLevel: 0)
                self.setLabelPositionForHorizontal(bounceLevel: 0)
            case .vertical:
                self.setLabelTextForVertical(bounceLevel: 0)
                self.setLabelPositionForVertical(bounceLevel: 0)
            }
        }
    }
    
    func calcBouncingLevelForHorizontal(scrollView:UIScrollView) -> CGFloat {
        let scrollViewHeight = scrollView.frame.size.height
        let contentSizeHeight = scrollView.contentSize.height
        let scrollOffsetY = scrollView.contentOffset.y
        if scrollOffsetY < 0 {
            return scrollOffsetY
        }
        if scrollOffsetY > contentSizeHeight - scrollViewHeight {
            return scrollOffsetY - (contentSizeHeight - scrollViewHeight)
        }
        return 0
    }
    func calcBouncingLevelForVertical(scrollView:UIScrollView) -> CGFloat {
        let scrollviewWidth = scrollView.frame.size.width
        let contentSizeWidth = scrollView.contentSize.width
        let scrollOffsetX = scrollView.contentOffset.x
        if scrollOffsetX < 0 {
            return scrollOffsetX
        }
        if scrollOffsetX > contentSizeWidth - scrollviewWidth {
            return scrollOffsetX - (contentSizeWidth - scrollviewWidth)
        }
        return 0
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        switch m_scrollBehavior {
        case .horizontal:
            let bouncingLevel = calcBouncingLevelForHorizontal(scrollView: scrollView)
            if abs(bouncingLevel) < invokeMergin { break }
            DispatchQueue.main.async {
                self.setAlpha(bounceLevel: bouncingLevel)
                self.setLabelTextForHorizontal(bounceLevel: bouncingLevel)
                self.setLabelPositionForHorizontal(bounceLevel: bouncingLevel)
            }
        case .vertical:
            let bouncingLevel = calcBouncingLevelForVertical(scrollView: scrollView)
            if abs(bouncingLevel) < invokeMergin { break }
            DispatchQueue.main.async {
                self.setAlpha(bounceLevel: bouncingLevel)
                self.setLabelTextForVertical(bounceLevel: bouncingLevel)
                self.setLabelPositionForVertical(bounceLevel: bouncingLevel)
            }
        }
    }
    
    var isDragging = false
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isDragging = true
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        isDragging = false
        let bouncingLevel:CGFloat
        switch m_scrollBehavior {
        case .horizontal:
            bouncingLevel = calcBouncingLevelForHorizontal(scrollView: scrollView)
        case .vertical:
            bouncingLevel = calcBouncingLevelForVertical(scrollView: scrollView)
        }
        if abs(bouncingLevel) >= activeThreshold {
            setAlpha(bounceLevel: 0)
            switch m_scrollBehavior {
            case .horizontal:
                if bouncingLevel > 0 {
                    if isForwardEnabled {
                        invokeMethod?(true)
                    }
                }else{
                    if isBackwardEnabled {
                        invokeMethod?(false)
                    }
                }
            case .vertical:
                if bouncingLevel < 0 {
                    if isForwardEnabled {
                        invokeMethod?(true)
                    }
                }else{
                    if isBackwardEnabled {
                        invokeMethod?(false)
                    }
                }
            }
        }
    }
}

