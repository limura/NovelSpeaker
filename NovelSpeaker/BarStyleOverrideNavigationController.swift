//
//  BarStyleOverrideNavigationController.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2026/03/08.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

class BarStyleOverrideNavigationController: UINavigationController {
    // 中に表示されている ViewController (topViewController) の設定を優先する
    override var childForStatusBarStyle: UIViewController? {
        return topViewController
    }
}
