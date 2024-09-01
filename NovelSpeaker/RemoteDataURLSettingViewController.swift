//
//  RemoteDataURLSetting.swift
//  NovelSpeaker
//
//  Created by 飯村卓司 on 2020/09/22.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import Foundation
import Eureka
import RealmSwift

class RemoteDataURLSettingViewController: FormViewController, RealmObserverResetDelegate {
    var globalDataNotificationToken:NotificationToken? = nil
    let preferredSiteInfoSectionTag = "preferredSiteInfoSectionTag"
    var startPreferredSiteInfoURLList:[String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        BehaviorLogger.AddLog(description: "RemoteDataURLSettingViewController viewDidLoad", data: [:])
        
        self.title = NSLocalizedString("RemoteDataURLSettingViewController_Title", comment: "内部データ参照用URLの設定")
        
        registerObserver()
        RealmObserverHandler.shared.AddDelegate(delegate: self)
        createCells()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let items = self.form.sectionBy(tag: self.preferredSiteInfoSectionTag) as? MultivaluedSection {
            let filterdItems = items.values().compactMap {
                if let url = $0 as? URL {
                    return url.absoluteString
                } else {
                    return nil
                }
            }
            if startPreferredSiteInfoURLList == filterdItems { return }
            // キャッシュファイルの対象が変わる前に一旦キャッシュファイルを削除させるために ClearSiteInfo() を呼び出します。
            StoryHtmlDecoder.shared.ClearSiteInfo()
            RealmUtil.Write { realm in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                globalState.preferredSiteInfoURLList.removeAll()
                globalState.preferredSiteInfoURLList.append(objectsIn: filterdItems)
            }
            // 念のため改めて ClearSiteInfo() を呼んでおきます。
            StoryHtmlDecoder.shared.ClearSiteInfo()
        }
    }
    
    deinit {
        RealmObserverHandler.shared.RemoveDelegate(delegate: self)
    }
    
    func StopObservers(){
        globalDataNotificationToken = nil
    }
    func RestartObservers(){
        StopObservers()
        registerObserver()
    }
    
    func registerObserver() {
        let targets:[String] = ["autopagerizeSiteInfoURL", "novelSpeakerSiteInfoURL", "defaultSpeechModURL", "searchInfoURL", "preferredSiteInfoURLList"]
        
        RealmUtil.RealmBlock { (realm) -> Void in
            if let globalData = RealmGlobalState.GetInstanceWith(realm: realm) {
                self.globalDataNotificationToken = globalData.observe({ (change) in
                    switch change {
                    case .change(_, let propertys):
                        for property in propertys {
                            if targets.contains(property.name) {
                                DispatchQueue.main.async {
                                    self.form.removeAll()
                                    self.createCells()
                                }
                                return
                            }
                        }
                    case .deleted:
                        break
                    default:
                        break
                    }
                })
            }
        }
    }
    
