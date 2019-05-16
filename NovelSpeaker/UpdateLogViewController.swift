//
//  UpdateLogViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/16.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit

class UpdateLogViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.title = NSLocalizedString("UpdateLogViewController_Title", comment: "更新履歴")
        let logTextView = UITextView(frame: self.view.frame)
        self.view.addSubview(logTextView)
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        logTextView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        logTextView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        logTextView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        logTextView.text = NSLocalizedString("UpdateLogViewController_UpdateLog", comment: "update log")
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
}
