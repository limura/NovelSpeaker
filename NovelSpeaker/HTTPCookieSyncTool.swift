//
//  HTTPCookieSyncTool.swift
//  novelspeaker
//
//  Created by 飯村卓司 on 2020/10/28.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//
/*
 ことせかい で使っている HTTP cookie を Realm側 に保存したり Realm側 から読み込んだりするためのツール

 HTTP cookie 周りは一つのアプリ内で共有される設定がある
 (基本的には他のアプリとは共有されないが、チームID?か何かを指定してやることで共有できる道があるぽい)
 てのと、
 HTTP cookie は URLSession や WkWebView のそれぞれが管理している
 という条件があって、
 URLSession にしろ WkWebView にしろ、何も指定しないと使われる default の cookieStorage がある。
 で、その default の cookieStorage のどちらかに書き込むと
 もう片方にも同様の内容が書き込まれるという謎の仕組みがある。
 この辺りは https://qiita.com/temoki/items/f14156b39f3aa913ed7e にそれぽい事が書いてあって
 確かに使ってみた所そんな感じの動きをしていることが確認された。

 ことせかい においては URLSession と WkWebView のどちらも使っていて、
 それぞれ default の cookieStorage を利用している。
 そのため、とりあえずは URLSession の側の default の cookieStorage を弄る事にする。
 (つまり WkWebview 側については触らずにテキトーに同期されるのを待つというスタンスにしている)

 で、iCloud で同期している別端末で cookie を使えると便利であると思われるため、
 cookieが更新される可能性がある場合には Realm側 にも書き込む事にして、
 Realm側 では observer を立てて自分以外の何者かが更新した場合はその更新情報をマージする、
 という戦術を取ることにする。
 
 という事で、この class はアプリ内での Realm側 への Save() と、Realm側 からの Load()、
 observer で監視して別端末からの更新を Load() するという事をするための class となる。
 
 動作としては、だいたい以下の3つの動きをする。

 ・起動時にRealm側からLoad()
 ・ダウンロードが落ち着いた(一通りダウンロードが終わった)らSave()
 ・observer で監視して別端末から更新があったらLoad()
 
 なお、Safariからの読み込みの場合に受け取ることのできるcookieはSave()はせず、
 expire date を指定しない session only な cookie として扱う事にする。
 (その上で、ダウンロードが終わった時に expire date が存在する物については Save() されるため、
 ログイン状態が保存される「場合がある」という形になりそう)
 */

import UIKit
import RealmSwift

class HTTPCookieSyncTool: RealmObserverResetDelegate {
    static let shared = HTTPCookieSyncTool()
    var globalStateNotificationToken:NotificationToken? = nil
    
    init() {
        WaitCanUseRealm {
            self.Load()
            DispatchQueue.main.async {
                self.observeGlobalState()
                RealmObserverHandler.shared.AddDelegate(delegate: self)
            }
        }
    }
    
    func WaitCanUseRealm(method: @escaping (()->Void)) {
        if CoreDataToRealmTool.IsConvertFromCoreDataFinished() {
            print("WaitCanUseRealmThenDo CoreDataToRealmTool.IsConvertFromCoreDataFinished() return true.")
            method()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.WaitCanUseRealm(method: method)
        }
    }
    
    func StopObservers() {
        globalStateNotificationToken = nil
    }
    
    func RestartObservers() {
        StopObservers()
        observeGlobalState()
    }
    
    func observeGlobalState() {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
                self.globalStateNotificationToken = globalState.observe({ (change) in
                    switch change {
                    case .change(_, let propertys):
                        for property in propertys {
                            if property.name == "cookieArrayData" {
                                print("HTTPCookieTool Load() by Realm observer event handler.")
                                DispatchQueue.main.async {
                                    self.Load()
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
    }
    
    func Save(){
        DispatchQueue.main.async {
            RealmUtil.Write(withoutNotifying: [self.globalStateNotificationToken]) { (realm) in
                self.SaveCookiesFromURLSessionSharedConfigurationWith(realm: realm)
            }
        }
    }
    func SaveSync(){
        NiftyUtilitySwift.DispatchSyncMainQueue {
            RealmUtil.Write(withoutNotifying: [self.globalStateNotificationToken]) { (realm) in
                self.SaveCookiesFromURLSessionSharedConfigurationWith(realm: realm)
            }
        }
    }

    func Load(){
        RealmUtil.RealmBlock { (realm) -> Void in
            self.LoadCookiesFromRealmWith(realm: realm)
        }
    }
    
    // Realm から cookie を読み込んで shared な HTTPCookieStorage に書き込みます。
    func LoadCookiesFromRealmWith(realm:Realm) {
        guard let realmCookieArray = RealmGlobalState.GetInstanceWith(realm: realm)?.GetCookieArray() else { return }
        if let cookieStorage = URLSession.shared.configuration.httpCookieStorage {
            let sharedCookieArray = cookieStorage.cookies ?? []
            let newCookieArray = NiftyUtilitySwift.RemoveExpiredCookie(cookieArray: NiftyUtilitySwift.MergeCookieArray(currentCookieArray: sharedCookieArray, newCookieArray: realmCookieArray))
            NiftyUtilitySwift.AssignCookieArrayToCookieStorage(cookieArray: newCookieArray, cookieStorage: cookieStorage)
        }
    }
    func SaveCookiesFromCookieArrayWith(realm:Realm, cookieArray:[HTTPCookie]) {
        guard let globalState = RealmGlobalState.GetInstanceWith(realm: realm) else { return }
        globalState.MergeCookieArrayWith(realm: realm, cookieArray: cookieArray)
    }

    // URLSession.shared.configuration.httpCookieStorage に保存されている cookie を realm 側に保存します
    func SaveCookiesFromURLSessionSharedConfigurationWith(realm:Realm) {
        guard let sharedCookieArray = URLSession.shared.configuration.httpCookieStorage?.cookies else { return }
        SaveCookiesFromCookieArrayWith(realm: realm, cookieArray: sharedCookieArray)
    }
}
