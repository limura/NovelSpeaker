//
//  NovelKeywordTagSelecterViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/25.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class NovelKeywordTagSelecterViewController: FormViewController {
    var novelID:String = ""
    var novelTagNotificationToken:NotificationToken? = nil
    var searchKey:String = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("NovelKeywordTagSelectorViewController_Title", comment: "タグを選択")
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonClicked(_:)))
        let searchButton = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(searchButtonClicked(_:)))
        self.navigationItem.rightBarButtonItems = [addButton, searchButton]
        
        self.createCells()
        self.observeRealmNovelTag()
    }
    
    func createCells() {
        var tagNameToSelected:[String:Bool] = [:]
        RealmUtil.RealmBlock { (realm) -> Void in
            if self.searchKey.count > 0 {
                guard let tagArray = RealmNovelTag.GetAllObjectsWith(realm: realm)?.filter("type = %@ AND name CONTAINS %@", RealmNovelTag.TagType.Keyword, self.searchKey) else { return }
                for tag in tagArray {
                    tagNameToSelected[tag.name] = tag.targetNovelIDArray.contains(self.novelID)
                }
            }else{
                guard let tagArray = RealmNovelTag.GetAllObjectsWith(realm: realm)?.filter("type = %@", RealmNovelTag.TagType.Keyword) else { return }
                for tag in tagArray {
                    tagNameToSelected[tag.name] = tag.targetNovelIDArray.contains(self.novelID)
                }
            }
        }

        let section = Section()
        for name in tagNameToSelected.keys.sorted() {
            section <<< CheckRow("CheckRow-\(name)") {
                $0.title = name
                if let isSelected = tagNameToSelected[name], isSelected == true {
                    $0.value = true
                }else{
                    $0.value = false
                }
                $0.trailingSwipe.actions = [
                    SwipeAction(style: .destructive, title: NSLocalizedString("AssignNovelFolderViewController_DeleteSwipeActionTitle", comment: "削除"), handler: { (action, row, completionHandler) in
                        RealmUtil.RealmBlock { (realm) -> Void in
                            guard let tag = RealmNovelTag.SearchWith(realm: realm, name: name, type: RealmNovelTag.TagType.Keyword) else {
                                completionHandler?(true)
                                return
                            }
                            RealmUtil.WriteWith(realm: realm) { (realm) in
                                tag.delete(realm: realm)
                            }
                        }
                        completionHandler?(true)
                    })
                ]
            }.onChange({ (row) in
                guard let isSelected = row.value else { return }
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let tag = RealmNovelTag.SearchWith(realm: realm, name: name, type: RealmNovelTag.TagType.Keyword) else { return }
                    RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.novelTagNotificationToken], block: { (realm) in
                        if isSelected {
                            RealmNovelTag.AddTag(realm: realm, name: name, novelID: self.novelID, type: RealmNovelTag.TagType.Keyword)
                        }else{
                            tag.unref(realm: realm, novelID: self.novelID)
                        }
                    })
                }
            })
        }
        form +++ section
    }
    
    func observeRealmNovelTag() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let target = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Keyword) else { return }
            self.novelTagNotificationToken = target.observe({ (changes) in
                switch changes {
                case .initial(_):
                    break
                case .update(_, let deletions, let insertions, let modifications):
                    if deletions.count > 0 || insertions.count > 0 || modifications.count > 0 {
                        DispatchQueue.main.async {
                            self.form.removeAll()
                            self.createCells()
                        }
                    }
                case .error(_):
                    break
                }
            })
        }
    }
    
    @objc func addButtonClicked(_ sender: UIBarButtonItem) {
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogTextInput(
                viewController: self,
                title: NSLocalizedString("NovelKeywordTagSelectorViewController_AddTagTitle", comment: "タグの追加"),
                message: nil,
                textFieldText: "",
                placeHolder: NSLocalizedString("NovelKeywordTagSelectorViewController_AddTagTitlePlaceHolder", comment: "空文字列は指定できません"),
                action: { (name) in
                    if name.count <= 0 {
                        DispatchQueue.main.async {
                            NiftyUtilitySwift.EasyDialogOneButton(
                                viewController: self,
                                title: nil,
                                message: NSLocalizedString("NovelKeywordTagSelectorViewController_AddTagTitlePlaceHolder", comment: "空文字列は指定できません"),
                                buttonTitle: nil,
                                buttonAction: nil)
                        }
                        return
                    }
                    RealmUtil.Write(block: { (realm) in
                        RealmNovelTag.AddTag(realm: realm, name: name, novelID: self.novelID, type: RealmNovelTag.TagType.Keyword)
                    })
                }
            )
        }
    }
    
    @objc func searchButtonClicked(_ sender: UIBarButtonItem) {
        DispatchQueue.main.async {
            NiftyUtilitySwift.EasyDialogTextInput(
                viewController: self,
                title: NSLocalizedString("NovelKeywordTagSelectorViewController_SearchButtonTitle", comment: "検索"),
                message: nil,
                textFieldText: self.searchKey,
                placeHolder: nil,
                action: { (text) in
                    self.searchKey = text
                    DispatchQueue.main.async {
                        self.form.removeAll()
                        self.createCells()
                    }
            })
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
