//
//  NovelDisplayColorSettingViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/10/21.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class NovelDisplayColorSettingViewController: FormViewController, UIPopoverPresentationControllerDelegate, MSColorSelectionViewControllerDelegate, RealmObserverResetDelegate {
    var tmpColorSetting:UIColor = UIColor.white
    
    var globalStateColorNotificationToken:NotificationToken? = nil
    
    enum ColorPickerTarget {
        case foreground
        case background
    }
    var colorPickerTarget:ColorPickerTarget = .foreground

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        createForms()
        registNotificationToken()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    func StopObservers() {
        globalStateColorNotificationToken = nil
    }
    func RestartObservers() {
        StopObservers()
        registNotificationToken()
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */
    
    func registNotificationToken() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            self.globalStateColorNotificationToken = globalState.observe({ (change) in
                switch change {
                case .change(_, let propertys):
                    for property in propertys {
                        if property.name == "fgColor" || property.name == "bgColor" {
                            DispatchQueue.main.async {
                                self.form.removeAll()
                                self.createForms()
                            }
                            return
                        }
                    }
                default:
                    break
                }
            })
        }
    }
    
    func getForegroundColor() -> UIColor {
        return RealmUtil.RealmBlock { (realm) -> UIColor in
            if let state = RealmGlobalState.GetInstanceWith(realm: realm), let color = state.foregroundColor {
                return color
            }
            if #available(iOS 13.0, *) {
                return UIColor.label
            }
            return UIColor.black
        }
    }
    func getBackgroundColor() -> UIColor {
        return RealmUtil.RealmBlock { (realm) -> UIColor in
            if let state = RealmGlobalState.GetInstanceWith(realm: realm), let color = state.backgroundColor {
                return color
            }
            if #available(iOS 13.0, *) {
                return UIColor.systemBackground
            }
            return UIColor.white
        }
    }
    
    func setColor(foregroundColor:UIColor, backgroundColor:UIColor) {
        if let row = form.rowBy(tag: "SampleLabel") as? LabelRow {
            DispatchQueue.main.async {
                row.baseCell.backgroundColor = backgroundColor
                row.cell.textLabel?.backgroundColor = backgroundColor
                row.cell.textLabel?.textColor = foregroundColor
            }
        }
    }
    
    func refreshColorFromSetting() {
        setColor(foregroundColor: getForegroundColor(), backgroundColor: getBackgroundColor())
    }
    
    func saveColor(foregroundColor:UIColor?, backgroundColor:UIColor?) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let state = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalStateColorNotificationToken]) { (realm) in
                state.foregroundColor = foregroundColor
                state.backgroundColor = backgroundColor
            }
        }
    }
    
    func selectColor(target:ColorPickerTarget, row:ButtonRow) {
        self.colorPickerTarget = target
        let colorSelectionViewController = MSColorSelectionViewController()
        let navController = UINavigationController(rootViewController: colorSelectionViewController)
        navController.modalPresentationStyle = .popover
        navController.popoverPresentationController?.delegate = self
        navController.popoverPresentationController?.sourceView = row.cell.contentView
        navController.popoverPresentationController?.sourceRect = row.cell.contentView.bounds
        navController.preferredContentSize = colorSelectionViewController.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        colorSelectionViewController.delegate = self
        colorSelectionViewController.color = self.getForegroundColor()
        switch target {
        case .background:
            colorSelectionViewController.color = self.getBackgroundColor()
        case .foreground:
            colorSelectionViewController.color = self.getForegroundColor()
        }
        self.tmpColorSetting = colorSelectionViewController.color
        let cancelButtonItem = UIBarButtonItem(title: NSLocalizedString("Cancel_button", comment: "キャンセル"), style: .done, target: self, action: #selector(self.cancelAndDismissViewController(sendor:)))
        colorSelectionViewController.navigationItem.leftBarButtonItem = cancelButtonItem
        if self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClass.compact {
            let commitButtonItem = UIBarButtonItem(title: NSLocalizedString("NovelDisplayColorSettingViewController_ColorPickerDoneTitle", comment: "この色で設定"), style: .done, target: self, action: #selector(self.dismissViewController(sendor:)))
            colorSelectionViewController.navigationItem.rightBarButtonItem = commitButtonItem
        }
        self.present(navController, animated: true, completion: nil)
    }

    func createForms() {
        form +++ Section()
        <<< LabelRow("SampleLabel") { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_SampleText", comment: "メロスは激怒した。必ず、かの邪智暴虐の王を除かなければならぬと決意した。メロスには政治がわからぬ。メロスは、村の牧人である。笛を吹き、羊と遊んで暮して来た。けれども邪悪に対しては、人一倍に敏感であった。\nきょう未明メロスは村を出発し、野を越え山越え、十里はなれた此のシラクスの市にやって来た。メロスには父も、母も無い。女房も無い。十六の、内気な妹と二人暮しだ。")
            row.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
            row.cell.textLabel?.numberOfLines = 0
            refreshColorFromSetting()
        }.cellUpdate({ (cellOf, row) in
            let backgroundColor = self.getBackgroundColor()
            row.baseCell.backgroundColor = backgroundColor
            row.cell.textLabel?.backgroundColor = backgroundColor
            row.cell.textLabel?.textColor = self.getForegroundColor()
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_Default", comment: "標準(ダークモード等に追従します)")
        }.onCellSelection({ (cellOf, row) in
            self.saveColor(foregroundColor: nil, backgroundColor: nil)
            self.refreshColorFromSetting()
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_White", comment: "白地に黒で固定")
        }.onCellSelection({ (cellOf, row) in
            self.saveColor(foregroundColor: UIColor.black, backgroundColor: UIColor.white)
            self.refreshColorFromSetting()
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_Cream", comment: "クリーム色地に黒で固定")
        }.onCellSelection({ (cellOf, row) in
            self.saveColor(foregroundColor: UIColor.black, backgroundColor: UIColor.init(red: 1.0, green: 1.0, blue: 0.878, alpha: 1.0))
            self.refreshColorFromSetting()
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_Gray", comment: "灰色地に白で固定")
        }.onCellSelection({ (cellOf, row) in
            self.saveColor(foregroundColor: UIColor.white, backgroundColor: UIColor.init(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0))
            self.refreshColorFromSetting()
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_Black", comment: "黒地に白で固定")
        }.onCellSelection({ (cellOf, row) in
            self.saveColor(foregroundColor: UIColor.white, backgroundColor: UIColor.black)
            self.refreshColorFromSetting()
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_UserDefined_Foreground", comment: "字の色を直接指定")
        }.onCellSelection({ (cellOf, row) in
            self.selectColor(target: .foreground, row: row)
        })
        <<< ButtonRow() { (row) in
            row.title = NSLocalizedString("NovelDisplayColorSettingViewController_ColorSettingButton_UserDefined_Background", comment: "背景色を直接指定")
        }.onCellSelection({ (cellOf, row) in
            self.selectColor(target: .background, row: row)
        })
    }
    
    func setColorPickerColor(color:UIColor) {
        switch self.colorPickerTarget {
        case .foreground:
            self.saveColor(foregroundColor: color, backgroundColor: getBackgroundColor())
            self.refreshColorFromSetting()
        case .background:
            self.saveColor(foregroundColor: getForegroundColor(), backgroundColor: color)
            self.refreshColorFromSetting()
        }
    }
    
    @objc func colorViewController(_ colorViewCntroller: MSColorSelectionViewController, didChange color: UIColor) {
        setColorPickerColor(color: color)
    }
    
    @objc func prepareForPopoverPresentation(_ popoverPresentationController: UIPopoverPresentationController) {
    }
    
    @objc func dismissViewController(sendor:UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func cancelAndDismissViewController(sendor:UIButton) {
        setColorPickerColor(color: self.tmpColorSetting)
        self.dismiss(animated: true, completion: nil)
    }
}
