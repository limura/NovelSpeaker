//
//  NovelFolderManageTableViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/11/16.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import UIKit
import RealmSwift

protocol TableViewRow {
    func getIdentifier() -> String
    func assignCell(cell:UITableViewCell)
    func canEditable() -> Bool // delete か insert ができる場合は true
    func getEditingStyle() -> UITableViewCell.EditingStyle
}

protocol TableViewSection {
    func numberOfRows() -> Int
    func assignCell(index:Int, cell:UITableViewCell)
    func canEditable(index:Int) -> Bool
    func doDelete(index:Int)
    func canMove(index:Int) -> Bool
    func move(fromIndex:Int, toIndex:Int)
    func getCellIdentifier(index:Int) -> String
    func getTitle() -> String?
    func getEditingStyle(index:Int) -> UITableViewCell.EditingStyle
}

class FolderAddButtonRow: TableViewRow, MultipleNovelIDSelectorDelegate {
    let folderName:String
    weak var parentViewController:UIViewController?
    
    init(folderName:String, parentViewController:UIViewController?) {
        self.folderName = folderName
        self.parentViewController = parentViewController
    }
    
    func getIdentifier() -> String {
        return "NovelFolderManageTableViewController_FolderRow"
    }
    func assignCell(cell: UITableViewCell) {
        cell.textLabel?.text = NSLocalizedString("NovelFolderManageTableViewController_AddButtonTitle", comment: "このフォルダに入れる小説を選択する")
        cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(FolderDeleteFolderButtonRow.tapGestureEvent)))
    }
    func canEditable() -> Bool {
        return true
    }
    func getEditingStyle() -> UITableViewCell.EditingStyle {
        return .insert
    }
    @objc func tapGestureEvent() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let novelIDArray = RealmNovelTag.SearchWith(realm: realm, name: self.folderName, type: RealmNovelTag.TagType.Bookshelf)?.targetNovelIDArray, let parent = self.parentViewController else { return }
            DispatchQueue.main.async {
                let nextViewController = MultipleNovelIDSelectorViewController()
                var set = Set<String>()
                for novelID in novelIDArray {
                    set.insert(novelID)
                }
                nextViewController.SelectedNovelIDSet = set
                nextViewController.IsUseAnyNovelID = false
                nextViewController.delegate = self
                parent.navigationController?.pushViewController(nextViewController, animated: true)
            }
        }
        
    }
    
    func MultipleNovelIDSelectorSelected(selectedNovelIDSet: Set<String>, hint: String) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let folder = RealmNovelTag.SearchWith(realm: realm, name: self.folderName, type: RealmNovelTag.TagType.Bookshelf) else { return }
            var set = selectedNovelIDSet
            var newNovelIDArray:[String] = []
            for novelID in folder.targetNovelIDArray {
                if set.contains(novelID) {
                    set.remove(novelID)
                    newNovelIDArray.append(novelID)
                }
            }
            newNovelIDArray.append(contentsOf: set)
            
            RealmUtil.WriteWith(realm: realm) { (realm) in
                folder.targetNovelIDArray.removeAll()
                folder.targetNovelIDArray.append(objectsIn: newNovelIDArray)
                realm.add(folder, update: .modified)
            }
            DispatchQueue.main.async {
                guard let parent = self.parentViewController as? NovelFolderManageTableViewController else { return }
                parent.LoadFolder()
            }
        }
    }
}

class FolderDeleteFolderButtonRow: TableViewRow {
    let folderName:String
    weak var parentViewController:UIViewController?
    
    init(folderName:String, parentViewController:UIViewController?) {
        self.folderName = folderName
        self.parentViewController = parentViewController
    }
    
