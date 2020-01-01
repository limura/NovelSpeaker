//
//  ContentView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/01/01.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var contentData = ContentData()
    var body: some View {
        ScrollView { VStack {
            if contentData.isiCloudEnabled {
                ForEach(contentData.novelList, id: \.novelID) { novel in
                    NavigationLink(destination:
                        List {
                            Text("Title:")
                            Text(novel.title)
                            Text("OK")
                    }) {
                        Text(novel.title)
                    }
                }
            }else{
                Text(contentData.message)
            }
        } }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

class ContentData:ObservableObject {
    @Published var isiCloudEnabled:Bool = false
    @Published var message:String = "iCloudからのデータ共有を待っています……"
    @Published var novelList:[RealmNovel] = []

    init() {
        guard ((try? RealmUtil.EnableSyncEngine()) != nil) else { return }
        if let novelArray = RealmNovel.GetAllObjects(), novelArray.count > 1 {
            novelList = Array(novelArray)
            isiCloudEnabled = true
            return
        }
        DispatchQueue.global(qos: .background).async {
            self.CheckiCloudSync()
        }
    }
    
    func CheckiCloudSync() {
        RealmUtil.CheckCloudDataIsValid { (result) in
            guard result == true, let novels = RealmNovel.GetAllObjects() else { return }
             DispatchQueue.main.async {
                 self.novelList = Array(novels)
                 self.isiCloudEnabled = true
             }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.isiCloudEnabled { return }
            var count = 0
            if let realm = try? RealmUtil.GetRealm() {
                count = RealmUtil.CountAllCloudRealmRecords(realm: realm)
            }
            self.message = "count: \(count)"
        }
    }
}

