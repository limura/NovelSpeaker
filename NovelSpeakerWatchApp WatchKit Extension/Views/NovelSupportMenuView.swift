//
//  NovelSupportMenuView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/02/08.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

enum NovelSupportMenuSubViewState {
    case Normal
    case StorySelect
    case VolumeControl
}

struct VolumeControlView: View {
    @ObservedObject var viewData:NovelSupportMenuViewData

    init(viewData:NovelSupportMenuViewData) {
        self.viewData = viewData
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
            SystemIconButtonView(systemIconName: "chevron.left.circle.fill", iconSize: CGFloat(20), foregroundColor: Color.blue.opacity(0.7)) {
                self.viewData.viewState = .Normal
            }
            WKInterfaceVolumeControlView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(viewData.viewState == .VolumeControl ? 1 : 0)
        }
        .opacity(viewData.viewState == .VolumeControl ? 1 : 0)
    }
}

struct StorySelectorView: View {
    let storyViewData:StoryViewData
    let novelID:String
    @ObservedObject var viewData:NovelSupportMenuViewData

    init(viewData:NovelSupportMenuViewData, storyViewData:StoryViewData) {
        self.viewData = viewData
        self.storyViewData = storyViewData
        self.novelID = RealmStoryBulk.StoryIDToNovelID(storyID: storyViewData.storyID)
    }
    static func GenerateTitleAndIndexArray(storyArray:[Story]) -> [String] {
        var result:[String] = []
        for (index, story) in storyArray.enumerated() {
            result.append("\(index):\(story.subtitle)")
        }
        return result
    }
    static func TitleAndIndexToTitle(titleAndIndex:String) -> String {
        guard let range = titleAndIndex.range(of: ":"), range.upperBound < titleAndIndex.endIndex else { return "" }
        let result = titleAndIndex[range.upperBound..<titleAndIndex.endIndex]
        return String(result)
    }
    static func TitleAndIndexToIndex(titleAndIndex:String) -> Int {
        let components = titleAndIndex.components(separatedBy: ":")
        guard components.count > 0 else { return 0 }
        return Int(components[0]) ?? 0
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            List(viewData.titleAndIndexArray, id: \.self) { (titleAndIndex) -> Button<Text> in
                Button(action: {
                    let index = StorySelectorView.TitleAndIndexToIndex(titleAndIndex: titleAndIndex)
                    DispatchQueue.main.async {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            guard let story = RealmStoryBulk.SearchStoryWith(realm: realm, storyID: RealmStoryBulk.CreateUniqueID(novelID: self.novelID, chapterNumber: index)) else { return }
                            StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true)
                            self.storyViewData.isSupportMenuVisible = false
                        }
                    }
                }) {
                    Text(StorySelectorView.TitleAndIndexToTitle(titleAndIndex: titleAndIndex))
                }
            }
            SystemIconButtonView(systemIconName: "chevron.left.circle.fill", iconSize: CGFloat(20), foregroundColor: Color.blue.opacity(0.7)) {
                self.viewData.viewState = .Normal
            }
        }
    }
}


struct NovelSupportMenuView: View {
    let storyViewData:StoryViewData
    @ObservedObject var viewData = NovelSupportMenuViewData()
    
    init(storyViewData:StoryViewData) {
        self.storyViewData = storyViewData
        loadStoryData(storyID: storyViewData.storyID)
    }
    
    func loadStoryData(storyID:String) {
        DispatchQueue.main.async {
            RealmUtil.RealmBlock { (realm) -> Void in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID)) else { return }
                self.viewData.navigationBarTitle = novel.title
            }
        }
    }
    
    var body: some View {
        ZStack {
            List{
                Button(action: {
                    DispatchQueue.main.async {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            var titleAndIndexArray:[String] = []
                            RealmStoryBulk.SearchAllStoryFor(realm: realm, novelID: RealmStoryBulk.StoryIDToNovelID(storyID: self.storyViewData.storyID), filterFunc: nil) { (story) in
                                titleAndIndexArray.append("\(story.chapterNumber):\(story.subtitle)")
                            }
                            self.viewData.titleAndIndexArray = titleAndIndexArray
                            self.viewData.viewState = .StorySelect
                        }
                    }
                }) {
                    Text(NSLocalizedString("WatchOS_NovelSupportMenuView_StorySelector", comment: "章を選択"))
                }
                .disabled(storyViewData.storyID == "")
                Button(action: {
                    self.viewData.viewState = .VolumeControl
                }) {
                    Text(NSLocalizedString("WatchOS_NovelSupportMenuView_VolumeControl", comment: "音量調整"))
                }
                Button(action: {
                    self.storyViewData.isSupportMenuVisible = false
                }) {
                    Text(NSLocalizedString("Cancel_button", comment: "キャンセル"))
                }
            }
            StorySelectorView(viewData: viewData, storyViewData: storyViewData)
            .opacity(viewData.viewState == .StorySelect ? 1 : 0)
            VolumeControlView(viewData: viewData)
            .opacity(viewData.viewState == .VolumeControl ? 1 : 0)
        }.navigationBarTitle(viewData.navigationBarTitle)
    }
}

class NovelSupportMenuViewData:ObservableObject {
    @Published var navigationBarTitle = NSLocalizedString("WatchOS_NowloadingText", comment: "読込中……")
    @Published var viewState = NovelSupportMenuSubViewState.Normal
    @Published var titleAndIndexArray:[String] = []
}

struct NovelSupportMenuView_Previews: PreviewProvider {
    static var previews: some View {
        NovelSupportMenuView(storyViewData: StoryViewData())
    }
}
