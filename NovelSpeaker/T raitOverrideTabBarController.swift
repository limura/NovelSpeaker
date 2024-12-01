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
}
