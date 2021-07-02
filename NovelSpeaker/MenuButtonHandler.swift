//
//  MenuButtonHandler.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2021/07/02.
//  Copyright © 2021 IIMURA Takuji. All rights reserved.
//

import Foundation

class MenuButtonHandler: NSObject {
    static let shared = MenuButtonHandler()
    
    // なお、Podcastアプリはこんな感じのショートカットキーだった。
    // 全体を「コントロール」っていうのに入れてる
    // 再生: スペース
    // 次へ: コマンド+→
    // 前へ: コマンド+←
    // 30秒スキップ: Shift+コマンド+→
    // 15秒戻し: Shift+コマンド+←
    // 音量を上げる: コマンド+↑
    // 音量を下げる: コマンド+↓
    @available(iOS 13.0, *)
    func BuildKeyboardShortcutMenu_Control(builder:UIMenuBuilder) {
        let startStopKey = UIKeyCommand(title:
            NSLocalizedString("MenuButtonHandler_StartStopShortcutKey_Title", comment: "再生/停止"), image: UIImage(systemName: "play.fill"),
            action: #selector(startStopKeyHandler),
            input: " ",
            modifierFlags: [.command])
        let skipForwardKey = UIKeyCommand(title:
            NSLocalizedString("MenuBarButtonHandler_SkipForwardShortcutKey_Title", comment: "少し前へ"),
           image: UIImage(systemName: "goforward.30"),
           action: #selector(skipForwardKeyHandler),
           input: UIKeyCommand.inputRightArrow,
           modifierFlags: [.command])
        let skipBackwardKey = UIKeyCommand(title:
            NSLocalizedString("MenuBarButtonHandler_SkipBackwardShortcutKey_Title", comment: "少し後ろへ"),
           image: UIImage(systemName: "gobackward.30"),
           action: #selector(skipBackwardKeyHandler),
           input: UIKeyCommand.inputLeftArrow,
           modifierFlags: [.command])
        let nextKey = UIKeyCommand(title:
            NSLocalizedString("MenuBarButtonHandler_NextShortcutKey_Title", comment: "次の章へ"),
           image: UIImage(systemName: "forward.frame.fill"),
           action: #selector(nextKeyHandler),
           input: UIKeyCommand.inputRightArrow,
           modifierFlags: [.command, .shift])
        let previousKey = UIKeyCommand(title:
            NSLocalizedString("MenuBarButtonHandler_PreviousShortcutKey_Title", comment: "前の章へ"),
           image: UIImage(systemName: "backward.frame.fill"),
           action: #selector(previousKeyHandler),
           input: UIKeyCommand.inputLeftArrow,
           modifierFlags: [.command, .shift])
        
        let controlMenu = UIMenu(title:
            NSLocalizedString("MenuBarButtonHandler_ControlMenu_Title", comment: "再生制御"),
            image: UIImage(systemName: "play"),
            identifier: .none,
            options: .destructive,
            children: [startStopKey, skipForwardKey, skipBackwardKey, nextKey, previousKey])
        
        builder.insertSibling(controlMenu, afterMenu: .application)
    }
    
    @objc func startStopKeyHandler() {
        DispatchQueue.main.async {
            StorySpeaker.shared.togglePlayPauseEvent()
        }
    }
    @objc func nextKeyHandler() {
        DispatchQueue.main.async {
            StorySpeaker.shared.nextTrackEvent()
        }
    }
    @objc func previousKeyHandler() {
        DispatchQueue.main.async {
            StorySpeaker.shared.previousTrackEvent()
        }
    }
    @objc func skipForwardKeyHandler() {
        DispatchQueue.main.async {
            StorySpeaker.shared.skipForwardEvent()
        }
    }
    @objc func skipBackwardKeyHandler() {
        DispatchQueue.main.async {
            StorySpeaker.shared.skipBackwardEvent()
        }
    }

    @available(iOS 13.0, *)
    @objc static func buildMenuHandler(builder:UIMenuBuilder) {
        print("buildMenuHandler in: \(builder.system)")
        switch builder.system {
        case .context:
            print("  context:")
            // 右クリックメニューを追加したい
        case .main:
            print("  main:")
            builder.remove(menu: .file)
            builder.remove(menu: .edit)
            builder.remove(menu: .format)
            builder.remove(menu: .help)
            MenuButtonHandler.shared.BuildKeyboardShortcutMenu_Control(builder: builder)
        default:
            print("  unknown.")
        }
    }
}
