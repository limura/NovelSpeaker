//
//  StoryView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/02/07.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

struct StoryView: View {
    @ObservedObject var storyViewData = StoryViewData()
    let viewData:ViewData
    init(story:Story, viewData:ViewData) {
        self.viewData = viewData
        storyViewData.SetCurrentStory(story: story)
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            VStack {
                List(storyViewData.combinedBlockArray) { block in
                    Text(block.displayText)
                }
                SpeechContorlView(storyViewData: storyViewData)
            }
            VStack {
                HStack {
                    SystemIconButtonView(systemIconName: "chevron.left.circle.fill", iconSize: CGFloat(20), foregroundColor: Color.blue.opacity(0.7)) {
                        StorySpeaker.shared.StopSpeech()
                        guard let novelList = RealmNovel.GetAllObjects() else { return }
                        self.viewData.ShowBookshelfView(novelList: Array(novelList))
                    }
                    Spacer()
                    SystemIconButtonView(systemIconName: "ellipsis.circle.fill", iconSize: CGFloat(20), foregroundColor: Color.white.opacity(0.7)) {
                        // TODO: 後で追加する。 viewData に NovelSupportMenuView を表示するように頼む。
                    }
                }
                Spacer()
            }
            NovelSupportMenuView(storyViewData: self.storyViewData)
            Text(NSLocalizedString("WatchOS_NowloadingText", comment: "読込中……"))
            .font(.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color.black)
            .opacity(self.storyViewData.isLoadingIndicatorVisible ? 1 : 0)
        }
        .navigationBarTitle(self.storyViewData.titleText)
        .edgesIgnoringSafeArea(.bottom)
        .gesture(
            DragGesture()
            .onEnded({ (gestureValue) in
                print("\(gestureValue.startLocation.x),\(gestureValue.startLocation.y) -> \(gestureValue.location.x),\(gestureValue.location.y)")
            })
        )
    }
}

class StoryViewData:ObservableObject,StorySpeakerDeletgate {
    @Published var titleText = NSLocalizedString("Watch_OS_StoryViewData_NowloadingText", comment: "読込中……")
    @Published var isSpeaking = StorySpeaker.shared.isPlayng
    
    @Published var combinedBlockArray:[CombinedSpeechBlock] = [
        CombinedSpeechBlock(block: SpeechBlockInfo(speechText: NSLocalizedString("WatchOS_NowloadingText", comment: "読込中……"), displayText: NSLocalizedString("WatchOS_NowloadingText", comment: "読込中……"), voice: nil, pitch: 1.0, rate: 1.0, delay: 0.0))
    ]
    @Published var displayIndex:Int = 0
    @Published var isLoadingIndicatorVisible = false
    @Published var isSupportMenuVisible = false
    @Published var storyID = ""
    
    init() {
        StorySpeaker.shared.AddDelegate(delegate: self)
    }
    deinit {
        StorySpeaker.shared.RemoveDelegate(delegate: self)
    }
    
    func SetCurrentStory(story:Story) {
        storyID = story.storyID
        DispatchQueue.main.async {
            StorySpeaker.shared.SetStory(story: story)
            self.combinedBlockArray = StorySpeaker.shared.speechBlockArray
            if let novel = story.ownerNovel {
                self.realoadTitleText(title: novel.title)
            }
        }
    }
    
    func realoadTitleText(title:String) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            self.titleText = title
        }
    }
    func storySpeakerStartSpeechEvent(storyID:String) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            self.isSpeaking = true
        }
    }
    func storySpeakerStopSpeechEvent(storyID:String) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            self.isSpeaking = false
        }
    }
    func storySpeakerUpdateReadingPoint(storyID:String, range:NSRange) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            self.displayIndex = StorySpeaker.shared.currentBlockIndex
        }
    }
    func storySpeakerStoryChanged(story:Story) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            self.displayIndex = 0
            self.combinedBlockArray = StorySpeaker.shared.speechBlockArray
            self.displayIndex = StorySpeaker.shared.currentBlockIndex
            self.storyID = story.storyID
        }
    }
    func setLoadingIndicator(isVisible:Bool) {
        NiftyUtilitySwift.DispatchSyncMainQueue {
            self.isLoadingIndicatorVisible = isVisible
        }
    }
}

struct StoryView_Previews: PreviewProvider {
    static var previews: some View {
        var story = Story()
        story.content = """
        　吾輩は猫である。名前はまだ無い。
        　どこで生れたかとんと見当けんとうがつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。吾輩はここで始めて人間というものを見た。しかもあとで聞くとそれは書生という人間中で一番獰悪どうあくな種族であったそうだ。この書生というのは時々我々を捕つかまえて煮にて食うという話である。しかしその当時は何という考もなかったから別段恐しいとも思わなかった。ただ彼の掌てのひらに載せられてスーと持ち上げられた時何だかフワフワした感じがあったばかりである。掌の上で少し落ちついて書生の顔を見たのがいわゆる人間というものの見始みはじめであろう。この時妙なものだと思った感じが今でも残っている。第一毛をもって装飾されべきはずの顔がつるつるしてまるで薬缶やかんだ。その後ご猫にもだいぶ逢あったがこんな片輪かたわには一度も出会でくわした事がない。のみならず顔の真中があまりに突起している。そうしてその穴の中から時々ぷうぷうと煙けむりを吹く。どうも咽むせぽくて実に弱った。これが人間の飲む煙草たばこというものである事はようやくこの頃知った。
        """
        let viewData = ViewData()
        return StoryView(story: story, viewData: viewData)
    }
}