    func getIdentifier() -> String {
        return "NovelFolderManageTableViewController_DeleteFolderButtonRow"
    }
    func assignCell(cell: UITableViewCell) {
        cell.textLabel?.text = NSLocalizedString("NovelFolderManageTableViewController_DeleteButtonTitle", comment: "このフォルダを削除する")
        cell.textLabel?.textAlignment = .center
        if #available(iOS 13.0, *) {
            cell.textLabel?.textColor = UIColor.link
        } else {
            cell.textLabel?.textColor = UIColor.systemBlue
        }
        cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(FolderDeleteFolderButtonRow.tapGestureEvent)))
    }
    func canEditable() -> Bool {
        return false
    }
    func getEditingStyle() -> UITableViewCell.EditingStyle {
        return .none
    }
    
    @objc func tapGestureEvent() {
        DispatchQueue.main.async {
            guard let parentViewController = self.parentViewController else { return }
            NiftyUtilitySwift.EasyDialogTwoButton(viewController: parentViewController, title: NSLocalizedString("NovelFolderManageTableViewController_ConifirmRemoveFolder_Title", comment: "フォルダの削除"), message: String(format: NSLocalizedString("NovelFolderManageTableViewController_ConfifirmRemoveFolder_Message_Format", comment: "フォルダ %@ を削除しますか？"), self.folderName), button1Title: nil, button1Action: nil, button2Title: NSLocalizedString("NovelFolderManageTableViewController_ConifirmRemoveFolder_OKButton", comment: "削除")) {
                RealmUtil.Write { (realm) in
                    guard let folder = RealmNovelTag.SearchWith(realm: realm, name: self.folderName, type: RealmNovelTag.TagType.Bookshelf) else { return }
                    folder.delete(realm: realm)
                }
                guard let parent = self.parentViewController as? NovelFolderManageTableViewController else { return }
                parent.LoadFolder()
            }
        }
    }
}

struct FolderRow: TableViewRow {
    let novelTitle:String
    let novelID:String
    
    func getIdentifier() -> String {
        return "NovelFolderManageTableViewController_FolderRow"
    }
    func assignCell(cell: UITableViewCell) {
        cell.textLabel?.text = novelTitle
    }
    func canEditable() -> Bool {
        return true
    }
    func getEditingStyle() -> UITableViewCell.EditingStyle {
        return .delete
    }
    func getNovelID() -> String { return novelID }
}

class FolderSection:TableViewSection {
    let folderName:String
    var rows:[TableViewRow]
    var isFolded:Bool = false
    weak var parentViewController:UIViewController?
    
    init(folderName:String, rows:[TableViewRow], parentViewController:UIViewController?) {
        self.folderName = folderName
        self.rows = rows
        self.parentViewController = parentViewController
        self.rows.append(FolderAddButtonRow(folderName: folderName, parentViewController: parentViewController))
        self.rows.append(FolderDeleteFolderButtonRow(folderName: folderName, parentViewController: parentViewController))
    }
    
    func numberOfRows() -> Int {
        return rows.count
    }
    func assignCell(index: Int, cell: UITableViewCell) {
        guard rows.count > index else { return }
        rows[index].assignCell(cell: cell)
    }
    func canEditable(index: Int) -> Bool {
        guard rows.count > index else { return false }
        return rows[index].canEditable()
    }
    func doDelete(index: Int) {
        guard rows.count > index else { return }
        let row = self.rows.remove(at: index)
        if let folderRow = row as? FolderRow {
            RealmUtil.Write { (realm) in
                guard let folder = RealmNovelTag.SearchWith(realm: realm, name: self.folderName, type: RealmNovelTag.TagType.Bookshelf), let index = folder.targetNovelIDArray.index(of: folderRow.novelID) else { return }
                folder.targetNovelIDArray.remove(at: index)
                realm.add(folder, update: .modified)
            }
        }
    }
    func canMove(index: Int) -> Bool {
        guard rows.count > index else { return false }
        if rows[index] is FolderRow {
            return true
        }
        return false
    }
    func move(fromIndex: Int, toIndex: Int) {
        guard rows.count > fromIndex, rows.count > toIndex else { return }
        let row = rows.remove(at: fromIndex)
        rows.insert(row, at: toIndex)
    }
    func getCellIdentifier(index: Int) -> String {
        guard rows.count > index else { return "NovelFolderManageTableViewController_FolderRow" }
        return rows[index].getIdentifier()
    }
    func getTitle() -> String? {
        return self.folderName
    }
    func getEditingStyle(index: Int) -> UITableViewCell.EditingStyle {
        guard rows.count > index else { return .none }
        return rows[index].getEditingStyle()
    }
    func getListedNovelIDArray() -> [String] {
        var result:[String] = []
        for row in rows {
            if let folder = row as? FolderRow {
                result.append(folder.getNovelID())
            }
        }
        return result
    }
}

class ManageSectionAddRow: TableViewRow {
    weak var parentViewController:UIViewController?
    
    init(parentViewController:UIViewController?) {
        self.parentViewController = parentViewController
    }
    
