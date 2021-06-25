//
//  UITabBarControllerExtension.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/06/23.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//
// from: https://gist.github.com/brindy/b93d0cd0ce4ca3560225ade23f4cf35e

import Foundation

extension UITabBarController {
    var isVisible:Bool {
        get {
            return tabBar.frame.origin.y < UIScreen.main.bounds.height
        }
    }
    
    // Inspired by https://gist.github.com/krodak/2bd8139c5f69b9434008
    func setTabBarVisible(visible:Bool, animated:Bool, animateCompletion: (()->Void)?) {
        
        // bail if the current state matches the desired state
        guard (isVisible != visible) else { return }
        
        // get a frame calculation ready
        let frame = tabBar.frame
        let height = frame.size.height
        let offsetY = (visible ? -height : height)
        
        // zero duration means no animation
        let duration:TimeInterval = (animated ? 0.3 : 0.0)
        
        //  animate the tabBar
        let animator = UIViewPropertyAnimator(duration: duration, curve: .linear) {
            self.tabBar.frame = frame.offsetBy(dx: 0, dy: offsetY)
            self.view.frame = CGRect(x:0,y:0,width: self.view.frame.width, height: self.view.frame.height + offsetY)
            self.view.setNeedsDisplay()
            self.view.layoutIfNeeded()
        }
        animator.addCompletion { pos in
            animateCompletion?()
        }
        animator.startAnimation()
    }
}
