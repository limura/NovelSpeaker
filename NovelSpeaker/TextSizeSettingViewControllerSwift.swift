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

        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySetting {
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
        }
        
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: NSLocalizedString("TextSizeSettingViewController_FontSettingTitle", comment: "字体設定"), style: .plain, target: self, action: #selector(fontSettingButtonClicked(_:))),
            UIBarButtonItem(title: NSLocalizedString("TextSizeSettinvViewController_ColorSettingTitle", comment: "色設定"), style: .plain, target: self, action: #selector(colorSettingButtonClicked(_:))),
        ]
        registNotificationCenter()
    }
    deinit {
        self.unregistNotificationCenter()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyColorSetting()
    }
    
    func applyColorSetting() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                if let state = RealmGlobalState.GetInstanceWith(realm: realm) {
                    self.sampleTextTextView.backgroundColor = state.backgroundColor
                    self.sampleTextTextView.textColor = state.foregroundColor
                }
            }
        }
    }
    
    func registNotificationCenter() {
        NovelSpeakerNotificationTool.addObserver(selfObject: ObjectIdentifier(self), name: Notification.Name.NovelSpeaker.RealmSettingChanged, queue: .main) { (notification) in
            DispatchQueue.main.async {
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    func unregistNotificationCenter() {
        NovelSpeakerNotificationTool.removeObserver(selfObject: ObjectIdentifier(self))
    }

    
    func setFontFromRealm() {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySetting {
                self.setFont(displaySetting: displaySetting)
            }
        }
    }
    
    func setFont(displaySetting:RealmDisplaySetting) {
        let textSizeValue = displaySetting.textSizeValue
        let font = displaySetting.font
        DispatchQueue.main.async {
            self.textSizeSlider.value = textSizeValue
            self.sampleTextTextView.font = font
        }
    }
    
    @objc func fontSettingButtonClicked(_ sender: UIBarButtonItem) {
        let nextViewController = FontSelectViewController()
        self.navigationController?.pushViewController(nextViewController, animated: true)
    }
    
    @objc func colorSettingButtonClicked(_ sender: UIBarButtonItem) {
        let nextViewController = NovelDisplayColorSettingViewController()
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
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySetting {
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.displaySettingObserbeToken]) { (realm) in
                    displaySetting.textSizeValue = self.textSizeSlider.value
                }
                self.setFont(displaySetting: displaySetting)
            }
        }
    }
    
}
