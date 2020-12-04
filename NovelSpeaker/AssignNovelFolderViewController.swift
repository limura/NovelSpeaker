//
//  AssignNovelFolderViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2019/06/12.
//  Copyright © 2019 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class AssignNovelFolderViewController: FormViewController {
    public var targetNovelID = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("AssignNovelFolderViewController_Title", comment: "フォルダへ分類")
        createCells()
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonClicked(_:)))
        self.navigationItem.rightBarButtonItems = [addButton]
    }
    
    func rebuildCells() {
        self.form.removeAll()
        createCells()
    }
    
    func createCells() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let tags = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Folder) else { return }
            
            let section = Section()
            for tag in tags {
                let tagName = tag.name
                let tagType = tag.type
                section <<< CheckRow(){
                    $0.title = tagName
                    $0.trailingSwipe.actions = [
                        SwipeAction(style: .destructive, title: NSLocalizedString("AssignNovelFolderViewController_DeleteSwipeActionTitle", comment: "削除"), handler: { (action, row, completionHandler) in
                            RealmUtil.RealmBlock { (realm) -> Void in
                                guard let tag = RealmNovelTag.SearchWith(realm: realm, name: tagName, type: tagType) else {
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
                    $0.value = tag.targetNovelIDArray.contains(self.targetNovelID)
                }.onChange({ (row) in
                    RealmUtil.RealmBlock { (realm) -> Void in
                        guard let value = row.value, let tag = RealmNovelTag.SearchWith(realm: realm, name: tagName, type: tagType) else { return }
                        if value {
                            RealmUtil.WriteWith(realm: realm, block: { (realm) in
                                RealmNovelTag.AddTag(realm: realm, name: tagName, novelID: self.targetNovelID, type: RealmNovelTag.TagType.Folder)
                            })
                        }else{
                            RealmUtil.WriteWith(realm: realm, block: { (realm) in
                                tag.unref(realm: realm, novelID: self.targetNovelID)
                            })
                        }
                    }
                })
            }

            self.form +++ section
        }
    }
    
    @objc func addButtonClicked(_ sender: UIBarButtonItem) {
        DispatchQueue.main.async {
            NiftyUtility.EasyDialogTextInput(
                viewController: self,
                title: NSLocalizedString("AssignNovelFolderViewController_CreateNewTagTitle", comment: "新規フォルダ作成"),
                message: nil,
                textFieldText: "",
                placeHolder: NSLocalizedString("AssignNovelFolderViewController_CreateNewTagPlaceHolder", comment: "同じ名前のフォルダは生成できません"),
                action: { (name) in
                    RealmUtil.RealmBlock { (realm) -> Void in
                        if RealmNovelTag.SearchWith(realm: realm, name: name, type: RealmNovelTag.TagType.Folder) != nil {
                            DispatchQueue.main.async {
                                NiftyUtility.EasyDialogMessageDialog(viewController: self, message: NSLocalizedString("AssignNovelFolderViewController_CreateNewTagPlaceHolder", comment: "同じ名前のフォルダは生成できません"))
                            }
                            return
                        }
                        RealmUtil.WriteWith(realm: realm, block: { (realm) in
                            RealmNovelTag.AddTag(realm: realm, name: name, novelID: self.targetNovelID, type: RealmNovelTag.TagType.Folder)
                        })
                    }
                    DispatchQueue.main.async {
                        self.rebuildCells()
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
