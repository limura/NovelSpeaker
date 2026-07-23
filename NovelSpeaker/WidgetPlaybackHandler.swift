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
                        completion()
                    }
                }
                return
            }
            toggle()
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
}