    func getIdentifier() -> String {
        return "NovelFolderManageTableViewController_ManageRow"
    }
    func assignCell(cell: UITableViewCell) {
        cell.textLabel?.text = NSLocalizedString("NovelFolderManageTableViewController_ManageRow_AddNewSection_Title", comment: "新しいフォルダを追加する")
        cell.textLabel?.textAlignment = .center
        if #available(iOS 13.0, *) {
            cell.textLabel?.textColor = UIColor.link
        } else {
            cell.textLabel?.textColor = UIColor.systemBlue
        }
        cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(ManageSectionAddRow.tapGestureEvent)))
    }
    func canEditable() -> Bool {
        return false
    }
    func getEditingStyle() -> UITableViewCell.EditingStyle {
        return .none
    }
    @objc func tapGestureEvent() {
        DispatchQueue.main.async {
            guard let parentViewController = self.parentViewController else { return }
            NiftyUtilitySwift.EasyDialogTextInput(viewController: parentViewController, title: nil, message: NSLocalizedString("NovelFolderManageTableViewController_CreateNewFolderMessage", comment: "新しく作成するフォルダ名を入力してください"), textFieldText: nil, placeHolder: NSLocalizedString("NovelFolderManageTableViewController_CreateNewFolder_PlaceHolderMessage", comment: "既に存在する名前や空文字列は指定できません")) { (name) in
                if name.count <= 0 {
                    guard let parentViewController = self.parentViewController else { return }
                    NiftyUtilitySwift.EasyDialogOneButton(viewController: parentViewController, title: nil, message: NSLocalizedString("NovelFolderManageTableViewController_CreateNewFolder_Error_NoName", comment: "空文字列は指定できません"), buttonTitle: nil, buttonAction: nil)
                    return
                }
                RealmUtil.RealmBlock { (realm) -> Void in
                    if let _ = RealmNovelTag.SearchWith(realm: realm, name: name, type: RealmNovelTag.TagType.Bookshelf) {
                        guard let parentViewController = self.parentViewController else { return }
                        NiftyUtilitySwift.EasyDialogOneButton(viewController: parentViewController, title: nil, message: NSLocalizedString("NovelFolderManageTableViewController_CreateNewFolder_Error_SameNameAlive", comment: "同じ名前のフォルダが既に定義されています"), buttonTitle: nil, buttonAction: nil)
                        return
                    }
                    RealmUtil.WriteWith(realm: realm) { (realm) in
                        let tag = RealmNovelTag.CreateNewTag(name: name, type: RealmNovelTag.TagType.Bookshelf)
                        realm.add(tag, update: .modified)
                    }
                    guard let parentTableViewController = self.parentViewController as? NovelFolderManageTableViewController else { return }
                    parentTableViewController.LoadFolder()
                }
            }
        }
    }
}

class ManageSection:TableViewSection {
    weak var parentViewController:UIViewController?
    let rows:[TableViewRow]
    
    init(parentViewController:UIViewController) {
        self.parentViewController = parentViewController
        rows = [ManageSectionAddRow(parentViewController: parentViewController)]
    }
    
    func numberOfRows() -> Int {
        return 1
    }
    func assignCell(index: Int, cell: UITableViewCell) {
        guard rows.count > index else { return }
        rows[index].assignCell(cell: cell)
    }
    func canEditable(index: Int) -> Bool {
        return false
    }
    func doDelete(index: Int) {
        // nothing to do
    }
    func canMove(index: Int) -> Bool {
        return false
    }
    func move(fromIndex: Int, toIndex: Int) {
    }
    func getCellIdentifier(index: Int) -> String {
        return "NovelFolderManageTableViewController_ManageRow"
    }
    func getTitle() -> String? {
        return nil
    }
    func getEditingStyle(index: Int) -> UITableViewCell.EditingStyle {
        return .none
    }
}

class NovelFolderManageTableViewController: UITableViewController, RealmObserverResetDelegate {
    
