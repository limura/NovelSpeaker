//
//  SpeechContorlView.swift
//  NovelSpeakerWatchApp WatchKit Extension
//
//  Created by 飯村卓司 on 2020/02/08.
//  Copyright © 2020 IIMURA Takuji. All rights reserved.
//

import SwiftUI

struct SpeechContorlView: View {
    @ObservedObject var storyViewData = StoryViewData()
    
    init(storyViewData:StoryViewData) {
        self.storyViewData = storyViewData
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack {
                SystemIconButtonView(systemIconName: "backward.end.fill", iconSize: CGFloat(geometry.size.width / 7)) {
                    let speaker = StorySpeaker.shared
                    let isPlaying = speaker.isPlayng
                    self.storyViewData.setLoadingIndicator(isVisible: true)
                    RealmUtil.RealmBlock { (realm) -> Void in
                        speaker.StopSpeech(realm: realm)
                    }
                    DispatchQueue.global(qos: .background).async {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            speaker.LoadPreviousChapter(realm: realm, completion: { (result) in
                                if result && isPlaying {
                                    speaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                                }
                            })
                        }
                        self.storyViewData.setLoadingIndicator(isVisible: false)
                    }
                }
                Spacer()
                SystemIconButtonView(systemIconName: "gobackward.30", iconSize: CGFloat(geometry.size.width / 7)) {
                    let speaker = StorySpeaker.shared
                    let isPlaying = speaker.isPlayng
                    self.storyViewData.setLoadingIndicator(isVisible: true)
                    RealmUtil.RealmBlock { (realm) -> Void in
                        speaker.StopSpeech(realm: realm) {
                            RealmUtil.RealmBlock { (realm) -> Void in
                                speaker.SkipBackward(realm: realm, length: 30) {
                                    if isPlaying {
                                        speaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                                    }else{
                                        self.storyViewData.displayIndex = speaker.currentBlockIndex
                                    }
                                    self.storyViewData.setLoadingIndicator(isVisible: false)
                                }
                            }
                        }
                    }
                    if isPlaying != true {
                        self.storyViewData.setLoadingIndicator(isVisible: false)
                    }
                }
                Spacer()
                Button(action: {
                    let speaker = StorySpeaker.shared
                    RealmUtil.RealmBlock { (realm) -> Void in
                        if speaker.isPlayng {
                            speaker.StopSpeech(realm: realm)
                        }else{
                            speaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                        }
                    }
                }) {
                    if self.storyViewData.isSpeaking {
                        Image(systemName: "stop.circle")
                        .resizable()
                        .frame(width: geometry.size.width / 6, height: geometry.size.width / 6, alignment: .trailing)
                        .background(Color.black)
                    }else{
                        Image(systemName: "play.circle")
                        .resizable()
                        .frame(width: geometry.size.width / 6, height: geometry.size.width / 6, alignment: .trailing)
                    }
                }
                .frame(width: geometry.size.width / 6, height: geometry.size.width / 6, alignment: .leading)
                Spacer()
                SystemIconButtonView(systemIconName: "goforward.30", iconSize: CGFloat(geometry.size.width / 7)) {
                    let speaker = StorySpeaker.shared
                    let isPlaying = speaker.isPlayng
                    self.storyViewData.setLoadingIndicator(isVisible: true)
                    RealmUtil.RealmBlock { (realm) -> Void in
                        speaker.StopSpeech(realm: realm) {
                            RealmUtil.RealmBlock { (realm) -> Void in
                                speaker.SkipForward(realm: realm, length: 30) {
                                    if isPlaying {
                                        speaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                                    }else{
                                        self.storyViewData.displayIndex = speaker.currentBlockIndex
                                    }
                                    self.storyViewData.setLoadingIndicator(isVisible: false)
                                }
                            }
                        }
                    }
                    if isPlaying != true {
                        self.storyViewData.setLoadingIndicator(isVisible: false)
                    }
                }
                Spacer()
                SystemIconButtonView(systemIconName: "forward.end.fill", iconSize: CGFloat(geometry.size.width / 7)) {
                    let speaker = StorySpeaker.shared
                    let isPlaying = speaker.isPlayng
                    self.storyViewData.setLoadingIndicator(isVisible: true)
                    RealmUtil.RealmBlock { (realm) -> Void in
                        speaker.StopSpeech(realm: realm)
                    }
                    DispatchQueue.global(qos: .background).async {
                        RealmUtil.RealmBlock { (realm) -> Void in
                            speaker.LoadNextChapter(realm: realm) { (result) in
                                if result && isPlaying {
                                    speaker.StartSpeech(realm: realm, withMaxSpeechTimeReset: true)
                                }
                            }
                        }
                        self.storyViewData.setLoadingIndicator(isVisible: false)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.width / 6, alignment: .bottomLeading)
        }.frame(minWidth: 100, idealWidth: 210, maxWidth: .infinity, minHeight: 25, idealHeight: 40, maxHeight: 45, alignment: .bottomLeading)
        .background(Color.black.opacity(0.7))
    }
}


struct SpeechContorlView_Previews: PreviewProvider {
    static var previews: some View {
        SpeechContorlView(storyViewData: StoryViewData())
    }
}
