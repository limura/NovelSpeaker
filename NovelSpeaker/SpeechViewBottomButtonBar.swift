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
// 右上と違って横幅に余裕はあるものの、ボタンを全部 ON にすると入り切らなくなるので、
// 入り切らない分は画面右上のボタン群と同じように左端の「…」メニューへ追い出す。
class SpeechViewBottomButtonBar: UIView {
    private let stackView = UIStackView()
    // setButtons() で渡された全ボタン。入り切らない分は「…」に追い出すので、
    // 実際に stackView に並んでいるものとは別に元の並びを覚えておく。
    private var allButtons:[UIButton] = []
    // 今 stackView に並べているボタンの数(「…」を含む)。
    // 同じ数になる限り並べ直さない(layoutSubviews から呼ばれるのでループさせないため)。
    private var appliedVisibleButtonCount:Int = -1
    // ボタン1個の幅。createSpeechViewButtonArray(buttonSize: 28) と合わせてある。
    private let buttonWidth:CGFloat = 28

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
        self.allButtons = buttons
        self.appliedVisibleButtonCount = -1
        applyButtonsForCurrentWidth()
    }

    var buttonCount: Int {
        return allButtons.count
    }

    // 画面の幅に何個のボタンを並べられるかを求める。
    // 表示位置の制約(小説本文画面側)で safeArea から左右 8pt ずつ空けているので、その分を引く。
    private func maxVisibleButtonCount() -> Int {
        guard let superview = self.superview else { return allButtons.count }
        let safeAreaWidth = superview.safeAreaLayoutGuide.layoutFrame.width
        let usableWidth = safeAreaWidth - 8 * 2 - (stackView.layoutMargins.left + stackView.layoutMargins.right)
        // まだ実レイアウト前で測れない場合は全部並べておく(次の layoutSubviews で測り直される)
        if usableWidth <= 0 { return allButtons.count }
        let spacing = CGFloat(NovelSpeakerUtility.GetBarButtonItemSpacing())
        let unitWidth = buttonWidth + spacing
        return max(1, Int(floor((usableWidth + spacing) / unitWidth)))
    }

    // 今の画面幅に合わせてボタンを並べ直す。
    // 入り切らない場合は、右端のボタン(発話開始/停止が入る事が多い)を残しつつ前の方のボタンを
    // 「…」メニューに追い出す。「…」は画面右上のボタン群と同じく左端に置く。
    private func applyButtonsForCurrentWidth() {
        if allButtons.isEmpty { return }
        let visibleCount = min(allButtons.count, maxVisibleButtonCount())
        if visibleCount == appliedVisibleButtonCount { return }
        appliedVisibleButtonCount = visibleCount

        stackView.spacing = CGFloat(NovelSpeakerUtility.GetBarButtonItemSpacing())
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if allButtons.count <= visibleCount {
            for button in allButtons {
                stackView.addArrangedSubview(button)
            }
            return
        }
        let lastButton = allButtons[allButtons.count - 1]
        let others = Array(allButtons.dropLast())
        // 「…」と lastButton の分を引いた残りが、そのまま並べられる数
        let capacityForOthers = visibleCount - 2
        let keptOthers = capacityForOthers > 0 ? Array(others.suffix(capacityForOthers)) : []
        let overflowButtons = Array(others.prefix(others.count - keptOthers.count))
        stackView.addArrangedSubview(createMoreButton(overflowButtons: overflowButtons))
        for button in keptOthers + [lastButton] {
            stackView.addArrangedSubview(button)
        }
    }

    private func createMoreButton(overflowButtons:[UIButton]) -> UIButton {
        let actions = overflowButtons.map { button -> UIAction in
            let action = UIAction(title: button.accessibilityLabel ?? "",
                                  image: button.image(for: .normal)) { _ in
                button.sendActions(for: .touchUpInside)
            }
            // 発話中でないと押せないボタン(少し戻す/少し進める)は、メニュー側でも押せないようにしておく
            if button.isEnabled == false {
                action.attributes = .disabled
            }
            return action
        }
        let moreButton = UIButton(type: .system)
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.menu = UIMenu(children: actions)
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = NSLocalizedString("SpeechViewController_moreButton_AccessibilityLabel", comment: "隠れたメニュー項目を表示する")
        // 他のボタンと同じ幅にしておく(でないと「…」だけ intrinsic 幅になり幅の見積もりとズレる)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = moreButton.widthAnchor.constraint(equalToConstant: buttonWidth)
        widthConstraint.priority = UILayoutPriority(999)
        let heightConstraint = moreButton.heightAnchor.constraint(equalToConstant: buttonWidth)
        heightConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        return moreButton
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
        // 画面の幅が確定する(回転する)のはここなので、入り切らないボタンの追い出しはここで行う
        applyButtonsForCurrentWidth()
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
