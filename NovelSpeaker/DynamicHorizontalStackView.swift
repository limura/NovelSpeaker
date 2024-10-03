//
//  DynamicHorizontalStackView.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2024/10/03.
//  Copyright © 2024 IIMURA Takuji. All rights reserved.
//

import UIKit

class DynamicHorizontalStackView: UIView {
    private let stackView = UIStackView()
    private var heightConstraint: NSLayoutConstraint!
    
    // 識別名で管理する辞書
    private var labelMap = [String: UILabel]()
    private var buttonMap = [String: UIButton]()
    private var textFieldMap = [String: UITextField]()

    // MARK: - Initializer
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - View Setup
    private func setupView() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        stackView.isLayoutMarginsRelativeArrangement = true
        addSubview(stackView)
        
        // Constraint to fit stackView into the view
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        // Initially, set the height to 0 for hiding purposes
        heightConstraint = self.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
    }

    // MARK: - Add Elements with Identifier
    func addLabel(identifier: String, text: String, accessibilityLabel: String? = nil) {
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true // DynamicType対応
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.alpha = 0
        label.accessibilityLabel = accessibilityLabel

        stackView.addArrangedSubview(label)
        labelMap[identifier] = label
        //adjustHeight()
    }

    func addButton(identifier: String, title: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.adjustsFontForContentSizeCategory = true // DynamicType対応
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.alpha = 0
        button.accessibilityLabel = accessibilityLabel

        stackView.addArrangedSubview(button)
        buttonMap[identifier] = button
        //adjustHeight()
    }

    func addTextField(identifier: String, accessibilityLabel: String? = nil, placeholder: String) {
        let textField = UITextField()
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.adjustsFontForContentSizeCategory = true // DynamicType対応
        textField.setContentHuggingPriority(.required, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.alpha = 0
        textField.accessibilityLabel = accessibilityLabel

        stackView.addArrangedSubview(textField)
        textFieldMap[identifier] = textField
        //adjustHeight()
    }

    // MARK: - Control Methods (Post-Creation)
    func updateLabelText(identifier: String, text: String) {
        labelMap[identifier]?.text = text
    }

    func setButtonEnabled(identifier: String, isEnabled: Bool) {
        buttonMap[identifier]?.isEnabled = isEnabled
    }

    func setTextFieldEnabled(identifier: String, isEnabled: Bool) {
        textFieldMap[identifier]?.isEnabled = isEnabled
    }

    func getTextFieldText(identifier: String) -> String? {
        return textFieldMap[identifier]?.text
    }

    // MARK: - Show/Hide with Animation
    func showView() -> CGFloat {
        // Update height constraint to fit content
        let expectedHeight = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        heightConstraint.constant = expectedHeight

        // 子要素を表示
        stackView.arrangedSubviews.forEach { $0.alpha = 1 }
        
        return expectedHeight
    }

    func hideView() -> CGFloat {
        let expectedHeight = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        // Set height to 0 for hiding
        heightConstraint.constant = 0

        // 子要素を非表示
        stackView.arrangedSubviews.forEach { $0.alpha = 0 }
        
        return expectedHeight
    }

    // Adjust the height of the view based on content
    private func adjustHeight() {
        let expectedHeight = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        heightConstraint.constant = expectedHeight
        UIView.animate(withDuration: 0.3) {
            self.layoutIfNeeded()
        }
    }
}
