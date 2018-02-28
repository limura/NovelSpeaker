//
//  DebugLogViewControllerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/25.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit

class DebugLogViewControllerSwift: UIViewController {
    @IBOutlet weak var logTextView: UITextView!
    
    var m_SearchString = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "DebugLogViewControllerSwift viewDidLoad", data: [:])

        // Do any additional setup after loading the view.
        updateLogText()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        updateLogText()
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    func updateLogText() {
        let logStringArray = GlobalDataSingleton.getInstance().getLogStringArray()
        var logResult = ""
        for logString in logStringArray! {
            guard let logString = logString as? String else {
                continue
            }
            if self.m_SearchString.count > 0 || false {
                if !logString.contains(self.m_SearchString) {
                    continue
                }
            }
            logResult += logString + "\r\n"
        }
        self.logTextView.text = logResult
    }
    
    @IBAction func clearButtonClicked(_ sender: Any) {
        GlobalDataSingleton.getInstance().clearLogString()
        updateLogText()
    }
    @IBAction func searchButtonClicked(_ sender: Any) {
        EasyDialog.Builder(self)
        .textField(tag: 100, placeholder: "search string", content: m_SearchString, keyboardType: .default, secure: false, focusKeyboard: true, borderStyle: .roundedRect)
        .addButton(title: "Search") { (dialog) in
            let searchTextField = dialog.view.viewWithTag(100) as! UITextField
            let searchString = searchTextField.text ?? ""
            self.m_SearchString = searchString
            self.updateLogText()
            DispatchQueue.main.async {
                dialog.dismiss(animated: true, completion: nil)
            }
        }
        .build().show()
    }
    
}
