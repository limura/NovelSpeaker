//
//  WidgetPlaybackHandler.swift
//  NovelSpeaker
//
//  iPhone側ウィジェット(ホーム画面/ロック画面/コントロールセンター)からの操作を
//  アプリ本体プロセスで実行する。AudioPlaybackIntent の perform() は iOS では
//  アプリ本体プロセスで実行される(PoC/WidgetSpeechPoC で実機実証済み)ので、
//  WatchSessionCoordinator と同様にアプリ内の StorySpeaker を直接叩けばよい。
//

import Foundation

class WidgetPlaybackHandler {
    /// ウィジェットからの「再生・停止」(PhoneSpeechToggleIntent.perform() から呼ばれる)
    static func togglePlayPauseFromWidget() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            togglePlayPause {
                continuation.resume()
            }
        }
    }

    /// WCSession の背面起動と同様、ウィジェットからのバックグラウンド起動直後は小説が
    /// 未セットなので、前回読んでいた小説をセットしてから実行する
    /// (WatchSessionCoordinator.handleCommand の commandsNeedingStory と同じ流儀)
    private static func togglePlayPause(completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            if StorySpeaker.shared.storyID.isEmpty {
                let story = RealmUtil.RealmBlock { realm -> Story? in
                    return RealmGlobalState.GetLastReadStory(realm: realm)
                }
                guard let story = story else {
                    completion()
                    return
                }
                StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { _ in
                    DispatchQueue.main.async {
                        toggle()
                        PhoneWidgetDataUpdater.update()
                        completion()
                    }
                }
                return
            }
            toggle()
            PhoneWidgetDataUpdater.update()
            completion()
        }
    }

    /// togglePlayPauseEvent() を使わず isNeedRepeatSpeech: true を明示する理由は
    /// WatchSessionCoordinator.executeCommand(.togglePlayPause) と同じ
    /// (背面起動直後は false のままで、章末で次章へ進まず止まってしまう)
    private static func toggle() {
        RealmUtil.RealmBlock { realm in
            if StorySpeaker.shared.isPlayng {
                StorySpeaker.shared.StopSpeech(realm: realm, stopAudioSession: true)
            } else {
                StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "iPhoneウィジェットからの再生・停止.\(#function)", isNeedRepeatSpeech: true)
            }
        }
    }

    /// ウィジェットからの「指定小説の再生を開始」(PhonePlayNovelIntent.perform() から呼ばれる)。
    /// WatchSessionCoordinator.openNovel(thenPlay: true) と同じ流儀:
    /// 栞の章を SetStory してから再生を開始する(SetStory は内部で現在の発話を止めるので、
    /// 別の小説を再生中でも対象の小説に切り替わる)
    static func playNovelFromWidget(novelID: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playNovel(novelID: novelID) {
                continuation.resume()
            }
        }
    }

    private static func playNovel(novelID: String, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            let story = RealmUtil.RealmBlock { realm -> Story? in
                guard let novel = RealmNovel.SearchNovelWith(realm: realm, novelID: novelID) else { return nil }
                let chapterNumber = novel.readingChapterNumber ?? 1
                return RealmStoryBulk.SearchStoryWith(realm: realm, novelID: novelID, chapterNumber: chapterNumber)
            }
            guard let story = story else {
                completion()
                return
            }
            StorySpeaker.shared.SetStory(story: story, withUpdateReadDate: true) { _ in
                DispatchQueue.main.async {
                    if !StorySpeaker.shared.isPlayng {
                        RealmUtil.RealmBlock { realm in
                            StorySpeaker.shared.StartSpeech(realm: realm, withMaxSpeechTimeReset: true, callerInfo: "iPhoneウィジェットからの指定小説再生.\(#function)", isNeedRepeatSpeech: true)
                        }
                    }
                    PhoneWidgetDataUpdater.update()
                    completion()
                }
            }
        }
    }
}
