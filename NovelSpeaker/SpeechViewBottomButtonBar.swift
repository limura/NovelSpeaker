//
//  SpeechViewBottomButtonBar.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2026/08/18.
//  Copyright © 2026 IIMURA Takuji. All rights reserved.
//

import UIKit

// 小説本文画面の下部に重ねて表示するボタン群。
//
// 画面右上のボタン群は「片手で持っていると押しにくい」ため、同じボタンを画面下部にも
// 置けるようにするためのもの(設定は右上とは独立していて、既定では何も表示しない)。
//
// 右上と違って横幅に余裕があるので、「…」への追い出し(trimUpperButtonsToFitIfNeeded)は
// 行わず、等間隔に並べるだけにしている。
class SpeechViewBottomButtonBar: UIView {
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // 縁取りと影の色を作るために applyThemeColor() で渡された本文の文字色を覚えておく。
    private var themeForegroundColor:UIColor = UIColor.label

    private func setupView() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.layer.cornerRadius = 8
        // 影を落とすので clipsToBounds は false にする。
        // 背景色は layer に cornerRadius を付けた状態で描かれるので、角丸自体はこれで問題ない。
        self.clipsToBounds = false
        // applyThemeColor() が呼ばれるまでの間も本文が透けないようにしておく。
        self.backgroundColor = UIColor.systemBackground
        // 本文の背景色とボタン群の背景色が同じだと境界がわからなくなるため、
        // 薄い縁取りと影を付けて浮いているように見せる。色は applyThemeColor() で本文の文字色から作る。
        self.layer.borderWidth = 1.0
        self.layer.shadowRadius = 4
        self.layer.shadowOffset = CGSize(width: 0, height: 2)
        self.layer.shadowOpacity = 0.25
        updateBorderAndShadowColor()

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        // 間隔は画面右上のボタン群と同じ設定値を使う(バラバラだとチグハグに見えるため)
        stackView.spacing = CGFloat(NovelSpeakerUtility.GetBarButtonItemSpacing())
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }

    func setButtons(_ buttons:[UIButton]) {
        stackView.spacing = CGFloat(NovelSpeakerUtility.GetBarButtonItemSpacing())
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for button in buttons {
            stackView.addArrangedSubview(button)
        }
    }

    var buttonCount: Int {
        return stackView.arrangedSubviews.count
    }

    func applyThemeColor(backgroundColor:UIColor, foregroundColor:UIColor) {
        // 本文の上に重なるので、下の文字が透けて読みにくくならないように不透明にする。
        self.backgroundColor = backgroundColor
        self.themeForegroundColor = foregroundColor
        updateBorderAndShadowColor()
        // ボタンの色は指定しない。画面右上のボタン群と同じく、
        // アプリ既定の tintColor(青)をそのまま使わせる。
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 影の形を角丸に合わせる(描画も軽くなる)
        self.layer.shadowPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.layer.cornerRadius).cgPath
        // ダークモード/ライトモードの切り替えでは CGColor は自動では変わらないので、
        // レイアウトのタイミングで作り直しておく。
        updateBorderAndShadowColor()
    }

    // 縁取りと影の色を本文の文字色から作る。
    // 背景が明るい時は文字色が暗いので普通の影に、背景が暗い時は文字色が明るいので
    // 薄く光っているように見えて、どちらでも境界がわかるようになる。
    private func updateBorderAndShadowColor() {
        let foregroundColor = self.themeForegroundColor.resolvedColor(with: self.traitCollection)
        self.layer.borderColor = foregroundColor.withAlphaComponent(0.3).cgColor
        self.layer.shadowColor = foregroundColor.cgColor
    }
}
