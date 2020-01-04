//
//  ContentView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/01/01.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

enum CurrentPageType {
    case neediCloudSync
    case bookshelf
    case speech
}

struct ContentView: View {
    @ObservedObject var viewData = ViewData()
    var body: some View {
        VStack {
            if viewData.currentPage == .neediCloudSync {
                autoreleasepool {
                    CheckiCloudSyncView()
                }
            }else if viewData.currentPage == .bookshelf {
                autoreleasepool {
                    BookshelfView(novelList: self.viewData.novelList ?? [], viewData: self.viewData)
                }
            }else {
                autoreleasepool {
                    StoryView(story: self.viewData.speechTargetStory ?? Story(), viewData: self.viewData)
                }
            }
        }
    }
    
    func GetContentText(novelID:String, chapterNumber:Int) -> String? {
        guard let story = RealmStoryBulk.SearchStory(novelID: novelID, chapterNumber: chapterNumber) else { return nil }
        StorySpeaker.shared.SetStory(story: story)
        return story.content
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct CheckiCloudSyncView: View {
    var body: some View {
        Text("iCloudからのデータ共有を待っています……")
    }
}

struct BookshelfView: View {
    @ObservedObject var bookshelfData = BookshelfData(novelList: [])
    let viewData:ViewData
    init(novelList:[RealmNovel], viewData:ViewData) {
        self.bookshelfData = BookshelfData(novelList: novelList)
        self.viewData = viewData
    }
    
    var body: some View {
        ScrollView { VStack {
            ForEach(self.bookshelfData.novelList, id: \.self) { novel in
                Button<Text>(action: {
                    print("tap: \(novel.title)")
                    guard let story = novel.readingChapter else { return }
                    self.viewData.ShowStory(story: story)
                }) {
                    Text(novel.title)
                }
            }
        } }
    }
}

class BookshelfData:ObservableObject {
    @Published var novelList:[RealmNovel] = []
    init(novelList:[RealmNovel]) {
        self.novelList = novelList
    }
}

struct StoryView: View {
    let story:Story
    let viewData:ViewData
    init(story:Story, viewData:ViewData) {
        self.story = story
        self.viewData = viewData
        StorySpeaker.shared.SetStory(story: story)
    }
    
    var body: some View {
        ScrollView { VStack {
            Button<Text>(action: {
                print("Speech button clicked.")
                StorySpeaker.shared.StartSpeech(withMaxSpeechTimeReset: false)
            }) {
                Text("Speech")
            }
            Button<Text>(action: {
                print("Stop button clicked.")
                StorySpeaker.shared.StopSpeech()
            }) {
                Text("Stop")
            }
            Button<Text>(action: {
                print("Back button clicked.")
                guard let novelList = RealmNovel.GetAllObjects() else { return }
                self.viewData.ShowBookshelfView(novelList: Array(novelList))
            }) {
                Text("Back")
            }
            Text(self.story.content)
        } }
    }
}

class ViewData:ObservableObject {
    @Published var currentPage = CurrentPageType.neediCloudSync
    var novelList:[RealmNovel]? = nil
    var speechTargetStory:Story? = nil

    init() {
        guard ((try? RealmUtil.EnableSyncEngine()) != nil) else { return }
        if let novelArray = RealmNovel.GetAllObjects(), novelArray.count > 1 {
            novelList = Array(novelArray)
            currentPage = .bookshelf
            return
        }
        DispatchQueue.global(qos: .background).async {
            self.CheckiCloudSync()
        }
    }
    
    func ClearCachedData() {
        self.novelList = nil
        self.speechTargetStory = nil
    }
    
    func ShowBookshelfView(novelList:[RealmNovel]) {
        ClearCachedData()
        self.novelList = novelList
        currentPage = .bookshelf
    }
    
    func CheckiCloudSync() {
        RealmUtil.CheckCloudDataIsValid { (result) in
            guard result == true, let novels = RealmNovel.GetAllObjects() else { return }
             DispatchQueue.main.async {
                self.ShowBookshelfView(novelList: Array(novels))
             }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.currentPage != CurrentPageType.neediCloudSync { return }
            var count = 0
            if let realm = try? RealmUtil.GetRealm() {
                count = RealmUtil.CountAllCloudRealmRecords(realm: realm)
            }
        }
    }
    
    func ShowStory(story:Story) {
        ClearCachedData()
        speechTargetStory = story
        currentPage = .speech
    }
}

