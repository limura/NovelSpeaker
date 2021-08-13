//
//  MultipleNovelIDSelectorViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/01.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//
// 小説を複数選択するインタフェースを作る時に使います。
// 選択結果は delegate で渡されます。

import UIKit
import Eureka
import RealmSwift

protocol MultipleNovelIDSelectorDelegate : AnyObject {
    func MultipleNovelIDSelectorSelected(selectedNovelIDSet:Set<String>, hint:String)
}

class MultipleNovelIDSelectorViewController: FormViewController, RealmObserverResetDelegate {
    public var SelectedNovelIDSet:Set<String> = Set<String>()
    public var IsUseAnyNovelID = true
    public var Hint = ""
    public var IsNeedDisplayFolderName = false
    public var UnDisplayFolderID:String? = nil
    public var OverrideTitle:String? = nil
    public weak var delegate:MultipleNovelIDSelectorDelegate?
    
    static let AnyTypeTag = RealmSpeechModSetting.anyTarget
    
    var novelArrayNotificationToken:NotificationToken? = nil
    var filterString = ""
    var filterButton:UIBarButtonItem = UIBarButtonItem()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.OverrideTitle ?? NSLocalizedString("MultipleNovelIDSelectorViewController_Title", comment: "小説を選択")
        
        createSelectorCells()
        self.filterButton = UIBarButtonItem.init(title: NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索"), style: .done, target: self, action: #selector(filterButtonClicked(sender:)))
        navigationItem.rightBarButtonItems = [filterButton]
        registNotificationCenter()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
    }

    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
        self.unregistNotificationCenter()
    }
    
    func StopObservers() {
        novelArrayNotificationToken = nil
    }
    func RestartObservers() {
        StopObservers()
        observeNovelArray()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let delegate = self.delegate else { return }
        delegate.MultipleNovelIDSelectorSelected(selectedNovelIDSet: self.SelectedNovelIDSet, hint: self.Hint)
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

    func observeNovelArray() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
            self.novelArrayNotificationToken = allNovels.observe({ (change) in
                switch change {
                case .initial(_):
                    break
                case .update(_, let deletions, let insertions, let modifications):
                    if deletions.count > 0 || insertions.count > 0 || modifications.count > 0 {
                        DispatchQueue.main.async {
                            self.form.removeAll()
                            self.createSelectorCells()
                        }
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    func createSelectorCells() {
        let section = Section()
        RealmUtil.RealmBlock { (realm) -> Void in
            guard var allNovels = RealmNovel.GetAllObjectsWith(realm: realm) else { return }
            if IsUseAnyNovelID {
                section <<< CheckRow(MultipleNovelIDSelectorViewController.AnyTypeTag) {
                    $0.title = NSLocalizedString("CreateSpeechModSettingViewControllerSwift_AnyTargetName", comment: "全ての小説")
                    $0.value = self.SelectedNovelIDSet.contains(MultipleNovelIDSelectorViewController.AnyTypeTag)
                }.onChange({ (row) in
                    guard let value = row.value else { return }
                    if value {
                        self.SelectedNovelIDSet.insert(MultipleNovelIDSelectorViewController.AnyTypeTag)
                    }else{
                        self.SelectedNovelIDSet.remove(MultipleNovelIDSelectorViewController.AnyTypeTag)
                    }
                })
            }
            if self.filterString.count > 0 {
                allNovels = allNovels.filter("title CONTAINS %@ OR writer CONTAINS %@", self.filterString, self.filterString)
            }
            var novelIDToFolderNameTable:[String:[String]] = [:]
            if self.IsNeedDisplayFolderName, let folderArray = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) {
                for folder in folderArray {
                    if let unDisplayFolderID = self.UnDisplayFolderID, unDisplayFolderID == folder.id {
                        continue
                    }
                    for novelID in folder.targetNovelIDArray {
                        if var folderNameList = novelIDToFolderNameTable[novelID] {
                            folderNameList.append(folder.name)
                            novelIDToFolderNameTable[novelID] = folderNameList
                        }else{
                            novelIDToFolderNameTable[novelID] = [folder.name]
                        }
                    }
                }
            }
            for novel in allNovels {
                let novelID = novel.novelID
                section <<< CheckRow(novelID) {
                    $0.title = novel.title
                    $0.value = self.SelectedNovelIDSet.contains(novelID)
                }.onChange({ (row) in
                    guard let value = row.value else { return }
                    if value {
                        self.SelectedNovelIDSet.insert(novelID)
                    }else{
                        self.SelectedNovelIDSet.remove(novelID)
                    }
                }).cellUpdate({ cell, row in
                    guard let folderNameArray = novelIDToFolderNameTable[novelID] else { return }
                    row.cellStyle = .subtitle
                    cell.detailTextLabel?.text = folderNameArray.joined(separator: ", ")
                })
            }
        }
        form +++ section
    }

    @objc func filterButtonClicked(sender: UIBarButtonItem) {
        NiftyUtility.EasyDialogTextInput(
            viewController: self,
            title: NSLocalizedString("SpeechModSettingsTableView_SearchTitle", comment: "検索"),
            message: nil,
            textFieldText: self.filterString,
            placeHolder: NSLocalizedString("BookShelfTableViewController_SearchMessage", comment: "小説名 と 作者名 が対象となります"), action: { (text) in
            self.filterString = text
            DispatchQueue.main.async {
                self.form.removeAll(keepingCapacity: true)
                self.createSelectorCells()
                if self.filterString.count <= 0 {
                    self.filterButton.title = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索")
                }else{
                    self.filterButton.title = NSLocalizedString("BookShelfTableViewController_SearchTitle", comment: "検索") + "(\(self.filterString))"
                }
            }
        })
    }
}
