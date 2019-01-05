//
//  NarouSearchResultDetailViewControllerSwift.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2018/03/11.
//  Copyright © 2018年 IIMURA Takuji. All rights reserved.
//

import UIKit
import Eureka

class NarouSearchResultDetailViewControllerSwift: FormViewController {
    
    @objc var NarouContentDetail:NarouContentCacheData? = nil
    var m_SearchResult:[Any]?

    override func viewDidLoad() {
        super.viewDidLoad()

        BehaviorLogger.AddLog(description: "NarouSearchResultDetailViewControllerSwift viewDidLoad", data: [:])
        
        self.m_SearchResult = nil
        
        let downloadButton = UIBarButtonItem.init(title: NSLocalizedString("NarouSearchResultDetailViewControllerSwift_DownloadButton", comment: "Download"), style: .plain, target: self, action: #selector(NarouSearchResultDetailViewControllerSwift.downloadButtonClicked))
        let shareButton = UIBarButtonItem.init(barButtonSystemItem: .action, target: self, action: #selector(NarouSearchResultDetailViewControllerSwift.shareButtonClicked))
        self.navigationItem.rightBarButtonItems = [downloadButton, shareButton]

        guard let content = self.NarouContentDetail else {
            return
        }
        
        form +++ Section()
        <<< DetailedButtonRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Writer", comment: "作者")
        }.cellUpdate({ (cell, row) in
            if let writer = content.writer {
                cell.detailTextLabel?.text = writer
            }else{
                cell.detailTextLabel?.text = "-"
            }
        }).onCellSelection({ (buttonCellOf, row) in
            let builder = EasyDialog.Builder(self)
            .text(content: NSLocalizedString("NarouSearchViewController_SearchTitle_Searching", comment:"Searching"))
            .text(content: NSLocalizedString("NarouSearchViewController_SearchMessage_NowSearching", comment:"Now searching"))
            let dialog = builder.build()
            dialog.show()
            DispatchQueue(label: "com.limuraproducts.novelspeaker.search").async {
                self.m_SearchResult = NarouLoader.searchUserID(content.userid)
                DispatchQueue.main.async {
                    dialog.dismiss(animated: false, completion: {
                        self.performSegue(withIdentifier: "searchUserIDResultPushSegue", sender: self)
                    })
                }
            }
        }) <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Title", comment: "タイトル")
        } <<< TextRow() {
            if let title = content.title {
                $0.title = title
            }else{
                $0.title = "-"
            }
            $0.cell.textLabel?.numberOfLines = 0
            $0.disabled = true
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_UpdateDate", comment: "更新日時")
            if let updatedAt = content.novelupdated_at {
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                dateFormatter.timeStyle = .medium
                $0.value = dateFormatter.string(from: updatedAt)
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Point", comment: "総合点")
            if let globalPoint = content.global_point {
                $0.value = globalPoint.stringValue
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Storys", comment: "掲載話数")
            if let generalAllNo = content.general_all_no {
                $0.value = generalAllNo.stringValue
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Bookmark_num", comment: "ブックマーク数")
            if let favNovelCount = content.fav_novel_cnt {
                $0.value = favNovelCount.stringValue
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Point_mean", comment: "平均評価点")
            if let allPoint = content.all_point, let allHyoukaCount = content.all_hyoka_cnt {
                let average = allPoint.floatValue / allHyoukaCount.floatValue
                if average.isNaN {
                    $0.value = "0.0"
                }else{
                    $0.value = String.init(format: "%f", average)
                }
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Point_count", comment: "評価数")
            if let allHyoukaCount = content.all_hyoka_cnt {
                $0.value = String.init(format: "%d", allHyoukaCount.intValue)
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_IsEnd", comment: "連載状態")
            if let end = content.end {
                if end.intValue == 0 {
                    var state = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_IsEnd=0", comment: "完結 又は 短編小説")
                    if let general_all_no = content.general_all_no {
                        if general_all_no.intValue > 1 {
                            state = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_IsEnd=0&genelral_all_no>1", comment: "完結")
                        }
                    }
                    $0.value = state
                }else{
                    $0.value = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_IsEnd=1", comment: "連載中")
                }
            }else{
                $0.value = "-"
            }
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Keyword", comment: "キーワード")
        } <<< TextRow() {
            if let keyword = content.keyword {
                $0.title = keyword
            }else{
                $0.title = "-"
            }
            $0.cell.textLabel?.numberOfLines = 0
            $0.disabled = true
        } <<< LabelRow() {
            $0.title = NSLocalizedString("NarouSearchResultDetailViewControllerSwift_Story", comment: "あらすじ")
        } <<< TextRow() {
            if let story = content.story {
                $0.title = story
            }else{
                $0.title = "-"
            }
            $0.cell.textLabel?.numberOfLines = 0
            $0.disabled = true
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "searchUserIDResultPushSegue" {
            if let nextViewController = segue.destination as? NarouSearchResultTableViewController {
                nextViewController.searchResultList = self.m_SearchResult
            }
        }
    }

    @objc func downloadButtonClicked(){
        if let errString = GlobalDataSingleton.getInstance().addDownloadQueue(forNarou: self.NarouContentDetail) {
            EasyDialog.Builder(self)
            .label(text: NSLocalizedString("NarouSearchResultDetailViewController_FailedInAdditionToDownloadQueue", comment:"ダウンロードキューへの追加に失敗"))
            .text(content: errString)
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                dialog.dismiss(animated: false, completion: nil)
            })
            .build().show()
            return
        }
        if let title = self.NarouContentDetail?.title {
            EasyDialog.Builder(self)
            .text(content: String.init(format: NSLocalizedString("NarouSearchResultDetailViewController_AddSuccess_Title", comment:"作品名: %@"), title))
            .text(content: NSLocalizedString("NarouSearchResultDetailViewController_AddSuccess_ItWasAddedToDownloadQueue", comment:"ダウンロードキューに追加されました"))
            .addButton(title: NSLocalizedString("OK_button", comment: "OK"), callback: { (dialog) in
                dialog.dismiss(animated: false, completion: {
                    self.navigationController?.popViewController(animated: true)
                })
            }).build().show()
        }
    }
    
    @objc func shareButtonClicked(){
        guard let userid = self.NarouContentDetail?.userid else {
            return
        }
        EasyDialog.Builder(self)
        .label(text: NSLocalizedString("NarouSearchResultDetailViewController_GoToMypage", comment:"作者のマイページへ移動"))
        .text(content: NSLocalizedString("NarouSearchResultDetailViewController_GoToMyPageMessage", comment:"作者のマイページへ移動します。よろしいですか？"))
        .addButton(title: NSLocalizedString("Cancel_button", comment: "Cancel")) { (dialog) in
            dialog.dismiss(animated: false, completion: nil)
        }.addButton(title: NSLocalizedString("OK_button", comment: "OK")) { (dialog) in
            if let url = URL.init(string: String.init(format: "https://mypage.syosetu.com/%@/", userid)) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            dialog.dismiss(animated: false, completion: nil)
        }.build().show()
    }
}