    func createCells() {
        let globalState:RealmGlobalState?
        if let realm = try? RealmUtil.GetRealm(), let state = RealmGlobalState.GetInstanceWith(realm: realm) {
            globalState = state
            startPreferredSiteInfoURLList = state.preferredSiteInfoURLList.map({$0})
        }else{
            globalState = nil
        }
        
        self.form
        +++ Section()
        <<< LabelRow() {
            $0.title = NSLocalizedString("RemoteDataURLSettingViewController_Information", comment: "注意: ここにある設定は下手に書き換えると ことせかい が正常に動作しなくなる可能性があります。書き換えを行う場合は内容を理解した上で行ってください。\nなお、標準設定は全て「空(なにも書かれていない)」状態ですので問題が起こった場合には全ての項目の内容を消すことで標準設定に戻すことができます。")
            $0.cell.textLabel?.numberOfLines = 0
        }
        +++ MultivaluedSection(multivaluedOptions: [.Insert, .Delete, .Reorder],
            header: NSLocalizedString("RemoteDataURLSettingViewController_preferredSiteInfoSection_Title", comment: "優先SiteInfo"),
            footer: "") {
            // 削除イベントを取るのが面倒くさそうだったので、viewDidDisappearでこのタグから内容を取り出してDBを更新することにします。
            $0.tag = self.preferredSiteInfoSectionTag
            $0.addButtonProvider = { section in
                return ButtonRow(){
                    $0.title = NSLocalizedString("RemoteDataURLSettingViewController_preferredSiteInfoList_AddButtonTitle", comment: "新しいURLを追加")
                }
            }
            $0.multivaluedRowToInsertAt = { index in
                return URLRow() { (row) in
                    row.placeholder = NSLocalizedString("RemoteDataURLSettingViewController_preferredSiteInfoList_AddURLPlaceholder", comment: "URLを入力してください")
                }
            }
            let currentForm = $0
            RealmUtil.RealmBlock { realm in
                if let preferredSiteInfoURLList = RealmGlobalState.GetInstanceWith(realm: realm)?.preferredSiteInfoURLList {
                    for urlString in preferredSiteInfoURLList {
                        if let url = URL(string: urlString) {
                            currentForm <<< URLRow() {
                                $0.value = url
                            }
                        }
                    }
                }
            }
        }
        +++ Section(NSLocalizedString("RemoteDataURLSettingViewController_NovelSpeakerSiteInfoSection_Title", comment: "ことせかい用SiteInfo"))
        <<< TextRow() {
            $0.title = ""
            $0.cell.textLabel?.numberOfLines = 0
            $0.cell.textField.borderStyle = .roundedRect
            $0.cell.textField.placeholder = NSLocalizedString("RemoteDataURLSettingViewController_URLTextFieldPlaceholder", comment: "URLを入力してください")
            $0.value = globalState?.novelSpeakerSiteInfoURL ?? ""
        }.onChange({ (row) in
            let value = row.value ?? ""
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalDataNotificationToken]) { (realm) in
                    globalState.novelSpeakerSiteInfoURL = value
                }
            }
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("RemoteDataURLSettingViewController_NovelSpeakerSiteInfoSampleButton", comment: "標準設定データのURLを開く")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (cellOf, row) in
            if let url = URL(string: StoryHtmlDecoder.NovelSpeakerSiteInfoTSVURL) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
        +++ Section(NSLocalizedString("RemoteDataURLSettingViewController_FallbackSiteInfoSection_Title", comment: "次点のSiteInfo"))
        <<< TextRow() {
            $0.title = ""
            $0.cell.textLabel?.numberOfLines = 0
            $0.cell.textField.borderStyle = .roundedRect
            $0.cell.textField.placeholder = NSLocalizedString("RemoteDataURLSettingViewController_URLTextFieldPlaceholder", comment: "URLを入力してください")
            $0.value = globalState?.autopagerizeSiteInfoURL ?? ""
        }.onChange({ (row) in
            let value = row.value ?? ""
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalDataNotificationToken]) { (realm) in
                    globalState.autopagerizeSiteInfoURL = value
                }
            }
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("RemoteDataURLSettingViewController_FallbackSiteInfoSampleButton", comment: "標準設定データのURLを開く")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (cellOf, row) in
            if let url = URL(string: StoryHtmlDecoder.AutopagerizeSiteInfoJSONURL) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
        +++ Section(NSLocalizedString("RemoteDataURLSettingViewController_SpeechModSection_Title", comment: "標準の読み替え設定"))
        <<< TextRow() {
            $0.title = ""
            $0.cell.textLabel?.numberOfLines = 0
            $0.cell.textField.borderStyle = .roundedRect
            $0.cell.textField.placeholder = NSLocalizedString("RemoteDataURLSettingViewController_URLTextFieldPlaceholder", comment: "URLを入力してください")
            $0.value = globalState?.defaultSpeechModURL ?? ""
        }.onChange({ (row) in
            let value = row.value ?? ""
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalDataNotificationToken]) { (realm) in
                    globalState.defaultSpeechModURL = value
                }
            }
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("RemoteDataURLSettingViewController_SpeechModSampleButton", comment: "標準設定データのURLを開く")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (cellOf, row) in
            if let url = URL(string: "https://limura.github.io/NovelSpeaker/data/DefaultSpeechModList.json") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
        +++ Section(NSLocalizedString("RemoteDataURLSettingViewController_SearchInfoSection_Title", comment: "Web検索用検索ヒント情報"))
        <<< TextRow() {
            $0.title = ""
            $0.cell.textLabel?.numberOfLines = 0
            $0.cell.textField.borderStyle = .roundedRect
            $0.cell.textField.placeholder = NSLocalizedString("RemoteDataURLSettingViewController_URLTextFieldPlaceholder", comment: "URLを入力してください")
            $0.value = globalState?.searchInfoURL ?? ""
        }.onChange({ (row) in
            let value = row.value ?? ""
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                RealmUtil.WriteWith(realm: realm, withoutNotifying: [self.globalDataNotificationToken]) { (realm) in
                    globalState.searchInfoURL = value
                }
            }
        })
        <<< ButtonRow() {
            $0.title = NSLocalizedString("RemoteDataURLSettingViewController_SearchInfoSampleButton", comment: "標準設定データのURLを開く")
            $0.cell.textLabel?.numberOfLines = 0
        }.onCellSelection({ (cellOf, row) in
            if let url = URL(string: NSLocalizedString("https://limura.github.io/NovelSpeaker/data/WebSearchInfo-ja_JP.json", comment: "適切にURLを返すように Localizable.strings に設定しておく。言語とか地域とかOS側の言語とかアプリ側の言語とかもうわけわからんので NSLocalizedString() 側で設定された言語の設定ファイルを読み込む、というイメージにする。")) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        })
    }
}

