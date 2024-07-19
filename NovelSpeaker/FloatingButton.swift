//
//  FloatingButton.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/12/21.
//  Copyright © 2018 IIMURA Takuji. All rights reserved.
//

import UIKit

class FloatingButton: UIView {

    /*
    // Only override draw() if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func draw(_ rect: CGRect) {
        // Drawing code
    }
    */

    @IBOutlet weak var view: UIView!
    @IBOutlet weak var button: UIButton!
    
    // ボタンが押された時に呼び出される関数
    var buttonClickedFunc:(()->Void)?
    // スクロールしていない時の UIScrollbar の場所
    var scrollViewStartPoint:CGPoint = CGPoint(x: -1, y: -1)
    // これ以上のスクロールがなされたら消える
    var maxScrollHeight = 300.0
    
    @objc public static func createNewFloatingButton() -> FloatingButton? {
        let nib = UINib.init(nibName: "FloatingButton", bundle: nil)
        let view = nib.instantiate(withOwner: self, options: nil)
        if view.count <= 0 {
            return nil
        }
        if let view = view[0] as? FloatingButton {
            return view
        }
        return nil
    }
        
    @IBAction func buttonClicked(_ sender: Any) {
        if let f = buttonClickedFunc {
            f()
        }
    }
    
    func layoutBottom(parentView:UIView, bottomConstraintAppend:CGFloat = 0.0) {
        if #available(iOS 11.0, *) {
            let view = parentView
            self.view.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -16.0 + bottomConstraintAppend).isActive = true
            self.view.leftAnchor.constraint(equalTo: view.layoutMarginsGuide.leftAnchor, constant: 8.0).isActive = true
            self.view.rightAnchor.constraint(equalTo: view.layoutMarginsGuide.rightAnchor, constant: -8.0).isActive = true
            self.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 1.0).isActive = true
        }else{
            let view = parentView
            self.view.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor, constant: -56.0 + bottomConstraintAppend).isActive = true
            self.view.leftAnchor.constraint(greaterThanOrEqualTo: view.leftAnchor, constant: 8.0).isActive = true
            self.view.rightAnchor.constraint(greaterThanOrEqualTo: view.rightAnchor, constant: 8.0).isActive = true
            self.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 1.0).isActive = true
        }
    }
    func layoutTop(parentView:UIView, topConstraintAppend:CGFloat = 0.0) {
        let view = parentView
        self.view.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 16.0 + topConstraintAppend).isActive = true
        self.view.leftAnchor.constraint(equalTo: view.layoutMarginsGuide.leftAnchor, constant: 8.0).isActive = true
        self.view.rightAnchor.constraint(equalTo: view.layoutMarginsGuide.rightAnchor, constant: -8.0).isActive = true
        self.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 1.0).isActive = true
    }
    
    @objc public func assignToView(view:UIView, currentOffset:CGPoint, text:String, animated:Bool, bottomConstraintAppend:CGFloat = 0.0, buttonClicked:@escaping () -> Void){
        if #available(iOS 11.0, *) {
            view.addSubview(self.view)
        }else{
            view.superview?.superview?.addSubview(self.view)
        }
        layoutBottom(parentView: view, bottomConstraintAppend: bottomConstraintAppend)
        if #available(iOS 13.0, *) {
            self.view.backgroundColor = UIColor.secondarySystemBackground
        } else {
            self.view.backgroundColor = UIColor.init(red: 0.94, green: 0.94, blue: 0.94, alpha: 1)
        }
        self.view.layer.cornerRadius = 5
        self.view.layer.masksToBounds = false
        self.view.layer.shadowOffset = CGSize(width: 5, height: 5)
        self.view.layer.shadowOpacity = 0.7
        self.view.layer.shadowRadius = 5
        buttonClickedFunc = buttonClicked
        button.setTitle(text, for: .normal)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button.titleLabel?.numberOfLines = 0
        self.scrollViewStartPoint = currentOffset
        if animated {
            showAnimate()
        }
    }
    
    @objc public func showAnimate(){
        self.view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        self.view.alpha = 0
        UIView.animate(withDuration: 0.25) {
            self.view.alpha = 1
            self.view.transform = CGAffineTransform(scaleX: 1, y: 1)
        }
    }
    
    @objc public func hideAnimate(){
        UIView.animate(withDuration: 0.25, animations: {
            self.view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            self.view.alpha = 0
        }) { (finished) in
            //if finished { // この finished が false で呼び出されるタイミングがあるぽいので finished は確認しないことにします
                self.view.removeFromSuperview()
            //}
        }
    }
    
    @objc public func hide(){
        if self.view != nil && self.view.superview != nil {
            self.view.removeFromSuperview()
        }
    }
    
    @objc public func scrollViewDidScroll(_ scrollView: UIScrollView) -> Bool {
        let scrollHeight = abs(Double(scrollViewStartPoint.y) - Double(scrollView.contentOffset.y))
        if scrollHeight > self.maxScrollHeight {
            if self.view != nil && self.view.superview != nil {
                self.view.removeFromSuperview()
            }
            return true;
        }
        let affineSize = CGFloat(0.3 * scrollHeight / self.maxScrollHeight)
        self.view.transform = CGAffineTransform(scaleX: 1 + affineSize, y: 1 + affineSize)
        let alpha = CGFloat(1 - scrollHeight / self.maxScrollHeight)
        self.view.alpha = alpha
        return false;
    }
    
    @objc public func initScrollPosition(point:CGPoint, scrollHeight:Double){
        scrollViewStartPoint = point
        maxScrollHeight = scrollHeight
    }
}