    var folderSectionArray:[TableViewSection] = []
    var realmNovelTagObserverToken:NotificationToken? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NovelFolderManageTableViewController_FolderRow")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NovelFolderManageTableViewController_ManageRow")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NovelFolderManageTableViewController_DeleteFolderButtonRow")
        self.tableView.isEditing = true
        
        self.title = NSLocalizedString("NovelFolderManageTableViewController_Title", comment: "フォルダ内小説の並び替え")
        
        folderSectionArray = [ManageSection(parentViewController: self)]
        LoadFolder()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        registerObserver()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveFolderOrder()
    }
    
    func StopObservers(){
        realmNovelTagObserverToken = nil
    }
    func RestartObservers(){
        StopObservers()
        registerObserver()
    }
    
    func registerObserver() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let tagArray = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Bookshelf) else { return }
            self.realmNovelTagObserverToken = tagArray.observe({ (change) in
                switch change {
                case .update(_, _, _, _):
                    self.LoadFolder()
                case .error(_):
                    break
                case .initial(_):
                    break
                }
            })
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return folderSectionArray.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard folderSectionArray.count > section else { return 0 }
        let folderSection = folderSectionArray[section]
        return folderSection.numberOfRows()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard self.folderSectionArray.count > indexPath.section else {
            let cell = UITableViewCell()
            cell.textLabel?.text = "-"
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: folderSectionArray[indexPath.section].getCellIdentifier(index: indexPath.row), for: indexPath)

        guard self.folderSectionArray.count > indexPath.section else {
            cell.textLabel?.text = "-"
            return cell
        }
        let section = self.folderSectionArray[indexPath.section]
        section.assignCell(index: indexPath.row, cell: cell)

        return cell
    }

    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        guard folderSectionArray.count > indexPath.section else { return false }
        return folderSectionArray[indexPath.section].canEditable(index: indexPath.row)
    }

    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            guard folderSectionArray.count > indexPath.section else { return }
            folderSectionArray[indexPath.section].doDelete(index: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
            print(#function)
            print("tableView commit insert call: \(indexPath.section), \(indexPath.row)")
        }
    }

    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
        let targetSection = fromIndexPath.section
        guard targetSection == to.section, folderSectionArray.count > targetSection else { return }
        folderSectionArray[targetSection].move(fromIndex: fromIndexPath.row, toIndex: to.row)
    }

    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        guard folderSectionArray.count > indexPath.section else { return false }
        return folderSectionArray[indexPath.section].canMove(index: indexPath.row)
    }
    
    // Section のヘッダに表示される文字列を返す。
    // 他に、UIView を返す奴もあるんだけど、Height を返すのもあったりするので UIView を返す奴を使う場合は Height も返すべきなのかもしれない。
    // Section のヘッダって全部大文字になっちゃうのなんとかならんのか？
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard folderSectionArray.count > section else { return nil }
        return folderSectionArray[section].getTitle()
    }
    
    // 移動しようとしている時に、その移動先には移動できるのかどうかを決められる奴ぽい。
    // 移動できるなら proposedDestinationIndexPath を返して、移動できないなら sourceIndexPath を返す
    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        if sourceIndexPath.section == proposedDestinationIndexPath.section, folderSectionArray.count > sourceIndexPath.section, folderSectionArray[sourceIndexPath.section].canMove(index: sourceIndexPath.row), folderSectionArray[sourceIndexPath.section].canMove(index: proposedDestinationIndexPath.row) {
            return proposedDestinationIndexPath
        }
        return sourceIndexPath
    }
    
    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard folderSectionArray.count > indexPath.section else { return .none }
        return folderSectionArray[indexPath.section].getEditingStyle(index: indexPath.row)
    }

    /*
    // インデントをつける事ができるらしい。返却しているのは恐らく pixel数ぽい？
    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        return 0
    }
    */
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    
    func LoadFolder() {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let folderArray = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Bookshelf) else { return }
                var newFolderSectionArray:[TableViewSection] = [ManageSection(parentViewController: self)]
                for folder in folderArray {
                    let rows:[FolderRow]
                    if let novelArray = RealmNovel.SearchNovelWith(realm: realm, novelIDArray: Array(folder.targetNovelIDArray)){
                        rows = novelArray.map({FolderRow(novelTitle: $0.title, novelID: $0.novelID)})
                    }else{
                        rows = []
                    }
                    let section = FolderSection(folderName: folder.name, rows: rows, parentViewController: self)
                    newFolderSectionArray.append(section)
                }
                self.folderSectionArray = newFolderSectionArray
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    func saveFolderOrder() {
        RealmUtil.Write(block: { (realm) in
            guard let folderArray = RealmNovelTag.GetObjectsFor(realm: realm, type: RealmNovelTag.TagType.Bookshelf) else { return }
            var novelIDArrayDictionary:[String:[String]] = [:]
            for section in self.folderSectionArray {
                if let folderSection = section as? FolderSection, let title = folderSection.getTitle() {
                    novelIDArrayDictionary[title] = folderSection.getListedNovelIDArray()
                }
            }
            for folder in folderArray {
                guard let newNovelIDArray = novelIDArrayDictionary[folder.name] else { continue }
                let currentNovelIDArray = Array(folder.targetNovelIDArray)
                if currentNovelIDArray == newNovelIDArray { continue }
                folder.targetNovelIDArray.removeAll()
                folder.targetNovelIDArray.append(objectsIn: newNovelIDArray)
                realm.add(folder, update: .modified)
            }
        })
    }
}
