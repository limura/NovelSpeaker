//
//  TimeIntervalCountDownRow.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2017/11/11.
//  Copyright © 2017年 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

open class TimeIntervalCell: Cell<TimeInterval>, CellType {
    
    public var datePicker: UIDatePicker
    
    public required init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        datePicker = UIDatePicker()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        datePicker = UIDatePicker()
        super.init(coder: aDecoder)
    }
    
    open override func setup() {
        super.setup()
        accessoryType = .none
        editingAccessoryType =  .none
        datePicker.datePickerMode = .countDownTimer
        datePicker.addTarget(self, action: #selector(TimeIntervalCell.datePickerValueChanged(_:)), for: .valueChanged)
    }
    
    deinit {
        datePicker.removeTarget(self, action: nil, for: .allEvents)
    }
    
    open override func update() {
        super.update()
        selectionStyle = row.isDisabled ? .none : .default
        datePicker.countDownDuration = row.value ?? 0
        if let minuteIntervalValue = (row as? DatePickerRowProtocol)?.minuteInterval {
            datePicker.minuteInterval = minuteIntervalValue
        }
        if row.isHighlighted {
            textLabel?.textColor = tintColor
        }
    }
    
    open override func didSelect() {
        super.didSelect()
        row.deselect()
    }
    
    override open var inputView: UIView? {
        if let v = row.value {
            datePicker.countDownDuration = v
        }
        return datePicker
    }
    
    @objc func datePickerValueChanged(_ sender: UIDatePicker) {
        row.value = sender.countDownDuration
        detailTextLabel?.text = row.displayValueFor?(row.value)
    }
    
    open override func cellCanBecomeFirstResponder() -> Bool {
        return canBecomeFirstResponder
    }
    
    override open var canBecomeFirstResponder: Bool {
        return !row.isDisabled
    }
}
public protocol TimeIntervalPickerRowProtocol: class {
    var minuteInterval: Int? { get set }
}

open class _TimeIntervalFieldRow: Row<TimeIntervalCell>, TimeIntervalPickerRowProtocol, NoValueDisplayTextConformance {
    
    /// The interval between options for this row's UIDatePicker
    open var minuteInterval: Int?
    
    open var noValueDisplayText: String? = nil
    
    required public init(tag: String?) {
        super.init(tag: tag)
        displayValueFor = { value in
            guard let timeInterval = value else {
                return nil
            }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            return formatter.string(from: timeInterval)
        }
    }
}
class _TimeIntervalCountDownRow: _TimeIntervalFieldRow {
    required public init(tag: String?) {
        super.init(tag: tag)
        displayValueFor = { value in
            guard let timeInterval = value else {
                return nil
            }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second]
            return formatter.string(from: timeInterval)
        }
    }
}

final class TimeIntervalCountDownRow: _TimeIntervalCountDownRow, RowType {
    required public init(tag: String?) {
        super.init(tag: tag)
    }
}
