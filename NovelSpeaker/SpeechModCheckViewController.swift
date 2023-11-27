//
//  SpeechModCheckViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2023/09/03.
//  Copyright © 2023 IIMURA Takuji. All rights reserved.
//
/*
 * 指定された StoryID を読み込んで、現在の設定で読み替えを適用した状態ではどうなるかを見える形で表示して、
 * できることならその変換を行った設定を発見するためのやつ。
 *
 * ただ、変換時には正規表現は展開されたものがSpeechModとして(仮に)登録された状態になっているため、
 * 変換対象になった部分の変換前の文字列(つまり表示される文字列)と、変換後の文字列しかわからない。
 *
 * また、UITextView でクリッカブル？にする方法がよくわからんかったので
 * AttributedText の .link に "speechmod://変換前の文字列" というURLを渡して、
 * そのタップイベントをDelegateで受け取って、変換前の文字列について取り出す、という怪しい事をしている。
 */

import Foundation

class SpeechModCheckViewController : UIViewController, UITextViewDelegate {
    var targetStoryID:String? = nil
    let textView = UITextView()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        textView.frame = view.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isSelectable = true
        textView.isEditable = false
        textView.delegate = self
        view.addSubview(textView)
        
        UpdateText()
    }
    
    func UpdateText() {
        guard let storyID = self.targetStoryID else { return }
        DispatchQueue.main.async {
            let story = RealmUtil.RealmBlock { (realm) -> Story? in
                return RealmStoryBulk.SearchStoryWith(realm: realm, storyID: storyID)
            }
            guard let story = story else { return }
            let font = RealmUtil.RealmBlock { (realm) -> UIFont? in
                return RealmGlobalState.GetInstanceWith(realm: realm)?.defaultDisplaySettingWith(realm: realm)?.font
            }
            guard let font = font else { return }
            let blockArray = StoryTextClassifier.CategorizeStoryText(story: story, withMoreSplitTargets: [], moreSplitMinimumLetterCount: 999999)
            let attributedText = NSMutableAttributedString()
            for block in blockArray {
                for b2 in block.speechBlockArray {
                    let speechText = b2.speechText ?? b2.displayText
                    if b2.isMod {
                        let str = NSMutableAttributedString(string: speechText)
                        str.addAttributes([
                            //.attachment: block.displayText,
                            .link: "speechmod://\(b2.displayText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
                            .foregroundColor: UIColor.darkText,
                            .backgroundColor: UIColor.systemGray3,
                            //.underlineColor: UIColor.blue,
                            .font: font,
                        ], range: NSRange(location: 0, length: speechText.count))
                        attributedText.append(str)
                    }else{
                        let str = NSMutableAttributedString(string: speechText)
                        str.addAttributes([
                            .font: font,
                        ], range: NSRange(location: 0, length: speechText.count))
                        attributedText.append(str)
                    }
                }
            }
            self.textView.attributedText = attributedText
        }
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        //print("shouldInteractWith: URL: \(URL.absoluteString.removingPercentEncoding ?? URL.absoluteString), substring: \(textView.attributedText.attributedSubstring(from: characterRange).string)")
        let url = (URL.absoluteString.removingPercentEncoding ?? URL.absoluteString)
        let before = url.NiftySubstring(from: "speechmod://".count, to: url.count)
        print("shouldInteractWith: before: \(before)")
        return false
    }
    
    func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        print("shouldInteractWith: textAttachment: \(textAttachment.description)")
        return false
    }
}
