//
//  UINavicationController+StatusBarHack.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/10/18.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit

class UINavicationController_StatusBarHack: UINavigationController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    override var childForStatusBarStyle:UIViewController? {
        get {
            return self.visibleViewController
        }
    }
}
