//
//  PickerViewDialog.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/12/01.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation

class PickerViewDialog : UIView, UITextFieldDelegate, UIPickerViewDelegate, UIPickerViewDataSource {
    @IBOutlet weak var pickerView: UIPickerView!
    @IBOutlet weak var upperDoneButton: UIButton!
    @IBOutlet weak var lowerDoneButton: UIButton!
    @IBOutlet weak var okButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!
    
    var displayTextArray:[String] = []
    var resultReceiver:((String)->Void)? = nil
    var centerYAnchorConstraint:NSLayoutConstraint? = nil
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        pickerView.delegate = self
        pickerView.dataSource = self
    }
    
    static func createNewDialog(displayTextArray:[String], firstSelectedString:String?, resultReceiver:((String)->Void)?) -> PickerViewDialog? {
        guard let toplevelViewController = NiftyUtility.GetRegisterdToplevelViewController() else { return nil }

        let nib = UINib.init(nibName: "PickerViewDialog", bundle: nil)
        guard let dialog = nib.instantiate(withOwner: self, options: nil).first as? PickerViewDialog else { return nil }

        dialog.displayTextArray = displayTextArray
        if let firstSelectedString = firstSelectedString, let index = displayTextArray.firstIndex(of: firstSelectedString) {
            dialog.pickerView.selectRow(index, inComponent: 0, animated: false)
        }else{
            let middle = displayTextArray.count / 2
            dialog.pickerView.selectRow(middle, inComponent: 0, animated: false)
        }
        dialog.resultReceiver = resultReceiver
        dialog.accessibilityViewIsModal = true
        if let toplevelView = toplevelViewController.view {
            toplevelView.addSubview(dialog)
            // TODO: 何故か constraint で制御しようとするとmacで動かした時にちゃんと動かない(´・ω・`)
            dialog.bounds = toplevelView.bounds
            dialog.frame = toplevelView.frame
            /*
            let yAnchorConstraint = dialog.centerYAnchor.constraint(equalTo: toplevelView.centerYAnchor)
            NSLayoutConstraint.activate([
                dialog.widthAnchor.constraint(equalTo: toplevelView.widthAnchor),
                dialog.heightAnchor.constraint(equalTo: toplevelView.heightAnchor),
                dialog.topAnchor.constraint(equalTo: toplevelView.topAnchor),
                dialog.leftAnchor.constraint(equalTo: toplevelView.leftAnchor),
                dialog.rightAnchor.constraint(equalTo: toplevelView.rightAnchor),
                dialog.bottomAnchor.constraint(equalTo: toplevelView.bottomAnchor),
//                dialog.centerXAnchor.constraint(equalTo: toplevelView.centerXAnchor),
//                yAnchorConstraint,
            ])
//            dialog.setYAnchorConstraint(constraint: yAnchorConstraint)
 */
        }
        UIAccessibility.post(notification: .screenChanged, argument: dialog)
        return dialog
    }
    
    func setYAnchorConstraint(constraint:NSLayoutConstraint) {
        if let prevConstraint = self.centerYAnchorConstraint {
            NSLayoutConstraint.deactivate([prevConstraint])
        }
        NSLayoutConstraint.activate([constraint])
        self.centerYAnchorConstraint = constraint
    }
    
    func popup(completion:(()->Void)?) {
        // TODO: 何故か constraint で制御しようとするとmacで動かした時にちゃんと動かない(´・ω・`)
        completion?()
        return

        guard let toplevelView = NiftyUtility.GetRegisterdToplevelViewController()?.view else { return }
        let height = UIScreen.main.bounds.height
        setYAnchorConstraint(constraint: self.centerYAnchor.constraint(equalTo: toplevelView.centerYAnchor, constant: height))
        UIView.animate(withDuration: 0.2) {
            self.setYAnchorConstraint(constraint: self.centerYAnchor.constraint(equalTo: toplevelView.centerYAnchor, constant: 0))
        } completion: { (result) in
            completion?()
        }
    }
    
    func popdown(completion:(()->Void)?) {
        // TODO: 何故か constraint で制御しようとするとmacで動かした時にちゃんと動かない(´・ω・`)
        completion?()
        return
        
        guard let toplevelView = NiftyUtility.GetRegisterdToplevelViewController()?.view else { return }
        let height = UIScreen.main.bounds.height
        setYAnchorConstraint(constraint: self.centerYAnchor.constraint(equalTo: toplevelView.centerYAnchor, constant: 0))
        UIView.animate(withDuration: 0.2) {
            self.setYAnchorConstraint(constraint: self.centerYAnchor.constraint(equalTo: toplevelView.centerYAnchor, constant: height))
        } completion: { (result) in
            completion?()
        }
    }

    func rowNumberToString(row:Int) -> String {
        guard row >= 0 && row < displayTextArray.count else { return "-" }
        return displayTextArray[row]
    }
    
    func getSelectedString() -> String {
        let selectedRow = self.pickerView.selectedRow(inComponent: 0)
        return rowNumberToString(row: selectedRow)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return displayTextArray.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return rowNumberToString(row: row)
    }
    
    // UIPickerView に表示される要素を返す(DynamicType 用に font を設定します)
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label:UILabel
        if let reuseLabel = view as? UILabel {
            label = reuseLabel
        }else{
            label = UILabel()
            label.font = UIFont.preferredFont(forTextStyle: .title1)
            label.textAlignment = .center
        }
        label.text = self.pickerView(pickerView, titleForRow: row, forComponent: component)
        return label
    }
    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
        let font = UIFont.preferredFont(forTextStyle: .title1)
        return font.lineHeight
    }
    
    @IBAction func doneButtonClicked(_ sender: Any) {
        popdown {
            self.removeFromSuperview()
        }
    }
    @IBAction func okButtonClicked(_ sender: Any) {
        let selectedString = getSelectedString()
        popdown {
            self.removeFromSuperview()
            self.resultReceiver?(selectedString)
        }
    }
    @IBAction func cancelButtonClicked(_ sender: Any) {
        popdown {
            self.removeFromSuperview()
        }
    }
}
