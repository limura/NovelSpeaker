//
//  T raitOverrideTabBarController.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2024/12/01.
//  Copyright © 2024 IIMURA Takuji. All rights reserved.
//

class TraitOverrideTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 18.0, *), NovelSpeakerUtility.IsNeedOverrideTabBarTraits() {
            //traitOverrides.verticalSizeClass = .compact
            traitOverrides.horizontalSizeClass = .compact
        } else {
            // Fallback on earlier versions
        }
    }
    
    // 表示中のコンテンツ（NavigationControllerなど）にステータスバーのスタイル決定を任せる
    override var childForStatusBarStyle: UIViewController? {
        return selectedViewController
    }

    // ステータスバーを隠すかどうかの判定も任せる（念のため）
    override var childForStatusBarHidden: UIViewController? {
        return selectedViewController
    }
}
