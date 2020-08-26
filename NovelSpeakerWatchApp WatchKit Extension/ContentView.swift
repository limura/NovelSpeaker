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
    @State var textDataArray:[String] = ["テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1", "テスト2-テスト2-テスト2-テスト2-テスト2-テスト2-テスト2-テスト2-テスト2", "テスト3", "テスト4", "テスト5", "テスト6", "テスト7", "テスト8", "テスト9", "テスト10", "テスト11", "テスト12"]

    init() {
        NovelSpeakerUtility.InsertDefaultSettingsIfNeeded()
        dummyStory.content = String(repeating: "吾輩は猫である。「名前はまだない。」しかし、そのうち名前がつけられると信じている。ところであなたは宇宙人を信じるだろうか？", count: 10)

        //StorySpeaker.shared.withMoreSplitTargets = ["。", "、", ".", ",", ":", "\n\n"]
        StorySpeaker.shared.withMoreSplitTargets = ["。", ".", "\n"]
        StorySpeaker.shared.moreSplitMinimumLetterCount = 30 // 40mm のタイプだと1行に11文字位表示できるぽいので3行だと30文字で切るのが良さげ？
        self.textDataArray = ["テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1-テスト1", "テスト2-テスト2-テスト2-テスト2-テスト2-テスト2-テスト2-テスト2-テスト2", "テスト3", "テスト4", "テスト5", "テスト6", "テスト7", "テスト8", "テスト9", "テスト10", "テスト11", "テスト12"]
    }
    
    func buttonClicked(parent:ScrollableVStack<String>) {
        if self.textDataArray.count % 3 == 0 {
            parent.ScrollToIndex(at: 1, isAnimationEnable: true)
            print("scroll to 0")
        }else{
            parent.ScrollToIndex(at: self.textDataArray.count - 1, isAnimationEnable: true)
            print("scroll to \(self.textDataArray.count - 1)")
        }
        self.textDataArray.append("New data \(self.textDataArray.count)")
    }

    var body: some View {
        Group {
            if viewData.currentPage == .neediCloudSync {
                ScrollableVStack<String>(data: self.textDataArray, converter: { content, parent -> AnyView in
                    AnyView(
                        Text(content)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture {
                            self.buttonClicked(parent: parent)
                        }
                    )
                })
                //CheckiCloudSyncView()
            }else if viewData.currentPage == .bookshelf {
                BookshelfView(novelList: self.viewData.novelList ?? [], viewData: self.viewData)
            }else {
                StoryView(story: self.viewData.speechTargetStory ?? Story(), viewData: self.viewData)
            }
        }
    }
    
    func GetContentText(novelID:String, chapterNumber:Int) -> String? {
        return RealmUtil.RealmBlock { (realm) -> String? in
            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber) else { return nil }
            StorySpeaker.shared.SetStory(realm: realm, story: story)
            return story.content
        }
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
                RealmUtil.RealmBlock { (realm) -> Void in
                    var story = Story()
                    story.content = self.speechText
                    StorySpeaker.shared.SetStory(realm: realm, story: story)
                    StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: false)
                }
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
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard let story = novel.readingChapterWith(realm: realm) else { return }
                    self.viewData.ShowStory(story: story)
                }
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
        if RealmUtil.RealmBlock(block: { (realm) -> Bool in
            if let novelArray = RealmNovel.GetAllObjectsWith(realm: realm), novelArray.count > 1 {
                novelList = Array(novelArray)
                currentPage = .bookshelf
                return true
            }
            return false
        }) {
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
                RealmUtil.RealmBlock { (realm) -> Void in
                    guard result == true, let novels = RealmNovel.GetAllObjectsWith(realm: realm), novels.count > 1 else { return }
                    self.ShowBookshelfView(novelList: Array(novels))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.currentPage != CurrentPageType.neediCloudSync { return }
            let count = RealmUtil.RealmBlock {
                return RealmUtil.CountAllCloudRealmRecords(realm: $0)
            }
        }
    }
    
    func ShowStory(story:Story) {
        ClearCachedData()
        speechTargetStory = story
        currentPage = .speech
    }
}

