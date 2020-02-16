//
//  ContentView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/01/01.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI
import AVFoundation

enum CurrentPageType {
    case neediCloudSync
    case bookshelf
    case speech
}

struct ContentView: View {
    @ObservedObject var viewData = ViewData()
    var dummyStory = Story()

    init() {
        NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
        dummyStory.content = String(repeating: "吾輩は猫である。「名前はまだない。」しかし、そのうち名前がつけられると信じている。ところであなたは宇宙人を信じるだろうか？", count: 10)

        //StorySpeaker.shared.withMoreSplitTargets = ["。", "、", ".", ",", ":", "\n\n"]
        StorySpeaker.shared.withMoreSplitTargets = ["。", ".", "\n"]
        StorySpeaker.shared.moreSplitMinimumLetterCount = 30 // 40mm のタイプだと1行に11文字位表示できるぽいので3行だと30文字で切るのが良さげ？
    }

    var body: some View {
        Group {
            if viewData.currentPage == .neediCloudSync {
                CheckiCloudSyncView()
            }else if viewData.currentPage == .bookshelf {
                BookshelfView(novelList: self.viewData.novelList ?? [], viewData: self.viewData)
            }else {
                StoryView(story: self.viewData.speechTargetStory ?? Story(), viewData: self.viewData)
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

class SpeechDelegateTest: NSObject, AVSpeechSynthesizerDelegate {
    let synthe = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthe.delegate = self
    }
    
    func speak(utt:AVSpeechUtterance) {
        synthe.speak(utt)
    }
}

struct CheckiCloudSyncView: View {
    let speechText = String(repeating: "こんにちは世界", count: 1)
    let delegateInstance = SpeechDelegateTest()
    var body: some View {
        List {
            Text("iCloudからのデータ共有を待っています……\nAppleWatchで ことせかい を使う場合、親機にあたる iPhone等 の ことせかい で本棚に小説を一つ以上登録する必要があります。\nまた、大量の本を本棚に登録している場合、同期が完了するまでにかなりの時間を要する可能性があります。")
            Button<Text>(action: {
                //let synthe = AVSpeechSynthesizer()
                let utt = AVSpeechUtterance(string: self.speechText)
                utt.voice = AVSpeechSynthesisVoice(language: "ja-JP")
                self.delegateInstance.speak(utt: utt)
            }) {
                Text("speech")
            }
            Button<Text>(action: {
                let speaker = Speaker()
                speaker.Speech(text: self.speechText)
            }) {
                Text("Speech(Speaker)")
            }
            Button<Text>(action: {
                var story = Story()
                story.content = self.speechText
                StorySpeaker.shared.SetStory(story: story)
                StorySpeaker.shared.StartSpeech(withMaxSpeechTimeReset: false)
            }) {
                Text("speech(StorySpeaker)")
            }
            Button<Text>(action: {
                let nowPlaying = URL(fileURLWithPath: "nowplaying:///")
                WKExtension.shared().openSystemURL(nowPlaying)
            }) {
                Text("Open(NowPlaying)")
            }
            Button<Text>(action: {
                let nowPlaying = URL(fileURLWithPath: "sms:1234567")
                WKExtension.shared().openSystemURL(nowPlaying)
            }) {
                Text("Open(sms)")
            }
        }
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
        List(bookshelfData) { (novel:RealmNovel) in
            Button<Text>(action: {
                guard let story = novel.readingChapter else { return }
                self.viewData.ShowStory(story: story)
            }) {
                Text(novel.title)
            }
        }
/*
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
 */
    }
}

/*
class BookshelfData:ObservableObject {
    @Published var novelList:[RealmNovel] = []
    init(novelList:[RealmNovel]) {
        self.novelList = novelList
    }
}*/

class BookshelfData: ObservableObject, RandomAccessCollection {
    typealias Element = RealmNovel
    
    @Published var novelList = [RealmNovel]()
    
    var startIndex: Int { novelList.startIndex }
    var endIndex: Int { novelList.endIndex }
    
    init(novelList:[RealmNovel]) {
        self.novelList = novelList
    }
    
    subscript(position: Int) -> RealmNovel {
        return novelList[position]
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
        DispatchQueue.main.async {
            RealmUtil.CheckCloudDataIsValid { (result) in
                guard result == true, let novels = RealmNovel.GetAllObjects(), novels.count > 1 else { return }
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

