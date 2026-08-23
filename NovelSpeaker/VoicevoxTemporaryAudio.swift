//
//  VoicevoxTemporaryAudio.swift
//  NovelSpeaker
//
//  読み上げ中に作った音声(一時分)の後始末。
//
//  VOICEVOX の音声は2種類ある。
//   - 事前生成音声: 利用者が「作って」と言った分。消えない。
//   - 一時分       : 読み上げ中に足りなくなって作った分。自動で消える。
//
//  一時分を持つのは、実時間で合成しきれない端末(iPhone SE2 等)で
//  無音を減らすため。合成した物をメモリだけに置くと 16MB(約6分)で頭打ちになり、
//  「読み上げ中に作り足す下限」を15分に設定しても届かない。
//  ファイルに置けば設定どおりに先まで作れる。
//
//  代わりに、断りなくストレージが増え続けない事を保証する必要がある。
//  そこで消す条件を3つに絞ってある:
//   1. 新しい方から「残す時間」ぶんだけ残し、古い物から捨てる
//   2. 別の小説の読み上げが始まったら、その小説以外の一時分を捨てる
//   3. 容量の上限は事前生成音声と合算で見る(別枠にすると合計が分からなくなる)
//

import Foundation

#if !os(watchOS)
enum VoicevoxTemporaryAudio {

    /// 再生位置より後ろに残しておく時間(分)。
    ///
    /// 「少し戻る」や寝落ちからの巻き戻しで、作り直しを避けるためのもの。
    /// 固定値にしないのは、聴き方(巻き戻す癖・寝落ちの頻度)で適切な長さが変わるため。
    static let defaultKeepBehindMinutes = 10
    static let keepBehindMinutesUserDefaultsKey = "NovelSpeaker.Voicevox.temporaryKeepBehindMinutes"

    static var keepBehindMinutes: Int {
        get {
            guard let stored = UserDefaults.standard.object(forKey: keepBehindMinutesUserDefaultsKey) as? Int else {
                return defaultKeepBehindMinutes
            }
            return max(0, stored)
        }
        set { UserDefaults.standard.set(max(0, newValue), forKey: keepBehindMinutesUserDefaultsKey) }
    }

    /// 一時分として持っておいてよい音声の長さ。
    ///
    /// 後ろに残す分 + 先へ作り足す分。前者は巻き戻し用、後者は無音を避けるための貯金で、
    /// どちらも既にある設定なので、**ここに新しい設定値は作らない**
    /// (別に作ると「結局いくつ使うのか」が利用者に分からなくなる)。
    static func budgetSeconds() -> Double {
        let behind = Double(keepBehindMinutes) * 60
        let ahead = Double(VoicevoxCacheLead.keepGeneratingBelowMinutes) * 60
        // 作り足しを使わない設定(0分)でも、今読んでいる所の前後は残しておきたい。
        return max(behind + ahead, 60)
    }

    /// 一時分が増え過ぎていたら、再生位置から遠い方を捨てる。
    ///
    /// 今どこを読んでいるかを必ず渡す事。渡さないと更新時刻の古い順に消える形に落ち、
    /// 「次に鳴らす1本」を消しては作り直す堂々巡りに戻る(VoicevoxCacheChurnTest 参照)。
    static func trimIfNeeded(novelID: String, playbackChapterNumber: Int? = nil) {
        let chapterNumber = playbackChapterNumber
            ?? VoicevoxCore.shared.diskCacheContext.flatMap { $0.novelID == novelID ? $0.chapterNumber : nil }
        VoicevoxDiskCacheStore.shared.trimTemporary(novelID: novelID,
                                                    keepingSeconds: budgetSeconds(),
                                                    playbackChapterNumber: chapterNumber)
    }

    /// ★読み上げる小説が変わった時に呼ぶ。他の小説の一時分を捨てる。
    ///
    /// 「開いた時」ではなく「読み上げが始まった時」に呼ぶこと。
    /// 開いただけ(目次を見た・本文を確かめた)で消すと、
    /// 戻ってきた時に作り直しになる。
    static func handlePlaybackStarted(novelID: String) {
        let freed = VoicevoxDiskCacheStore.shared.removeTemporary(exceptNovelID: novelID)
        if freed > 0 {
            AppInformationLogger.AddLog(
                message: "[VOICEVOX音声生成] 別の小説を読み始めたので、前の小説の一時分を片付けました"
                    + "(\(freed / 1024 / 1024)MB)",
                isForDebug: true)
        }
        trimIfNeeded(novelID: novelID)
    }
}
#endif
