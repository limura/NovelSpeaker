//
//  TextSizeSettingViewControllerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/16.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class TextSizeSettingViewControllerSwift: UIViewController {
    @IBOutlet weak var textSizeSlider: UISlider!
    @IBOutlet weak var sampleTextTextView: UITextView!

    var displaySettingObserbeToken:NotificationToken? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting {
            setFont(displaySetting: displaySetting)
            displaySettingObserbeToken = displaySetting.observe { (change) in
                switch change {
                case .change(_):
                    self.setFontFromRealm()
                case .error(_):
                    break
                case .deleted:
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
        
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: NSLocalizedString("TextSizeSettingViewController_FontSettingTitle", comment: "字体設定"), style: .plain, target: self, action: #selector(fontSettingButtonClicked(_:)))
        ]
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    func setFontFromRealm() {
        if let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting {
            self.setFont(displaySetting: displaySetting)
        }
    }
    
    func setFont(displaySetting:RealmDisplaySetting) {
        DispatchQueue.main.async {
            self.textSizeSlider.value = displaySetting.textSizeValue
            self.sampleTextTextView.font = displaySetting.font
        }
    }
    
    @objc func fontSettingButtonClicked(_ sender: UIBarButtonItem) {
        let nextViewController = FontSelectViewController()
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    @IBAction func textSizeSliderChanged(_ sender: Any) {
        if let realm = try? RealmUtil.GetRealm(), let displaySetting = RealmGlobalState.GetInstance()?.defaultDisplaySetting, let token = self.displaySettingObserbeToken {
            realm.beginWrite()
            displaySetting.textSizeValue = self.textSizeSlider.value
            try! realm.commitWrite(withoutNotifying: [token])
            self.setFont(displaySetting: displaySetting)
        }
    }
    
}
