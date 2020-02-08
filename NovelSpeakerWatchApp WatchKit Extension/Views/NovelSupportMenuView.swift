//
//  NovelSupportMenuView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/02/08.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

struct NovelSupportMenuView: View {
    let storyID:String
    @ObservedObject var viewData = NovelSupportMenuViewData()
    
    init(storyID:String) {
        self.storyID = storyID
        loadStoryData(storyID: storyID)
    }
    
    func loadStoryData(storyID:String) {
        DispatchQueue.main.async {
            guard let novel = RealmNovel.SearchNovelFrom(novelID: RealmStoryBulk.StoryIDToNovelID(storyID: storyID)) else { return }
            self.viewData.navigationBarTitle = novel.title
        }
    }
    
    var body: some View {
        ZStack {
            List{
                Button(action: {
                    // TODO: 後で書く
                }) {
                    Text(NSLocalizedString("WatchOS_NovelSupportMenuView_StorySelector", comment: "章を選択"))
                }
            }
            
        }.navigationBarTitle(viewData.navigationBarTitle)
    }
}

class NovelSupportMenuViewData:ObservableObject {
    @Published var navigationBarTitle = NSLocalizedString("WatchOS_NowloadingText", comment: "読込中……")
}

struct NovelSupportMenuView_Previews: PreviewProvider {
    static var previews: some View {
        NovelSupportMenuView(storyID: "")
    }
}
