//
//  NovelLikeOrderSettingViewController.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/12/14.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka
import RealmSwift

class NovelLikeOrderSettingViewController: FormViewController, MultipleNovelIDSelectorDelegate, RealmObserverResetDelegate {
    
    var globalStateNotificationToken:NotificationToken? = nil

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        self.createRows()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(addNovelButtonClicked))
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        self.registerGlobalStateObserver()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveCurrentOrder()
    }
    
    func StopObservers() {
        globalStateNotificationToken = nil
    }
    
    func RestartObservers() {
        StopObservers()
        registerGlobalStateObserver()
    }
    
    func registerGlobalStateObserver() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            self.globalStateNotificationToken = globalState.observe({ (change) in
                switch change {
                case .change(_, let propertys):
                    for property in propertys {
                        if property.name == "novelLikeOrder" {
                            DispatchQueue.main.async {
                                self.form.removeAll()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    self.createRows()
                                }
                            }
                        }
                    }
                case .deleted:
                    break
                case .error(_):
                    break
                }
            })
        }
    }
    
    func saveCurrentOrder() {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm), let allNovelIDArray = RealmNovel.GetAllObjectsWith(realm: realm)?.map({$0.novelID}) else { return }
            let newOrder = List<String>()
            for row in self.form.allRows {
                guard let novelID = row.tag, novelID.count > 0, allNovelIDArray.contains(novelID) else { continue }
                newOrder.append(novelID)
            }
            RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalStateNotificationToken]) { (realm) in
                globalState.novelLikeOrder.removeAll()
                globalState.novelLikeOrder.append(objectsIn: newOrder)
            }
        }
    }
    
    func createRows() {
        guard let novelLikeOrder = RealmUtil.RealmBlock(block: { (realm) -> List<String>? in
            return RealmGlobalState.GetInstanceWith(realm: realm)?.novelLikeOrder
        }) else { return }
        self.form +++ MultivaluedSection(multivaluedOptions: [.Reorder], header: nil, footer: nil, { (section) in
            RealmUtil.RealmBlock { (realm) -> Void in
                for novelID in novelLikeOrder {
                    guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { continue }
                    section <<< LabelRow(novel.novelID) {
                        $0.title = novel.title
                    }
                }
            }
        })
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        super.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
        self.saveCurrentOrder()
    }
    
    @objc func addNovelButtonClicked() {
        RealmUtil.RealmBlock { (realm) -> Void in
            let novelLikeOrder = RealmGlobalState.GetInstanceWith(realm: realm)?.novelLikeOrder ?? List<String>()
            var idSet = Set<String>()
            for novelID in novelLikeOrder {
                idSet.insert(novelID)
            }
            let nextViewController = MultipleNovelIDSelectorViewController()
            nextViewController.delegate = self
            nextViewController.SelectedNovelIDSet = idSet
            nextViewController.IsUseAnyNovelID = false
            self.navigationController?.pushViewController(nextViewController, animated: true)
        }
    }
    
    func MultipleNovelIDSelectorSelected(selectedNovelIDSet:Set<String>, hint:String) {
        RealmUtil.RealmBlock { (realm) -> Void in
            guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
            var newNovelIDSet = Set<String>()
            var removedNovelIDSet = Set<String>()
            let currentNovelLikeOrder = globalState.novelLikeOrder
            for novelID in selectedNovelIDSet {
                if currentNovelLikeOrder.contains(novelID) == false {
                    newNovelIDSet.insert(novelID)
                }
            }
            for novelID in currentNovelLikeOrder {
                if selectedNovelIDSet.contains(novelID) == false {
                    removedNovelIDSet.insert(novelID)
                }
            }
            RealmUtil.WriteWith(realm: realm) { (realm) in
                for novelID in removedNovelIDSet {
                    if let index = currentNovelLikeOrder.index(of: novelID) {
                        currentNovelLikeOrder.remove(at: index)
                    }
                }
                for novelID in newNovelIDSet {
                    currentNovelLikeOrder.append(novelID)
                }
            }
        }
    }
}
