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
 
 追記:
 
 以前の ことせかい(Version 1.1.*) では cookie をリクエストヘッダに追加する形で実装しており、
 そのデータは JavaScript で document.cookie として取り出した文字列そのものであった。
 これは HTTPCookie の保持する情報の一部しか入っていない(domain, path, expire date が無い)ため、
 正確な HTTPCookie に還元することができない。
 (なお、Safariからの取り込みの場合、アプリ側からはSafari側の cookieStorage を参照する事ができないため、
 Safariの上でJavaScriptを動作させてdocument.cookieを参照し、
 それが含まれたlinkとしてnovelspeaker://downloadurl/...
 を開こうとすることでcookie情報を渡しており、これが問題を発生させている。
 なお、Web取込タブにおいても同様の仕組みを導入していたが、
 今回WkWebView側のcookieStorageを参照するようにすることでこれを回避している。
 ただ、WkWebView側のcookieStorageの参照は iOS 11 以降でないとできないため、
 iOS 10 では以前と同様のJavaScriptからの参照に留まっているため、iOS 10 では同様の問題が発生する)
 また、リクエストヘッダに追加する形という事は、実際の cookieStorage には保存していないという動作をしていた。
 だたし、最初に取得された document.cookie をいつまでも覚えており、それをHTTP Headerに再現して送信する、
 という動作をすることになっていたため、
 一部の Webサイト ではなんとなく動いてしまっていた(当然それでは動かないWebサイトもあった)。
 さて、このイケていない cookie の取り扱いをどうするべきであろうか。
 
 案1:
 JavaScript側で取得した値を以前と同様に保存しておき、以前と同様に毎回 HTTP Headerに再現して送信する。
 
 案2:
 正確な HTTPCookie として還元できない情報しか得られなかった場合、
 Web取込ページで開き直す事でそちらでログイン等の手続きをとってもらい、
 そこから受け取れるようになった HTTPCookie を保存する。
 
 案1はcookieの動作としては「よろしくない」ため、採用したくない。
 案2はSafariからの取り込み操作がほぼ無意味になるのでこれはこれであまり採用したくない。
 という事で、
 
 案3:
 正確な HTTPCookie として還元できない情報しか得られなかった場合、
 cookieを設定しないで取得した情報で十分であればそれを採用し、
 駄目そうであればWeb取込ページで開き直す事でログイン等の手続きをとってもらい、
 そこから受け取れるようになった HTTPCookie を保存する。
 
 ……というのが良い？かな？
 cookieなくても取得できるWebサイト(か、既にアプリ側が保持しているcookieで取得できるWebサイト)の場合は
 今までの Safariからの取り込み と同様の操作で取得できるし、
 そうでない場合はWeb取込タブ側でログインの手続きをとってもらう事になるため、
 より正しいcookieが保存できる。
 
 という事で、そのように実装する事にする。
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
