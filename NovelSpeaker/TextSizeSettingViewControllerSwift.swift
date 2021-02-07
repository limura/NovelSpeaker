//
//  TextSizeSettingViewControllerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/05/16.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

class TextSizeSettingViewControllerSwift: UIViewController, RealmObserverResetDelegate {
    @IBOutlet weak var textSizeSlider: UISlider!
    @IBOutlet weak var sampleTextTextView: UITextView!
    @IBOutlet weak var lineSpacingSlider: UISlider!
    @IBOutlet weak var fontSizeLabel: UILabel!
    @IBOutlet weak var lineSpacingLabel: UILabel!
    
    var displaySettingObserbeToken:NotificationToken? = nil
    var textAttribute:[NSAttributedString.Key: Any] = [:]
    
    let sampleText = """
メロスは両手で老爺のからだをゆすぶって質問を重ねた。老爺は、あたりをはばかる低声で、わずか答えた。
「王様は、人を殺します。」
「なぜ殺すのだ。」
「悪心を抱いている、というのですが、誰もそんな、悪心を持っては居りませぬ。」
「たくさんの人を殺したのか。」
「はい、はじめは王様の妹婿さまを。それから、御自身のお世嗣を。それから、妹さまを。それから、妹さまの御子さまを。それから、皇后さまを。それから、賢臣のアレキス様を。」
「おどろいた。国王は乱心か。」
「いいえ、乱心ではございませぬ。人を、信ずる事が出来ぬ、というのです。このごろは、臣下の心をも、お疑いになり、少しく派手な暮しをしている者には、人質ひとりずつ差し出すことを命じて居ります。御命令を拒めば十字架にかけられて、殺されます。きょうは、六人殺されました。」
　聞いて、メロスは激怒した。「呆れた王だ。生かして置けぬ。」
　メロスは、単純な男であった。買い物を、背負ったままで、のそのそ王城にはいって行った。たちまち彼は、巡邏の警吏に捕縛された。調べられて、メロスの懐中からは短剣が出て来たので、騒ぎが大きくなってしまった。メロスは、王の前に引き出された。
「この短刀で何をするつもりであったか。言え！」暴君ディオニスは静かに、けれども威厳を以て問いつめた。その王の顔は蒼白で、眉間の皺しわは、刻み込まれたように深かった。

太宰治 走れメロスより
"""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        addObservers()

        fontSizeLabel.text = NSLocalizedString("TextSizeSettingViewController_FontSizeLabel_Text", comment: "文字の大きさ")
        fontSizeLabel.sizeToFit()
        lineSpacingLabel.text = NSLocalizedString("TextSizeSettingViewController_LineSpacingLabel_Text", comment: "行間")
        fontSizeLabel.sizeToFit()

        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: NSLocalizedString("TextSizeSettingViewController_FontSettingTitle", comment: "字体設定"), style: .plain, target: self, action: #selector(fontSettingButtonClicked(_:))),
            UIBarButtonItem(title: NSLocalizedString("TextSizeSettinvViewController_ColorSettingTitle", comment: "色設定"), style: .plain, target: self, action: #selector(colorSettingButtonClicked(_:))),
        ]
        registNotificationCenter()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    func StopObservers() {
        displaySettingObserbeToken = nil
    }
    func RestartObservers() {
        StopObservers()
        addObservers()
    }
    
    func addObservers() {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) {
                setFont(displaySetting: displaySetting)
                displaySettingObserbeToken = displaySetting.observe { (change) in
                    switch change {
                    case .change(_, _):
                        self.setFontFromRealm()
                    case .error(_):
                        break
                    case .deleted:
                        self.navigationController?.popViewController(animated: true)
                    }
                }
            }
        }
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

    func updateTextAttribute(font:UIFont?, lineSpacing:CGFloat) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing // 行間
        var attributes:[NSAttributedString.Key:Any] = [
            .paragraphStyle: style
        ]
        if let font = font {
            attributes[.font] = font
        }
        textAttribute = attributes
    }
    
    func applyText(text:String) {
        self.sampleTextTextView.attributedText = NSAttributedString(string: text, attributes: self.textAttribute)
        RealmUtil.RealmBlock { (realm) -> Void in
            if let state = RealmGlobalState.GetInstanceWith(realm: realm) {
                self.sampleTextTextView.backgroundColor = state.backgroundColor
                self.sampleTextTextView.textColor = state.foregroundColor
            }
        }
    }

    func setFontFromRealm() {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) {
                self.setFont(displaySetting: displaySetting)
            }
        }
    }
    
    func setFont(displaySetting:RealmDisplaySetting) {
        updateTextAttribute(font: displaySetting.font, lineSpacing: displaySetting.lineSpacingDisplayValue)
        DispatchQueue.main.async {
            self.applyText(text: self.sampleText)
            self.textSizeSlider.value = displaySetting.textSizeValue
            self.lineSpacingSlider.value = displaySetting.lineSpacing
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
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) {
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.displaySettingObserbeToken]) { (realm) in
                    displaySetting.textSizeValue = self.textSizeSlider.value
                    realm.add(displaySetting, update: .modified)
                }
                self.setFont(displaySetting: displaySetting)
            }
        }
    }
    
    @IBAction func lineSpacingSliderChanged(_ sender: Any) {
        RealmUtil.RealmBlock { (realm) -> Void in
            if let displaySetting = RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm) {
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.displaySettingObserbeToken]) { (realm) in
                    displaySetting.lineSpacing = self.lineSpacingSlider.value
                    realm.add(displaySetting, update: .modified)
                }
                self.setFont(displaySetting: displaySetting)
            }
        }
    }
}
